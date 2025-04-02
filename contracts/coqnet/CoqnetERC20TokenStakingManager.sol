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
        uint256 duration;
        bytes32[] validationIDs;
    }

    struct CoqnetMetricsStorage {
        uint256 _validatorsRegistered;
        uint256 _maxValidators;
        uint256 _maxNodesPerValidator;
        mapping(address => uint256) _nodesPerValidator;
        mapping(address => bytes32) _lastValidationId;
        mapping(bytes32 => uint256) _validationIdEpoch;
        bytes32[] _activeValidationIds;
        ValidationEpoch _epoch;
        mapping(uint256 => ValidationEpoch) _epochs;
        uint256 currentEpoch;
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
        CoqnetMetricsStorage storage $metrics = _getCoqnetMetricsStorage();

        validationID = _initializeValidatorRegistration(
            registrationInput, delegationFeeBips, minStakeDuration, stakeAmount
        );

        $metrics._lastValidationId[_msgSender()] = validationID;
        $metrics._activeValidationIds.push(validationID);
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
        CoqnetMetricsStorage storage $metrics = _getCoqnetMetricsStorage();

        validationID = _initializeValidatorRegistration(
            registrationInput, delegationFeeBips, minStakeDuration, stakeAmount
        );

        $._posValidatorInfo[validationID].owner = validator;
        $._rewardRecipients[validationID] = validator;

        $metrics._lastValidationId[validator] = validationID;
        $metrics._activeValidationIds.push(validationID);
    }

    function _checkRegistrationEpoch(
        address validator
    ) internal view {
        ValidatorManagerStorage storage $$ = _getValidatorManagerStorage();
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        bytes32 validationID = $._lastValidationId[validator];
        console.log(">>> ID", uint256(validationID));
        if (!_isPoSValidator(validationID)) return;

        uint256 endedAt = $$._validationPeriods[validationID].endedAt;
        uint256 startedAt = $$._validationPeriods[validationID].startedAt;
        console.log("reg epoch >>>>", block.timestamp, startedAt, endedAt);

        if (startedAt == 0) revert MustWaitOneEpoch(); // waiting for confirmation acknowledgment
        if (endedAt == 0) revert MustWaitOneEpoch(); //yet finalized
        if (block.timestamp - endedAt <= $._epoch.duration) revert MustWaitOneEpoch(); //finalized

        //Okay can register another node
    }

    function _checkActiveValidationIDs() internal {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        if ($._activeValidationIds.length < MAX_EPOCH_VALIDATORS) return;

        (uint256 i, bytes32 validationID) = _findInactiveValidationID();
        if (validationID == 0) revert ValidatorRegistrationExceeded();

        // drop the inactive validationID
        _initializeEndPoSValidationOnBehalfOf(validationID);
        // clean up from activeValidationIds
        $._activeValidationIds[i] = $._activeValidationIds[$._activeValidationIds.length - 1];
        $._activeValidationIds.pop();
    }

    function _findInactiveValidationID()
        internal
        view
        returns (uint256 index, bytes32 inactiveValidationID)
    {
        PoSValidatorManagerStorage storage $$ = _getPoSValidatorManagerStorage();
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();

        for (uint256 i = 0; i < $._activeValidationIds.length; i++) {
            bytes32 validationID = $._activeValidationIds[i];
            uint256 elapsedUptime = block.timestamp - $._epoch.startTime;
            uint256 expectedUptime = (elapsedUptime * UPTIME_THRESHOLD_PERCENTAGE);
            uint256 uptimeSeconds = $$._posValidatorInfo[validationID].uptimeSeconds;
            // Check if the validator's uptime is below the expected uptime
            // 100 % of the time
            if (uptimeSeconds * 100 < expectedUptime) {
                return (i, validationID);
            }
        }

        return (0, bytes32(0));
    }

    function _checkAndUpdateValidationEpoch() internal {
        console.log(">>>attempting drop");
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        console.log(">>>", block.timestamp, $._epoch.endTime);
        if (block.timestamp < $._epoch.endTime) return;

        // drop the inactive validationIDs
        if ($._activeValidationIds.length > 0) {
            for (uint256 i = 0; i < $._activeValidationIds.length; i++) {
                console.log(">>>droping inactive validators");
                bytes32 validationID = $._activeValidationIds[i];
                _initializeEndPoSValidationOnBehalfOf(validationID);
                $._activeValidationIds.pop();
            }
        }
        console.log(">>>new epoch");
        // start next epoch
        $._epoch.epoch++;
        $._epoch.duration = 30 days;
        $._epoch.startTime = block.timestamp;
        $._epoch.endTime = block.timestamp + 30 days;
    }

    function _initializeEndPoSValidationOnBehalfOf(
        bytes32 validationID
    ) internal {
        PoSValidatorManagerStorage storage $$ = _getPoSValidatorManagerStorage();
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        // take ownership temporarily for EndPoSValidation On behalf
        address owner = $$._posValidatorInfo[validationID].owner;
        ValidatorStatus status = $._validationPeriods[validationID].status;
        if (status != ValidatorStatus.Active) return;

        $$._posValidatorInfo[validationID].owner = _msgSender();
        // endValidation On behalf whether eligible or not for rewards
        _initializeEndPoSValidation(validationID, false, 0, owner);
        // restore ownership
        $$._posValidatorInfo[validationID].owner = owner;
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

        CoqnetMetricsStorage storage $metrics = _getCoqnetMetricsStorage();
        if ($metrics._nodesPerValidator[_msgSender()] > 0) {
            --$metrics._nodesPerValidator[_msgSender()];
        }

        return super._initializeEndPoSValidation(
            validationID, includeUptimeProof, messageIndex, rewardRecipient
        );
    }

    function _initializeEndValidation(
        bytes32 validationID
    ) internal override returns (Validator memory validator) {
        CoqnetMetricsStorage storage $metrics = _getCoqnetMetricsStorage();
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();

        super._initializeEndValidation(validationID);

        // end at current time or epoch end time
        uint256 endedAt =
            block.timestamp >= $metrics._epoch.endTime ? $metrics._epoch.endTime : block.timestamp;

        $._validationPeriods[validationID].endedAt = uint64(endedAt);
        console.log(">>>>>e", $metrics._epoch.endTime);
        console.log(">>>>>", endedAt);
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
    function getValidationEpoch() external view returns (ValidationEpoch memory epoch) {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        epoch = $._epoch;
    }

    // @todo: remove this function
    function getLastValidationID(
        address validator
    ) external view returns (bytes32 epoch) {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        return $._lastValidationId[validator];
    }

    // @todo: remove this function
    function getActiveValidationIDs()
        external
        view
        returns (bytes32[] memory activeValidationIDs)
    {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        return $._activeValidationIds;
    }
}
