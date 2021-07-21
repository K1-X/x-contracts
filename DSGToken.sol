pragma solidity ^0.5.11;

import './AccountFrozenBalances.sol';
import './Ownable.sol';
import './Whitelisted.sol';
import './Burnable.sol';
import './Pausable.sol';
import './Mintable.sol';
import './Meltable.sol';
import "./Rules.sol";
import "./TokenRecipient.sol";
import "./IERC20Token.sol";

contract DSGToken is AccountFrozenBalances, Ownable, Whitelisted, Burnable, Pausable, Mintable, Meltable {
    using SafeMath for uint256;
    using Rules for Rules.Rule;

    uint256 constant public maxCallFrequency = 100;

    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupplyLimit;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    uint256 private _totalSupply;

    enum RoleType { Invalid, FUNDER, TEAM, ADVISORS, PARTNERSHIP, COMMUNITY, SEED, PRIVATE, AIRDROP}

    struct FreezeData {
        bool initialzed;
        uint256 frozenAmount;       // fronzen amount
        uint256 startBlock;         // freeze block for start.
        uint256 lastFreezeBlock;
    }

    mapping (address => RoleType) private _roles;
    mapping (uint256 => Rules.Rule) private _rules;
    mapping (address => FreezeData) private _freeze_datas;
    uint256 public monthIntervalBlock = 2;    // 172800
    uint256 public yearIntervalBlock = 10;    // 2102400
    uint256 public sixMonthIntervalBlock = 6; // six month block: 1036800

    bool public seedPause = true;
    uint256 public seedMeltStartBlock = 0;       

    bool public ruleReady;

    // upgrade part
    uint256 private _totalUpgraded;    

    modifier onlyReady(){
        require(ruleReady, "ruleReady is false");
        _;
    }            

    modifier canClaim() {
        require(uint256(_roles[msg.sender]) != uint256(RoleType.Invalid), "Invalid user role");
        require(_freeze_datas[msg.sender].initialzed);
        if(_roles[msg.sender] == RoleType.SEED){
            require(!seedPause, "Seed is not time to unlock yet");
        }
        _;
    }

    modifier canTransfer() {
        if(paused()){
            require (isWhitelisted(msg.sender) == true, "can't perform an action");
        }
        _;
    }

    modifier canMint(uint256 _amount) {
        require((_totalSupply + _amount) <= totalSupplyLimit, "Mint: Exceed the maximum circulation");
        _;
    }

    modifier roleCanMint(uint256 _role, uint256 _amount) {
        // for airdrop, use community amount.
        if(_role == uint256(RoleType.AIRDROP)) {
            _role = uint256(RoleType.COMMUNITY);
        }
        require(_amount <= _rules[_role].remainAmount, "RoleMint: Exceed the maximum circulation");
        _;
        _rules[_role].remainAmount = _rules[_role].remainAmount.sub(_amount);
    }

    modifier canBatchMint(uint256[] memory _amounts) {
        uint256 mintAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            mintAmount = mintAmount.add(_amounts[i]);
        }
        require(mintAmount <= totalSupplyLimit, "BatchMint: Exceed the maximum circulation");
        _;
    }

    modifier roleCanBatchMint(uint256 _role, uint256[] memory _amounts) {
        if(_role == uint256(RoleType.AIRDROP)) {
            _role = uint256(RoleType.COMMUNITY);
        }
        uint256 mintAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            mintAmount = mintAmount.add(_amounts[i]);
        }
        require(mintAmount <= _rules[_role].remainAmount, "RoleBatchMint: Exceed the maximum circulation");
        _;
        _rules[_role].remainAmount = _rules[_role].remainAmount.sub(mintAmount);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    event Freeze(address indexed from, uint256 amount);
    event Melt(address indexed from, uint256 amount);
    event MintFrozen(address indexed to, uint256 amount);
    event Claim(address indexed from, uint256 amount);

    event Withdrawal(address indexed src, uint wad);

    // 
    event Upgrade(address indexed from, uint256 _value);

    constructor (string memory _name, string memory _symbol) public {
        name = _name;
        symbol = _symbol;
        decimals = 18;
        totalSupplyLimit = 1024 * 1024 * 1024 * 10 ** uint256(decimals);
        //mint(msg.sender, 0);
        //ruleReady = false;
        //_readyRule();
    }

    function readyRule() onlyMinter public {
    //function _readyRule() internal {
        ruleReady = true;
        // Set a maximum amount for each role.
        // Unlocked annually or monthly, the proportion of unlocked monthly or yearly.
        _rules[uint256(RoleType.FUNDER)].setRule(yearIntervalBlock, 10, 7546257537 * 10 ** (uint256(decimals)-2));   // 107803679.1 * 70%
        _rules[uint256(RoleType.TEAM)].setRule(monthIntervalBlock, 2, 560858304356 * 10 ** (uint256(decimals)-4));      // 57230439.22 * 98%
        _rules[uint256(RoleType.ADVISORS)].setRule(monthIntervalBlock, 2, 13153337344 * 10 ** (uint256(decimals)-3)); // 13421772.8 * 98%
        _rules[uint256(RoleType.PARTNERSHIP)].setRule(monthIntervalBlock, 20, 4563402752 * 10 ** (uint256(decimals)-2)); // 45634027.52 (sixmonth behind start release) 
        _rules[uint256(RoleType.COMMUNITY)].setRule(monthIntervalBlock, 20, 3489660928*10**(uint256(decimals)-2)); // 34896609.28 (sixmonth behind start release) 
        _rules[uint256(RoleType.SEED)].setRule(monthIntervalBlock, 10, 3575560274*10** (uint256(decimals)-2));   // 35755602.74
        _rules[uint256(RoleType.PRIVATE)].setRule(monthIntervalBlock, 10, 536870912*10**(uint256(decimals)-1)); // 53687091.2

        // for free token and set rules.
        _rules[uint256(RoleType.AIRDROP)].setRule(yearIntervalBlock, 2, 0);
    }

    function roleType(address account) public view returns (uint256) {
        return uint256(_roles[account]);
    }

    function startBlock(address account) public view returns (uint256) {
        return _freeze_datas[account].startBlock;
    }

    function lastestFreezeBlock(address account) public view returns (uint256) {
        return _freeze_datas[account].lastFreezeBlock;
    }

    function queryFreezeAmount(address account) public view returns(uint256) {
        uint256 lastFreezeBlock = _freeze_datas[account].lastFreezeBlock;
        if(uint256(_roles[account]) == uint256(RoleType.SEED) || uint256(_roles[account]) == uint256(RoleType.PRIVATE)) {
            if(seedPause){
                return 0;
            }
            require(!seedPause, "seed pause is true, can't to claim");
            if(seedMeltStartBlock != 0 && seedMeltStartBlock > lastFreezeBlock) {
                lastFreezeBlock = seedMeltStartBlock;
            }
        }
        uint256 amount = _rules[uint256(_roles[account])].freezeAmount(_freeze_datas[account].frozenAmount , _freeze_datas[account].startBlock, lastFreezeBlock, block.number);
        uint256 balance = _frozen_balanceOf(account);
        if(amount > balance) {
            amount = balance;
        }
        return amount;
    }

    function totalSupply() public view returns (uint256) {
        return totalSupplyLimit;
    }

    function currentTotalSupply() public view returns(uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account].add(_frozen_balanceOf(account));
    }

    function roleRemainAmount(uint256 _role) public view returns(uint256) {
        return _rules[_role].remainAmount;
    }

    function frozenBalanceOf(address account) public view returns (uint256) {
        return _frozen_balanceOf(account);
    }

    function transfer(address recipient, uint256 amount) public canTransfer returns (bool) {
        require(recipient != address(this), "can't transfer tokens to the contract address");

        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferBatch(address[] memory recipients, uint256[] memory amounts) public canTransfer returns (bool) {
        require(recipients.length > 0, "transferBatch: recipient should be to at least one address");
        require(recipients.length == amounts.length, "transferBatch: recipients and amounts must be equal");
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
        return true;
    }

    function allowance(address _owner, address spender) public view returns (uint256) {
        return _allowances[_owner][spender];
    }

    function approve(address spender, uint256 value) public returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /* Approve and then communicate the approved contract in a single tx */
    function approveAndCall(address _spender, uint256 _value, bytes memory _extraData) public returns (bool) {
        TokenRecipient spender = TokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, address(this), _extraData);
            return true;
        } else {
            return false;
        }
    }

    function transferFrom(address sender, address recipient, uint256 amount) public canTransfer returns (bool) {
        require(recipient != address(this), "can't transfer tokens to the contract address");

        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue));
        return true;
    }

    function mint(address account, uint256 amount) public onlyMinter canMint(amount) returns (bool) {
        _mint(account, amount);
        return true;
    }

    function burn(uint256 amount) public whenBurn {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public whenBurn {
        _burnFrom(account, amount);
    }

    function mintBatchToken(address[] calldata accounts, uint256[] calldata amounts) external onlyMinter canBatchMint(amounts) returns (bool) {
        require(accounts.length > 0, "mintBatchToken: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchToken: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mint(accounts[i], amounts[i]);
        }

        return true;
    }

    function mintFrozenTokens(address account, uint256 amount) public onlyMinter canMint(amount) returns (bool) {
        _mintfrozen(account, amount);
        return true;
    }

    function mintBatchFrozenTokens(address[] calldata accounts, uint256[] calldata amounts) external onlyMinter canBatchMint(amounts) returns (bool) {
        require(accounts.length > 0, "mintBatchFrozenTokens: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchFrozenTokens: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintfrozen(accounts[i], amounts[i]);
        }

        return true;
    }

    function mintFrozenTokensForFunder(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) roleCanMint(uint256(RoleType.FUNDER), amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Funder: specified account already initialzed");
        _roles[account] = RoleType.FUNDER;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForTeam(address account, uint256 amount) public onlyMinter  onlyReady canMint(amount) roleCanMint(uint256(RoleType.TEAM), amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Team: specified account already initialzed");
        _roles[account] = RoleType.TEAM;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForAdvisors(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) roleCanMint(uint256(RoleType.ADVISORS), amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Advisors: specified account already initialzed");
        _roles[account] = RoleType.ADVISORS;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    ///@notice release starts after six months.
    function mintFrozenTokensForPartnership(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) roleCanMint(uint256(RoleType.PARTNERSHIP), amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Partnership: specified account already initialzed");
        _roles[account] = RoleType.PARTNERSHIP;
        // release starts after six months.
        uint256 startBn = block.number + sixMonthIntervalBlock;
        _freeze_datas[account] = FreezeData(true, amount, startBn , startBn);
        _mintfrozen(account, amount);
        return true;
    }

    ///@notice release starts after six months.
    function mintFrozenTokensForCommunity(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) roleCanMint(uint256(RoleType.COMMUNITY), amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Community: specified account already initialzed");
        _roles[account] = RoleType.COMMUNITY;
        uint256 startBn = block.number + sixMonthIntervalBlock;
        _freeze_datas[account] = FreezeData(true, amount, startBn, startBn);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForSeed(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) roleCanMint(uint256(RoleType.SEED), amount) returns (bool) {
        _mintFrozenTokensForSeed(account, amount);
        return true;
    }

    function mintBatchFrozenTokensForSeed(address[] memory accounts, uint256[] memory amounts) public onlyMinter onlyReady canBatchMint(amounts)  roleCanBatchMint(uint256(RoleType.SEED), amounts) returns (bool) {
        require(accounts.length > 0, "mintBatchFrozenTokensForSeed: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchFrozenTokensForSeed: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintFrozenTokensForSeed(accounts[i], amounts[i]);
        }
        return true;
    }

    function mintBatchFrozenTokensForPrivate(address[] memory accounts, uint256[] memory amounts) public onlyMinter onlyReady canBatchMint(amounts)  roleCanBatchMint(uint256(RoleType.PRIVATE), amounts) returns (bool) {
        require(accounts.length > 0, "mintBatchFrozenTokensForPrivate: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchFrozenTokensForPrivate: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintFrozenTokensForPrivate(accounts[i], amounts[i]);
        }
        return true;
    }

    function mintBatchFrozenTokensForAirdrop(address[] memory accounts, uint256[] memory amounts) public onlyMinter onlyReady canBatchMint(amounts) roleCanBatchMint(uint256(RoleType.AIRDROP), amounts) returns (bool) {
        require(accounts.length > 0, "mintBatchFrozenTokensForAirdrop: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchFrozenTokensForAirdrop: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintFrozenTokensForAirdrop(accounts[i], amounts[i]);
        }
        return true;
    }

    // @dev burn erc20 token and exchange mainnet token.
    function upgrade(uint256 amount) public {
        require(amount != 0, "DSGT: upgradable amount should be more than 0");
        address holder = msg.sender;

        // Burn tokens to be upgraded
        _burn(holder, amount);

        // Remember how many tokens we have upgraded
        _totalUpgraded = _totalUpgraded.add(amount);

        // Upgrade agent upgrades/reissues tokens
        emit Upgrade(holder, amount);
    }

    function totalUpgraded() public view returns (uint256) {
        return _totalUpgraded;
    }

    function withdraw(address _token, address payable _recipient) public onlyOwner {
        if (_token == address(0x0)) {
            require(_recipient != address(0x0));
            // transfer eth
            _recipient.transfer(address(this).balance);
            emit Withdrawal(_recipient, address(this).balance);
            return;
        }

        IERC20Token token = IERC20Token(_token);
        uint balance = token.balanceOf(address(this));
        // transfer token
        token.transfer(_recipient, balance);
        emit Withdrawal(_recipient, balance);
    }

    function isContract(address _addr) view internal returns (bool) {
        if (_addr == address(0x0)) return false;
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function getBlockNumber() internal view returns (uint256) {
        return block.number;
    }

    function claimTokens() public canClaim returns (bool) {
        //Rules.Rule storage rule = _rules[uint256(_roles[msg.sender])];
        uint256 lastFreezeBlock = _freeze_datas[msg.sender].lastFreezeBlock;
        if(uint256(_roles[msg.sender]) == uint256(RoleType.SEED) || uint256(_roles[msg.sender]) == uint256(RoleType.PRIVATE) ) {
            require(!seedPause, "seed pause is true, can't to claim");
            if(seedMeltStartBlock != 0 && seedMeltStartBlock > lastFreezeBlock) {
                lastFreezeBlock = seedMeltStartBlock;
            }
        }
        uint256 amount = _rules[uint256(_roles[msg.sender])].freezeAmount(_freeze_datas[msg.sender].frozenAmount, _freeze_datas[msg.sender].startBlock, lastFreezeBlock, block.number);
        require(amount > 0, "Melt amount must be greater than 0");
        // border amount
        if(amount > _frozen_balanceOf(msg.sender)) {
            amount = _frozen_balanceOf(msg.sender);
        }
        _melt(msg.sender, amount); 

        _freeze_datas[msg.sender].lastFreezeBlock = block.number;

        emit Claim(msg.sender, amount);
        return true;
    }

    function startSeedPause() onlyOwner public {
        seedPause = false;
        seedMeltStartBlock = block.number;
    }

    function _mintFrozenTokensForSeed(address account, uint256 amount) internal returns (bool) {
        require(!_freeze_datas[account].initialzed, "Seed: specified account already initialzed");
        _roles[account] = RoleType.SEED;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function _mintFrozenTokensForPrivate(address account, uint256 amount) internal returns (bool) {
        require(!_freeze_datas[account].initialzed, "Private: specified account already initialzed");
        _roles[account] = RoleType.PRIVATE;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    /// @dev for airbon
    function _mintFrozenTokensForAirdrop(address account, uint256 amount) internal returns (bool) {
        // only init once for a address.
        require(!_freeze_datas[account].initialzed, "Airdrop: specified account already initialzed");
        _roles[account] = RoleType.AIRDROP;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }


    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        require(account != address(this), "ERC20: mint to the contract address");
        require(amount > 0, "ERC20: mint amount should be > 0");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(this), account, amount);
    }

    function _burn(address account, uint256 value) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _totalSupply = _totalSupply.sub(value);
        _balances[account] = _balances[account].sub(value);
        emit Transfer(account, address(this), value);
    }

    function _approve(address _owner, address spender, uint256 value) internal {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[_owner][spender] = value;
        emit Approval(_owner, spender, value);
    }

    function _burnFrom(address account, uint256 amount) internal {
        _burn(account, amount);
        _approve(account, msg.sender, _allowances[account][msg.sender].sub(amount));
    }

    function _freeze(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: freeze from the zero address");
        require(amount > 0, "ERC20: freeze from the address: amount should be > 0");

        _balances[account] = _balances[account].sub(amount);
        _frozen_add(account, amount);

        emit Freeze(account, amount);
    }

    function _mintfrozen(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint frozen to the zero address");
        require(account != address(this), "ERC20: mint frozen to the contract address");
        require(amount > 0, "ERC20: mint frozen amount should be > 0");

        _totalSupply = _totalSupply.add(amount);

        emit Transfer(address(this), account, amount);

        _frozen_add(account, amount);

        emit MintFrozen(account, amount);
    }

    function _melt(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: melt from the zero address");
        require(amount > 0, "ERC20: melt from the address: value should be > 0");
        require(_frozen_balanceOf(account) >= amount, "ERC20: melt from the address: balance < amount");

        _frozen_sub(account, amount);
        _balances[account] = _balances[account].add(amount);

        emit Melt(account, amount);
    }

    function _burnFrozen(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: frozen burn from the zero address");

        _totalSupply = _totalSupply.sub(amount);
        _frozen_sub(account, amount);

        emit Transfer(account, address(this), amount);
    }
}