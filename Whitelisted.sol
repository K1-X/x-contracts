pragma solidity ^0.5.11;

contract Whitelisted {
    
address private _whitelistadmin;
    address public pendingWhiteListAdmin;

    mapping (address => bool) private _whitelisted;

   modifier onlyWhitelistAdmin() {
        require(msg.sender == _whitelistadmin, "caller is not admin of whitelist");
        _;
    }    

    modifier onlyPendingWhitelistAdmin() {
        require(msg.sender == pendingWhiteListAdmin);
        _;
    }

    event WhitelistAdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    constructor () internal {
        _whitelistadmin = msg.sender;
        _whitelisted[msg.sender] = true;
    }

    function whitelistadmin() public view returns (address){
        return _whitelistadmin;
    }
}
