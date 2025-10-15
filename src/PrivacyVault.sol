// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SelfVerificationRoot} from "@selfxyz/contracts/abstract/SelfVerificationRoot.sol";
import {ISelfVerificationRoot} from "@selfxyz/contracts/interfaces/ISelfVerificationRoot.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/interfaces/IIdentityVerificationHubV2.sol";
import {SelfStructs} from "@selfxyz/contracts/libraries/SelfStructs.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";

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
    
    /// @notice países bloqueados
    mapping(bytes32 => bool) public blockedCountry;

    event DepositValidated(
        address indexed depositor,
        uint256 amount,
        string issuingState,
        string nationality,
        uint256 nullifier
    );

    event ConfigIdUpdated(bytes32 prevId, bytes32 newId);
    event CountryBlocklistUpdated(bytes32 indexed countryKey, bool blocked);

    error AlreadyUsedNullifier();
    error InvalidUserData();
    error OfacFlagged();
    error CountryBlocked(string issuingState, string nationality);


    constructor(
        address hubV2,
        string memory scopeSeed,
        address cUsdToken,
        SelfUtils.UnformattedVerificationConfigV2 memory rawCfg
    ) SelfVerificationRoot(hubV2, scopeSeed) Ownable(msg.sender) {
        CUSD_TOKEN = IERC20(cUsdToken);

        // 1) Formatear y registrar config en el Hub → devuelve configId
        verificationConfig = SelfUtils.formatVerificationConfigV2(rawCfg);
        verificationConfigId = IIdentityVerificationHubV2(hubV2).setVerificationConfigV2(verificationConfig);
    }

    function setConfigId(bytes32 configId) external onlyOwner {
        emit ConfigIdUpdated(verificationConfigId, configId);
        verificationConfigId = configId;
    }

    /// @dev countryStr debe venir ya normalizado (p.ej., "MEX" o "MX").
    ///      Se calcula el hash vía inline assembly para evitar asignaciones en memoria.
    function setCountryBlocked(string calldata countryStr, bool blocked) external onlyOwner {
        bytes32 key = _keccakStringCalldata(countryStr);
        blockedCountry[key] = blocked;
        emit CountryBlocklistUpdated(key, blocked);
    }

    /// @dev Hash eficiente (keccak256) de string calldata sin conversiones intermedias.
    function _keccakStringCalldata(string calldata s) internal pure returns (bytes32 out) {
        assembly {
            let off := s.offset
            let len := s.length
            // Copiamos a memoria una sola vez para usar keccak256
            let ptr := mload(0x40)
            calldatacopy(ptr, off, len)
            out := keccak256(ptr, len)
            mstore(0x40, add(ptr, len))
        }
    }

    // -------------------------------------------------
    // User entrypoint
    // -------------------------------------------------
    /**
     * @notice Solicita depósito validado por Self.
     * @param proofPayload |32 bytes attestationId| proofData |
     * @param userContextData |32 destChainId|32 userIdentifier| userDefinedData |
     * @dev userDefinedData DEBE incluir: abi.encode(depositor, amount)
     *      para que el hook tenga el address y monto exacto a transferir.
     */
    function deposit(
        bytes calldata proofPayload,
        bytes calldata userContextData
    ) external {
        // El Hub validará y nos devolverá el callback a onVerificationSuccess -> customVerificationHook
        verifySelfProof(proofPayload, userContextData);
    }

     /// @dev Devuelve el configId (estático para MVP)
    function getConfigId(
        bytes32 /*destinationChainId*/,
        bytes32 /*userIdentifier*/,
        bytes memory /*userDefinedData*/
    ) public view override returns (bytes32) {
        return verificationConfigId;
    }

    /// @dev Aquí hacemos TODA la lógica post-verificación: país/OFAC/nullifier y transferFrom.
    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory output,
        bytes memory userData
    ) internal override {
        // 1) anti-replay
        if (usedNullifier[output.nullifier]) revert AlreadyUsedNullifier();
        usedNullifier[output.nullifier] = true;

        // 2) OFAC (si el config tiene ofacEnabled, el Hub ya corta; esto es doble seguro)
        if (output.ofac[0] || output.ofac[1] || output.ofac[2]) revert OfacFlagged();

        // 3) País — el Hub también valida forbiddenCountries; aquí solo log/defensa extra.
        //    Si quieres re-chequear manualmente, podrías comparar contra tu propia lista.
        //    Para MVP, basta con confiar en el config registrado + loggear:
        //    output.issuingState y output.nationality están “disclosed”.

        // 4) userData -> (depositor, amount) para transferFrom
        if (userData.length < 64) revert InvalidUserData();
        (address depositor, uint256 amount) = abi.decode(userData, (address, uint256));

        // 5) transferir cUSD (requiere approve previo del usuario)
        CUSD_TOKEN.safeTransferFrom(depositor, address(this), amount);

        emit DepositValidated(depositor, amount, output.issuingState, output.nationality, output.nullifier);

        // (más adelante) aquí podrías crear la nota privada en ShieldedPool: depositNote(commitment, encMemo)
    }

}