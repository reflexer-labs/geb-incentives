pragma solidity ^0.6.7;

contract Auth {
    // --- Authorities ---
    mapping (address => uint) public authorities;
    function addAuthority(address account) external isAuthority { authorities[account] = 1; }
    function removeAuthority(address account) external isAuthority { authorities[account] = 0; }
    modifier isAuthority {
        require(authorities[msg.sender] == 1, "PIScaledPerSecondValidator/not-an-authority");
        _;
    }

    constructor () public {
        authorities[msg.sender] = 1;
    }
}