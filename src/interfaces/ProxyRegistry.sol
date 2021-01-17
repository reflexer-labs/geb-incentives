pragma solidity 0.6.7;

abstract contract ProxyRegistry {
    function proxies(address) virtual public view returns (address);
}
