// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {
    ERC20Burnable, ERC20
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract WCOQ is ERC20Burnable, AccessControl {
    using SafeERC20 for ERC20;

    string private constant _TOKEN_NAME = "Wrapped Coqnet Token";
    string private constant _TOKEN_SYMBOL = "WCOQ";
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    address public constant OWNER = 0xb4f69B081E784d50FF0a1ec1d46570ABAC7a221d;

    constructor() ERC20(_TOKEN_NAME, _TOKEN_SYMBOL) {
        _mint(OWNER, 1e28);
        _grantRole(DEFAULT_ADMIN_ROLE, OWNER);
    }

    function mint(address account, uint256 amount) external onlyRole(ISSUER_ROLE) {
        _mint(account, amount);
    }
}
