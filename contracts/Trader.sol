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

        approveSpendToken(usdcToken, tUsdcAddr);
        approveSpendToken(positionToken, vvsRouterAddr);

        usdcToken.transferFrom(msg.sender, address(this), usdcAmount);

        uint positionTokenPrice = priceOracle.getUnderlyingPrice(tPositionTokenAddr);
        uint usdcPrice = priceOracle.getUnderlyingPrice(tUsdcAddr);

        uint leftUsdcAmount = usdcAmount;
        for (uint i = 0; i < rounds; i++) {
            leftUsdcAmount = _short(leftUsdcAmount, usdcPrice, tPositionToken, positionTokenPrice);
        }
        supplyAsCollateral(tUsdcToken, leftUsdcAmount);
    }

    function _short(uint usdcAmount, uint usdcPrice, TToken tPositionToken, uint positionTokenPrice) private returns (uint) {
        supplyAsCollateral(tUsdcToken, usdcAmount);
        uint positionTokenAmount = usdcAmount * usdcPrice * 6 / 10 / positionTokenPrice;
        require(tPositionToken.borrow(positionTokenAmount) == 0, "Trader: borrow failed");
        return swapExactTokensForTokens(positionTokenAmount, tPositionToken.underlying(), usdcAddr, address(this));
    }

    function long(uint usdcAmount, address tPositionTokenAddr, uint rounds) external {
        require(rounds > 0 && rounds <= 4, "Trader: rounds must be within [1, 4]");
        TToken tPositionToken = TToken(tPositionTokenAddr);
        IERC20 positionToken = IERC20(tPositionToken.underlying());

        approveSpendToken(usdcToken, vvsRouterAddr);
        approveSpendToken(positionToken, tPositionTokenAddr);

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


    function getClosePositionAmount(address tTokenAddr) public returns (uint) {
        TToken tToken = TToken(tTokenAddr);

        uint borrowBalance = tToken.borrowBalanceCurrent(address(this));

        address[] memory path = new address[](2);
        path[0] = usdcAddr;
        path[1] = tToken.underlying();

        uint[] memory amounts = vvsRouter.getAmountsIn(borrowBalance, path);
        return amounts[0];
    }

    function needAmountIn(address inTokenAddr, address outTokenAddr, uint outAmount) private view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = inTokenAddr;
        path[1] = outTokenAddr;

        uint[] memory amounts = vvsRouter.getAmountsIn(outAmount, path);
        return amounts[0];
    }

    function closeShortPosition(address tBorrowedTokenAddr) external {
        TToken tBorrowedToken = TToken(tBorrowedTokenAddr);
        IERC20 borrowedToken = IERC20(tBorrowedToken.underlying());

        approveSpendToken(usdcToken, vvsRouterAddr);
        approveSpendToken(borrowedToken, tBorrowedTokenAddr);

        uint collateralBalance = tUsdcToken.balanceOfUnderlying(address(this));
        uint borrowBalance = tBorrowedToken.borrowBalanceCurrent(address(this));

        uint collateralTokenPrice = priceOracle.getUnderlyingPrice(tUsdcAddr);
        uint borrowTokenPrice = priceOracle.getUnderlyingPrice(tBorrowedTokenAddr);
        (, uint collateralFactor,) = tectonic.markets(tUsdcAddr);

        uint collateralInUSD = collateralBalance * collateralTokenPrice;
        uint borrowInUSD = borrowBalance * borrowTokenPrice;

        require(collateralInUSD > borrowInUSD, "Trader: collateral less than loan");

        borrowBalance -= ensure30PercentOfBorrowRepayForShort(collateralInUSD, borrowInUSD, collateralFactor, borrowTokenPrice, tBorrowedToken);

        for (uint i = 0; i < 3; i++) {
            console.log("round: %s", i);
            uint withdrawCollateralAmount = (collateralInUSD - borrowInUSD * 1e18 / collateralFactor) / collateralTokenPrice;
            tUsdcToken.redeemUnderlying(withdrawCollateralAmount);
            console.log("redeemed USDC: %s", withdrawCollateralAmount);
            uint needCollateralAmount = needAmountIn(usdcAddr, address(borrowedToken), borrowBalance);
            needCollateralAmount = needCollateralAmount > withdrawCollateralAmount ? withdrawCollateralAmount : needCollateralAmount;
            uint swappedBorrowTokenAmount = swapExactTokensForTokens(needCollateralAmount, usdcAddr, address(borrowedToken), address(this));
            console.log("swapped ETH: %s", swappedBorrowTokenAmount);

            uint repayAmount = swappedBorrowTokenAmount >= borrowBalance ? borrowBalance : swappedBorrowTokenAmount;
            tBorrowedToken.repayBorrow(repayAmount);
            console.log("repay ETH: %s", repayAmount);
            borrowBalance = borrowBalance - repayAmount;
            collateralBalance = collateralBalance - withdrawCollateralAmount;
            borrowInUSD = borrowBalance * borrowTokenPrice;
            collateralInUSD = collateralBalance * collateralTokenPrice;
            console.log("collateral balance: %s", collateralBalance);
            console.log("borrow balance: %s", borrowBalance);
            if (borrowBalance == 0) break;
        }

        if (borrowBalance > 0) {
            // TODO: not likely to happen
        }

        tUsdcToken.redeemUnderlying(collateralBalance);
        console.log("final redeem USDC: %s", collateralBalance);
        uint usdcBalance = usdcToken.balanceOf(address(this));
        console.log("transfer USDC back: %s", usdcBalance);
        usdcToken.transfer(msg.sender, usdcBalance);
    }

    function approveSpendToken(IERC20 token, address spender) private {
        if (token.allowance(address(this), spender) == 0) {
            token.approve(spender, type(uint).max);
        }
    }

    function closeLongPosition(address tCollateralTokenAddr) public {
        TToken tCollateralToken = TToken(tCollateralTokenAddr);
        IERC20 collateralToken = IERC20(tCollateralToken.underlying());

        approveSpendToken(collateralToken, vvsRouterAddr);
        approveSpendToken(usdcToken, tUsdcAddr);

        uint collateralBalance = tCollateralToken.balanceOfUnderlying(address(this));
        uint borrowBalance = tUsdcToken.borrowBalanceCurrent(address(this));

        uint collateralTokenPrice = priceOracle.getUnderlyingPrice(tCollateralTokenAddr);
        uint borrowTokenPrice = priceOracle.getUnderlyingPrice(tUsdcAddr);
        (, uint collateralFactor,) = tectonic.markets(tCollateralTokenAddr);

        uint collateralInUSD = collateralBalance * collateralTokenPrice;
        uint borrowInUSD = borrowBalance * borrowTokenPrice;

        require(collateralInUSD > borrowInUSD, "Trader: collateral less than loan");

        borrowBalance -= ensure30PercentOfBorrowRepayForLong(collateralInUSD, borrowInUSD, collateralFactor, borrowTokenPrice);

        for (uint i = 0; i < 3; i++) {
            uint withdrawCollateralAmount = (collateralInUSD - borrowInUSD * 1e18 / collateralFactor) / collateralTokenPrice;
            tCollateralToken.redeemUnderlying(withdrawCollateralAmount);
            uint swappedBorrowTokenAmount = swapExactTokensForTokens(withdrawCollateralAmount, address(collateralToken), usdcAddr, address(this));

            uint repayAmount = swappedBorrowTokenAmount >= borrowBalance ? borrowBalance : swappedBorrowTokenAmount;
            tUsdcToken.repayBorrow(repayAmount);
            borrowBalance = borrowBalance - repayAmount;
            collateralBalance = collateralBalance - withdrawCollateralAmount;
            borrowInUSD = borrowBalance * borrowTokenPrice;
            collateralInUSD = collateralBalance * collateralTokenPrice;
            if (borrowBalance == 0) break;
        }

        if (borrowBalance > 0) {
            usdcToken.transferFrom(msg.sender, address(this), borrowBalance);
            tUsdcToken.repayBorrow(borrowBalance);
        }

        tCollateralToken.redeemUnderlying(collateralBalance);
        swapExactTokensForTokens(collateralBalance, address(collateralToken), usdcAddr, address(this));
        uint usdcBalance = usdcToken.balanceOf(address(this));
        usdcToken.transfer(msg.sender, usdcBalance);
    }

    function ensure30PercentOfBorrowRepayForLong(uint collateralInUSD, uint borrowInUSD, uint collateralFactor, uint borrowTokenPrice) private returns (uint) {
        uint repayAmount;
        // below required collateral
        if (collateralInUSD <= borrowInUSD * 1e18 / collateralFactor) {
            uint overBorrowedInUSD = borrowInUSD - collateralInUSD * collateralFactor / 1e18;
            repayAmount = ((borrowInUSD - overBorrowedInUSD) * 3 / 10 + overBorrowedInUSD) / borrowTokenPrice;
        } else {
            // available collateral below 30% of borrow
            uint availableCollateralInUSD = collateralInUSD - borrowInUSD * 1e18 / collateralFactor;
            uint borrow30PercentInUSD = borrowInUSD * 3 / 10;
            if (availableCollateralInUSD < borrow30PercentInUSD) {
                repayAmount = (borrow30PercentInUSD - availableCollateralInUSD) / borrowTokenPrice;
            }
        }

        if (repayAmount > 0) {
            usdcToken.transferFrom(msg.sender, address(this), repayAmount);
            tUsdcToken.repayBorrow(repayAmount);
        }

        return repayAmount;
    }

    function ensure30PercentOfBorrowRepayForShort(uint collateralInUSD, uint borrowInUSD, uint collateralFactor, uint borrowTokenPrice, TToken tBorrowToken) private returns (uint) {
        uint repayAmount;
        // below required collateral
        if (collateralInUSD <= borrowInUSD * 1e18 / collateralFactor) {
            uint overBorrowedInUSD = borrowInUSD - collateralInUSD * collateralFactor / 1e18;
            repayAmount = ((borrowInUSD - overBorrowedInUSD) * 3 / 10 + overBorrowedInUSD) / borrowTokenPrice;
        } else {
            // available collateral below 30% of borrow
            uint availableCollateralInUSD = collateralInUSD - borrowInUSD * 1e18 / collateralFactor;
            uint borrow30PercentInUSD = borrowInUSD * 3 / 10;
            if (availableCollateralInUSD < borrow30PercentInUSD) {
                repayAmount = (borrow30PercentInUSD - availableCollateralInUSD) / borrowTokenPrice;
            }
        }

        console.log("pre repay amount: %s", repayAmount);

        if (repayAmount > 0) {
            address borrowTokenAddr = tBorrowToken.underlying();
            uint needUsdcAmount = needAmountIn(usdcAddr, borrowTokenAddr, repayAmount);
            usdcToken.transferFrom(msg.sender, address(this), needUsdcAmount);
            uint swappedBorrowTokenAmount = swapExactTokensForTokens(needUsdcAmount, usdcAddr, borrowTokenAddr, address(this));
            tBorrowToken.repayBorrow(repayAmount);
        }
        return repayAmount;
    }
}