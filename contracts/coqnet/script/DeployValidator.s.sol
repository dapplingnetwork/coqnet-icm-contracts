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

        CoqnetERC20TokenStakingManager poaImplementation =
            new CoqnetERC20TokenStakingManager(ICMInitializable.Allowed);

        console.log("POAValidator implementation address:", address(poaImplementation));
        // 0x2236b5c6b042F107b0B46b589c2E328108B430f6
        vm.stopBroadcast();
        // forge script script/DeployValidator.s.sol --rpc-url https://api.avax-test.network/ext/bc/C/rpc --broadcast
    }
}
