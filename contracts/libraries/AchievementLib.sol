// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../utils/Constants.sol";

library AchievementLib {
    struct AchievementResult {
        uint256 bonus;
        uint256 newMilestone;
    }

    function checkAchievements(
        uint256 consecutive,
        uint256 lastMilestone
    ) internal pure returns (AchievementResult memory) {
        AchievementResult memory result;
        result.bonus = 0;
        result.newMilestone = lastMilestone;

        if (
            consecutive >= Constants.ACHIEVEMENT_MILESTONE_5 &&
            lastMilestone < Constants.ACHIEVEMENT_MILESTONE_5
        ) {
            result.bonus = Constants.ACHIEVEMENT_BONUS_5;
            result.newMilestone = Constants.ACHIEVEMENT_MILESTONE_5;
        } else if (
            consecutive >= Constants.ACHIEVEMENT_MILESTONE_10 &&
            lastMilestone < Constants.ACHIEVEMENT_MILESTONE_10
        ) {
            result.bonus = Constants.ACHIEVEMENT_BONUS_10;
            result.newMilestone = Constants.ACHIEVEMENT_MILESTONE_10;
        } else if (
            consecutive >= Constants.ACHIEVEMENT_MILESTONE_20 &&
            lastMilestone < Constants.ACHIEVEMENT_MILESTONE_20
        ) {
            result.bonus = Constants.ACHIEVEMENT_BONUS_20;
            result.newMilestone = Constants.ACHIEVEMENT_MILESTONE_20;
        }

        return result;
    }
}

