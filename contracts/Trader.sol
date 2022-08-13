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
    address constant vvsRouterAddr = 0x145863Eb42Cf62847A6Ca784e6416C1682b1b2Ae;

    PriceOracle constant priceOracle = PriceOracle(0xD360D8cABc1b2e56eCf348BFF00D2Bd9F658754A);
    IVVSRouter02 constant vvsRouter = IVVSRouter02(0x145863Eb42Cf62847A6Ca784e6416C1682b1b2Ae);
    TectonicCoreInterface constant tectonic = TectonicCoreInterface(0xb3831584acb95ED9cCb0C11f677B5AD01DeaeEc0);
    IERC20 usdcToken = IERC20(usdcAddr);
    TToken tUsdcToken = TToken(tUsdcAddr);

    function short(uint usdcAmount, address tPositionTokenAddr, uint rounds) external {
        require(rounds > 0 && rounds <= 4, "Trader: rounds must be within [1, 4]");

        usdcToken.transferFrom(msg.sender, address(this), usdcAmount);

        if (usdcToken.allowance(address(this), tUsdcAddr) < usdcAmount) {
            usdcToken.approve(tUsdcAddr, type(uint).max);
        }

        uint positionTokenPrice = priceOracle.getUnderlyingPrice(tPositionTokenAddr);
        uint usdcPrice = priceOracle.getUnderlyingPrice(tUsdcAddr);

        uint leftUsdcAmount = usdcAmount;
        for (uint i = rounds; i > 0; i--) {
            leftUsdcAmount = _short(leftUsdcAmount, usdcPrice, tPositionTokenAddr, positionTokenPrice, i);
        }
    }

    function long(uint usdcAmount, address tPositionTokenAddr, uint rounds) external {
        require(rounds > 0 && rounds <= 4, "Trader: rounds must be within [1, 4]");
        TToken tPositionToken = TToken(tPositionTokenAddr);
        IERC20 positionToken = IERC20(tPositionToken.underlying());

        if (usdcToken.allowance(address(this), vvsRouterAddr) == 0) {
            usdcToken.approve(vvsRouterAddr, type(uint).max);
        }

        if (positionToken.allowance(address(this), tPositionTokenAddr) == 0) {
            positionToken.approve(tPositionTokenAddr, type(uint).max);
        }

        require(usdcToken.transferFrom(msg.sender, address(this), usdcAmount), "Trader: transfer USDC failed");

        uint positionTokenPrice = priceOracle.getUnderlyingPrice(tPositionTokenAddr);
        uint usdcPrice = priceOracle.getUnderlyingPrice(tUsdcAddr);

        uint availableUsdcAmount = usdcAmount;
        for (uint i = 0; i < rounds; i++) {
            uint positionTokenAmount = _long(availableUsdcAmount, tPositionTokenAddr);
            if (i == rounds - 1) break;
            availableUsdcAmount = positionTokenAmount * positionTokenPrice * 6 / 10 / usdcPrice;
            require(tUsdcToken.borrow(availableUsdcAmount) == 0, "Trader: borrow failed");
        }
    }

    function _long(uint usdcAmount, address tPositionTokenAddr) private returns (uint) {
        uint positionTokenAmount = swapExactTokensForTokens(usdcAmount, usdcAddr, tPositionTokenAddr, address(this));
        supplyAsCollateral(tPositionTokenAddr, positionTokenAmount);
        return positionTokenAmount;
    }

    function supplyAsCollateral(address tTokenAddr, uint amount) private {
        TToken tToken = TToken(tTokenAddr);
        tToken.mint(amount);
        address[] memory tTokens = new address[](1);
        tTokens[0] = address(tToken);
        tectonic.enterMarkets(tTokens);
    }

    function swapExactTokensForTokens(uint amountIn, address srcToken, address targetToken, address to) private returns (uint) {
        address[] memory path = new address[](2);
        path[0] = srcToken;
        path[1] = targetToken;
        uint[] memory amounts = vvsRouter.swapExactTokensForTokens(amountIn, 0, path, to, block.timestamp + 3 minutes);
        return amounts[1];
    }

    function _short(uint usdcAmount, uint usdcPrice, address tPositionTokenAddr, uint positionTokenPrice, uint round) private returns (uint) {
        TToken tPositionToken = TToken(tPositionTokenAddr);
        IERC20 positionToken = IERC20(tPositionToken.underlying());

        // supply USDC and enable collateral
        tUsdcToken.mint(usdcAmount);
        address[] memory tTokens = new address[](1);
        tTokens[0] = tUsdcAddr;
        tectonic.enterMarkets(tTokens);

        uint positionTokenAmount = usdcAmount * usdcPrice * 6 / 10 / positionTokenPrice;

        // borrow position token
        require(tPositionToken.borrow(positionTokenAmount) == 0, "Trader: borrow failed");

        // sell position to get USDC
        if (positionToken.allowance(address(this), vvsRouterAddr) < positionTokenAmount) {
            positionToken.approve(vvsRouterAddr, type(uint).max);
        }
        address[] memory path = new address[](2);
        path[0] = address(positionToken);
        path[1] = usdcAddr;
        address swapTo = round == 1 ? msg.sender : address(this);
        uint[] memory amounts = vvsRouter.swapExactTokensForTokens(positionTokenAmount, 0, path, swapTo, block.timestamp + 3 minutes);
        return amounts[1];
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

        uint positionBalance = tBorrowedToken.borrowBalanceCurrent(address(this));

        address[] memory path = new address[](2);
        path[0] = usdcAddr;
        path[1] = address(borrowedToken);

        uint[] memory amounts = vvsRouter.getAmountsIn(positionBalance, path);
        uint needUsdcAmount = amounts[0];
        require(usdcToken.balanceOf(msg.sender) >= needUsdcAmount, "Trader: not enough USDC to close the position");

        usdcToken.transferFrom(msg.sender, address(this), needUsdcAmount);

        if (usdcToken.allowance(address(this), vvsRouterAddr) < needUsdcAmount) {
            usdcToken.approve(vvsRouterAddr, type(uint).max);
        }
        vvsRouter.swapTokensForExactTokens(positionBalance, amounts[0], path, address(this), block.timestamp + 3 minutes);

        if (borrowedToken.allowance(address(this), tBorrowedTokenAddr) < positionBalance) {
            borrowedToken.approve(tBorrowedTokenAddr, type(uint).max);
        }
        require(tBorrowedToken.repayBorrow(positionBalance) == 0, "Trader: repay borrow error");

        uint tUsdcBalance = tUsdcToken.balanceOf(address(this));
        require(tUsdcToken.redeem(tUsdcBalance) == 0, "Trader: redeem usdc error");
        usdcToken.transfer(msg.sender, usdcToken.balanceOf(address(this)));
    }
}
