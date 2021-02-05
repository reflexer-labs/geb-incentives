pragma solidity 0.6.7;

import '../zeppelin/ERC20/IERC20.sol';
import '../zeppelin/math/SafeMath.sol';

import "./Auth.sol";
import './StakingRewards.sol';

contract StakingRewardsFactory is Auth, SafeMath {
    // immutables
    address public rewardsToken;

    // the staking tokens for which the rewards contract has been deployed
    address[] public stakingTokens;

    // info about rewards for a particular staking token
    struct StakingRewardsInfo {
        address stakingRewards;
        uint rewardAmount;
    }

    // rewards info by campaign number
    mapping(uint256 => StakingRewardsInfo) public stakingRewardsInfo;
    // timestamp when the last campaign ends for a specific staking token
    mapping(address => uint256) public lastCampaignEndTime;

    // --- Events ---
    event ModifyParameters(uint256 indexed campaign, bytes32 parameter, uint256 val);
    event Deploy(address indexed stakingToken, uint256 indexed campaignNumber, uint256 rewardAmount, uint256 duration);
    event NotifyRewardAmount(uint256 indexed campaignNumber, uint256 rewardAmount);

    constructor(
        address _rewardsToken
    ) Auth() public {
        rewardsToken = _rewardsToken;
    }

    // --- Administration ---
    function modifyParameters(uint256 campaign, bytes32 parameter, uint256 val) external isAuthorized {
        require(campaign < stakingTokens.length, "StakingRewardsFactory/inexistent-campaign");

        StakingRewardsInfo storage info = stakingRewardsInfo[campaign];
        require(info.stakingRewards != address(0), 'StakingRewardsFactory/not-deployed');

        if (parameter == "rewardAmount") {
            require(StakingRewards(info.stakingRewards).rewardRate() == 0, "StakingRewardsFactory/campaign-already-started");
            require(val >= StakingRewards(info.stakingRewards).rewardsDuration(), "StakingRewardsFactory/reward-lower-than-duration");
            info.rewardAmount = val;
        }
        else revert("StakingRewardsFactory/modify-unrecognized-params");
        emit ModifyParameters(campaign, parameter, val);
    }

    // --- Utils ---
    function totalCampaignCount() public view returns (uint256) {
        return stakingTokens.length;
    }
    function transferTokenOut(address token, address receiver, uint256 amount) external isAuthorized {
        require(address(receiver) != address(0), "StakingRewardsFactory/cannot-transfer-to-null");
        require(IERC20(token).transfer(receiver, amount), "StakingRewardsFactory/could-not-transfer-token");
    }

    // --- Core Logic ---
    // @notify Deploy a staking reward contract for the staking token, and store the reward amount
    // @dev The reward will be distributed to the staking reward contract no sooner than the genesis
    function deploy(address stakingToken, uint rewardAmount, uint duration) public isAuthorized {
        require(rewardAmount > 0, "StakingRewardsFactory/null-reward");
        require(rewardAmount >= duration, "StakingRewardsFactory/reward-lower-than-duration");

        StakingRewardsInfo storage info = stakingRewardsInfo[stakingTokens.length];

        info.stakingRewards = address(new StakingRewards(/*_rewardsDistribution=*/ address(this), rewardsToken, stakingToken, duration));
        info.rewardAmount = rewardAmount;
        stakingTokens.push(stakingToken);

        emit Deploy(stakingToken, stakingTokens.length - 1, rewardAmount, duration);
    }

    // @notify Reward amount for an individual staking token
    function notifyRewardAmount(uint256 campaignNumber) public isAuthorized {
        StakingRewardsInfo storage info = stakingRewardsInfo[campaignNumber];
        require(info.stakingRewards != address(0), 'StakingRewardsFactory/not-deployed');

        if (info.rewardAmount > 0) {
            uint rewardAmount = info.rewardAmount;
            uint remainder    = rewardAmount % StakingRewards(info.stakingRewards).rewardsDuration();
            info.rewardAmount = 0;
            rewardAmount      = sub(rewardAmount, remainder);

            uint256 campaignEndTime = add(block.timestamp, StakingRewards(info.stakingRewards).rewardsDuration());
            if (lastCampaignEndTime[stakingTokens[campaignNumber]] < campaignEndTime) {
              lastCampaignEndTime[stakingTokens[campaignNumber]] = campaignEndTime;
            }

            require(
                IERC20(rewardsToken).transfer(info.stakingRewards, rewardAmount),
                'StakingRewardsFactory/transfer-failed'
            );
            StakingRewards(info.stakingRewards).notifyRewardAmount(rewardAmount);

            emit NotifyRewardAmount(campaignNumber, rewardAmount);
        }
    }
}
