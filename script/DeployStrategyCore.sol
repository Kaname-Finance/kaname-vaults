// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {StrategyCore} from "../src/StrategyCore.sol";
import {DefaultSetup} from "./Setup.sol";

contract DeployStrategyCore is DefaultSetup {
    function run() public {
        vm.startBroadcast(privateKey);
        StrategyCore strategyCore = new StrategyCore{salt: bytes32(0)}();
        vm.stopBroadcast();
        // 0xAc347bA8aA1bfB2f01864c9897F84CbB27c9C721
        console.log("StrategyCore deployed at: %s", address(strategyCore));
    }
}
