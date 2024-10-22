// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MultisignatureWallet {
    // signers mapping
    mapping(address => bool) public isSigner;
    // signer count
    uint256 public signerCount;
    // required approvals
    uint256 public immutable requiredApprovals;

    // proposal type
    enum ProposalType {
        Execute,
        AddSigner,
        RemoveSigner
    }

    // proposal struct
    struct Proposal {
        address to;
        uint256 value;
        bytes data;
        uint256 approvals;
        mapping(address => bool) hasApproved;
        bool executed;
        ProposalType proposalType;
        address signerToAddOrRemove; // used for add or remove signer
    }

    // proposals mapping
    mapping(uint256 => Proposal) public proposals;
    // proposal count
    uint256 public proposalCount;

    error Unauthorized();
    error InvalidParameters();
    error ProposalAlreadyExecuted();
    error InsufficientApprovals();
    error ExecutionFailed();
    error CannotRemoveSigner();
    error InsufficientBalance();

    event ProposalCreated(
        uint256 indexed proposalId,
        address to,
        uint256 value,
        bytes data,
        ProposalType proposalType,
        address signerToAddOrRemove
    );
    event ProposalApproved(uint256 indexed proposalId, address signer);
    event ProposalExecuted(
        uint256 indexed proposalId, address to, uint256 value, ProposalType proposalType, address signerToAddOrRemove
    );
    event SignerAdded(address signer);
    event SignerRemoved(address signer);

    constructor(address[] memory _signers, uint256 _requiredApprovals) {
        if (_signers.length == 0 || _requiredApprovals == 0 || _requiredApprovals > _signers.length) {
            revert InvalidParameters();
        }

        for (uint256 i = 0; i < _signers.length; i++) {
            isSigner[_signers[i]] = true;
            emit SignerAdded(_signers[i]);
        }
        signerCount = _signers.length;
        requiredApprovals = _requiredApprovals;
    }

    modifier onlySigner() {
        if (!isSigner[msg.sender]) revert Unauthorized();
        _;
    }

    // create proposal
    function createProposal(
        address to,
        uint256 value,
        bytes memory data,
        ProposalType proposalType,
        address signerToAddOrRemove
    )
        external
        onlySigner
    {
        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.to = to;
        proposal.value = value;
        proposal.data = data;
        proposal.proposalType = proposalType;
        proposal.signerToAddOrRemove = signerToAddOrRemove;

        emit ProposalCreated(proposalId, to, value, data, proposalType, signerToAddOrRemove);
    }

    // approve proposal
    function approveProposal(uint256 proposalId) external onlySigner {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.hasApproved[msg.sender]) return;

        proposal.approvals++;
        proposal.hasApproved[msg.sender] = true;

        emit ProposalApproved(proposalId, msg.sender);
    }

    // execute proposal
    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.approvals < requiredApprovals) revert InsufficientApprovals();

        proposal.executed = true;

        if (proposal.proposalType == ProposalType.Execute) {
            // only execute if there is enough balance
            if (address(this).balance < proposal.value) revert InsufficientBalance();
            // transfer the value to the to address with the proposal.data
            (bool success,) = proposal.to.call{ value: proposal.value }(proposal.data);
            if (!success) revert ExecutionFailed();
        } else if (proposal.proposalType == ProposalType.AddSigner) {
            if (!isSigner[proposal.signerToAddOrRemove]) {
                isSigner[proposal.signerToAddOrRemove] = true;
                signerCount++;
                emit SignerAdded(proposal.signerToAddOrRemove);
            }
        } else if (proposal.proposalType == ProposalType.RemoveSigner) {
            if (isSigner[proposal.signerToAddOrRemove]) {
                if (signerCount <= requiredApprovals) revert CannotRemoveSigner();
                isSigner[proposal.signerToAddOrRemove] = false;
                signerCount--;
                emit SignerRemoved(proposal.signerToAddOrRemove);
            }
        }

        emit ProposalExecuted(
            proposalId, proposal.to, proposal.value, proposal.proposalType, proposal.signerToAddOrRemove
        );
    }

    // check if a signer has approved a proposal
    function hasApproved(uint256 proposalId, address signer) public view returns (bool) {
        return proposals[proposalId].hasApproved[signer];
    }

    // receive Ether
    receive() external payable { }
}
