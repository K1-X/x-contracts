pragma solidity ^0.5.11;

contract Whitelisted {
    
address private _whitelistadmin;
    address public pendingWhiteListAdmin;

    mapping (address => bool) private _whitelisted;
    
}
