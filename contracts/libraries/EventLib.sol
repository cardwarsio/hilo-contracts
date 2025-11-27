// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library EventLib {
    function generateEventId(
        address emitter,
        string memory eventType,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(emitter, eventType, nonce));
    }

    function generateEventId(
        address emitter,
        string memory eventType,
        address user,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(emitter, eventType, user, timestamp));
    }
}

