/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/
* Synthetix
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

pragma solidity 0.6.7;

import "../lp/LPTokenWrapper.sol";
import "./Auth.sol";
import "./LinkedList.sol";
import "../zeppelin/math/Math.sol";
import "../zeppelin/utils/ReentrancyGuard.sol";

contract RollingDistributionIncentives is LPTokenWrapper, Math, Auth, ReentrancyGuard {
    using LinkedList for LinkedList.List;

    // --- Variables ---
    // The token used to reward stakers
    IERC20  public rewardToken;
    // The total amount of rewards that were and will be distributed
    uint256 public globalReward;
    // The total amount of campaigns ever created
    uint256 public campaignCount;
    // Max amount of campaigns to keep active in memory at any time
    uint256 public maxCampaigns;
    // Earliest campaign kept active in memory
    uint256 public firstCampaign;
    // The latest scheduled campaign
    uint256 public lastCampaign;
    // Access flag, indicates whether this contract is still active
    uint256 public contractEnabled;

    // Rewards to be unlocked for each campaign
    mapping(address => mapping(uint256 => DelayedReward)) public   delayedRewards;
    // Campaign data
    mapping(uint => Campaign)                             public   campaigns;
    // List of scheduled campaigns
    LinkedList.List                                       internal campaignList;

    uint256 constant public HUNDRED               = 100;
    uint256 constant public THOUSAND              = 1000;
    uint256 constant public MILLION               = 1000000;
    uint256 constant public DEFAULT_MAX_CAMPAIGNS = 16;
    uint256 constant public WAD                   = 1e18;

    // --- Structs ---
    struct DelayedReward {
        uint256 totalAmount;
        uint256 exitedAmount;
        uint256 latestExitTime;
    }

    struct Campaign {
        uint256 reward;
        uint256 startTime;
        uint256 duration;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 rewardDelay;
        uint256 instantExitPercentage;
        mapping(address => uint256) rewards;
        mapping(address => uint256) userRewardPerTokenPaid;
    }

    // --- Events ---
    event CampaignAdded(uint256 campaignId);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event DisableContract();
    event DelayReward(address account, uint256 campaignId, uint256 startTime, uint256 totalDelayedReward);
    event DelayedRewardPaid(address indexed user, uint256 campaignId, uint256 reward);
    event WithdrewExtraRewardTokens(address caller, uint256 globalReward, uint256 amount);
    event ModifyParameters(bytes32 indexed parameter, uint256 data);
    event ModifyParameters(bytes32 indexed parameter, uint256 campaign, uint256 data);

    // --- Modifiers ---
    modifier updateReward(address account) {
        if (contractEnabled == 1)
            _updateRewards(account, lastCampaign);
        _;
    }
    modifier updateCampaignReward(address account, uint256 campaignId) {
        _updateRewards(account, campaignId);
        _;
    }

    /// @notice Modifier helper, calculates rewards
    /// @dev Will recursively iterate through campaigns, updating campaign data and user data (within a campaign) when needed.
    /// @dev It is bounded by the number of campaigns that need to be updated (and will only update campaign or user data as necessary).
    /// @dev Users are their own "keepers". If users interact with this contract frequently, the won't incur high costs (the longer the user is inactive, the higher the gas cost).
    /// @dev Ultimately bounded by maxCampaigns.
    /// @param account User address
    /// @param campaignId Campaign id
    function _updateRewards(address account, uint256 campaignId) internal {
        if (campaignId == 0) return;
        Campaign storage campaign = campaigns[campaignId];
        bool update;

        if (campaign.lastUpdateTime != finish(campaignId)) { // campaign needs update
            campaign.rewardPerTokenStored = rewardPerToken(campaignId);
            campaign.lastUpdateTime = lastTimeRewardApplicable(campaignId);
            update = true;
        }
        if (campaign.userRewardPerTokenPaid[account] != campaign.rewardPerTokenStored) { // user needs update
            campaign.rewards[account] = earned(account, campaignId);
            campaign.userRewardPerTokenPaid[account] = campaign.rewardPerTokenStored;
            if (finish(campaignId) > block.timestamp || balanceOf(account) > 0)
                update = true;
        }

        if (update) { // keep on going backwards through the list until it finds a campaigns that is up to date.
            (, uint256 prevCampaign) = campaignList.prev(campaignId);
            _updateRewards(account, prevCampaign);
        }
    }

    /// @notice Constructor
    /// @param lpToken_ Liquidity provider token (tokens that users will stake)
    /// @param rewardToken_ Rewards token
    constructor(
        address lpToken_,
        address rewardToken_
    ) public {
        require(lpToken_ != address(0), "RollingDistributionIncentives/invalid-lp-token");
        require(rewardToken_ != address(0), "RollingDistributionIncentives/invalid-reward-token");
        lpToken         = IERC20(lpToken_);
        rewardToken     = IERC20(rewardToken_);
        maxCampaigns    = DEFAULT_MAX_CAMPAIGNS;
        contractEnabled = 1;
        emit ModifyParameters("maxCampaigns", DEFAULT_MAX_CAMPAIGNS);
    }

    // --- Boolean Logic ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Administration ---
    /// @notice Modify campaign parameters
    /// @param parameter Parameter to be changed
    /// @param campaignId Campaign for which to set the parameter
    /// @param val New parameter value
    function modifyParameters(bytes32 parameter, uint256 campaignId, uint256 val) external isAuthorized {
        Campaign storage campaign = campaigns[campaignId];

        if (parameter == "rewardDelay") {
          require(
              campaign.startTime > now ||
              val < campaign.rewardDelay,
              "RollingDistributionIncentives/invalid-reward-delay"
          );
          campaign.rewardDelay = val;
          emit ModifyParameters(parameter, campaignId, val);
          return;
        }

        require(campaign.startTime > now, "RollingDistributionIncentives/invalid-campaign");

        if (parameter == "reward") {
          require(val > 0, "RollingDistributionIncentives/invalid-reward");
          campaign.reward = val;
        } else if (parameter == "startTime") {
          require(val > now, "RollingDistributionIncentives/invalid-new-start-time");
          campaign.startTime = val;
          campaign.lastUpdateTime = val;
        } else if (parameter == "duration") {
          require(val > 0, "RollingDistributionIncentives/invalid-duration");
          campaign.duration = val;
        } else if (parameter == "instantExitPercentage") {
          require(val <= THOUSAND, "RollingDistributionIncentives/invalid-instant-exit-percentage");
          campaign.instantExitPercentage = val;
        } else revert("RollingDistributionIncentives/modify-unrecognized-param");

        emit ModifyParameters(parameter, campaignId, val);
    }

    /// @notice Modify campaign parameters
    /// @param parameter Parameter to be changed
    /// @param val New parameter value
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthorized {
        if (parameter == "maxCampaigns") {
          maxCampaigns = val;

          while (campaignList.range() > maxCampaigns) {
            uint256 campaignToDelete = firstCampaign;
            (, firstCampaign) = campaignList.next(firstCampaign);
            campaignList.del(campaignToDelete);
          }

        } else revert("RollingDistributionIncentives/modify-unrecognized-param");
        emit ModifyParameters(parameter, val);
    }

    /// @return The id of the currently active campaign, zero if none are active
    function currentCampaign() public view returns (uint256) {
        if (lastCampaign == 0) return 0;
        uint256 campaignId = lastCampaign;
        while (campaignId >= firstCampaign) {
            if (campaigns[campaignId].startTime <= now && finish(campaignId) >= now) return campaignId;
            (, campaignId) = campaignList.prev(campaignId);
        }
    }

    /// @notice Transfers tokens not locked for rewards to caller
    function withdrawExtraRewardTokens() external isAuthorized {
        require(rewardToken.balanceOf(address(this)) > globalReward, "RollingDistributionIncentives/does-not-exceed-global-reward");
        uint256 amountToWithdraw = sub(rewardToken.balanceOf(address(this)), globalReward);
        safeTransfer(rewardToken, msg.sender, amountToWithdraw);
        emit WithdrewExtraRewardTokens(msg.sender, globalReward, amountToWithdraw);
    }

    // --- Distribution Logic ---
    /// @notice Returns the last time distribution was active (now if currently active, startTime if in the future, finishTime if in the past)
    /// @param campaignId Id of the campaign
    function lastTimeRewardApplicable(uint256 campaignId) public view returns (uint256) {
        return min(max(now, campaigns[campaignId].startTime), finish(campaignId));
    }

    /// @notice Rewards per token staked, should be called every time the supply of LP tokens changes during a campaign
    /// @param campaignId Id of the campaign
    /// @return returns Rewards per token staked (amount of tokens paid per token staked during the entire duration
    ///             of the campaign or up to now if the campaign is active)
    function rewardPerToken(uint256 campaignId) public view returns (uint256) {
        require(campaignList.isNode(campaignId), "RollingDistributionIncentives/invalid-campaign");
        Campaign storage campaign = campaigns[campaignId];
        if (totalSupply() == 0 || campaign.lastUpdateTime == lastTimeRewardApplicable(campaignId)) {
            return campaign.rewardPerTokenStored;
        }
        return
          add(
            campaign.rewardPerTokenStored,
            div(mul(mul(sub(lastTimeRewardApplicable(campaignId), campaign.lastUpdateTime), campaign.rewardRate), WAD), totalSupply())
          );
    }

    /// @notice Calculate earned tokens for a single account in a given campaign
    /// @param account Account of the staker
    /// @param campaignId Id of the campaign
    /// @return The balance earned up to now (or up to the end time of the campaign), minus rewards already claimed
    function earned(address account, uint256 campaignId) public view returns (uint256) {
        Campaign storage campaign = campaigns[campaignId];
        return add(
          div(mul(balanceOf(account), sub(rewardPerToken(campaignId), campaign.userRewardPerTokenPaid[account])), WAD),
          campaign.rewards[account]
        );
    }

    /// @notice Used for staking on the contract (previous ERC20 approval required)
    /// @param amount Amount to be staked
    function stake(uint256 amount) override public {
        stake(amount, msg.sender);
    }

    /// @notice Used for staking in the contract on behalf of another address (previous ERC20 approval required)
    /// @param amount Amount to be staked
    /// @param owner Account that will own both the rewards and the added LP tokens
    function stake(uint256 amount, address owner) override public updateReward(owner) nonReentrant {
        require(contractEnabled == 1, "RollingDistributionIncentives/contract-disabled");
        require(amount > 0, "RollingDistributionIncentives/cannot-stake-zero");
        require(owner != address(0), "RollingDistributionIncentives/invalid-owner");
        require(currentCampaign() > 0, "RollingDistributionIncentives/campaigns-not-active");

        super.stake(amount, owner);
        emit Staked(owner, amount);
    }

    /// @notice Used for withdrawing staked tokens
    /// @param amount Amount to be withdrawn
    function withdraw(uint256 amount) override public updateReward(msg.sender) nonReentrant {
        require(amount > 0, "RollingDistributionIncentives/cannot-withdraw-zero");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Atomically withdraw the user's full balance and get available rewards from current or last campaign
    function exit() external {
        withdraw(balanceOf(msg.sender));
        uint256 currentCampaign_ = currentCampaign();
        getReward((currentCampaign_ == 0) ? lastCampaign : currentCampaign_);
    }

    /// @notice Withdraw rewards after locking period
    /// @param account Account that owns a reward balance
    /// @param campaignId Id of the campaign
    function getLockedReward(address account, uint256 campaignId) public {
        require(
          delayedRewards[account][campaignId].totalAmount > delayedRewards[account][campaignId].exitedAmount,
          "RollingDistributionIncentives/exited-whole-delayed-amount"
        );

        uint256 campaignFinish = finish(campaignId);
        require(campaignFinish < now, "RollingDistributionIncentives/vesting-not-yet-started");

        uint256 timeElapsedSinceLastExit = sub(now, delayedRewards[account][campaignId].latestExitTime);
        require(timeElapsedSinceLastExit > 0, "RollingDistributionIncentives/invalid-time-elapsed");

        uint256 amountToExit;
        uint256 rewardDelay = campaigns[campaignId].rewardDelay;
        if (now >= add(campaignFinish, rewardDelay)) {
            amountToExit = sub(delayedRewards[account][campaignId].totalAmount, delayedRewards[account][campaignId].exitedAmount);
        } else {
            amountToExit = mul(
              div(mul(timeElapsedSinceLastExit, MILLION), rewardDelay),
              delayedRewards[account][campaignId].totalAmount
            ) / MILLION;
        }

        require(amountToExit > 0, "RollingDistributionIncentives/no-rewards");

        delayedRewards[account][campaignId].latestExitTime = now;
        delayedRewards[account][campaignId].exitedAmount = add(delayedRewards[account][campaignId].exitedAmount, amountToExit);

        globalReward = sub(globalReward,amountToExit);
        safeTransfer(rewardToken, account, amountToExit);
        emit DelayedRewardPaid(account, campaignId, amountToExit);
    }

    /// @notice Withdraw available rewards (instant rewards will be transferred imediately, remainder is locked)
    /// @param campaignId Id of the campaign
    function getReward(uint256 campaignId) public updateCampaignReward(msg.sender, campaignId) nonReentrant {
        require(campaignList.isNode(campaignId), "RollingDistributionIncentives/invalid-campaign");
        uint256 totalReward = earned(msg.sender, campaignId);
        if (totalReward > 0) {
            campaigns[campaignId].rewards[msg.sender] = 0;
        }
        require(totalReward > 0, "RollingDistributionIncentives/no-rewards-available");
        uint256 instantReward      = mul(totalReward, campaigns[campaignId].instantExitPercentage) / THOUSAND;
        uint256 totalDelayedReward = sub(totalReward, instantReward);

        if (totalDelayedReward > 0) {
            uint256 campaignFinish = finish(campaignId);

            if (delayedRewards[msg.sender][campaignId].totalAmount == 0) {
              delayedRewards[msg.sender][campaignId].latestExitTime = campaignFinish;
            }
            delayedRewards[msg.sender][campaignId].totalAmount = add(delayedRewards[msg.sender][campaignId].totalAmount, totalDelayedReward);
            emit DelayReward(msg.sender, campaignId, campaignFinish, totalDelayedReward);
            if (campaignFinish < now) {
              getLockedReward(msg.sender, campaignId);
            }
        }
        if (instantReward > 0) {
            globalReward = sub(globalReward, instantReward);
            emit RewardPaid(msg.sender, instantReward);
            safeTransfer(rewardToken, msg.sender, instantReward);
        }
    }

    /// @notice Creates a new campaign
    /// @param reward Reward for campaign (the contract needs enough balance for the campaign to be created)
    /// @param startTime Campaign start time
    /// @param duration Campaign duration
    /// @param rewardDelay Unlock period for locked tokens post campaign end
    /// @param instantExitPercentage Percentage to be paid immediately on getRewards (1000 == 100%)
    /// @return The id of the newly created campaign
    function newCampaign
    (
        uint256 reward,
        uint256 startTime,
        uint256 duration,
        uint256 rewardDelay,
        uint256 instantExitPercentage
    )
        external
        isAuthorized
        returns (uint256)
    {
        require(reward > 0, "RollingDistributionIncentives/invalid-reward");
        require(startTime > now, "RollingDistributionIncentives/startTime-in-the-past");
        require(duration > 0, "RollingDistributionIncentives/invalid-duration");
        require(instantExitPercentage <= THOUSAND, "RollingDistributionIncentives/invalid-instant-exit-percentage");

        campaignCount = add(campaignCount, 1);
        require(
          lastCampaign == 0 || startTime > finish(lastCampaign),
          "RollingDistributionIncentives/startTime-before-last-campaign-finishes"
        );

        campaigns[campaignCount] = Campaign(
            reward,
            startTime,
            duration,
            div(reward, duration),           // rewardRate
            startTime,                       // lastUpdateTime
            0,                               // rewardPerTokenStored
            (instantExitPercentage == THOUSAND) ? 0 : rewardDelay,
            instantExitPercentage
        );
        lastCampaign = campaignCount;
        campaignList.push(campaignCount, false);

        if (campaignList.range() == 1) {
          firstCampaign = campaignCount;
        }
        else if (campaignList.range() > maxCampaigns) {
            uint256 campaignToDelete = firstCampaign;
            (,firstCampaign) = campaignList.next(firstCampaign);
            campaignList.del(campaignToDelete);
        }

        globalReward = add(globalReward,reward);
        emit CampaignAdded(campaignCount);
        return campaignCount;
    }

    /// @notice Cancel a campaign
    /// @param campaignId Id of the campaign
    function cancelCampaign(uint campaignId) external isAuthorized {
        Campaign storage campaign = campaigns[campaignId];
        require(campaign.startTime > now, "RollingDistributionIncentives/campaign-started");
        campaign.startTime = 0;
        campaign.duration  = 0;
        globalReward       = sub(globalReward, campaign.reward);

        // removing from list
        if (lastCampaign == campaignId) {
          (, lastCampaign) = campaignList.prev(lastCampaign);
        }

        // removing from list
        if (firstCampaign == campaignId) {
          (, firstCampaign) = campaignList.next(firstCampaign);
        }

        campaignList.del(campaignId);
    }

    /// @return The campaign list length
    function campaignListLength() public view returns (uint256) {
        return campaignList.range();
    }

    /// @param campaignId The id of a campaign
    /// @return The timestamp at which a campaign ends
    function finish(uint256 campaignId) public view returns (uint256) {
        return add(campaigns[campaignId].startTime, campaigns[campaignId].duration);
    }

    /// @param owner Account that holds rewards
    /// @param campaignId The id of a campaign
    /// @return Rewards from the account
    function rewards(address owner, uint campaignId) public view returns (uint) {
        return campaigns[campaignId].rewards[owner];
    }

    /// @param owner Account that holds rewards
    /// @param campaignId The id of a campaign
    /// @return userRewardPerTokenPaid from the account
    function userRewardPerTokenPaid(address owner, uint campaignId) public view returns (uint) {
        return campaigns[campaignId].userRewardPerTokenPaid[owner];
    }

    /// @notice Disable this contract
    function disableContract() external isAuthorized {
        contractEnabled = 0;
        emit DisableContract();
    }
}
