// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {WCOQ} from "../WCOQ.sol";
import {Script} from "forge-std/Script.sol";

contract GrantRole is Script {
    function run() public {
        uint256 validatorOwnerPK = vm.envUint("VALIDATOR_MANAGER_OWNER_PK");
        WCOQ token = WCOQ(0xDc3b0E30d1D079159B616b2Bf618D17167EBd5fB);
        bytes32 issuerRole = token.ISSUER_ROLE();

        vm.startBroadcast(validatorOwnerPK);

        token.grantRole(issuerRole, 0x0ec8F51391b3976B406ec182c8c22e537Ff14ECa);

        vm.stopBroadcast();

        // forge script script/grantRole.s.sol --rpc-url https://api.avax-test.network/ext/bc/C/rpc --broadcast
    }
}
