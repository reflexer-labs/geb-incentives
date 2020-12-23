pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "../uniswap/RollingDistributionIncentives.sol";

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

contract RateSetterFuzz {


}