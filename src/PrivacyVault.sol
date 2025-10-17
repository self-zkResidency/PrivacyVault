// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SelfVerificationRoot} from "@selfxyz/contracts/abstract/SelfVerificationRoot.sol";
import {ISelfVerificationRoot} from "@selfxyz/contracts/interfaces/ISelfVerificationRoot.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/interfaces/IIdentityVerificationHubV2.sol";
import {SelfStructs} from "@selfxyz/contracts/libraries/SelfStructs.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";
import {CountryCodes} from "@selfxyz/contracts/libraries/CountryCode.sol";

/**
 * @title PrivacyVault
 * @notice MVP: valida prueba de Self (país/OFAC) y acepta cUSD si pasa.
 * @dev El depósito (transferFrom) ocurre en customVerificationHook al recibir el callback del Hub.
 */
contract PrivacyVault is SelfVerificationRoot, Ownable {
  using SafeERC20 for IERC20;

   IERC20 public immutable CUSD_TOKEN;

    SelfStructs.VerificationConfigV2 public verificationConfig;
    bytes32 public verificationConfigId;

    /// @notice nullifiers ya usados (evita doble verificación)
    mapping(uint256 => bool) public usedNullifier;

    /// @notice Storage para el nuevo flujo de verificación
    bool public verificationSuccessful;
    ISelfVerificationRoot.GenericDiscloseOutputV2 public lastOutput;
    bytes public lastUserData;
    address public lastUserAddress;

    event DepositValidated(
        address indexed depositor,
        uint256 amount,
        string issuingState,
        string nationality,
        uint256 nullifier
    );

    event VerificationCompleted(ISelfVerificationRoot.GenericDiscloseOutputV2 output, bytes userData);
    event ConfigIdUpdated(bytes32 prevId, bytes32 newId);

    error AlreadyUsedNullifier();
    error InvalidUserData();
    error OfacFlagged();


    constructor(
        address hubV2,
        string memory scopeSeed,
        address cUsdToken // 0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b
    ) SelfVerificationRoot(hubV2, scopeSeed) Ownable(msg.sender) {
        CUSD_TOKEN = IERC20(cUsdToken);

        // Configuración con países prohibidos
        string[] memory forbiddenCountries = new string[](4);
        forbiddenCountries[0] = CountryCodes.UNITED_STATES;
        forbiddenCountries[1] = CountryCodes.IRAN;
        forbiddenCountries[2] = CountryCodes.COLOMBIA;
        forbiddenCountries[3] = CountryCodes.NORTH_KOREA;
        
        SelfUtils.UnformattedVerificationConfigV2 memory rawConfig = SelfUtils.UnformattedVerificationConfigV2({
            olderThan: 18,
            forbiddenCountries: forbiddenCountries,
            ofacEnabled: true
        });

        // 1) Formatear y registrar config en el Hub → devuelve configId
        verificationConfig = SelfUtils.formatVerificationConfigV2(rawConfig);
        verificationConfigId = IIdentityVerificationHubV2(hubV2).setVerificationConfigV2(verificationConfig);
    }

    function setConfigId(bytes32 configId) external onlyOwner {
        emit ConfigIdUpdated(verificationConfigId, configId);
        verificationConfigId = configId;
    }

     /// @dev Devuelve el configId (estático para MVP)
    function getConfigId(
        bytes32 /*destinationChainId*/,
        bytes32 /*userIdentifier*/,
        bytes memory /*userDefinedData*/
    ) public view override returns (bytes32) {
        return verificationConfigId;
    }

    /**
     * @notice Solicita verificación de Self (países prohibidos, OFAC, edad).
     * @param proofPayload |32 bytes attestationId| proofData |
     * @param userContextData |32 destChainId|32 userIdentifier| userDefinedData |
     * @dev userDefinedData DEBE incluir: abi.encode(depositor, amount)
     *      para que el depósito posterior tenga el address y monto exacto a transferir.
     */
    function verifyUser(
        bytes calldata proofPayload,
        bytes calldata userContextData
    ) external {
        // El Hub validará y nos devolverá el callback a onVerificationSuccess -> customVerificationHook
        verifySelfProof(proofPayload, userContextData);
    }

    /// @dev Hook de verificación exitosa - solo guarda los datos como en ProofOfHuman
    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory output,
        bytes memory userData
    ) internal override {
        verificationSuccessful = true;
        lastOutput = output;
        lastUserData = userData;
        lastUserAddress = address(uint160(output.userIdentifier));

        emit VerificationCompleted(output, userData);
    }

    /**
     * @notice Ejecuta el depósito después de verificación exitosa.
     * @dev Solo puede ser llamado si verificationSuccessful es true.
     *      Ejecuta todas las validaciones y transfiere los cUSD.
     */
    function executeDeposit() external {
        if (!verificationSuccessful) revert InvalidUserData();

        // 1) anti-replay
        if (usedNullifier[lastOutput.nullifier]) revert AlreadyUsedNullifier();
        usedNullifier[lastOutput.nullifier] = true;

        // 2) OFAC (si el config tiene ofacEnabled, el Hub ya corta; esto es doble seguro)
        if (lastOutput.ofac[0] || lastOutput.ofac[1] || lastOutput.ofac[2]) revert OfacFlagged();

        // 3) Países prohibidos - ya validados por el Hub usando forbiddenCountries del config
        //    lastOutput.issuingState y lastOutput.nationality están "disclosed" para logging

        // 4) userData -> (depositor, amount) para transferFrom
        if (lastUserData.length < 64) revert InvalidUserData();
        (address depositor, uint256 amount) = abi.decode(lastUserData, (address, uint256));

        // 5) transferir cUSD (requiere approve previo del usuario)
        CUSD_TOKEN.safeTransferFrom(depositor, address(this), amount);

        emit DepositValidated(depositor, amount, lastOutput.issuingState, lastOutput.nationality, lastOutput.nullifier);

        // Reset para evitar reutilización
        verificationSuccessful = false;
        lastUserAddress = address(0);

        // (más adelante) aquí podrías crear la nota privada en ShieldedPool: depositNote(commitment, encMemo)
    }

}