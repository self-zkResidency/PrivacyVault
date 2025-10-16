// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockHubV2} from "../src/mocks/MockHubV2.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";
import {ISelfVerificationRoot} from "@selfxyz/contracts/interfaces/ISelfVerificationRoot.sol";

contract PrivacyVaultTest is Test {
    MockERC20 cUSD;
    PrivacyVault vault;
    MockHubV2 hub;
    
    address depositor = address(0xD3);
    uint256 amount = 1000e6; // 6 decimales
    
    function setUp() public {
        // Mock token
        cUSD = new MockERC20("cUSD", "cUSD", 6);
        cUSD.mint(depositor, amount);

        // Raw config (en prod el Hub valida países/OFAC; aquí solo necesitamos id)
        string[] memory forb = new string[](1);
        forb[0] = "UNITED_STATES";

        SelfUtils.UnformattedVerificationConfigV2 memory rawCfg = SelfUtils.UnformattedVerificationConfigV2({
            olderThan: 18,
            forbiddenCountries: forb,
            ofacEnabled: true
        });

        // Deploy vault con hub = mock
        // scopeSeed: "proof-of-country"
        hub = new MockHubV2(address(0)); // placeholder
        vault = new PrivacyVault(address(hub), "proof-of-country", address(cUSD), rawCfg);
        // conectar el mock al vault real
        hub = new MockHubV2(address(vault));
    }
    
    // helper: construye output permitido
    function _mkOutputAllowed() internal pure returns (ISelfVerificationRoot.GenericDiscloseOutputV2 memory out) {
        out.attestationId = bytes32("E_PASSPORT");
        out.userIdentifier = uint256(uint160(address(0x1111)));
        out.nullifier = 777;
        out.forbiddenCountriesListPacked = [uint256(0), uint256(0), uint256(0), uint256(0)];
        out.issuingState = "MEXICO";
        string[] memory name = new string[](2);
        name[0] = "Satoshi"; name[1] = "Nakamoto";
        out.name = name;
        out.idNumber = "ABC123";
        out.nationality = "MEXICAN";
        out.dateOfBirth = "01-01-90";
        out.gender = "M";
        out.expiryDate = "01-01-30";
        out.olderThan = 18;
        out.ofac = [false, false, false];
    }

    // helper: payloads dummy (mínimos para pasar checks de longitud en abstract)
    function _mkInputs(address dep, uint256 amt) internal pure returns (bytes memory proofPayload, bytes memory userContextData) {
        // proofPayload = |32 attestationId| + proofData (vacío)
        proofPayload = abi.encodePacked(bytes32("E_PASSPORT"));

        // userContextData = |32 destChainId|32 userIdentifier| userDefinedData |
        bytes32 destChainId = bytes32(uint256(11142220)); // Celo Sepolia id
        bytes32 userIdentifier = bytes32(uint256(uint160(dep)));
        bytes memory userDefinedData = abi.encode(dep, amt);
        userContextData = bytes.concat(destChainId, userIdentifier, userDefinedData);
    }

    function test_Deposit_AllowsCountry_TransfersFunds() public {
        // approve
        vm.prank(depositor);
        cUSD.approve(address(vault), amount);

        // configurar hub: pasa verificación y devuelve output permitido
        hub.setShouldPass(true);
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory out = _mkOutputAllowed();
        hub.setNextOutput(out);

        (bytes memory proofPayload, bytes memory userContextData) = _mkInputs(depositor, amount);

        // Antes
        assertEq(cUSD.balanceOf(depositor), amount);
        assertEq(cUSD.balanceOf(address(vault)), 0);

        // Ejecuta depósito → verify → callback → transferFrom
        vm.prank(depositor);
        vault.deposit(proofPayload, userContextData);

        // Después
        assertEq(cUSD.balanceOf(depositor), 0, "depositor debe quedar sin fondos");
        assertEq(cUSD.balanceOf(address(vault)), amount, "vault debe recibir fondos");

        // nullifier marcado
        (bool success, bytes memory data) = address(vault).staticcall(abi.encodeWithSignature("usedNullifier(uint256)", out.nullifier));
        assertTrue(success);
        bool used = abi.decode(data, (bool));
        assertTrue(used, "nullifier debe estar marcado");
    }

function test_Deposit_BlockedCountry_NoTransfer() public {
        // Caso “bloqueado”: simulamos que el Hub NO llama al callback (revert en verify)
        vm.prank(depositor);
        cUSD.approve(address(vault), amount);

        hub.setShouldPass(false); // simula failing verification
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory out = _mkOutputAllowed();
        out.issuingState = "UNITED_STATES"; // si el Hub aplicara la política, fallaría
        hub.setNextOutput(out);

        (bytes memory proofPayload, bytes memory userContextData) = _mkInputs(depositor, amount);

        // Ejecuta, pero el mock revierte en verify → depósito no ocurre
        vm.expectRevert(bytes("VerificationFailed"));
        vm.prank(depositor);
        vault.deposit(proofPayload, userContextData);

        // Balances intactos
        assertEq(cUSD.balanceOf(depositor), amount);
        assertEq(cUSD.balanceOf(address(vault)), 0);

        // Nullifier NO marcado (no hubo callback)
        (bool success, bytes memory data) = address(vault).staticcall(abi.encodeWithSignature("usedNullifier(uint256)", out.nullifier));
        assertTrue(success);
        bool used = abi.decode(data, (bool));
        assertFalse(used, "nullifier no debe estar marcado");
    }

}

