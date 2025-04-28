// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.27;

// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// /**
//  * @title MudraPromotionalToken
//  * @dev ERC20 token specifically for airdrops and promotional activities
//  * Tokens can only be used for betting on the Mudra platform
//  * Cannot be transferred between users or sold on exchanges
//  * Uses OpenZeppelin's ERC20 implementation with added minting and burning capabilities
//  * Owner has full control and can assign/remove roles to other addresses
//  */
// contract MudraPromotionalToken is ERC20, ERC20Burnable, Ownable, ReentrancyGuard {
//     // Decimals (overriding ERC20's default 18)
//     uint8 private constant _decimals = 6;
    
//     // Global whitelisting - always enforced for promotional tokens
//     mapping(address => bool) public isWhitelisted;
    
//     // Roles
//     mapping(address => bool) public isMinter;
//     mapping(address => bool) public isBurner;
//     mapping(address => bool) public isWhitelister;
    
//     // Events
//     event MinterStatusUpdated(address indexed minter, bool status);
//     event BurnerStatusUpdated(address indexed burner, bool status);
//     event WhitelisterStatusUpdated(address indexed whitelister, bool status);
//     event AddressWhitelisted(address indexed account, bool status);
//     event TokensUsedForBetting(address indexed user, uint256 amount);
    
//     // Errors
//     error InvalidMinterAddress();
//     error InvalidBurnerAddress();
//     error InvalidWhitelisterAddress();
//     error InvalidAddress();
//     error InvalidMintAmount();
//     error InvalidBurnAmount();
//     error InvalidSenderWhitelisted();
//     error InvalidRecipientWhitelisted();
//     error TransferNotAllowed();
//     error InvalidSpenderAddress();
//     error CallerNotAuthorized();
    
//     /**
//      * @dev Constructor
//      * @param tokenName Name of the token
//      * @param tokenSymbol Symbol of the token
//      */
//     constructor(
//         string memory tokenName,
//         string memory tokenSymbol
//     ) ERC20(tokenName, tokenSymbol) Ownable(msg.sender) {
//         // Set owner as minter, burner, and whitelister by default
//         isMinter[msg.sender] = true;
//         isBurner[msg.sender] = true;
//         isWhitelister[msg.sender] = true;
        
//         // Whitelist the owner by default
//         isWhitelisted[msg.sender] = true;
        
//         emit MinterStatusUpdated(msg.sender, true);
//         emit BurnerStatusUpdated(msg.sender, true);
//         emit WhitelisterStatusUpdated(msg.sender, true);
//         emit AddressWhitelisted(msg.sender, true);
//     }
    
//     /**
//      * @dev Override decimals to return 6 instead of ERC20's default 18
//      */
//     function decimals() public pure override returns (uint8) {
//         return _decimals;
//     }
    
//     /**
//      * @dev Modifier to check if caller is a minter
//      */
//     modifier onlyMinter() {
//         require(isMinter[msg.sender] || msg.sender == owner(), "Caller is not a minter");
//         _;
//     }
    
//     /**
//      * @dev Modifier to check if caller is a burner
//      */
//     modifier onlyBurner() {
//         require(isBurner[msg.sender] || msg.sender == owner(), "Caller is not a burner");
//         _;
//     }
    
//     /**
//      * @dev Modifier to check if caller is a whitelister
//      */
//     modifier onlyWhitelister() {
//         require(isWhitelister[msg.sender] || msg.sender == owner(), "Caller is not a whitelister");
//         _;
//     }
    
//     /**
//      * @dev Set minter status
//      * @param minter Address to update
//      * @param status New minter status
//      */
//     function setMinter(address minter, bool status) external onlyOwner {
//         require(minter != address(0), "Invalid minter address");
//         isMinter[minter] = status;
//         emit MinterStatusUpdated(minter, status);
//     }
    
//     /**
//      * @dev Set burner status
//      * @param burner Address to update
//      * @param status New burner status
//      */
//     function setBurner(address burner, bool status) external onlyOwner {
//         require(burner != address(0), "Invalid burner address");
//         isBurner[burner] = status;
//         emit BurnerStatusUpdated(burner, status);
//     }
    
//     /**
//      * @dev Set whitelister status
//      * @param whitelister Address to update
//      * @param status New whitelister status
//      */
//     function setWhitelister(address whitelister, bool status) external onlyOwner {
//         require(whitelister != address(0), "Invalid whitelister address");
//         isWhitelister[whitelister] = status;
//         emit WhitelisterStatusUpdated(whitelister, status);
//     }
    
//     /**
//      * @dev Set whitelist status for an address
//      * @param account Address to update
//      * @param status New whitelist status
//      */
//     function setWhitelisted(address account, bool status) external onlyWhitelister {
//         require(account != address(0), "Invalid address");
//         isWhitelisted[account] = status;
//         emit AddressWhitelisted(account, status);
//     }
    
//     /**
//      * @dev Batch whitelist addresses
//      * @param accounts Array of addresses to whitelist
//      * @param status Whitelist status to set for all addresses
//      */
//     function batchWhitelist(address[] calldata accounts, bool status) external onlyWhitelister {
//         for (uint256 i = 0; i < accounts.length; i++) {
//             if (accounts[i] == address(0)) continue; // Skip zero addresses
//             isWhitelisted[accounts[i]] = status;
//             emit AddressWhitelisted(accounts[i], status);
//         }
//     }
    
//     /**
//      * @dev Hook that is called before any token transfer
//      * This includes minting and burning
//      */
//     function _update(
//         address from,
//         address to,
//         uint256 amount
//     ) internal override virtual {
//         // Skip whitelisting check for minting and burning operations
//         if (from != address(0) && to != address(0)) {
//             // Check whitelisting (always required for promotional tokens)
//             require(isWhitelisted[from], "Sender is not whitelisted");
//             require(isWhitelisted[to], "Recipient is not whitelisted");
            
//             // For promotional tokens, restrict transfers to only owner-related transfers
//             bool isOwnerInvolved = (from == owner() || to == owner());
            
//             require(isOwnerInvolved, "Transfer not allowed: owner must be involved");
            
//             // If transfer is to owner, it's considered as "using tokens for betting"
//             if (to == owner()) {
//                 emit TokensUsedForBetting(from, amount);
//             }
//         }
        
//         super._update(from, to, amount);
//     }
    
//     /**
//      * @dev Override the approve behavior for promotional tokens
//      * @param spender Address that will spend the tokens
//      * @param amount Amount of tokens to approve
//      */
//     function approve(address spender, uint256 amount) public override returns (bool) {
//         address tokenOwner = _msgSender();
        
//         // For promotional token, only the owner can be approved to spend tokens
//         // Unless the token owner is also the contract owner
//         require(
//             spender == owner() || tokenOwner == owner(),
//             "Only owner can be approved for spending"
//         );
        
//         return super.approve(spender, amount);
//     }
    
//     /**
//      * @dev Mints new tokens using OpenZeppelin's _mint
//      * @param to Address receiving the tokens
//      * @param amount Amount of tokens to mint
//      */
//     function mint(address to, uint256 amount) external onlyMinter nonReentrant {
//         require(to != address(0), "Mint to the zero address");
//         require(amount > 0, "Mint amount must be greater than zero");
        
//         // Automatically whitelist airdrop recipients
//         if (!isWhitelisted[to]) {
//             isWhitelisted[to] = true;
//             emit AddressWhitelisted(to, true);
//         }
        
//         _mint(to, amount);
//     }
    
//     /**
//      * @dev Burns tokens from an account using OpenZeppelin's _burn
//      * @param from Address to burn tokens from
//      * @param amount Amount of tokens to burn
//      */
//     function burnFrom(address from, uint256 amount) public override onlyBurner nonReentrant {
//         require(amount > 0, "Burn amount must be greater than zero");
        
//         // Skip allowance check for authorized burners
//         if (isBurner[msg.sender] || msg.sender == owner()) {
//             _burn(from, amount);
//         } else {
//             // Use the standard implementation which checks for allowance
//             super.burnFrom(from, amount);
//         }
//     }
    
//     /**
//      * @dev Batch airdrop tokens to multiple addresses
//      * @param recipients Array of recipient addresses
//      * @param amounts Array of token amounts
//      */
//     function batchAirdrop(address[] calldata recipients, uint256[] calldata amounts) external onlyMinter nonReentrant {
//         require(recipients.length == amounts.length, "Array lengths must match");
        
//         for (uint256 i = 0; i < recipients.length; i++) {
//             address to = recipients[i];
//             uint256 amount = amounts[i];
            
//             if (to == address(0) || amount == 0) continue; // Skip invalid entries
            
//             // Automatically whitelist airdrop recipients
//             if (!isWhitelisted[to]) {
//                 isWhitelisted[to] = true;
//                 emit AddressWhitelisted(to, true);
//             }
            
//             _mint(to, amount);
//         }
//     }
    
//     /**
//      * @dev Use promotional tokens for betting (transfers to owner)
//      * @param user User address
//      * @param amount Amount of tokens to use
//      */
//     function useForBetting(address user, uint256 amount) external onlyOwner nonReentrant {
//         require(user != address(0), "Invalid user address");
//         require(amount > 0, "Amount must be greater than zero");
        
//         _transfer(user, owner(), amount);
        
//         // TokensUsedForBetting event is emitted in _update
//     }
// } 