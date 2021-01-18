pragma solidity 0.6.7;

import "../interfaces/Ownable.sol";
import "../interfaces/ProxyRegistry.sol";

import "../merkle/MerkleAuthorizer.sol";
import "./StakingRewards.sol";

contract MerkleProxyStakingRewards is MerkleAuthorizer, StakingRewards {
    /* ========== STATE VARIABLES ========== */

    ProxyRegistry               public registry;
    mapping(address => uint256) private _merkleUserBalances;

    constructor(
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        address _registry,
        uint256 rewardsDuration_,
        bytes32 merkleRoot_
    ) public MerkleAuthorizer(merkleRoot_) StakingRewards(_rewardsDistribution, _rewardsToken, _stakingToken, rewardsDuration_) {
        require(_registry != address(0), "MerkleProxyStakingRewards/null-registry");
        merkleAuth = 1;
        registry   = ProxyRegistry(_registry);
    }

    /* ========== VIEWS ========== */

    function merkleUserBalances(address user) public view returns (uint256) {
        return _merkleUserBalances[user];
    }

    function originalCaller(address caller) public view returns (address) {
        address owner;
        if (isContract(caller)) {
          owner = Ownable(caller).owner();
          require(registry.proxies(owner) == caller, "MerkleProxyStakingRewards/sender-not-owner-proxy");
        } else {
          owner = caller;
        }
        return owner;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 index, uint256 depositAmount, uint256 merkleAmount, bytes32[] calldata merkleProof)
      external nonReentrant updateReward(msg.sender) {
        require(merkleAuth == 1, "MerkleProxyStakingRewards/not-merkle-auth");
        address owner = originalCaller(msg.sender);
        require(isMerkleAuthorized(index, owner, merkleAmount, merkleProof), "MerkleProxyStakingRewards/invalid-proof");
        uint256 newMerkleAccountBalance = add(_merkleUserBalances[owner], depositAmount);
        require(newMerkleAccountBalance <= merkleAmount, "MerkleProxyStakingRewards/exceeds-merkle-cap");
        _merkleUserBalances[owner] = newMerkleAccountBalance;
        _stake(depositAmount);
    }

    function withdraw(uint256 amount) public override {
        require(merkleAuth == 1, "MerkleProxyStakingRewards/not-merkle-auth");
        address owner = originalCaller(msg.sender);
        _merkleUserBalances[owner] = sub(_merkleUserBalances[owner], amount);
        super.withdraw(amount);
    }
}
