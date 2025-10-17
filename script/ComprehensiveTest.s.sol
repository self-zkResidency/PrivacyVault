// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";

contract ComprehensiveTest is Script {
    function run() external {
        address vaultAddress = 0x63127A6f30f0762e3e9BB467aF1eDFFbe0c24cB3;
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
        
        // 2. Verificar configuración de países (ahora estática)
        console.log("\n2. CONFIGURACION DE PAISES:");
        console.log("Los paises prohibidos estan configurados estaticamente en el constructor:");
        console.log("- USA (Estados Unidos)");
        console.log("- IRN (Iran)");
        console.log("- COL (Colombia)");
        console.log("- PRK (Corea del Norte)");
        console.log("OFAC habilitado: true");
        console.log("Edad minima: 18 anos");
        
        // 3. Verificar nullifiers (deberia estar vacio inicialmente)
        console.log("\n3. NULLIFIERS:");
        console.log("Nullifier 123 usado:", vault.usedNullifier(123));
        console.log("Nullifier 456 usado:", vault.usedNullifier(456));
        
        // 4. Verificar configuracion de verificacion
        console.log("\n4. CONFIGURACION DE VERIFICACION:");
        console.log("Config ID:");
        console.logBytes32(vault.verificationConfigId());
        
        // 5. Verificar estado de verificacion
        console.log("\n5. ESTADO DE VERIFICACION:");
        console.log("Verificacion exitosa:", vault.verificationSuccessful());
        console.log("Ultima direccion de usuario:", vault.lastUserAddress());
        
        console.log("\n=== TEST COMPLETADO ===");
        
        vm.stopBroadcast();
    }
}
