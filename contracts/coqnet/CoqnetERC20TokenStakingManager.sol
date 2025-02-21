// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {PoSValidatorManager} from "@validator-manager/PoSValidatorManager.sol";
import {PoSValidatorManagerSettings} from "@validator-manager/interfaces/IPoSValidatorManager.sol";
import {ValidatorRegistrationInput} from "@validator-manager/interfaces/IValidatorManager.sol";
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

    struct CoqnetMetricsStorage {
        uint256 _validatorsRegistered;
        uint256 _maxValidators;
        uint256 _maxNodesPerValidator;
        mapping(address => uint256) _nodesPerValidator;
    }
    // solhint-enable private-vars-leading-underscore

    // keccak256(abi.encode(uint256(keccak256("avalanche-icm.storage.ERC20TokenStakingManager")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 public constant ERC20_STAKING_MANAGER_STORAGE_LOCATION =
        0x6e5bdfcce15e53c3406ea67bfce37dcd26f5152d5492824e43fd5e3c8ac5ab00;

    // keccak256(abi.encode(uint256(keccak256("coqnet.storage.CoqnetMetricsStorage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 public constant COQNET_METRICS_STORAGE_LOCATION =
        0x15948f25c54ec2687bf5cd60236db66c5e145b7bc4b04f89902ccb02ee706d00;

    bytes32 public constant REGISTER_ROLE = keccak256("REGISTER_ROLE");

    error InvalidTokenAddress(address tokenAddress);
    error ValidatorRegistrationExceeded();
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

    modifier checkRegistration() {
        CoqnetMetricsStorage storage $ = _getCoqnetMetricsStorage();
        if ($._validatorsRegistered >= $._maxValidators) {
            revert ValidatorRegistrationExceeded();
        }
        _;
        ++$._validatorsRegistered;
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
    ) external reinitializer(6) {
        __ERC20TokenStakingManager_init(settings, token);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        CoqnetMetricsStorage storage $metrics = _getCoqnetMetricsStorage();
        $metrics._maxNodesPerValidator = 3;
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
        checkRegistration
        returns (bytes32 validationID)
    {
        return _initializeValidatorRegistration(
            registrationInput, delegationFeeBips, minStakeDuration, stakeAmount
        );
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
        checkRegistration
        returns (bytes32 validationID)
    {
        CoqnetMetricsStorage storage $metrics = _getCoqnetMetricsStorage();
        if ($metrics._nodesPerValidator[validator] >= $metrics._maxNodesPerValidator) {
            revert ValidatorRegistrationExceeded();
        }

        ++$metrics._nodesPerValidator[validator];
        PoSValidatorManagerStorage storage $ = _getPoSValidatorManagerStorage();
        validationID = _initializeValidatorRegistration(
            registrationInput, delegationFeeBips, minStakeDuration, stakeAmount
        );
        $._posValidatorInfo[validationID].owner = validator;
        $._rewardRecipients[validationID] = validator;
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
    function _reward(address account, uint256 amount) internal virtual override {}

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
}
