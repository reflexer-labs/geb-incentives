pragma solidity 0.6.7;

import "../zeppelin/ERC20/SafeERC20.sol";

contract LPTokenWrapper is SafeERC20 {
    IERC20 public lpToken;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) virtual public {
        stake(amount, msg.sender);
    }

    function stake(uint256 amount, address owner) virtual public {
        _totalSupply = add(_totalSupply, amount);
        _balances[owner] = add(_balances[owner], amount);
        safeTransferFrom(lpToken, msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) virtual public {
        _totalSupply = sub(_totalSupply, amount);
        _balances[msg.sender] = sub(_balances[msg.sender], amount);
        safeTransfer(lpToken, msg.sender, amount);
    }
}
