// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

import "./PriceFeed.sol";
import "./Borrowing.sol";
import "./Base.sol";
import "./LUSDToken.sol";
import "./SortedVaults.sol";

// Pools 
import "./ActivePool.sol";
import "./StabilityPool.sol";
import "./GasPool.sol";
import "./StakingPool.sol";

import "hardhat/console.sol";

contract VaultManager is Base, Ownable {
    PriceFeed public priceFeed;
    Borrowing public borrowing;    
    LUSDToken public lusdToken;
    SortedVaults public sortedVaults;

    // Pools
    StabilityPool public stabilityPool;
    ActivePool public activePool;
    GasPool public gasPool;
    StakingPool public stakingPool;
    
    uint256 public baseRate;

    // latest fee operation (redemption or new LUSD issuance)
    uint256 public lastFeeOperationTime;
    
    enum Status {
        nonExistent, // 0
        active,  // 1
        closedByOwner, // 2
        closedByLiquidation, // 3
        closedByRedemption // 4
    }

    // Store the necessary data for a Vault
    struct Vault {
        uint debt;
        uint collateral;
        Status status;
    }

    mapping (address => Vault) public vaults;
    
    function setAddresses(PriceFeed _priceFeed, LUSDToken _lUSDToken, StabilityPool _stabilityPool, GasPool _gasPool, StakingPool _stakingPool, ActivePool _activePool) external onlyOwner {
            
        borrowing = Borrowing(msg.sender);
        priceFeed = _priceFeed;
        lusdToken = _lUSDToken;
        sortedVaults = new SortedVaults(msg.sender);
        
        // pools
        activePool = _activePool;
        stabilityPool = _stabilityPool;    
        gasPool = _gasPool;
        stakingPool = _stakingPool;
        
        renounceOwnership();
    }
    
    function liquidate(address _borrower) external {
        uint256 price = priceFeed.getPrice();
        console.log("Price %s", price);
        
        // get vault info
        (uint256 currentETH, uint256 currentLUSDDebt) = _getCurrentTroveAmounts(_borrower);
        console.log("currentETH %s", currentETH);
        console.log("currentLUSDDebt %s", currentLUSDDebt);

        uint256 collateralRatio = LiquityMath._computeCR(currentETH, currentLUSDDebt, price);
        console.log("collateralRatio %s", collateralRatio);
        
        require(collateralRatio < MINIMUN_COLLATERAL_RATIO, "Cannot liquidate vault");
        
        uint256 lusdInStabilityPool = stabilityPool.getTotalLUSDDeposits();
        require(lusdInStabilityPool >= currentLUSDDebt, "Insufficient funds to liquidate");
        
        // calculate collateral compensation
        uint256 collateralCompensation = currentETH / PERCENT_DIVISOR; // to get 5 %
        uint256 gasCompensation = LUSD_GAS_COMPENSATION;
        uint256 collateralToLiquidate = currentETH - collateralCompensation;
        
        // update debt  
        activePool.decreaseLUSDDebt(currentLUSDDebt);
        
        // update debt + burn tokens 
        stabilityPool.offset(currentLUSDDebt);
        
        // send liquidated eth to stabilityPool
        activePool.sendETH(address(stabilityPool), collateralToLiquidate);
        
        // close vault 
        _closeVault(_borrower, Status.closedByLiquidation);
        
        // send gas compensation 
        lusdToken.transferFrom(address(gasPool), msg.sender, gasCompensation);
        
        // send eth liquidated (0.5%) to liquidator 
        activePool.sendETH(msg.sender, collateralCompensation);
    }
    
    function redemption(uint256 _amountToRedeem) external {
        require(lusdToken.balanceOf(msg.sender) >= _amountToRedeem, "VaultManager: Requested redemption amount must be <= user's LUSD token balance");
        
        uint256 price = priceFeed.getPrice();
        console.log("Price %s", price);
        
        // mention that this case in liquity is more complex but for learning purposes we are simplifying, we will just redeem the last one,
        // also mention that in reality liquity would go throught all the troves till the amount of LUSD that is redeemed is complete 
        address borrowerToRedeemFrom = sortedVaults.getLast();
        
        // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Vault minus the liquidation reserve
        uint256 maxAmounToRedeem = LiquityMath._min(_amountToRedeem, vaults[msg.sender].debt - LUSD_GAS_COMPENSATION);
        console.log("LUSD to redeem %s", maxAmounToRedeem);
        
        // Get the ETHLot of equivalent value in USD
        uint256 ethToRedeem = maxAmounToRedeem * DECIMAL_PRECISION / price;
        console.log("Eth to redeem %s", ethToRedeem);
        
        // Decrease the debt and collateral of the current Vault according to the LUSD lot and corresponding ETH to send
        uint newDebt = vaults[borrowerToRedeemFrom].debt - maxAmounToRedeem;
        uint newCollateral = vaults[borrowerToRedeemFrom].collateral - ethToRedeem;
        console.log("newDebt %s", newDebt);
        console.log("newCollateral %s", newCollateral);
        
        uint256 totalSystemDebt = activePool.getLUSDDebt();
        console.log("totalSystemDebt %s", totalSystemDebt);
        
        if (newDebt == LUSD_GAS_COMPENSATION) {
            // close vault
            _closeVault(borrowerToRedeemFrom, Status.closedByRedemption);
        } else {
            uint newNICR = LiquityMath._computeNominalCR(newCollateral, newDebt);
            sortedVaults.reInsert(borrowerToRedeemFrom, newNICR);
            console.log("Old debt %s", vaults[borrowerToRedeemFrom].debt);
            console.log("Old collateral %s", vaults[borrowerToRedeemFrom].collateral);
            
            vaults[borrowerToRedeemFrom].debt = newDebt;
            vaults[borrowerToRedeemFrom].collateral = newCollateral;
        }
        
         // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total LUSD supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(ethToRedeem, price, totalSystemDebt);

        // Calculate the redemption fee in ETH
        uint256 ethFee = _getRedemptionFee(ethToRedeem);
        console.log("ethFee %s", ethFee);
        
        // Send the ETH fee to the LQTY staking contract
        activePool.sendETH(address(stakingPool), ethFee);
        stakingPool.increaseETHFees(ethFee);

        uint256 ethToSendToRedeemer = ethToRedeem - ethFee;
        console.log("ethToSendToRedeemer %s", ethToSendToRedeemer);
       
        // Burn the total LUSD that is cancelled with debt
        lusdToken.burn(msg.sender, maxAmounToRedeem);
        
        // Update Active Pool LUSD
        activePool.decreaseLUSDDebt(maxAmounToRedeem);
        
        // send ETH to redeemer
        activePool.sendETH(msg.sender, ethToSendToRedeemer);
    }
    
    function _updateBaseRateFromRedemption(uint _ETHDrawn,  uint _price, uint _totalLUSDSupply) internal returns (uint) {
        uint decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn ETH back to LUSD at face value rate (1 LUSD:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint redeemedLUSDFraction = (_ETHDrawn * _price) / _totalLUSDSupply;

        uint newBaseRate = decayedBaseRate + (redeemedLUSDFraction / BETA);
        newBaseRate = LiquityMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%

        baseRate = newBaseRate;

        _updateLastFeeOpTime();

        return newBaseRate;
    }
    
    function _getRedemptionFee(uint _ETHDrawn) internal view returns (uint) {
        return _calcRedemptionFee(getRedemptionRate(), _ETHDrawn);
    }
    
    function _calcRedemptionFee(uint _redemptionRate, uint _ETHDrawn) internal pure returns (uint) {
        uint redemptionFee = _redemptionRate * _ETHDrawn / DECIMAL_PRECISION;
        require(redemptionFee < _ETHDrawn, "TroveManager: Fee would eat up all returned collateral");
        return redemptionFee;
    }
    
    function getRedemptionRate() public view returns (uint) {
        return _calcRedemptionRate(baseRate);
    }
    
    function _calcRedemptionRate(uint _baseRate) internal pure returns (uint) {
        return LiquityMath._min(
            REDEMPTION_FEE_FLOOR + _baseRate,
            DECIMAL_PRECISION // cap at a maximum of 100%
        );
    }
    
    // Return the nominal collateral ratio (ICR) of a given Trove, without the price. Takes a trove's pending coll and debt rewards from redistributions into account.
    function getNominalICR(address _borrower) public view returns (uint) {
        (uint currentETH, uint currentLUSDDebt) = _getCurrentTroveAmounts(_borrower);

        uint NICR = _computeNominalCR(currentETH, currentLUSDDebt);
        return NICR;
    }
    
    function _computeNominalCR(uint _coll, uint _debt) internal pure returns (uint) {
        if (_debt > 0) {
            return _coll * NICR_PRECISION / _debt;
        }
        // Return the maximal value for uint256 if the Trove has a debt of 0. Represents "infinite" CR.
        else { // if (_debt == 0)
            return 2**256 - 1;
        }
    }
    
    function _getCurrentTroveAmounts(address _borrower) internal view returns (uint, uint) {
        uint currentETH = vaults[_borrower].collateral;
        uint currentLUSDDebt = vaults[_borrower].debt;

        return (currentETH, currentLUSDDebt);
    }
    
    // Updates the baseRate state variable based on time elapsed since the last redemption or LUSD borrowing operation.
    function decayBaseRateFromBorrowing() external onlyBorrowingContract {
        uint decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= DECIMAL_PRECISION);  // The baseRate can decay to 0

        baseRate = decayedBaseRate;

        _updateLastFeeOpTime();
    }
    
    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastFeeOp();
        console.log("MinutesPassed %s", minutesPassed);
        
        uint decayFactor = LiquityMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return baseRate * decayFactor / DECIMAL_PRECISION;
    }
    
    function _updateLastFeeOpTime() internal {
        uint timePassed = block.timestamp - lastFeeOperationTime;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            lastFeeOperationTime = block.timestamp;
        }
    }
    
    function getBorrowingFee(uint _LUSDDebt) external view returns (uint) {
        return _calcBorrowingFee(getBorrowingRate(), _LUSDDebt);
    }
    
    function _calcBorrowingFee(uint _borrowingRate, uint _LUSDDebt) internal pure returns (uint) {
        return _borrowingRate * _LUSDDebt / DECIMAL_PRECISION;
    }
    
    function getBorrowingRate() public view returns (uint) {
        return _calcBorrowingRate(baseRate);
    }

    function _calcBorrowingRate(uint _baseRate) internal pure returns (uint) {
        return LiquityMath._min(
            BORROWING_FEE_FLOOR + _baseRate,
            MAX_BORROWING_FEE
        );
    }
    
    function _minutesPassedSinceLastFeeOp() internal view returns (uint) {
        return block.timestamp - lastFeeOperationTime / SECONDS_IN_ONE_MINUTE;
    } 
    
    // --- Vault property getters ---
    function getVaultDebt(address _borrower) external view returns (uint) {
        return vaults[_borrower].debt;
    }

    function getVaultCollateral(address _borrower) external view returns (uint) {
        return vaults[_borrower].collateral;
    }

    // --- Vault property setters, called by BorrowingContract ---
    function createVault(address _borrower, uint _collateral, uint256 _debt, uint _status) external onlyBorrowingContract {
        vaults[_borrower].status = Status(_status);   
        vaults[_borrower].collateral = _collateral;
        vaults[_borrower].debt = _debt;
        
        sortedVaults.insert(_borrower, getNominalICR(_borrower));
    }
    
    function closeVault(address _borrower) external onlyBorrowingContract {
        _closeVault(_borrower, Status.closedByOwner);    
    }
    
    function _closeVault(address _borrower, Status closedStatus) internal {
        vaults[_borrower].status = closedStatus;
        vaults[_borrower].collateral = 0;
        vaults[_borrower].debt = 0;

        sortedVaults.remove(_borrower);
    }
    
    modifier onlyBorrowingContract {
         console.log("Dentro -1");
        require(msg.sender == address(borrowing), "VaultManager: Caller is not the Borrowing contract");
        _;
    }
}
