pragma solidity 0.6.7;

abstract contract StakingContractLike {
    function stake(uint256, uint256, uint256, bytes32[] calldata) virtual external;
    function withdraw(uint256) virtual public;
}
abstract contract TokenLike {
    function approve(address, uint) virtual public returns (bool);
}

contract NonProxyOwnable {
    address             public owner;
    TokenLike           public stakingToken;
    StakingContractLike public staking;

    constructor(address staking_, address stakingToken_) public {
        owner         = msg.sender;
        stakingToken  = TokenLike(stakingToken_);
        staking       = StakingContractLike(staking_);

        stakingToken.approve(staking_, uint(-1));
    }

    function setOwner(address owner_) public {
        owner = owner_;
    }

    function stake(uint256 index, uint256 depositAmount, uint256 merkleAmount, bytes32[] calldata merkleProof) external {
        staking.stake(index, depositAmount, merkleAmount, merkleProof);
    }

    function withdraw(uint256 amount) external {
        staking.withdraw(amount);
    }
}
