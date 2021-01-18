pragma solidity 0.6.7;

import "../../interfaces/Ownable.sol";
import "../../interfaces/ProxyRegistry.sol";

import "../../uniswap/StakingRewards.sol";

contract MockMerkleProxyStakingRewards is StakingRewards {
    /* ========== STATE VARIABLES ========== */

    bytes32 public immutable merkleRoot;

    ProxyRegistry               public registry;
    mapping(address => uint256) private _merkleUserBalances;

    constructor(
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        address _registry,
        uint256 rewardsDuration_,
        bytes32 merkleRoot_
    ) public StakingRewards(_rewardsDistribution, _rewardsToken, _stakingToken, rewardsDuration_) {
        require(_registry != address(0), "MockMerkleProxyStakingRewards/null-registry");
        merkleAuth = 1;
        merkleRoot = merkleRoot_;
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

    function toggleMerkleAuth() external {
        if (merkleAuth == 0) {
          merkleAuth = 1;
        } else {
          merkleAuth = 0;
        }
    }

    /*
    * @notice Assumes all proofs are valid in order to test the rest of the logic
    */
    function stake(uint256 index, uint256 depositAmount, uint256 merkleAmount, bytes32[] calldata merkleProof)
      external nonReentrant updateReward(msg.sender) {
        require(merkleAuth == 1, "MerkleProxyStakingRewards/not-merkle-auth");
        address owner = originalCaller(msg.sender);
        uint256 newMerkleAccountBalance = add(_merkleUserBalances[owner], depositAmount);
        require(newMerkleAccountBalance <= merkleAmount, "MerkleProxyStakingRewards/exceeds-merkle-cap");
        _merkleUserBalances[owner] = newMerkleAccountBalance;
        _stake(depositAmount);
    }

    function withdraw(uint256 amount) public override {
        require(merkleAuth == 1, "MockMerkleProxyStakingRewards/not-merkle-auth");
        address owner = originalCaller(msg.sender);
        _merkleUserBalances[owner] = sub(_merkleUserBalances[owner], amount);
        super.withdraw(amount);
    }
}
