// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {WCOQ} from "../WCOQ.sol";

//solhint-disable no-console
contract DeployToken is Script {
    function run() public {
        uint256 deployer = vm.envUint("DEPLOYER");

        //deploy token
        vm.startBroadcast(deployer);

        WCOQ token = new WCOQ();

        console.log("WCOQ address:", address(token));
        // mainnet: 0x6FED18dbBd1E80D70AB633b55Abb820890ABFf27
        vm.stopBroadcast();

        // forge script contracts/coqnet/script/DeployToken.s.sol --rpc-url avax
    }
}
