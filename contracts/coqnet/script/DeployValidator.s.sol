// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {CoqnetERC20TokenStakingManager} from "../CoqnetERC20TokenStakingManager.sol";

//solhint-disable no-console
contract DeployValidator is Script {
    function run() public {
        uint256 deployer = vm.envUint("DEPLOYER");

        vm.startBroadcast(deployer);

        CoqnetERC20TokenStakingManager posImplementation =
            new CoqnetERC20TokenStakingManager(ICMInitializable.Allowed);

        console.log("POSValidator address:", address(posImplementation));
        // mainnet: 0x8e04217e68dE3d7D6f9810b2157Dd46E3A15FEaC
        vm.stopBroadcast();
        // forge script contracts/coqnet/script/DeployValidator.s.sol --rpc-url avax
    }
}
