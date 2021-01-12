pragma solidity 0.6.7;

abstract contract RewardsDistributionRecipient {
    address public rewardsDistribution;

    function notifyRewardAmount(uint256 reward) virtual external;

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "RewardsDistributionRecipient/caller-is-not-rewards-distribution");
        _;
    }
}
