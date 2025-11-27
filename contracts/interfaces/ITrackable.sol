// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITrackable {
    struct TrackedEvent {
        bytes32 eventId;
        address user;
        string eventType;
        uint256 timestamp;
        bytes data;
    }

    function getEventHistory(
        address user,
        uint256 from,
        uint256 to
    ) external view returns (TrackedEvent[] memory);

    function getEventCount(address user) external view returns (uint256);

    function getEventById(bytes32 eventId) external view returns (TrackedEvent memory);
}

