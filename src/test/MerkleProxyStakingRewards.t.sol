pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/delegate.sol";

import "geb-proxy-registry/GebProxyRegistry.sol";

import {MockGebProxyIncentivesActions} from "./mock/MockGebProxyIncentivesActions.sol";
import {MockMerkleProxyStakingRewards} from "./mock/MockMerkleProxyStakingRewards.sol";
import {NonProxyNonOwnable} from "./mock/NonProxyNonOwnable.sol";
import {NonProxyOwnable} from "./mock/NonProxyOwnable.sol";
import "./mock/Staker.sol";
import "./mock/MockStakingRewardsFactory.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract MerkleProxyStakingRewardsTest is DSTest, ProxyCalls {
    Hevm hevm;

    MockStakingRewardsFactory rewardsFactory;
    MockMerkleProxyStakingRewards stakingRewards;
    NonProxyNonOwnable nonProxyNonOwnable;
    NonProxyOwnable nonProxyOwnable;

    GebProxyRegistry registry;
    DSProxyFactory proxyFactory;

    DSDelegateToken rewardToken;
    DSToken stakingToken;

    Staker alice;

    uint256 merkleAmount      = 100E18;
    uint256 initAmountToMint  = 1000 ether;
    uint256 defaultDuration   = 12 hours;
    uint256 defaultReward     = 10 ether;
    bytes32 merkleRoot        = bytes32(keccak256(abi.encode(string("merkleRoot"))));
    bytes32[] merkleProof;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        rewardToken = new DSDelegateToken("GOV", "GOV");
        stakingToken = new DSToken("STAKE", "STAKE");

        rewardToken.mint(address(this), initAmountToMint);
        stakingToken.mint(address(this), initAmountToMint);

        proxyFactory = new DSProxyFactory();
        registry = new GebProxyRegistry(address(proxyFactory));

        rewardsFactory = new MockStakingRewardsFactory(address(rewardToken));
        proxyActions = address(new MockGebProxyIncentivesActions());

        // Create a merkle authed campaign
        rewardsFactory.deployMerkleAuthed(
          address(stakingToken),
          address(registry),
          defaultReward,
          defaultDuration,
          merkleRoot
        );

        (address stakingContract, uint rewardAmount) = rewardsFactory.stakingRewardsInfo(0);

        nonProxyNonOwnable = new NonProxyNonOwnable(stakingContract, address(stakingToken));
        nonProxyOwnable    = new NonProxyOwnable(stakingContract, address(stakingToken));
        stakingRewards     = MockMerkleProxyStakingRewards(stakingContract);

        assertEq(rewardAmount, defaultReward);
    }

    function test_setup() public {
        assertEq(stakingRewards.merkleAuth(), 1);
        assertEq(address(stakingRewards.registry()), address(registry));
        assertEq(address(stakingRewards.rewardsDistribution()), address(rewardsFactory));
        assertEq(address(stakingRewards.rewardsToken()), address(rewardToken));
        assertEq(address(stakingRewards.stakingToken()), address(stakingToken));
        assertEq(stakingRewards.rewardsDuration(), defaultDuration);
        assertEq(stakingRewards.merkleRoot(), merkleRoot);

        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);

        assertEq(stakingRewards.periodFinish(), now + defaultDuration);
        assertEq(stakingRewards.rewardRate(), defaultReward / defaultDuration);
        assertEq(stakingRewards.lastUpdateTime(), now);
        assertEq(stakingRewards.rewardPerTokenStored(), 0);
    }
    function test_original_caller_eoa() public {
        assertEq(stakingRewards.originalCaller(address(0x10)), address(0x10));
    }
    function test_original_caller_proxy_contract() public {
        registry.build(address(0x10));
        assertEq(stakingRewards.originalCaller(address(registry.proxies(address(0x10)))), address(0x10));
    }
    function testFail_original_caller_non_proxy_non_ownable() public {
        assertEq(stakingRewards.originalCaller(address(nonProxyNonOwnable)), address(0x10));
    }
    function testFail_original_caller_non_proxy_ownable() public {
        nonProxyOwnable.setOwner(address(0x10));
        assertEq(stakingRewards.originalCaller(address(nonProxyOwnable)), address(0x10));
    }
    function test_stake_using_proxy() public {
        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);
        registry.build(address(this));

        assertEq(stakingRewards.merkleUserBalances(address(this)), 0);

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));
        this.stakeInMine(address(stakingRewards), 1 ether, 1, merkleAmount, merkleProof);

        assertEq(stakingRewards.merkleUserBalances(address(this)), 1 ether);
        assertEq(stakingRewards.totalSupply(), 1 ether);
        assertEq(stakingRewards.balanceOf(address(userProxy)), 1 ether);

        rewardsFactory.notifyRewardAmount(0);
        hevm.warp(now + 10 seconds);

        this.stakeInMine(address(stakingRewards), 99 ether, 1, merkleAmount, merkleProof);
        assertEq(stakingRewards.merkleUserBalances(address(this)), 100 ether);
        assertEq(stakingRewards.totalSupply(), 100 ether);
        assertEq(stakingRewards.balanceOf(address(userProxy)), 100 ether);
    }
    function testFail_stake_using_proxy_above_merkle_limit() public {
        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);
        registry.build(address(this));

        assertEq(stakingRewards.merkleUserBalances(address(this)), 0);

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));
        this.stakeInMine(address(stakingRewards), merkleAmount + 1, 1, merkleAmount, merkleProof);
    }
    function test_stake_withdraw_using_proxy() public {
        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);
        registry.build(address(this));

        assertEq(stakingRewards.merkleUserBalances(address(this)), 0);

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));
        this.stakeInMine(address(stakingRewards), 1 ether, 1, merkleAmount, merkleProof);

        this.withdrawFromMine(address(stakingRewards), 0.5 ether);
        assertEq(stakingRewards.merkleUserBalances(address(this)), 0.5 ether);
        assertEq(stakingRewards.totalSupply(), 0.5 ether);
        assertEq(stakingRewards.balanceOf(address(userProxy)), 0.5 ether);

        this.withdrawFromMine(address(stakingRewards), 0.5 ether);
        assertEq(stakingRewards.merkleUserBalances(address(this)), 0);
        assertEq(stakingRewards.totalSupply(), 0);
        assertEq(stakingRewards.balanceOf(address(userProxy)), 0);
    }
    function testFail_non_merkle_authed_stake() public {
        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);
        registry.build(address(this));

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));
        this.stakeInMine(address(stakingRewards), 1 ether);
    }
    function testFail_withdraw_when_nothing_staked() public {
        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);
        registry.build(address(this));

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));
        this.withdrawFromMine(address(stakingRewards), 0.5 ether);
    }
    function test_stake_withdraw_and_harvest() public {
        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);
        registry.build(address(this));

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));

        uint256 currentRewardTokenBalance  = rewardToken.balanceOf(address(this));
        uint256 currentStakingTokenBalance = stakingToken.balanceOf(address(this));

        this.stakeInMine(address(stakingRewards), 1 ether, 1, merkleAmount, merkleProof);
        hevm.warp(now + defaultDuration / 2);
        this.withdrawAndHarvest(address(stakingRewards), 0.5 ether);

        assertTrue(rewardToken.balanceOf(address(this)) > currentRewardTokenBalance);
        assertEq(currentStakingTokenBalance, stakingToken.balanceOf(address(this)) + 0.5 ether);
        assertEq(stakingRewards.merkleUserBalances(address(this)), 0.5 ether);
        assertEq(stakingRewards.totalSupply(), 0.5 ether);
        assertEq(stakingRewards.balanceOf(address(userProxy)), 0.5 ether);
    }
    function test_stake_exit() public {
        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);
        registry.build(address(this));

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));

        uint256 currentRewardTokenBalance  = rewardToken.balanceOf(address(this));
        uint256 currentStakingTokenBalance = stakingToken.balanceOf(address(this));

        this.stakeInMine(address(stakingRewards), 1 ether, 1, merkleAmount, merkleProof);
        hevm.warp(now + defaultDuration / 2);
        this.exitMine(address(stakingRewards));

        assertTrue(rewardToken.balanceOf(address(this)) > currentRewardTokenBalance);
        assertEq(currentStakingTokenBalance, stakingToken.balanceOf(address(this)));
        assertEq(stakingRewards.merkleUserBalances(address(this)), 0);
        assertEq(stakingRewards.totalSupply(), 0);
        assertEq(stakingRewards.balanceOf(address(userProxy)), 0);
    }
    function testFail_stake_transfer_ownership_withdraw() public {
        alice = new Staker(address(proxyActions));

        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);

        registry.build(address(this));
        registry.build(address(alice));

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));

        uint256 currentRewardTokenBalance  = rewardToken.balanceOf(address(this));
        uint256 currentStakingTokenBalance = stakingToken.balanceOf(address(this));

        this.stakeInMine(address(stakingRewards), 1 ether, 1, merkleAmount, merkleProof);
        userProxy.setOwner(address(alice));
        alice.setProxy(userProxy);

        alice.withdrawFromMine(address(stakingRewards), 1 ether);
    }
    function testFail_stake_both_transfer_ownership_withdraw() public {
        alice = new Staker(address(proxyActions));

        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);

        registry.build(address(this));
        registry.build(address(alice));

        alice.setProxy(registry.proxies(address(alice)));
        alice.approveToken(address(registry.proxies(address(alice))), address(stakingToken), uint(-1));
        stakingToken.transfer(address(alice), 1 ether);

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));
        alice.stakeInMine(address(stakingRewards), 1 ether, 1, merkleAmount, merkleProof);

        this.stakeInMine(address(stakingRewards), 1 ether, 1, merkleAmount, merkleProof);
        userProxy.setOwner(address(alice));
        alice.setProxy(userProxy);

        assertEq(stakingRewards.merkleUserBalances(address(alice)), 1 ether);
        assertEq(stakingRewards.merkleUserBalances(address(this)), 1 ether);
        assertEq(stakingRewards.totalSupply(), 2 ether);
        assertEq(stakingRewards.balanceOf(address(registry.proxies(address(alice)))), 1 ether);
        assertEq(stakingRewards.balanceOf(address(userProxy)), 1 ether);
        assertEq(userProxy.owner(), address(alice));
        assertEq(registry.proxies(address(alice)).owner(), address(alice));

        alice.withdrawFromMine(address(stakingRewards), 0.5 ether);
    }
    function testFail_stake_both_transfer_ownership_stake() public {
        alice = new Staker(address(proxyActions));

        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);

        registry.build(address(this));
        registry.build(address(alice));

        alice.setProxy(registry.proxies(address(alice)));
        alice.approveToken(address(registry.proxies(address(alice))), address(stakingToken), uint(-1));
        stakingToken.transfer(address(alice), 1 ether);

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));
        alice.stakeInMine(address(stakingRewards), 0.5 ether, 1, merkleAmount, merkleProof);

        this.stakeInMine(address(stakingRewards), 1 ether, 1, merkleAmount, merkleProof);
        userProxy.setOwner(address(alice));
        alice.setProxy(userProxy);

        assertEq(stakingRewards.merkleUserBalances(address(alice)), 0.5 ether);
        assertEq(stakingRewards.merkleUserBalances(address(this)), 1 ether);
        assertEq(stakingRewards.totalSupply(), 1.5 ether);
        assertEq(stakingRewards.balanceOf(address(registry.proxies(address(alice)))), 0.5 ether);
        assertEq(stakingRewards.balanceOf(address(userProxy)), 1 ether);
        assertEq(userProxy.owner(), address(alice));
        assertEq(registry.proxies(address(alice)).owner(), address(alice));

        alice.stakeInMine(address(stakingRewards), 0.5 ether);
    }
    function test_stake_both_transfer_ownership_get_rewards() public {
        alice = new Staker(address(proxyActions));

        rewardToken.transfer(address(rewardsFactory), defaultReward);
        rewardsFactory.notifyRewardAmount(0);

        registry.build(address(this));
        registry.build(address(alice));

        alice.setProxy(registry.proxies(address(alice)));
        alice.approveToken(address(registry.proxies(address(alice))), address(stakingToken), uint(-1));
        stakingToken.transfer(address(alice), 1 ether);

        userProxy = registry.proxies(address(this));
        stakingToken.approve(address(userProxy), uint(-1));
        alice.stakeInMine(address(stakingRewards), 0.5 ether, 1, merkleAmount, merkleProof);

        this.stakeInMine(address(stakingRewards), 1 ether, 1, merkleAmount, merkleProof);
        userProxy.setOwner(address(alice));
        alice.setProxy(userProxy);

        assertEq(stakingRewards.merkleUserBalances(address(alice)), 0.5 ether);
        assertEq(stakingRewards.merkleUserBalances(address(this)), 1 ether);
        assertEq(stakingRewards.totalSupply(), 1.5 ether);
        assertEq(stakingRewards.balanceOf(address(registry.proxies(address(alice)))), 0.5 ether);
        assertEq(stakingRewards.balanceOf(address(userProxy)), 1 ether);
        assertEq(userProxy.owner(), address(alice));
        assertEq(registry.proxies(address(alice)).owner(), address(alice));

        hevm.warp(now + 10 seconds);
        uint rewardTokenBalance = rewardToken.balanceOf(address(alice));
        alice.getRewards(address(stakingRewards));
        assertTrue(rewardToken.balanceOf(address(alice)) > rewardTokenBalance);

        alice.setProxyOwner(address(this));
        rewardTokenBalance = rewardToken.balanceOf(address(this));
        this.getRewards(address(stakingRewards));
        assertEq(rewardToken.balanceOf(address(this)), rewardTokenBalance);
    }
}
