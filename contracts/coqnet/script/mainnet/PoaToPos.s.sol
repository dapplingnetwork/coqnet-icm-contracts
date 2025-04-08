// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";

import {CoqnetERC20TokenStakingManager} from "../../CoqnetERC20TokenStakingManager.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PoSValidatorManagerSettings} from "@validator-manager/interfaces/IPoSValidatorManager.sol";
import {IRewardCalculator} from "@validator-manager/interfaces/IRewardCalculator.sol";
import {ValidatorManagerSettings} from "@validator-manager/interfaces/IValidatorManager.sol";
import {WCOQ} from "../../WCOQ.sol";
import {IERC20Mintable} from "@validator-manager/interfaces/IERC20Mintable.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";

contract MainnetUpgradePOAtoPOS is Script {
    bytes32 public constant L1_ID =
        bytes32(hex"0ad6355dc6b82cd375e3914badb3e2f8d907d0856f8e679b2db46f8938a2f012");
    bytes32 public constant SOURCE_BLOCKCHAIN_ID =
        bytes32(hex"898b8aa8353f2b79ee1de07c36474fcee339003d90fa06ea3a90d9e88b7d7c33");

    uint256 public constant MINIMUM_STAKE_AMOUNT = 20_000_000e18;
    uint256 public constant MAXIMUM_STAKE_AMOUNT = 20_000_000e18;
    uint64 public constant CHURN_PERIOD = 60 seconds;
    uint8 public constant MAXIMUM_CHURN_PERCENTAGE = 80;

    uint64 public constant MINIMUM_STAKE_DURATION = 61 seconds;
    uint16 public constant MINIMUM_DELEGATION_FEE_BIPS = 100;
    uint8 public constant MAXIMUM_STAKE_MULTIPLIER = 1;
    uint256 public constant WEIGHT_TO_VALUE_FACTOR = 0.02e25;

    address public constant REWARDS_CALCULATOR = 0x34d58daD810c5B8833f262e9619EE5E33eC73C44;
    address public owner = 0x6b207141f47d749321C40D023F5981fdc5E2434d;
    address public constant COQ = 0x420FcA0121DC28039145009570975747295f2329;

    function run() public {
        uint256 validatorOwnerPK = vm.envUint("VALIDATOR_MANAGER_OWNER_PK");
        vm.startBroadcast(validatorOwnerPK);

        ProxyAdmin admin = ProxyAdmin(0xf3a23A5a144047478718e6F9C65fAB94C2B89D17);
        ITransparentUpgradeableProxy transparentProxy =
            ITransparentUpgradeableProxy(0x1424Aef0d5272373BEB69b2a860bd1da078df67F);

        CoqnetERC20TokenStakingManager posImplementation =
            new CoqnetERC20TokenStakingManager(ICMInitializable.Disallowed);

        PoSValidatorManagerSettings memory settings = _defaultPoSSettings();
        bytes memory data =
            abi.encodeCall(posImplementation.initialize, (settings, IERC20Mintable(COQ), owner));

        admin.upgradeAndCall(transparentProxy, address(posImplementation), data);

        vm.stopBroadcast();

        // forge script contracts/coqnet/script/mainnet/PoaToPos.s.sol:MainnetUpgradePOAtoPOS --rpc-url avax
    }

    function _defaultPoSSettings() internal pure returns (PoSValidatorManagerSettings memory) {
        return PoSValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                subnetID: L1_ID,
                churnPeriodSeconds: CHURN_PERIOD,
                maximumChurnPercentage: MAXIMUM_CHURN_PERCENTAGE
            }),
            minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
            maximumStakeAmount: MAXIMUM_STAKE_AMOUNT,
            minimumStakeDuration: MINIMUM_STAKE_DURATION,
            minimumDelegationFeeBips: MINIMUM_DELEGATION_FEE_BIPS,
            maximumStakeMultiplier: MAXIMUM_STAKE_MULTIPLIER,
            weightToValueFactor: WEIGHT_TO_VALUE_FACTOR,
            rewardCalculator: IRewardCalculator(REWARDS_CALCULATOR),
            uptimeBlockchainID: SOURCE_BLOCKCHAIN_ID
        });
    }
}
