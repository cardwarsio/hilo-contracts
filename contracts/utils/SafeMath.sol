// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library SafeMath {
    error Overflow();
    error Underflow();
    error DivisionByZero();

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        if (c < a) {
            revert Overflow();
        }
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b > a) {
            revert Underflow();
        }
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        if (c / a != b) {
            revert Overflow();
        }
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert DivisionByZero();
        }
        return a / b;
    }
}

