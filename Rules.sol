pragma solidity ^0.5.11;

import "./SafeMath.sol";

library Rules {
    
    using SafeMath for uint256;

    struct Rule {
        uint256 baseAmount;                
        uint256 intervalFreezeBlock;        
        uint256 percent;                   
        bool    initRule;                   
    }

    function setRule(Rule storage rule, uint256 _baseAmount,  uint256 _intervalFreezeBlock, uint256 _percent) internal {
        require(_baseAmount != 0);
        require(_intervalFreezeBlock > 0);
        require(_percent > 0);
        rule.baseAmount = _baseAmount;
        rule.intervalFreezeBlock = _intervalFreezeBlock;
        rule.percent = _percent;
        rule.initRule = true;
    }

    function freezeAmount(Rule storage rule, uint256 startFrozenBlock, uint256 lastFreezeBlock, uint256 currentBlock) internal view returns(uint256) {
        require(startFrozenBlock <= lastFreezeBlock, "startFrozenBlockmust be greater than or equal to lastFreezeBlock");
        require(currentBlock >= lastFreezeBlock);
        require(rule.baseAmount > 0);
        require(rule.percent > 0);
        uint256 actualFactor =  currentBlock.sub(startFrozenBlock).div(rule.intervalFreezeBlock);
        uint256 alreadyFactor = lastFreezeBlock.sub(startFrozenBlock).div(rule.intervalFreezeBlock);
        require(actualFactor >= alreadyFactor, "invalid factor");
        uint256 factor = actualFactor - alreadyFactor;
        return rule.baseAmount.mul(rule.percent).mul(factor).div(100);
    }
}