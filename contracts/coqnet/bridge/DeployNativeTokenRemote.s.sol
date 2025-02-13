// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {NativeTokenRemoteUpgradeable} from
    "./../../ictt/TokenRemote/NativeTokenRemoteUpgradeable.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TokenRemoteSettings} from "../../ictt/TokenRemote/interfaces/ITokenRemote.sol";

//solhint-disable no-console
contract DeployNativeTokenRemote is Script {
    address public constant INITIAL_OWNER = 0x6b207141f47d749321C40D023F5981fdc5E2434d;
    bytes32 public constant TOKEN_HOME_BLOCKCHAIN_ID =
        bytes32(hex"0427d4b22a2a78bcddd456742caf91b56badbff985ee19aef14573e7343fd652");

    uint8 public constant TOKEN_HOME_DECIMALS = 18;

    string public constant NATIVE_SYMBOL = "COQ";

    address public teleporterRegistry = 0xE329B5Ff445E4976821FdCa99D6897EC43891A6c;
    address public teleporterManager = 0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf;
    address public tokenHomeAddress = 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2;

    function run() public {
        uint256 deployer = vm.envUint("DEPLOYER");
        //deploy token
        vm.startBroadcast(deployer);

        // coqnet: 0x1C0d2019347fc55B679967cF21aaa7d7D02726A7
        NativeTokenRemoteUpgradeable nativeRemote =
            new NativeTokenRemoteUpgradeable(ICMInitializable.Disallowed);

        TokenRemoteSettings memory remoteSettings = TokenRemoteSettings({
            teleporterRegistryAddress: teleporterRegistry,
            teleporterManager: teleporterManager,
            minTeleporterVersion: 1,
            tokenHomeBlockchainID: TOKEN_HOME_BLOCKCHAIN_ID,
            tokenHomeAddress: tokenHomeAddress,
            tokenHomeDecimals: TOKEN_HOME_DECIMALS
        });
        //solhint-disable-next-line
        bytes memory data = abi.encodeWithSelector(
            nativeRemote.initialize.selector, remoteSettings, NATIVE_SYMBOL, 100e18 + 1e24, 0
        );

        // coqnet: 0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(nativeRemote), INITIAL_OWNER, data);
        console.log("Token Home Proxy at:", address(proxy));
        vm.stopBroadcast();

        //DEPLOY NATIVE TOKEN REMOTE IMPL

        // forge create contracts/ictt/TokenRemote/NativeTokenRemoteUpgradeable.sol:NativeTokenRemoteUpgradeable --rpc-url coqnet --private-key $PK --broadcast --constructor-args 1

        // DEPLOY NATIVE TOKEN REMOTE PROXY

        //forge verify-contract 0x1C0d2019347fc55B679967cF21aaa7d7D02726A7 contracts/ictt/TokenRemote/NativeTokenRemoteUpgradeable.sol:NativeTokenRemoteUpgradeable --rpc-url coqnet --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan' --num-of-optimizations 200 --compiler-version 0.8.25 --etherscan-api-key a

        //forge create lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --rpc-url coqnet --private-key $PK --broadcast --constructor-args 0x1C0d2019347fc55B679967cF21aaa7d7D02726A7 0x6b207141f47d749321C40D023F5981fdc5E2434d 0x

        // INITIALZE NATIVE TOKEN REMOTE

        //cast send 0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98 "initialize((address,address,uint256,bytes32,address,uint8),string,uint256,uint256)" "(0xE329B5Ff445E4976821FdCa99D6897EC43891A6c, 0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf, 1, 0x0427d4b22a2a78bcddd456742caf91b56badbff985ee19aef14573e7343fd652, 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2,18)" COQ 1000100ether 0  --rpc-url coqnet --private-key $PK

        // REGISTER WITH HOME

        //cast send  0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98 "registerWithHome((address,uint256))" "(0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98,0)" --rpc-url coqnet --private-key $PK

        // BRIDGE native COQ to ERC20 CoqInu

        // struct SendTokensInput {
        //     bytes32 destinationBlockchainID;
        //     address destinationTokenTransferrerAddress;
        //     address recipient;
        //     address primaryFeeTokenAddress;
        //     uint256 primaryFee;
        //     uint256 secondaryFee;
        //     uint256 requiredGasLimit;
        //     address multiHopFallback;
        // }

        //cast send 0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98 "send((bytes32,address,address,address,uint256,uint256,uint256,address))" "(0x0427d4b22a2a78bcddd456742caf91b56badbff985ee19aef14573e7343fd652, 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2, 0x38C5479620f6C2f29677F04d89E356cF6E75CFde, 0x0000000000000000000000000000000000000000, 0, 0, 10000000,0x0000000000000000000000000000000000000000)" --value 300ether --rpc-url coqnet --private-key $PK
    }
}
