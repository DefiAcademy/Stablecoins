// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

import "./LUSDToken.sol";
import "./VaultManager.sol";

contract StabilityPool is Ownable {
    LUSDToken public lusdToken;
    VaultManager public vaultManager;
    
    uint256 internal totalETHDeposited;
    uint256 internal totalLUSDDeposits;
     
    mapping (address => uint256) public deposits;  // depositor address -> total deposits
     
    function setAddresses(LUSDToken _lUSDToken, VaultManager _vaultManager) external onlyOwner {
        lusdToken = _lUSDToken;
        vaultManager = _vaultManager;
        
        renounceOwnership();
    }
    
    function deposit(uint256 _amount) external {
        deposits[msg.sender] = deposits[msg.sender] + _amount;

        // update LUSD Deposits
        uint256 newTotalLUSDDeposits = totalLUSDDeposits + _amount;
        totalLUSDDeposits = newTotalLUSDDeposits;
        
        // transfer LUSD
        lusdToken.transferFrom(msg.sender, address(this), _amount);
    }
    
    function offset(uint256 _lusdAmount) external onlyVaultManager {
        // decrease debt in active pool 
        totalLUSDDeposits = totalLUSDDeposits - _lusdAmount;
        
        // burn lusd 
        lusdToken.burn(address(this), _lusdAmount);
    }
    
    // Getters
    function getETHDeposited() external view returns (uint) {
        return totalETHDeposited;
    }
    
    function getTotalLUSDDeposits() external view returns(uint256){
        return totalLUSDDeposits;
    }
    
    modifier onlyVaultManager {
        require(msg.sender == address(vaultManager), "StabilityPool: Sender is not VaultManager");
        _;
    }
    
    // Fallback
    receive() external payable onlyVaultManager {
        totalETHDeposited = totalETHDeposited + msg.value;
    }
}
