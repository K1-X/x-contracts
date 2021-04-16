pragma solidity ^0.5.11;

contract Meltable {
  
   mapping (address => bool) private _melters;
    address private _melteradmin;
    address public pendingMelterAdmin;    
}
