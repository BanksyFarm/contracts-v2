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
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract TreasuryUtil is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    address public immutable WETH;

    address public immutable treasuryDAOAddress;

    address public immutable usdCurrency;

    address public immutable routerAddress;


    event DepositFeeConvertedToUSD(address indexed inputToken, uint256 inputAmount);

    constructor(address _treasuryDAOAddress, address _usdCurrency, address _routerAddress) {
        treasuryDAOAddress = _treasuryDAOAddress;
        routerAddress = _routerAddress;
        usdCurrency = _usdCurrency;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);

        WETH = IUniswapV2Router02(routerAddress).WETH();
    }

    /// Public functions ///
    // Convert owner deposite fee to usd. Only operator (masterchef) can run it
    // tokenType 0 for single token
    function convertDepositFeesToUSD(address token, uint256 tokenType) public onlyRole(OPERATOR_ROLE) {
        uint256 amount = IERC20(token).balanceOf(address(this));

        if (amount == 0)
            return;

        if (tokenType == 1) {
            (address token0, address token1) = _removeLiquidity(token, amount);
            convertDepositFeesToUSD(token0, 0);
            convertDepositFeesToUSD(token1, 0);
            return;
        }

        uint256 usdBalanceBefore;

        if (token != usdCurrency) {
            usdBalanceBefore = IERC20(usdCurrency).balanceOf(address(this));
            _swapTokensForTokens(token, usdCurrency, amount);
        }

        uint256 usdAmount = IERC20(usdCurrency).balanceOf(address(this)) - usdBalanceBefore;

        if (usdAmount > 0)
            IERC20(usdCurrency).safeTransfer(treasuryDAOAddress, usdAmount);

        emit DepositFeeConvertedToUSD(token, amount);
    }

    /// Internal functions ///
    function _swapTokensForTokens(address from, address to, uint256 amount) internal {
        address[] memory path = new address[](from == WETH || to == WETH ? 2 : 3);
        if (from == WETH || to == WETH) {
            path[0] = from;
            path[1] = to;
        } else {
            path[0] = from;
            path[1] = WETH;
            path[2] = to;
        }

        IERC20(from).safeApprove(routerAddress, amount);

        IUniswapV2Router02(routerAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0, // accept any amount of USD
            path,
            address(this),
            block.timestamp
        );
    }

    function _removeLiquidity(address token, uint256 tokenAmount) internal returns(address, address) {
        IERC20(token).safeApprove(routerAddress, tokenAmount);

        IUniswapV2Pair lpToken = IUniswapV2Pair(token);

        address token0 = lpToken.token0();
        address token1 = lpToken.token1();

        IUniswapV2Router02(routerAddress).removeLiquidity(
            token0,
            token1,
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp
        );

        return (token0, token1);
    }

    // For emergency cases. Only The Gnosis Safe Multisig wallet administrator can run it
    function emergencyWithDrawToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        if (balanceToken > 0)
            IERC20(token).safeTransfer(msg.sender, balanceToken);
    }

}
