// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";

contract TestPrivacyVault is Script {
    function run() external {
        address vaultAddress = 0x950650FdA9C97c24aA90C6f0C3e8d9DDbA4a48Fb;
        PrivacyVault vault = PrivacyVault(vaultAddress);
        
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        
        // Test: Bloquear México
        string memory country = "MEX";
        vault.setCountryBlocked(country, true);
        console.log("Pais bloqueado:", country);
        
        // Verificar owner
        console.log("Owner:", vault.owner());
        console.log("cUSD Token:", address(vault.CUSD_TOKEN()));
        console.log("Verification Config ID:");
        console.logBytes32(vault.verificationConfigId());
        
        vm.stopBroadcast();
    }
}
