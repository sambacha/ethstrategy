// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

interface IEthStrategy {
    function mint(address _to, uint256 _amount) external;
}

abstract contract DutchAuction is OwnableRoles {
    error AuctionAlreadyActive();
    error AuctionNotActive();
    error InvalidStartPrice();
    error AmountExceedsSupply();
    
    struct Auction {
        uint64 startTime;
        uint64 duration;
        uint128 startPrice;
        uint128 endPrice;
        uint128 amount;
    }

    Auction public auction;

    address public immutable ethStrategy;
    address public immutable paymentToken;
    uint8 constant decimals = 18;

    event AuctionStarted(Auction auction);

    constructor(
        address _ethStrategy,
        address _governor,
        address _paymentToken
    ) {
        ethStrategy = _ethStrategy;
        paymentToken = _paymentToken;
        _initializeOwner(_governor);
        _grantRoles(msg.sender, 1);
    }

    function startAuction(
        uint64 _offset,
        uint64 _duration,
        uint128 _startPrice,
        uint128 _endPrice,
        uint128 _amount
    ) public onlyOwnerOrRoles(1) {
        uint256 currentTime = block.timestamp;
        Auction memory _auction = auction;
        if (isAuctionActive(_auction, currentTime)) {
            revert AuctionAlreadyActive();
        }
        if (_startPrice < _endPrice || _endPrice == 0) {
            revert InvalidStartPrice();
        }
        auction = Auction({
            startTime: uint64(currentTime + _offset),
            duration: _duration,
            startPrice: _startPrice,
            endPrice: _endPrice,
            amount: _amount
        });

        emit AuctionStarted(_auction);
    }

    function fill(uint128 _amount) public {
        Auction memory _auction = auction;
        uint256 currentTime = block.timestamp;
        if (!isAuctionActive(_auction, currentTime)) {
            revert AuctionNotActive();
        }
        if (_amount > _auction.amount) {
            revert AmountExceedsSupply();
        }
        uint128 currentPrice = _getCurrentPrice(_auction, currentTime);
        auction.amount = _auction.amount - _amount;
        _fill(_amount, currentPrice);
    }

    function _fill(uint128 amount, uint128 price) internal virtual;

    function isAuctionActive(
        Auction memory _auction,
        uint256 currentTime
    ) public pure returns (bool) {
        return
            _auction.startTime > 0 &&
            _auction.startTime + _auction.duration > currentTime &&
            currentTime >= _auction.startTime;
    }

    function _getCurrentPrice(
        Auction memory _auction,
        uint256 currentTime
    ) internal pure returns (uint128) {
        uint256 delta_p = _auction.startPrice - _auction.endPrice;
        uint256 delta_t = currentTime - _auction.startTime;
        return
            uint128(
                ((delta_p * delta_t) / _auction.duration) + _auction.endPrice
            );
    }

    function getCurrentPrice(
        uint256 currentTime
    ) external view returns (uint128) {
        Auction memory _auction = auction;
        return _getCurrentPrice(_auction, currentTime);
    }

    function isAuctionActive(
        uint256 currentTime
    ) external view returns (bool) {
        Auction memory _auction = auction;
        return isAuctionActive(_auction, currentTime);
    }
}