// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


abstract contract VaultStorage {

    struct Transaction {
        address to;
        uint256 value;
        bytes   data;
        bool    executed;
        uint256 confirmations;
        uint256 submissionTime;
    
        uint256 executionTime;
    }

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public threshold;

    mapping(uint256 => mapping(address => bool)) public confirmed;
    mapping(uint256 => Transaction) public transactions;
    uint256 public txCount;


    mapping(address => uint256) public balances;
    uint256 public totalVaultValue;


    bytes32 public merkleRoot;
    mapping(address => bool) public claimed;


    bool public paused;

    mapping(address => bool) public pauseVoted;
    uint256 public pauseVoteCount;

    mapping(address => bool) public unpauseVoted;
    uint256 public unpauseVoteCount;


    uint256 public constant TIMELOCK_DURATION = 1 hours;
}
