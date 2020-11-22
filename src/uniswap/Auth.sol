pragma solidity 0.6.7;

contract Auth {
    // --- Authorities ---
    mapping (address => uint) public authorities;
    function addAuthority(address account) external isAuthorized { authorities[account] = 1; }
    function removeAuthority(address account) external isAuthorized { authorities[account] = 0; }
    modifier isAuthorized {
        require(authorities[msg.sender] == 1, "Auth/not-an-authority");
        _;
    }

    constructor () public {
        authorities[msg.sender] = 1;
    }
}
