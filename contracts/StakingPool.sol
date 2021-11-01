// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

import "./Borrowing.sol";
import "./ActivePool.sol";
import "./VaultManager.sol";

contract StakingPool is Ownable {
    uint256 public totalETHFees;
    
    uint256 public totalLUSDFees;
    
    Borrowing public borrowing;
    ActivePool activePool;
    VaultManager vaultManager;
    
    function setAddresses(Borrowing _borrowing, ActivePool _activePool, VaultManager _vaultManager) external onlyOwner {
        borrowing = _borrowing;
        activePool = _activePool;
        vaultManager = _vaultManager;
        
        renounceOwnership();
    }
    
    function increaseLUSDFees(uint256 _amount) external onlyBorrowingContract {
        totalLUSDFees = totalLUSDFees + _amount;
    }
    
    function increaseETHFees(uint256 _amount) external onlyVaultManagerContract {
        totalETHFees = totalETHFees + _amount;
    }
    
    modifier onlyBorrowingContract {
        require(msg.sender == address(borrowing), "StakingPool: Caller is not the Borrowing contract");
        _;
    }
    
    modifier onlyVaultManagerContract {
        require(msg.sender == address(vaultManager), "StakingPool: Caller is not the VaultManager contract");
        _;
    }
    
    modifier onlyActivePool {
        require(msg.sender == address(activePool), "StakingPool: Caller is not the ActivePool");
        _;
    }
    
    receive() external payable onlyActivePool {
    }
    
}
