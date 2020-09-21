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

contract GebUniswapSingleDistributionIncentives is IRewardDistributionRecipient, LPTokenWrapper, Math {
    // --- Variables ---
    IERC20  public rewardToken;

    uint256 public globalReward;
    uint256 public DURATION;
    uint256 public startTime;
    uint256 public periodFinish;
    uint256 public exitCooldown;
    uint256 public instantExitPercentage;
    uint256 public rewardDelay;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256)                           public userRewardPerTokenPaid;
    mapping(address => uint256)                           public rewards;
    mapping(address => uint256)                           public lastExitTime;
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
        uint256 DURATION_,
        uint256 startTime_,
        uint256 exitCooldown_,
        uint256 rewardDelay_,
        uint256 instantExitPercentage_
    ) public {
        require(lpToken_ != address(0), "GebUniswapSingleDistributionIncentives/invalid-lp-token");
        require(rewardToken_ != address(0), "GebUniswapSingleDistributionIncentives/invalid-reward-token");
        require(DURATION_ > 0, "GebUniswapSingleDistributionIncentives/invalid-duration");
        require(startTime_ > now, "GebUniswapSingleDistributionIncentives/invalid-start-time");
        require(instantExitPercentage_ <= THOUSAND, "GebUniswapSingleDistributionIncentives/");
        lpToken               = IERC20(lpToken_);
        rewardToken           = IERC20(rewardToken_);
        DURATION              = DURATION_;
        startTime             = startTime_;
        exitCooldown          = exitCooldown_;
        rewardDelay           = rewardDelay_;
        instantExitPercentage = instantExitPercentage_;
    }

    // --- Boolean Logic ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, uint256 val) external onlyOwner {
        require(now < startTime, "GebUniswapSingleDistributionIncentives/surpassed-start-time");
        if (parameter == "startTime") {
          require(val > now, "GebUniswapSingleDistributionIncentives/invali-new-start-time");
          startTime = val;
        } else if (parameter == "DURATION") {
          require(val > 0, "GebUniswapSingleDistributionIncentives/invalid-new-duration");
          DURATION = val;
        } else if (parameter == "exitCooldown") {
          exitCooldown = val;
        } else if (parameter == "rewardDelay") {
          rewardDelay = val;
        } else if (parameter == "instantExitPercentage") {
          require(val <= THOUSAND, "GebUniswapSingleDistributionIncentives/invalid-instant-exit-percentage");
          instantExitPercentage = val;
        } else revert("GebUniswapSingleDistributionIncentives/modify-unrecognized-param");
    }
    function withdrawExtraRewardTokens() external onlyOwner {
        require(rewardToken.balanceOf(address(this)) > globalReward, "GebUniswapSingleDistributionIncentives/does-not-exceed-global-reward");
        uint amountToWithdraw = sub(rewardToken.balanceOf(address(this)), globalReward);
        safeTransfer(rewardToken, msg.sender, amountToWithdraw);
        emit WithdrewExtraRewardTokens(msg.sender, globalReward, amountToWithdraw);
    }

    // --- Distribution Logic ---
    function lastTimeRewardApplicable() public view returns (uint256) {
        return min(block.timestamp, periodFinish);
    }

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

    function earned(address account) public view returns (uint256) {
        return add(div(mul(balanceOf(account), sub(rewardPerToken(), userRewardPerTokenPaid[account])), 1e18), rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount) override public updateReward(msg.sender) checkStart {
        require(amount > 0, "GebUniswapSingleDistributionIncentives/cannot-stake-zero");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) override public updateReward(msg.sender) checkStart {
        require(amount > 0, "GebUniswapSingleDistributionIncentives/cannot-withdraw-zero");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        require(
          either(lastExitTime[msg.sender] == 0, sub(now, lastExitTime[msg.sender]) >= exitCooldown),
          "GebUniswapSingleDistributionIncentives/wait-more"
        );
        lastExitTime[msg.sender] = now;
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function exit(address account, uint timestamp) external {
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
        delayedRewards[account][timestamp].exitedAmount = add(delayedRewards[account][timestamp].exitedAmount, amountToExit);
        if (amountToExit > 0) {
          safeTransfer(rewardToken, account, amountToExit);
        }
    }

    function getReward() public updateReward(msg.sender) checkStart {
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
            safeTransfer(rewardToken, msg.sender, instantReward);
            emit RewardPaid(msg.sender, instantReward);
        }
    }

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
          rewardRate = div(add(reward, leftover), DURATION);
          globalReward = add(reward, leftover);

          lastUpdateTime = block.timestamp;
          periodFinish = add(block.timestamp, DURATION);
          emit RewardAdded(reward);
        } else {
          rewardRate = div(reward, DURATION);
          lastUpdateTime = startTime;
          periodFinish = add(startTime, DURATION);
          globalReward = reward;
          emit RewardAdded(reward);
        }
    }
}
