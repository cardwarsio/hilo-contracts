// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ReentrancyLib {
    error ReentrantCall();

    struct ReentrancyGuard {
        uint256 status;
    }

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    function init(ReentrancyGuard storage guard) internal {
        guard.status = _NOT_ENTERED;
    }

    function enter(ReentrancyGuard storage guard) internal {
        if (guard.status == _ENTERED) {
            revert ReentrantCall();
        }
        guard.status = _ENTERED;
    }

    function exit(ReentrancyGuard storage guard) internal {
        guard.status = _NOT_ENTERED;
    }

    function check(ReentrancyGuard storage guard) internal view returns (bool) {
        return guard.status == _NOT_ENTERED;
    }
}

