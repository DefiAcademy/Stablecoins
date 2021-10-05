// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

contract PriceFeed {
    uint256 latestPrice;
    
    function setPrice(uint256 _newPrice) external {
        latestPrice = _newPrice;    
    }
    
    function getPrice() external view returns (uint256){
        return latestPrice;
    }
}
