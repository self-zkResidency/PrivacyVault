// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVaultSimple} from "../src/PrivacyVaultSimple.sol";

contract DeploySimple is Script {
    function run() external returns (PrivacyVaultSimple vault) {
        // Configuración para Celo Mainnet
        address hub = 0x16ECBA51e18a4a7e61fdC417f0d47AFEeDfbed74; // Self Hub en Celo Mainnet
        string memory scopeSeed = "nomi-money";

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        console.log("=== DEPLOYING SIMPLIFIED PRIVACY VAULT ===");
        console.log("Hub Address:", hub);
        console.log("Scope Seed:", scopeSeed);

        // Deploy del contrato simplificado
        vault = new PrivacyVaultSimple(hub, scopeSeed);

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT SUCCESSFUL ===");
        console.log("PrivacyVaultSimple Address:", address(vault));
        console.log("Owner:", vault.owner());
        console.log("Scope:", vault.scope());
        console.log("Verification Config ID:");
        console.logBytes32(vault.verificationConfigId());
        
        console.log("\n=== SIMPLIFIED FLOW ===");
        console.log("1. Freelancer: verifyUser() -> createInvoice(invoiceId)");
        console.log("2. Payer: verifyUser() -> executeDeposit(invoiceId)");
        console.log("3. Relayer: attestNightfallDeposit(invoiceId, nightfallHash)");
        console.log("4. Freelancer: verifyUser() -> unlockFunds(invoiceId)");
        
        console.log("\n=== CONFIGURATION ===");
        console.log("Invoice Amount: 10 USD (fixed)");
        console.log("Forbidden Countries: USA, IRAN, AFGHANISTAN, NORTH_KOREA");
        console.log("Minimum Age: 18 years");
        console.log("OFAC Check: Enabled");
        console.log("Invoice Expiry: 3 days (no validation)");
        console.log("Eligibility Period: 3 days");
    }
}
