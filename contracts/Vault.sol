// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

contract Vault is ERC20 {
    StabilityPool stabilityPool;
    PriceFeed priceFeed;
    
    uint256 minimumCollateralRatio;

    // create collateral token 
    // store positions
    // find a way to get all positions and query 1 by 1 to see their collateral ratio 
    struct Position {
        uint256 collateralAmount;
        uint256 debtAmount;
    }
    
    constructor(address _priceFeed, address _stabilityPool, uint256 _minimumCollateralRatio) ERC20("LUSD", "LUSD"){
        stabilityPool = StabilityPool(_stabilityPool);
        priceFeed = PriceFeed(_priceFeed);
        minimumCollateralRatio = _minimumCollateralRatio;
    }
    
    function borrow(uint256 _amount) external {
        // review collateral ratio by getting price 
        // transfer collateral from sender to this contract 
        // mint LUSD to the sender 
    }
    
    function repay(uint256 _amount) external {
        // transfer LUSD to this contract 
        // burn LUSD
        // transfer collateral locked to sender 
    }
    
    function liquidate(address _borrowerAddress) external {
        // get the position of the borrower 
        // transfer tokens from Stabiliy Pool 
        // transfer collateral to Stability Pool 
        // burn tokens 
        // delete position 
    }
    
    function redeem(uint256 _amountToRedeem) external {
        // get the position with the lowest collateral ratio 
        // transfer the number(_amountToRedeem) of LUSD to this contract 
        // return proportional collateral to redeemer 
        // update BASE RATE 
    }
}
