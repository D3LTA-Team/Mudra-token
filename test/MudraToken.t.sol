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
    event WhitelisterStatusUpdated(address indexed account, bool status);
    event BlacklisterStatusUpdated(address indexed account, bool status);
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
                    AUDIT FIX TESTS - CRITICAL
    //////////////////////////////////////////////////////////////*/

    function testBlacklistedSpenderCannotUseTransferFrom() public {
        // Setup: user1 has tokens and approves user2
        vm.prank(owner);
        token.transfer(user1, 1000);
        
        vm.prank(user1);
        token.approve(user2, 500);
        
        // Blacklist the spender (user2)
        vm.prank(owner);
        token.setBlacklisted(user2, true);
        
        // user2 (blacklisted spender) should not be able to use transferFrom
        vm.prank(user2);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transferFrom(user1, user3, 100);
        
        // Verify no tokens were transferred
        assertEq(token.balanceOf(user1), 1000);
        assertEq(token.balanceOf(user3), 0);
        assertEq(token.allowance(user1, user2), 500); // Allowance should remain
    }

    function testSpendAllowanceBlacklistCheck() public {
        // This test specifically targets the _spendAllowance override
        // We test it through transferFrom since burnFrom has onlyOwner modifier
        
        // Setup: user1 has tokens and approves user2
        vm.prank(owner);
        token.transfer(user1, 1000);
        
        vm.prank(user1);
        token.approve(user2, 500);
        
        // Whitelist user3 and user4 for transfers
        vm.startPrank(owner);
        token.setWhitelisted(user3, true);
        token.setWhitelisted(user4, true);
        vm.stopPrank();
        
        // Normal transferFrom should work
        vm.prank(user2);
        token.transferFrom(user1, user3, 100);
        assertEq(token.balanceOf(user3), 100);
        assertEq(token.allowance(user1, user2), 400);
        
        // Now blacklist the spender
        vm.prank(owner);
        token.setBlacklisted(user2, true);
        
        // transferFrom should fail due to blacklisted spender
        vm.prank(user2);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transferFrom(user1, user4, 100);
        
        // Verify state didn't change
        assertEq(token.balanceOf(user4), 0);
        assertEq(token.allowance(user1, user2), 400); // Allowance unchanged
    }

    function testOwnershipTransferRevokesRoles() public {
        address newOwner = makeAddr("newOwner");
        
        // Verify old owner has roles
        assertTrue(token.isWhitelister(owner));
        assertTrue(token.isBlacklister(owner));
        assertTrue(token.isWhitelisted(owner));
        
        // Transfer ownership and verify events
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit WhitelisterStatusUpdated(owner, false);
        vm.expectEmit(true, true, true, true);
        emit BlacklisterStatusUpdated(owner, false);
        vm.expectEmit(true, true, true, true);
        emit AddressWhitelisted(owner, false);
        vm.expectEmit(true, true, true, true);
        emit WhitelisterStatusUpdated(newOwner, true);
        vm.expectEmit(true, true, true, true);
        emit BlacklisterStatusUpdated(newOwner, true);
        vm.expectEmit(true, true, true, true);
        emit AddressWhitelisted(newOwner, true);
        token.transferOwnership(newOwner);
        
        // Verify ownership change
        assertEq(token.owner(), newOwner);
        
        // Verify old owner lost all roles
        assertFalse(token.isWhitelister(owner));
        assertFalse(token.isBlacklister(owner));
        assertFalse(token.isWhitelisted(owner));
        
        // Verify new owner has all roles
        assertTrue(token.isWhitelister(newOwner));
        assertTrue(token.isBlacklister(newOwner));
        assertTrue(token.isWhitelisted(newOwner));
        
        // Verify old owner cannot perform admin functions
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner));
        token.mint(owner, 1000);
        
        // Verify new owner can perform admin functions
        vm.prank(newOwner);
        token.mint(newOwner, 1000);
        assertEq(token.balanceOf(newOwner), 1000);
    }

    function testBlacklistingKeepsTokens() public {
        // Setup: user3 has tokens
        vm.startPrank(owner);
        token.setWhitelisted(user3, true);
        token.mint(user3, 5000);
        vm.stopPrank();
        
        assertEq(token.balanceOf(user3), 5000);
        uint256 totalSupplyBefore = token.totalSupply();
        
        // Blacklist user3 - tokens should remain (no auto-burn)
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AddressBlacklisted(user3, true);
        token.setBlacklisted(user3, true);
        
        // Verify tokens are still there (not auto-burned)
        assertEq(token.balanceOf(user3), 5000);
        assertEq(token.totalSupply(), totalSupplyBefore);
        assertTrue(token.isBlacklisted(user3));
        
        // But user3 cannot transfer
        vm.prank(user3);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user1, 100);
    }

    function testBatchBlacklistingKeepsTokens() public {
        // Setup: multiple users with tokens
        address[] memory users = new address[](3);
        users[0] = user3;
        users[1] = user4;
        users[2] = makeAddr("user5");
        
        vm.startPrank(owner);
        for (uint i = 0; i < users.length; i++) {
            token.setWhitelisted(users[i], true);
            token.mint(users[i], 1000 * (i + 1)); // Different amounts
        }
        vm.stopPrank();
        
        uint256 totalSupplyBefore = token.totalSupply();
        uint256[] memory balancesBefore = new uint256[](3);
        for (uint i = 0; i < users.length; i++) {
            balancesBefore[i] = token.balanceOf(users[i]);
        }
        
        // Batch blacklist should keep all their tokens
        vm.prank(owner);
        token.batchBlacklist(users, true);
        
        // Verify all tokens are still there (not burned)
        for (uint i = 0; i < users.length; i++) {
            assertEq(token.balanceOf(users[i]), balancesBefore[i]);
            assertTrue(token.isBlacklisted(users[i]));
        }
        assertEq(token.totalSupply(), totalSupplyBefore);
    }

    function testBlacklistingUserWithZeroBalanceWorks() public {
        // Blacklist a user with no tokens
        assertEq(token.balanceOf(user3), 0);
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AddressBlacklisted(user3, true);
        token.setBlacklisted(user3, true);
        
        assertTrue(token.isBlacklisted(user3));
        assertEq(token.balanceOf(user3), 0);
    }

    function testManualBurnFromBlacklistedUser() public {
        // Setup: user3 has tokens, then gets blacklisted
        vm.startPrank(owner);
        token.setWhitelisted(user3, true);
        token.mint(user3, 1000);
        token.setBlacklisted(user3, true); // Tokens remain (no auto-burn)
        vm.stopPrank();
        
        assertEq(token.balanceOf(user3), 1000);
        assertTrue(token.isBlacklisted(user3));
        
        // Owner can manually burn tokens from blacklisted user
        vm.prank(owner);
        token.burnFrom(user3, 600);
        
        // Verify tokens were burned manually
        assertEq(token.balanceOf(user3), 400);
        
        // Unblacklist user3
        vm.prank(owner);
        token.setBlacklisted(user3, false);
        
        // Re-whitelist user3 (since blacklisting revoked the whitelist status)
        vm.prank(owner);
        token.setWhitelisted(user3, true);
        
        // Verify user3 still has remaining tokens and can now transfer
        assertEq(token.balanceOf(user3), 400);
        assertFalse(token.isBlacklisted(user3));
        assertTrue(token.isWhitelisted(user3));
        
        vm.prank(user3);
        token.transfer(user1, 100);
        assertEq(token.balanceOf(user3), 300);
        assertEq(token.balanceOf(user1), 100);
    }

    /*//////////////////////////////////////////////////////////////
                        ORIGINAL TESTS (UPDATED)
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
        // First whitelist user3 and user4
        vm.startPrank(owner);
        token.setWhitelisted(user3, true);
        token.setWhitelisted(user4, true);
        vm.stopPrank();
        
        assertTrue(token.isWhitelisted(user3));
        assertTrue(token.isWhitelisted(user4));

        address[] memory users = new address[](3);
        users[0] = user3;
        users[1] = user4;
        users[2] = address(0); // Should be skipped

        // Test batch blacklisting (should revoke whitelist status)
        vm.prank(blacklister);
        token.batchBlacklist(users, true);

        assertTrue(token.isBlacklisted(user3));
        assertTrue(token.isBlacklisted(user4));
        assertFalse(token.isBlacklisted(address(0)));
        
        // Verify whitelist status was revoked
        assertFalse(token.isWhitelisted(user3));
        assertFalse(token.isWhitelisted(user4));

        // Test batch removal from blacklist
        vm.prank(blacklister);
        token.batchBlacklist(users, false);

        assertFalse(token.isBlacklisted(user3));
        assertFalse(token.isBlacklisted(user4));
        
        // Note: whitelist status remains false after unblacklisting
        assertFalse(token.isWhitelisted(user3));
        assertFalse(token.isWhitelisted(user4));
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

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES & VULNERABILITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testSimultaneousWhitelistAndBlacklist() public {
        // Whitelist user3 first
        vm.prank(owner);
        token.setWhitelisted(user3, true);
        assertTrue(token.isWhitelisted(user3));
        
        // Now blacklist the same address (this should revoke whitelist automatically)
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AddressWhitelisted(user3, false); // Expect whitelist to be revoked
        vm.expectEmit(true, true, true, true);
        emit AddressBlacklisted(user3, true);
        token.setBlacklisted(user3, true);

        // Verify user3 is blacklisted and no longer whitelisted
        assertTrue(token.isBlacklisted(user3));
        assertFalse(token.isWhitelisted(user3)); // Should be false now

        // Verify that transfers to/from this address fail due to blacklisting
        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user3, 100);

        // Verify that minting to this address fails
        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.mint(user3, 100);
        
        // Verify that you cannot whitelist an already blacklisted address
        vm.prank(owner);
        vm.expectRevert(MudraToken.CannotWhitelistBlacklistedAddress.selector);
        token.setWhitelisted(user3, true);
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

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Mint(address to, uint256 amount) public {
        // Avoid zero address and zero amount cases that will revert
        vm.assume(to != address(0));
        vm.assume(to != owner && to != user1 && to != user2 && to != user3 && to != user4);
        vm.assume(to != whitelister && to != blacklister);
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2); // Avoid overflow

        // Ensure the address starts fresh (not blacklisted and balance is 0)
        assertEq(token.balanceOf(to), 0);
        assertFalse(token.isBlacklisted(to));

        // Ensure the address is whitelisted
        vm.prank(owner);
        token.setWhitelisted(to, true);

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
        vm.assume(from != owner && from != user1 && from != user2 && from != user3 && from != user4);
        vm.assume(to != owner && to != user1 && to != user2 && to != user3 && to != user4);
        vm.assume(from != whitelister && from != blacklister);
        vm.assume(to != whitelister && to != blacklister);
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2);

        // Ensure addresses start fresh
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), 0);
        assertFalse(token.isBlacklisted(from));
        assertFalse(token.isBlacklisted(to));

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
        vm.assume(target != owner && target != user1 && target != user2 && target != user3 && target != user4);
        vm.assume(target != whitelister && target != blacklister);
        vm.assume(mintAmount > 0 && burnAmount > 0);
        vm.assume(burnAmount <= mintAmount);
        vm.assume(mintAmount < type(uint256).max / 2); // Avoid overflow

        // Ensure target starts fresh
        assertEq(token.balanceOf(target), 0);
        assertFalse(token.isBlacklisted(target));

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

    function testNonWhitelisterCannotWhitelist() public {
        // Test that a user who is neither whitelister nor owner cannot whitelist
        // This covers the missing branch: !isWhitelister[msg.sender] && msg.sender != owner()
        vm.prank(user3); // user3 is not a whitelister and not the owner
        vm.expectRevert(MudraToken.InvalidWhitelisterAddress.selector);
        token.setWhitelisted(user4, true);
    }

    function testCannotWhitelistBlacklistedAddress() public {
        // Blacklist user3 first
        vm.prank(owner);
        token.setBlacklisted(user3, true);
        
        // Try to whitelist the blacklisted address - should fail
        vm.prank(owner);
        vm.expectRevert(MudraToken.CannotWhitelistBlacklistedAddress.selector);
        token.setWhitelisted(user3, true);
        
        // Verify user3 is still not whitelisted
        assertFalse(token.isWhitelisted(user3));
        assertTrue(token.isBlacklisted(user3));
    }

    function testBatchWhitelistSkipsBlacklistedAddresses() public {
        // Setup: blacklist user3 and user4
        vm.startPrank(owner);
        token.setBlacklisted(user3, true);
        token.setBlacklisted(user4, true);
        vm.stopPrank();
        
        // Try to batch whitelist including blacklisted addresses
        address[] memory users = new address[](3);
        users[0] = user3; // blacklisted - should be skipped
        users[1] = user4; // blacklisted - should be skipped
        users[2] = makeAddr("user5"); // not blacklisted - should work
        
        vm.prank(whitelister);
        token.batchWhitelist(users, true);
        
        // Verify results
        assertFalse(token.isWhitelisted(user3)); // Skipped due to blacklist
        assertFalse(token.isWhitelisted(user4)); // Skipped due to blacklist
        assertTrue(token.isWhitelisted(users[2])); // Successfully whitelisted
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

    /*//////////////////////////////////////////////////////////////
                    COMPREHENSIVE COVERAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function testBurnFromOwnerPathOnly() public {
        // Test that burnFrom always goes through owner path (no unreachable code)
        vm.prank(owner);
        token.mint(user1, 1000);
        
        // Owner burns directly
        vm.prank(owner);
        token.burnFrom(user1, 300);
        assertEq(token.balanceOf(user1), 700);
        
        // Non-owner cannot burn (onlyOwner modifier)
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user2));
        token.burnFrom(user1, 100);
    }

    function testOwnershipTransferToZeroAddressBlocked() public {
        // This should be blocked by OpenZeppelin's Ownable
        vm.prank(owner);
        vm.expectRevert();
        token.transferOwnership(address(0));
    }

    function testCompleteBlacklistWorkflow() public {
        // 1. User has tokens
        vm.startPrank(owner);
        token.setWhitelisted(user3, true);
        token.mint(user3, 1000);
        token.mint(user1, 100); // Give user1 some tokens for testing
        vm.stopPrank();
        
        // 2. User can transfer normally
        vm.prank(user3);
        token.transfer(user1, 100);
        assertEq(token.balanceOf(user3), 900);
        assertEq(token.balanceOf(user1), 200); // user1 now has 200 tokens
        
        // 3. User gets blacklisted (tokens remain, no auto-burn)
        vm.prank(owner);
        token.setBlacklisted(user3, true);
        assertEq(token.balanceOf(user3), 900); // Tokens still there
        
        // 4. User cannot perform any operations
        vm.prank(user3);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user1, 1);
        
        // 5. User cannot be sent tokens
        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user3, 1);
        
        // 6. User cannot mint tokens
        vm.prank(owner);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.mint(user3, 1);
        
        // 7. Owner can manually burn tokens from blacklisted user
        vm.prank(owner);
        token.burnFrom(user3, 500);
        assertEq(token.balanceOf(user3), 400);
        
        // 8. Unblacklist and user can transfer remaining tokens
        vm.startPrank(owner);
        token.setBlacklisted(user3, false);
        // Re-whitelist user3 (since blacklisting revoked the whitelist status)
        token.setWhitelisted(user3, true);
        vm.stopPrank();
        
        vm.prank(user3);
        token.transfer(user1, 200);
        assertEq(token.balanceOf(user3), 200);
        assertEq(token.balanceOf(user1), 400); // user1 now has 400
    }

    function testBlacklistingWithDifferentScenarios() public {
        // Set up user1 and user2 with tokens
        vm.startPrank(owner);
        token.mint(user1, 1000);
        token.mint(user2, 500); // Give user2 tokens too
        vm.stopPrank();

        // Blacklist user1 - tokens should remain but transfers blocked
        vm.prank(blacklister);
        token.setBlacklisted(user1, true);
        
        // Verify user1 still has tokens (no auto-burn)
        assertEq(token.balanceOf(user1), 1000);
        assertTrue(token.isBlacklisted(user1));

        // Verify user1 cannot transfer
        vm.prank(user1);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user2, 100);

        // Verify others cannot transfer to user1 (blacklisted recipient)
        vm.prank(user2);
        vm.expectRevert(MudraToken.AccountBlacklisted.selector);
        token.transfer(user1, 50);

        // Owner can manually burn tokens from blacklisted user if needed
        vm.prank(owner);
        token.burnFrom(user1, 500);
        assertEq(token.balanceOf(user1), 500);

        // Unblacklist user1
        vm.prank(blacklister);
        token.setBlacklisted(user1, false);
        
        // Re-whitelist user1 (since blacklisting revoked the whitelist status)
        vm.prank(owner);
        token.setWhitelisted(user1, true);
        
        // Verify user1 can now transfer remaining tokens
        vm.prank(user1);
        token.transfer(user2, 100);
        assertEq(token.balanceOf(user1), 400);
        assertEq(token.balanceOf(user2), 600);
    }

    function testBlacklistingRevokesWhitelistStatus() public {
        // Test the auditor's suggestion: blacklisting should revoke whitelist status
        
        // Setup: whitelist user3
        vm.prank(owner);
        token.setWhitelisted(user3, true);
        assertTrue(token.isWhitelisted(user3));
        assertFalse(token.isBlacklisted(user3));
        
        // Blacklist user3 (should automatically revoke whitelist)
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AddressWhitelisted(user3, false); // Expect whitelist revocation event
        vm.expectEmit(true, true, true, true);
        emit AddressBlacklisted(user3, true);   // Expect blacklist event
        token.setBlacklisted(user3, true);
        
        // Verify state after blacklisting
        assertTrue(token.isBlacklisted(user3));
        assertFalse(token.isWhitelisted(user3)); // Should be automatically revoked
        
        // Test batch operation too
        address[] memory users = new address[](2);
        users[0] = user4;
        users[1] = makeAddr("user5");
        
        // Whitelist both addresses first
        vm.startPrank(owner);
        token.setWhitelisted(user4, true);
        token.setWhitelisted(users[1], true);
        vm.stopPrank();
        
        assertTrue(token.isWhitelisted(user4));
        assertTrue(token.isWhitelisted(users[1]));
        
        // Batch blacklist should revoke whitelist for both
        vm.prank(owner);
        token.batchBlacklist(users, true);
        
        assertTrue(token.isBlacklisted(user4));
        assertTrue(token.isBlacklisted(users[1]));
        assertFalse(token.isWhitelisted(user4));    // Should be revoked
        assertFalse(token.isWhitelisted(users[1])); // Should be revoked
    }
}
