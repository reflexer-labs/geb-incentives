pragma solidity ^0.6.7;

import "../../uniswap/RollingDistributionIncentives.sol";

// @notice Fuzz the whole thing, assess the results to see if failures make sense
contract GeneralFuzz is RollingDistributionIncentives {

    constructor() public
        RollingDistributionIncentives(
            address(0x1),
            address(0x2)
        ){}
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

// @notice Fuzz user interactions with the contract throuout several campaigns
contract ExecutionFuzz {
    MockToken lpToken;
    MockToken rewardToken;
    RollingDistributionIncentives pool;
    Farmer[] farmers;
    uint userCount = 2;
    uint campaignCount = 10;
    uint campaignValue = 1 ether;
    uint maxTxValue = 100000 ether;

    constructor() public {
        lpToken = new MockToken();
        rewardToken = new MockToken();
        pool = new RollingDistributionIncentives(address(lpToken), address(rewardToken));
        pool.modifyParameters("canStake", 1);

        // creating users and setting up campaigns (1/week, 1 ether each, no vesting)
        for (uint i = 0; i < userCount; i++) {
            farmers.push(new Farmer(pool));
        }

        for (uint i = 0; i < campaignCount; i++) {
            pool.newCampaign(1 ether, block.timestamp + 1 + (i * 1 weeks) , 6.5 days, 1, 1000);
        }
    }

    // will stake a random amount within maxTxValue
    function stake(uint user, uint amount) public {
        farmers[user%userCount].doStake(amount%maxTxValue);
    }

    // will withdraw a valid amount (less than user balance)
    function withdraw(uint user, uint amount) public {
        Farmer farmer = farmers[user%userCount];
        uint previousBalance = pool.balanceOf(address(farmer));

        if (previousBalance == 0) {
            farmer.doWithdraw(amount% maxTxValue); // will always gracefully revert
        } else {
            try farmer.doWithdraw(amount% previousBalance) {} catch {assert(false);} // will fail if withdraw reverts
            assert(pool.balanceOf(address(farmer)) == previousBalance - amount%previousBalance); // asserts balances
        }
    }

    // gets rewards for a random campaign
    function getRewards(uint user, uint campaign) public {
        uint currentCampaign = pool.currentCampaign();
        Farmer(farmers[user%userCount]).doGetReward(campaign%(currentCampaign == 0 ? campaignCount : currentCampaign));
    }

    function echidna_test_pool_totalSupply() public returns (bool) {
        return (pool.totalSupply() == lpToken.received(address(pool)) - lpToken.sent(address(pool)));
    }

    function echidna_test_rewards() public returns (bool passed) {
        uint currentCampaign = pool.currentCampaign();
        if (currentCampaign == 0) {
            return rewardToken.sent(address(pool)) < campaignCount * campaignValue;
        }
    }
}
    