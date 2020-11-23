pragma solidity 0.6.7;

contract Auth {
    // --- Authorities ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "Auth/not-an-authority");
        _;
    }

    constructor () public {
        authorizedAccounts[msg.sender] = 1;
    }
}
