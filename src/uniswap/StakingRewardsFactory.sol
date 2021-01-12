pragma solidity 0.6.7;

import '../zeppelin/ERC20/IERC20.sol';

import "./Auth.sol";
import './StakingRewards.sol';

contract StakingRewardsFactory is Auth {
    // immutables
    address public rewardsToken;

    // the staking tokens for which the rewards contract has been deployed
    address[] public stakingTokens;

    // info about rewards for a particular staking token
    struct StakingRewardsInfo {
        address stakingRewards;
        uint rewardAmount;
    }

    // rewards info by staking token
    mapping(uint256 => StakingRewardsInfo) public stakingRewardsInfoByStakingToken;

    // --- Events ---
    event Deploy(address indexed stakingToken, uint256 indexed campaignNumber, uint256 rewardAmount, uint256 duration);
    event NotifyRewardAmount(uint256 indexed campaignNumber, uint256 rewardAmount);

    constructor(
        address _rewardsToken
    ) Auth() public {
        rewardsToken = _rewardsToken;
    }

    ///// permissioned functions

    // deploy a staking reward contract for the staking token, and store the reward amount
    // the reward will be distributed to the staking reward contract no sooner than the genesis
    function deploy(address stakingToken, uint rewardAmount, uint duration) public isAuthorized {
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[stakingTokens.length];

        info.stakingRewards = address(new StakingRewards(/*_rewardsDistribution=*/ address(this), rewardsToken, stakingToken, duration));
        info.rewardAmount = rewardAmount;
        stakingTokens.push(stakingToken);

        emit Deploy(stakingToken, stakingTokens.length - 1, rewardAmount, duration);
    }

    // call notifyRewardAmount for all staking tokens.
    function notifyRewardAmounts() external isAuthorized {
        require(stakingTokens.length > 0, 'StakingRewardsFactory::notifyRewardAmounts: called before any deploys');
        for (uint i = 0; i < stakingTokens.length; i++) {
            notifyRewardAmount(i);
        }
    }

    // notify reward amount for an individual staking token.
    // this is a fallback in case the notifyRewardAmounts costs too much gas to call for all contracts
    function notifyRewardAmount(uint256 campaignNumber) public isAuthorized {
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[campaignNumber];
        require(info.stakingRewards != address(0), 'StakingRewardsFactory::notifyRewardAmount: not deployed');

        if (info.rewardAmount > 0) {
            uint rewardAmount = info.rewardAmount;
            info.rewardAmount = 0;

            require(
                IERC20(rewardsToken).transfer(info.stakingRewards, rewardAmount),
                'StakingRewardsFactory::notifyRewardAmount: transfer failed'
            );
            StakingRewards(info.stakingRewards).notifyRewardAmount(rewardAmount);

            emit NotifyRewardAmount(campaignNumber, rewardAmount);
        }
    }
}
