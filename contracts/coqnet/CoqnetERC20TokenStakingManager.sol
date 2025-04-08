// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {PoSValidatorManager} from "@validator-manager/PoSValidatorManager.sol";
import {PoSValidatorManagerSettings} from "@validator-manager/interfaces/IPoSValidatorManager.sol";
import {
    ValidatorRegistrationInput,
    ValidatorStatus,
    Validator
} from "@validator-manager/interfaces/IValidatorManager.sol";
import {IERC20TokenStakingManager} from
    "@validator-manager/interfaces/IERC20TokenStakingManager.sol";
import {IERC20Mintable} from "@validator-manager/interfaces/IERC20Mintable.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {SafeERC20TransferFrom} from "@utilities/SafeERC20TransferFrom.sol";
import {Initializable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/access/AccessControlUpgradeable.sol";

import "forge-std/console.sol";
/**
 * @dev Implementation of the {IERC20TokenStakingManager} interface.
 *
 * @custom:security-contact https://github.com/ava-labs/icm-contracts/blob/main/SECURITY.md
 */

contract CoqnetERC20TokenStakingManager is
    Initializable,
    AccessControlUpgradeable,
    PoSValidatorManager,
    IERC20TokenStakingManager
{
    using SafeERC20 for IERC20Mintable;
    using SafeERC20TransferFrom for IERC20Mintable;

    // solhint-disable private-vars-leading-underscore
    /// @custom:storage-location erc7201:avalanche-icm.storage.ERC20TokenStakingManager
    struct ERC20TokenStakingManagerStorage {
        IERC20Mintable _token;
        uint8 _tokenDecimals;
    }

    struct ValidationEpoch {
        uint256 epoch;
        uint256 startTime;
        uint256 endTime;
        bytes32[] validationIDs;
    }

    struct CoqnetMetricsStorage {
        uint256 _validatorsRegistered;
        uint256 _maxValidators;
        uint256 _maxNodesPerValidator;
        mapping(address => uint256) _nodesPerValidator;
        mapping(address => bytes32) _lastValidationId;
        mapping(bytes32 => uint256) _validationIdEpoch;
        mapping(uint256 => ValidationEpoch) _epochs;
        uint256 _currentEpoch;
    }

    // solhint-enable private-vars-leading-underscore

    // keccak256(abi.encode(uint256(keccak256("avalanche-icm.storage.ERC20TokenStakingManager")) - 1)) & ~bytes32(uint256(0xff));

    bytes32 public constant ERC20_STAKING_MANAGER_STORAGE_LOCATION =
        0x6e5bdfcce15e53c3406ea67bfce37dcd26f5152d5492824e43fd5e3c8ac5ab00;

    // keccak256(abi.encode(uint256(keccak256("coqnet.storage.CoqnetMetricsStorage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 public constant COQNET_METRICS_STORAGE_LOCATION =
        0x15948f25c54ec2687bf5cd60236db66c5e145b7bc4b04f89902ccb02ee706d00;

    bytes32 public constant REGISTER_ROLE = keccak256("REGISTER_ROLE");

    uint256 public constant UPTIME_THRESHOLD_PERCENTAGE = 80;
    uint256 public constant MAX_EPOCH_VALIDATORS = 5;
    uint256 public constant EPOCH_DURATION = 30 days;

    error InvalidTokenAddress(address tokenAddress);
    error ValidatorRegistrationExceeded();
    error MustWaitOneEpoch();

    // solhint-disable ordering

    function _getERC20StakingManagerStorage()
        private
        pure
        returns (ERC20TokenStakingManagerStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := ERC20_STAKING_MANAGER_STORAGE_LOCATION
        }
    }

    // solhint-disable ordering
    function _getCoqnetMetricsStorage() private pure returns (CoqnetMetricsStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := COQNET_METRICS_STORAGE_LOCATION
        }
    }

    modifier checkRegistration(
        address validator
    ) {
        _checkAndUpdateValidationEpoch();
        _checkRegistrationEpoch(validator);
        _checkActiveValidationIDs();
        _;
    }

    constructor(
        ICMInitializable init
    ) {
        if (init == ICMInitializable.Disallowed) {
            _disableInitializers();
        }
    }

    /**
     * @notice Initialize the ERC20 token staking manager
     * @dev Uses reinitializer(2) on the PoS staking contracts to make sure after migration from PoA, the PoS contracts can reinitialize with its needed values.
     * @param settings Initial settings for the PoS validator manager
     * @param token The ERC20 token to be staked
     */
    function initialize(
        PoSValidatorManagerSettings calldata settings,
        IERC20Mintable token,
        address admin
    ) external reinitializer(10) {
        __ERC20TokenStakingManager_init(settings, token);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // CoqnetMetricsStorage storage $metrics = _getCoqnetMetricsStorage();

        // ++$metrics._epoch.duration;
        // $metrics._epoch.duration = 30 days;
        // $metrics._epoch.startTime = block.timestamp;
        // $metrics._epoch.endTime = block.timestamp + 30 days;
    }

    // solhint-disable-next-line func-name-mixedcase
    function __ERC20TokenStakingManager_init(
        PoSValidatorManagerSettings calldata settings,
        IERC20Mintable token
    ) internal onlyInitializing {
        __POS_Validator_Manager_init(settings);
        __ERC20TokenStakingManager_init_unchained(token);
    }

    // solhint-disable-next-line func-name-mixedcase
    function __ERC20TokenStakingManager_init_unchained(
        IERC20Mintable token
    ) internal onlyInitializing {
        ERC20TokenStakingManagerStorage storage $ = _getERC20StakingManagerStorage();
        if (address(token) == address(0)) {
            revert InvalidTokenAddress(address(token));
        }
        $._token = token;
    }

    /**
     * @notice See {IERC20TokenStakingManager-initializeValidatorRegistration}
     */
    function initializeValidatorRegistration(
        ValidatorRegistrationInput calldata registrationInput,
        uint16 delegationFeeBips,
        uint64 minStakeDuration,
        uint256 stakeAmount
    )
        external
        nonReentrant
        onlyRole(REGISTER_ROLE)
        checkRegistration(_msgSender())
        returns (bytes32 validationID)
    {
        validationID = _initializeValidatorRegistration(
            registrationInput, delegationFeeBips, minStakeDuration, stakeAmount
        );

        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        $._epochs[$._currentEpoch].validationIDs.push(validationID);
        $._lastValidationId[_msgSender()] = validationID;
        $._validationIdEpoch[validationID] = $._currentEpoch;
    }

    /**
     * @notice Allows a register to initiate registration of a validator on behalf of a validator
     */
    function initializeValidatorRegistrationOnBehalfOf(
        ValidatorRegistrationInput calldata registrationInput,
        uint16 delegationFeeBips,
        uint64 minStakeDuration,
        uint256 stakeAmount,
        address validator
    )
        external
        nonReentrant
        onlyRole(REGISTER_ROLE)
        checkRegistration(validator)
        returns (bytes32 validationID)
    {
        PoSValidatorManagerStorage storage $ = _getPoSValidatorManagerStorage();

        validationID = _initializeValidatorRegistration(
            registrationInput, delegationFeeBips, minStakeDuration, stakeAmount
        );

        $._posValidatorInfo[validationID].owner = validator;
        $._rewardRecipients[validationID] = validator;

        CoqnetMetricsStorage storage $metrics = _getCoqnetMetricsStorage();
        $metrics._epochs[$metrics._currentEpoch].validationIDs.push(validationID);
        $metrics._lastValidationId[validator] = validationID;
        $metrics._validationIdEpoch[validationID] = $metrics._currentEpoch;
    }

    function _checkRegistrationEpoch(
        address validator
    ) internal view {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        bytes32 validationID = $._lastValidationId[validator];
        if (!_isPoSValidator(validationID)) return;

        ValidationEpoch storage epoch = $._epochs[$._currentEpoch];
        ValidationEpoch storage previousEpoch = $._epochs[$._currentEpoch - 1];

        // has an active validationID
        if (_findValidationID(epoch.validationIDs, validationID)) {
            revert MustWaitOneEpoch();
        }
        // had an active validationID in the previous epoch
        if (_findValidationID(previousEpoch.validationIDs, validationID)) {
            revert MustWaitOneEpoch();
        }

        // Okay can register a node
    }

    function _findValidationID(
        bytes32[] memory validationIDs,
        bytes32 validationID
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < validationIDs.length; i++) {
            if (validationIDs[i] == validationID) return true;
        }

        return false;
    }

    function _checkActiveValidationIDs() internal {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        ValidationEpoch storage epoch = $._epochs[$._currentEpoch];
        // if the epoch is not full, allow registration
        if (epoch.validationIDs.length < MAX_EPOCH_VALIDATORS) return;

        console.log("finding");
        (uint256 i, bytes32 validationID) = _findInactiveValidationID(epoch);
        // all validators are active
        if (validationID == 0) revert ValidatorRegistrationExceeded();
        console.log("found");
        console.logUint(i);
        // remove the inactive validator
        epoch.validationIDs[i] = epoch.validationIDs[epoch.validationIDs.length - 1];
        epoch.validationIDs.pop();
    }

    function _findInactiveValidationID(
        ValidationEpoch memory epoch
    ) internal view returns (uint256 index, bytes32 inactiveValidationID) {
        PoSValidatorManagerStorage storage $$ = _getPoSValidatorManagerStorage();
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();

        for (uint256 i = 0; i < epoch.validationIDs.length; i++) {
            bytes32 validationID = epoch.validationIDs[i];
            Validator memory validator = $._validationPeriods[validationID];
            ValidatorStatus status = validator.status;
            if (status == ValidatorStatus.Unknown || status == ValidatorStatus.Invalidated) {
                return (i, validationID);
            }
            if (status != ValidatorStatus.Active) continue;

            uint256 elapsedUptime = block.timestamp - validator.startedAt;
            uint256 expectedUptime = (elapsedUptime * UPTIME_THRESHOLD_PERCENTAGE);
            uint256 uptimeSeconds = $$._posValidatorInfo[validationID].uptimeSeconds;
            // Check if the validator's uptime is below the expected uptime
            // 100 % of the time
            console.log("uptime calc");
            console.logUint(uptimeSeconds);
            console.logUint(expectedUptime);
            if ((uptimeSeconds * 100) < expectedUptime) {
                return (i, validationID);
            }
        }

        return (0, bytes32(0));
    }

    function _checkAndUpdateValidationEpoch() internal {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        ValidationEpoch storage epoch = $._epochs[$._currentEpoch];
        if (block.timestamp < epoch.endTime && epoch.startTime > 0) return;

        // start next epoch
        ValidationEpoch storage nextEpoch = $._epochs[++$._currentEpoch];
        nextEpoch.epoch = $._currentEpoch;
        nextEpoch.startTime = block.timestamp;
        nextEpoch.endTime = block.timestamp + EPOCH_DURATION;
    }

    /**
     * @notice See {IERC20TokenStakingManager-initializeDelegatorRegistration}
     */
    //solhint-disable no-empty-blocks
    function initializeDelegatorRegistration(
        bytes32 validationID,
        uint256 delegationAmount
    ) external nonReentrant returns (bytes32) {}

    /**
     * @notice Returns the ERC20 token being staked
     */
    function erc20() external view returns (IERC20Mintable) {
        return _getERC20StakingManagerStorage()._token;
    }

    /**
     * @notice See {PoSValidatorManager-_lock}
     * Note: Must be guarded with reentrancy guard for safe transfer from.
     */
    function _lock(
        uint256 value
    ) internal virtual override returns (uint256) {
        return _getERC20StakingManagerStorage()._token.safeTransferFrom(value);
    }

    /**
     * @notice See {PoSValidatorManager-_unlock}
     * Note: Must be guarded with reentrancy guard for safe transfer.
     */
    function _unlock(address to, uint256 value) internal virtual override {
        _getERC20StakingManagerStorage()._token.safeTransfer(to, value);
    }

    /**
     * @notice See {PoSValidatorManager-_reward}
     */
    function _reward(address account, uint256 amount) internal virtual override {
        _getERC20StakingManagerStorage()._token.mint(account, amount);
    }

    function _initializeEndPoSValidation(
        bytes32 validationID,
        bool includeUptimeProof,
        uint32 messageIndex,
        address rewardRecipient
    ) internal override (PoSValidatorManager) returns (bool) {
        if (!_isPoSValidator(validationID)) {
            revert UnauthorizedOwner(_msgSender());
        }

        bool rewarded = super._initializeEndPoSValidation(
            validationID, includeUptimeProof, messageIndex, rewardRecipient
        );

        CoqnetMetricsStorage storage $metrics = _getCoqnetMetricsStorage();
        uint256 epoch = $metrics._validationIdEpoch[validationID];
        if (!_findValidationID($metrics._epochs[epoch].validationIDs, validationID)) {
            // remove its rewards if ended up inactive
            PoSValidatorManagerStorage storage $ = _getPoSValidatorManagerStorage();
            $._redeemableValidatorRewards[validationID] = 0;
        }

        return rewarded;
    }

    function _initializeEndValidation(
        bytes32 validationID
    ) internal override returns (Validator memory validator) {
        CoqnetMetricsStorage storage $metrics = _getCoqnetMetricsStorage();
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();

        super._initializeEndValidation(validationID);

        // end validation at its epoch end time or current block time
        uint256 epochEndTime = $metrics._epochs[$metrics._currentEpoch].endTime;
        uint256 endedAt = block.timestamp >= epochEndTime ? epochEndTime : block.timestamp;

        $._validationPeriods[validationID].endedAt = uint64(endedAt);
        validator = $._validationPeriods[validationID];
    }

    function getPoSValidators(
        bytes32[] calldata validationIDs
    ) external view returns (address[] memory owners) {
        PoSValidatorManagerStorage storage $ = _getPoSValidatorManagerStorage();

        owners = new address[](validationIDs.length);

        for (uint256 i = 0; i < validationIDs.length; i++) {
            owners[i] = $._posValidatorInfo[validationIDs[i]].owner;
        }

        return owners;
    }

    function setMaxValidators(
        uint256 maxValidators
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        $._maxValidators = maxValidators;
    }

    function setMaxNodesPerValidator(
        uint256 maxNodesPerValidator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        $._maxNodesPerValidator = maxNodesPerValidator;
    }

    // @todo: remove this function
    function getValidationEpoch(
        uint256 epochIdx
    ) external view returns (ValidationEpoch memory epoch) {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        epoch = $._epochs[epochIdx];
    }

    // @todo: remove this function
    function getLastValidationID(
        address validator
    ) external view returns (bytes32 epoch) {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        return $._lastValidationId[validator];
    }
    // @todo: remove this function

    function getCurrentEpochIndex() external view returns (uint256) {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        return $._currentEpoch;
    }
}
