// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {CoqnetERC20TokenStakingManager} from "../CoqnetERC20TokenStakingManager.sol";

//solhint-disable no-console
contract DeployValidator is Script {
    function run() public {
        uint256 owner = vm.envUint("VALIDATOR_MANAGER_OWNER_PK");

        //deploy implementation
        vm.startBroadcast(owner);

        CoqnetERC20TokenStakingManager posImplementation =
            new CoqnetERC20TokenStakingManager(ICMInitializable.Allowed);

        console.log("POSValidator address:", address(posImplementation));
        // 0xd9E3D21f5798F9d400DD03F4C7Dc3554Df49d3C1
        vm.stopBroadcast();
        // forge script script/DeployValidator.s.sol --rpc-url https://api.avax-test.network/ext/bc/C/rpc --broadcast
    }
}
