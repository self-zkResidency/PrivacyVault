// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/interfaces/IIdentityVerificationHubV2.sol";

contract DeployPrivacyVault is Script {
    // - IDENTITY_VERIFICATION_HUB_ADDRESS (requerido en testnet/mainnet)
    // - SCOPE_SEED (string corto, p.ej. "proof-of-country")
    // - CUSD_ADDRESS (dirección del token cUSD en esa red)
    // - FORBIDDEN_COUNTRIES (CSV opcional, p.ej. "UNITED_STATES,IRAN")
    // - OFAC_ENABLED ("true"/"false"), default false

    function run() external returns (PrivacyVault vault) {
        address hub = vm.envAddress("IDENTITY_VERIFICATION_HUB_ADDRESS");
        string memory scopeSeed = vm.envString("SCOPE_SEED");
        address cusd = vm.envAddress("CUSD_ADDRESS");

        // Parsear lista de países bloqueados desde CSV (opcional)
        string memory countriesCsv = vm.envOr("FORBIDDEN_COUNTRIES", string(""));
        string[] memory forb = _splitCsv(countriesCsv);

        bool ofacEnabled = false;
        string memory ofacStr = vm.envOr("OFAC_ENABLED", string("false"));
        if (_eqNoCase(ofacStr, "true")) ofacEnabled = true;

        // Construir raw config
        SelfUtils.UnformattedVerificationConfigV2 memory rawCfg = SelfUtils.UnformattedVerificationConfigV2({
            olderThan: 18,
            forbiddenCountries: forb,   // máx 40
            ofacEnabled: ofacEnabled
        });

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        vault = new PrivacyVault(hub, scopeSeed, cusd, rawCfg);

        vm.stopBroadcast();

        console.log("PrivacyVault deployed:", address(vault));
        console.log("Hub:", hub);
        console.log("Scope:", vault.scope());
    }

    // ----------------- helpers -----------------
    function _splitCsv(string memory csv) internal pure returns (string[] memory arr) {
        bytes memory b = bytes(csv);
        if (b.length == 0) {
            arr = new string[](0);
            return arr;
        }
        // contar comas
        uint256 count = 1;
        for (uint256 i; i < b.length; i++) if (b[i] == ",") count++;
        arr = new string[](count);
        uint256 last = 0;
        uint256 idx = 0;
        for (uint256 i; i <= b.length; i++) {
            if (i == b.length || b[i] == ",") {
                bytes memory slice = new bytes(i - last);
                for (uint256 j; j < slice.length; j++) slice[j] = b[last + j];
                arr[idx++] = string(slice);
                last = i + 1;
            }
        }
    }

    function _eqNoCase(string memory a, string memory b) internal pure returns (bool) {
        bytes memory ba = bytes(a);
        bytes memory bb = bytes(b);
        if (ba.length != bb.length) return false;
        for (uint256 i; i < ba.length; i++) {
            uint8 ca = uint8(ba[i]);
            uint8 cb = uint8(bb[i]);
            if (ca >= 97 && ca <= 122) ca -= 32; // to upper
            if (cb >= 97 && cb <= 122) cb -= 32;
            if (ca != cb) return false;
        }
        return true;
    }
}
