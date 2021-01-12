pragma solidity 0.6.7;

import "ds-token/delegate.sol";
import "ds-token/token.sol";

import "ds-test/test.sol";

import "../uniswap/StakingRewards.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Farmer {
    StakingRewards pool;
    DSToken stakingToken;

    constructor(StakingRewards _pool, DSToken token) public {
        pool = _pool;
        stakingToken = token;
    }

    function doStake(uint amount) public {
        stakingToken.approve(address(pool), amount);
        pool.stake(amount);
    }

    function doWithdraw(uint amount) public {
        pool.withdraw(amount);
    }

    function doGetReward() public {
        pool.getReward();
    }

    function doExit() public {
        pool.exit();
    }
}

contract StakingRewardsTest is DSTest {
    Hevm hevm;

    DSDelegateToken rewardToken;
    DSToken stakingToken;
    StakingRewards pool;
    Farmer[] farmers;

    uint256 initAmountToMint = 1000 ether;
    uint256 defaultDuration  = 12 hours;
    uint256 defaultReward    = 10 ether;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        rewardToken = new DSDelegateToken("GOV", "GOV");
        stakingToken = new DSToken("STAKE", "STAKE");

        pool = new StakingRewards(
            address(this), // rewardsDistribution
            address(rewardToken),
            address(stakingToken),
            defaultDuration
        );

        for (uint i = 0; i < 3; i++) {
            farmers.push(new Farmer(pool, stakingToken));
            stakingToken.mint(address(farmers[i]), initAmountToMint);
        }

        rewardToken.mint(address(pool), initAmountToMint);
    }

    function test_setup() public {
        assertEq(address(pool.rewardsDistribution()), address(this));
        assertEq(address(pool.rewardsToken()), address(rewardToken));
        assertEq(address(pool.stakingToken()), address(stakingToken));
        assertEq(pool.rewardsDuration(), defaultDuration);
    }
    function test_deploy_campaign_check_setup_before_notify() public {
        assertEq(pool.periodFinish(), 0);
        assertEq(pool.rewardRate(), 0);
        assertEq(pool.lastUpdateTime(), 0);
        assertEq(pool.rewardPerTokenStored(), 0);
    }
    function test_deploy_campaign_check_setup_after_one_notify() public {
        pool.notifyRewardAmount(defaultReward);

        assertEq(pool.periodFinish(), now + defaultDuration);
        assertEq(pool.rewardRate(), defaultReward / defaultDuration);
        assertEq(pool.lastUpdateTime(), now);
        assertEq(pool.rewardPerTokenStored(), 0);
    }
    function test_deploy_campaign_check_setup_after_multi_notify() public {
        pool.notifyRewardAmount(defaultReward);
        uint previousRewardRate = pool.rewardRate();
        uint previousPeriodFinish = pool.periodFinish();
        
        hevm.warp(now + (defaultDuration / 2)); // mid distribution
        pool.notifyRewardAmount(defaultReward);

        assertEq(pool.periodFinish(), now + defaultDuration);
        assertEq(pool.lastUpdateTime(), now);
        assertEq(pool.rewardPerTokenStored(), 0);

        uint256 leftover = (previousPeriodFinish - block.timestamp) * previousRewardRate;
        assertEq(pool.rewardRate(), (defaultReward  + leftover) / defaultDuration);
    }
    function test_stake_unstake_before_any_rewards() public {
        Farmer farmer = farmers[0];
        farmer.doStake(1 ether);

        assertEq(pool.totalSupply(), 1 ether);
        assertEq(pool.balanceOf(address(farmer)), 1 ether);

        hevm.warp(now + 5 hours);
        farmer.doWithdraw(1 ether);

        assertEq(pool.totalSupply(), 0);
        assertEq(pool.balanceOf(address(farmer)), 0);
    }
    function test_unstake_after_campaign_expiry() public {
        Farmer farmer = farmers[0];
        farmer.doStake(1 ether);

        pool.notifyRewardAmount(defaultReward);

        hevm.warp(now + defaultDuration + 1); // after expiry
        farmer.doWithdraw(1 ether);

        assertEq(pool.totalSupply(), 0);
        assertEq(pool.balanceOf(address(farmer)), 0);
    }
    function test_stake_claim_once() public {
        Farmer farmer = farmers[0];
        farmer.doStake(1 ether);

        pool.notifyRewardAmount(defaultReward);

        hevm.warp(now + (defaultDuration / 2)); // mid campaign
        farmer.doGetReward();
        assertTrue(rewardToken.balanceOf(address(farmer)) > 4.9999999 ether);    
    }
    function test_stake_claim_multi() public {
        Farmer farmer = farmers[0];
        farmer.doStake(1 ether);

        pool.notifyRewardAmount(defaultReward);

        hevm.warp(now + (defaultDuration / 2)); // mid campaign
        farmer.doGetReward();
        assertTrue(rewardToken.balanceOf(address(farmer)) > 4.9999999 ether);       

        hevm.warp(pool.periodFinish() + 1); // after expiry
        farmer.doGetReward();
        assertTrue(rewardToken.balanceOf(address(farmer)) > 9.9999999 ether);       
    }
    function test_stake_claim_after_campaign_expiry() public {

    }
    function test_multi_user_stake_claim() public {
        //
        // 1x: +----------------+ = 5eth for 5h + 1eth for 5h
        // 4x:         +--------+ = 0eth for 5h + 4eth for 5h
        //

        pool.notifyRewardAmount(defaultReward);
        farmers[0].doStake(1 ether);

        hevm.warp(now + (defaultDuration / 2)); // mid campaign
        farmers[1].doStake(4 ether);

        hevm.warp(pool.periodFinish() + 1); // after expiry
        farmers[0].doGetReward();
        farmers[1].doGetReward();
        assertTrue(rewardToken.balanceOf(address(farmers[0])) > 5.9999999 ether);  
        assertTrue(rewardToken.balanceOf(address(farmers[1])) > 3.9999999 ether);  


    }
    function test_multi_user_stake_claim_unstake() public {
        //
        // 2x: +----------------+--------+ = 4eth for 4h + 2eth for 4h + 2.85eth for 4h
        // 3x: +----------------+          = 6eth for 4h + 3eth for 4h +    0eth for 4h
        // 5x:         +-----------------+ = 0eth for 4h + 5eth for 4h + 7.14eth for 4h
        //

        pool.notifyRewardAmount(30 ether);
        farmers[0].doStake(2 ether);
        farmers[1].doStake(3 ether);

        hevm.warp(now + 4 hours); 
        farmers[2].doStake(5 ether);

        hevm.warp(now + 4 hours); 
        farmers[1].doExit();

        hevm.warp(pool.periodFinish() + 1); 
        farmers[0].doExit();
        farmers[2].doExit();
        assertTrue(rewardToken.balanceOf(address(farmers[0])) > 8.8499999 ether);  
        assertTrue(rewardToken.balanceOf(address(farmers[1])) > 8.9999999 ether);  
        assertTrue(rewardToken.balanceOf(address(farmers[2])) > 12.139999 ether);  
    }
    function test_stake_post_campaign_end_before_any_claim() public {
        Farmer farmer = farmers[0];
        pool.notifyRewardAmount(defaultReward);

        hevm.warp(pool.periodFinish() + 1); 

        farmer.doStake(1 ether);
        hevm.warp(now + 4 weeks);
        farmer.doGetReward();

        assertEq(rewardToken.balanceOf(address(farmer)), 0);        
    }
    function test_stake_notify_twice_unstake_claim() public {
        Farmer farmer = farmers[0];
        farmer.doStake(1 ether);
        pool.notifyRewardAmount(defaultReward);

        hevm.warp(pool.periodFinish() + (defaultDuration / 2)); // mid campaign
        pool.notifyRewardAmount(defaultReward);

        hevm.warp(pool.periodFinish() + 1); 
        farmer.doExit(); // unstake all + claim

        assertTrue(rewardToken.balanceOf(address(farmer)) > 19.999999 ether);
        assertEq(pool.balanceOf(address(farmer)), 0);

    }
}
