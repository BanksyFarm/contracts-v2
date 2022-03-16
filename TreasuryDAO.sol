/*
     ,-""""-.
   ,'      _ `.
  /       )_)  \
 :              :
 \              /
  \            /
   `.        ,'
     `.    ,'
       `.,'
        /\`.   ,-._
            `-'         Banksy.farm
 */

// SPDX-License-Identifier: MIT
// Kurama protocol certified

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";


contract TreasuryDAO is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    address public immutable usdCurrency;

    // Distribution usd time frame
    uint256 public distributionTimeFrame = 3600 * 24 * 30; // 1 month by default

    uint256 public lastUSDDistroTime;

    uint256 public pendingUSD;

    event USDTransferredToUser(address recipient, uint256 usdAmount);
    event SetUSDDistributionTimeFrame(uint256 oldValue, uint256 newValue);

    constructor(address _usdCurrency, uint256 startTime) {
        usdCurrency = _usdCurrency;

        lastUSDDistroTime = startTime;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    /// External functions ///
    /// Calculate the usd Relase over the timer. Only operator(masterchef) can run it
    function getUsdRelease(uint256 totalUsdLockup) external onlyRole(OPERATOR_ROLE) returns (uint256) {
        uint256 usdBalance = IERC20(usdCurrency).balanceOf(address(this));
        if (pendingUSD + totalUsdLockup > usdBalance)
            return 0;

        uint256 usdAvailable = usdBalance - pendingUSD - totalUsdLockup;

        uint256 timeSinceLastDistro = block.timestamp > lastUSDDistroTime ? block.timestamp - lastUSDDistroTime : 0;

        uint256 usdRelease = (timeSinceLastDistro * usdAvailable) / distributionTimeFrame;

        usdRelease = usdRelease > usdAvailable ? usdAvailable : usdRelease;

        lastUSDDistroTime = block.timestamp;
        pendingUSD = pendingUSD + usdRelease;

        return usdRelease;
    }

    // Pay usd to owner. Only operator(masterchef) can run it
    function transferUSDToOwner(address ownerAddress, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        uint256 usdBalance = IERC20(usdCurrency).balanceOf(address(this));
        if (usdBalance < amount)
            amount = usdBalance;

        IERC20(usdCurrency).safeTransfer(ownerAddress, amount);

        if (amount > pendingUSD)
            amount = pendingUSD;

        pendingUSD = pendingUSD - amount;

        emit USDTransferredToUser(ownerAddress, amount);
    }

    // Set distribution time frame for usd distribution. Only admin can run it
    function setUSDDistributionTimeFrame(uint256 newUsdDistributionTimeFrame) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newUsdDistributionTimeFrame > 0);

        emit SetUSDDistributionTimeFrame(distributionTimeFrame, newUsdDistributionTimeFrame);

        distributionTimeFrame = newUsdDistributionTimeFrame;

    }

    // For emergency cases. Only admin can run it
    function emergencyWithDrawToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        if (balanceToken > 0)
            IERC20(token).safeTransfer(msg.sender, balanceToken);
    }
}
