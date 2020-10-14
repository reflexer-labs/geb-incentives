pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./GebUniswapSingleDistributionIncentives.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Farmer {
    GebUniswapSingleDistributionIncentives pool;

    constructor(GebUniswapSingleDistributionIncentives pool_) public {
        pool = pool_;
    }

    function doStake(uint amount) public {
        pool.stake(amount);
    }

    function doWithdraw(uint amount) public {
        pool.withdraw(amount);
    }

    function doExit() public {
        pool.exit();
    }

    function doExit(address account, uint timestamp) public {
        pool.exit(account,timestamp);
    }

    function doGetReward() public {
        pool.getReward();
    }

    function doApprove(address token, address who, uint value) public {
        DSToken(token).approve(who, value);
    }
}

contract GebUniswapSingleDistributionIncentivesTest is DSTest {
    DSToken lpToken;
    DSToken rewardToken;
    Hevm    hevm;
    GebUniswapSingleDistributionIncentives pool;

    Farmer user1;
    Farmer user2;
    Farmer user3;
    address self;

    uint duration = 21 days;
    uint exitCooldown = 2 days;
    uint rewardDelay = 12 hours;
    uint instantExitPercentage = 50;
    uint initialBalance = 100 ether;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        lpToken = new DSToken("LPT");
        rewardToken = new DSToken("RWRD");
        pool = new GebUniswapSingleDistributionIncentives(
            address(lpToken),
            address(rewardToken),
            duration,
            now + 1000, // startTime
            exitCooldown,
            rewardDelay,
            instantExitPercentage
        );

        user1 = new Farmer(pool);
        user2 = new Farmer(pool);
        user3 = new Farmer(pool);
        self = address(this);

        lpToken.mint(address(user1), initialBalance);
        lpToken.mint(address(user2), initialBalance);
        lpToken.mint(address(user3), initialBalance);
        rewardToken.mint(address(pool), 100 ether);

        pool.setRewardDistribution(self);

        hevm.warp(now + 1000);
    }

    function testConstructor() public {
        assertEq(address(pool.lpToken()), address(lpToken));
        assertEq(address(pool.rewardToken()), address(rewardToken));
        assertEq(pool.DURATION(), duration);
        assertEq(pool.startTime(), now);
        assertEq(pool.exitCooldown(), exitCooldown);
        assertEq(pool.rewardDelay(), rewardDelay);
        assertEq(pool.instantExitPercentage(), instantExitPercentage);
    }

    function testStake() public {
        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        assertEq(pool.totalSupply(), 1 ether);
        assertEq(pool.balanceOf(address(user1)), 1 ether);
        assertEq(lpToken.balanceOf(address(pool)), 1 ether);
        assertEq(lpToken.balanceOf(address(user1)), initialBalance - 1 ether);
    }

    function testFailStakeBeforeStart() public {
        hevm.warp(now - 1);
        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
    }

    function testFailStakeLowerApproval() public {
        user1.doApprove(address(lpToken), address(pool), 0.9 ether);
        user1.doStake(1 ether);
    }

    function testFailStakeZero() public {
        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(0);
    }

    function testWithdraw() public {
        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        user1.doWithdraw(0.5 ether);

        assertEq(pool.totalSupply(), 0.5 ether);
        assertEq(pool.balanceOf(address(user1)), 0.5 ether);
        assertEq(lpToken.balanceOf(address(pool)), 0.5 ether);
        assertEq(lpToken.balanceOf(address(user1)), initialBalance - 0.5 ether);
    }

    function testFailWithdrawMoreThanBalance() public {
        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        user1.doWithdraw(1 ether + 1);
    }

    function testFailWithdrawZero() public {
        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        user1.doWithdraw(0);
    }


    // testing reward calculation

    function almostEqual(uint origValue, uint origExpected) public returns (bool) { 
        uint precision = 6; // note: check if precision can be improved
        uint value = origValue / (1 * 10 ** precision);
        uint expected = origExpected / (1 * 10 ** precision);
        return (
            value == expected ||
            value + 1 == expected ||
            value == expected - 1
        );
    }

    function testRewardCalculation1() public { // two stakers with same stake

        pool.notifyRewardAmount(10 ether); 
        assertEq(pool.rewardPerToken(), 0);
        assertEq(pool.earned(address(user1)), 0);
        assertEq(pool.earned(address(user2)), 0);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        assertEq(pool.rewardPerToken(), 0);
        assertEq(pool.earned(address(user1)), 0);
        assertEq(pool.earned(address(user2)), 0);

        hevm.warp(now + 21 days);

        assertTrue(almostEqual(pool.rewardPerToken(), 5 ether));
        assertTrue(almostEqual(pool.earned(address(user1)), 5 ether));
        assertTrue(almostEqual(pool.earned(address(user2)), 5 ether));        
    }

    function testRewardCalculation2() public { // two stakers with different stake

        pool.notifyRewardAmount(12 ether);
        assertEq(pool.rewardPerToken(), 0);
        assertEq(pool.earned(address(user1)), 0);
        assertEq(pool.earned(address(user2)), 0);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 3 ether);
        user2.doStake(3 ether);

        assertEq(pool.rewardPerToken(), 0);
        assertEq(pool.earned(address(user1)), 0);
        assertEq(pool.earned(address(user2)), 0);

        hevm.warp(now + 21 days);

        assertTrue(almostEqual(pool.rewardPerToken(), 3 ether));
        assertTrue(almostEqual(pool.earned(address(user1)), 3 ether));
        assertTrue(almostEqual(pool.earned(address(user2)), 9 ether));        
    }

    function testRewardCalculation3() public { 

        //
        // 1x: +----------------+ = 12 for 1w + 3 for 2w
        // 3x:         +--------+ =  0 for 1w + 9 for 2w
        //    

        pool.notifyRewardAmount(36 ether);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 7 days);

        user2.doApprove(address(lpToken), address(pool), 3 ether);
        user2.doStake(3 ether);

        hevm.warp(now + 14 days);

        assertTrue(almostEqual(pool.rewardPerToken(), 18 ether)); // note: check rewardPerToken
        assertTrue(almostEqual(pool.earned(address(user1)), 18 ether));
        assertTrue(almostEqual(pool.earned(address(user2)), 18 ether));        
    }

    function testRewardCalculation4() public { 

        //
        // 1x: +----------------+--------+ = 3 + 1 + 1.33
        // 3x: +----------------+          = 9 + 3 + 0
        // 8x:         +-----------------+ = 0 + 8 + 10.66
        //

        pool.notifyRewardAmount(36 ether);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 3 ether);
        user2.doStake(3 ether);

        hevm.warp(now + 7 days);
        assertTrue(almostEqual(pool.earned(address(user1)), 3 ether));
        assertTrue(almostEqual(pool.earned(address(user2)), 9 ether)); 

        user3.doApprove(address(lpToken), address(pool), 8 ether);
        user3.doStake(8 ether);

        hevm.warp(now + 7 days);
        assertTrue(almostEqual(pool.earned(address(user1)), 4 ether));
        assertTrue(almostEqual(pool.earned(address(user2)), 12 ether)); 
        assertTrue(almostEqual(pool.earned(address(user3)), 8 ether)); 

        user2.doWithdraw(3 ether);
        hevm.warp(now + 7 days);

        emit log_named_uint("rewardPerToken", pool.rewardPerToken()); // note: check rewardPerToken, returns the lowest
        assertTrue(almostEqual(pool.earned(address(user1)), 5333333333333333333));
        assertTrue(almostEqual(pool.earned(address(user2)), 12 ether)); 
        assertTrue(almostEqual(pool.earned(address(user3)), 18666666666666666666));    
    }

    function testGetReward() public { 

        //
        // 1x: +----------------+--------+ = 3 + 1 + 1.33
        // 3x: +----------------+          = 9 + 3 + 0
        // 8x:         +-----------------+ = 0 + 8 + 10.66
        //

        pool.notifyRewardAmount(36 ether);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 3 ether);
        user2.doStake(3 ether);

        hevm.warp(now + 7 days);

        user3.doApprove(address(lpToken), address(pool), 8 ether);
        user3.doStake(8 ether);

        hevm.warp(now + 7 days);

        user2.doWithdraw(3 ether);
        hevm.warp(now + 7 days);

        user1.doGetReward();
        user2.doGetReward();
        user3.doGetReward();

        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), 5333333333333333333));
        assertTrue(almostEqual(rewardToken.balanceOf(address(user2)), 12 ether)); 
        assertTrue(almostEqual(rewardToken.balanceOf(address(user3)), 18666666666666666666));    
    }


}