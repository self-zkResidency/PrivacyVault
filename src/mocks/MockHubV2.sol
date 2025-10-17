// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISelfVerificationRoot} from "@selfxyz/contracts/interfaces/ISelfVerificationRoot.sol";
import {SelfStructs} from "@selfxyz/contracts/libraries/SelfStructs.sol";

interface ITarget {
    function onVerificationSuccess(bytes memory output, bytes memory userData) external;
}

// Mock Hub que NO implementa la interfaz completa, solo las funciones necesarias para tests
contract MockHubV2 {
    bool public shouldPass;
    ISelfVerificationRoot.GenericDiscloseOutputV2 public nextOutput;
    address public target;

    constructor(address _target) {
        target = _target;
    }

    function setShouldPass(bool v) external { shouldPass = v; }
    
    function setTarget(address _target) external { target = _target; }
    
    function setNextOutput(ISelfVerificationRoot.GenericDiscloseOutputV2 calldata out) external {
        nextOutput = out;
    }

    function verify(bytes calldata, bytes calldata combined) external {
        if (!shouldPass) revert("VerificationFailed");
        if (combined.length < 96) revert("badCombined");
        
        bytes memory userDefinedData;
        unchecked {
            userDefinedData = combined[96:combined.length];
        }

        ITarget(target).onVerificationSuccess(abi.encode(nextOutput), userDefinedData);
    }

    function setVerificationConfigV2(SelfStructs.VerificationConfigV2 calldata) external pure returns (bytes32) {
        return bytes32(uint256(123));
    }
}
