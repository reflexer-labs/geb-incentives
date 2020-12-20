pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "../uniswap/RollingDistributionIncentives.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Farmer {
    RollingDistributionIncentives pool;

    constructor(RollingDistributionIncentives pool_) public {
        pool = pool_;
    }

    function doStake(uint amount) public {
        pool.stake(amount);
    }

    function doStakeFor(uint amount, address owner) public {
        pool.stake(amount, owner);
    }

    function doWithdraw(uint amount) public {
        pool.withdraw(amount);
    }

    function doExit() public {
        pool.exit();
    }

    function doGetLockedReward(address account, uint campaignId) public {
        pool.getLockedReward(account, campaignId);
    }

    function doGetReward(uint campaign) public {
        pool.getReward(campaign);
    }

    function doApprove(address token, address who, uint value) public {
        DSToken(token).approve(who, value);
    }

    function doModifyParameters(bytes32 parameter, uint256 campaignId, uint256 val) public {
        pool.modifyParameters(parameter, campaignId, val);
    }

    function doModifyParameters(bytes32 parameter, uint256 val) public {
        pool.modifyParameters(parameter, val);
    }

    function doWithdrawExtraRewardTokens() public {
        pool.withdrawExtraRewardTokens();
    }

    function doNewCampaign(uint256 reward, uint256 startTime, uint256 duration) public {
        pool.newCampaign(reward, startTime, reward, 0, 1000);
    }

    function doTransfer(address token, address receiver, uint256 amount) public {
        DSToken(token).transfer(receiver, amount);
    }
}

contract RollingDistributionIncentivesTest is DSTest {
    DSToken lpToken;
    DSToken rewardToken;
    Hevm    hevm;
    RollingDistributionIncentives pool;

    Farmer user1;
    Farmer user2;
    Farmer user3;
    address self;

    uint rewardDelay           = 12 days;
    uint instantExitPercentage = 500; // 50%
    uint initialBalance        = 1000000000000 ether;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        lpToken = new DSToken("LPT", "LPT");
        rewardToken = new DSToken("RWRD", "RWRD");
        pool = new RollingDistributionIncentives(
            address(lpToken),
            address(rewardToken)
        );
        pool.modifyParameters("canStake", 1);

        user1 = new Farmer(pool);
        user2 = new Farmer(pool);
        user3 = new Farmer(pool);
        self = address(this);

        lpToken.mint(address(user1), initialBalance);
        lpToken.mint(address(user2), initialBalance);
        lpToken.mint(address(user3), initialBalance);
        rewardToken.mint(address(pool), initialBalance);

        hevm.warp(now + 1000);
    }

    function testConstructor() public {
        assertEq(pool.authorizedAccounts(address(this)), 1);
        assertEq(address(pool.lpToken()), address(lpToken));
        assertEq(address(pool.rewardToken()), address(rewardToken));
    }

    // admin
    function testModifyCampaignParameters() public {
        uint256 campaignId = pool.newCampaign(10 ether, now + 1 days, 5 days, 90 days, 500);
        assertEq(campaignId, 1);

        pool.modifyParameters("reward", 1, 20 ether);
        pool.modifyParameters("startTime", 1, now + 3 days);
        pool.modifyParameters("duration", 1, 10 days);
        pool.modifyParameters("rewardDelay", 1, 3 weeks);
        pool.modifyParameters("instantExitPercentage", 1, 300);

        (
            uint reward,
            uint startTime,
            uint duration,,
            uint lastUpdateTime,,
            uint rewardDelay,
            uint instantExitPercentage
        ) = pool.campaigns(1);
        assertEq(reward, 20 ether);
        assertEq(startTime, now + 3 days);
        assertEq(duration, 10 days);
        assertEq(lastUpdateTime, startTime);
        assertEq(rewardDelay, 3 weeks);
        assertEq(instantExitPercentage, 300);
    }

    function testModifyParameters() public {
        pool.modifyParameters("maxCampaigns", 100);
        assertEq(pool.maxCampaigns(), 100);
    }

    function testModifyReduceMaxCampaigns() public {
        for (uint i = 1; i <= pool.DEFAULT_MAX_CAMPAIGNS(); i++) {
            pool.newCampaign(1 ether, i * 1 weeks + block.timestamp, 5 days, rewardDelay, instantExitPercentage);
        }
        assertEq(pool.firstCampaign(), 1);
        assertEq(pool.lastCampaign(), pool.DEFAULT_MAX_CAMPAIGNS());
        assertEq(pool.campaignListLength(), pool.DEFAULT_MAX_CAMPAIGNS());
        pool.modifyParameters("maxCampaigns", 10);
        assertEq(pool.firstCampaign(), pool.DEFAULT_MAX_CAMPAIGNS() - 9);
        assertEq(pool.lastCampaign(), pool.DEFAULT_MAX_CAMPAIGNS());
        assertEq(pool.campaignListLength(), 10);
    }

    function testFailModifyCampaignParametersUnauthorized() public {
        uint256 campaignId = pool.newCampaign(10 ether, now + 1 days, 5 days, 90 days, 500);
        assertEq(campaignId, 1);
        user1.doModifyParameters("startTime", 1, now + 1);
    }

    function testFailModifyParametersUnauthorized() public {
        user1.doModifyParameters("maxCampaigns", 100);
    }

    function testFailModifyParametersCampaignStarted() public {
        pool.newCampaign(10 ether, now + 1 days, 5 days, 90 days, 500);
        hevm.warp(now + 1 days);
        pool.modifyParameters("reward", 1, 1 ether);
    }

    function testFailModifyParametersLongerRewardDelayAfterCampaignStarted() public {
        pool.newCampaign(10 ether, now + 1 days, 5 days, 90 days, 500);
        hevm.warp(now + 1 days);
        pool.modifyParameters("rewardDelay", 1, 90 days + 1);
    }

    function testFailModifyParametersInexistentCampaign() public {
        pool.newCampaign(10 ether, now + 1 days, 5 days, 90 days, 500);
        pool.modifyParameters("reward", 2, 1 ether);
    }

    function testFailModifyParametersZeroReward() public {
        pool.newCampaign(10 ether, now + 1 days, 5 days, 90 days, 500);
        pool.modifyParameters("reward", 1, 0);
    }

    function testFailModifyParametersStartPast() public {
        pool.newCampaign(10 ether, now + 1 days, 5 days, 90 days, 500);
        pool.modifyParameters("startTime", 1, now);
    }

    function testFailModifyParametersDurationZero() public {
        pool.newCampaign(10 ether, now + 1 days, 5 days, 90 days, 500);
        pool.modifyParameters("duration", 1, 0);
    }

    function testFailModifyParametersInvalidExitPercentage() public {
        pool.newCampaign(10 ether, now + 1 days, 5 days, 90 days, 500);
        pool.modifyParameters("instantExitPercentage", 1, 1001);
    }

    function testFailModifyParametersUnexistent() public {
        user1.doModifyParameters("abc", 100);
    }

    function testWithdrawExtraRewardTokens() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        assertEq(rewardToken.balanceOf(address(this)), 0);
        pool.withdrawExtraRewardTokens();
        assertEq(rewardToken.balanceOf(address(this)),initialBalance - 10 ether);
    }

    function testFailWithdrawNoExtraBalance() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        assertEq(rewardToken.balanceOf(address(this)), 0);
        pool.withdrawExtraRewardTokens();
        pool.withdrawExtraRewardTokens();
    }

    function testFailWithdrawUnauthorized() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        user1.doWithdrawExtraRewardTokens();
    }

    // stake
    function testStake() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        assertEq(pool.totalSupply(), 1 ether);
        assertEq(pool.balanceOf(address(user1)), 1 ether);
        assertEq(lpToken.balanceOf(address(pool)), 1 ether);
        assertEq(lpToken.balanceOf(address(user1)), initialBalance - 1 ether);
    }

    function testStakeFor() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStakeFor(1 ether, address(0xabc));

        assertEq(pool.totalSupply(), 1 ether);
        assertEq(pool.balanceOf(address(0xabc)), 1 ether);
        assertEq(lpToken.balanceOf(address(pool)), 1 ether);
        assertEq(lpToken.balanceOf(address(user1)), initialBalance - 1 ether);
    }

    function testFailStakeLowerApproval() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 0.9 ether);
        user1.doStake(1 ether);
    }

    function testFailStakeZero() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(0);
    }

    function testFailStakeBeforeCampaign() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(0);
    }

    function testTransferLPTokensBeforeCampaignThenStake() public {
        user1.doTransfer(address(lpToken), address(pool), 1);
        assertEq(lpToken.balanceOf(address(pool)), 1);

        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 0.5 ether);
        user1.doStake(0.5 ether);

        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        assertEq(pool.totalSupply(), 1.5 ether);
        assertEq(pool.balanceOf(address(user1)), 0.5 ether);
        assertEq(pool.balanceOf(address(user2)), 1 ether);
        assertEq(lpToken.balanceOf(address(pool)), 1.5 ether + 1);
    }

    function testTransferLPTokensAfterCampaignThenStake() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 0.5 ether);
        user1.doStake(0.5 ether);

        user1.doTransfer(address(lpToken), address(pool), 1);
        assertEq(lpToken.balanceOf(address(pool)), 0.5 ether + 1);

        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        assertEq(pool.totalSupply(), 1.5 ether);
        assertEq(pool.balanceOf(address(user1)), 0.5 ether);
        assertEq(pool.balanceOf(address(user2)), 1 ether);
        assertEq(lpToken.balanceOf(address(pool)), 1.5 ether + 1);
    }

    function testFailStakeInSecondCampaignWhenStakingPaused() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);

        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 0.5 ether);
        user1.doStake(0.5 ether);

        hevm.warp(now + 5 days + 1);
        emit log_named_uint("currentCampaign 1 finished", pool.currentCampaign());
        user1.doWithdraw(0.5 ether);

        pool.modifyParameters("canStake", 0);
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        assertEq(pool.lastCampaign(), 2);

        user1.doApprove(address(lpToken), address(pool), 0.5 ether);
        user1.doStake(0.5 ether);
    }

    function testStakeInSecondCampaignAfterStart() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 0.5 ether);
        user1.doStake(0.5 ether);

        hevm.warp(now + 5 days);
        user1.doWithdraw(0.5 ether);

        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);

        user1.doApprove(address(lpToken), address(pool), 0.5 ether);
        user1.doStake(0.5 ether);
    }

    function testStakeAfterMaxCampaignsModified() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 5 days + 1);

        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        pool.modifyParameters("maxCampaigns", pool.maxCampaigns() - 1);

        assertEq(pool.currentCampaign(), 1);
        user1.doApprove(address(lpToken), address(pool), 0.5 ether);
        user1.doStake(0.5 ether);

        hevm.warp(now + 5 days + 1);

        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        pool.modifyParameters("maxCampaigns", 1);

        assertEq(pool.currentCampaign(), 0);
        hevm.warp(now + 1);
        assertEq(pool.currentCampaign(), 3);

        user1.doApprove(address(lpToken), address(pool), 0.5 ether);
        user1.doStake(0.5 ether);
    }

    // withdraw
    function testWithdraw() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        user1.doWithdraw(0.5 ether);

        assertEq(pool.totalSupply(), 0.5 ether);
        assertEq(pool.balanceOf(address(user1)), 0.5 ether);
        assertEq(lpToken.balanceOf(address(pool)), 0.5 ether);
        assertEq(lpToken.balanceOf(address(user1)), initialBalance - 0.5 ether);
    }

    function testWithdrawStakedMidCampaign() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1 + 2.5 days);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 2.5 days);
        assertEq(pool.totalSupply(), 1 ether);
        assertEq(pool.balanceOf(address(user1)), 1 ether);
        assertEq(lpToken.balanceOf(address(pool)), 1 ether);
        assertEq(lpToken.balanceOf(address(user1)), initialBalance - 1 ether);
    }

    function testMultiWithdraw() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);

        hevm.warp(now + 1);
        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 2.5 days);
        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        hevm.warp(now + 1 days);
        user1.doWithdraw(0.5 ether);
        user2.doWithdraw(0.5 ether);

        hevm.warp(now + 1.5 days);
        assertEq(pool.totalSupply(), 1 ether);
        assertEq(pool.balanceOf(address(user2)), 0.5 ether);
        assertEq(pool.balanceOf(address(user1)), 0.5 ether);
        assertEq(lpToken.balanceOf(address(pool)), 1 ether);
        assertEq(lpToken.balanceOf(address(user2)), initialBalance - 0.5 ether);
        assertEq(lpToken.balanceOf(address(user1)), initialBalance - 0.5 ether);
    }

    function testMultiWithdrawAfterMultiCampaigns() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 2.5 days + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        hevm.warp(now + 2.5 days);

        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1 days);

        user3.doApprove(address(lpToken), address(pool), 1 ether);
        user3.doStake(1 ether);

        hevm.warp(now + 4 days);
        user1.doWithdraw(1 ether);
        user2.doWithdraw(1 ether);
        user3.doWithdraw(1 ether);

        assertEq(pool.totalSupply(), 0);
        assertEq(pool.balanceOf(address(user3)), 0);
        assertEq(pool.balanceOf(address(user2)), 0);
        assertEq(pool.balanceOf(address(user1)), 0);

        assertEq(lpToken.balanceOf(address(pool)), 0);
        assertEq(lpToken.balanceOf(address(user3)), initialBalance);
        assertEq(lpToken.balanceOf(address(user2)), initialBalance);
        assertEq(lpToken.balanceOf(address(user1)), initialBalance);
    }

    function testFailWithdrawMoreThanBalance() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        user1.doWithdraw(1 ether + 1);
    }

    function testFailWithdrawZero() public {
        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        user1.doWithdraw(0);
    }

    function testTransferLPTokensBeforeCampaignThenWithdraw() public {
        user1.doTransfer(address(lpToken), address(pool), 1);
        assertEq(lpToken.balanceOf(address(pool)), 1);

        pool.newCampaign(10 ether, now + 1, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 0.5 ether);
        user1.doStake(0.5 ether);

        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        hevm.warp(now + 4 days);
        user1.doWithdraw(0.5 ether);
        user2.doWithdraw(1 ether);

        assertEq(pool.totalSupply(), 0);
        assertEq(pool.balanceOf(address(user1)), 0);
        assertEq(pool.balanceOf(address(user2)), 0);
        assertEq(lpToken.balanceOf(address(pool)), 1);
    }

    // testing reward calculation
    function almostEqual(uint origValue, uint origExpected) public returns (bool) {
        uint precision = 14; // 1 / 1000
        uint value = origValue / (1 * 10 ** precision);
        uint expected = origExpected / (1 * 10 ** precision);

        return (
            value >= expected - 10 && value <= expected + 10
        );
    }

    function testRewardCalculation0() public { // one staker, one distribution
        pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        hevm.warp(now+1);

        assertEq(pool.rewardPerToken(1), 0);
        assertEq(pool.earned(address(user1), 1), 0);
        assertEq(pool.earned(address(user2), 1), 0);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        assertEq(pool.rewardPerToken(1), 0);
        assertEq(pool.earned(address(user1), 1), 0);
        assertEq(pool.earned(address(user2), 1), 0);

        hevm.warp(now + 21 days + 1);

        assertTrue(almostEqual(pool.rewardPerToken(1), 10 ether));
        assertTrue(almostEqual(pool.earned(address(user1), 1), 10 ether));
    }

    function testRewardCalculation1() public { // one staker, two distributions
        uint256 campaignId = pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        assertEq(campaignId, 1);
        hevm.warp(now+1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 21 days + 1);

        assertTrue(almostEqual(pool.rewardPerToken(1), 10 ether));
        assertTrue(almostEqual(pool.earned(address(user1), 1), 10 ether));
        assertEq(pool.earned(address(user2), 1), 0);

        hevm.warp(now + 52 weeks);

        campaignId = pool.newCampaign(10 ether, now + 1, 90 days, rewardDelay, instantExitPercentage);
        assertEq(campaignId, 2);
        hevm.warp(now + 90 days + 1);

        assertTrue(almostEqual(pool.rewardPerToken(2), 10 ether));
        assertTrue(almostEqual(pool.earned(address(user1), 2), 10 ether));
    }

    function testRewardCalculation2() public { // two stakers with same stake, three dists
        uint256 campaignId = pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        assertEq(campaignId, 1);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        hevm.warp(now + 30 weeks);
        assertTrue(almostEqual(pool.rewardPerToken(1), 5 ether));
        assertTrue(almostEqual(pool.earned(address(user1), 1), 5 ether));
        assertTrue(almostEqual(pool.earned(address(user2), 1), 5 ether));

        campaignId = pool.newCampaign(30 ether, now + 1, 90 days, rewardDelay, instantExitPercentage);
        assertEq(campaignId, 2);
        hevm.warp(now + 90 days + 1);

        assertTrue(almostEqual(pool.rewardPerToken(2), 15 ether));
        assertTrue(almostEqual(pool.earned(address(user1), 2), 15 ether));
        assertTrue(almostEqual(pool.earned(address(user2), 2), 15 ether));

        hevm.warp(now + 200 weeks);
        assertTrue(almostEqual(pool.rewardPerToken(1), 5 ether));
        assertTrue(almostEqual(pool.earned(address(user1), 1), 5 ether));
        assertTrue(almostEqual(pool.earned(address(user2), 1), 5 ether));
        assertTrue(almostEqual(pool.rewardPerToken(2), 15 ether));
        assertTrue(almostEqual(pool.earned(address(user1), 2), 15 ether));
        assertTrue(almostEqual(pool.earned(address(user2), 2), 15 ether));

        campaignId = pool.newCampaign(60 ether, now + 1, 280 days, rewardDelay, instantExitPercentage);
        assertEq(campaignId, 3);
        hevm.warp(now + 280 days + 1);

        assertTrue(almostEqual(pool.rewardPerToken(3), 30 ether));
        assertTrue(almostEqual(pool.earned(address(user1), 3), 30 ether));
        assertTrue(almostEqual(pool.earned(address(user2), 3), 30 ether));
    }

    function testRewardCalculation3() public { // two stakers with different stake
        pool.newCampaign(12 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        hevm.warp(now+1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 3 ether);
        user2.doStake(3 ether);

        hevm.warp(now + 21 days);

        assertTrue(almostEqual(pool.rewardPerToken(1), 3 ether));
        assertTrue(almostEqual(pool.earned(address(user1),1), 3 ether));
        assertTrue(almostEqual(pool.earned(address(user2),1), 9 ether));

        hevm.warp(now + 1);
        pool.newCampaign(24 ether, now + 1, 280 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 280 days + 1);

        assertTrue(almostEqual(pool.rewardPerToken(2), 6 ether));
        assertTrue(almostEqual(pool.earned(address(user1), 2), 6 ether));
        assertTrue(almostEqual(pool.earned(address(user2), 2), 18 ether));
    }

    function testRewardCalculation4() public {
        //
        // 1x: +----------------+ = 12 for 1w + 3 for 2w
        // 3x:         +--------+ =  0 for 1w + 9 for 2w
        //

        pool.newCampaign(36 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        hevm.warp(now+1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 7 days);

        user2.doApprove(address(lpToken), address(pool), 3 ether);
        user2.doStake(3 ether);

        hevm.warp(now + 14 days);

        assertTrue(almostEqual(pool.rewardPerToken(1), 18 ether));
        assertTrue(almostEqual(pool.earned(address(user1), 1), 18 ether));
        assertTrue(almostEqual(pool.earned(address(user2), 1), 18 ether));

        hevm.warp(now + 6 weeks);

        //
        // 1x: +----------------+--------+ = 3 + 1 + 1.33
        // 3x: +----------------+          = 9 + 3 + 0
        // 8x:         +-----------------+ = 0 + 8 + 10.66
        //

        pool.newCampaign(36 ether, now + 1, 21 days, rewardDelay, instantExitPercentage); // 2

        hevm.warp(now + 7 days + 1);
        assertTrue(almostEqual(pool.earned(address(user1), 2), 3 ether));
        assertTrue(almostEqual(pool.earned(address(user2), 2), 9 ether));

        user3.doApprove(address(lpToken), address(pool), 8 ether);
        user3.doStake(8 ether);

        hevm.warp(now + 7 days);
        assertTrue(almostEqual(pool.earned(address(user1), 2), 4 ether));
        assertTrue(almostEqual(pool.earned(address(user2), 2), 12 ether));
        assertTrue(almostEqual(pool.earned(address(user3), 2), 8 ether));

        user2.doWithdraw(3 ether);
        hevm.warp(now + 7 days);

        assertTrue(almostEqual(pool.earned(address(user1), 2), 5333333333333333333));
        assertTrue(almostEqual(pool.earned(address(user2), 2), 12 ether));
        assertTrue(almostEqual(pool.earned(address(user3), 2), 18666666666666666666));
    }

    function testRewardCalculation5() public { // one flash staker
        lpToken.mint(address(user1), 100000 ether);

        pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        assertEq(pool.rewardPerToken(1), 0);
        assertEq(pool.earned(address(user1), 1), 0);

        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 100000 ether);
        user1.doStake(100000 ether);
        user1.doWithdraw(100000 ether);

        assertEq(pool.rewardPerToken(1), 0);
        assertEq(pool.earned(address(user1), 1), 0);

        hevm.warp(now + 21 days);

        assertEq(pool.rewardPerToken(1), 0);
        assertEq(pool.earned(address(user1), 1), 0);
    }

    function testRewardCalculation6() public { // one staker, one distribution, 1 sec
        pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        hevm.warp(now+1);
        assertEq(pool.rewardPerToken(1), 0);
        assertEq(pool.earned(address(user1), 1), 0);
        assertEq(pool.earned(address(user2), 1), 0);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        assertEq(pool.rewardPerToken(1), 0);
        assertEq(pool.earned(address(user1), 1), 0);
        assertEq(pool.earned(address(user2), 1), 0);

        hevm.warp(now + 1); // 1 sec
        assertTrue(pool.earned(address(user1), 1) > 0);
    }

    // getReward
    function testGetReward() public {
        //
        // 1x: +----------------+--------+ = 3 + 1 + 1.33
        // 3x: +----------------+          = 9 + 3 + 0
        // 8x:         +-----------------+ = 0 + 8 + 10.66
        //

        pool.newCampaign(36 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);

        hevm.warp(now + 1);

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

        user1.doGetReward(1);
        user2.doGetReward(1);
        user3.doGetReward(1);

        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), (5333333333333333333 * instantExitPercentage) / 1000));
        assertTrue(almostEqual(rewardToken.balanceOf(address(user2)), (12 ether * instantExitPercentage) / 1000));
        assertTrue(almostEqual(rewardToken.balanceOf(address(user3)), (18666666666666666666 * instantExitPercentage) / 1000));

        // checking locked rewards
        (uint totalAmount, uint exitedAmount, uint lastExitTime) = pool.delayedRewards(address(user1), 1);
        assertTrue(almostEqual(totalAmount, 5333333333333333333 - ((5333333333333333333 * instantExitPercentage) / 1000)));
        assertEq(exitedAmount, 0);
        assertEq(lastExitTime, now);

        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user2), 1);
        assertTrue(almostEqual(totalAmount, 12 ether - ((12 ether * instantExitPercentage) / 1000)));
        assertEq(exitedAmount, 0);
        assertEq(lastExitTime, now);

        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user3), 1);
        assertTrue(almostEqual(totalAmount, 18666666666666666666 - ((18666666666666666666 * instantExitPercentage) / 1000)));
        assertEq(exitedAmount, 0);
        assertEq(lastExitTime, now);
    }

   function testGetReward2() public {
        user1.doApprove(address(lpToken), address(pool), 1 ether);
        pool.modifyParameters("maxCampaigns", 100);

        uint totalCampaigns = 80;
        for (uint i = 1; i <= totalCampaigns; i++) {
            pool.newCampaign(1 ether, i * 1 weeks + block.timestamp, 5 days, rewardDelay, instantExitPercentage);
            // hevm.warp(now + 2 weeks);
        }

        hevm.warp(1 weeks + block.timestamp);
        user1.doStake(1 ether);
        hevm.warp(now + 84 weeks);

        // check reward amount for user1, fully vested
        user1.doGetReward(1);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), 1 ether));

        user1.doGetReward(5);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), 2 ether));

        user1.doGetReward(80);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), 3 ether));
    }

    function testGetLockedReward() public {
        pool.newCampaign(30 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);
        user3.doApprove(address(lpToken), address(pool), 1 ether);
        user3.doStake(1 ether);

        hevm.warp(now + 21 days);

        user1.doGetReward(1); // 10 eth each
        user2.doGetReward(1);
        user3.doGetReward(1);

        uint instantReward = (10 ether * instantExitPercentage) / 1000;
        uint amountLocked = 10 ether - instantReward;

        // 3 days rewardDelay
        hevm.warp(now + 3 days + 1);

        user1.doGetLockedReward(address(user1), 1);
        (uint totalAmount, uint exitedAmount, uint lastExitTime) = pool.delayedRewards(address(user1), 1);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked / 4));
        assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward + (amountLocked / 4)));

        // 6 days
        hevm.warp(now + 3 days);

        user1.doGetLockedReward(address(user2), 1);
        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user2), 1);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked / 2));
        assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user2)), instantReward + (amountLocked / 2)));

        // 12 days - all unlocked
        hevm.warp(now + 6 days);

        user1.doGetLockedReward(address(user3), 1);
        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user3), 1);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked));
        assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user3)), instantReward + amountLocked));

        user1.doGetLockedReward(address(user1), 1);
        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user1), 1);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked));
        assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward + amountLocked));

        // far into the future
        hevm.warp(now + 104 weeks);

        user1.doGetLockedReward(address(user2), 1);
        (totalAmount, exitedAmount, lastExitTime) = pool.delayedRewards(address(user2), 1);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked));
        assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user2)), instantReward + amountLocked));
    }

    function testGetLockedReward2() public {
        // testing get locked rewards with smallest interval possible (one block, around 15secs)
        pool.newCampaign(1000 ether, now + 1, 21 days, 16 weeks, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        hevm.warp(now + 21 days);

        user1.doGetReward(1); // 500 tokens each

        uint instantReward = (500 ether * instantExitPercentage) / 1000;
        uint amountLocked = 500 ether - instantReward;

        hevm.warp(now + 2); // start of vesting
        uint interval = 10; // 10 seconds
        for (uint i = 1; i <= 20; i++) {
            hevm.warp(now + interval);
            user1.doGetLockedReward(address(user1), 1);
            assertTrue(rewardToken.balanceOf(address(user1)) > instantReward); // increases per sec
        }

        hevm.warp(now + 16 weeks); // end of vesting
        user1.doGetLockedReward(address(user1), 1);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward + amountLocked));
    }

    function testFailGetLockedRewardNoBalance() public {
        pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 21 days);

        user1.doGetReward(1); // 10

        hevm.warp(now + rewardDelay);

        user1.doGetLockedReward(address(user1), 1);
        user1.doGetLockedReward(address(user1), 1);
    }

    function testFailInvalidTimeElapsed() public {
        pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 21 days);

        user1.doGetReward(1); // 10

        hevm.warp(now + 2 hours);

        user1.doGetLockedReward(address(user1), 1);
        user1.doGetLockedReward(address(user1), 1);
    }

    // exit
    function testExit() public {
        pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);

        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 21 days);

        uint instantReward = (10 ether * instantExitPercentage) / 1000;
        uint amountLocked = 10 ether - instantReward;

        user1.doExit();

        (uint totalAmount, uint exitedAmount, uint lastExitTime) = pool.delayedRewards(address(user1), 1);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertEq(exitedAmount, 0);
        assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward));
    }

    function testExitMidVesting() public {
        pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 21 days + 1);
        hevm.warp(now + (rewardDelay / 2));

        uint instantReward = (10 ether * instantExitPercentage) / 1000;
        uint amountLocked = 10 ether - instantReward;

        user1.doExit();

        (uint totalAmount, uint exitedAmount, uint lastExitTime) = pool.delayedRewards(address(user1), 1);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertTrue(almostEqual(exitedAmount, amountLocked / 2));
        assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward + (amountLocked / 2)));
    }

    function testExitAfterVesting() public {
        pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);

        hevm.warp(now + 1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 21 days + 1);
        hevm.warp(now + rewardDelay);

        uint instantReward = (10 ether * instantExitPercentage) / 1000;
        uint amountLocked = 10 ether - instantReward;

        user1.doExit();

        (uint totalAmount, uint exitedAmount, uint lastExitTime) = pool.delayedRewards(address(user1), 1);
        assertTrue(almostEqual(totalAmount, amountLocked));
        assertEq(exitedAmount, totalAmount);
        assertEq(lastExitTime, now);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), instantReward + exitedAmount));
    }

    // notifyRewardamount
    function testNewCampaign() public {
        assertEq(pool.lastCampaign(), 0);
        assertEq(pool.firstCampaign(), 0);
        assertEq(pool.globalReward(), 0);
        assertEq(pool.campaignCount(), 0);
        assertEq(pool.campaignListLength(), 0);
        assertEq(pool.contractEnabled(), 1);

        pool.newCampaign(10 ether, now + 1, 21 days, 0, 1000);

        assertEq(pool.lastCampaign(), 1);
        assertEq(pool.firstCampaign(), 1);
        assertEq(pool.globalReward(), 10 ether);
        assertEq(pool.campaignCount(), 1);
        assertEq(pool.campaignListLength(), 1);
        assertEq(pool.contractEnabled(), 1);

        (
            uint reward,
            uint startTime,
            uint duration,
            uint rewardRate,
            uint lastUpdateTime,
            uint rewardPerToken,
            uint rewardDelay,
            uint instantExitPercentage
        ) = pool.campaigns(1);
        assertEq(reward, 10 ether);
        assertEq(startTime, now + 1);
        assertEq(duration, 21 days);
        assertEq(rewardRate, reward / 21 days);
        assertEq(lastUpdateTime, now + 1);
        assertEq(rewardPerToken, 0);
        assertEq(rewardDelay, 0);
        assertEq(instantExitPercentage, 1000);
    }

    function testFailNewCampaignInvalidInstantExitPercenntage() public {
        pool.newCampaign(10 ether, now + 30 days, 30 days, rewardDelay, 1001);
    }

    function testFailNewCampaignRewardZero() public {
        pool.newCampaign(0, now + 30 days, 30 days, rewardDelay, instantExitPercentage);
    }

    function testFailNewCampaignDurationZero() public {
        pool.newCampaign(10 ether, now + 30 days, 0, rewardDelay, instantExitPercentage);
    }

    function testFailNewCampaignStartPast() public {
        pool.newCampaign(10 ether, now - 1, 30 days, rewardDelay, instantExitPercentage);
    }

    function testFailNotifyRewardAmountUnauthorized() public {
        user1.doNewCampaign(10 ether, now + 1, 1 days);
    }

    function testRollingMaxCampaigns() public {
        for (uint i = 1; i <= pool.DEFAULT_MAX_CAMPAIGNS() * 2; i++) {
            pool.newCampaign(1 ether, i * 1 weeks + block.timestamp, 5 days, rewardDelay, instantExitPercentage);
        }
        assertEq(pool.campaignCount(), pool.DEFAULT_MAX_CAMPAIGNS() * 2);
        assertEq(pool.campaignListLength(), pool.DEFAULT_MAX_CAMPAIGNS());
        assertEq(pool.firstCampaign(), pool.DEFAULT_MAX_CAMPAIGNS() + 1);
        assertEq(pool.lastCampaign(), pool.DEFAULT_MAX_CAMPAIGNS() * 2);
    }

    function testFailNewCampaignOverlappingCampaigns() public {
        pool.newCampaign(10 ether, now + 1, 30 days, rewardDelay, instantExitPercentage);
        pool.newCampaign(10 ether, now + 2 days, 30 days, rewardDelay, instantExitPercentage);
    }

    // cancel
    function testFailCancelledCampaignGetReward() public { // one staker, one distribution
        pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        pool.cancelCampaign(1);
        hevm.warp(now+1);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);

        hevm.warp(now + 21 days);

        user1.doGetReward(1);
    }

    function testCancelCampaign() public {
        pool.newCampaign(10 ether, now + 1 days, 21 days, rewardDelay, instantExitPercentage);
        pool.newCampaign(10 ether, now + 4 weeks, 21 days, rewardDelay, instantExitPercentage);

        assertEq(pool.campaignListLength(), 2);
        assertEq(pool.lastCampaign(), 2);
        assertEq(pool.firstCampaign(), 1);
        pool.cancelCampaign(2);

        (
            ,
            uint startTime,
            uint duration,
            ,,,,
        ) = pool.campaigns(2);
        assertEq(startTime, 0);
        assertEq(duration, 0);
        assertEq(pool.globalReward(), 10 ether);
        assertEq(pool.campaignListLength(), 1);
        assertEq(pool.lastCampaign(), 1);
        assertEq(pool.firstCampaign(), 1);

        // cancelling last campaign
        pool.cancelCampaign(1);
        assertEq(pool.campaignListLength(), 0);
        assertEq(pool.lastCampaign(), 0);
        assertEq(pool.firstCampaign(), 0);
        assertEq(pool.globalReward(), 0);
    }

    function testFailCancelCampaignAlreadyStarted() public {
        pool.newCampaign(10 ether, now + 1, 21 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 1);
        pool.cancelCampaign(1);
    }

    function testCancelCampaignRecreateStakeWithdraw() public {
        pool.newCampaign(10 ether, now + 1 days, 21 days, rewardDelay, instantExitPercentage);

        hevm.warp(now + 1);
        pool.cancelCampaign(1);

        pool.newCampaign(10 ether, now + 1 days, 21 days, rewardDelay, instantExitPercentage);
        hevm.warp(now + 11 days);

        assertEq(pool.campaignListLength(), 1);
        assertEq(pool.lastCampaign(), 2);
        assertEq(pool.firstCampaign(), 2);

        user1.doApprove(address(lpToken), address(pool), 1 ether);
        user1.doStake(1 ether);
        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        hevm.warp(now + 9 days);
        user3.doApprove(address(lpToken), address(pool), 1 ether);
        user3.doStake(1 ether);

        hevm.warp(now + 1 days);
        user1.doWithdraw(0.5 ether);
        user2.doWithdraw(0.5 ether);
        user3.doWithdraw(0.5 ether);

        assertEq(pool.balanceOf(address(user3)), 0.5 ether);
        assertEq(pool.balanceOf(address(user2)), 0.5 ether);
        assertEq(pool.balanceOf(address(user1)), 0.5 ether);

        assertEq(lpToken.balanceOf(address(pool)), 1.5 ether);
        assertEq(lpToken.balanceOf(address(user3)), initialBalance - 0.5 ether);
        assertEq(lpToken.balanceOf(address(user2)), initialBalance - 0.5 ether);
        assertEq(lpToken.balanceOf(address(user1)), initialBalance - 0.5 ether);

        hevm.warp(now + 1 days);
        user1.doWithdraw(0.5 ether);
        user2.doWithdraw(0.5 ether);
        user3.doWithdraw(0.5 ether);

        assertEq(pool.balanceOf(address(user3)), 0);
        assertEq(pool.balanceOf(address(user2)), 0);
        assertEq(pool.balanceOf(address(user1)), 0);

        assertEq(lpToken.balanceOf(address(pool)), 0);
        assertEq(lpToken.balanceOf(address(user3)), initialBalance);
        assertEq(lpToken.balanceOf(address(user2)), initialBalance);
        assertEq(lpToken.balanceOf(address(user1)), initialBalance);
    }

    function testUpdateRewardBounds() public {
        uint maxGas = 7000000;  // a bit more than half of the mainnet block gas limit
        pool.modifyParameters("maxCampaigns", 100);

        user1.doApprove(address(lpToken), address(pool), 1 ether);

        uint totalCampaigns = 100;
        for (uint i = 1; i <= totalCampaigns; i++) {
            pool.newCampaign(1 ether, i * 1 weeks + block.timestamp, 5 days, rewardDelay, instantExitPercentage);
        }

        hevm.warp(1 weeks + block.timestamp);
        user1.doStake(1 ether);
        hevm.warp(now + 80 weeks);

        user2.doApprove(address(lpToken), address(pool), 1 ether);
        uint previousGas = gasleft();
        user2.doStake(1 ether); // this will update all 80 previous campaigns, along with user info (unlikely to ever happen, as past campaigns are not reupdated)
        assertTrue(previousGas - gasleft() < maxGas);

        user1.doWithdraw(1 ether);
        assertEq(rewardToken.balanceOf(address(user1)), 0 ether);

        hevm.warp(now + 10 weeks);

        user3.doApprove(address(lpToken), address(pool), 1 ether);
        user3.doStake(1 ether);

        hevm.warp(now + 14 weeks);

        user1.doGetReward(1);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), 1 ether));

        user1.doGetReward(5);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user1)), 2 ether));

        user2.doWithdraw(1 ether);
        user3.doWithdraw(1 ether);

        user2.doGetReward(88);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user2)), 1 ether));

        user2.doGetReward(95);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user2)), 1.5 ether));

        user3.doGetReward(95);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user3)), 0.5 ether));
    }

    function testFailGetRewardsNoReward() public {

        pool.modifyParameters("maxCampaigns", 30);

        uint totalCampaigns = 25;
        for (uint i = 1; i <= totalCampaigns; i++) {
            pool.newCampaign(1 ether, i * 1 weeks + block.timestamp, 5 days, rewardDelay, instantExitPercentage);
        }
        hevm.warp(now + 10 weeks);

        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        hevm.warp(now + 10 weeks);

        user2.doGetReward(12);
        assertTrue(almostEqual(rewardToken.balanceOf(address(user2)), 1 ether));

        user2.doGetReward(2); // was not staking at the time
    }

    function testDisableContract() public {
        pool.newCampaign(1 ether, 1 weeks + block.timestamp, 5 days, rewardDelay, instantExitPercentage);
        pool.disableContract();
        assertEq(pool.contractEnabled(), 0);
    }

    function testFailDisableContractUnauthorized() public {
        pool.newCampaign(1 ether, 1 weeks + block.timestamp, 5 days, rewardDelay, instantExitPercentage);
        pool.removeAuthorization(address(this));
        pool.disableContract();
    }

    function testFailStakeInDisabledContract() public {
        pool.newCampaign(1 ether, 1 weeks + block.timestamp, 5 days, rewardDelay, instantExitPercentage);
        pool.disableContract();
        assertEq(pool.contractEnabled(), 0);

        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);
    }

    function testWithdrawFromDisabledContract() public {
        pool.newCampaign(1 ether, 1 weeks + block.timestamp, 5 days, rewardDelay, instantExitPercentage);
        hevm.warp(1 weeks + block.timestamp);

        user2.doApprove(address(lpToken), address(pool), 1 ether);
        user2.doStake(1 ether);

        pool.disableContract();
        assertEq(pool.contractEnabled(), 0);

        user2.doWithdraw(1 ether);
    }
}
