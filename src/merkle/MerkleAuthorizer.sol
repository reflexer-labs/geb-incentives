// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.7;

import "../zeppelin/ERC20/IERC20.sol";
import "../zeppelin/cryptography/MerkleProof.sol";

contract MerkleAuthorizer is MerkleProof {
    bytes32 public immutable merkleRoot;

    constructor(bytes32 merkleRoot_) public {
        merkleRoot = merkleRoot_;
    }

    function isMerkleAuthorized(uint256 index, address account, uint256 amount, bytes32[] memory merkleProof) public view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        return MerkleProof.verify(merkleProof, merkleRoot, node);
    }
}
