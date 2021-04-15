pragma solidity ^0.5.11;

contract Pausable {
    bool private _paused;
    address private _pauser;
    address public pendingPauser;

    modifier onlyPauser() {
        require(msg.sender == _pauser, "caller is not a pauser");
        _;
    }

    modifier onlyPendingPauser() {
        require(msg.sender == pendingPauser);
        _;
    }

    event PauserTransferred(address indexed previousPauser, address indexed newPauser);


    constructor () internal {
        _paused = false;
        _pauser = msg.sender;
    }
}
