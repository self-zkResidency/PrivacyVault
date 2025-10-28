// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SelfVerificationRoot} from "@selfxyz/contracts/abstract/SelfVerificationRoot.sol";
import {ISelfVerificationRoot} from "@selfxyz/contracts/interfaces/ISelfVerificationRoot.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/interfaces/IIdentityVerificationHubV2.sol";
import {SelfStructs} from "@selfxyz/contracts/libraries/SelfStructs.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";
import {CountryCodes} from "@selfxyz/contracts/libraries/CountryCode.sol";

/**
 * @title PrivacyVault (non-custodial, audit-friendly, Nightfall-oriented)
 * @notice MVP: valida prueba de Self (edad/país/OFAC) y registra intención de depósito
 *         + ancla recibo de Nightfall. No custodia tokens.
 *
 *  1) verifyUser(proofPayload, userCtx) -> Self valida y llama customVerificationHook
 *  2) executeDeposit() -> checks (anti-replay/OFAC), emit DepositIntent and eligibility
 *  3) backend:
 *       - issue X.509 (CA own) and register in Nightfall X509.sol (via /v1/certification)
 *       - call /v1/deposit (NF Client) with X-Request-ID = uuid
 *       - when NF confirms (webhook), call attestNightfallDeposit()
 *
 * Nota: userData = abi.encode(depositor, amount, uuid, travelRuleHash)
 */
contract PrivacyVault is SelfVerificationRoot, Ownable {
  
    enum Role {
        Unknown,
        Payer,
        Receiver
    }

    enum IntentStatus {
        None,
        Emitted,      // DepositIntent emitted (before NF deposit/transfer)
        NFCommitted,  // Nightfall deposit/transfer confirmed (receipt anchored)
        UnlockAuth    // Receiver authorized withdrawal (optional, if you apply withdrawal gating)
    }

    struct PendingVerification {
        // Buffer by caller or by uuid (see pendingByUuid)
        bool exists;
        Role role;
        ISelfVerificationRoot.GenericDiscloseOutputV2 output;
        bytes userData; // encoding according to role
    }

    struct Intent {
        address payer;
        address receiver;
        uint256 amount;
        bytes32 travelRuleHash;
        uint256 nullifier;     // of the payer (Self verification)
        uint64  createdAt;
        IntentStatus status;
    }

    SelfStructs.VerificationConfigV2 public verificationConfig;
    bytes32 public verificationConfigId;

    /// @notice used nullifiers (to avoid double verification)
    mapping(uint256 => bool) public usedNullifier;

    uint64 public eligibilityWindow = 3 days;
    /// Temporal eligibility marker (e.g. for NF deposits by 30d)
    mapping(address => uint64) public eligibleUntil;
    mapping(address => PendingVerification) private pendingByCaller;
    mapping(bytes16 => PendingVerification) private pendingByUuid;

    // intents and receiver verification by uuid
    mapping(bytes16 => Intent) public intentByUuid;
    mapping(bytes16 => address) public receiverByUuid;
    mapping(bytes16 => bool)    public receiverVerified;

    /// Relayer (backend) authorized to anchor NF receipts
    address public relayer;

    event DepositIntent(
         bytes16 indexed uuid,
         address indexed payer,
         address indexed receiver,
         uint256 amount,
         bytes32 travelRuleHash,
         uint payerNullifier
    );

    event NightfallReceipt(
        bytes16 indexed uuid,
        bytes32 commitmentHash,
        uint256 l2BlockNumber,
        bytes32 l1TxHash
    );

    event ReceiverVerified(bytes16 indexed uuid, address indexed receiver);
    event UnlockAuthorized(bytes16 indexed uuid, address indexed receiver);

    event VerificationBuffered(Role role, address indexed user, bytes16 indexed uuid);
    event ConfigIdUpdated(bytes32 prevId, bytes32 newId);
    event RelayerUpdated(address indexed prev, address indexed next);
    event EligibilityWindowUpdated(uint64 prev, uint64 next);

    error AlreadyUsedNullifier();
    error InvalidUserData();
    error OfacFlagged();
    error NotRelayer();
    error NotEligible();
    error WrongCaller();
    error UnknownIntent();
    error InvalidRole();
    error AlreadyExists();

    modifier onlyRelayer() {
        if (msg.sender != relayer) revert NotRelayer();
        _;
    }

    constructor(
        address hubV2,
        string memory scopeSeed,
        address _relayer // 0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b
    ) SelfVerificationRoot(hubV2, scopeSeed) Ownable(msg.sender) {
        relayer = _relayer;

        // Configuración con países prohibidos
        string[] memory forbiddenCountries = new string[](4);
        forbiddenCountries[0] = CountryCodes.UNITED_STATES;
        forbiddenCountries[1] = CountryCodes.IRAN;
        forbiddenCountries[2] = CountryCodes.AFGHANISTAN;
        forbiddenCountries[3] = CountryCodes.NORTH_KOREA;
        
        SelfUtils.UnformattedVerificationConfigV2 memory rawConfig = SelfUtils.UnformattedVerificationConfigV2({
            olderThan: 18,
            forbiddenCountries: forbiddenCountries,
            ofacEnabled: true
        });

        // 1) Format and register config in the Hub → returns configId
        verificationConfig = SelfUtils.formatVerificationConfigV2(rawConfig);
        verificationConfigId = IIdentityVerificationHubV2(hubV2).setVerificationConfigV2(verificationConfig);
    }

    function setConfigId(bytes32 configId) external onlyOwner {
        emit ConfigIdUpdated(verificationConfigId, configId);
        verificationConfigId = configId;
    }

    function setRelayer(address _relayer) external onlyOwner {
        emit RelayerUpdated(relayer, _relayer);
        relayer = _relayer;
    }

    function setEligibilityWindow(uint64 seconds_) external onlyOwner {
        emit EligibilityWindowUpdated(eligibilityWindow, seconds_);
        eligibilityWindow = seconds_;
    }

     /// @dev Returns the configId (static for MVP)
    function getConfigId(
        bytes32 /*destinationChainId*/,
        bytes32 /*userIdentifier*/,
        bytes memory /*userDefinedData*/
    ) public view override returns (bytes32) {
        return verificationConfigId;
    }

     /**
     * @dev userContextData para payer:
     * abi.encode(
     *   bytes16 uuid,
     *   address payer,        // msg.sender recomendado
     *   address receiver,
     *   uint256 amount,
     *   bytes32 travelRuleHash,
     *   uint8 role            // Role.Payer
     * )
     */
    function verifyPayer(bytes calldata proofPayload, bytes calldata userContextData) external {
        verifySelfProof(proofPayload, userContextData);
    }

    /**
     * @dev userContextData para receiver:
     * abi.encode(
     *   bytes16 uuid,
     *   address receiver,     // msg.sender recomendado
     *   uint8 role            // Role.Receiver
     * )
     */
    function verifyReceiver(bytes calldata proofPayload, bytes calldata userContextData) external {
        verifySelfProof(proofPayload, userContextData);
    }

    /// @dev Hook de verificación exitosa - solo guarda los datos como en ProofOfHuman
    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory output,
        bytes memory userData
    ) internal override {
        if (output.ofac[0] || output.ofac[1] || output.ofac[2]) revert OfacFlagged();

        if (userData.length < 1) revert InvalidUserData();
        
        Role role = _peekRole(userData);
        if (role == Role.Unknown) revert InvalidRole();

        (bytes16 uuid,) = _peekUuidAndAddr(userData);

        PendingVerification memory pv = PendingVerification({
            exists: true,
            role: role,
            output: output,
            userData: userData
        });

        address who = address(uint160(output.userIdentifier));
        
        pendingByCaller[who] = pv;
        pendingByUuid[uuid] = pv;

        emit VerificationBuffered(role, who, uuid);
        eligibleUntil[who] = uint64(block.timestamp) + eligibilityWindow;
    }

    // -------- Intent flow --------
    /**
     * @notice Payer confirma el intent después de su verificación (usa su buffer).
     * @dev Solo el payer puede llamarlo; emite DepositIntent y persiste Intent.
     */
    function executeDeposit() external {
        PendingVerification memory pv = pendingByCaller[msg.sender];
        if (!pv.exists || pv.role != Role.Payer) revert WrongCaller();

        if (usedNullifier[pv.output.nullifier]) revert AlreadyUsedNullifier();
        usedNullifier[pv.output.nullifier] = true;

        if (eligibleUntil[msg.sender] < uint64(block.timestamp)) revert NotEligible();

        (
            bytes16 uuid,
            address payer,
            address receiver,
            uint256 amount,
            bytes32 travelRuleHash
        ) = _decodePayerUserData(pv.userData);

        if (payer != msg.sender) revert WrongCaller();
        if (intentByUuid[uuid].status != IntentStatus.None) revert AlreadyExists();

        intentByUuid[uuid] = Intent({
            payer: payer,
            receiver: receiver,
            amount: amount,
            travelRuleHash: travelRuleHash,
            nullifier: pv.output.nullifier,
            createdAt: uint64(block.timestamp),
            status: IntentStatus.Emitted
        });

        emit DepositIntent(uuid, payer, receiver, amount, travelRuleHash, pv.output.nullifier);

        delete pendingByCaller[msg.sender];
    }

    function markReceiverVerified(bytes16 uuid) external {
        address receiver = intentByUuid[uuid].receiver; // Obtener el receiver del intent
        PendingVerification memory pv = pendingByCaller[receiver];
        if (!pv.exists || pv.role != Role.Receiver) revert WrongCaller();

        // Check that the intent exists
        Intent storage intent = intentByUuid[uuid];
        if (intent.status == IntentStatus.None) revert UnknownIntent();

        if (intent.receiver != msg.sender) revert WrongCaller();
    
        receiverByUuid[uuid] = msg.sender;
        receiverVerified[uuid] = true;
        emit ReceiverVerified(uuid, msg.sender);
        
        delete pendingByCaller[receiver];
    }

     /**
     * @notice Called by the relayer/backend when the NF Client confirms the deposit
     * @param uuid            Must match the X-Request-ID used in /v1/deposit
     * @param commitmentHash  Commitment created in L2 (hex string -> bytes32)
     * @param l2BlockNumber   L2 block where it was included
     * @param l1TxHash        L1 tx hash of escrow in Nightfall.sol
     */
    function attestNightfallDeposit(
        bytes16 uuid,
        bytes32 commitmentHash,
        uint256 l2BlockNumber,
        bytes32 l1TxHash
    ) external onlyRelayer {
        Intent storage it = intentByUuid[uuid];
        if (it.status == IntentStatus.None) revert UnknownIntent();

        // mark the intent as committed in NF
        it.status = IntentStatus.NFCommitted;

        emit NightfallReceipt(uuid, commitmentHash, l2BlockNumber, l1TxHash);
    }

    function unlockFunds(bytes16 uuid) external {
        if (!receiverVerified[uuid]) revert NotEligible();           // ✅ Receiver debe estar verificado
        if (receiverByUuid[uuid] != msg.sender) revert WrongCaller(); // ✅ Solo el receiver autorizado
        Intent storage it = intentByUuid[uuid];
        if (it.status == IntentStatus.None) revert UnknownIntent();   // ✅ Intent debe existir

        it.status = IntentStatus.UnlockAuth;  // 🔓 Autoriza el retiro
        emit UnlockAuthorized(uuid, msg.sender);
    }

    function isEligible(address user) external view returns (bool) {
        return eligibleUntil[user] >= uint64(block.timestamp);
    }

    function _decodePayerUserData(bytes memory userData)
        internal
        pure
        returns (
            bytes16 uuid,
            address payer,
            address receiver,
            uint256 amount,
            bytes32 travelRuleHash
        )
        {
         if (userData.length < 121) revert InvalidUserData();
         (uuid, payer, receiver, amount, travelRuleHash,) =
            abi.decode(userData, (bytes16, address, address, uint256, bytes32, uint8));
        }
    
    function _peekRole(bytes memory userData) internal view returns (Role role) {
        // Try long format first
        if (userData.length >= 121) {
            try this._decodeAsLong(userData) returns (uint8 r) {
                return Role(r);
            } catch {
                // Fall through to short format
            }
        }
        
        // Try short format
        if (userData.length >= 37) { // 16 + 20 + 1 bytes minimum
            try this._decodeAsShort(userData) returns (uint8 r2) {
                return Role(r2);
            } catch {
                return Role.Unknown;
            }
        }
        
        return Role.Unknown;
    }

    function _peekUuidAndAddr(bytes memory userData)
        internal
        view
        returns (bytes16 uuid, address who)
    {
        // Try long format first
        if (userData.length >= 121) {
            try this._decodeUuidAddrLong(userData) returns (bytes16 u, address a) {
                return (u, a);
            } catch {
                // Fall through to short format
            }
        }
        
        // Try short format
        if (userData.length >= 37) {
            try this._decodeUuidAddrShort(userData) returns (bytes16 u2, address a2) {
                return (u2, a2);
            } catch {
                revert InvalidUserData();
            }
        }
        
        revert InvalidUserData();
    }

    function _decodeAsLong(bytes memory d) external pure returns (uint8) {
        (, , , , , uint8 role) = abi.decode(d, (bytes16, address, address, uint256, bytes32, uint8));
        return role;
    }
    function _decodeAsShort(bytes memory d) external pure returns (uint8) {
        (, , uint8 role) = abi.decode(d, (bytes16, address, uint8));
        return role;
    }
    function _decodeUuidAddrLong(bytes memory d) external pure returns (bytes16, address) {
        (bytes16 u, address a, , , ,) = abi.decode(d, (bytes16, address, address, uint256, bytes32, uint8));
        return (u, a);
    }
    function _decodeUuidAddrShort(bytes memory d) external pure returns (bytes16, address) {
        (bytes16 u, address a, ) = abi.decode(d, (bytes16, address, uint8));
        return (u, a);
    }
}