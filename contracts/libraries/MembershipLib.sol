// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IMarketplace.sol";
import "../utils/Constants.sol";

library MembershipLib {

    function getMultiplier(
        IMarketplace marketplace,
        address user
    ) internal view returns (uint256) {
        uint256 membershipMultiplier;
        
        if (address(marketplace) == address(0)) {
            membershipMultiplier = Constants.MULTIPLIER_BASIC;
        } else {
            (IMarketplace.MembershipTier tier, , uint256 expiresAt) = marketplace.getUserMembership(user);
            
            if (expiresAt < block.timestamp) {
                membershipMultiplier = Constants.MULTIPLIER_BASIC;
            } else if (tier == IMarketplace.MembershipTier.Pro) {
                membershipMultiplier = Constants.MULTIPLIER_PRO;
            } else if (tier == IMarketplace.MembershipTier.Plus) {
                membershipMultiplier = Constants.MULTIPLIER_PLUS;
            } else {
                membershipMultiplier = Constants.MULTIPLIER_BASIC;
            }
        }

        // Check for active multiplier boost and add it to membership multiplier
        // Both are stored in 10x format (e.g., 15 = 1.5x, 20 = 2x)
        (uint256 boostMultiplier, ) = marketplace.getMultiplierBoost(user);
        if (boostMultiplier > 0) {
            // Add boost to membership multiplier (both in 10x format)
            return membershipMultiplier + boostMultiplier;
        }
        
        return membershipMultiplier;
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
        } else if (tier == IMarketplace.MembershipTier.Basic) {
            if (currentStreak >= Constants.STREAK_THRESHOLD_HIGH) {
                return Constants.STREAK_BONUS_BASIC_HIGH;
            }
            if (currentStreak >= Constants.STREAK_THRESHOLD_LOW) {
                return Constants.STREAK_BONUS_BASIC_LOW;
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
        
        // Multipliers are stored as 10x (e.g., 15 = 1.5x), so divide by 10
        return ((baseSuperGem * multiplier) / 10) + streakBonus;
    }
}

