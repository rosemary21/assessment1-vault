// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VaultStorage.sol";

abstract contract MultiSigBase is VaultStorage {


    event Submission(uint256 indexed txId);
    event Confirmation(uint256 indexed txId, address indexed owner);
    event Execution(uint256 indexed txId);


    modifier onlyOwner() {
        require(isOwner[msg.sender], "not an owner");
        _;
    }

    modifier notPaused() {
        require(!paused, "vault is paused");
        _;
    }

    modifier onlyViaMultisig() {
        require(msg.sender == address(this), "only callable via multisig");
        _;
    }


    function submitTransaction(
        address to,
        uint256 value,
        bytes calldata data
    ) external onlyOwner notPaused {
        uint256 id = txCount++;
        transactions[id] = Transaction({
            to:            to,
            value:         value,
            data:          data,
            executed:      false,
            confirmations: 1,
            submissionTime: block.timestamp,
            executionTime:  0
        });
        confirmed[id][msg.sender] = true;

        
        if (threshold <= 1) {
            transactions[id].executionTime = block.timestamp + TIMELOCK_DURATION;
        }

        emit Submission(id);
        emit Confirmation(id, msg.sender);
    }

    
    function confirmTransaction(uint256 txId) external onlyOwner notPaused {
        Transaction storage txn = transactions[txId];
        require(!txn.executed, "already executed");
        require(!confirmed[txId][msg.sender], "already confirmed");

        confirmed[txId][msg.sender] = true;
        txn.confirmations++;

        if (txn.confirmations >= threshold && txn.executionTime == 0) {
            txn.executionTime = block.timestamp + TIMELOCK_DURATION;
        }

        emit Confirmation(txId, msg.sender);
    }

  
    function executeTransaction(uint256 txId) external notPaused {
        Transaction storage txn = transactions[txId];
        require(txn.confirmations >= threshold, "insufficient confirmations");
        require(!txn.executed, "already executed");
    
        require(txn.executionTime > 0, "timelock not initiated");
        require(block.timestamp >= txn.executionTime, "timelock not elapsed");

        txn.executed = true;
        (bool success,) = txn.to.call{value: txn.value}(txn.data);
        require(success, "transaction execution failed");

        emit Execution(txId);
    }
}
