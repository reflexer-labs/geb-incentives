pragma solidity ^0.6.7;

// import "../../../lib/ds-token/src/token.sol"; // echidna will not recognize dapp tools style import
import "../../uniswap/RollingDistributionIncentives.sol";

// contract Farmer {
//     RollingDistributionIncentives pool;

//     constructor(RollingDistributionIncentives pool_) public {
//         pool = pool_;
//     }

//     function doStake(uint amount) public {
//         pool.stake(amount);
//     }

//     function doStakeFor(uint amount, address owner) public {
//         pool.stake(amount, owner);
//     }

//     function doWithdraw(uint amount) public {
//         pool.withdraw(amount);
//     }

//     function doExit() public {
//         pool.exit();
//     }

//     function doGetLockedReward(address account, uint campaignId) public {
//         pool.getLockedReward(account, campaignId);
//     }

//     function doGetReward(uint campaign) public {
//         pool.getReward(campaign);
//     }

//     function doApprove(address token, address who, uint value) public {
//         DSToken(token).approve(who, value);
//     }

//     function doModifyParameters(bytes32 parameter, uint256 campaignId, uint256 val) public {
//         pool.modifyParameters(parameter, campaignId, val);
//     }

//     function doModifyParameters(bytes32 parameter, uint256 val) public {
//         pool.modifyParameters(parameter, val);
//     }

//     function doWithdrawExtraRewardTokens() public {
//         pool.withdrawExtraRewardTokens();
//     }

//     function doNewCampaign(uint256 reward, uint256 startTime, uint256 duration) public {
//         pool.newCampaign(reward, startTime, reward, 0, 1000);
//     }

//     function doTransfer(address token, address receiver, uint256 amount) public {
//         DSToken(token).transfer(receiver, amount);
//     }
// }

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

// @notice Fuzz user interactions with the contract throuout 5 campaigns
contract ExecutionFuzz {
    MockToken lpToken;
    MockToken rewardToken;
    RollingDistributionIncentives pool;
    Farmer[] farmers;
    uint userCount = 10;
    uint campaignCount = 3;
    uint campaignValue = 1 ether;
    uint maxTxValue = 100000 * 10 ** 18;

    constructor() public {
        lpToken = new MockToken();
        rewardToken = new MockToken();
        pool = new RollingDistributionIncentives(address(lpToken), address(rewardToken));

        // creating users and setting up campaigns (1/week, 1 ether each, no vesting)
        for (uint i = 0; i < userCount; i++) {
            farmers.push(new Farmer(pool));
        }

        for (uint i = 0; i < campaignCount; i++) {
            pool.newCampaign(1 ether, (i + 1) * 1 weeks + block.timestamp, 5 days, 1, 1000);
        }
    }

    function stake(uint user, uint amount) public {
        Farmer(farmers[user%userCount]).doStake(amount%maxTxValue);
    }
    function withdraw(uint user, uint amount) public {
        Farmer farmer = farmers[user%userCount];
        uint previousBalance = pool.balanceOf(address(farmer));
        farmer.doWithdraw(amount%previousBalance);

        assert(pool.balanceOf(address(farmer)) == previousBalance - (amount%previousBalance));
    }
    function getRewards(uint user, uint campaign) public {
        Farmer(farmers[user%userCount]).doGetReward(campaign%campaignCount);
    }

    function echidna_test_totalSupply() public returns (bool) {
        return (pool.totalSupply() == lpToken.received(address(pool)) - lpToken.sent(address(pool)));
    }

    function echidna_test_rewards() public returns (bool passed) {
        return rewardToken.sent(address(pool)) < campaignCount * campaignValue;
    }

}
    