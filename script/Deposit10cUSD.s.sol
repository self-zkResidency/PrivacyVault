// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deposit10cUSD is Script {
    // Direcciones del contrato desplegado
    address constant PRIVACY_VAULT = 0x63127A6f30f0762e3e9BB467aF1eDFFbe0c24cB3;
    address constant CUSD_TOKEN = 0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b;
    address constant HUB_ADDRESS = 0x16ECBA51e18a4a7e61fdC417f0d47AFEeDfbed74;
    
    // Monto a depositar (10 cUSD con 18 decimales)
    uint256 constant DEPOSIT_AMOUNT = 10e18;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(deployerPrivateKey);
        
        console.log("=== Deposito de 10 cUSD en PrivacyVault ===");
        console.log("Usuario:", user);
        console.log("Contrato PrivacyVault:", PRIVACY_VAULT);
        console.log("Token cUSD:", CUSD_TOKEN);
        console.log("Hub Self:", HUB_ADDRESS);
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
            console.log("Balance actual:", initialBalance / 1e18, "cUSD");
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Aprobar el gasto
        console.log("Aprobando gasto de cUSD...");
        cusd.approve(PRIVACY_VAULT, DEPOSIT_AMOUNT);
        
        // Verificar allowance
        uint256 allowance = cusd.allowance(user, PRIVACY_VAULT);
        console.log("Allowance configurado:", allowance / 1e18, "cUSD");
        
        // Preparar datos para la verificacion de Self
        // NOTA: Esto fallara porque necesitas un proof valido de Self
        bytes memory proofPayload = abi.encodePacked(
            bytes32("E_PASSPORT") // attestationId
            // En produccion, aqui iria el proofData real de la verificacion de Self
        );
        
        // userContextData: destChainId + userIdentifier + userDefinedData
        bytes32 destChainId = bytes32(uint256(11142220)); // Celo Sepolia
        bytes32 userIdentifier = bytes32(uint256(uint160(user)));
        bytes memory userDefinedData = abi.encode(user, DEPOSIT_AMOUNT);
        bytes memory userContextData = bytes.concat(destChainId, userIdentifier, userDefinedData);
        
        console.log("Datos preparados:");
        console.log("  proofPayload length:", proofPayload.length);
        console.log("  userContextData length:", userContextData.length);
        console.log("  destChainId:", uint256(destChainId));
        console.log("  userIdentifier:", uint256(userIdentifier));
        
        // Paso 1: Verificar usuario
        console.log("Paso 1: Verificando usuario...");
        console.log("NOTA: Esto probablemente fallara porque necesitas un proof valido de Self");
        
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
            console.log("Esto es esperado si no tienes un proof valido de Self");
        } catch (bytes memory lowLevelData) {
            console.log("ERROR: Error de bajo nivel en deposito");
            console.log("Datos del error:");
            console.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
        
        console.log("=== Fin del test ===");
        console.log("Para un deposito exitoso, necesitas:");
        console.log("1. Un proof valido de Self (verificacion de identidad)");
        console.log("2. Que tu pais no este en la lista de paises bloqueados");
        console.log("3. Que no estes en la lista OFAC");
    }
    
    // Funcion helper para verificar la configuracion del contrato
    function checkContractConfig() external view {
        PrivacyVault vault = PrivacyVault(PRIVACY_VAULT);
        
        console.log("=== Configuracion del Contrato ===");
        console.log("Direccion del token cUSD:", address(vault.CUSD_TOKEN()));
        console.log("Owner:", vault.owner());
        console.log("Scope:", uint256(vault.scope()));
        console.log("Config ID:", uint256(vault.verificationConfigId()));
    }
}
