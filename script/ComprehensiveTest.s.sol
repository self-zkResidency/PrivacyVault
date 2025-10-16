// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";

contract ComprehensiveTest is Script {
    function run() external {
        address vaultAddress = 0x950650FdA9C97c24aA90C6f0C3e8d9DDbA4a48Fb;
        PrivacyVault vault = PrivacyVault(vaultAddress);
        
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        
        console.log("=== PRIVACY VAULT COMPREHENSIVE TEST ===");
        
        // 1. Verificar configuración inicial
        console.log("\n1. CONFIGURACION INICIAL:");
        console.log("Owner:", vault.owner());
        console.log("cUSD Token:", address(vault.CUSD_TOKEN()));
        console.log("Verification Config ID:");
        console.logBytes32(vault.verificationConfigId());
        
        // 2. Probar bloqueo de países
        console.log("\n2. BLOQUEO DE PAISES:");
        
        // Bloquear varios países
        string[3] memory countries = ["MEX", "COL", "ARG"];
        for (uint i = 0; i < countries.length; i++) {
            vault.setCountryBlocked(countries[i], true);
            console.log("Bloqueado:", countries[i]);
        }
        
        // Desbloquear uno
        vault.setCountryBlocked("ARG", false);
        console.log("Desbloqueado: ARG");
        
        // 3. Verificar nullifiers (debería estar vacío inicialmente)
        console.log("\n3. NULLIFIERS:");
        console.log("Nullifier 123 usado:", vault.usedNullifier(123));
        console.log("Nullifier 456 usado:", vault.usedNullifier(456));
        
        // 4. Verificar configuración de verificación
        console.log("\n4. CONFIGURACION DE VERIFICACION:");
        console.log("Config ID:");
        console.logBytes32(vault.verificationConfigId());
        
        console.log("\n=== TEST COMPLETADO ===");
        
        vm.stopBroadcast();
    }
}
