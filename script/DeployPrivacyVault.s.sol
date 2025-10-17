// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";

contract DeployPrivacyVault is Script {
    // Variables de entorno requeridas:
    // - IDENTITY_VERIFICATION_HUB_ADDRESS (requerido en testnet/mainnet)
    // - CUSD_ADDRESS (dirección del token cUSD en esa red)
    // - PRIVATE_KEY (clave privada para deploy)

    function run() external returns (PrivacyVault vault) {
        address hub = vm.envAddress("IDENTITY_VERIFICATION_HUB_ADDRESS");
        string memory scopeSeed = "proofOfCountry"; // vm.envString("SCOPE_SEED");
        address cusd = vm.envAddress("CUSD_ADDRESS");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        // El constructor ahora maneja la configuración internamente
        vault = new PrivacyVault(hub, scopeSeed, cusd);

        vm.stopBroadcast();

        console.log("PrivacyVault deployed:", address(vault));
        console.log("Hub:", hub);
        console.log("Scope:", vault.scope());
        console.log("ConfigId:");
        console.logBytes32(vault.verificationConfigId());
    }

}
