// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CoqnetERC20TokenStakingManager} from "../CoqnetERC20TokenStakingManager.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {PoSValidatorManagerSettings} from "@validator-manager/PoSValidatorManager.sol";
import {PoSValidatorManagerTest} from "@validator-manager/tests/PoSValidatorManagerTests.t.sol";
import {
    ValidatorRegistrationInput,
    IValidatorManager
} from "@validator-manager/interfaces/IValidatorManager.sol";
import {
    ValidatorRegistrationInput,
    IValidatorManager
} from "@validator-manager/interfaces/IValidatorManager.sol";
import {IERC20Mintable, IERC20} from "@validator-manager/interfaces/IERC20Mintable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {WCOQ} from "../WCOQ.sol";
import {ValidatorMessages} from "@validator-manager/ValidatorMessages.sol";
import {ValidatorManagerSettings} from "@validator-manager/interfaces/IValidatorManager.sol";
import {IRewardCalculator} from "@validator-manager/interfaces/IRewardCalculator.sol";
import {
    WarpMessage,
    IWarpMessenger
} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";

import "./../RewardsCalculator.sol";

contract CoqnetERC20TokenStakingManagerTest is PoSValidatorManagerTest {
    using SafeERC20 for IERC20Mintable;

    bytes32 public constant L1_ID =
        bytes32(hex"080fa7727ac2b73292de264684f469732687b61977ae5e95d79727a2e8dd7c54");
    bytes32 public constant SOURCE_BLOCKCHAIN_ID =
        bytes32(hex"1fbae9f07fdccb931e9de419b15690728296f4743f77588082b3e4425d6de54a");

    uint256 public constant MINIMUM_STAKE_AMOUNT = 560e24;
    uint256 public constant MAXIMUM_STAKE_AMOUNT = 560e24;
    uint64 public constant CHURN_PERIOD = 30 days;
    uint8 public constant MAXIMUM_CHURN_PERCENTAGE = 80;

    uint64 public constant MINIMUM_STAKE_DURATION = 30 days;
    uint16 public constant MINIMUM_DELEGATION_FEE_BIPS = 100;
    uint8 public constant MAXIMUM_STAKE_MULTIPLIER = 1;
    uint256 public constant WEIGHT_TO_VALUE_FACTOR = 1e25;
    address public constant REWARDS_CALCULATOR = 0x7906466991143f662faC3B06D5e3846e4c6CC893;

    bytes32 public constant COQNET_METRICS_STORAGE_LOCATION =
        0x15948f25c54ec2687bf5cd60236db66c5e145b7bc4b04f89902ccb02ee706d00;

    ProxyAdmin public admin = ProxyAdmin(0xf2673a325Bf125469aCdF5a869327E340C78C1A2);
    ITransparentUpgradeableProxy public proxy =
        ITransparentUpgradeableProxy(0x0ec8F51391b3976B406ec182c8c22e537Ff14ECa);
    CoqnetERC20TokenStakingManager public app = CoqnetERC20TokenStakingManager(address(proxy));
    WCOQ public wcoq = WCOQ(0x5bA67Aa90c0d947D1f953774e44bB4d926C62fd8);
    WCOQ public token;

    address public validatorOwner = 0xb4f69B081E784d50FF0a1ec1d46570ABAC7a221d;

    address public validator = makeAddr("validator");
    address public register = makeAddr("register");

    function setUp() public override {
        // _setUp();
        // _mockGetBlockchainID();
        // _mockInitializeValidatorSet();
        // deal(register, 1 ether);
        validatorManager = app;
        posValidatorManager = app;
        token = wcoq;
        deal(address(wcoq), address(this), 50000e24);
        token.approve(address(app), type(uint256).max);

        bytes32 role = token.ISSUER_ROLE();
        vm.prank(validatorOwner);
        token.grantRole(role, address(app));
    }

    // known issues, if validation completes within min stake duration and epoch end time, wont be able to end validation nor claim rewards

    function testRewardsToActiveValidatorsUpToEpochEndTime() public {
        _upgrade();
        _grantRegisterRole(address(this));
        uint64 weight = 56;

        bytes32 validationID = _setUpInitializeValidatorOnBehalfOfRegistration(
            DEFAULT_NODE_ID,
            L1_ID,
            weight,
            uint64(vm.getBlockTimestamp()),
            DEFAULT_BLS_PUBLIC_KEY,
            validator
        );

        bytes memory l1ValidatorRegistrationMessage =
            ValidatorMessages.packL1ValidatorRegistrationMessage(validationID, true);
        _mockGetPChainWarpMessage(l1ValidatorRegistrationMessage, true);
        app.completeValidatorRegistration(0);

        vm.warp(block.timestamp + 45 days + 2);

        bytes memory uptimeMsg =
            ValidatorMessages.packValidationUptimeMessage(validationID, 45 days);
        _mockGetUptimeWarpMessage(uptimeMsg, true);
        posValidatorManager.submitUptimeProof(validationID, 0);

        vm.prank(validator);
        app.initializeEndValidation(validationID, false, 0);

        bytes memory endValidationMessage =
            ValidatorMessages.packL1ValidatorRegistrationMessage(validationID, false);
        _mockGetPChainWarpMessage(endValidationMessage, true);

        // _expectRewardIssuance(, 0);
        // calculate upto 30 days
        app.completeEndValidation(0);
    }

    function testRemovesRewardsOfInactiveValidators() public {
        _upgrade();
        _grantRegisterRole(address(this));
        uint64 weight = 56;

        uint64 expirationTime;

        bytes32[] memory validationIDs = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            bytes memory node = abi.encodePacked(
                hex"1234567812345678123456781234567812345678123456781234567812345680",
                bytes1(uint8(i))
            );

            expirationTime = uint64(vm.getBlockTimestamp() + 1);
            bytes32 validationID = _setUpInitializeValidatorOnBehalfOfRegistration(
                node, L1_ID, weight, expirationTime, DEFAULT_BLS_PUBLIC_KEY, address(uint160(i + 1))
            );
            validationIDs[i] = validationID;

            bytes memory l1ValidatorRegistrationMessage =
                ValidatorMessages.packL1ValidatorRegistrationMessage(validationID, true);
            _mockGetPChainWarpMessage(l1ValidatorRegistrationMessage, true);
            app.completeValidatorRegistration(0);

            vm.warp(vm.getBlockTimestamp() + 60 minutes);

            bytes memory uptimeMsg =
                ValidatorMessages.packValidationUptimeMessage(validationID, 60 minutes);
            _mockGetUptimeWarpMessage(uptimeMsg, true);
            posValidatorManager.submitUptimeProof(validationID, 0);
        }

        expirationTime = uint64(vm.getBlockTimestamp() + 1);
        _setUpInitializeValidatorOnBehalfOfRegistration(
            DEFAULT_NODE_ID, L1_ID, weight, expirationTime, DEFAULT_BLS_PUBLIC_KEY, address(9)
        );

        vm.warp(vm.getBlockTimestamp() + 15 days);

        // submit uptime proof
        bytes memory uptimeMsg2 =
            ValidatorMessages.packValidationUptimeMessage(validationIDs[0], 12 days);
        _mockGetUptimeWarpMessage(uptimeMsg2, true);
        posValidatorManager.submitUptimeProof(validationIDs[0], 0);

        vm.warp(vm.getBlockTimestamp() + 15 days + 1);

        vm.prank(address(1));
        app.forceInitializeEndValidation(validationIDs[0], true, 0);

        bytes memory l1ValidatorasEndMessage =
            ValidatorMessages.packL1ValidatorRegistrationMessage(validationIDs[0], false);
        _mockGetPChainWarpMessage(l1ValidatorasEndMessage, true);
        _expectRewardIssuance(address(1), 0);
        app.completeEndValidation(0);
    }

    // ends all validations at epochs endTime
    // Should register within min stake duration and epoch end Time
    function testCreatesNewEpochUponEpochEnding() public {
        _upgrade();
        _grantRegisterRole(address(this));
        uint64 weight = 56;
        bytes memory node =
            bytes(hex"1234567812345678123456781234567812345678123456781234567812345680");
        uint64 expirationTime = uint64(block.timestamp + 1);
        _setUpInitializeValidatorOnBehalfOfRegistration(
            node, L1_ID, weight, expirationTime, DEFAULT_BLS_PUBLIC_KEY, address(100)
        );

        uint256 currentEpoch = app.getCurrentEpochIndex();
        assertEq(currentEpoch, 1);

        // advance
        vm.warp(block.timestamp + 30 days + 2);

        node = bytes(hex"1234567812345678123456781234567812345678123456781234567812345681");
        expirationTime = uint64(vm.getBlockTimestamp());
        _setUpInitializeValidatorOnBehalfOfRegistration(
            node, L1_ID, weight, expirationTime, DEFAULT_BLS_PUBLIC_KEY, address(101)
        );

        currentEpoch = app.getCurrentEpochIndex();
        assertEq(currentEpoch, 2);
    }

    function testCannotRegisterIfAllsValidationsAreActive() public {
        _upgrade();
        _grantRegisterRole(address(this));
        validatorManager = app;
        posValidatorManager = app;
        token = wcoq;
        uint64 weight = 56;
        deal(address(wcoq), address(this), 50000e24);
        token.approve(address(app), type(uint256).max);

        bytes32[] memory validatorIDs = new bytes32[](5);

        for (uint256 i = 0; i < 5; i++) {
            bytes memory node = abi.encodePacked(
                hex"1234567812345678123456781234567812345678123456781234567812345680",
                bytes1(uint8(i)) // Increment last byte
            );

            uint64 expirationTime = uint64(vm.getBlockTimestamp() + 1);
            bytes32 validationID = _setUpInitializeValidatorOnBehalfOfRegistration(
                node, L1_ID, weight, expirationTime, DEFAULT_BLS_PUBLIC_KEY, address(uint160(i + 1))
            );
            validatorIDs[i] = validationID;

            bytes memory l1ValidatorRegistrationMessage =
                ValidatorMessages.packL1ValidatorRegistrationMessage(validationID, true);
            _mockGetPChainWarpMessage(l1ValidatorRegistrationMessage, true);
            app.completeValidatorRegistration(0);

            vm.warp(vm.getBlockTimestamp() + 60 minutes);
        }
        for (uint256 i = 0; i < 5; i++) {
            uint64 uptime = uint64(4.5 hours);
            bytes32 validationID = validatorIDs[i];
            bytes memory uptimeMsg =
                ValidatorMessages.packValidationUptimeMessage(validationID, uptime);
            _mockGetUptimeWarpMessage(uptimeMsg, true);
            posValidatorManager.submitUptimeProof(validationID, 0);
        }

        ValidatorRegistrationInput memory input;
        vm.expectRevert(CoqnetERC20TokenStakingManager.ValidatorRegistrationExceeded.selector);
        app.initializeValidatorRegistrationOnBehalfOf(input, 0, 0, 0, validator);
    }

    function testInvalidatesAndReplacesAnInactiveValidationID() public {
        _upgrade();
        _grantRegisterRole(address(this));
        uint64 weight = 56;
        deal(address(wcoq), address(this), 50000e24);
        token.approve(address(app), type(uint256).max);

        for (uint256 i = 0; i < 5; i++) {
            bytes memory node = abi.encodePacked(
                hex"1234567812345678123456781234567812345678123456781234567812345680",
                bytes1(uint8(i)) // Increment last byte
            );
            uint64 expirationTime = uint64(vm.getBlockTimestamp() + 1);
            bytes32 validationID = _setUpInitializeValidatorOnBehalfOfRegistration(
                node, L1_ID, weight, expirationTime, DEFAULT_BLS_PUBLIC_KEY, address(uint160(i))
            );

            bytes memory l1ValidatorRegistrationMessage =
                ValidatorMessages.packL1ValidatorRegistrationMessage(validationID, true);
            _mockGetPChainWarpMessage(l1ValidatorRegistrationMessage, true);
            app.completeValidatorRegistration(0);
            vm.warp(vm.getBlockTimestamp() + 1);
        }

        uint64 expirationTime1 = uint64(block.timestamp + 1);
        // solhint-disable func-named-parameters
        _setUpInitializeValidatorOnBehalfOfRegistration(
            DEFAULT_NODE_ID, L1_ID, weight, expirationTime1, DEFAULT_BLS_PUBLIC_KEY, address(100)
        );
    }

    function testCanRegisterUpToMaxValidatorPerEpoch() public {
        _upgrade();
        _grantRegisterRole(address(this));
        validatorManager = app;
        posValidatorManager = app;
        token = wcoq;
        uint64 weight = 56;

        deal(address(wcoq), address(this), 50000e24);
        token.approve(address(app), type(uint256).max);

        for (uint256 i = 0; i < 5; i++) {
            bytes memory node = abi.encodePacked(
                hex"1234567812345678123456781234567812345678123456781234567812345680",
                bytes1(uint8(i)) // Increment last byte
            );
            uint64 expirationTime = uint64(block.timestamp + 1 days);
            // solhint-disable func-named-parameters
            _setUpInitializeValidatorOnBehalfOfRegistration(
                node, L1_ID, weight, expirationTime, DEFAULT_BLS_PUBLIC_KEY, address(uint160(i))
            );
        }

        ValidatorRegistrationInput memory input;
        vm.expectRevert(CoqnetERC20TokenStakingManager.ValidatorRegistrationExceeded.selector);
        app.initializeValidatorRegistrationOnBehalfOf(input, 0, 0, 0, validator);
    }

    function testCanRegisterOneValidationPerValidatorEveryTwoEpochs() public {
        _upgrade();
        _grantRegisterRole(address(this));
        validatorManager = app;
        posValidatorManager = app;
        token = wcoq;
        uint64 weight = 56;

        deal(address(wcoq), address(this), 50000e24);
        token.approve(address(app), type(uint256).max);

        uint64 expirationTime = uint64(block.timestamp + 1 days);
        // solhint-disable func-named-parameters
        bytes32 validationID = _setUpInitializeValidatorOnBehalfOfRegistration(
            DEFAULT_NODE_ID, L1_ID, weight, expirationTime, DEFAULT_BLS_PUBLIC_KEY, validator
        );

        bytes memory l1ValidatorRegistrationMessage =
            ValidatorMessages.packL1ValidatorRegistrationMessage(validationID, true);
        _mockGetPChainWarpMessage(l1ValidatorRegistrationMessage, true);
        app.completeValidatorRegistration(0);

        // retry within current period
        ValidatorRegistrationInput memory input;
        vm.expectRevert(CoqnetERC20TokenStakingManager.MustWaitOneEpoch.selector);
        app.initializeValidatorRegistrationOnBehalfOf(input, 0, 0, 0, validator);

        bytes memory node =
            bytes(hex"1234567812345678123456781234567812345678123456781234567812345679");

        // retry upon prev epoch ending
        vm.warp((block.timestamp + 30 days));
        vm.expectRevert(CoqnetERC20TokenStakingManager.MustWaitOneEpoch.selector);
        app.initializeValidatorRegistrationOnBehalfOf(input, 0, 0, 0, validator);
        expirationTime = uint64(block.timestamp + 1);
        // make an epoch with some validators
        _setUpInitializeValidatorOnBehalfOfRegistration(
            node, L1_ID, weight, expirationTime, DEFAULT_BLS_PUBLIC_KEY, address(100000)
        );

        node = bytes(hex"1234567812345678123456781234567812345678123456781234567812345680");
        // retry upon +1 period ending (1 epoch after the last registration)
        expirationTime = uint64(block.timestamp + 30 days + 1);
        // solhint-disable func-named-parameters
        _setUpInitializeValidatorOnBehalfOfRegistration(
            node, L1_ID, weight, expirationTime, DEFAULT_BLS_PUBLIC_KEY, validator
        );
    }

    function testStartsANewValidationEpoch() public {
        _upgrade();
        _grantRegisterRole(address(this));

        token = wcoq;
        uint64 weight = 56;
        deal(address(wcoq), address(this), 10000e24);
        token.approve(address(app), _weightToValue(weight));
        // solhint-disable func-named-parameters
        bytes32 validationID = _setUpInitializeValidatorOnBehalfOfRegistration(
            DEFAULT_NODE_ID, L1_ID, weight, DEFAULT_EXPIRY, DEFAULT_BLS_PUBLIC_KEY, validator
        );

        CoqnetERC20TokenStakingManager.ValidationEpoch memory epoch = app.getValidationEpoch(1);
        assertEq(epoch.epoch, 1);
        assertEq(epoch.startTime, block.timestamp);
        assertEq(epoch.endTime, block.timestamp + 30 days);

        bytes32 lastValidationId = app.getLastValidationID(validator);
        assertEq(lastValidationId, validationID);
    }

    function testOnlyAdminCanSetMaxValidators() public {
        _upgrade();
        vm.expectRevert();
        app.setMaxValidators(10);

        vm.prank(validatorOwner);
        app.setMaxValidators(10);

        bytes32 maxValidatorsSlot = bytes32(uint256(COQNET_METRICS_STORAGE_LOCATION) + 1);
        uint256 newMaxValidators = uint256(vm.load(address(app), maxValidatorsSlot));

        assertEq(newMaxValidators, 10);
    }

    function testCannotExceedMaxRegistrations() public {
        _upgrade();
        _grantRegisterRole(register);

        vm.store(address(app), COQNET_METRICS_STORAGE_LOCATION, bytes32(abi.encode(11)));
        vm.expectRevert(CoqnetERC20TokenStakingManager.ValidatorRegistrationExceeded.selector);
        ValidatorRegistrationInput memory input;
        app.initializeValidatorRegistration(input, 0, 0, 0);

        vm.prank(register);
        vm.expectRevert(CoqnetERC20TokenStakingManager.ValidatorRegistrationExceeded.selector);
        app.initializeValidatorRegistrationOnBehalfOf(input, 0, 0, 0, validator);
    }

    function testInitializeValidatorRegistrationOnBehalfOf() public {
        _upgrade();
        _grantRegisterRole(address(this));
        bytes32 maxValidatorsSlot = bytes32(uint256(COQNET_METRICS_STORAGE_LOCATION) + 1);
        vm.store(address(app), maxValidatorsSlot, bytes32(abi.encode(10)));
        token = wcoq;

        uint64 weight = 56;
        deal(address(wcoq), address(this), 10000e24);
        token.approve(address(app), _weightToValue(weight));
        // solhint-disable func-named-parameters
        _setUpInitializeValidatorOnBehalfOfRegistration(
            DEFAULT_NODE_ID, L1_ID, weight, DEFAULT_EXPIRY, DEFAULT_BLS_PUBLIC_KEY, validator
        );
    }

    function _setUpInitializeValidatorOnBehalfOfRegistration(
        bytes memory nodeID,
        bytes32 l1ID,
        uint64 weight,
        uint64 registrationExpiry,
        bytes memory blsPublicKey,
        address validator_
    ) internal returns (bytes32 validationID) {
        (validationID,) = ValidatorMessages.packRegisterL1ValidatorMessage(
            ValidatorMessages.ValidationPeriod({
                nodeID: nodeID,
                subnetID: l1ID,
                blsPublicKey: blsPublicKey,
                registrationExpiry: registrationExpiry,
                remainingBalanceOwner: DEFAULT_P_CHAIN_OWNER,
                disableOwner: DEFAULT_P_CHAIN_OWNER,
                weight: weight
            })
        );
        (, bytes memory registerL1ValidatorMessage) = ValidatorMessages
            .packRegisterL1ValidatorMessage(
            ValidatorMessages.ValidationPeriod({
                subnetID: l1ID,
                nodeID: nodeID,
                blsPublicKey: blsPublicKey,
                registrationExpiry: registrationExpiry,
                remainingBalanceOwner: DEFAULT_P_CHAIN_OWNER,
                disableOwner: DEFAULT_P_CHAIN_OWNER,
                weight: weight
            })
        );
        vm.warp(registrationExpiry - 1);
        _mockSendWarpMessage(registerL1ValidatorMessage, bytes32(0));

        // _beforeSend(_weightToValue(weight), address(app));
        vm.expectEmit(true, true, true, true, address(app));
        emit ValidationPeriodCreated(validationID, bytes32(0), weight, nodeID, registrationExpiry);

        _initializeValidatorRegistrationOnBehalfOf(
            ValidatorRegistrationInput({
                nodeID: nodeID,
                blsPublicKey: blsPublicKey,
                remainingBalanceOwner: DEFAULT_P_CHAIN_OWNER,
                disableOwner: DEFAULT_P_CHAIN_OWNER,
                registrationExpiry: registrationExpiry
            }),
            validator_,
            weight
        );
    }

    function _upgrade() internal {
        PoSValidatorManagerSettings memory settings = _defaultCoqPoSSettings();
        settings.rewardCalculator = new RewardsCalculator(1000);
        CoqnetERC20TokenStakingManager impl =
            new CoqnetERC20TokenStakingManager(ICMInitializable.Disallowed);
        bytes memory data = abi.encodeCall(
            app.initialize, (settings, IERC20Mintable(address(wcoq)), validatorOwner)
        );

        vm.startPrank(validatorOwner);
        admin.upgradeAndCall(proxy, address(impl), data);
        vm.stopPrank();
    }

    function _grantRegisterRole(
        address to
    ) internal {
        vm.startPrank(validatorOwner);
        app.grantRole(app.REGISTER_ROLE(), to);
        vm.stopPrank();
    }

    function _setUp() internal override returns (IValidatorManager) {
        app = new CoqnetERC20TokenStakingManager(ICMInitializable.Allowed);
        token = new WCOQ();
        PoSValidatorManagerSettings memory defaultPoSSettings = _defaultPoSSettings();

        app.initialize(defaultPoSSettings, IERC20Mintable(address(token)), validatorOwner);
        validatorManager = app;
        posValidatorManager = app;
        return app;
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

    function _initializeValidatorRegistration(
        ValidatorRegistrationInput memory registrationInput,
        uint16 delegationFeeBips,
        uint64 minStakeDuration,
        uint256 stakeAmount
    ) internal virtual override returns (bytes32) {
        return app.initializeValidatorRegistration(
            registrationInput, delegationFeeBips, minStakeDuration, stakeAmount
        );
    }

    function _initializeValidatorOnBehalfOfRegistration(
        ValidatorRegistrationInput memory registrationInput,
        uint16 delegationFeeBips,
        uint64 minStakeDuration,
        uint256 stakeAmount
    ) internal virtual returns (bytes32) {
        return app.initializeValidatorRegistration(
            registrationInput, delegationFeeBips, minStakeDuration, stakeAmount
        );
    }

    function _initializeValidatorRegistrationOnBehalfOf(
        ValidatorRegistrationInput memory input,
        address validator_,
        uint64 weight
    ) internal virtual returns (bytes32) {
        return app.initializeValidatorRegistrationOnBehalfOf(
            input, DEFAULT_DELEGATION_FEE_BIPS, 30 days, _weightToValue(weight), validator_
        );
    }

    function _initializeValidatorRegistration(
        ValidatorRegistrationInput memory input,
        uint64 weight
    ) internal virtual override returns (bytes32) {
        return app.initializeValidatorRegistration(
            input,
            DEFAULT_DELEGATION_FEE_BIPS,
            DEFAULT_MINIMUM_STAKE_DURATION,
            _weightToValue(weight)
        );
    }

    function _beforeSend(uint256 amount, address spender) internal override {
        deal(address(token), address(this), amount);
        token.approve(spender, amount);
        token.transfer(spender, amount);

        // ERC20 tokens need to be pre-approved
        vm.startPrank(spender);
        token.approve(address(app), amount);
        vm.stopPrank();
    }

    function _expectStakeUnlock(address account, uint256 amount) internal override {
        vm.expectCall(address(token), abi.encodeCall(IERC20.transfer, (account, amount)));
    }

    function _expectRewardIssuance(address account, uint256 amount) internal override {
        vm.expectCall(address(token), abi.encodeCall(IERC20Mintable.mint, (account, amount)));
    }

    function _getStakeAssetBalance(
        address account
    ) internal view override returns (uint256) {
        return token.balanceOf(account);
    }

    function _weightToValue(
        uint64 weight
    ) internal pure override returns (uint256) {
        return uint256(weight) * 1e25;
    }

    function _defaultCoqPoSSettings() internal pure returns (PoSValidatorManagerSettings memory) {
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

// contract POSValidatorManagerTestMocked is PoSValidatorManagerTests {}
