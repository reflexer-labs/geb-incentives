/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/
* Synthetix: GebUniswapIncentives.sol
*
* Docs: https://docs.synthetix.io/
*
*
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

pragma solidity ^0.6.7;

import "./IRewardDistributionRecipient.sol";
import "../lp/LPTokenWrapper.sol";

import "../zeppelin/math/Math.sol";
import "../zeppelin/utils/ReentrancyGuard.sol";

contract GebUniswapSingleDistributionIncentives is IRewardDistributionRecipient, LPTokenWrapper, Math, ReentrancyGuard {
    // --- Variables ---
    IERC20  public rewardToken;

    uint256 public globalReward;
    uint256 public rewardsDuration;
    uint256 public startTime;
    uint256 public periodFinish;
    uint256 public instantExitPercentage;
    uint256 public rewardDelay;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256)                           public userRewardPerTokenPaid;
    mapping(address => uint256)                           public rewards;
    mapping(address => mapping(uint256 => DelayedReward)) public delayedRewards;

    uint256 constant public THOUSAND = 1000;

    // --- Structs ---
    struct DelayedReward {
        uint totalAmount;
        uint exitedAmount;
        uint latestExitTime;
    }

    // --- Events ---
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event DelayReward(address account, uint startTime, uint totalDelayedReward);
    event WithdrewExtraRewardTokens(address caller, uint globalReward, uint amount);

    // --- Modifiers ---
    modifier checkStart(){
        require(block.timestamp >= startTime, "GebUniswapSingleDistributionIncentives/not-start");
        _;
    }
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(
        address lpToken_,
        address rewardToken_,
        uint256 rewardsDuration_,
        uint256 startTime_,
        uint256 rewardDelay_,
        uint256 instantExitPercentage_
    ) public {
        require(lpToken_ != address(0), "GebUniswapSingleDistributionIncentives/invalid-lp-token");
        require(rewardToken_ != address(0), "GebUniswapSingleDistributionIncentives/invalid-reward-token");
        require(rewardsDuration_ > 0, "GebUniswapSingleDistributionIncentives/invalid-duration");
        require(startTime_ > now, "GebUniswapSingleDistributionIncentives/invalid-start-time");
        require(instantExitPercentage_ <= THOUSAND, "GebUniswapSingleDistributionIncentives/");
        lpToken               = IERC20(lpToken_);
        rewardToken           = IERC20(rewardToken_);
        rewardsDuration       = rewardsDuration_;
        startTime             = startTime_;
        rewardDelay           = rewardDelay_;
        instantExitPercentage = instantExitPercentage_;
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthority {
        require(now < startTime, "GebUniswapSingleDistributionIncentives/surpassed-start-time");
        if (parameter == "startTime") {
          require(val > now, "GebUniswapSingleDistributionIncentives/invalid-new-start-time");
          require(periodFinish == 0, "GebUniswapSingleDistributionIncentives/distribution-already-set-up");
          startTime = val;
        } else if (parameter == "rewardsDuration") {
          require(periodFinish == 0, "GebUniswapSingleDistributionIncentives/distribution-already-set-up");
          rewardsDuration = val;
        } else if (parameter == "rewardDelay") { 
          rewardDelay = val;
        } else if (parameter == "instantExitPercentage") {
          require(val <= THOUSAND, "GebUniswapSingleDistributionIncentives/invalid-instant-exit-percentage");
          instantExitPercentage = val;
        } else revert("GebUniswapSingleDistributionIncentives/modify-unrecognized-param");
    }

    /// @notice Returns tokens not locked for rewards to caller (only Authority)
    function withdrawExtraRewardTokens() external isAuthority {
        require(rewardToken.balanceOf(address(this)) > globalReward, "GebUniswapSingleDistributionIncentives/does-not-exceed-global-reward");
        uint amountToWithdraw = sub(rewardToken.balanceOf(address(this)), globalReward);
        safeTransfer(rewardToken, msg.sender, amountToWithdraw);
        emit WithdrewExtraRewardTokens(msg.sender, globalReward, amountToWithdraw);
    }

    // --- Distribution Logic ---
    /// @notice Returns last time distribution was active (now if currently active)
    function lastTimeRewardApplicable() public view returns (uint256) {
        return min(block.timestamp, periodFinish);
    }

    /// @notice Rewards per token staked
    /// @return returns rewards per token staked
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            add(
              rewardPerTokenStored,
              div(mul(mul(sub(lastTimeRewardApplicable(), lastUpdateTime), rewardRate), 1e18), totalSupply())
            );
    }

    /// @notice Calculate earned tokens up to now
    /// @param account Account of the staker
    /// @return balance earned up to now
    function earned(address account) public view returns (uint256) { 
        return add(div(mul(balanceOf(account), sub(rewardPerToken(), userRewardPerTokenPaid[account])), 1e18), rewards[account]);
    }

    /// @notice Used for staking on the contract (previous ERC20 approval required)
    /// @param amount Amount to be staked
    function stake(uint256 amount) override public updateReward(msg.sender) checkStart nonReentrant {
        require(amount > 0, "GebUniswapSingleDistributionIncentives/cannot-stake-zero");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    /// @notice Used for withdrawing staked tokens
    /// @param amount Amount to be withdrawn
    function withdraw(uint256 amount) override public updateReward(msg.sender) nonReentrant { 
        require(amount > 0, "GebUniswapSingleDistributionIncentives/cannot-withdraw-zero"); 
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice One TX exit (withdraws full balance and gets all available rewards)
    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    /// @notice Wthdraw rewards after locking period
    /// @param account Account that owns a reward balance
    /// @param timestamp Timestamp when getReward was called (and instant rewards paid)
    function getLockedReward(address account, uint timestamp) external nonReentrant { 
        require(delayedRewards[account][timestamp].totalAmount > 0, "GebUniswapSingleDistributionIncentives/invalid-slot");
        require(
          delayedRewards[account][timestamp].totalAmount > delayedRewards[account][timestamp].exitedAmount,
          "GebUniswapSingleDistributionIncentives/exited-whole-delayed-amount"
        );
        uint timeElapsedSinceLastExit = sub(now, delayedRewards[account][timestamp].latestExitTime);
        require(timeElapsedSinceLastExit > 0, "GebUniswapSingleDistributionIncentives/invalid-time-elapsed");
        uint amountToExit;
        if (now >= add(timestamp, rewardDelay)) {
            amountToExit = sub(delayedRewards[account][timestamp].totalAmount, delayedRewards[account][timestamp].exitedAmount);
        } else {
            amountToExit = mul(div(mul(timeElapsedSinceLastExit, 100), rewardDelay), delayedRewards[account][timestamp].totalAmount) / 100;
        }
        delayedRewards[account][timestamp].latestExitTime = now;
        delayedRewards[account][timestamp].exitedAmount = add(delayedRewards[account][timestamp].exitedAmount, amountToExit);
        if (amountToExit > 0) {
            globalReward = sub(globalReward,amountToExit);
            safeTransfer(rewardToken, account, amountToExit);
        }
    }

    /// @notice Wthdraw rewards available, locking the remainder
    function getReward() public updateReward(msg.sender) checkStart nonReentrant {
        uint256 totalReward = earned(msg.sender);
        if (totalReward > 0) {
            rewards[msg.sender] = 0;
        }
        uint256 instantReward = mul(totalReward, instantExitPercentage) / THOUSAND;
        uint256 totalDelayedReward = sub(totalReward, instantReward);
        if (totalDelayedReward > 0) {
            delayedRewards[msg.sender][now] = DelayedReward(totalDelayedReward, 0, now);
            emit DelayReward(msg.sender, now, totalDelayedReward);
        }
        if (instantReward > 0) {
            globalReward = sub(globalReward, instantReward);
            emit RewardPaid(msg.sender, instantReward);
            safeTransfer(rewardToken, msg.sender, instantReward);
        }
    }

    /// @notice Notify distribution amount
    function notifyRewardAmount(uint256 reward)
        override
        external
        onlyRewardDistribution
        updateReward(address(0))
    {
        if (block.timestamp > startTime) {
          require(block.timestamp < periodFinish, "GebUniswapSingleDistributionIncentives/passed-period-finish");

          uint256 remaining = sub(periodFinish, block.timestamp);
          uint256 leftover = mul(remaining, rewardRate);
          rewardRate = div(add(reward, leftover), rewardsDuration);
          periodFinish = add(block.timestamp, rewardsDuration);
          lastUpdateTime = block.timestamp;
          globalReward = add(globalReward, leftover);
        } else {
          rewardRate = div(reward, rewardsDuration);
          periodFinish = add(startTime, rewardsDuration);
          lastUpdateTime = startTime;
          globalReward = reward;
        }

        emit RewardAdded(reward);
        uint balance = rewardToken.balanceOf(address(this));
        require(rewardRate <= div(balance,rewardsDuration), "GebUniswapSingleDistributionIncentives/Provided-reward-too-high");        
    }
}
