pragma solidity 0.6.7;

import "ds-proxy/proxy.sol";
import "ds-token/token.sol";

contract ProxyCalls {
    DSProxy userProxy;
    address proxyActions;

    function stakeInMine(address, uint, uint, uint, bytes32[] memory) public {
        userProxy.execute(proxyActions, msg.data);
    }

    function stakeInMine(address, uint) public {
        userProxy.execute(proxyActions, msg.data);
    }

    function getRewards(address pool) public {
        userProxy.execute(proxyActions, abi.encodeWithSignature("getRewards(address)", pool));
    }

    function exitMine(address) public {
        userProxy.execute(proxyActions, msg.data);
    }

    function withdrawFromMine(address, uint) public {
        userProxy.execute(proxyActions, msg.data);
    }

    function withdrawAndHarvest(address, uint) public {
        userProxy.execute(proxyActions, msg.data);
    }
}

contract Staker is ProxyCalls {
    constructor(address proxyActions_) public {
        proxyActions = proxyActions_;
    }

    function setProxy(DSProxy proxy_) external {
        userProxy = proxy_;
    }

    function setProxyOwner(address newOwner) external {
        userProxy.setOwner(newOwner);
    }

    function approveToken(address target, address token, uint amount) external {
        DSToken(token).approve(target, amount);
    }
}
