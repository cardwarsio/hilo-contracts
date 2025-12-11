// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMarketplace {
    enum MembershipTier {
        Basic,
        Plus,
        Pro
    }

    function getUserMembership(
        address _user
    )
        external
        view
        returns (MembershipTier tier, uint256 purchasedAt, uint256 expiresAt);
    function getUserExtraCredits(address _user) external view returns (uint256);
    function getUserItemPurchaseCount(
        address _user,
        uint256 _itemId
    ) external view returns (uint256);
    function getMultiplierBoost(
        address _user
    ) external view returns (uint256 multiplier, uint256 expiresAt);
}
