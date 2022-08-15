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

        TToken tPositionToken = TToken(tPositionTokenAddr);
        IERC20 positionToken = IERC20(tPositionToken.underlying());

        if (usdcToken.allowance(address(this), tUsdcAddr) == 0) {
            usdcToken.approve(tUsdcAddr, type(uint).max);
        }

        if (positionToken.allowance(address(this), vvsRouterAddr) == 0) {
            positionToken.approve(vvsRouterAddr, type(uint).max);
        }

        usdcToken.transferFrom(msg.sender, address(this), usdcAmount);

        uint positionTokenPrice = priceOracle.getUnderlyingPrice(tPositionTokenAddr);
        uint usdcPrice = priceOracle.getUnderlyingPrice(tUsdcAddr);

        uint leftUsdcAmount = usdcAmount;
        for (uint i = rounds; i > 0; i--) {
            leftUsdcAmount = _short(leftUsdcAmount, usdcPrice, tPositionToken, positionTokenPrice, i);
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
            console.log("long round: %s", i);
            uint positionTokenAmount = _long(availableUsdcAmount, tPositionToken, positionToken);
            if (i == rounds - 1) break;
            availableUsdcAmount = positionTokenAmount * positionTokenPrice * 6 / 10 / usdcPrice;
            require(tUsdcToken.borrow(availableUsdcAmount) == 0, "Trader: borrow failed");
            console.log("borrow usdc amount: %s", availableUsdcAmount);
        }
    }

    function _long(uint usdcAmount, TToken tPositionToken, IERC20 positionToken) private returns (uint) {
        console.log("spend usdc amount: %s", usdcAmount);
        uint positionTokenAmount = swapExactTokensForTokens(usdcAmount, usdcAddr, address(positionToken), address(this));
        console.log("supply collateral eth amount: %s", positionTokenAmount);
        supplyAsCollateral(tPositionToken, positionTokenAmount);
        return positionTokenAmount;
    }

    function supplyAsCollateral(TToken tToken, uint amount) private {
        require(tToken.mint(amount) == 0, "Trader: supply token failed");
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

    function _short(uint usdcAmount, uint usdcPrice, TToken tPositionToken, uint positionTokenPrice, uint round) private returns (uint) {
        supplyAsCollateral(tUsdcToken, usdcAmount);
        uint positionTokenAmount = usdcAmount * usdcPrice * 6 / 10 / positionTokenPrice;
        require(tPositionToken.borrow(positionTokenAmount) == 0, "Trader: borrow failed");
        address swapTo = round == 1 ? msg.sender : address(this);
        return swapExactTokensForTokens(positionTokenAmount, tPositionToken.underlying(), usdcAddr, swapTo);
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

    function close(address tCollateralTokenAddr, address tBorrowTokenAddr) public {
        TToken tCollateralToken = TToken(tCollateralTokenAddr);
        IERC20 collateralToken = IERC20(tCollateralToken.underlying());

        TToken tBorrowToken = TToken(tBorrowTokenAddr);
        IERC20 borrowToken = IERC20(tBorrowToken.underlying());

        if (collateralToken.allowance(address(this), vvsRouterAddr) == 0) {
            collateralToken.approve(vvsRouterAddr, type(uint).max);
        }

        if (borrowToken.allowance(address(this), tBorrowTokenAddr) == 0) {
            borrowToken.approve(tBorrowTokenAddr, type(uint).max);
        }

        uint collateralBalance = tCollateralToken.balanceOfUnderlying(address(this));
        uint borrowBalance = tBorrowToken.borrowBalanceCurrent(address(this));

        uint collateralTokenPrice = priceOracle.getUnderlyingPrice(tCollateralTokenAddr);
        uint borrowTokenPrice = priceOracle.getUnderlyingPrice(tBorrowTokenAddr);
        (, uint collateralFactor,) = tectonic.markets(tCollateralTokenAddr);

        console.log("collateralTokenPrice: %s", collateralTokenPrice);
        console.log("borrowTokenPrice: %s", borrowTokenPrice);
        console.log("collateralFactor: %s", collateralFactor);

        console.log("collateralBalance: %s", collateralBalance);
        console.log("borrowBalance: %s", borrowBalance);
        uint netUsd = (collateralBalance * collateralTokenPrice - borrowBalance * borrowTokenPrice) / borrowTokenPrice;
        console.log("net USDC: %s", netUsd);

        for (uint i = 0; i < 3; i++) {
            console.log("repay round: %s", i);

            uint collateralInUSD = collateralBalance * collateralTokenPrice;
            uint borrowInUSD = borrowBalance * borrowTokenPrice;
            uint withdrawCollateralAmount = (collateralInUSD - borrowInUSD * 1e18 / collateralFactor) / collateralTokenPrice;
            tCollateralToken.redeemUnderlying(withdrawCollateralAmount);
            console.log("redeem collateral: %s", withdrawCollateralAmount);
            uint swappedBorrowTokenAmount = swapExactTokensForTokens(withdrawCollateralAmount, address(collateralToken), usdcAddr, address(this));
            console.log("swapped collateral to get borrow token: %s", swappedBorrowTokenAmount);

            uint repayAmount = swappedBorrowTokenAmount >= borrowBalance ? borrowBalance : swappedBorrowTokenAmount;
            tBorrowToken.repayBorrow(repayAmount);
            console.log("repay amount: %s", repayAmount);
            borrowBalance = borrowBalance - repayAmount;
            collateralBalance = collateralBalance - withdrawCollateralAmount;
            console.log("collateralBalance: %s", collateralBalance);
            console.log("borrowBalance: %s", borrowBalance);
            if(borrowBalance == 0) break;
        }

        if (borrowBalance > 0) {
            console.log("transfer USDC from msg.sender: %s", borrowBalance);
            usdcToken.transferFrom(msg.sender, address(this), borrowBalance);
            console.log("repay amount: %s", borrowBalance);
            tBorrowToken.repayBorrow(borrowBalance);
        }

        tCollateralToken.redeemUnderlying(collateralBalance);
        console.log("redeem collateral: %s", collateralBalance);
        uint swappedBorrowTokenAmount = swapExactTokensForTokens(collateralBalance, address(collateralToken), usdcAddr, address(this));
        console.log("swapped collateral to get borrow token: %s", swappedBorrowTokenAmount);
        uint usdcBalance = usdcToken.balanceOf(address(this));
        usdcToken.transfer(msg.sender, usdcBalance);
        console.log("transfer USDC back to user: %s", usdcBalance);
    }
}
