pragma solidity 0.6.7;

import "../zeppelin/math/Math.sol";
import "../zeppelin/ERC20/ERC20Detailed.sol";
import "../zeppelin/ERC20/SafeERC20.sol";
import "../zeppelin/utils/ReentrancyGuard.sol";

import "./RewardsDistributionRecipient.sol";

contract StakingRewards is SafeERC20, Math, RewardsDistributionRecipient, ReentrancyGuard {
    /* ========== STATE VARIABLES ========== */

    IERC20  public rewardsToken;
    IERC20  public stakingToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate   = 0;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256                     private _totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        uint256 rewardsDuration_
    ) public {
        require(rewardsDuration_ > 0, "StakingRewards/null-rewards-duration");
        rewardsToken        = IERC20(_rewardsToken);
        stakingToken        = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;
        rewardsDuration     = rewardsDuration_;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
          add(
            rewardPerTokenStored,
            div(mul(mul(sub(lastTimeRewardApplicable(), lastUpdateTime), rewardRate), 1e18), _totalSupply)
          );
    }

    function earned(address account) public view returns (uint256) {
        return add(div(mul(_balances[account], sub(rewardPerToken(), userRewardPerTokenPaid[account])), 1e18), rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return mul(rewardRate, rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stakeWithPermit(uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "StakingRewards/cannot-stake-0");
        _totalSupply = add(_totalSupply, amount);
        _balances[msg.sender] = add(_balances[msg.sender], amount);

        // permit
        IUniswapV2ERC20(address(stakingToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);

        safeTransferFrom(stakingToken, msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(merkleAuth == 0, "StakingRewards/is-merkle-auth");
        _stake(amount);
    }

    function _stake(uint256 amount) internal {
        require(amount > 0, "StakingRewards/cannot-stake-0");
        _totalSupply = add(_totalSupply, amount);
        _balances[msg.sender] = add(_balances[msg.sender], amount);
        safeTransferFrom(stakingToken, msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "StakingRewards/cannot-withdraw-0");
        _totalSupply = sub(_totalSupply, amount);
        _balances[msg.sender] = sub(_balances[msg.sender], amount);
        safeTransfer(stakingToken, msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            safeTransfer(rewardsToken, msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) override external onlyRewardsDistribution updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = div(reward, rewardsDuration);
        } else {
            uint256 remaining = sub(periodFinish, block.timestamp);
            uint256 leftover = mul(remaining, rewardRate);
            rewardRate = div(add(reward, leftover), rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardsToken.balanceOf(address(this));
        require(rewardRate <= div(balance, rewardsDuration), "StakingRewards/provided-reward-too-high");

        lastUpdateTime = block.timestamp;
        periodFinish = add(block.timestamp, rewardsDuration);
        emit RewardAdded(reward);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}

interface IUniswapV2ERC20 {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}
