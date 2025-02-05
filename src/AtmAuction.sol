// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DutchAuction} from "./DutchAuction.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./DutchAuction.sol";

contract AtmAuction is DutchAuction {
    constructor(address _ethStrategy, address _governor, address _paymentToken)
        DutchAuction(_ethStrategy, _governor, _paymentToken)
    {}

    function _fill(uint128 amountOut, uint128 amountIn, uint64, uint64) internal override {
        SafeTransferLib.safeTransferFrom(paymentToken, msg.sender, owner(), amountIn);
        IEthStrategy(ethStrategy).mint(msg.sender, amountOut);
    }
}
