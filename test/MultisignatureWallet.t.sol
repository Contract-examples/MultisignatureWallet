// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MultisignatureWallet.sol";

contract MultisignatureWalletTest is Test {
    MultisignatureWallet public wallet;
    address[] public signers;
    uint256 public constant REQUIRED_APPROVALS = 2;

    address public user1;
    address public user2;
    address public user3;
    address public nonSigner;

    function setUp() public {
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);
        nonSigner = address(0x4);

        signers = [user1, user2, user3];
        wallet = new MultisignatureWallet(signers, REQUIRED_APPROVALS);

        // deal 10 ETH
        vm.deal(address(wallet), 10 ether);
    }

    function testConstructor() public {
        assertEq(wallet.signerCount(), 3);
        assertEq(wallet.requiredApprovals(), REQUIRED_APPROVALS);
        assertTrue(wallet.isSigner(user1));
        assertTrue(wallet.isSigner(user2));
        assertTrue(wallet.isSigner(user3));
        assertFalse(wallet.isSigner(nonSigner));
    }

    function testCreateProposal() public {
        vm.prank(user1);
        wallet.createProposal(nonSigner, 1 ether, "", MultisignatureWallet.ProposalType.Execute, address(0));

        (
            address to,
            uint256 value,
            ,
            uint256 approvals,
            bool executed,
            MultisignatureWallet.ProposalType proposalType,
            address signerToAddOrRemove
        ) = wallet.proposals(0);
        assertEq(to, nonSigner);
        assertEq(value, 1 ether);
        assertEq(approvals, 0);
        assertFalse(executed);
        assertEq(uint256(proposalType), uint256(MultisignatureWallet.ProposalType.Execute));
        assertEq(signerToAddOrRemove, address(0));
    }

    function testApproveProposal() public {
        vm.prank(user1);
        wallet.createProposal(nonSigner, 1 ether, "", MultisignatureWallet.ProposalType.Execute, address(0));

        vm.prank(user2);
        wallet.approveProposal(0);

        (,,, uint256 approvals,,,) = wallet.proposals(0);
        assertEq(approvals, 1);
        assertTrue(wallet.hasApproved(0, user2));
    }

    function testExecuteProposal() public {
        vm.prank(user1);
        wallet.createProposal(nonSigner, 1 ether, "", MultisignatureWallet.ProposalType.Execute, address(0));

        vm.prank(user2);
        wallet.approveProposal(0);

        vm.prank(user3);
        wallet.approveProposal(0);

        uint256 initialBalance = address(nonSigner).balance;
        wallet.executeProposal(0);

        (,,,, bool executed,,) = wallet.proposals(0);
        assertTrue(executed);
        assertEq(address(nonSigner).balance, initialBalance + 1 ether);
    }

    function testAddSigner() public {
        vm.prank(user1);
        wallet.createProposal(address(0), 0, "", MultisignatureWallet.ProposalType.AddSigner, nonSigner);

        vm.prank(user2);
        wallet.approveProposal(0);

        vm.prank(user3);
        wallet.approveProposal(0);

        wallet.executeProposal(0);

        assertTrue(wallet.isSigner(nonSigner));
        assertEq(wallet.signerCount(), 4);
    }

    function testRemoveSigner() public {
        vm.prank(user1);
        wallet.createProposal(address(0), 0, "", MultisignatureWallet.ProposalType.RemoveSigner, user3);

        vm.prank(user2);
        wallet.approveProposal(0);

        vm.prank(user3);
        wallet.approveProposal(0);

        wallet.executeProposal(0);

        assertFalse(wallet.isSigner(user3));
        assertEq(wallet.signerCount(), 2);
    }

    function testFailNonSignerCreateProposal() public {
        vm.prank(nonSigner);
        wallet.createProposal(nonSigner, 1 ether, "", MultisignatureWallet.ProposalType.Execute, address(0));
    }

    function testFailInsufficientApprovals() public {
        vm.prank(user1);
        wallet.createProposal(nonSigner, 1 ether, "", MultisignatureWallet.ProposalType.Execute, address(0));

        vm.prank(user2);
        wallet.approveProposal(0);

        wallet.executeProposal(0);
    }

    function testFailRemoveLastRequiredSigner() public {
        // First, remove one signer to reach the minimum required signers
        vm.prank(user1);
        wallet.createProposal(address(0), 0, "", MultisignatureWallet.ProposalType.RemoveSigner, user3);

        vm.prank(user2);
        wallet.approveProposal(0);

        vm.prank(user1);
        wallet.approveProposal(0);

        wallet.executeProposal(0);

        // Now try to remove another signer, which should fail
        vm.prank(user1);
        wallet.createProposal(address(0), 0, "", MultisignatureWallet.ProposalType.RemoveSigner, user2);

        vm.prank(user2);
        wallet.approveProposal(1);

        vm.prank(user1);
        wallet.approveProposal(1);

        wallet.executeProposal(1);
    }

    function testReceiveEther() public {
        uint256 initialBalance = address(wallet).balance;
        vm.deal(address(this), 1 ether);
        (bool success,) = address(wallet).call{ value: 1 ether }("");
        require(success, "Failed to send Ether");
        assertEq(address(wallet).balance, initialBalance + 1 ether);
    }
}
