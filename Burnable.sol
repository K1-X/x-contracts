pragma solidity ^0.5.11;

contract Burnable {
    bool private _burnallow;
    address private _burner;
    address public pendingBurner;

    modifier whenBurn() {
        require(_burnallow, "burnable: can't burn");
        _;
    }

modifier onlyBurner() {
        require(msg.sender == _burner, "caller is not a burner");
        _;
    }
}
