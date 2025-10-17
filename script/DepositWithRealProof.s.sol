// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DepositWithRealProof is Script {
    // Direcciones del contrato desplegado
    address constant PRIVACY_VAULT = 0x018f6558d8F81B319Ae33618Ac7bfdC3Ac23dF8c;
    address constant CUSD_TOKEN = 0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b;
    address constant HUB_ADDRESS = 0x16ECBA51e18a4a7e61fdC417f0d47AFEeDfbed74;
    
    // Monto a depositar (10 cUSD con 18 decimales)
    uint256 constant DEPOSIT_AMOUNT = 10e18;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(deployerPrivateKey);
        
        console.log("=== Deposito con Proof Real de Self ===");
        console.log("Usuario:", user);
        console.log("Contrato PrivacyVault:", PRIVACY_VAULT);
        console.log("Token cUSD:", CUSD_TOKEN);
        console.log("Monto a depositar:", DEPOSIT_AMOUNT / 1e18, "cUSD");
        
        // Crear instancias
        PrivacyVault vault = PrivacyVault(PRIVACY_VAULT);
        IERC20 cusd = IERC20(CUSD_TOKEN);
        
        // Verificar balance inicial
        uint256 initialBalance = cusd.balanceOf(user);
        console.log("Balance inicial de cUSD:", initialBalance / 1e18, "cUSD");
        
        if (initialBalance < DEPOSIT_AMOUNT) {
            console.log("ERROR: Balance insuficiente para el deposito");
            console.log("Necesitas al menos", DEPOSIT_AMOUNT / 1e18, "cUSD");
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Aprobar el gasto
        console.log("Aprobando gasto de cUSD...");
        cusd.approve(PRIVACY_VAULT, DEPOSIT_AMOUNT);
        
        // Verificar allowance
        uint256 allowance = cusd.allowance(user, PRIVACY_VAULT);
        console.log("Allowance configurado:", allowance / 1e18, "cUSD");
        
        // INSTRUCCIONES PARA OBTENER PROOF REAL:
        // 1. Ve a https://playground.staging.self.xyz/
        // 2. Genera un proof mock para un pais permitido (no USA)
        // 3. Copia el proofPayload y userContextData del playground
        // 4. Reemplaza los datos de abajo con los datos reales
        
        // DATOS DEL PLAYGROUND (reemplazar con datos reales):
        bytes memory proofPayload = hex""; // Reemplazar con proofPayload del playground
        bytes memory userContextData = hex""; // Reemplazar con userContextData del playground
        
        // Verificar que los datos no esten vacios
        if (proofPayload.length == 0 || userContextData.length == 0) {
            console.log("ERROR: Debes proporcionar datos de proof reales del playground");
            console.log("Ve a https://playground.staging.self.xyz/ y genera un proof mock");
            vm.stopBroadcast();
            return;
        }
        
        console.log("Datos del proof:");
        console.log("  proofPayload length:", proofPayload.length);
        console.log("  userContextData length:", userContextData.length);
        
        // Paso 1: Verificar usuario
        console.log("Paso 1: Verificando usuario con proof real...");
        
        try vault.verifyUser(proofPayload, userContextData) {
            console.log("SUCCESS: Verificacion exitosa!");
            
            // Verificar que la verificacion fue exitosa
            bool verificationSuccess = vault.verificationSuccessful();
            console.log("Verificacion exitosa:", verificationSuccess);
            
            if (verificationSuccess) {
                console.log("Paso 2: Ejecutando deposito...");
                
                // Paso 2: Ejecutar deposito
                vault.executeDeposit();
                console.log("SUCCESS: Deposito ejecutado exitosamente!");
                
                // Verificar balances finales
                uint256 finalUserBalance = cusd.balanceOf(user);
                uint256 finalVaultBalance = cusd.balanceOf(PRIVACY_VAULT);
                
                console.log("Balance final del usuario:", finalUserBalance / 1e18, "cUSD");
                console.log("Balance final del vault:", finalVaultBalance / 1e18, "cUSD");
                console.log("Diferencia depositada:", (initialBalance - finalUserBalance) / 1e18, "cUSD");
            } else {
                console.log("ERROR: La verificacion no fue exitosa");
            }
            
        } catch Error(string memory reason) {
            console.log("ERROR: Error en verificacion:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("ERROR: Error de bajo nivel en deposito");
            console.log("Datos del error:");
            console.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
        
        console.log("=== Fin del test ===");
    }
    
    // Funcion para probar con datos hardcodeados (para testing rapido)
    function testWithHardcodedProof() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(deployerPrivateKey);
        
        console.log("=== Test con Proof Hardcodeado ===");
        console.log("Usuario:", user);
        
        PrivacyVault vault = PrivacyVault(PRIVACY_VAULT);
        IERC20 cusd = IERC20(CUSD_TOKEN);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Aprobar gasto
        cusd.approve(PRIVACY_VAULT, DEPOSIT_AMOUNT);
        
        // Datos de ejemplo (reemplazar con datos reales del playground)
        bytes memory proofPayload = abi.encodePacked(bytes32("E_PASSPORT"));
        bytes32 destChainId = bytes32(uint256(11142220));
        bytes32 userIdentifier = bytes32(uint256(uint160(user)));
        bytes memory userDefinedData = abi.encode(user, DEPOSIT_AMOUNT);
        bytes memory userContextData = bytes.concat(destChainId, userIdentifier, userDefinedData);
        
        console.log("Intentando verificacion con datos de ejemplo...");
        
        try vault.verifyUser(proofPayload, userContextData) {
            console.log("SUCCESS: Verificacion exitosa!");
            
            if (vault.verificationSuccessful()) {
                vault.executeDeposit();
                console.log("SUCCESS: Deposito ejecutado!");
            }
        } catch Error(string memory reason) {
            console.log("ERROR:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("ERROR de bajo nivel:");
            console.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
    }
}

