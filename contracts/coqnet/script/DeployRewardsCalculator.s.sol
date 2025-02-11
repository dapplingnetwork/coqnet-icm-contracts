// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {RewardsCalculator} from "../RewardsCalculator.sol";

//solhint-disable no-console
contract DeployRewardsCalculator is Script {
    uint64 public constant DEFAULT_REWARD_BASIS_POINTS = 42;

    function run() public {
        uint256 deployer = vm.envUint("DEPLOYER");
        //deploy token
        vm.startBroadcast(deployer);

        RewardsCalculator rewards = new RewardsCalculator(DEFAULT_REWARD_BASIS_POINTS);

        console.log("RewardsCalculator:", address(rewards));
        // 0x2eD5aBb96D0C06a6e79527027DE4D97Cc30c9452
        vm.stopBroadcast();

        // forge script contracts/coqnet/script/DeployRewardsCalculator.s.sol --rpc-url avax
    }
}
