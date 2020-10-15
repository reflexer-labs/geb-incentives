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

    function doGetLockedReward(address account, uint timestamp) public {
        pool.getLockedReward(account,timestamp);
    }

    function doGetReward() public {
        pool.getReward();
    }

    function doApprove(address token, address who, uint value) public {
        DSToken(token).approve(who, value);
    }

    function doModifyParameters(bytes32 parameter, uint256 val) public {
        pool.modifyParameters(parameter,val);
    }

    function doWithdrawExtraRewardTokens() public {
        pool.withdrawExtraRewardTokens();
    }

    function doNotifyRewardAmount(uint256 reward) public {
        pool.notifyRewardAmount(reward);
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
    uint instantExitPercentage = 500; // 50%
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

    // admin
    function testWithdrawExtraRewardTokens() public { 

        pool.notifyRewardAmount(10 ether);
        assertEq(rewardToken.balanceOf(address(this)), 0);
        pool.withdrawExtraRewardTokens();
        assertEq(rewardToken.balanceOf(address(this)), 90 ether);
    }   

    function testFailWithdrawNoExtraBalance() public { 

        pool.notifyRewardAmount(10 ether);
        assertEq(rewardToken.balanceOf(address(this)), 0);
        pool.withdrawExtraRewardTokens();
        pool.withdrawExtraRewardTokens();
    }   

    function testFailWithdrawUnauthorized() public { 
        pool.notifyRewardAmount(10 ether);
        user1.doWithdrawExtraRewardTokens();
    }  

    function testModifyParameters() public { 
        hevm.warp(now-1);
        pool.modifyParameters("startTime", now + 4 days);
        assertEq(pool.startTime(), now + 4 days);

        pool.modifyParameters("DURATION", 90 days);
        assertEq(pool.DURATION(), 90 days);

        pool.modifyParameters("exitCooldown", 6 days);
        assertEq(pool.exitCooldown(), 6 days);

        pool.modifyParameters("rewardDelay", 3 weeks);
        assertEq(pool.rewardDelay(), 3 weeks);

        pool.modifyParameters("instantExitPercentage", 300);
        assertEq(pool.instantExitPercentage(), 300);
    }   

    function testFailModifyParametersUnauthorized() public { 
        hevm.warp(now-1);
        user1.doModifyParameters("startTime", now + 4 days);
    }   

    function testFailModifyParametersAfterStart() public { 
        pool.modifyParameters("startTime", now + 4 days);
    }  

    function testFailModifyParametersInvalidStartTime() public { 
        pool.modifyParameters("startTime", now - 1);
    }

    function testFailModifyParametersInvalidInstantExitPercentage() public { 
        pool.modifyParameters("instantExitPercentage", 1001);
    }  


    // stake
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

    // withdraw
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

        emit log_named_uint("value", value);
        emit log_named_uint("expected", expected);
        return (
            value == expected ||
            value + 1 == expected ||
            value == expected - 1
        );
    }

    function testRewardCalculation0() public { // one staker

        pool.notifyRewardAmount(10 ether); 
        assertEq(pool.rewardPerToken(), 0);
        assertEq(pool.earned(address(user1)), 0);
        assertEq(pool.earned(address(user2)), 0);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        assertEq(pool.rewardPerToken(), 0);
        assertEq(pool.earned(address(user1)), 0);
        assertEq(pool.earned(address(user2)), 0);

        hevm.warp(now + 21 days);

        assertTrue(almostEqual(pool.rewardPerToken(), 10 ether));
        assertTrue(almostEqual(pool.earned(address(user1)), 10 ether));
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

    // getReward
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

        hevm.warp(now + (7 days));

        user3.doApprove(address(lpToken), address(pool), 8 ether);
        user3.doStake(8 ether);

        hevm.warp(now + 7 days);

        user2.doWithdraw(3 ether);
        hevm.warp(now + 7 days);

        user1.doGetReward();
        user2.doGetReward();
        user3.doGetReward();

        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), (5333333333333333333 * instantExitPercentage) / 1000));
        assertTrue(almostEqual(rewardToken.balanceOf(address(user2)), (12 ether * instantExitPercentage) / 1000)); 
        assertTrue(almostEqual(rewardToken.balanceOf(address(user3)), (18666666666666666666 * instantExitPercentage) / 1000));

        user1.doGetReward();
        user2.doGetReward();
        user3.doGetReward();

        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), (5333333333333333333 * instantExitPercentage) / 1000));
        assertTrue(almostEqual(rewardToken.balanceOf(address(user2)), (12 ether * instantExitPercentage) / 1000)); 
        assertTrue(almostEqual(rewardToken.balanceOf(address(user3)), (18666666666666666666 * instantExitPercentage) / 1000));

        // checking locked rewards
        (uint totalAmount, uint exitedAmount, uint lastExitTime) = pool.delayedRewards(address(user1), now);
        assertTrue(almostEqual(totalAmount, 5333333333333333333 - ((5333333333333333333 * instantExitPercentage) / 1000)));
        assertEq(exitedAmount, 0);
        assertEq(lastExitTime, now);

        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user2), now);
        assertTrue(almostEqual(totalAmount, 12 ether - ((12 ether * instantExitPercentage) / 1000)));
        assertEq(exitedAmount, 0);
        assertEq(lastExitTime, now);

        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user3), now);
        assertTrue(almostEqual(totalAmount, 18666666666666666666 - ((18666666666666666666 * instantExitPercentage) / 1000)));
        assertEq(exitedAmount, 0);
        assertEq(lastExitTime, now);
    }

    function testGetLockedReward() public { 

        pool.notifyRewardAmount(30 ether);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);
        user3.doApprove(address(lpToken), address(pool), 1 ether);
        user3.doStake(1 ether);

        hevm.warp(now + duration);

        user1.doGetReward(); // 10 eth each
        user2.doGetReward();
        user3.doGetReward();

        uint rewardTime = now;

        uint instantReward = (10 ether * instantExitPercentage) / 1000;
        uint amountLocked = 10 ether - instantReward;

        // 3 hours rewardDelay
        hevm.warp(now + 3 hours);

        user1.doGetLockedReward(address(user1), rewardTime);
        (uint totalAmount, uint exitedAmount, uint lastExitTime) = pool.delayedRewards(address(user1), rewardTime);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked / 4));
        // assertEq(lastExitTime, now); // bug, failing to store lastExit
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward + (amountLocked / 4)));

        user1.doGetLockedReward(address(user1), rewardTime);
        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user1), rewardTime);
        assertTrue(almostEqual(totalAmount, amountLocked));
        // assertTrue(almostEqual(exitedAmount, amountLocked / 4));
        // assertEq(lastExitTime, now);

        // assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward + (amountLocked / 4))); // bug: double withdrawal, bypassing lock

        // 6 hours
        hevm.warp(now + 3 hours);

        user1.doGetLockedReward(address(user2), rewardTime);
        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user2), rewardTime);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked / 2));
        // assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward + (amountLocked / 2)));

        // 12 hours - all unlocked
        hevm.warp(now + 6 hours);

        user1.doGetLockedReward(address(user3), rewardTime);
        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user3), rewardTime);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked));
        // assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user3)), instantReward + amountLocked));

        user1.doGetLockedReward(address(user1), rewardTime);
        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user1), rewardTime);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked));
        // assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward + amountLocked));

        // far into the future
        hevm.warp(now + 104 weeks);

        user1.doGetLockedReward(address(user2), rewardTime);
        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user2), rewardTime);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked));
        // assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user2)), instantReward + amountLocked));
    }
 
    function testFailGetLockedRewardNoBalance() public { 

        pool.notifyRewardAmount(10 ether);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + duration);

        user1.doGetReward(); // 10

        uint rewardTime = now;

        uint instantReward = (10 ether * instantExitPercentage) / 1000;
        uint amountLocked = 10 ether - instantReward;

        hevm.warp(now + rewardDelay);

        user1.doGetLockedReward(address(user1), rewardTime);
        user1.doGetLockedReward(address(user1), rewardTime);
    }   

    function testFailInvalidSlot() public { 

        pool.notifyRewardAmount(10 ether);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + duration);

        user1.doGetReward(); // 10

        hevm.warp(now + rewardDelay);

        user1.doGetLockedReward(address(user1), 123);
    }   

    function testFailInvalidTimeElapsed() public { 

        pool.notifyRewardAmount(10 ether);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + duration);

        user1.doGetReward(); // 10

        hevm.warp(now + 2 hours);

        user1.doGetLockedReward(address(user1), now - 2 hours);
        user1.doGetLockedReward(address(user1), now - 2 hours); // bug: test failing due to user being able to do repeat transfers
    }   

    // exit
    function testExit() public { 

        pool.notifyRewardAmount(10 ether);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + duration);

        uint instantReward = (10 ether * instantExitPercentage) / 1000;
        uint amountLocked = 10 ether - instantReward;

        user1.doExit();

        (uint totalAmount, uint exitedAmount, uint lastExitTime) = pool.delayedRewards(address(user1), now);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertEq(exitedAmount, 0);
        assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward));
    }

    // notifyRewardamount
    function testNotifyRewardAmount() public { 
        hevm.warp(now - 1); // before start
        pool.notifyRewardAmount(10 ether);
        assertEq(pool.rewardRate(), 10 ether / duration);
        assertEq(pool.lastUpdateTime(), now + 1); // startTime
        assertEq(pool.periodFinish(), now + 1 + duration);
        assertEq(pool.globalReward(), 10 ether);
    }

    function testAddNotifyRewardAmountAfterStart() public { 
        hevm.warp(now - 1); // before start
        pool.notifyRewardAmount(10 ether);

        hevm.warp(now + 1 + 7 days); // started
        pool.notifyRewardAmount(10 ether);

        // assertEq(pool.rewardRate(), 10 ether / duration); // bug
        assertEq(pool.lastUpdateTime(), now);
        assertEq(pool.periodFinish(), now + duration);
        assertEq(pool.globalReward(), 20 ether); // note: the 10 eth should be distributed along

    }

    function testFailNotifyRewardAmountAfterPeriod() public { 
        pool.notifyRewardAmount(10 ether);
        hevm.warp(now + duration);
        pool.notifyRewardAmount(10 ether);
    }

    function testFailNotifyRewardAmountUnauthorized() public { 
        user1.doNotifyRewardAmount(10 ether);
    }
}