// SPDX-License-Identifier: MIT

pragma solidity >= 0.5.16;

interface PriceOracle {
  function getUnderlyingPrice(address tToken) external view returns (uint);
}
