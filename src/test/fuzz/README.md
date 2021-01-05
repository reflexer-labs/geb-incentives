# Security Tests

The contracts in this folder are the fuzz and symbolic execution scripts for the rolling distribution incentives contract.

## Fuzz

To run the fuzzer, set up Echidna (https://github.com/crytic/echidna) on your machine.

Then run
```
echidna-test src/test/fuzz/RollingDistributionIncentivesFuzz.sol --contract <Name of contract> --config echidna.yaml
```

Configs are in the root of this repo (echidna.yaml). You can set the number of and depth of runs,

The contracts in this folder are modified versions of the originals in the _src_ folder. They have assertions added to test for invariants, visibility of functions modified. Running the Fuzz against modified versions without the assertions is still possible, general properties on the Fuzz contract can be executed against unmodified contracts.

Tests should only run one at a time because they interfere with each other.

### General fuzz

Goal: Check for unexpected failures. Use contract GeneralFuzz.sol, with checkAsserts == true in echidna config.

Results:
Analyzing contract: /Users/fabio/Documents/reflexer/geb-incentives/src/test/fuzz/RollingDistributionIncentivesFuzz.sol:GeneralFuzz
assertion in campaigns: passed! 🎉
assertion in totalSupply: passed! 🎉
assertion in getReward: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in withdraw: passed! 🎉
assertion in withdrawExtraRewardTokens: passed! 🎉
assertion in MILLION: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in globalReward: passed! 🎉
assertion in earned: passed! 🎉
assertion in contractEnabled: passed! 🎉
assertion in cancelCampaign: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in delayedRewards: passed! 🎉
assertion in lpToken: passed! 🎉
assertion in WAD: passed! 🎉
assertion in userRewardPerTokenPaid: passed! 🎉
assertion in balanceOf: passed! 🎉
assertion in campaignCount: passed! 🎉
assertion in stake: passed! 🎉
assertion in THOUSAND: passed! 🎉
assertion in rewardPerToken: passed! 🎉
assertion in currentCampaign: passed! 🎉
assertion in disableContract: passed! 🎉
assertion in lastCampaign: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in canStake: passed! 🎉
assertion in stake: passed! 🎉
assertion in rewards: passed! 🎉
assertion in maxCampaigns: passed! 🎉
assertion in firstCampaign: passed! 🎉
assertion in finish: passed! 🎉
assertion in newCampaign: passed! 🎉
assertion in getLockedReward: passed! 🎉
assertion in campaignListLength: passed! 🎉
assertion in DEFAULT_MAX_CAMPAIGNS: passed! 🎉
assertion in exit: passed! 🎉
assertion in lastTimeRewardApplicable: passed! 🎉
assertion in rewardToken: passed! 🎉
assertion in HUNDRED: passed! 🎉
assertion in modifyParameters: passed! 🎉

Unique instructions: 3681
Unique codehashes: 1
Seed: -2636884132160192479

### Execution fuzz 

This script will setup x campaigns, and run through them fuzzing user interaction (withdraws, deposits and getting rewards)

Set user and campaign amount to taste, this test is best run with a high seqLen (sequences of transactions). It will test for the totalSupply of incentives ownership, and also the boundaries for reward granting. It also asserts if a withdrawal (for available balance) suceeds.

1. 10 users, 3 campaigns. Tested with a high seqLen of 500 (number of interactions per run).
Analyzing contract: /Users/fabio/Documents/reflexer/geb-incentives/src/test/fuzz/RollingDistributionIncentivesFuzz.sol:ExecutionFuzz
echidna_test_pool_totalSupply: passed! 🎉
echidna_test_rewards: passed! 🎉
assertion in withdraw: passed! 🎉
assertion in stake: passed! 🎉
assertion in getRewards: passed! 🎉

2. 1 user, 12 campaigns. seqLen set to 5 to ensure trials span long periods of inactivity.


## Symbolic execution
The scripts are in SymbolicExecution.sol. 

Run ```dapp test --fuzz-runs <number> prove_stake``` to run tests for staking.

- prove_stake
- prove_withdraw
- prove_getRewards *** failing for over 84 campaigns with revert("invalid-campaign"), run with more than default runs to arrive at the error.

All remaining tests with the exception of the mentioned above pass with a high number of runs.

