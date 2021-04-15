pragma solidity ^0.5.11;

contract Burnable {
    bool private _burnallow;
    address private _burner;
    address public pendingBurner;

    modifier whenBurn() {
        require(_burnallow, "burnable: can't burn");
        _;
    }

}
