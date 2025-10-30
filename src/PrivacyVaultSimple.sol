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
 * @title PrivacyVaultSimple
 * @notice Flujo simplificado: Invoice + Verificación Self + Nightfall
 * @dev Flujo: Usuario A crea invoice → Usuario B verifica y deposita → Nightfall procesa → Usuario A confirma recepción
 */
contract PrivacyVaultSimple is SelfVerificationRoot, Ownable {
    
    // ============ CONSTANTS ============
    
    uint256 public constant INVOICE_AMOUNT = 10 * 10**18; // 10 USD (18 decimals)
    
    // ============ STRUCTS ============
    
    struct Invoice {
        address freelancer;        // Usuario A (quien crea el invoice)
        uint256 createdAt;        // Timestamp de creación
        uint256 expiresAt;        // Timestamp de expiración (3 días)
        bool isPaid;              // Si ya fue pagado
        bytes32 nightfallHash;    // Hash de la transacción Nightfall
    }
    
    struct DepositIntent {
        address payer;            // Usuario B (quien paga)
        uint256 createdAt;        // Timestamp del depósito
        bool isProcessed;         // Si ya fue procesado por Nightfall
    }
    
    // ============ STATE VARIABLES ============
    
    SelfStructs.VerificationConfigV2 public verificationConfig;
    bytes32 public verificationConfigId;
    
    // Storage para verificación temporal
    bool public verificationSuccessful;
    ISelfVerificationRoot.GenericDiscloseOutputV2 public lastOutput;
    bytes public lastUserData;
    address public lastUserAddress;
    uint8 public lastUserRole; // 1 = Freelancer, 2 = Payer
    
    // Mappings
    mapping(bytes16 => Invoice) public invoices;           // invoiceId => Invoice
    mapping(bytes16 => DepositIntent) public deposits;     // invoiceId => DepositIntent
    mapping(uint256 => bool) public usedNullifiers;        // nullifier => used
    mapping(address => bool) public isEligible;            // user => eligible (3 días)
    mapping(address => uint256) public eligibleUntil;      // user => timestamp
    
    // ============ EVENTS ============
    
    event InvoiceCreated(
        bytes16 indexed invoiceId,
        address indexed freelancer,
        uint256 expiresAt
    );
    
    event InvoicePaid(
        bytes16 indexed invoiceId,
        address indexed payer
    );
    
    event NightfallProcessed(
        bytes16 indexed invoiceId,
        bytes32 nightfallHash
    );
    
    event FundsUnlocked(
        bytes16 indexed invoiceId,
        address indexed freelancer
    );
    
    event VerificationCompleted(
        address indexed user,
        uint8 role,
        bytes16 invoiceId
    );
    
    // ============ ERRORS ============
    
    error InvalidUserData();
    error OfacFlagged();
    error AlreadyUsedNullifier();
    error InvoiceNotFound();
    error InvoiceAlreadyPaid();
    error WrongCaller();
    error NotEligible();
    error InvalidRole();
    error InvalidStatus();
    
    // ============ CONSTRUCTOR ============
    
    constructor(
        address hubV2,
        string memory scopeSeed
    ) SelfVerificationRoot(hubV2, scopeSeed) Ownable(msg.sender) {
        
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

        verificationConfig = SelfUtils.formatVerificationConfigV2(rawConfig);
        verificationConfigId = IIdentityVerificationHubV2(hubV2).setVerificationConfigV2(verificationConfig);
    }
    
    // ============ VERIFICATION FUNCTIONS ============
    
    /**
     * @notice Verifica usuario (freelancer o payer)
     * @param proofPayload Attestation ID
     * @param userContextData Datos del usuario
     */
    function verifyUser(
        bytes calldata proofPayload,
        bytes calldata userContextData
    ) external {
        verifySelfProof(proofPayload, userContextData);
    }
    
    /**
     * @dev Hook de verificación exitosa
     */
    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory output,
        bytes memory userData
    ) internal override {
        // Validaciones básicas
        if (userData.length == 0) revert InvalidUserData();
        // OFAC: deshabilitado temporalmente en el contrato. Si se requiere,
        // puede aplicarse desde el Hub (config) o reactivarse aquí.
        // if (output.ofac[0] || output.ofac[1] || output.ofac[2]) revert OfacFlagged();
        
        // Decodificar datos del usuario
        (bytes16 invoiceId, uint8 role) = abi.decode(userData, (bytes16, uint8));
        
        if (role != 1 && role != 2) revert InvalidRole(); // 1 = Freelancer, 2 = Payer
        
        // Guardar datos de verificación
        verificationSuccessful = true;
        lastOutput = output;
        lastUserData = userData;
        lastUserAddress = address(uint160(output.userIdentifier));
        lastUserRole = role;
        
        // Marcar usuario como elegible por 3 días
        eligibleUntil[lastUserAddress] = uint64(block.timestamp) + 3 days;
        isEligible[lastUserAddress] = true;
        
        emit VerificationCompleted(lastUserAddress, role, invoiceId);
    }
    
    // ============ INVOICE FUNCTIONS ============
    
    /**
     * @notice Crea un invoice (solo freelancer verificado)
     * @param invoiceId ID único del invoice (generado por frontend)
     */
    function createInvoice(bytes16 invoiceId) external {
        if (!verificationSuccessful || lastUserRole != 1) revert WrongCaller();
        if (eligibleUntil[msg.sender] < block.timestamp) revert NotEligible();
        if (invoices[invoiceId].freelancer != address(0)) revert InvoiceNotFound(); // Ya existe
        
        invoices[invoiceId] = Invoice({
            freelancer: msg.sender,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + 3 days,
            isPaid: false,
            nightfallHash: bytes32(0)
        });
        
        emit InvoiceCreated(invoiceId, msg.sender, block.timestamp + 3 days);
        
        // Reset verificación
        verificationSuccessful = false;
    }
    
    /**
     * @notice Ejecuta depósito para un invoice (solo payer verificado)
     * @param invoiceId ID del invoice a pagar
     */
    function executeDeposit(bytes16 invoiceId) external {
        if (!verificationSuccessful || lastUserRole != 2) revert WrongCaller();
        if (eligibleUntil[msg.sender] < block.timestamp) revert NotEligible();
        if (usedNullifiers[lastOutput.nullifier]) revert AlreadyUsedNullifier();
        
        Invoice storage invoice = invoices[invoiceId];
        if (invoice.freelancer == address(0)) revert InvoiceNotFound();
        if (invoice.isPaid) revert InvoiceAlreadyPaid();
        
        // Marcar nullifier como usado
        usedNullifiers[lastOutput.nullifier] = true;
        
        // Crear intent de depósito (monto fijo: 10 USD)
        deposits[invoiceId] = DepositIntent({
            payer: msg.sender,
            createdAt: block.timestamp,
            isProcessed: false
        });
        
        // Marcar invoice como pagado
        invoice.isPaid = true;
        
        emit InvoicePaid(invoiceId, msg.sender);
        
        // Reset verificación
        verificationSuccessful = false;
    }
    
    /**
     * @notice Confirma procesamiento por Nightfall (solo relayer)
     * @param invoiceId ID del invoice
     * @param nightfallHash Hash de la transacción Nightfall
     */
    function attestNightfallDeposit(bytes16 invoiceId, bytes32 nightfallHash) external onlyOwner {
        Invoice storage invoice = invoices[invoiceId];
        if (invoice.freelancer == address(0)) revert InvoiceNotFound();
        
        invoice.nightfallHash = nightfallHash;
        deposits[invoiceId].isProcessed = true;
        
        emit NightfallProcessed(invoiceId, nightfallHash);
    }
    
    /**
     * @notice Desbloquea fondos para el freelancer (solo freelancer verificado)
     * @param invoiceId ID del invoice
     */
    function unlockFunds(bytes16 invoiceId) external {
        if (!verificationSuccessful || lastUserRole != 1) revert WrongCaller();
        if (eligibleUntil[msg.sender] < block.timestamp) revert NotEligible();
        
        Invoice storage invoice = invoices[invoiceId];
        if (invoice.freelancer != msg.sender) revert WrongCaller();
        if (!invoice.isPaid) revert InvalidStatus();
        if (!deposits[invoiceId].isProcessed) revert InvalidStatus();
        
        // Invoice completado (no hay campo isActive en esta versión simplificada)
        
        emit FundsUnlocked(invoiceId, msg.sender);
        
        // Reset verificación
        verificationSuccessful = false;
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function getConfigId(
        bytes32 /*destinationChainId*/,
        bytes32 /*userIdentifier*/,
        bytes memory /*userDefinedData*/
    ) public view override returns (bytes32) {
        return verificationConfigId;
    }
    
    function isInvoiceActive(bytes16 invoiceId) external view returns (bool) {
        Invoice memory invoice = invoices[invoiceId];
        return !invoice.isPaid && block.timestamp <= invoice.expiresAt;
    }
    
    function getInvoice(bytes16 invoiceId) external view returns (Invoice memory) {
        return invoices[invoiceId];
    }
    
    function getDeposit(bytes16 invoiceId) external view returns (DepositIntent memory) {
        return deposits[invoiceId];
    }
}
