// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBoost {
    enum BoostType {
        None,
        TxBoost
    }

    struct ActiveBoost {
        BoostType boostType;
        uint64 expiresAt;
        uint256 remainingUses;
    }

    function getUserBoost(address _user) external view returns (ActiveBoost memory);
    function consumeBoost(address _user) external returns (bool);
}

