pragma solidity 0.6.7;

import "ds-token/delegate.sol";
import "ds-token/token.sol";

import "ds-test/test.sol";

import "../uniswap/StakingRewardsFactory.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract StakingRewardsFactoryTest is DSTest {
    Hevm hevm;

    DSDelegateToken rewardToken;
    DSToken stakingToken;

    StakingRewardsFactory factory;

    uint256 initAmountToMint = 1000E18;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        rewardToken = new DSDelegateToken("GOV", "GOV");
        stakingToken = new DSToken("STAKE", "STAKE");

        factory = new StakingRewardsFactory(address(rewardToken));

        rewardToken.mint(address(this), initAmountToMint);
        stakingToken.mint(address(this), initAmountToMint);
    }

    function test_setup() public {
        assertEq(factory.rewardsToken(), address(rewardToken));
    }
    function test_deploy_campaign() public {
        factory.deploy(address(stakingToken), 100E18, 1 hours);

        (address stakingContract, uint256 rewardAmount) = factory.stakingRewardsInfo(0);
        assertEq(factory.lastCampaignEndTime(address(stakingToken)), 0);
        assertTrue(stakingContract != address(0));
        assertEq(rewardAmount, 100E18);
        assertEq(factory.stakingTokens(0), address(stakingToken));

        assertEq(address(StakingRewards(stakingContract).rewardsToken()), address(rewardToken));
        assertEq(address(StakingRewards(stakingContract).stakingToken()), address(stakingToken));
        assertEq(StakingRewards(stakingContract).periodFinish(), 0);
        assertEq(StakingRewards(stakingContract).rewardRate(), 0);
        assertEq(StakingRewards(stakingContract).rewardsDuration(), 1 hours);
        assertEq(StakingRewards(stakingContract).lastUpdateTime(), 0);
        assertEq(StakingRewards(stakingContract).rewardPerTokenStored(), 0);
        assertEq(StakingRewards(stakingContract).totalSupply(), 0);
    }
    function test_deploy_multi_campaign_same_token() public {
        factory.deploy(address(stakingToken), 100E18, 1 hours);
        factory.deploy(address(stakingToken), 200E18, 6 hours);
        factory.deploy(address(stakingToken), 300E18, 4 hours);

        address stakingContract;
        uint256 rewardAmount;

        for (uint i = 0; i < 3; i++) {
          (stakingContract, rewardAmount) = factory.stakingRewardsInfo(i);

          assertTrue(stakingContract != address(0));
          assertEq(rewardAmount, 100E18 * (i + 1));
          assertEq(factory.stakingTokens(i), address(stakingToken));

          assertEq(address(StakingRewards(stakingContract).rewardsToken()), address(rewardToken));
          assertEq(address(StakingRewards(stakingContract).stakingToken()), address(stakingToken));
          assertEq(StakingRewards(stakingContract).periodFinish(), 0);
          assertEq(StakingRewards(stakingContract).rewardRate(), 0);
          assertEq(StakingRewards(stakingContract).lastUpdateTime(), 0);
          assertEq(StakingRewards(stakingContract).rewardPerTokenStored(), 0);
          assertEq(StakingRewards(stakingContract).totalSupply(), 0);
        }
        assertEq(factory.lastCampaignEndTime(address(stakingToken)), 0);
    }
    function test_deploy_multi_campaign_multi_token() public {
        DSToken stakingToken2;
        stakingToken2 = new DSToken("STAKE", "STAKE");
        stakingToken2.mint(address(this), initAmountToMint);

        // Token 1
        factory.deploy(address(stakingToken), 100E18, 1 hours);
        factory.deploy(address(stakingToken), 200E18, 6 hours);
        factory.deploy(address(stakingToken), 300E18, 4 hours);

        // Token 2
        factory.deploy(address(stakingToken2), 100E18, 100 days);
        factory.deploy(address(stakingToken2), 200E18, 600 days);
        factory.deploy(address(stakingToken2), 300E18, 400 days);

        // Checks
        address stakingContract;
        uint256 rewardAmount;
        uint i;

        for (i = 0; i < 3; i++) {
          (stakingContract, rewardAmount) = factory.stakingRewardsInfo(i);

          assertTrue(stakingContract != address(0));
          assertEq(rewardAmount, 100E18 * (i + 1));
          assertEq(factory.stakingTokens(i), address(stakingToken));

          assertEq(address(StakingRewards(stakingContract).rewardsToken()), address(rewardToken));
          assertEq(address(StakingRewards(stakingContract).stakingToken()), address(stakingToken));
          assertEq(StakingRewards(stakingContract).periodFinish(), 0);
          assertEq(StakingRewards(stakingContract).rewardRate(), 0);
          assertEq(StakingRewards(stakingContract).lastUpdateTime(), 0);
          assertEq(StakingRewards(stakingContract).rewardPerTokenStored(), 0);
          assertEq(StakingRewards(stakingContract).totalSupply(), 0);
        }
        assertEq(factory.lastCampaignEndTime(address(stakingToken)), 0);

        for (uint i = 3; i < 6; i++) {
          (stakingContract, rewardAmount) = factory.stakingRewardsInfo(i);

          assertTrue(stakingContract != address(0));
          assertEq(rewardAmount, 100E18 * (i - 2));
          assertEq(factory.stakingTokens(i), address(stakingToken2));

          assertEq(address(StakingRewards(stakingContract).rewardsToken()), address(rewardToken));
          assertEq(address(StakingRewards(stakingContract).stakingToken()), address(stakingToken2));
          assertEq(StakingRewards(stakingContract).periodFinish(), 0);
          assertEq(StakingRewards(stakingContract).rewardRate(), 0);
          assertEq(StakingRewards(stakingContract).lastUpdateTime(), 0);
          assertEq(StakingRewards(stakingContract).rewardPerTokenStored(), 0);
          assertEq(StakingRewards(stakingContract).totalSupply(), 0);
        }
        assertEq(factory.lastCampaignEndTime(address(stakingToken2)), 0);
    }
    function test_transfer_token_out() public {
        rewardToken.transfer(address(factory), 500E18);
        assertEq(rewardToken.balanceOf(address(factory)), 500E18);

        factory.transferTokenOut(address(rewardToken), address(0x1), 500E18);
        assertEq(rewardToken.balanceOf(address(0x1)), 500E18);
    }
    function testFail_transfer_token_out_to_null() public {
        rewardToken.transfer(address(factory), 500E18);
        factory.transferTokenOut(address(rewardToken), address(0), 500E18);
    }
    function test_modify_reward_amount() public {
        factory.deploy(address(stakingToken), 100E18, 1 hours);
        factory.modifyParameters(0, "rewardAmount", 50E18);

        (address stakingContract, uint256 rewardAmount) = factory.stakingRewardsInfo(0);
        assertEq(factory.lastCampaignEndTime(address(stakingToken)), 0);
        assertTrue(stakingContract != address(0));
        assertEq(rewardAmount, 50E18);
    }
    function testFail_modify_reward_amount_inexistent() public {
        factory.deploy(address(stakingToken), 100E18, 1 hours);
        factory.modifyParameters(1, "rewardAmount", 50E18);
    }
    function testFail_modify_reward_amount_already_notified() public {
        factory.deploy(address(stakingToken), 100E18, 1 hours);
        rewardToken.transfer(address(factory), 100E18);
        factory.notifyRewardAmount(0);
        factory.modifyParameters(0, "rewardAmount", 50E18);
    }
    function testFail_deploy_null_amount() public {
        factory.deploy(address(stakingToken), 0, 1 hours);
    }
    function testFail_notify_not_enough_balance() public {
        factory.deploy(address(stakingToken), 100E18, 1 hours);
        factory.notifyRewardAmount(0);
    }
    function test_notify_multi() public {
        factory.deploy(address(stakingToken), 108E18, 1 hours);
        factory.deploy(address(stakingToken), 216E18, 6 hours);
        factory.deploy(address(stakingToken), 324E18, 4 hours);

        rewardToken.transfer(address(factory), 648E18);

        factory.notifyRewardAmount(0);
        factory.notifyRewardAmount(1);
        factory.notifyRewardAmount(2);

        assertEq(rewardToken.balanceOf(address(factory)), 0);

        (address stakingContract, uint256 rewardAmount) = factory.stakingRewardsInfo(0);
        assertEq(rewardToken.balanceOf(address(stakingContract)), 108E18);

        (stakingContract, rewardAmount) = factory.stakingRewardsInfo(1);
        assertEq(rewardToken.balanceOf(address(stakingContract)), 216E18);

        (stakingContract, rewardAmount) = factory.stakingRewardsInfo(2);
        assertEq(rewardToken.balanceOf(address(stakingContract)), 324E18);
    }
    function test_notify_after_campaign_ends() public {
        factory.deploy(address(stakingToken), 108E18, 1 hours);
        rewardToken.transfer(address(factory), 200E18);
        factory.notifyRewardAmount(0);

        hevm.warp(now + 1 hours + 1);
        factory.notifyRewardAmount(0);

        (address stakingContract, uint256 rewardAmount) = factory.stakingRewardsInfo(0);
        assertEq(rewardToken.balanceOf(address(stakingContract)), 108E18);
    }
}
