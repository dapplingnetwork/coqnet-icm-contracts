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
        // mainnet: 0x34d58daD810c5B8833f262e9619EE5E33eC73C44
        vm.stopBroadcast();

        // forge script contracts/coqnet/script/DeployRewardsCalculator.s.sol --rpc-url avax
    }
}
