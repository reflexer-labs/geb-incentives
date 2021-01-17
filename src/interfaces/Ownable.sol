pragma solidity 0.6.7;

abstract contract Ownable {
    function owner() virtual public view returns (address);
}
