// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {PoSValidatorManagerTest} from "./PoSValidatorManagerTests.t.sol";
import {ERC20TokenStakingManager} from "../ERC20TokenStakingManager.sol";
import {ValidatorManagerSettings} from "../interfaces/IValidatorManager.sol";
import {PoSValidatorManagerSettings} from "../interfaces/IPoSValidatorManager.sol";
import {IRewardCalculator} from "../interfaces/IRewardCalculator.sol";
import {ICMInitializable} from "../../utilities/ICMInitializable.sol";
import {ExampleERC20} from "@mocks/ExampleERC20.sol";
import {IERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/utils/SafeERC20.sol";

// TODO: Remove this once all unit tests implemented
// solhint-disable no-empty-blocks
contract ERC20TokenStakingManagerTest is PoSValidatorManagerTest {
    using SafeERC20 for IERC20;

    ERC20TokenStakingManager public app;
    IERC20 public token;

    function setUp() public virtual {
        // Construct the object under test
        app = new ERC20TokenStakingManager(ICMInitializable.Allowed);
        token = new ExampleERC20();
        app.initialize(
            PoSValidatorManagerSettings({
                baseSettings: ValidatorManagerSettings({
                    pChainBlockchainID: P_CHAIN_BLOCKCHAIN_ID,
                    subnetID: DEFAULT_SUBNET_ID,
                    churnPeriodSeconds: DEFAULT_CHURN_PERIOD,
                    maximumChurnPercentage: DEFAULT_MAXIMUM_CHURN_PERCENTAGE
                }),
                minimumStakeWeight: DEFAULT_MINIMUM_STAKE_WEIGHT,
                maximumStakeWeight: DEFAULT_MAXIMUM_STAKE_WEIGHT,
                minimumStakeDuration: DEFAULT_MINIMUM_STAKE_DURATION,
                rewardCalculator: IRewardCalculator(address(0))
            }),
            token
        );
        validatorManager = app;
        posValidatorManager = app;
    }

    function _initializeValidatorRegistration(
        bytes32 nodeID,
        uint64 registrationExpiry,
        bytes memory signature,
        uint64 weight
    ) internal virtual override returns (bytes32) {
        return app.initializeValidatorRegistration(
            _weightToValue(weight), nodeID, registrationExpiry, signature
        );
    }

    function _initializeDelegatorRegistration(
        bytes32 validationID,
        address delegatorAddress,
        uint64 weight
    ) internal virtual override returns (bytes32) {
        uint256 value = _weightToValue(weight);
        vm.startPrank(delegatorAddress);
        bytes32 delegationID = app.initializeDelegatorRegistration(validationID, value);
        vm.stopPrank();
        return delegationID;
    }

    function _beforeSend(uint64 weight, address spender) internal override {
        uint256 value = _weightToValue(weight);
        token.safeIncreaseAllowance(spender, value);
        token.safeTransfer(spender, value);

        // ERC20 tokens need to be pre-approved
        vm.startPrank(spender);
        token.safeIncreaseAllowance(address(app), value);
        vm.stopPrank();
    }

    function _expectStakeUnlock(address account, uint256 amount) internal override {
        vm.expectCall(address(token), abi.encodeCall(IERC20.transfer, (account, amount)));
    }

    // TODO this needs to be kept in line with the contract conversions, but we can't make external calls
    // to the contract and use vm.expectRevert at the same time
    function _valueToWeight(uint256 value) internal virtual override returns (uint64) {
        return uint64(value / 1e12);
    }

    // TODO this needs to be kept in line with the contract conversions, but we can't make external calls
    // to the contract and use vm.expectRevert at the same time
    function _weightToValue(uint64 weight) internal virtual override returns (uint256) {
        return uint256(weight) * 1e12;
    }

    function _getStakeAssetBalance(address account) internal view override returns (uint256) {
        return token.balanceOf(account);
    }
}
