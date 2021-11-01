// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Base.sol";
import "./PriceFeed.sol";
import "./VaultManager.sol";
import "./LUSDToken.sol";

// pools 
import "./ActivePool.sol";
import "./StabilityPool.sol";
import "./GasPool.sol";
import "./StakingPool.sol";

import "hardhat/console.sol";

contract Borrowing is Base {
    PriceFeed public priceFeed;
    VaultManager public vaultManager;
    LUSDToken public lusdToken;
    
    // pools 
    ActivePool public activePool;
    StabilityPool public stabilityPool;
    GasPool public gasPool;
    StakingPool public stakingPool;
    
    constructor(){
        priceFeed = new PriceFeed();
        priceFeed.setPrice(1000 * 10**18);
        
        // pools 
        activePool = new ActivePool();
        stabilityPool = new StabilityPool();
        gasPool = new GasPool();
        stakingPool = new StakingPool();
        
        // initialize vault manager
        vaultManager = new VaultManager();
        
        // lusdToken
        lusdToken = new LUSDToken(address(vaultManager), address(stabilityPool));

        // set addresses
        activePool.setAddresses(this, vaultManager, stabilityPool);
        stabilityPool.setAddresses(lusdToken, vaultManager);
        stakingPool.setAddresses(this, activePool, vaultManager);
        vaultManager.setAddresses(priceFeed, lusdToken, stabilityPool, gasPool, stakingPool, activePool);
    }
    
    function borrow(uint256 _LUSDAmount) public payable {
        uint256 lusdAmount = _LUSDAmount * DECIMAL_PRECISION;
        uint256 debt = lusdAmount;
        
        // get price 
        uint256 price = priceFeed.getPrice();
        console.log("Price %s", price);
        
        // calculations
        uint256 collateralRatio = msg.value * price / debt;
        console.log("collateralRatio %s", collateralRatio);
        
        // validate collateral ratio 
        _requireCollateralRatioIsAboveMCR(collateralRatio);
        
        vaultManager.decayBaseRateFromBorrowing(); // decay the baseRate state variable
        console.log("After decay base rate");
        
        uint256 borrowingFee = vaultManager.getBorrowingFee(lusdAmount);
        console.log("borrowingFee %s", borrowingFee);
        
        // increase fees in staking pool 
        stakingPool.increaseLUSDFees(borrowingFee);

        // mint LUSD for StakingPool
        lusdToken.mint(address(stakingPool), borrowingFee);
        
        uint256 compositeDebt = debt + LUSD_GAS_COMPENSATION + borrowingFee;
        console.log("compositeDebt %s", compositeDebt);
        
        // create vault 
        vaultManager.createVault(msg.sender, msg.value, compositeDebt, 1);
        
        // send Eth to ActivePool
        _addCollateralToActivePool(msg.value);
        console.log("ActivePool Collateral Deposited %s", activePool.getETHDeposited());
        
        // mint tokens for user
        lusdToken.mint(msg.sender, lusdAmount);
        console.log("Balance of borrower %s", lusdToken.balanceOf(msg.sender));
        
        // mint tokens for gas compensations
        lusdToken.mint(address(gasPool), LUSD_GAS_COMPENSATION);
        console.log("gas compensations %s", lusdToken.balanceOf(address(gasPool)));
        
        // increase LUSD Debt 
        activePool.increaseLUSDDebt(compositeDebt);
        console.log("ActivePool LUSD Debt %s", activePool.getLUSDDebt());
    }
    
    function repay() external {
        uint256 collateral = vaultManager.getVaultCollateral(msg.sender);
        uint256 debt = vaultManager.getVaultDebt(msg.sender);
        
        uint256 debtRepayment = debt - LUSD_GAS_COMPENSATION;
        require(lusdToken.balanceOf(msg.sender) >= debtRepayment, "Borrower doesnt have enough LUSD to make repayment");

        vaultManager.closeVault(msg.sender);
        
        // Burn the repaid LUSD from the user's balance 
        lusdToken.burn(msg.sender, debtRepayment);
        activePool.decreaseLUSDDebt(debtRepayment);
        
        // burn the gas compensation from the Gas Pool
        lusdToken.burn(address(gasPool), LUSD_GAS_COMPENSATION);
        activePool.decreaseLUSDDebt(LUSD_GAS_COMPENSATION);
        
        // Send the collateral back to the user
        activePool.sendETH(msg.sender, collateral);
    }
    
    function _requireCollateralRatioIsAboveMCR(uint256 _collateralRatio) internal pure {
        require(_collateralRatio >= MINIMUN_COLLATERAL_RATIO, "Collateral Ratio Below MINIMUN_COLLATERAL_RATIO");
    }
    
    function _addCollateralToActivePool(uint _amount) internal {
        (bool success, ) = address(activePool).call{value: _amount}("");
        require(success, "Borrowing: Sending ETH to ActivePool failed");
    }

}
