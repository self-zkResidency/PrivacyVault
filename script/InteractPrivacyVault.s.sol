// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";

contract InteractPrivacyVault is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        
        PrivacyVault vault = PrivacyVault(vaultAddress);
        
        vm.startBroadcast(privateKey);
        
        // Ejemplo: bloquear un país
        string memory country = "MEX";
        vault.setCountryBlocked(country, true);
        console.log("Pais bloqueado:", country);
        
        // Verificar owner
        console.log("Owner:", vault.owner());
        
        vm.stopBroadcast();
    }
}
