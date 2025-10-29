// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";

contract DeployMainnet is Script {
    function run() external returns (PrivacyVault vault) {
        // Configuración para Celo Mainnet
        address hub = 0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF; // Self Hub en Celo Mainnet
        string memory scopeSeed = "nomi-money";
        address relayerAddress = 0x4A3f4D82a075434b24ff2920C573C704af776f6A; // Tu dirección relayer

        // IMPORTANTE: Configura tu PRIVATE_KEY como variable de entorno
        // export PRIVATE_KEY=tu_clave_privada_aqui
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        console.log("=== DEPLOYING PRIVACY VAULT TO CELO MAINNET ===");
        console.log("Hub Address:", hub);
        console.log("Scope Seed:", scopeSeed);
        console.log("Relayer Address:", relayerAddress);

        // Deploy del contrato
        vault = new PrivacyVault(hub, scopeSeed, relayerAddress);

        vm.stopBroadcast();

        console.log("\n=== MAINNET DEPLOYMENT SUCCESSFUL ===");
        console.log("PrivacyVault Address:", address(vault));
        console.log("Owner:", vault.owner());
        console.log("Relayer:", vault.relayer());
        console.log("Scope:", vault.scope());
        console.log("Verification Config ID:");
        console.logBytes32(vault.verificationConfigId());
        
        console.log("\n=== MAINNET CONFIGURATION ===");
        console.log("Network: Celo Mainnet (Chain ID: 42220)");
        console.log("Forbidden Countries: USA, IRAN, AFGHANISTAN, NORTH_KOREA");
        console.log("Minimum Age: 18 years");
        console.log("OFAC Check: Enabled");
        console.log("Eligibility Period: 3 days");
        
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Verify deployment on Celo Explorer");
        console.log("2. Update frontend with new contract address");
        console.log("3. Configure Nightfall 4 integration");
        console.log("4. Test verification flow on mainnet");
        console.log("5. Set up relayer backend");
    }
}
