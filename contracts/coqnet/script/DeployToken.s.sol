// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {WCOQ} from "../WCOQ.sol";

//solhint-disable no-console
contract DeployToken is Script {
    function run() public {
        uint256 owner = vm.envUint("VALIDATOR_MANAGER_OWNER_PK");

        //deploy token
        vm.startBroadcast(owner);

        WCOQ token = new WCOQ();

        console.log("WCOQ address:", address(token));
        // 0xDc3b0E30d1D079159B616b2Bf618D17167EBd5fB
        vm.stopBroadcast();

        // forge script script/DeployToken.s.sol --rpc-url https://api.avax-test.network/ext/bc/C/rpc --broadcast
    }
}
