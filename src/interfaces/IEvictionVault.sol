// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEvictionVault {
    function deposit() external payable;
    function withdraw(uint256 amount) external;

 
    function setMerkleRoot(bytes32 root) external;
    function claim(bytes32[] calldata proof, uint256 amount) external;

   
    function emergencyWithdrawAll(address payable recipient) external;

    function votePause() external;
    function voteUnpause() external;

    function verifySignature(
        address signer,
        bytes32 messageHash,
        bytes memory signature
    ) external pure returns (bool);
}
