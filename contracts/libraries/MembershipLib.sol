// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IMarketplace.sol";
import "../utils/Constants.sol";

library MembershipLib {

    function getMultiplier(
        IMarketplace marketplace,
        address user
    ) internal view returns (uint256) {
        if (address(marketplace) == address(0)) {
            return Constants.MULTIPLIER_BASIC;
        }

        (IMarketplace.MembershipTier tier, , uint256 expiresAt) = marketplace.getUserMembership(user);
        
        if (expiresAt < block.timestamp) {
            return Constants.MULTIPLIER_BASIC;
        }

        if (tier == IMarketplace.MembershipTier.Pro) {
            return Constants.MULTIPLIER_PRO;
        } else if (tier == IMarketplace.MembershipTier.Plus) {
            return Constants.MULTIPLIER_PLUS;
        }
        
        return Constants.MULTIPLIER_BASIC;
    }

    function getStreakBonus(
        IMarketplace marketplace,
        address user,
        uint256 currentStreak
    ) internal view returns (uint256) {
        if (address(marketplace) == address(0)) {
            return 0;
        }

        (IMarketplace.MembershipTier tier, , uint256 expiresAt) = marketplace.getUserMembership(user);
        
        if (expiresAt < block.timestamp) {
            return 0;
        }

        if (tier == IMarketplace.MembershipTier.Pro) {
            if (currentStreak >= Constants.STREAK_THRESHOLD_HIGH) {
                return Constants.STREAK_BONUS_PRO_HIGH;
            }
            if (currentStreak >= Constants.STREAK_THRESHOLD_LOW) {
                return Constants.STREAK_BONUS_PRO_LOW;
            }
        } else if (tier == IMarketplace.MembershipTier.Plus) {
            if (currentStreak >= Constants.STREAK_THRESHOLD_HIGH) {
                return Constants.STREAK_BONUS_PLUS_HIGH;
            }
            if (currentStreak >= Constants.STREAK_THRESHOLD_LOW) {
                return Constants.STREAK_BONUS_PLUS_LOW;
            }
        }
        
        return 0;
    }

    function calculateSuperGems(
        bool isSuitWin,
        uint256 multiplier,
        uint256 streakBonus
    ) internal pure returns (uint256) {
        uint256 baseSuperGem = isSuitWin 
            ? Constants.BASE_SUPERGEM_SUIT_WIN 
            : Constants.BASE_SUPERGEM_WIN;
        
        return (baseSuperGem * multiplier) + streakBonus;
    }
}

