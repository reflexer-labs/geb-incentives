pragma solidity 0.6.7;

import "ds-token/delegate.sol";
import "ds-token/token.sol";

import "ds-test/test.sol";

import "../uniswap/StakingRewardsFactory.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract StakingRewardsTest is DSTest {
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

    }
    function test_deploy_campaign_check_setup_before_notify() public {

    }
    function test_deploy_campaign_check_setup_after_one_notify() public {

    }
    function test_deploy_campaign_check_setup_after_multi_notify() public {

    }
    function test_stake_unstake_before_any_rewards() public {

    }
    function test_unstake_after_campaign_expiry() public {

    }
    function test_stake_claim_once() public {

    }
    function test_stake_claim_multi() public {

    }
    function test_stake_claim_after_campaign_expiry() public {

    }
    function test_multi_user_stake_claim() public {

    }
    function test_multi_user_stake_claim_unstake() public {

    }
    function test_stake_post_campaign_end_before_any_claim() public {

    }
    function test_stake_notify_twice_unstake_claim() public {
      
    }
}
