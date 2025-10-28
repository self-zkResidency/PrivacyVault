// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";
import {MockHubV2} from "../src/mocks/MockHubV2.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";
import {ISelfVerificationRoot} from "@selfxyz/contracts/interfaces/ISelfVerificationRoot.sol";

contract PrivacyVaultTest is Test {
    PrivacyVault vault;
    MockHubV2 hub;
    
    address payer = address(0xD3);
    address receiver = address(0xD4);
    address relayer = address(0xD5);
    uint256 amount = 1000e18; // 18 decimales (como USDC)
    bytes16 uuid = bytes16(uint128(0x1234567890abcdef1234567890abcdef));
    bytes32 travelRuleHash = keccak256("travel-rule-data");
    
    function setUp() public {
        // Deploy mock hub
        hub = new MockHubV2(address(0)); // placeholder inicial
        
        // Deploy vault con nueva arquitectura (sin ERC20)
        vault = new PrivacyVault(address(hub), "nomi-money", relayer);
        
        // Conectar el hub al vault
        hub.setTarget(address(vault));
    }
    
    // helper: construye output permitido para payer
    function _mkOutputAllowed(address user) internal pure returns (ISelfVerificationRoot.GenericDiscloseOutputV2 memory out) {
        out.attestationId = bytes32("E_PASSPORT");
        out.userIdentifier = uint256(uint160(user)); // Usar el address del usuario correctamente
        out.nullifier = 777;
        out.forbiddenCountriesListPacked = [uint256(0), uint256(0), uint256(0), uint256(0)];
        out.issuingState = "MEX";
        string[] memory name = new string[](2);
        name[0] = "Satoshi"; name[1] = "Nakamoto";
        out.name = name;
        out.idNumber = "ABC123";
        out.nationality = "MEX";
        out.dateOfBirth = "01-01-90";
        out.gender = "M";
        out.expiryDate = "01-01-30";
        out.olderThan = 18;
        out.ofac = [false, false, false];
    }

    // helper: payloads para payer (formato largo)
    function _mkPayerInputs() internal view returns (bytes memory proofPayload, bytes memory userContextData) {
        // proofPayload = |32 attestationId| + proofData (vacío)
        proofPayload = abi.encodePacked(bytes32("E_PASSPORT"));

        // userContextData = |32 destChainId|32 userIdentifier| userDefinedData |
        bytes32 destChainId = bytes32(uint256(11142220)); // Celo Sepolia id
        bytes32 userIdentifier = bytes32(uint256(uint160(payer)));
        
        // userDefinedData para payer: uuid, payer, receiver, amount, travelRuleHash, role
        bytes memory userDefinedData = abi.encode(uuid, payer, receiver, amount, travelRuleHash, uint8(1)); // Role.Payer = 1
        userContextData = bytes.concat(destChainId, userIdentifier, userDefinedData);
    }

    // helper: payloads para receiver (formato corto)
    function _mkReceiverInputs() internal view returns (bytes memory proofPayload, bytes memory userContextData) {
        // proofPayload = |32 attestationId| + proofData (vacío)
        proofPayload = abi.encodePacked(bytes32("E_PASSPORT"));

        // userContextData = |32 destChainId|32 userIdentifier| userDefinedData |
        bytes32 destChainId = bytes32(uint256(11142220)); // Celo Sepolia id
        bytes32 userIdentifier = bytes32(uint256(uint160(receiver)));
        
        // userDefinedData para receiver: uuid, receiver, role
        bytes memory userDefinedData = abi.encode(uuid, receiver, uint8(2)); // Role.Receiver = 2
        userContextData = bytes.concat(destChainId, userIdentifier, userDefinedData);
    }

    function test_PayerVerification_AndDepositIntent() public {
        // Configurar hub: pasa verificación y devuelve output permitido
        hub.setShouldPass(true);
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory out = _mkOutputAllowed(payer);
        hub.setNextOutput(out);

        (bytes memory proofPayload, bytes memory userContextData) = _mkPayerInputs();

        // Verificar que no hay intent inicialmente
        (address intentPayer, address intentReceiver, uint256 intentAmount, bytes32 intentTravelRuleHash, uint256 intentNullifier, uint64 intentCreatedAt, PrivacyVault.IntentStatus intentStatus) = vault.intentByUuid(uuid);
        assertEq(uint8(intentStatus), 0, "Intent debe estar en estado None");

        // Paso 1: Verificar payer
        vm.prank(payer);
        vault.verifyPayer(proofPayload, userContextData);
        
        // Verificar que la verificación fue exitosa (eligibility)
        assertTrue(vault.isEligible(payer), "Payer debe ser elegible");
        
        // Paso 2: Ejecutar depósito (crear intent)
        vm.prank(payer);
        vault.executeDeposit();

        // Verificar que el intent fue creado
        (address intentPayer2, address intentReceiver2, uint256 intentAmount2, bytes32 intentTravelRuleHash2, uint256 intentNullifier2, uint64 intentCreatedAt2, PrivacyVault.IntentStatus intentStatus2) = vault.intentByUuid(uuid);
        assertEq(intentPayer2, payer, "Payer debe coincidir");
        assertEq(intentReceiver2, receiver, "Receiver debe coincidir");
        assertEq(intentAmount2, amount, "Amount debe coincidir");
        assertEq(intentTravelRuleHash2, travelRuleHash, "Travel rule hash debe coincidir");
        assertEq(uint8(intentStatus2), 1, "Status debe ser Emitted");

        // Verificar nullifier marcado
        assertTrue(vault.usedNullifier(out.nullifier), "Nullifier debe estar marcado");
    }

    function test_ReceiverVerification() public {
        // Primero crear un intent (simular flujo completo)
        hub.setShouldPass(true);
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory payerOut = _mkOutputAllowed(payer);
        hub.setNextOutput(payerOut);

        (bytes memory payerProofPayload, bytes memory payerUserContextData) = _mkPayerInputs();

        // Verificar payer y crear intent
        vm.prank(payer);
        vault.verifyPayer(payerProofPayload, payerUserContextData);
        
        vm.prank(payer);
        vault.executeDeposit();

        // Ahora verificar receiver
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory receiverOut = _mkOutputAllowed(receiver);
        receiverOut.nullifier = 888; // Diferente nullifier para receiver
        hub.setNextOutput(receiverOut);

        (bytes memory receiverProofPayload, bytes memory receiverUserContextData) = _mkReceiverInputs();

        // Verificar receiver
        vm.prank(receiver);
        vault.verifyReceiver(receiverProofPayload, receiverUserContextData);

        // Marcar receiver como verificado
        vm.prank(receiver);
        vault.markReceiverVerified(uuid);

        // Verificar que el receiver fue marcado como verificado
        assertTrue(vault.receiverVerified(uuid), "Receiver debe estar verificado");
        assertEq(vault.receiverByUuid(uuid), receiver, "Receiver debe coincidir");
    }

    function test_NightfallReceipt() public {
        // Crear intent completo
        hub.setShouldPass(true);
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory out = _mkOutputAllowed(payer);
        hub.setNextOutput(out);

        (bytes memory proofPayload, bytes memory userContextData) = _mkPayerInputs();

        vm.prank(payer);
        vault.verifyPayer(proofPayload, userContextData);
        
        vm.prank(payer);
        vault.executeDeposit();

        // Simular receipt de Nightfall
        bytes32 commitmentHash = keccak256("commitment-data");
        uint256 l2BlockNumber = 12345;
        bytes32 l1TxHash = keccak256("l1-tx-hash");

        vm.prank(relayer);
        vault.attestNightfallDeposit(uuid, commitmentHash, l2BlockNumber, l1TxHash);

        // Verificar que el status cambió a NFCommitted
        (, , , , , , PrivacyVault.IntentStatus intentStatus) = vault.intentByUuid(uuid);
        assertEq(uint8(intentStatus), 2, "Status debe ser NFCommitted");
    }

    function test_UnlockFunds() public {
        // Crear flujo completo hasta NFCommitted
        hub.setShouldPass(true);
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory payerOut = _mkOutputAllowed(payer);
        hub.setNextOutput(payerOut);

        (bytes memory payerProofPayload, bytes memory payerUserContextData) = _mkPayerInputs();

        vm.prank(payer);
        vault.verifyPayer(payerProofPayload, payerUserContextData);
        
        vm.prank(payer);
        vault.executeDeposit();

        // Verificar receiver
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory receiverOut = _mkOutputAllowed(receiver);
        receiverOut.nullifier = 888;
        hub.setNextOutput(receiverOut);

        (bytes memory receiverProofPayload, bytes memory receiverUserContextData) = _mkReceiverInputs();

        vm.prank(receiver);
        vault.verifyReceiver(receiverProofPayload, receiverUserContextData);

        vm.prank(receiver);
        vault.markReceiverVerified(uuid);

        // Simular NF receipt
        vm.prank(relayer);
        vault.attestNightfallDeposit(uuid, keccak256("commitment"), 12345, keccak256("l1-tx"));

        // Unlock funds
        vm.prank(receiver);
        vault.unlockFunds(uuid);

        // Verificar que el status cambió a UnlockAuth
        (, , , , , , PrivacyVault.IntentStatus intentStatus) = vault.intentByUuid(uuid);
        assertEq(uint8(intentStatus), 3, "Status debe ser UnlockAuth");
    }

    function test_BlockedCountry_NoVerification() public {
        // Caso "bloqueado": simulamos que el Hub NO llama al callback (revert en verify)
        hub.setShouldPass(false); // simula failing verification
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory out = _mkOutputAllowed(payer);
        out.issuingState = "USA"; // si el Hub aplicara la política, fallaría
        hub.setNextOutput(out);

        (bytes memory proofPayload, bytes memory userContextData) = _mkPayerInputs();

        // Ejecuta, pero el mock revierte en verify → verificación no ocurre
        vm.expectRevert(bytes("VerificationFailed"));
        vm.prank(payer);
        vault.verifyPayer(proofPayload, userContextData);

        // Verificar que no hay intent creado
        (, , , , , , PrivacyVault.IntentStatus intentStatus) = vault.intentByUuid(uuid);
        assertEq(uint8(intentStatus), 0, "Intent debe estar en estado None");

        // Nullifier NO marcado (no hubo callback)
        assertFalse(vault.usedNullifier(out.nullifier), "Nullifier no debe estar marcado");
    }

}

