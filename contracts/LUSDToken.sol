// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";

contract LUSDToken is ERC20 {
    address public borrowingAdress; 
    address public vaultManagerAddress;
    address public stabilityPoolAddress;
    
    constructor(address _vaultManagerAddress, address _stabilityPoolAddress) ERC20("LUSDToken", "LUSDToken"){
        borrowingAdress = msg.sender;    
        vaultManagerAddress = _vaultManagerAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
    }
    
    function mint(address _account, uint256 _amount) external onlyBorrowing{
        _mint(_account, _amount);
    }
    
    
    function burn(address _account, uint256 _amount) external onlyBorrowingOrVaultManagerOrStabilityPool{
        _burn(_account, _amount);
    }
    
    modifier onlyBorrowingOrVaultManagerOrStabilityPool {
        require(msg.sender == borrowingAdress || msg.sender == vaultManagerAddress || msg.sender == stabilityPoolAddress, "Invalid minter");
        _;
    }
    
    modifier onlyBorrowing {
        require(msg.sender == borrowingAdress, "Invalid minter");
        _;
    }
    
}
