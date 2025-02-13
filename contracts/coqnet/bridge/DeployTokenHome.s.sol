// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC20TokenHomeUpgradeable} from "./../../ictt/TokenHome/ERC20TokenHomeUpgradeable.sol";

import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";

//solhint-disable no-console
contract DeployTokenHome is Script {
    address public constant INITIAL_OWNER = 0x6b207141f47d749321C40D023F5981fdc5E2434d;
    address public constant COQ = 0x420FcA0121DC28039145009570975747295f2329;
    uint8 public constant COQ_DECIMALS = 18;
    address public teleporterManager = 0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf;
    address public teleporterRegistry = 0x7C43605E14F391720e1b37E49C78C4b03A488d98;

    function run() public {
        uint256 deployer = vm.envUint("DEPLOYER");

        //deploy token
        vm.startBroadcast(deployer);
        //tokenHome mainnet: 0x1a6F3002b1340B84B6eC9454b2C6fbB18a6E8a07
        ERC20TokenHomeUpgradeable tokenHome =
            new ERC20TokenHomeUpgradeable(ICMInitializable.Disallowed);
        //solhint-disable-next-line
        bytes memory data = abi.encodeCall(
            tokenHome.initialize, (teleporterRegistry, teleporterManager, 1, COQ, COQ_DECIMALS)
        );

        // proxy mainnet: 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(tokenHome), INITIAL_OWNER, data);
        console.log("Token Home Proxy at:", address(proxy));
        vm.stopBroadcast();

        // DEPLOY TOKEN HOME IMPL
        // forge create contracts/ictt/TokenHome/ERC20TokenHomeUpgradeable.sol:ERC20TokenHomeUpgradeable --rpc-url avax --private-key $PK --broadcast --constructor-args 1

        // DEPLOY TOKEN HOME PROXY
        //forge verify-contract 0x1a6F3002b1340B84B6eC9454b2C6fbB18a6E8a07 contracts/ictt/TokenHome/ERC20TokenHomeUpgradeable.sol:ERC20TokenHomeUpgradeable --rpc-url avax --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan' --num-of-optimizations 200 --compiler-version 0.8.25 --etherscan-api-key "k"

        //forge create lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --rpc-url avax --private-key $PK --broadcast --constructor-args 0x1a6F3002b1340B84B6eC9454b2C6fbB18a6E8a07 0x6b207141f47d749321C40D023F5981fdc5E2434d 0x

        //INITIALZE TOKEN HOME

        //cast send 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2 "initialize(address,address,uint256,address,uint8)" 0x7C43605E14F391720e1b37E49C78C4b03A488d98 0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf 1 0x420FcA0121DC28039145009570975747295f2329 18 --rpc-url avax --private-key $PK

        // BRIDGE ERC20 COQINU TO NATIVE COQ

        // {
        //     bytes32 destinationBlockchainID;
        //     address destinationTokenTransferrerAddress;
        //     address recipient;
        //     address primaryFeeTokenAddress;
        //     uint256 primaryFee;
        //     uint256 secondaryFee;
        //     uint256 requiredGasLimit;
        //     address multiHopFallback;
        // }

        //cast send 0x420FcA0121DC28039145009570975747295f2329 "approve(address,uint256)" 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2 100ether --rpc-url avax --private-key $PK

        //cast send 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2 "send((bytes32,address,address,address,uint256,uint256,uint256,address), uint256)" "(0x898b8aa8353f2b79ee1de07c36474fcee339003d90fa06ea3a90d9e88b7d7c33, 0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98, 0x38C5479620f6C2f29677F04d89E356cF6E75CFde, 0x0000000000000000000000000000000000000000, 0, 0, 10000000,0x0000000000000000000000000000000000000000)" 100ether --rpc-url avax --private-key $PK
    }
}
