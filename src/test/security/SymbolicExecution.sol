pragma solidity ^0.6.7;

import "../../uniswap/RollingDistributionIncentives.sol";
import "ds-test/test.sol";

abstract contract Hevm {
    function warp(uint) virtual public;
    function roll(uint) virtual public;
}

// @notice Mock token used for testing
contract MockToken {
    uint constant maxUint = uint(0) - 1;
    mapping (address => uint256) public received;
    mapping (address => uint256) public sent;

    function totalSupply() public view returns (uint) {
        return maxUint;
    }
    function balanceOf(address src) public view returns (uint) {
        return maxUint;
    }
    function allowance(address src, address guy) public view returns (uint) {
        return maxUint;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        received[dst] += wad;
        sent[src]     += wad;
        return true;
    }

    function approve(address guy, uint wad) virtual public returns (bool) {

        return true;
    }
}

contract Farmer {
    RollingDistributionIncentives pool;

    constructor(RollingDistributionIncentives pool_) public {
        pool = pool_;
    }

    function doStake(uint amount) public {
        pool.stake(amount);
    }

    function doWithdraw(uint amount) public {
        pool.withdraw(amount);
    }

    function doGetLockedReward(address account, uint campaignId) public {
        pool.getLockedReward(account, campaignId);
    }

    function doGetReward(uint campaign) public {
        pool.getReward(campaign);
    }
}

// @notice Symbolic execution of key functions
contract SymbolicExecutionTest is DSTest {
    Hevm      hevm;
    MockToken lpToken;
    MockToken rewardToken;
    RollingDistributionIncentives pool;
    Farmer[] farmers;
    uint userCount = 5;
    uint campaignCount = 100;
    uint campaignValue = 1 ether;
    uint maxTxValue = 100 ether;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        lpToken = new MockToken();
        rewardToken = new MockToken();
        pool = new RollingDistributionIncentives(address(lpToken), address(rewardToken));
        pool.modifyParameters("canStake", 1);

        // creating users and setting up campaigns (1/week, 1 ether each, no vesting)
        for (uint i = 0; i < userCount; i++) {
            farmers.push(new Farmer(pool));
        }

        for (uint i = 0; i < campaignCount; i++) {
            pool.newCampaign(campaignValue, block.timestamp + 1 + (i * 1 weeks) , 1 weeks - 1, 1, 1000);
        }
        hevm.warp(now+1);
    }

    // will stake a random amount within maxTxValue
    function prove_stake(uint amount) public {
        if (amount % maxTxValue == 0) return; // preventing zero staking, hevm will fail for reverts unlike echidna

        uint previousBalance = pool.balanceOf(address(farmers[0]));
        farmers[0].doStake(amount%maxTxValue);
        assertEq(pool.balanceOf(address(farmers[0])), previousBalance + amount%maxTxValue); // asserts balances
        assertEq(pool.totalSupply(), previousBalance + amount%maxTxValue); // asserts totalSupply
        assertEq(lpToken.sent(address(farmers[0])),  lpToken.received(address(pool)));
        assertEq(lpToken.sent(address(farmers[0])),  amount%maxTxValue);
    }

    // will withdraw a valid amount (less than user balance) after a time determined by warp, tuned to span all campaigns
    function prove_withdraw(uint amount, uint warp) public {
        if (amount % maxTxValue == 0) return; // preventing zero staking, hevm will fail for reverts unlike echidna

        Farmer farmer = farmers[0];
        farmer.doStake(amount%maxTxValue);

        hevm.warp(now + (warp % (campaignCount * 1 weeks)));
        uint previousBalance = pool.balanceOf(address(farmer));

        uint amountToWithdraw = amount%previousBalance == 0 ? amount%maxTxValue : amount%previousBalance;

        try farmer.doWithdraw(amountToWithdraw) {} catch {assertTrue(false);} // will fail if withdraw reverts
        assertEq(pool.balanceOf(address(farmer)), previousBalance - amountToWithdraw); // asserts balances
        assertEq(pool.totalSupply(), previousBalance - amountToWithdraw); // asserts totalSupply
        assertEq(lpToken.sent(address(farmer)),  lpToken.received(address(pool)));
        assertEq(lpToken.received(address(farmer)),  amountToWithdraw);
    }

    // gets rewards for a random campaign
    function prove_getRewards(uint users, uint amount, uint warp) public {
        if (amount % maxTxValue == 0) return; // preventing zero staking, hevm will fail for reverts unlike echidna

        Farmer farmer = farmers[users%userCount];
        farmer.doStake(amount%maxTxValue);

        hevm.warp(now + (warp % (campaignCount * 1 weeks)));

        uint currentCampaign = pool.currentCampaign();
        if (currentCampaign > 1) {// testing for complete campaigns
            farmer.doGetReward(currentCampaign - 1);

            assertTrue(rewardToken.received(address(farmer)) > 0.999999 ether); // asserts balances, allow for loss of precision
            assertTrue(rewardToken.sent(address(pool)) > 0.999999 ether); // asserts balances, allow for loss of precision
        }
    }
}
    