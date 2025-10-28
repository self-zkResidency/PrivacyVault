// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";

contract DeployPrivacyVault is Script {
    // Variables de entorno requeridas:
    // - IDENTITY_VERIFICATION_HUB_ADDRESS (dirección del Hub de Self)
    // - RELAYER_ADDRESS (dirección del relayer autorizado para Nightfall)
    // - PRIVATE_KEY (clave privada para deploy)
    // - SCOPE_SEED (opcional, por defecto "nomi-money")

    function run() external returns (PrivacyVault vault) {
        address hub = vm.envAddress("IDENTITY_VERIFICATION_HUB_ADDRESS");
        string memory scopeSeed = "nomi-money"; // vm.envString("SCOPE_SEED");
        address relayerAddress = vm.envAddress("RELAYER_ADDRESS");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        console.log("=== DEPLOYING PRIVACY VAULT (Nightfall 4) ===");
        console.log("Hub Address:", hub);
        console.log("Scope Seed:", scopeSeed);
        console.log("Relayer Address:", relayerAddress);

        // Deploy del contrato con la nueva arquitectura
        vault = new PrivacyVault(hub, scopeSeed, relayerAddress);

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT SUCCESSFUL ===");
        console.log("PrivacyVault Address:", address(vault));
        console.log("Owner:", vault.owner());
        console.log("Relayer:", vault.relayer());
        console.log("Scope:", vault.scope());
        console.log("Verification Config ID:");
        console.logBytes32(vault.verificationConfigId());
        
        console.log("\n=== CONFIGURATION ===");
        console.log("Forbidden Countries: USA, IRAN, AFGHANISTAN, NORTH_KOREA");
        console.log("Minimum Age: 18 years");
        console.log("OFAC Check: Enabled");
        console.log("Eligibility Period: 3 days");
        
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Verify deployment on block explorer");
        console.log("2. Configure Nightfall 4 integration");
        console.log("3. Test verification flow");
        console.log("4. Set up relayer backend");
    }

}
