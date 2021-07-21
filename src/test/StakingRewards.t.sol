pragma solidity 0.6.7;

import "ds-test/test.sol";
import "../uniswap/StakingRewards.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract DSDelegateToken is DSTokenBase(0), DSStop {
    // --- Variables ---
    // @notice The coin's symbol
    string public symbol;
    // @notice The coin's name
    string public name;
    /// @notice Standard token precision. Override to customize
    uint256 public decimals = 18;
    /// @notice A record of each accounts delegate
    mapping (address => address) public delegates;
    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;
    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;
    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

    // --- Structs ---
    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint256 fromBlock;
        uint256 votes;
    }

    // --- Constants ---
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    // --- Events ---
    /// @notice An event that's emitted when the contract mints tokens
    event Mint(address indexed guy, uint wad);
    /// @notice An event that's emitted when the contract burns tokens
    event Burn(address indexed guy, uint wad);
    /// @notice An event that's emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    /// @notice An event that's emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    constructor(string memory name_, string memory symbol_) public {
        name   = name_;
        symbol = symbol_;
    }

    // --- Functionality ---
    /**
     * @notice Approve an address to transfer all of your tokens
     * @param guy The address to give approval to
     */
    function approve(address guy) public stoppable returns (bool) {
        return super.approve(guy, uint(-1));
    }
    /**
     * @notice Approve an address to transfer part of your tokens
     * @param guy The address to give approval to
     * @param wad The amount of tokens to approve
     */
    function approve(address guy, uint wad) override public stoppable returns (bool) {
        return super.approve(guy, wad);
    }

    /**
     * @notice Transfer tokens from src to dst
     * @param src The address to transfer tokens from
     * @param dst The address to transfer tokens to
     * @param wad The amount of tokens to transfer
     */
    function transferFrom(address src, address dst, uint wad)
        override
        public
        stoppable
        returns (bool)
    {
        if (src != msg.sender && _approvals[src][msg.sender] != uint(-1)) {
            require(_approvals[src][msg.sender] >= wad, "ds-delegate-token-insufficient-approval");
            _approvals[src][msg.sender] = sub(_approvals[src][msg.sender], wad);
        }

        require(_balances[src] >= wad, "ds-delegate-token-insufficient-balance");
        _balances[src] = sub(_balances[src], wad);
        _balances[dst] = add(_balances[dst], wad);

        emit Transfer(src, dst, wad);

        _moveDelegates(delegates[src], delegates[dst], wad);

        return true;
    }
    /**
     * @notice Transfer tokens to dst
     * @param dst The address to transfer tokens to
     * @param wad The amount of tokens to transfer
     */
    function push(address dst, uint wad) public {
        transferFrom(msg.sender, dst, wad);
    }
    /**
     * @notice Transfer tokens from src to yourself
     * @param src The address to transfer tokens frpom
     * @param wad The amount of tokens to transfer
     */
    function pull(address src, uint wad) public {
        transferFrom(src, msg.sender, wad);
    }
    /**
     * @notice Transfer tokens between two addresses
     * @param src The address to transfer tokens from
     * @param dst The address to transfer tokens to
     * @param wad The amount of tokens to transfer
     */
    function move(address src, address dst, uint wad) public {
        transferFrom(src, dst, wad);
    }

    /**
     * @notice Mint tokens for yourself
     * @param wad The amount of tokens to mint
     */
    function mint(uint wad) public {
        mint(msg.sender, wad);
    }
    /**
     * @notice Burn your own tokens
     * @param wad The amount of tokens to burn
     */
    function burn(uint wad) public {
        burn(msg.sender, wad);
    }
    /**
     * @notice Mint tokens for guy
     * @param guy The address to mint tokens for
     * @param wad The amount of tokens to mint
     */
    function mint(address guy, uint wad) public auth stoppable {
        _balances[guy] = add(_balances[guy], wad);
        _supply = add(_supply, wad);
        emit Mint(guy, wad);

        _moveDelegates(delegates[address(0)], delegates[guy], wad);
    }
    /**
     * @notice Burn guy's tokens
     * @param guy The address to burn tokens from
     * @param wad The amount of tokens to burn
     */
    function burn(address guy, uint wad) public auth stoppable {
        if (guy != msg.sender && _approvals[guy][msg.sender] != uint(-1)) {
            require(_approvals[guy][msg.sender] >= wad, "ds-delegate-token-insufficient-approval");
            _approvals[guy][msg.sender] = sub(_approvals[guy][msg.sender], wad);
        }

        require(_balances[guy] >= wad, "ds-delegate-token-insufficient-balance");
        _balances[guy] = sub(_balances[guy], wad);
        _supply = sub(_supply, wad);
        emit Burn(guy, wad);

        _moveDelegates(delegates[guy], delegates[address(0)], wad);
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public {
        return _delegate(msg.sender, delegatee);
    }
    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(abi.encodePacked(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "ds-delegate-token-invalid-signature");
        require(nonce == nonces[signatory]++, "ds-delegate-token-invalid-nonce");
        require(now <= expiry, "ds-delegate-token-signature-expired");
        return _delegate(signatory, delegatee);
    }
    /**
     * @notice Internal function to delegate votes from `delegator` to `delegatee`
     * @param delegator The address that delegates its votes
     * @param delegatee The address to delegate votes to
     */
    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        delegates[delegator]    = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, balanceOf(delegator));
    }
    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum  = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = sub(srcRepOld, amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum  = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = add(dstRepOld, amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }
    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint256 oldVotes, uint256 newVotes) internal {
        uint blockNumber = block.number;

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "ds-delegate-token-not-yet-determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    /**
    * @notice Fetch the chain ID
    **/
    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}

contract DSMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }
    function max(uint x, uint y) internal pure returns (uint z) {
        return x >= y ? x : y;
    }
    function imin(int x, int y) internal pure returns (int z) {
        return x <= y ? x : y;
    }
    function imax(int x, int y) internal pure returns (int z) {
        return x >= y ? x : y;
    }

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;

    //rounds to zero if x*y < WAD / 2
    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }
    //rounds to zero if x*y < WAD / 2
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), RAY / 2) / RAY;
    }
    //rounds to zero if x*y < WAD / 2
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }
    //rounds to zero if x*y < RAY / 2
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, RAY), y / 2) / y;
    }

    // This famous algorithm is called "exponentiation by squaring"
    // and calculates x^n with x as fixed-point and n as regular unsigned.
    //
    // It's O(log n), instead of O(n) for naive repeated multiplication.
    //
    // These facts are why it works:
    //
    //  If n is even, then x^n = (x^2)^(n/2).
    //  If n is odd,  then x^n = x * x^(n-1),
    //   and applying the equation for even x gives
    //    x^n = x * (x^2)^((n-1) / 2).
    //
    //  Also, EVM division is flooring and
    //    floor[(n-1) / 2] = floor[n / 2].
    //
    function rpow(uint x, uint n) internal pure returns (uint z) {
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x);

            if (n % 2 != 0) {
                z = rmul(z, x);
            }
        }
    }
}

abstract contract ERC20Events {
    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);
}

abstract contract ERC20 is ERC20Events {
    function totalSupply() virtual public view returns (uint);
    function balanceOf(address guy) virtual public view returns (uint);
    function allowance(address src, address guy) virtual public view returns (uint);

    function approve(address guy, uint wad) virtual public returns (bool);
    function transfer(address dst, uint wad) virtual public returns (bool);
    function transferFrom(
        address src, address dst, uint wad
    ) virtual public returns (bool);
}


contract DSNote {
    event LogNote(
        bytes4   indexed  sig,
        address  indexed  guy,
        bytes32  indexed  foo,
        bytes32  indexed  bar,
        uint256           wad,
        bytes             fax
    ) anonymous;

    modifier note {
        bytes32 foo;
        bytes32 bar;
        uint256 wad;

        assembly {
            foo := calldataload(4)
            bar := calldataload(36)
            wad := callvalue()
        }

        _;

        emit LogNote(msg.sig, msg.sender, foo, bar, wad, msg.data);
    }
}

interface DSAuthority {
    function canCall(
        address src, address dst, bytes4 sig
    ) external view returns (bool);
}

abstract contract DSAuthEvents {
    event LogSetAuthority (address indexed authority);
    event LogSetOwner     (address indexed owner);
}

contract DSAuth is DSAuthEvents {
    DSAuthority  public  authority;
    address      public  owner;

    constructor() public {
        owner = msg.sender;
        emit LogSetOwner(msg.sender);
    }

    function setOwner(address owner_)
        virtual
        public
        auth
    {
        owner = owner_;
        emit LogSetOwner(owner);
    }

    function setAuthority(DSAuthority authority_)
        virtual
        public
        auth
    {
        authority = authority_;
        emit LogSetAuthority(address(authority));
    }

    modifier auth {
        require(isAuthorized(msg.sender, msg.sig), "ds-auth-unauthorized");
        _;
    }

    function isAuthorized(address src, bytes4 sig) virtual internal view returns (bool) {
        if (src == address(this)) {
            return true;
        } else if (src == owner) {
            return true;
        } else if (authority == DSAuthority(0)) {
            return false;
        } else {
            return authority.canCall(src, address(this), sig);
        }
    }
}

contract DSStop is DSNote, DSAuth {
    bool public stopped;

    modifier stoppable {
        require(!stopped, "ds-stop-is-stopped");
        _;
    }
    function stop() public auth note {
        stopped = true;
    }
    function start() public auth note {
        stopped = false;
    }

}

contract DSTokenBase is ERC20, DSMath {
    uint256                                            _supply;
    mapping (address => uint256)                       _balances;
    mapping (address => mapping (address => uint256))  _approvals;

    constructor(uint supply) public {
        _balances[msg.sender] = supply;
        _supply = supply;
    }

    function totalSupply() override public view returns (uint) {
        return _supply;
    }
    function balanceOf(address src) override public view returns (uint) {
        return _balances[src];
    }
    function allowance(address src, address guy) override public view returns (uint) {
        return _approvals[src][guy];
    }

    function transfer(address dst, uint wad) override public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        override
        virtual
        public
        returns (bool)
    {
        if (src != msg.sender) {
            require(_approvals[src][msg.sender] >= wad, "ds-token-insufficient-approval");
            _approvals[src][msg.sender] = sub(_approvals[src][msg.sender], wad);
        }

        require(_balances[src] >= wad, "ds-token-insufficient-balance");
        _balances[src] = sub(_balances[src], wad);
        _balances[dst] = add(_balances[dst], wad);

        emit Transfer(src, dst, wad);

        return true;
    }

    function approve(address guy, uint wad) virtual override public returns (bool) {
        _approvals[msg.sender][guy] = wad;

        emit Approval(msg.sender, guy, wad);

        return true;
    }
}

contract DSToken is DSTokenBase(0), DSStop {
    // @notice The coin's symbol
    string public symbol;
    // @notice The coin's name
    string public name;
    // @notice Standard token precision. override to customize
    uint256 public decimals = 18;

    constructor(string memory name_, string memory symbol_) public {
        name   = name_;
        symbol = symbol_;
    }

    event Mint(address indexed guy, uint wad);
    event Burn(address indexed guy, uint wad);

    function approve(address guy) public stoppable returns (bool) {
        return super.approve(guy, uint(-1));
    }

    function approve(address guy, uint wad) override public stoppable returns (bool) {
        return super.approve(guy, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        override
        public
        stoppable
        returns (bool)
    {
        if (src != msg.sender && _approvals[src][msg.sender] != uint(-1)) {
            require(_approvals[src][msg.sender] >= wad, "ds-token-insufficient-approval");
            _approvals[src][msg.sender] = sub(_approvals[src][msg.sender], wad);
        }

        require(_balances[src] >= wad, "ds-token-insufficient-balance");
        _balances[src] = sub(_balances[src], wad);
        _balances[dst] = add(_balances[dst], wad);

        emit Transfer(src, dst, wad);

        return true;
    }

    function push(address dst, uint wad) public {
        transferFrom(msg.sender, dst, wad);
    }
    function pull(address src, uint wad) public {
        transferFrom(src, msg.sender, wad);
    }
    function move(address src, address dst, uint wad) public {
        transferFrom(src, dst, wad);
    }

    function mint(uint wad) public {
        mint(msg.sender, wad);
    }
    function burn(uint wad) public {
        burn(msg.sender, wad);
    }
    function mint(address guy, uint wad) public auth stoppable {
        _balances[guy] = add(_balances[guy], wad);
        _supply = add(_supply, wad);
        emit Mint(guy, wad);
    }
    function burn(address guy, uint wad) public auth stoppable {
        if (guy != msg.sender && _approvals[guy][msg.sender] != uint(-1)) {
            require(_approvals[guy][msg.sender] >= wad, "ds-token-insufficient-approval");
            _approvals[guy][msg.sender] = sub(_approvals[guy][msg.sender], wad);
        }

        require(_balances[guy] >= wad, "ds-token-insufficient-balance");
        _balances[guy] = sub(_balances[guy], wad);
        _supply = sub(_supply, wad);
        emit Burn(guy, wad);
    }
}

contract Farmer {
    StakingRewards pool;
    DSToken stakingToken;

    constructor(StakingRewards _pool, DSToken token) public {
        pool = _pool;
        stakingToken = token;
    }

    function doStake(uint amount) public {
        stakingToken.approve(address(pool), amount);
        pool.stake(amount);
    }

    function doWithdraw(uint amount) public {
        pool.withdraw(amount);
    }

    function doGetReward() public {
        pool.getReward();
    }

    function doExit() public {
        pool.exit();
    }
}

contract StakingRewardsTest is DSTest {
    Hevm hevm;

    DSDelegateToken rewardToken;
    DSToken stakingToken;
    StakingRewards pool;
    Farmer[] farmers;

    uint256 initAmountToMint = 1000 ether;
    uint256 defaultDuration  = 12 hours;
    uint256 defaultReward    = 10 ether;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        rewardToken = new DSDelegateToken("GOV", "GOV");
        stakingToken = new DSToken("STAKE", "STAKE");

        pool = new StakingRewards(
            address(this), // rewardsDistribution
            address(rewardToken),
            address(stakingToken),
            defaultDuration
        );

        for (uint i = 0; i < 3; i++) {
            farmers.push(new Farmer(pool, stakingToken));
            stakingToken.mint(address(farmers[i]), initAmountToMint);
        }

        rewardToken.mint(address(pool), initAmountToMint);
    }

    function test_setup() public {
        assertEq(address(pool.rewardsDistribution()), address(this));
        assertEq(address(pool.rewardsToken()), address(rewardToken));
        assertEq(address(pool.stakingToken()), address(stakingToken));
        assertEq(pool.rewardsDuration(), defaultDuration);
    }
    function test_deploy_campaign_check_setup_before_notify() public {
        assertEq(pool.periodFinish(), 0);
        assertEq(pool.rewardRate(), 0);
        assertEq(pool.lastUpdateTime(), 0);
        assertEq(pool.rewardPerTokenStored(), 0);
    }
    function test_deploy_campaign_check_setup_after_one_notify() public {
        pool.notifyRewardAmount(defaultReward);

        assertEq(pool.periodFinish(), now + defaultDuration);
        assertEq(pool.rewardRate(), defaultReward / defaultDuration);
        assertEq(pool.lastUpdateTime(), now);
        assertEq(pool.rewardPerTokenStored(), 0);
    }
    function test_deploy_campaign_check_setup_after_multi_notify() public {
        pool.notifyRewardAmount(defaultReward);
        uint previousRewardRate = pool.rewardRate();
        uint previousPeriodFinish = pool.periodFinish();

        hevm.warp(now + (defaultDuration / 2)); // mid distribution
        pool.notifyRewardAmount(defaultReward);

        assertEq(pool.periodFinish(), now + defaultDuration);
        assertEq(pool.lastUpdateTime(), now);
        assertEq(pool.rewardPerTokenStored(), 0);

        uint256 leftover = (previousPeriodFinish - block.timestamp) * previousRewardRate;
        assertEq(pool.rewardRate(), (defaultReward  + leftover) / defaultDuration);
    }
    function test_stake_unstake_before_any_rewards() public {
        Farmer farmer = farmers[0];
        farmer.doStake(1 ether);

        assertEq(pool.totalSupply(), 1 ether);
        assertEq(pool.balanceOf(address(farmer)), 1 ether);

        hevm.warp(now + 5 hours);
        farmer.doWithdraw(1 ether);

        assertEq(pool.totalSupply(), 0);
        assertEq(pool.balanceOf(address(farmer)), 0);
    }
    function test_unstake_after_campaign_expiry() public {
        Farmer farmer = farmers[0];
        farmer.doStake(1 ether);

        pool.notifyRewardAmount(defaultReward);

        hevm.warp(now + defaultDuration + 1); // after expiry
        farmer.doWithdraw(1 ether);

        assertEq(pool.totalSupply(), 0);
        assertEq(pool.balanceOf(address(farmer)), 0);
    }
    function test_stake_claim_once() public {
        Farmer farmer = farmers[0];
        farmer.doStake(1 ether);

        pool.notifyRewardAmount(defaultReward);

        hevm.warp(now + (defaultDuration / 2)); // mid campaign
        farmer.doGetReward();
        assertTrue(rewardToken.balanceOf(address(farmer)) > 4.9999999 ether);
    }
    function test_stake_claim_multi() public {
        Farmer farmer = farmers[0];
        farmer.doStake(1 ether);

        pool.notifyRewardAmount(defaultReward);

        hevm.warp(now + (defaultDuration / 2)); // mid campaign
        farmer.doGetReward();
        assertTrue(rewardToken.balanceOf(address(farmer)) > 4.9999999 ether);

        hevm.warp(pool.periodFinish() + 1); // after expiry
        farmer.doGetReward();
        assertTrue(rewardToken.balanceOf(address(farmer)) > 9.9999999 ether);
    }
    function test_stake_claim_after_campaign_expiry() public {

    }
    function test_multi_user_stake_claim() public {
        //
        // 1x: +----------------+ = 5eth for 5h + 1eth for 5h
        // 4x:         +--------+ = 0eth for 5h + 4eth for 5h
        //

        pool.notifyRewardAmount(defaultReward);
        farmers[0].doStake(1 ether);

        hevm.warp(now + (defaultDuration / 2)); // mid campaign
        farmers[1].doStake(4 ether);

        hevm.warp(pool.periodFinish() + 1); // after expiry
        farmers[0].doGetReward();
        farmers[1].doGetReward();
        assertTrue(rewardToken.balanceOf(address(farmers[0])) > 5.9999999 ether);
        assertTrue(rewardToken.balanceOf(address(farmers[1])) > 3.9999999 ether);


    }
    function test_multi_user_stake_claim_unstake() public {
        //
        // 2x: +----------------+--------+ = 4eth for 4h + 2eth for 4h + 2.85eth for 4h
        // 3x: +----------------+          = 6eth for 4h + 3eth for 4h +    0eth for 4h
        // 5x:         +-----------------+ = 0eth for 4h + 5eth for 4h + 7.14eth for 4h
        //

        pool.notifyRewardAmount(30 ether);
        farmers[0].doStake(2 ether);
        farmers[1].doStake(3 ether);

        hevm.warp(now + 4 hours);
        farmers[2].doStake(5 ether);

        hevm.warp(now + 4 hours);
        farmers[1].doExit();

        hevm.warp(pool.periodFinish() + 1);
        farmers[0].doExit();
        farmers[2].doExit();
        assertTrue(rewardToken.balanceOf(address(farmers[0])) > 8.8499999 ether);
        assertTrue(rewardToken.balanceOf(address(farmers[1])) > 8.9999999 ether);
        assertTrue(rewardToken.balanceOf(address(farmers[2])) > 12.139999 ether);
    }
    function test_stake_post_campaign_end_before_any_claim() public {
        Farmer farmer = farmers[0];
        pool.notifyRewardAmount(defaultReward);

        hevm.warp(pool.periodFinish() + 1);

        farmer.doStake(1 ether);
        hevm.warp(now + 4 weeks);
        farmer.doGetReward();

        assertEq(rewardToken.balanceOf(address(farmer)), 0);
    }
    function test_stake_notify_twice_unstake_claim() public {
        Farmer farmer = farmers[0];
        farmer.doStake(1 ether);
        pool.notifyRewardAmount(defaultReward);

        hevm.warp(pool.periodFinish() + (defaultDuration / 2)); // mid campaign
        pool.notifyRewardAmount(defaultReward);

        hevm.warp(pool.periodFinish() + 1);
        farmer.doExit(); // unstake all + claim

        assertTrue(rewardToken.balanceOf(address(farmer)) > 19.999999 ether);
        assertEq(pool.balanceOf(address(farmer)), 0);

    }
}
