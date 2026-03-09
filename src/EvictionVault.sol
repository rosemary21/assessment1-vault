// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IEvictionVault.sol";
import "./base/MultiSigBase.sol";


contract EvictionVault is MultiSigBase, ReentrancyGuard, IEvictionVault {


    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 amount);
    event MerkleRootSet(bytes32 indexed newRoot);
    event Claim(address indexed claimant, uint256 amount);
    event VotedPause(address indexed voter, uint256 currentVotes);
    event VotedUnpause(address indexed voter, uint256 currentVotes);


    constructor(address[] memory _owners, uint256 _threshold) payable {
        require(_owners.length > 0, "no owners");
        require(
            _threshold > 0 && _threshold <= _owners.length,
            "invalid threshold"
        );

        threshold = _threshold;

        for (uint256 i = 0; i < _owners.length; i++) {
            address o = _owners[i];
            require(o != address(0), "zero-address owner");
            require(!isOwner[o], "duplicate owner");
            isOwner[o] = true;
            owners.push(o);
        }

        if (msg.value > 0) {
            totalVaultValue = msg.value;
        }
    }


    receive() external payable {
        balances[msg.sender] += msg.value;
        totalVaultValue     += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
        totalVaultValue     += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    
    function withdraw(uint256 amount) external notPaused nonReentrant {
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        totalVaultValue      -= amount;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "ETH transfer failed");

        emit Withdrawal(msg.sender, amount);
    }


    function setMerkleRoot(bytes32 root) external onlyViaMultisig {
        merkleRoot = root;
        emit MerkleRootSet(root);
    }


    function claim(
        bytes32[] calldata proof,
        uint256 amount
    ) external notPaused nonReentrant {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(
            MerkleProof.processProof(proof, leaf) == merkleRoot,
            "invalid merkle proof"
        );
        require(!claimed[msg.sender], "already claimed");

        claimed[msg.sender]  = true;
        totalVaultValue     -= amount;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "claim transfer failed");

        emit Claim(msg.sender, amount);
    }

  
    function emergencyWithdrawAll(
        address payable recipient
    ) external onlyViaMultisig nonReentrant {
        require(recipient != address(0), "zero recipient");

        uint256 balance = address(this).balance;
        totalVaultValue = 0;

        (bool ok,) = recipient.call{value: balance}("");
        require(ok, "emergency transfer failed");
    }

  
    function votePause() external onlyOwner notPaused {
        require(!pauseVoted[msg.sender], "already voted to pause");

        pauseVoted[msg.sender] = true;
        pauseVoteCount++;
        emit VotedPause(msg.sender, pauseVoteCount);

        if (pauseVoteCount >= threshold) {
            paused = true;
            _resetPauseVotes();
        }
    }

    
    function voteUnpause() external onlyOwner {
        require(paused, "not paused");
        require(!unpauseVoted[msg.sender], "already voted to unpause");

        unpauseVoted[msg.sender] = true;
        unpauseVoteCount++;
        emit VotedUnpause(msg.sender, unpauseVoteCount);

        if (unpauseVoteCount >= threshold) {
            paused = false;
            _resetUnpauseVotes();
        }
    }

   
    function verifySignature(
        address signer,
        bytes32 messageHash,
        bytes memory signature
    ) external pure returns (bool) {
        return ECDSA.recover(messageHash, signature) == signer;
    }


    function _resetPauseVotes() private {
        for (uint256 i = 0; i < owners.length; i++) {
            pauseVoted[owners[i]] = false;
        }
        pauseVoteCount = 0;
    }

    function _resetUnpauseVotes() private {
        for (uint256 i = 0; i < owners.length; i++) {
            unpauseVoted[owners[i]] = false;
        }
        unpauseVoteCount = 0;
    }
}
