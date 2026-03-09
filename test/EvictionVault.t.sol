// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {EvictionVault} from "../src/EvictionVault.sol";

contract EvictionVaultTest is Test {
    EvictionVault vault;

    address owner;
    address alice;
    address bob;

    uint256 constant ONE_HOUR = 3_601; // just past the 1-hour timelock

    function merkleLeaf(address addr, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(addr, amount));
    }

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob   = makeAddr("bob");

        vm.deal(owner, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob,   10 ether);

        address[] memory _owners = new address[](1);
        _owners[0] = owner;

        // Deploy with a 1-of-1 multisig and seed 1 ETH so there is always ETH for tests.
        vm.prank(owner);
        vault = new EvictionVault{value: 1 ether}(_owners, 1);
    }

    function test_Deployment_SetsOwnerAndThreshold() public view {
        assertTrue(vault.isOwner(owner));
        assertEq(vault.threshold(), 1);
        assertFalse(vault.paused());
        assertEq(vault.totalVaultValue(), 1 ether);
    }

    function test_Deposit_TracksETH() public {
        vm.prank(alice);
        vault.deposit{value: 0.5 ether}();

        assertEq(vault.balances(alice), 0.5 ether);
    }

    function test_Deposit_ViaReceive() public {
        // Direct ETH transfer — triggers receive()
        vm.prank(alice);
        (bool ok,) = address(vault).call{value: 0.25 ether}("");
        assertTrue(ok);

        // FIX verified: credited to msg.sender (alice), NOT tx.origin
        assertEq(vault.balances(alice), 0.25 ether);
    }

    function test_Withdraw_ReturnsETHToDepositor() public {
        vm.prank(alice);
        vault.deposit{value: 0.5 ether}();

        uint256 before = alice.balance;
        // FIX verified: uses .call instead of .transfer
        vm.prank(alice);
        vault.withdraw(0.5 ether);

        assertEq(alice.balance - before, 0.5 ether);
        assertEq(vault.balances(alice), 0);
    }

    function test_Timelock_ExecutesETHTransferAfterDelay() public {
        // Owner submits a transaction sending 0.1 ETH to alice
        vm.prank(owner);
        vault.submitTransaction(alice, 0.1 ether, "");

        // Try to execute immediately — must revert (timelock not elapsed)
        vm.expectRevert("timelock not elapsed");
        vault.executeTransaction(0);

        // Advance time past the 1-hour timelock
        vm.warp(block.timestamp + ONE_HOUR);

        // Now execution should succeed and alice should receive 0.1 ETH
        uint256 before = alice.balance;
        vault.executeTransaction(0);
        assertEq(alice.balance - before, 0.1 ether);
    }

    function test_MerkleClaim_WhitelistedAddressCanClaimAfterRootSet() public {
        uint256 claimAmount = 0.2 ether;
        // For a single-leaf Merkle tree the root equals the leaf itself.
        bytes32 root = merkleLeaf(alice, claimAmount);

        // Encode setMerkleRoot(root) and submit it as a multisig transaction.
        bytes memory setRootData = abi.encodeWithSignature("setMerkleRoot(bytes32)", root);
        vm.prank(owner);
        vault.submitTransaction(address(vault), 0, setRootData);

        // FIX verified: setMerkleRoot can only be called via multisig
        vm.expectRevert("only callable via multisig");
        vm.prank(alice);
        vault.setMerkleRoot(root);

        vm.warp(block.timestamp + ONE_HOUR);
        vault.executeTransaction(0); // sets merkle root

        bytes32[] memory proof = new bytes32[](0);

        uint256 before = alice.balance;
        vm.prank(alice);
        vault.claim(proof, claimAmount);
        assertEq(alice.balance - before, claimAmount);

        vm.expectRevert("already claimed");
        vm.prank(alice);
        vault.claim(proof, claimAmount);
    }

    function test_PauseUnpause_WhenThresholdVotesReached() public {
        vm.prank(owner);
        vault.votePause();
        assertTrue(vault.paused());

        vm.prank(alice);
        vault.deposit{value: 0.1 ether}();

        vm.expectRevert("vault is paused");
        vm.prank(alice);
        vault.withdraw(0.1 ether);

        vm.prank(owner);
        vault.voteUnpause();
        assertFalse(vault.paused());

        uint256 before = alice.balance;
        vm.prank(alice);
        vault.withdraw(0.1 ether);
        assertEq(alice.balance - before, 0.1 ether);
    }

    function test_EmergencyWithdraw_DrainsVaultOnlyViaMulsig() public {
        // Direct call must revert
        vm.expectRevert("only callable via multisig");
        vm.prank(alice);
        vault.emergencyWithdrawAll(payable(alice));

        uint256 vaultBalance = address(vault).balance;
        bytes memory emergencyData = abi.encodeWithSignature(
            "emergencyWithdrawAll(address)",
            owner
        );

        vm.prank(owner);
        vault.submitTransaction(address(vault), 0, emergencyData);

        vm.warp(block.timestamp + ONE_HOUR);

        uint256 before = owner.balance;
        vault.executeTransaction(0);
        assertEq(owner.balance - before, vaultBalance);

        assertEq(address(vault).balance, 0);
    }
}
