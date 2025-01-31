// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";

import {CoqnetERC20TokenStakingManager} from "../CoqnetERC20TokenStakingManager.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PoSValidatorManagerSettings} from "@validator-manager/interfaces/IPoSValidatorManager.sol";
import {IRewardCalculator} from "@validator-manager/interfaces/IRewardCalculator.sol";
import {ValidatorManagerSettings} from "@validator-manager/interfaces/IValidatorManager.sol";
import {WCOQ} from "../WCOQ.sol";
import {IERC20Mintable} from "@validator-manager/interfaces/IERC20Mintable.sol";

contract UpgradePOAtoPOS is Script {
    bytes32 public constant L1_ID =
        bytes32(hex"080fa7727ac2b73292de264684f469732687b61977ae5e95d79727a2e8dd7c54");
    bytes32 public constant SOURCE_BLOCKCHAIN_ID =
        bytes32(hex"1fbae9f07fdccb931e9de419b15690728296f4743f77588082b3e4425d6de54a");

    uint256 public constant MINIMUM_STAKE_AMOUNT = 560e24;
    uint256 public constant MAXIMUM_STAKE_AMOUNT = 560e24;
    uint64 public constant CHURN_PERIOD = 60 seconds;
    uint8 public constant MAXIMUM_CHURN_PERCENTAGE = 80;

    uint64 public constant MINIMUM_STAKE_DURATION = 61 seconds;
    uint16 public constant MINIMUM_DELEGATION_FEE_BIPS = 100;
    uint8 public constant MAXIMUM_STAKE_MULTIPLIER = 1;
    uint256 public constant WEIGHT_TO_VALUE_FACTOR = 1e25;
    address public constant REWARDS_CALCULATOR = 0x7906466991143f662faC3B06D5e3846e4c6CC893;
    address public validatorOwner = 0xb4f69B081E784d50FF0a1ec1d46570ABAC7a221d;

    function run() public {
        uint256 validatorOwnerPK = vm.envUint("VALIDATOR_MANAGER_OWNER_PK");

        ProxyAdmin admin = ProxyAdmin(0xf2673a325Bf125469aCdF5a869327E340C78C1A2);
        ITransparentUpgradeableProxy transparentProxy =
            ITransparentUpgradeableProxy(0x0ec8F51391b3976B406ec182c8c22e537Ff14ECa);
        CoqnetERC20TokenStakingManager posImplementation =
            CoqnetERC20TokenStakingManager(0x2236b5c6b042F107b0B46b589c2E328108B430f6);
        WCOQ token = WCOQ(0xDc3b0E30d1D079159B616b2Bf618D17167EBd5fB);

        PoSValidatorManagerSettings memory settings = _defaultPoSSettings();
        bytes memory data = abi.encodeCall(
            posImplementation.initialize, (settings, IERC20Mintable(address(token)), validatorOwner)
        );

        vm.startBroadcast(validatorOwnerPK);

        admin.upgradeAndCall(transparentProxy, address(posImplementation), data);

        vm.stopBroadcast();

        // forge script script/PoaToPos.s.sol --rpc-url https://api.avax-test.network/ext/bc/C/rpc --broadcast
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
