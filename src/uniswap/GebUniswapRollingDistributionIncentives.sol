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

contract GebUniswapRollingDistributionIncentives is IRewardDistributionRecipient, LPTokenWrapper, Math, ReentrancyGuard {
    // --- Variables ---
    IERC20  public rewardToken;

    uint256 public globalReward;
    uint256 public lastFinish;
    uint256 public campaignCount;
    uint256 public instantExitPercentage;
    uint256 public rewardDelay;

    mapping(address => mapping(uint256 => DelayedReward)) public delayedRewards;
    mapping(uint => Campaign)                             public campaigns;

    uint256 constant public THOUSAND = 1000;

    // --- Structs ---
    struct DelayedReward {
        uint totalAmount;
        uint exitedAmount;
        uint latestExitTime;
    }

    struct Campaign {
        uint reward;
        uint startTime;
        uint duration;
        uint rewardRate;
        uint finish;
        uint lastUpdateTime;
        uint rewardPerTokenStored;
        mapping(address => uint256) rewards;
        mapping(address => uint256) userRewardPerTokenPaid;
    }

    // --- Events ---
    event CampaignAdded(uint256 campaign);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event DelayReward(address account, uint startTime, uint totalDelayedReward);
    event WithdrewExtraRewardTokens(address caller, uint globalReward, uint amount);

    // --- Modifiers ---
    modifier updateReward(address account) {
        uint campaignId = currentCampaign();
        if (campaignId != 0) {
            Campaign storage campaign = campaigns[campaignId];

            campaign.rewardPerTokenStored = rewardPerToken(campaignId);
            campaign.lastUpdateTime = lastTimeRewardApplicable(campaignId);
            if (account != address(0)) {
                campaign.rewards[account] = earned(account, campaignId);
                campaign.userRewardPerTokenPaid[account] = campaign.rewardPerTokenStored;
            }
        }
        _;
    }

    function currentCampaign() public view returns (uint) {
        if (campaignCount == 0) return 0;
        else
            for (uint i = campaignCount; campaigns[i].finish >= now; i--) {
                if (campaigns[i].startTime <= now) return i;
            }
    }

    constructor(
        address lpToken_,
        address rewardToken_,
        uint256 rewardDelay_,
        uint256 instantExitPercentage_        
    ) public {
        require(lpToken_ != address(0), "GebUniswapSingleDistributionIncentives/invalid-lp-token");
        require(rewardToken_ != address(0), "GebUniswapSingleDistributionIncentives/invalid-reward-token");
        require(instantExitPercentage_ <= THOUSAND, "GebUniswapSingleDistributionIncentives/");
        lpToken               = IERC20(lpToken_);
        rewardToken           = IERC20(rewardToken_);
        rewardDelay           = rewardDelay_;
        instantExitPercentage = instantExitPercentage_;
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthority {
        if (parameter == "rewardDelay") { 
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
    function lastTimeRewardApplicable(uint campaignId) public view returns (uint256) {
        return min(block.timestamp, campaigns[campaignId].finish);
    }

    /// @notice Rewards per token staked
    /// @return returns rewards per token staked
    function rewardPerToken(uint campaignId) public view returns (uint256) {
        Campaign storage campaign = campaigns[campaignId];
        if (totalSupply() == 0) {
            return campaign.rewardPerTokenStored;
        }
        return
            add(
              campaign.rewardPerTokenStored,
              div(mul(mul(sub(lastTimeRewardApplicable(campaignId), campaign.lastUpdateTime), campaign.rewardRate), 1e18), totalSupply())
            );
    }

    /// @notice Calculate earned tokens up to now
    /// @param account Account of the staker
    /// @return balance earned up to now
    function earned(address account, uint campaignId) public view returns (uint256) { 
        Campaign storage campaign = campaigns[campaignId];
        return add(div(mul(balanceOf(account), sub(rewardPerToken(campaignId), campaign.userRewardPerTokenPaid[account])), 1e18), campaign.rewards[account]);
    }

    /// @notice Used for staking on the contract (previous ERC20 approval required)
    /// @param amount Amount to be staked
    function stake(uint256 amount) override public updateReward(msg.sender) nonReentrant {
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
        // getReward();
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
    function getReward(uint campaignId) public updateReward(msg.sender) nonReentrant {
        uint256 totalReward = earned(msg.sender, campaignId);
        if (totalReward > 0) {
            campaigns[campaignId].rewards[msg.sender] = 0;
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
    function newCampaign
    (
        uint256 reward,
        uint256 startTime,
        uint256 duration
    )
        external
        onlyRewardDistribution
        // updateReward(address(0))
    {
        require(reward > 0, "GebUniswapRollingDistributionIncentives/invalid-reward");
        require(startTime >= block.timestamp, "GebUniswapRollingDistributionIncentives/startTime-in-the-past");
        require(startTime > lastFinish, "GebUniswapRollingDistributionIncentives/startTime-before-last-campaign-finishes");
        require(duration > 0, "GebUniswapRollingDistributionIncentives/invalid-duration");

        campaignCount = add(campaignCount, 1);
        campaigns[campaignCount] = Campaign(
            reward,
            startTime,
            rewardDelay,
            div(reward, duration), // rewardRate
            add(startTime,duration), // finish
            startTime, // lastUpdateTime
            0 // rewardPerToken
        );
        lastFinish = add(startTime, duration);
        globalReward = add(globalReward,reward);
        require(globalReward <= rewardToken.balanceOf(address(this)), "GebUniswapRollingDistributionIncentives/Provided-reward-too-high");
        emit CampaignAdded(campaignCount);
    }
}