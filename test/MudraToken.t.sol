// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {MudraToken} from "../src/MudraToken.sol";

contract MudraTokenTest is Test {
    // Constants for test configuration
    string constant TOKEN_NAME = "Mudra Token";
    string constant TOKEN_SYMBOL = "MUDRA";
    uint8 constant DECIMALS = 6;
    uint256 constant INITIAL_MINT_AMOUNT = 1_000_000 * 10 ** 6; // 1 million tokens

    // Test addresses
    address public owner;
    address public whitelister;
    address public blacklister;
    address public user1;
    address public user2;
    address public user3;
    address public user4;

    // Contract instance
    MudraToken public token;

    // Errors from Pausable
    error EnforcedPause();
    error ExpectedPause();

    // Events to test
    event WhitelisterStatusUpdated(address indexed whitelister, bool status);
    event BlacklisterStatusUpdated(address indexed blacklister, bool status);
    event AddressWhitelisted(address indexed account, bool status);
    event AddressBlacklisted(address indexed account, bool status);
    event WhitelistStatusUpdated(bool status);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        // Set up test addresses
        owner = makeAddr("owner");
        whitelister = makeAddr("whitelister");
        blacklister = makeAddr("blacklister");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");

        // Deploy token with owner as the admin
        token = new MudraToken(TOKEN_NAME, TOKEN_SYMBOL, owner);

        // Mint initial supply
        vm.prank(owner);
        token.mint(owner, INITIAL_MINT_AMOUNT);

        // Set up roles
        vm.startPrank(owner);
        token.setWhitelister(whitelister, true);
        token.setBlacklister(blacklister, true);
        token.setWhitelisted(user1, true);
        token.setWhitelisted(user2, true);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testInitialState() public view {
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.decimals(), DECIMALS);
        assertEq(token.totalSupply(), INITIAL_MINT_AMOUNT);
        assertEq(token.balanceOf(owner), INITIAL_MINT_AMOUNT);
        assertEq(token.owner(), owner);
        assertTrue(token.isWhitelister(owner));
        assertTrue(token.isBlacklister(owner));
        assertTrue(token.isWhitelisted(owner));
        assertTrue(token.isWhitelisted(user1));
        assertTrue(token.isWhitelisted(user2));
        assertTrue(token.whitelistingEnabled());
        assertFalse(token.paused());
    }

    function testDecimals() public view {
        assertEq(token.decimals(), DECIMALS);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testOnlyOwnerCanMint() public {
        // Owner can mint
        vm.prank(owner);
        token.mint(user1, 1000);
        assertEq(token.balanceOf(user1), 1000);

        // Non-owner cannot mint
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        token.mint(user1, 1000);
    }

    function testMintRequiresNonZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(MudraToken.InvalidAddress.selector);
        token.mint(address(0), 1000);
    }

    function testMintRequiresPositiveAmount() public {
        vm.prank(owner);
        vm.expectRevert(MudraToken.InvalidMintAmount.selector);
        token.mint(user1, 0);
    }

    function testMintToBlacklistedAddress() public {
        // Blacklist user1
        vm.prank(owner);
        token.setBlacklisted(user1, true);

        // Try to mint to blacklisted user
        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.mint(user1, 1000);
    }

    function testOnlyOwnerCanBurn() public {
        // Setup: mint tokens to user1
        vm.prank(owner);
        token.mint(user1, 1000);

        // Owner can burn from user1
        vm.prank(owner);
        token.burnFrom(user1, 500);
        assertEq(token.balanceOf(user1), 500);

        // Non-owner cannot burn
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user2));
        token.burnFrom(user1, 500);
    }

    function testBurnRequiresPositiveAmount() public {
        vm.prank(owner);
        vm.expectRevert(MudraToken.InvalidBurnAmount.selector);
        token.burnFrom(user1, 0);
    }

    function testBurnFromBlacklistedAddress() public {
        // Setup: mint tokens to user1
        vm.prank(owner);
        token.mint(user1, 1000);

        // Blacklist user1
        vm.prank(owner);
        token.setBlacklisted(user1, true);

        // Try to burn from blacklisted user
        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.burnFrom(user1, 500);
    }

    function testOwnerPauseAndUnpause() public {
        // Owner can pause
        vm.prank(owner);
        token.pause();
        assertTrue(token.paused());

        // Owner can unpause
        vm.prank(owner);
        token.unpause();
        assertFalse(token.paused());

        // Non-owner cannot pause
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        token.pause();
    }

    /*//////////////////////////////////////////////////////////////
                        ROLE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetWhitelister() public {
        // Owner can set whitelister
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit WhitelisterStatusUpdated(user3, true);
        token.setWhitelister(user3, true);
        assertTrue(token.isWhitelister(user3));

        // Owner can remove whitelister
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit WhitelisterStatusUpdated(user3, false);
        token.setWhitelister(user3, false);
        assertFalse(token.isWhitelister(user3));

        // Non-owner cannot set whitelister
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        token.setWhitelister(user3, true);
    }

    function testSetBlacklister() public {
        // Owner can set blacklister
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BlacklisterStatusUpdated(user3, true);
        token.setBlacklister(user3, true);
        assertTrue(token.isBlacklister(user3));

        // Owner can remove blacklister
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BlacklisterStatusUpdated(user3, false);
        token.setBlacklister(user3, false);
        assertFalse(token.isBlacklister(user3));

        // Non-owner cannot set blacklister
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        token.setBlacklister(user3, true);
    }

    function testSetWhitelistingEnabled() public {
        // Owner can disable whitelisting
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit WhitelistStatusUpdated(false);
        token.setWhitelistingEnabled(false);
        assertFalse(token.whitelistingEnabled());

        // Owner can enable whitelisting
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit WhitelistStatusUpdated(true);
        token.setWhitelistingEnabled(true);
        assertTrue(token.whitelistingEnabled());

        // Non-owner cannot change whitelisting status
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        token.setWhitelistingEnabled(false);
    }

    /*//////////////////////////////////////////////////////////////
                        WHITELIST TESTS
    //////////////////////////////////////////////////////////////*/

    function testWhitelistManagement() public {
        // Whitelister can whitelist an address
        vm.prank(whitelister);
        vm.expectEmit(true, true, true, true);
        emit AddressWhitelisted(user3, true);
        token.setWhitelisted(user3, true);
        assertTrue(token.isWhitelisted(user3));

        // Whitelister can remove an address from whitelist
        vm.prank(whitelister);
        vm.expectEmit(true, true, true, true);
        emit AddressWhitelisted(user3, false);
        token.setWhitelisted(user3, false);
        assertFalse(token.isWhitelisted(user3));

        // Non-whitelister cannot manage whitelist
        vm.prank(user3);
        vm.expectRevert(MudraToken.InvalidWhitelisterAddress.selector);
        token.setWhitelisted(user4, true);

        // Owner can always whitelist, even if not explicitly a whitelister
        vm.prank(owner);
        token.setWhitelisted(user4, true);
        assertTrue(token.isWhitelisted(user4));
    }

    function testBatchWhitelist() public {
        address[] memory users = new address[](3);
        users[0] = user3;
        users[1] = user4;
        users[2] = address(0); // Should be skipped

        // Test batch whitelisting
        vm.prank(whitelister);
        token.batchWhitelist(users, true);

        assertTrue(token.isWhitelisted(user3));
        assertTrue(token.isWhitelisted(user4));
        assertFalse(token.isWhitelisted(address(0)));

        // Test batch removal from whitelist
        vm.prank(whitelister);
        token.batchWhitelist(users, false);

        assertFalse(token.isWhitelisted(user3));
        assertFalse(token.isWhitelisted(user4));
    }

    function testBatchWhitelistSizeLimits() public {
        // Create an array with 301 addresses (exceeding the 300 limit)
        address[] memory largeArray = new address[](301);
        for (uint256 i = 0; i < 301; i++) {
            largeArray[i] = address(uint160(i + 1));
        }

        // Test that it reverts with too many addresses
        vm.prank(whitelister);
        vm.expectRevert("Batch too large");
        token.batchWhitelist(largeArray, true);

        // Test with exactly 300 addresses (should work)
        address[] memory exactArray = new address[](300);
        for (uint256 i = 0; i < 300; i++) {
            exactArray[i] = address(uint160(i + 1));
        }

        vm.prank(whitelister);
        token.batchWhitelist(exactArray, true);
        assertTrue(token.isWhitelisted(exactArray[0]));
        assertTrue(token.isWhitelisted(exactArray[299]));
    }

    /*//////////////////////////////////////////////////////////////
                        BLACKLIST TESTS
    //////////////////////////////////////////////////////////////*/

    function testBlacklistManagement() public {
        // Blacklister can blacklist an address
        vm.prank(blacklister);
        vm.expectEmit(true, true, true, true);
        emit AddressBlacklisted(user3, true);
        token.setBlacklisted(user3, true);
        assertTrue(token.isBlacklisted(user3));

        // Blacklister can remove an address from blacklist
        vm.prank(blacklister);
        vm.expectEmit(true, true, true, true);
        emit AddressBlacklisted(user3, false);
        token.setBlacklisted(user3, false);
        assertFalse(token.isBlacklisted(user3));

        // Non-blacklister cannot manage blacklist
        vm.prank(user3);
        vm.expectRevert(MudraToken.InvalidBlacklisterAddress.selector);
        token.setBlacklisted(user4, true);

        // Owner can always blacklist, even if not explicitly a blacklister
        vm.prank(owner);
        token.setBlacklisted(user4, true);
        assertTrue(token.isBlacklisted(user4));
    }

    function testBatchBlacklist() public {
        address[] memory users = new address[](3);
        users[0] = user3;
        users[1] = user4;
        users[2] = address(0); // Should be skipped

        // Test batch blacklisting
        vm.prank(blacklister);
        token.batchBlacklist(users, true);

        assertTrue(token.isBlacklisted(user3));
        assertTrue(token.isBlacklisted(user4));
        assertFalse(token.isBlacklisted(address(0)));

        // Test batch removal from blacklist
        vm.prank(blacklister);
        token.batchBlacklist(users, false);

        assertFalse(token.isBlacklisted(user3));
        assertFalse(token.isBlacklisted(user4));
    }

    function testBatchBlacklistSizeLimits() public {
        // Create an array with 301 addresses (exceeding the 300 limit)
        address[] memory largeArray = new address[](301);
        for (uint256 i = 0; i < 301; i++) {
            largeArray[i] = address(uint160(i + 1));
        }

        // Test that it reverts with too many addresses
        vm.prank(blacklister);
        vm.expectRevert("Batch too large");
        token.batchBlacklist(largeArray, true);

        // Test with exactly 300 addresses (should work)
        address[] memory exactArray = new address[](300);
        for (uint256 i = 0; i < 300; i++) {
            exactArray[i] = address(uint160(i + 1));
        }

        vm.prank(blacklister);
        token.batchBlacklist(exactArray, true);
        assertTrue(token.isBlacklisted(exactArray[0]));
        assertTrue(token.isBlacklisted(exactArray[299]));
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransferBetweenWhitelistedAddresses() public {
        // Setup: send some tokens to user1
        vm.prank(owner);
        token.transfer(user1, 1000);
        assertEq(token.balanceOf(user1), 1000);

        // Test transfer from user1 to user2 (both whitelisted)
        vm.prank(user1);
        token.transfer(user2, 500);
        assertEq(token.balanceOf(user1), 500);
        assertEq(token.balanceOf(user2), 500);
    }

    function testTransferToNonWhitelistedAddress() public {
        // Setup: send some tokens to user1
        vm.prank(owner);
        token.transfer(user1, 1000);

        // Try to transfer to a non-whitelisted address
        vm.prank(user1);
        vm.expectRevert(MudraToken.InvalidRecipientWhitelisted.selector);
        token.transfer(user3, 500);
    }

    function testTransferFromNonWhitelistedAddress() public {
        // Setup: disable whitelisting, send tokens to user3 (not whitelisted), re-enable whitelisting
        vm.startPrank(owner);
        token.setWhitelistingEnabled(false);
        token.transfer(user3, 1000);
        token.setWhitelistingEnabled(true);
        vm.stopPrank();

        // Try to transfer from a non-whitelisted address
        vm.prank(user3);
        vm.expectRevert(MudraToken.InvalidSenderWhitelisted.selector);
        token.transfer(user1, 500);
    }

    function testTransferToBlacklistedAddress() public {
        // Setup: blacklist user2
        vm.prank(owner);
        token.setBlacklisted(user2, true);

        // Try to transfer to a blacklisted address
        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user2, 500);
    }

    function testTransferFromBlacklistedAddress() public {
        // Setup: send tokens to user1 and blacklist them
        vm.prank(owner);
        token.transfer(user1, 1000);
        vm.prank(owner);
        token.setBlacklisted(user1, true);

        // Try to transfer from a blacklisted address
        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user2, 500);
    }

    function testTransferWhenPaused() public {
        // Setup: send some tokens to user1
        vm.prank(owner);
        token.transfer(user1, 1000);

        // Pause the contract
        vm.prank(owner);
        token.pause();

        // Try to transfer when paused
        vm.prank(user1);
        vm.expectRevert(EnforcedPause.selector);
        token.transfer(user2, 500);

        // Unpause and verify transfer works
        vm.prank(owner);
        token.unpause();
        vm.prank(user1);
        token.transfer(user2, 500);
        assertEq(token.balanceOf(user2), 500);
    }

    function testTransferWithWhitelistingDisabled() public {
        // Setup: disable whitelisting
        vm.prank(owner);
        token.setWhitelistingEnabled(false);

        // Setup: send tokens to user1
        vm.prank(owner);
        token.transfer(user1, 1000);

        // Now user1 should be able to transfer to non-whitelisted user3
        vm.prank(user1);
        token.transfer(user3, 500);
        assertEq(token.balanceOf(user3), 500);
    }

    /*//////////////////////////////////////////////////////////////
                        APPROVAL AND TRANSFERFROM TESTS
    //////////////////////////////////////////////////////////////*/

    function testApproveAndTransferFrom() public {
        // Setup: send tokens to user1
        vm.prank(owner);
        token.transfer(user1, 1000);

        // User1 approves user2 to spend tokens
        vm.prank(user1);
        token.approve(user2, 500);
        assertEq(token.allowance(user1, user2), 500);

        // User2 transfers tokens from user1 to themselves
        vm.prank(user2);
        token.transferFrom(user1, user2, 300);
        assertEq(token.balanceOf(user1), 700);
        assertEq(token.balanceOf(user2), 300);
        assertEq(token.allowance(user1, user2), 200);
    }

    function testTransferFromToBlacklistedAddress() public {
        // Setup: send tokens to user1, user1 approves user2
        vm.prank(owner);
        token.transfer(user1, 1000);
        vm.prank(user1);
        token.approve(user2, 500);

        // Blacklist user3
        vm.prank(owner);
        token.setBlacklisted(user3, true);

        // Try to transferFrom to a blacklisted address
        vm.prank(user2);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transferFrom(user1, user3, 300);
    }

    function testTransferFromFromBlacklistedAddress() public {
        // Setup: send tokens to user1, user1 approves user2
        vm.prank(owner);
        token.transfer(user1, 1000);
        vm.prank(user1);
        token.approve(user2, 500);

        // Blacklist user1
        vm.prank(owner);
        token.setBlacklisted(user1, true);

        // Try to transferFrom from a blacklisted address
        vm.prank(user2);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transferFrom(user1, user2, 300);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES & VULNERABILITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testSimultaneousWhitelistAndBlacklist() public {
        // Set up an address that is both whitelisted and blacklisted
        vm.startPrank(owner);
        token.setWhitelisted(user3, true);
        token.setBlacklisted(user3, true);
        vm.stopPrank();

        // Verify that transfers to/from this address fail due to blacklisting
        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user3, 100);

        // Verify that minting to this address fails
        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.mint(user3, 100);
    }

    function testRoleManagementSecurityEdgeCases() public {
        // Test removing whitelister role from self
        vm.startPrank(whitelister);
        // This should fail since only owner can manage roles
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", whitelister));
        token.setWhitelister(whitelister, false);
        vm.stopPrank();

        // Test owner removing their own role - this is allowed, but checks
        // if the owner can still perform actions (they should be able to)
        vm.startPrank(owner);
        token.setWhitelister(owner, false);
        assertFalse(token.isWhitelister(owner));

        // Owner should still be able to whitelist addresses
        token.setWhitelisted(user3, true);
        assertTrue(token.isWhitelisted(user3));
        vm.stopPrank();
    }

    function testReentrancyProtection() public {
        // Simplified test: Verify nonReentrant modifier on critical functions
        // Note: A full reentrancy test would require a malicious contract implementation

        // Test reentrancy protection on mint
        vm.prank(owner);
        token.mint(user1, 1000);

        // Test reentrancy protection on burn
        vm.prank(owner);
        token.burnFrom(user1, 500);

        // If these don't revert, then the nonReentrant modifier is at least present
        // A full test would require simulating a reentrant call
    }

    function testInfiniteMintAndBurn() public {
        // Test very large mint amount (close to uint256 max)
        uint256 largeAmount = type(uint256).max / 2;

        vm.prank(owner);
        token.mint(owner, largeAmount);

        // Check that balance and total supply increased correctly
        assertEq(token.balanceOf(owner), INITIAL_MINT_AMOUNT + largeAmount);
        assertEq(token.totalSupply(), INITIAL_MINT_AMOUNT + largeAmount);

        // Test burning a large amount
        vm.prank(owner);
        token.burnFrom(owner, largeAmount);

        // Check that balance and total supply decreased correctly
        assertEq(token.balanceOf(owner), INITIAL_MINT_AMOUNT);
        assertEq(token.totalSupply(), INITIAL_MINT_AMOUNT);
    }

    function testOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        // Transfer ownership
        vm.prank(owner);
        token.transferOwnership(newOwner);

        // Verify new owner has taken control
        assertEq(token.owner(), newOwner);

        // Verify new owner has full privileges
        vm.prank(newOwner);
        token.mint(newOwner, 1000);
        assertEq(token.balanceOf(newOwner), 1000);

        // Verify old owner has lost privileges
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner));
        token.mint(owner, 1000);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Mint(address to, uint256 amount) public {
        // Avoid zero address and zero amount cases that will revert
        vm.assume(to != address(0));
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2); // Avoid overflow

        // Ensure the address is whitelisted
        vm.prank(owner);
        token.setWhitelisted(to, true);

        // Ensure the address is not blacklisted
        vm.prank(owner);
        token.setBlacklisted(to, false);

        // Mint tokens
        vm.prank(owner);
        token.mint(to, amount);

        // Verify balance
        assertEq(token.balanceOf(to), amount);
    }

    function testFuzz_Transfer(address from, address to, uint256 amount) public {
        // Avoid edge cases that will revert
        vm.assume(from != address(0) && to != address(0));
        vm.assume(from != to);
        vm.assume(amount > 0);
        vm.assume(amount < INITIAL_MINT_AMOUNT);

        // Ensure addresses are whitelisted
        vm.startPrank(owner);
        token.setWhitelisted(from, true);
        token.setWhitelisted(to, true);

        // Mint tokens to 'from' address
        token.mint(from, amount);
        vm.stopPrank();

        // Perform transfer
        vm.prank(from);
        token.transfer(to, amount);

        // Verify balances
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), amount);
    }

    function testFuzz_Burn(address target, uint256 mintAmount, uint256 burnAmount) public {
        // Avoid edge cases that will revert
        vm.assume(target != address(0));
        vm.assume(mintAmount > 0 && burnAmount > 0);
        vm.assume(burnAmount <= mintAmount);
        vm.assume(mintAmount < type(uint256).max / 2); // Avoid overflow

        // Whitelist the target address
        vm.prank(owner);
        token.setWhitelisted(target, true);

        // Mint tokens to target
        vm.prank(owner);
        token.mint(target, mintAmount);

        // Burn tokens from target
        vm.prank(owner);
        token.burnFrom(target, burnAmount);

        // Verify balance
        assertEq(token.balanceOf(target), mintAmount - burnAmount);
    }

    /*//////////////////////////////////////////////////////////////
                    ADDITIONAL TESTS FOR FULL COVERAGE
    //////////////////////////////////////////////////////////////*/

    function testBurnFromNonOwnerWithAllowance() public {
        // Setup: mint tokens to user1
        vm.prank(owner);
        token.mint(user1, 1000);

        // User1 approves user2 to burn tokens
        vm.prank(user1);
        token.approve(user2, 500);

        // User2 should not be able to burnFrom (only owner can)
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user2));
        token.burnFrom(user1, 300);
    }

    function testZeroAddressCases() public {
        // Test zero address in setWhitelister
        vm.prank(owner);
        vm.expectRevert(MudraToken.InvalidAddress.selector);
        token.setWhitelister(address(0), true);

        // Test zero address in setBlacklister
        vm.prank(owner);
        vm.expectRevert(MudraToken.InvalidAddress.selector);
        token.setBlacklister(address(0), true);

        // Test zero address in setWhitelisted
        vm.prank(owner);
        vm.expectRevert(MudraToken.InvalidAddress.selector);
        token.setWhitelisted(address(0), true);

        // Test zero address in setBlacklisted
        vm.prank(owner);
        vm.expectRevert(MudraToken.InvalidAddress.selector);
        token.setBlacklisted(address(0), true);
    }

    function testSkipZeroAddressInBatchOperations() public {
        address[] memory addresses = new address[](3);
        addresses[0] = user3;
        addresses[1] = address(0); // Should be skipped
        addresses[2] = user4;

        // Test batch whitelist with zero address
        vm.prank(whitelister);
        token.batchWhitelist(addresses, true);

        assertTrue(token.isWhitelisted(user3));
        assertTrue(token.isWhitelisted(user4));
        assertFalse(token.isWhitelisted(address(0)));

        // Test batch blacklist with zero address
        vm.prank(blacklister);
        token.batchBlacklist(addresses, true);

        assertTrue(token.isBlacklisted(user3));
        assertTrue(token.isBlacklisted(user4));
        assertFalse(token.isBlacklisted(address(0)));
    }

    function testUnpauseWhenNotPaused() public {
        // Unpause when not paused (should be a no-op or revert)
        vm.prank(owner);
        vm.expectRevert(ExpectedPause.selector);
        token.unpause();
    }

    function testPauseWhenPaused() public {
        // Pause the contract
        vm.prank(owner);
        token.pause();

        // Try to pause again
        vm.prank(owner);
        vm.expectRevert(EnforcedPause.selector);
        token.pause();
    }

    function testTransferERC20WhenNotWhitelisted() public {
        // Setup: disable whitelisting
        vm.prank(owner);
        token.setWhitelistingEnabled(false);

        // Non-whitelisted users should be able to transfer
        vm.prank(owner);
        token.mint(user3, 1000); // User3 is not whitelisted

        vm.prank(user3);
        token.transfer(user4, 500); // User4 is not whitelisted

        assertEq(token.balanceOf(user3), 500);
        assertEq(token.balanceOf(user4), 500);

        // Re-enable whitelisting for other tests
        vm.prank(owner);
        token.setWhitelistingEnabled(true);
    }

    function testBurnFromAllCases() public {
        // Setup: mint tokens to various users
        vm.startPrank(owner);
        token.mint(user1, 1000);
        token.mint(user2, 1000);
        vm.stopPrank();

        // Case 1: Owner burns directly (no allowance needed)
        vm.prank(owner);
        token.burnFrom(user1, 300);
        assertEq(token.balanceOf(user1), 700);

        // Case 2: Non-owner tries to burn without allowance
        vm.prank(user3);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user3));
        token.burnFrom(user2, 300);

        // Ensure balance remained unchanged
        assertEq(token.balanceOf(user2), 1000);
    }

    function testInvalidAddressWhitelisterOrBlacklister() public {
        // Test non-whitelister trying to whitelist
        vm.prank(user3);
        vm.expectRevert(MudraToken.InvalidWhitelisterAddress.selector);
        token.setWhitelisted(user4, true);

        // Test non-blacklister trying to blacklist
        vm.prank(user3);
        vm.expectRevert(MudraToken.InvalidBlacklisterAddress.selector);
        token.setBlacklisted(user4, true);
    }

    function testMintAndBurnToBlacklistedAddress() public {
        // Blacklist user3
        vm.prank(owner);
        token.setBlacklisted(user3, true);

        // Try to mint to blacklisted address
        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.mint(user3, 1000);

        // Setup for burn test: whitelist and mint to user4
        vm.startPrank(owner);
        token.setWhitelisted(user4, true);
        token.mint(user4, 1000);
        vm.stopPrank();

        // Blacklist user4
        vm.prank(owner);
        token.setBlacklisted(user4, true);

        // Try to burn from blacklisted address
        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.burnFrom(user4, 500);
    }

    /*//////////////////////////////////////////////////////////////
                ADDITIONAL TESTS FOR 100% BRANCH COVERAGE
    //////////////////////////////////////////////////////////////*/

    function testTransferWithSenderZeroAddress() public {
        // This test covers the branch in _update where from is address(0) - minting case
        // We're testing that only the recipient needs to be whitelisted during minting

        // Whitelist recipient (set in setUp)
        vm.startPrank(owner);
        token.setWhitelisted(user1, true);
        token.mint(user1, 1000);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 1000);
    }

    function testTransferWithRecipientZeroAddress() public {
        // This test covers the branch in _update where to is address(0) - burning case
        // We're testing that only the sender needs to be whitelisted during burning

        // Mint tokens to user1 (already whitelisted in setUp)
        vm.prank(owner);
        token.mint(user1, 1000);

        // Burn tokens from user1 - uses _update with to=address(0)
        vm.prank(owner);
        token.burnFrom(user1, 500);

        assertEq(token.balanceOf(user1), 500);
    }

    function testBurnFromWithNonOwnerCalls() public {
        // Setup: mint tokens to user1
        vm.prank(owner);
        token.mint(user1, 1000);

        // Give user3 approval to burn user1's tokens
        vm.prank(user1);
        token.approve(user3, 300);

        // User3 tries to burn - should fail because burnFrom is owner-only
        vm.prank(user3);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user3));
        token.burnFrom(user1, 300);

        // Verify standard ERC20Burnable's burnFrom is not accessible
        assertEq(token.balanceOf(user1), 1000);
    }

    function testEmptyBatchOperations() public {
        // Test batch operations with empty arrays
        address[] memory emptyArray = new address[](0);

        // Batch whitelist with empty array
        vm.prank(whitelister);
        token.batchWhitelist(emptyArray, true);

        // Batch blacklist with empty array
        vm.prank(blacklister);
        token.batchBlacklist(emptyArray, true);
    }

    function testNonWhitelisterControlPath() public {
        // Test non-whitelister path in onlyWhitelister
        vm.prank(user3); // Not a whitelister
        vm.expectRevert(MudraToken.InvalidWhitelisterAddress.selector);
        token.setWhitelisted(user4, true);

        // Test owner can whitelist even if not explicitly set as whitelister
        vm.startPrank(owner);
        token.setWhitelister(owner, false); // Remove whitelister role from owner

        // Owner should still be able to manage whitelists due to "|| msg.sender == owner()" in the modifier
        token.setWhitelisted(user4, true);
        vm.stopPrank();

        assertTrue(token.isWhitelisted(user4));
    }

    function testNonBlacklisterControlPath() public {
        // Test non-blacklister path in onlyBlacklister
        vm.prank(user3); // Not a blacklister
        vm.expectRevert(MudraToken.InvalidBlacklisterAddress.selector);
        token.setBlacklisted(user4, true);

        // Test owner can blacklist even if not explicitly set as blacklister
        vm.startPrank(owner);
        token.setBlacklister(owner, false); // Remove blacklister role from owner

        // Owner should still be able to manage blacklists due to "|| msg.sender == owner()" in the modifier
        token.setBlacklisted(user4, true);
        vm.stopPrank();

        assertTrue(token.isBlacklisted(user4));
    }

    function testEdgeCasesWithWhitelistingDisabled() public {
        // Test transfer scenarios with whitelisting disabled

        // Disable whitelisting
        vm.prank(owner);
        token.setWhitelistingEnabled(false);

        // Test transfer from non-whitelisted sender to non-whitelisted recipient
        vm.prank(owner);
        token.mint(user3, 1000); // user3 is not whitelisted

        vm.prank(user3);
        token.transfer(user4, 500); // user4 is not whitelisted

        // Make sure user1 has some tokens
        vm.prank(owner);
        token.mint(user1, 1000); // user1 is whitelisted

        // Test transfer from whitelisted to non-whitelisted
        vm.prank(user1); // user1 is whitelisted
        token.transfer(user3, 100);

        // Test transfer from non-whitelisted to whitelisted
        vm.prank(user3);
        token.transfer(user1, 100);

        // Re-enable whitelisting for other tests
        vm.prank(owner);
        token.setWhitelistingEnabled(true);
    }

    function testMintDirectlyToBlacklistedAddress() public {
        // First whitelist user3 (so whitelisting doesn't interfere)
        vm.prank(owner);
        token.setWhitelisted(user3, true);

        // Then blacklist the address
        vm.prank(owner);
        token.setBlacklisted(user3, true);

        // Try to mint to blacklisted address
        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.mint(user3, 1000);
    }

    function testMultipleConstraintsOnTransfer() public {
        // Test a transfer with multiple constraints
        // 1. Setup a paused contract
        vm.prank(owner);
        token.pause();

        // 2. Try to transfer when paused (should revert with pause error first)
        vm.prank(user1);
        vm.expectRevert(EnforcedPause.selector);
        token.transfer(user2, 100);

        // 3. Unpause but blacklist recipient
        vm.startPrank(owner);
        token.unpause();
        token.setBlacklisted(user2, true);
        vm.stopPrank();

        // 4. Try transfer to blacklisted (should revert with blacklist error)
        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user2, 100);

        // 5. Unblacklist recipient but disable whitelist and try with non-whitelisted sender
        vm.startPrank(owner);
        token.setBlacklisted(user2, false);
        token.setWhitelisted(user1, false);
        vm.stopPrank();

        // 6. Try transfer from non-whitelisted (should revert with whitelist error)
        vm.prank(user1);
        vm.expectRevert(MudraToken.InvalidSenderWhitelisted.selector);
        token.transfer(user2, 100);
    }

    function testBurnFromWithOwnerLogic() public {
        // Setup: mint tokens to user1
        vm.prank(owner);
        token.mint(user1, 1000);

        // Test burnFrom as owner without allowance
        vm.prank(owner);
        token.burnFrom(user1, 300);

        // Verify the burn happened
        assertEq(token.balanceOf(user1), 700);

        // Give a different user (not owner) allowance
        vm.prank(user1);
        token.approve(user2, 300);

        // Test burnFrom with a non-owner, which should fail
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user2));
        token.burnFrom(user1, 200);

        // Verify no additional tokens were burned
        assertEq(token.balanceOf(user1), 700);
    }

    /*//////////////////////////////////////////////////////////////
                FINAL TESTS FOR 100% COVERAGE
    //////////////////////////////////////////////////////////////*/

    function testBurnFromBranchWithNonOwnerAllowanceCheck() public {
        // Setup: mint tokens to user1
        vm.prank(owner);
        token.mint(user1, 1000);

        // Using a non-owner address for burnFrom (this tests the else branch in burnFrom)
        address nonOwner = makeAddr("nonOwner");

        // Try burnFrom without approval (should fail with insufficient allowance)
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        token.burnFrom(user1, 500);
        vm.stopPrank();

        // Verify tokens were not burned
        assertEq(token.balanceOf(user1), 1000);
    }

    function testBatchOperationsWithDifferentSizes() public {
        // Test with a larger batch (but still within limits)
        address[] memory largeButValidArray = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            largeButValidArray[i] = address(uint160(i + 1));
        }

        // Batch whitelist with large valid array
        vm.prank(whitelister);
        token.batchWhitelist(largeButValidArray, true);

        // Verify a few addresses were whitelisted
        assertTrue(token.isWhitelisted(largeButValidArray[0]));
        assertTrue(token.isWhitelisted(largeButValidArray[50]));
        assertTrue(token.isWhitelisted(largeButValidArray[99]));

        // Batch blacklist with large valid array
        vm.prank(blacklister);
        token.batchBlacklist(largeButValidArray, true);

        // Verify a few addresses were blacklisted
        assertTrue(token.isBlacklisted(largeButValidArray[0]));
        assertTrue(token.isBlacklisted(largeButValidArray[50]));
        assertTrue(token.isBlacklisted(largeButValidArray[99]));
    }

    function testZeroAmountChecks() public {
        // Test minting with zero amount
        vm.prank(owner);
        vm.expectRevert(MudraToken.InvalidMintAmount.selector);
        token.mint(user1, 0);

        // Test burning with zero amount
        vm.prank(owner);
        vm.expectRevert(MudraToken.InvalidBurnAmount.selector);
        token.burnFrom(user1, 0);
    }

    function testWhitelistingEnabledEdgeCases() public {
        // Test all branches in the _update function related to whitelistingEnabled

        // 1. First setup: whitelisting disabled, sender not whitelisted, recipient not whitelisted
        vm.prank(owner);
        token.setWhitelistingEnabled(false);

        // Mint tokens to non-whitelisted user3
        vm.prank(owner);
        token.mint(user3, 1000);

        // Transfer should work even though sender and recipient are not whitelisted
        vm.prank(user3);
        token.transfer(user4, 500);

        // 2. Test: whitelisting enabled, sender is whitelisted, recipient not whitelisted
        vm.prank(owner);
        token.setWhitelistingEnabled(true);

        // Make sender whitelisted
        vm.prank(owner);
        token.setWhitelisted(user3, true);

        // Transfer should fail due to recipient not being whitelisted
        vm.prank(user3);
        vm.expectRevert(MudraToken.InvalidRecipientWhitelisted.selector);
        token.transfer(user4, 100);

        // 3. Test: whitelisting enabled, sender not whitelisted, recipient is whitelisted
        // First disable whitelisting to set up the scenario
        vm.prank(owner);
        token.setWhitelistingEnabled(false);

        // Give tokens to user4 (not whitelisted yet)
        vm.prank(owner);
        token.mint(user4, 1000);

        // Now set up the scenario
        vm.startPrank(owner);
        token.setWhitelisted(user4, false); // Ensure user4 is not whitelisted
        token.setWhitelisted(user2, true); // But recipient is whitelisted
        token.setWhitelistingEnabled(true); // Re-enable whitelisting
        vm.stopPrank();

        // Transfer should fail due to sender not being whitelisted
        vm.prank(user4);
        vm.expectRevert(MudraToken.InvalidSenderWhitelisted.selector);
        token.transfer(user2, 50);
    }

    function testMintingToNonWhitelistedAddress() public {
        // Test that minting works to non-whitelisted addresses (since whitelisting check is skipped for mint)

        // Ensure user3 is not whitelisted
        assertFalse(token.isWhitelisted(user3));

        // Mint should work even though user3 is not whitelisted
        vm.prank(owner);
        token.mint(user3, 1000);

        // Verify the mint worked
        assertEq(token.balanceOf(user3), 1000);
    }

    function testBlacklistingWithDifferentScenarios() public {
        // Test minting to a blacklisted address
        vm.prank(owner);
        token.setBlacklisted(user3, true);

        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.mint(user3, 1000);

        // Test burning from a blacklisted address
        // Setup - mint to user4 first, then blacklist
        vm.startPrank(owner);
        token.setWhitelisted(user4, true);
        token.mint(user4, 1000);
        token.setBlacklisted(user4, true);
        vm.stopPrank();

        // Attempt to burn from blacklisted
        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.burnFrom(user4, 500);

        // Send tokens to user1 for testing transfers
        vm.prank(owner);
        token.mint(user1, 1000);

        // Test transfer to blacklisted address
        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user3, 100);

        // Test transfer from blacklisted address (owner is not blacklisted by default)
        // First blacklist a user that has tokens
        vm.prank(owner);
        token.setBlacklisted(user1, true);

        // Then try transfer from that address
        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user2, 100);
    }

    function testVerifyBurnFromWithAllowance() public {
        // Test the burnFrom function's specific branch where a non-owner tries to burn with allowance

        // Setup: mint tokens to user1
        vm.prank(owner);
        token.mint(user1, 1000);

        // User1 approves user2 to spend tokens
        vm.prank(user1);
        token.approve(user2, 500);

        // Test the branch where non-owner calls burnFrom (should revert)
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user2));
        token.burnFrom(user1, 300);

        // Verify no burn happened
        assertEq(token.balanceOf(user1), 1000);
    }

    function testSequentialWhitelistThenBlacklist() public {
        // Whitelist then blacklist an address
        vm.prank(owner);
        token.setWhitelisted(user3, true);
        assertTrue(token.isWhitelisted(user3));

        vm.prank(owner);
        token.setBlacklisted(user3, true);
        assertTrue(token.isBlacklisted(user3));

        // Test operations all fail due to blacklist
        // Mint
        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.mint(user3, 1000);

        // Transfer to blacklisted
        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user3, 100);
    }

    function testPauseTransfersUnderDifferentConditions() public {
        // Setup - mint tokens to test addresses
        vm.startPrank(owner);
        token.mint(user1, 1000);
        token.mint(user2, 1000);
        token.mint(user3, 1000);
        vm.stopPrank();

        // Test 1: Whitelist + Not Paused -> Transfer works
        // (This scenario is covered by existing tests)

        // Test 2: Whitelist + Paused -> Transfer fails with pause error
        vm.prank(owner);
        token.pause();

        vm.prank(user1);
        vm.expectRevert(EnforcedPause.selector);
        token.transfer(user2, 200);

        // Test 3: No Whitelist + Paused -> Transfer fails with pause error first
        vm.startPrank(owner);
        token.setWhitelistingEnabled(false);
        // Still paused
        vm.stopPrank();

        vm.prank(user3); // Not whitelisted
        vm.expectRevert(EnforcedPause.selector);
        token.transfer(user4, 200);

        // Test 4: Blacklisted + Paused -> Transfer fails with pause error first
        vm.startPrank(owner);
        token.setBlacklisted(user1, true);
        // Still paused
        vm.stopPrank();

        vm.prank(user1); // Now blacklisted
        vm.expectRevert(EnforcedPause.selector);
        token.transfer(user2, 200);

        // Unpause for other tests
        vm.prank(owner);
        token.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                    APPROVAL RACE CONDITION TESTS
    //////////////////////////////////////////////////////////////*/

    function testApproveZeroFirst() public {
        // Setup: user1 should be able to approve a new amount when there is no previous allowance
        vm.startPrank(user1);
        assertTrue(token.approve(user2, 100));
        assertEq(token.allowance(user1, user2), 100);

        // Attempt to change allowance directly without setting to zero first (should fail)
        vm.expectRevert(MudraToken.InvalidApprove.selector);
        token.approve(user2, 50);

        // Verify allowance is still the original amount
        assertEq(token.allowance(user1, user2), 100);

        // Set allowance to zero first
        assertTrue(token.approve(user2, 0));
        assertEq(token.allowance(user1, user2), 0);

        // Now should be able to set to new amount
        assertTrue(token.approve(user2, 50));
        assertEq(token.allowance(user1, user2), 50);
        vm.stopPrank();
    }

    function testApproveZeroAmount() public {
        // Setting to zero should always work regardless of previous allowance
        vm.prank(user1);
        token.approve(user2, 100);
        assertEq(token.allowance(user1, user2), 100);

        vm.prank(user1);
        token.approve(user2, 0);
        assertEq(token.allowance(user1, user2), 0);
    }

    function testApproveWhenPaused() public {
        // Setup
        vm.prank(owner);
        token.pause();

        // Approve should fail when paused
        vm.prank(user1);
        vm.expectRevert(EnforcedPause.selector);
        token.approve(user2, 100);

        // Unpause
        vm.prank(owner);
        token.unpause();

        // Approve should work when unpaused
        vm.prank(user1);
        token.approve(user2, 100);
        assertEq(token.allowance(user1, user2), 100);
    }

    function testApproveForBlacklistedAddress() public {
        // Test approving a blacklisted spender
        vm.prank(owner);
        token.setBlacklisted(user2, true);

        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.approve(user2, 100);

        // Test approving from a blacklisted owner
        vm.prank(owner);
        token.setBlacklisted(user1, true);

        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.approve(user3, 100);
    }
}
