# Leverage Trading with VVS and Tectonic

## Introduction

Support leverage trading with VVS and Tectonic.

## How to Demo

### Prepare

Send USDC to accounts

```shell
hh run scripts/sendUSDC.ts
```

Add liquidity to WETH/USDC liquidity pool

```shell
hh run scripts/addLiquidity.ts 
```

Deploy the contract

```shell
hh run scripts/deploy.ts
```

### Long

Change USD/ETH price to 1000.

```shell
PRICE=1000 hh run scripts/changePrice.ts
```

Open Long position

- Input: 1000 USDC
- Loan to Value Ratio: 60%

| round           | 1st | 2nd | 3rd  | total |
|-----------------|-----|-----|------|-------|
| USDC Borrowed   |     | 600 | 360  | 960   |
| WETH Collateral | 1   | 0.6 | 0.36 | 1.96  |

```shell
hh run scripts/openLongPosition.ts 
```

Change USD/ETH price to 2000.

```shell
PRICE=2000 hh run scripts/changePrice.ts
```

Close long position

Estimate profit: 1000 * 1.96 = 1960.

```shell
hh run scripts/closeLongPosition.ts 
```

### Short

Change USD/ETH price to 1000.

```shell
PRICE=1000 hh run scripts/changePrice.ts
```

Open short position

- Input: 1000 USDC
- Loan to Value Ratio: 60%

| round           | start | 1st | 2nd  | 3rd   | total |
|-----------------|-------|-----|------|-------|-------|
| WETH Borrowed   |       | 0.6 | 0.36 | 0.216 | 1.176 |
| USDC Collateral | 1000  | 600 | 360  | 216   | 2176  |

```shell
hh run scripts/openShortPosition.ts 
```

Change USD/ETH price to 500.

```shell
PRICE=500 hh run scripts/changePrice.ts
```

Close short position

Estimate profit: 500 * 1.176 = 588.

```shell
hh run scripts/closeShortPosition.ts 
```
