pragma solidity 0.6.7;

abstract contract MerkleGebIncentivesLike {
    function stakingToken() virtual public returns (address);
    function rewardsToken() virtual public returns (address);
    function stake(uint256, uint256, uint256, bytes32[] memory) virtual public;
    function withdraw(uint256) virtual public;
    function exit() virtual public;
    function balanceOf(address) virtual public view returns (uint256);
    function getReward() virtual public;
}
abstract contract DSTokenLike {
    function balanceOf(address) virtual public view returns (uint);
    function approve(address, uint) virtual public;
    function transfer(address, uint) virtual public;
    function transferFrom(address, address, uint) virtual public;
}

/// @title Merkle incentives proxy actions
/// @notice This contract is supposed to be used alongside a DSProxy contract.
/// @dev These functions are meant to be used as a a library for a DSProxy. Some are unsafe if you call them directly.
contract MockGebProxyIncentivesActions {
    // Internal functions

    /// @notice Stakes in Incentives Pool (geb-incentives)
    /// @param incentives address - Liquidity mining pool
    function _stakeInMine(address incentives, uint256 index, uint256 merkleAmount, bytes32[] calldata merkleProof) internal {
        DSTokenLike lpToken = DSTokenLike(MerkleGebIncentivesLike(incentives).stakingToken());
        lpToken.approve(incentives, uint(0 - 1));
        MerkleGebIncentivesLike(incentives).stake(index, lpToken.balanceOf(address(this)), merkleAmount, merkleProof);
    }

    // Public functions

    /// @notice Stakes in liquidity mining pool
    /// @param incentives address - pool address
    /// @param wad uint - amount
    function stakeInMine(address incentives, uint wad, uint256 index, uint256 merkleAmount, bytes32[] calldata merkleProof) external {
        DSTokenLike(MerkleGebIncentivesLike(incentives).stakingToken()).transferFrom(msg.sender, address(this), wad);
        _stakeInMine(incentives, index, merkleAmount, merkleProof);
    }

    /// @notice Harvests rewards available (both instant and staked)
    /// @param incentives address - Liquidity mining pool
    function getRewards(address incentives) public {
        MerkleGebIncentivesLike incentivesContract = MerkleGebIncentivesLike(incentives);
        DSTokenLike rewardToken = DSTokenLike(incentivesContract.rewardsToken());
        incentivesContract.getReward();
        rewardToken.transfer(msg.sender, rewardToken.balanceOf(address(this)));
    }

    /// @notice Exits liquidity mining pool (withdraw LP tokens and getRewards for current campaign)
    /// @param incentives address - Liquidity mining pool
    function exitMine(address incentives) external {
        MerkleGebIncentivesLike incentivesContract = MerkleGebIncentivesLike(incentives);
        DSTokenLike rewardToken = DSTokenLike(incentivesContract.rewardsToken());
        DSTokenLike lpToken = DSTokenLike(incentivesContract.stakingToken());
        incentivesContract.exit();
        rewardToken.transfer(msg.sender, rewardToken.balanceOf(address(this)));
        lpToken.transfer(msg.sender, lpToken.balanceOf(address(this)));
    }

    /// @notice Withdraw LP tokens from liquidity mining pool
    /// @param incentives address - Liquidity mining pool
    /// @param value uint - value to withdraw
    function withdrawFromMine(address incentives, uint value) external {
        MerkleGebIncentivesLike incentivesContract = MerkleGebIncentivesLike(incentives);
        DSTokenLike lpToken = DSTokenLike(incentivesContract.stakingToken());
        incentivesContract.withdraw(value);
        lpToken.transfer(msg.sender, lpToken.balanceOf(address(this)));
    }

    /// @notice Withdraw LP tokens from liquidity mining pool and harvests rewards
    /// @param incentives address - Liquidity mining pool
    /// @param value uint - value to withdraw
    function withdrawAndHarvest(address incentives, uint value) external {
        MerkleGebIncentivesLike incentivesContract = MerkleGebIncentivesLike(incentives);
        DSTokenLike rewardToken = DSTokenLike(incentivesContract.rewardsToken());
        DSTokenLike lpToken = DSTokenLike(incentivesContract.stakingToken());
        incentivesContract.withdraw(value);
        getRewards(incentives);
        lpToken.transfer(msg.sender, lpToken.balanceOf(address(this)));
    }
}
