// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEventTracker {
    event EventTracked(
        bytes32 indexed eventId,
        address indexed emitter,
        string eventType,
        bytes data,
        uint256 indexed timestamp
    );

    function trackEvent(
        string memory eventType,
        bytes memory data
    ) external returns (bytes32);
}

