// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Utilities} from "../../utils/Utilities.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WETH9} from "../../../src/Contracts/WETH9.sol";

import {
    IUniswapV3Factory,
    IUniswapV3Pool,
    INonfungiblePositionManager
} from "../../../src/Contracts/puppet-v3/Interfaces.sol";

import {PuppetV3Pool} from "../../../src/Contracts/puppet-v3/PuppetV3Pool.sol";

contract PuppetV3 is Test {
    using FixedPointMathLib for uint256;

    string ETH_RPC_URL;
    uint256 mainnetFork;

    // Initial liquidity amounts for Uniswap v3 pool
    uint256 internal constant UNISWAP_INITIAL_TOKEN_LIQUIDITY = 100e18;
    uint256 internal constant UNISWAP_INITIAL_WETH_LIQUIDITY = 100e18;

    uint256 internal constant ATTACKER_INITIAL_TOKEN_BALANCE = 110e18;
    uint256 internal constant ATTACKER_INITIAL_ETH_BALANCE = 1e18;
    uint256 internal constant DEPLOYER_INITIAL_ETH_BALANCE = 200e18;

    uint256 internal constant LENDING_POOL_INITIAL_TOKEN_BALANCE = 1000000e18;

    INonfungiblePositionManager internal uniswapPositionManager;
    uint24 internal constant FEE = 3000; // 0.3%

    IUniswapV3Factory internal uniswapV3Factory;
    IUniswapV3Pool internal uniswapV3Pool;

    DamnValuableToken internal dvt;
    WETH9 internal weth;

    PuppetV3Pool internal puppetV3Pool;

    address payable internal attacker;
    address payable internal deployer;

    uint256 internal initialBlockTimestamp;

    function encodePriceSqrt(uint256 reserve0, uint256 reserve1) internal pure returns (uint160) {
        require(reserve0 > 0 && reserve1 > 0, "R");
        uint256 ratio = reserve1 / reserve0;
        return uint160(FixedPointMathLib.sqrt(ratio) * 2 ** 96);
    }

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */
        ETH_RPC_URL = vm.envString("ETH_RPC_URL");
        mainnetFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(mainnetFork);

        // Initialize player account
        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");
        vm.deal(attacker, ATTACKER_INITIAL_ETH_BALANCE);

        // Initialize deployer account
        deployer = payable(address(uint160(uint256(keccak256(abi.encodePacked("deployer"))))));
        vm.label(deployer, "deployer");

        // Get a reference to the Uniswap V3 Factory contract
        uniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

        // Deploy token to be traded in Uniswap
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        weth = new WETH9();
        vm.label(address(weth), "WETH");

        // Set deployer WETH and DVT balances
        deal(address(weth), deployer, UNISWAP_INITIAL_WETH_LIQUIDITY);
        deal(address(dvt), deployer, UNISWAP_INITIAL_TOKEN_LIQUIDITY);

        uniswapPositionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        uniswapPositionManager.createAndInitializePoolIfNecessary(
            address(weth), address(dvt), FEE, encodePriceSqrt(1, 1)
        );

        uniswapV3Pool = IUniswapV3Pool(uniswapV3Factory.getPool(address(weth), address(dvt), FEE));
        uniswapV3Pool.increaseObservationCardinalityNext(40);

        // Start prank
        vm.startPrank(deployer, deployer);

        // Deployer adds liquidity at current price to Uniswap V3 exchange
        weth.approve(address(uniswapPositionManager), type(uint256).max);
        dvt.approve(address(uniswapPositionManager), type(uint256).max);

        uniswapPositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(weth),
                token1: address(dvt),
                tickLower: -60,
                tickUpper: 60,
                fee: FEE,
                amount0Desired: UNISWAP_INITIAL_WETH_LIQUIDITY,
                amount1Desired: UNISWAP_INITIAL_TOKEN_LIQUIDITY,
                amount0Min: 0,
                amount1Min: 0,
                recipient: deployer,
                deadline: block.timestamp * 2
            })
        );

        // Deploy the lending pool
        puppetV3Pool = new PuppetV3Pool(address(weth), address(dvt), address(uniswapV3Pool));

        // Setup initial token balances of lending pool and player
        deal(address(dvt), attacker, ATTACKER_INITIAL_TOKEN_BALANCE);
        deal(address(dvt), address(puppetV3Pool), LENDING_POOL_INITIAL_TOKEN_BALANCE);

        // Some time passes
        vm.warp(block.timestamp + 3 days);

        // Ensure oracle in lending pool is working as expected. At this point, DVT/WETH price should be 1:1.
        // To borrow 1 DVT, must deposit 3 ETH
        assertEq(puppetV3Pool.calculateDepositOfWETHRequired(1e18), 3e18);

        // To borrow all DVT in lending pool, user must deposit three times its value
        assertEq(
            puppetV3Pool.calculateDepositOfWETHRequired(LENDING_POOL_INITIAL_TOKEN_BALANCE),
            LENDING_POOL_INITIAL_TOKEN_BALANCE * 3
        );

        // Ensure player doesn't have that much ETH
        assertLt(attacker.balance, LENDING_POOL_INITIAL_TOKEN_BALANCE * 3);

        initialBlockTimestamp = block.timestamp;
        
        vm.stopPrank();

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */

        // Block timestamp must not have changed too much
        assertLt(block.timestamp - initialBlockTimestamp, 115, "Too much time passed");

        // Player has taken all tokens out of the pool
        assertEq(dvt.balanceOf(address(puppetV3Pool)), 0);
        assertGe(dvt.balanceOf(attacker), LENDING_POOL_INITIAL_TOKEN_BALANCE);
    }
}
