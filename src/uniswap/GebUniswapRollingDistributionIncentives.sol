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

import "../lp/LPTokenWrapper.sol";
import "./Auth.sol";
import "../zeppelin/math/Math.sol";
import "../zeppelin/utils/ReentrancyGuard.sol";

contract GebUniswapRollingDistributionIncentives is LPTokenWrapper, Math, Auth, ReentrancyGuard {
    // --- Variables ---
    IERC20  public rewardToken;

    uint256 public globalReward;
    uint256 public lastFinish;
    uint256 public campaignCount;

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
        uint rewardDelay;
        uint instantExitPercentage;
        mapping(address => uint256) rewards;
        mapping(address => uint256) userRewardPerTokenPaid;
    }

    // --- Events ---
    event CampaignAdded(uint256 campaignId);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event DelayReward(address account, uint campaignId, uint startTime, uint totalDelayedReward);
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

    constructor(
        address lpToken_,
        address rewardToken_
    ) public {
        require(lpToken_ != address(0), "GebUniswapRollingDistributionIncentives/invalid-lp-token");
        require(rewardToken_ != address(0), "GebUniswapRollingDistributionIncentives/invalid-reward-token");
        lpToken               = IERC20(lpToken_);
        rewardToken           = IERC20(rewardToken_);
    }

    // --- Administration ---
    /// @notice Modify Campaign parameters (only authed)
    /// @param parameter Parameter to be changed
    /// @param campaignId Campaign in wich to set the parameter
    /// @param val new parameter value
    function modifyParameters(bytes32 parameter, uint256 campaignId, uint256 val) external isAuthority {
        Campaign storage campaign = campaigns[campaignId];
        require(campaign.startTime > block.timestamp, "GebUniswapRollingDistributionIncentives/invalid-campaign");

        if (parameter == "reward") {
          require(val > 0, "GebUniswapRollingDistributionIncentives/invalid-reward");
          campaign.reward = val;
        } else if (parameter == "startTime") {
          require(val > block.timestamp, "GebUniswapRollingDistributionIncentives/invalid-new-start-time");
          campaign.startTime = val;
          campaign.lastUpdateTime = val;
        } else if (parameter == "duration") {
          require(val > 0, "GebUniswapRollingDistributionIncentives/invalid-duration");
          campaign.duration = val;
          campaign.finish = campaign.startTime + val;
        } else if (parameter == "rewardDelay") { 
          campaign.rewardDelay = val;
        } else if (parameter == "instantExitPercentage") {
          require(val <= THOUSAND, "GebUniswapRollingDistributionIncentives/invalid-instant-exit-percentage");
          campaign.instantExitPercentage = val;
        } else revert("GebUniswapRollingDistributionIncentives/modify-unrecognized-param");
    }

    /// @notice Returns Id of currently active campaign, zero if none are active
    function currentCampaign() public view returns (uint) {
        if (campaignCount == 0) return 0;
        else
            for (uint i = campaignCount; campaigns[i].finish >= block.timestamp; i--) {
                if (campaigns[i].startTime <= block.timestamp) return i;
            }
    }

    /// @notice Returns tokens not locked for rewards to caller (only Authority)
    function withdrawExtraRewardTokens() external isAuthority {
        require(rewardToken.balanceOf(address(this)) > globalReward, "GebUniswapRollingDistributionIncentives/does-not-exceed-global-reward");
        uint amountToWithdraw = sub(rewardToken.balanceOf(address(this)), globalReward);
        safeTransfer(rewardToken, msg.sender, amountToWithdraw);
        emit WithdrewExtraRewardTokens(msg.sender, globalReward, amountToWithdraw);
    }

    // --- Distribution Logic ---
    /// @notice Returns last time distribution was active (now if currently active)
    /// @param campaignId Id of the campaign
    function lastTimeRewardApplicable(uint campaignId) public view returns (uint256) {
        return min(block.timestamp, campaigns[campaignId].finish);
    }

    /// @notice Rewards per token staked
    /// @return returns rewards per token staked
    /// @param campaignId Id of the campaign
    function rewardPerToken(uint campaignId) public view returns (uint256) {
        require(campaignId <= campaignCount, "GebUniswapRollingDistributionIncentives/inexistent-campaign");
        Campaign storage campaign = campaigns[campaignId];
        require(campaign.startTime != 0, "GebUniswapRollingDistributionIncentives/campaign-cancelled");
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
    /// @param campaignId Id of the campaign
    /// @return balance earned up to now
    function earned(address account, uint campaignId) public view returns (uint256) { 
        Campaign storage campaign = campaigns[campaignId];
        return add(div(mul(balanceOf(account), sub(rewardPerToken(campaignId), campaign.userRewardPerTokenPaid[account])), 1e18), campaign.rewards[account]);
    }

    /// @notice Used for staking on the contract (previous ERC20 approval required)
    /// @param amount Amount to be staked
    function stake(uint256 amount) override public {
        stake(amount, msg.sender);
    }

    /// @notice Used for staking on the contract for another address (previous ERC20 approval required)
    /// @param amount Amount to be staked
    /// @param owner Account that will own both the rewards and liquidity
    function stake(uint256 amount, address owner) override public updateReward(owner) nonReentrant {
        require(amount > 0, "GebUniswapRollingDistributionIncentives/cannot-stake-zero");
        require(owner != address(0), "GebUniswapRollingDistributionIncentives/invalid-owner");
        super.stake(amount, owner);
        emit Staked(owner, amount);
    }

    /// @notice Used for withdrawing staked tokens
    /// @param amount Amount to be withdrawn
    function withdraw(uint256 amount) override public updateReward(msg.sender) nonReentrant { 
        require(amount > 0, "GebUniswapRollingDistributionIncentives/cannot-withdraw-zero"); 
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice One TX exit (withdraws full balance and gets available rewards from current or last campaign)
    function exit() external {
        withdraw(balanceOf(msg.sender));
        uint currentCampaign_ = currentCampaign();
        getReward((currentCampaign_ == 0) ? campaignCount : currentCampaign_);
    }

    /// @notice Wthdraw rewards after locking period
    /// @param account Account that owns a reward balance
    /// @param campaignId Id of the campaign
    /// @param timestamp Timestamp when getReward was called (and instant rewards paid)
    function getLockedReward(address account, uint campaignId, uint timestamp) external nonReentrant { 
        require(delayedRewards[account][timestamp].totalAmount > 0, "GebUniswapRollingDistributionIncentives/invalid-slot");
        require(
          delayedRewards[account][timestamp].totalAmount > delayedRewards[account][timestamp].exitedAmount,
          "GebUniswapRollingDistributionIncentives/exited-whole-delayed-amount"
        );
        uint timeElapsedSinceLastExit = sub(block.timestamp, delayedRewards[account][timestamp].latestExitTime);
        require(timeElapsedSinceLastExit > 0, "GebUniswapRollingDistributionIncentives/invalid-time-elapsed");
        uint amountToExit;
        uint rewardDelay = campaigns[campaignId].rewardDelay;
        if (block.timestamp >= add(timestamp, rewardDelay)) {
            amountToExit = sub(delayedRewards[account][timestamp].totalAmount, delayedRewards[account][timestamp].exitedAmount);
        } else {
            amountToExit = mul(div(mul(timeElapsedSinceLastExit, 100), rewardDelay), delayedRewards[account][timestamp].totalAmount) / 100;
        }
        delayedRewards[account][timestamp].latestExitTime = block.timestamp;
        delayedRewards[account][timestamp].exitedAmount = add(delayedRewards[account][timestamp].exitedAmount, amountToExit);
        if (amountToExit > 0) {
            globalReward = sub(globalReward,amountToExit);
            safeTransfer(rewardToken, account, amountToExit);
        }
    }

    /// @notice Wthdraw rewards available, locking the remainder
    /// @param campaignId Id of the campaign
    function getReward(uint campaignId) public updateReward(msg.sender) nonReentrant {
        uint256 totalReward = earned(msg.sender, campaignId);
        if (totalReward > 0) {
            campaigns[campaignId].rewards[msg.sender] = 0;
        }
        uint256 instantReward = mul(totalReward, campaigns[campaignId].instantExitPercentage) / THOUSAND;
        uint256 totalDelayedReward = sub(totalReward, instantReward);
        if (totalDelayedReward > 0) {
            delayedRewards[msg.sender][block.timestamp] = DelayedReward(totalDelayedReward, 0, block.timestamp);
            emit DelayReward(msg.sender, campaignId, block.timestamp, totalDelayedReward);
        }
        if (instantReward > 0) {
            globalReward = sub(globalReward, instantReward);
            emit RewardPaid(msg.sender, instantReward);
            safeTransfer(rewardToken, msg.sender, instantReward);
        }
    }

    /// @notice Notify distribution amount
    /// @param reward Reward for campaign (the contract needs enough balance for the campaign to be created)
    /// @param startTime Campaign startTime
    /// @param duration Campaign duration
    /// @param rewardDelay Vesting period for locked tokens
    /// @param instantExitPercentage Percentage to be paid immediately on getRewards (1000 == 100%)
    function newCampaign
    (
        uint256 reward,
        uint256 startTime,
        uint256 duration,
        uint256 rewardDelay,
        uint256 instantExitPercentage
    )
        external
        isAuthority
    {
        require(reward > 0, "GebUniswapRollingDistributionIncentives/invalid-reward");
        require(startTime > block.timestamp, "GebUniswapRollingDistributionIncentives/startTime-in-the-past");
        require(startTime > lastFinish, "GebUniswapRollingDistributionIncentives/startTime-before-last-campaign-finishes");
        require(duration > 0, "GebUniswapRollingDistributionIncentives/invalid-duration");
        require(instantExitPercentage <= THOUSAND, "GebUniswapRollingDistributionIncentives/invalid-instant-exit-percentage");

        campaignCount = add(campaignCount, 1);
        campaigns[campaignCount] = Campaign(
            reward,
            startTime,
            duration,
            div(reward, duration),   // rewardRate
            add(startTime,duration), // finish
            startTime,               // lastUpdateTime
            0,                       // rewardPerTokenStored
            (instantExitPercentage == THOUSAND) ? 0 : rewardDelay,
            instantExitPercentage
        );
        lastFinish = add(startTime, duration);
        globalReward = add(globalReward,reward);
        emit CampaignAdded(campaignCount);
    }

    function cancelCampaign(uint campaignId) external isAuthority {
        Campaign storage campaign = campaigns[campaignId];
        require(campaign.startTime > now, "GebUniswapRollingDistributionIncentives/campaign-started");
        campaign.startTime = 0;
        campaign.duration = 0;
        campaign.finish = 0;
        globalReward = sub(globalReward, campaign.reward);
    }
}