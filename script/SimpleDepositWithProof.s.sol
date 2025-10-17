// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleDepositWithProof is Script {
    // Direcciones del contrato desplegado
    address constant PRIVACY_VAULT = 0x63127A6f30f0762e3e9BB467aF1eDFFbe0c24cB3;
    address constant CUSD_TOKEN = 0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b;
    
    // Monto a depositar (10 cUSD con 18 decimales)
    uint256 constant DEPOSIT_AMOUNT = 10e18;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(deployerPrivateKey);
        
        console.log("=== Deposito Simple con Proof del Playground ===");
        console.log("Usuario:", user);
        console.log("Contrato PrivacyVault:", PRIVACY_VAULT);
        console.log("Monto a depositar:", DEPOSIT_AMOUNT / 1e18, "cUSD");
        
        // Crear instancias
        PrivacyVault vault = PrivacyVault(PRIVACY_VAULT);
        IERC20 cusd = IERC20(CUSD_TOKEN);
        
        // Verificar balance inicial
        uint256 initialBalance = cusd.balanceOf(user);
        console.log("Balance inicial de cUSD:", initialBalance / 1e18, "cUSD");
        
        if (initialBalance < DEPOSIT_AMOUNT) {
            console.log("ERROR: Balance insuficiente para el deposito");
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Aprobar el gasto
        console.log("Aprobando gasto de cUSD...");
        cusd.approve(PRIVACY_VAULT, DEPOSIT_AMOUNT);
        
        // Usar el formato exacto del playground
        // proofPayload: solo el attestationId (1 = E_PASSPORT)
        bytes memory proofPayload = abi.encodePacked(bytes32(uint256(1)));
        
        // userContextData del playground (exacto)
        bytes memory userContextData = hex"000000000000000000000000000000000000000000000000000000000000a4ec000000000000000000000000c2564e41b7f5cb66d2d99466450cfebce9e8228f48656c6c6f2053464f";
        
        console.log("Datos del proof:");
        console.log("  proofPayload length:", proofPayload.length);
        console.log("  userContextData length:", userContextData.length);
        
        // Paso 1: Verificar usuario
        console.log("Paso 1: Verificando usuario...");
        
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
}

