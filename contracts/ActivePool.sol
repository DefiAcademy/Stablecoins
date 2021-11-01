// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

import "./Borrowing.sol";
import "./VaultManager.sol";
import "./StabilityPool.sol";

contract ActivePool is Ownable {
    Borrowing public borrowing;
    VaultManager public vaultManager;
    StabilityPool public stabilityPool;
    
    uint256 internal totalETHDeposited;
    uint256 internal totalLUSDDebt; 
    
    function setAddresses(Borrowing _borrowingAddress, VaultManager _vaultManagerAddress, StabilityPool _stabilityPoolAddress) external onlyOwner {
        borrowing = _borrowingAddress;
        vaultManager = _vaultManagerAddress;
        stabilityPool = _stabilityPoolAddress;
        
        renounceOwnership();
    }
    
    // Getters
    function getETHDeposited() external view returns (uint) {
        return totalETHDeposited;
    }

    function getLUSDDebt() external view returns (uint) {
        return totalLUSDDebt;
    }
    
    // Main functionality 
    function sendETH(address _account, uint _amount) external onlyBorrowingOrVaultManagerOrStabilityPool {
        totalETHDeposited = totalETHDeposited - _amount;
        (bool success, ) = _account.call{ value: _amount }("");
        require(success, "ActivePool: sending ETH failed");
    }
    
    function increaseLUSDDebt(uint _amount) external onlyBorrowingOrVaultManager {
        totalLUSDDebt  = totalLUSDDebt + _amount;
    }

    function decreaseLUSDDebt(uint _amount) external onlyBorrowingOrVaultManagerOrStabilityPool {
        totalLUSDDebt = totalLUSDDebt - _amount;
    }
    
    // Modifiers
    modifier onlyBorrowingContract {
        require(msg.sender == address(borrowing), "ActivePool: Caller is not the Borrowing contract");
        _;
    }
    
    modifier onlyBorrowingOrVaultManager {
        require(msg.sender == address(borrowing) || msg.sender == address(vaultManager), "ActivePool: Caller is not the Borrowing or VaultManager contract");
        _;
    }
    
    modifier onlyBorrowingOrVaultManagerOrStabilityPool {
        require(msg.sender == address(borrowing) || msg.sender == address(vaultManager) || msg.sender == address(stabilityPool), "ActivePool: Caller is not the Borrowing or VaultManager or StabilityPool contract");
        _;
    }
    
    // Fallback
    receive() external payable onlyBorrowingContract {
        totalETHDeposited = totalETHDeposited + msg.value;
    }
}
