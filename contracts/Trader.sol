// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interface/PriceOracle.sol";
import "./interface/TectonicCoreInterface.sol";
import "./interface/TToken.sol";
import "./interface/IVVSRouter02.sol";

contract Trader {
    address constant usdcAddr = 0xc21223249CA28397B4B6541dfFaEcC539BfF0c59;
    address constant tUsdcAddr = 0xB3bbf1bE947b245Aef26e3B6a9D777d7703F4c8e;
    address constant tETHAddr = 0x543F4Db9BD26C9Eb6aD4DD1C33522c966C625774;
    address constant ethAddr = 0xe44Fd7fCb2b1581822D0c862B68222998a0c299a;
    address constant tectonicProxyAddr = 0xb3831584acb95ED9cCb0C11f677B5AD01DeaeEc0;
    address constant vvsRouterAddr = 0x145863Eb42Cf62847A6Ca784e6416C1682b1b2Ae;

    PriceOracle constant priceOracle = PriceOracle(0xD360D8cABc1b2e56eCf348BFF00D2Bd9F658754A);
    IVVSRouter02 constant vvsRouter = IVVSRouter02(0x145863Eb42Cf62847A6Ca784e6416C1682b1b2Ae);

    function short(uint usdcAmount) external {
        IERC20(usdcAddr).transferFrom(msg.sender, address(this), usdcAmount);

        if (IERC20(usdcAddr).allowance(address(this), tUsdcAddr) < usdcAmount) {
            IERC20(usdcAddr).approve(tUsdcAddr, type(uint).max);
        }
        TToken(tUsdcAddr).mint(usdcAmount);
        address[] memory tTokens = new address[](1);
        tTokens[0] = tUsdcAddr;
        TectonicCoreInterface(tectonicProxyAddr).enterMarkets(tTokens);

        uint targetTokenPrice = priceOracle.getUnderlyingPrice(tETHAddr);
        uint usdcPrice = priceOracle.getUnderlyingPrice(tUsdcAddr);
        uint targetTokenAmount = usdcAmount * usdcPrice * 6 / 10 / targetTokenPrice;
        require(TToken(tETHAddr).borrow(targetTokenAmount) == 0, "borrow failed");

        exchangeTokenForUSDC(ethAddr, targetTokenAmount);
    }

    function exchangeTokenForUSDC(address tokenAddr, uint amount) private returns (uint) {
        address[] memory path = new address[](2);
        path[0] = tokenAddr;
        path[1] = usdcAddr;
        if (IERC20(tokenAddr).allowance(address(this), vvsRouterAddr) < amount) {
            IERC20(tokenAddr).approve(vvsRouterAddr, type(uint).max);
        }
        uint[] memory swapResult = vvsRouter.swapExactTokensForTokens(amount, 0, path, msg.sender, block.timestamp + 3 minutes);

        return swapResult[swapResult.length - 1];
    }

    function getClosePositionAmount(address tTokenAddr) public returns (uint) {
        TToken tToken = TToken(tTokenAddr);

        uint borrowBalance = tToken.borrowBalanceCurrent(address(this));

        address[] memory path = new address[](2);
        path[0] = usdcAddr;
        path[1] = tToken.underlying();

        uint[] memory amounts = vvsRouter.getAmountsIn(borrowBalance, path);
        return amounts[0];
    }

    function closePosition(address tBorrowedTokenAddr) external {
        TToken tBorrowedToken = TToken(tBorrowedTokenAddr);
        IERC20 borrowedToken = IERC20(tBorrowedToken.underlying());
        IERC20 usdcToken = IERC20(usdcAddr);

        uint positionBalance = tBorrowedToken.borrowBalanceCurrent(address(this));

        address[] memory path = new address[](2);
        path[0] = usdcAddr;
        path[1] = tBorrowedToken.underlying();

        uint[] memory amounts = vvsRouter.getAmountsIn(positionBalance, path);
        uint needUsdcAmount = amounts[0];

        require(usdcToken.balanceOf(msg.sender) >= needUsdcAmount, "Trader: not enough USDC to close the position");

        usdcToken.transferFrom(msg.sender, address(this), needUsdcAmount);

        if (usdcToken.allowance(address(this), vvsRouterAddr) < needUsdcAmount) {
            usdcToken.approve(vvsRouterAddr, type(uint).max);
        }

        uint[] memory swapResult = vvsRouter.swapTokensForExactTokens(positionBalance, amounts[0], path, address(this), block.timestamp + 3 minutes);

        if (borrowedToken.allowance(address(this), tBorrowedTokenAddr) < positionBalance) {
            borrowedToken.approve(tBorrowedTokenAddr, type(uint).max);
        }
        require(tBorrowedToken.repayBorrow(positionBalance) == 0, "repay error");

        TToken tUsdcToken = TToken(tUsdcAddr);
        uint tUsdcBalance = tUsdcToken.balanceOf(address(this));
        require(tUsdcToken.redeem(tUsdcBalance) == 0, "redeem usdc error");
        usdcToken.transfer(msg.sender, usdcToken.balanceOf(address(this)));
    }
}
