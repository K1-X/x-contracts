pragma solidity ^0.5.11;

contract Meltable {
  
   mapping (address => bool) private _melters;
    address private _melteradmin;

    address public pendingMelterAdmin;    
   
    modifier onlyMelterAdmin() {
        require (msg.sender == _melteradmin, "caller not a melter admin");
        _;
    }

    modifier onlyMelter() {
        require (_melters[msg.sender] == true, "can't perform melt");
        _;
    }
   
   modifier onlyPendingMelterAdmin() {
        require(msg.sender == pendingMelterAdmin);
        _;
    }

    event MelterTransferred(address indexed previousMelter, address indexed newMelter);
}




