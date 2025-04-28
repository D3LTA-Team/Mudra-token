// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
/**
 * @title MudraToken
 * @dev ERC20 token for the Mudra platform
 * Includes global whitelisting system to control token transfers
 * Supports blacklisting/freezing of specific addresses for compliance
 * Uses OpenZeppelin's ERC20 implementation with added minting and burning capabilities
 * Owner has full control and can assign/remove roles to other addresses
 */

contract MudraToken is ERC20, ERC20Burnable, Ownable, ReentrancyGuard, Pausable {
    // Decimals (overriding ERC20's default 18)
    uint8 private constant DECIMALS = 6;

    // Global whitelisting
    mapping(address => bool) public isWhitelisted;
    bool public whitelistingEnabled = true;

    // Blacklisting/freezing
    mapping(address => bool) public isBlacklisted;

    // Roles
    mapping(address => bool) public isWhitelister;
    mapping(address => bool) public isBlacklister;

    // Events
    event WhitelisterStatusUpdated(address indexed whitelister, bool status);
    event BlacklisterStatusUpdated(address indexed blacklister, bool status);
    event AddressWhitelisted(address indexed account, bool status);
    event AddressBlacklisted(address indexed account, bool status);
    event WhitelistStatusUpdated(bool status);

    // Errors
    error InvalidWhitelisterAddress();
    error InvalidBlacklisterAddress();
    error InvalidAddress();
    error InvalidMintAmount();
    error InvalidBurnAmount();
    error InvalidSenderWhitelisted();
    error InvalidRecipientWhitelisted();
    error AccountBlacklisted();
    error InvalidApprove();

    /**
     * @dev Constructor
     * @param tokenName Name of the token
     * @param tokenSymbol Symbol of the token
     * @param initialOwner Address of the contract owner
     */
    constructor(string memory tokenName, string memory tokenSymbol, address initialOwner)
        ERC20(tokenName, tokenSymbol)
        Ownable(initialOwner)
    {
        require(initialOwner != address(0), "Owner cannot be zero address");

        // Set owner as whitelister and blacklister by default
        isWhitelister[initialOwner] = true;
        isBlacklister[initialOwner] = true;

        // Whitelist the owner by default
        isWhitelisted[initialOwner] = true;

        emit WhitelisterStatusUpdated(initialOwner, true);
        emit BlacklisterStatusUpdated(initialOwner, true);
        emit AddressWhitelisted(initialOwner, true);
    }

    /**
     * @dev Override decimals to return 6 instead of ERC20's default 18
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @dev Modifier to check if caller is a whitelister
     */
    modifier onlyWhitelister() {
        require(isWhitelister[msg.sender] || msg.sender == owner(), InvalidWhitelisterAddress());
        _;
    }

    /**
     * @dev Modifier to check if caller is a blacklister
     */
    modifier onlyBlacklister() {
        require(isBlacklister[msg.sender] || msg.sender == owner(), InvalidBlacklisterAddress());
        _;
    }

    /**
     * @dev Set whitelister status
     * @param whitelister Address to update
     * @param status New whitelister status
     */
    function setWhitelister(address whitelister, bool status) external onlyOwner {
        require(whitelister != address(0), InvalidAddress());
        isWhitelister[whitelister] = status;
        emit WhitelisterStatusUpdated(whitelister, status);
    }

    /**
     * @dev Set blacklister status
     * @param blacklister Address to update
     * @param status New blacklister status
     */
    function setBlacklister(address blacklister, bool status) external onlyOwner {
        require(blacklister != address(0), InvalidAddress());
        isBlacklister[blacklister] = status;
        emit BlacklisterStatusUpdated(blacklister, status);
    }

    /**
     * @dev Toggle whitelisting functionality on/off
     * @param status Whether whitelisting should be enabled
     */
    function setWhitelistingEnabled(bool status) external onlyOwner {
        whitelistingEnabled = status;
        emit WhitelistStatusUpdated(status);
    }

    /**
     * @dev Set whitelist status for an address
     * @param account Address to update
     * @param status New whitelist status
     */
    function setWhitelisted(address account, bool status) external onlyWhitelister {
        require(account != address(0), InvalidAddress());
        isWhitelisted[account] = status;
        emit AddressWhitelisted(account, status);
    }

    /**
     * @dev Blacklist or unblacklist an address
     * @param account Address to update
     * @param status Blacklist status (true to blacklist, false to unblacklist)
     */
    function setBlacklisted(address account, bool status) external onlyBlacklister {
        require(account != address(0), InvalidAddress());
        isBlacklisted[account] = status;
        emit AddressBlacklisted(account, status);
    }

    /**
     * @dev Batch whitelist addresses
     * @param accounts Array of addresses to whitelist
     * @param status New whitelist status
     */
    function batchWhitelist(address[] calldata accounts, bool status) external onlyWhitelister {
        require(accounts.length <= 300, "Batch too large");
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) continue; // Skip zero addresses
            isWhitelisted[accounts[i]] = status;
            emit AddressWhitelisted(accounts[i], status);
        }
    }

    /**
     * @dev Batch blacklist addresses
     * @param accounts Array of addresses to blacklist
     * @param status New blacklist status
     */
    function batchBlacklist(address[] calldata accounts, bool status) external onlyBlacklister {
        require(accounts.length <= 300, "Batch too large");
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) continue; // Skip zero addresses
            isBlacklisted[accounts[i]] = status;
            emit AddressBlacklisted(accounts[i], status);
        }
    }

    /**
     * @dev Hook that is called before any token transfer
     * This includes minting and burning
     */
    function _update(address from, address to, uint256 amount) internal virtual override whenNotPaused {
        // Check for blacklisted addresses
        if (from != address(0)) {
            require(!isBlacklisted[from], AccountBlacklisted());
        }
        if (to != address(0)) {
            require(!isBlacklisted[to], AccountBlacklisted());
        }

        // Skip the whitelisting check for minting and burning operations
        if (from != address(0) && to != address(0)) {
            // Skip whitelisting check if disabled
            if (whitelistingEnabled) {
                require(isWhitelisted[from], InvalidSenderWhitelisted());
                require(isWhitelisted[to], InvalidRecipientWhitelisted());
            }
        }

        super._update(from, to, amount);
    }

    /**
     * @dev Mints new tokens using OpenZeppelin's _mint
     * @param to Address receiving the tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), InvalidAddress());
        require(amount > 0, InvalidMintAmount());
        require(!isBlacklisted[to], AccountBlacklisted());

        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from an account using OpenZeppelin's _burn
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) public override onlyOwner nonReentrant {
        require(amount > 0, InvalidBurnAmount());
        require(!isBlacklisted[from], AccountBlacklisted());

        // Skip allowance check for authorized burners
        if (msg.sender == owner()) {
            _burn(from, amount);
        } else {
            // Use the standard implementation which checks for allowance
            super.burnFrom(from, amount);
        }
    }

    /**
     * @dev Pause the token
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the token
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Override the approve function to mitigate the race condition vulnerability.
     *
     * We implement the suggested pattern to mitigate the race condition:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * @param spender The address which will spend the funds
     * @param amount The amount of tokens to be spent
     */
    function approve(address spender, uint256 amount) public virtual override whenNotPaused returns (bool) {
        address currentOwner = _msgSender();

        // Check that neither the owner nor spender is blacklisted
        require(!isBlacklisted[currentOwner], AccountBlacklisted());
        require(!isBlacklisted[spender], AccountBlacklisted());

        require(amount == 0 || allowance(currentOwner, spender) == 0, InvalidApprove());

        return super.approve(spender, amount);
    }
}
