// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IERC20.sol";

contract MockUSDT is IERC20 {
    string public constant name = "Tether USD";
    string public constant symbol = "USDT";
    uint8 public constant decimals = 6; // USDT uses 6 decimals

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(uint256 initialSupply) {
        _totalSupply = initialSupply;
        _balances[msg.sender] = initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address to,
        uint256 amount
    ) external override returns (bool) {
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) {
            revert();
        }
        if (to == address(0)) {
            revert();
        }

        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) {
            revert();
        }
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) {
            revert();
        }
        if (spender == address(0)) {
            revert();
        }

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) {
                revert();
            }
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    // Mint function - removed for security (only faucet can mint)

    // Faucet functionality
    uint256 public constant FAUCET_AMOUNT = 20 * 10 ** 6; // 20 USDT with 6 decimals
    uint256 public constant FAUCET_COOLDOWN = 1 hours;
    mapping(address => uint256) public lastFaucetClaim;

    event FaucetClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    function claimFaucet() external {
        address user = msg.sender;
        require(user != address(0), "Invalid address");

        uint256 currentTime = block.timestamp;
        uint256 lastClaim = lastFaucetClaim[user];

        require(
            currentTime >= lastClaim + FAUCET_COOLDOWN,
            "Faucet cooldown not expired"
        );

        lastFaucetClaim[user] = currentTime;

        unchecked {
            _totalSupply += FAUCET_AMOUNT;
            _balances[user] += FAUCET_AMOUNT;
        }

        emit Transfer(address(0), user, FAUCET_AMOUNT);
        emit FaucetClaimed(user, FAUCET_AMOUNT, currentTime);
    }

    function getFaucetCooldown(address user) external view returns (uint256) {
        require(user != address(0), "Invalid address");

        uint256 lastClaim = lastFaucetClaim[user];
        if (lastClaim == 0) {
            return 0; // Never claimed, can claim now
        }
        uint256 nextClaimTime = lastClaim + FAUCET_COOLDOWN;
        if (block.timestamp >= nextClaimTime) {
            return 0; // Cooldown expired, can claim now
        }
        return nextClaimTime - block.timestamp; // Time remaining
    }

    function canClaimFaucet(address user) external view returns (bool) {
        if (user == address(0)) {
            return false;
        }

        uint256 lastClaim = lastFaucetClaim[user];
        if (lastClaim == 0) {
            return true; // Never claimed, can claim now
        }
        return block.timestamp >= lastClaim + FAUCET_COOLDOWN;
    }
}
