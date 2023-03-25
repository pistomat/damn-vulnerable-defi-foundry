// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {AuthorizerUpgradeable} from "../../../src/Contracts/wallet-mining/AuthorizerUpgradeable.sol";
import {WalletDeployer} from "../../../src/Contracts/wallet-mining/WalletDeployer.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract WalletMining is Test {
    address internal constant DEPOSIT_ADDRESS = 0x9B6fb606A9f5789444c17768c6dFCF2f83563801;
    uint256 internal constant DEPOSIT_TOKEN_AMOUNT = 20000000e18;

    address payable internal attacker;
    address payable internal deployer;
    address payable internal ward;

    DamnValuableToken internal dvt;
    AuthorizerUpgradeable internal authorizerImplementation;
    WalletDeployer internal walletDeployer;
    TransparentUpgradeableProxy internal uups;
    AuthorizerUpgradeable internal authorizer;

    uint256 internal initialWalletDeployerTokenBalance;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        // Initialize player account
        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");

        // Initialize deployer account
        deployer = payable(address(uint160(uint256(keccak256(abi.encodePacked("deployer"))))));
        vm.label(deployer, "Deployer");

        // Initialize ward account
        ward = payable(address(uint160(uint256(keccak256(abi.encodePacked("ward"))))));
        vm.label(ward, "Ward");

        // Deploy Damn Valuable Token contract
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        vm.startPrank(deployer, deployer);

        // Deploy authorizer with the corresponding proxy
        authorizerImplementation = new AuthorizerUpgradeable();
        vm.label(address(authorizerImplementation), "AuthorizerImplementation");

        address[] memory _wards = new address[](1);
        _wards[0] = ward;
        address[] memory _aims = new address[](1);
        _aims[0] = DEPOSIT_ADDRESS;
        uups = new TransparentUpgradeableProxy({
            _logic: address(authorizerImplementation),
            admin_: deployer,
            _data: abi.encodeWithSignature("init(address[],address[])", _wards, _aims)
        });
        vm.label(address(uups), "UUPS");
        authorizer = AuthorizerUpgradeable(address(uups));
        vm.label(address(authorizer), "Authorizer");

        vm.stopPrank();

        assertEq(authorizer.owner(), deployer);
        assertTrue(authorizer.can(ward, DEPOSIT_ADDRESS));
        assertTrue(!authorizer.can(attacker, DEPOSIT_ADDRESS));

        vm.startPrank(deployer, deployer);

        // Deploy Safe Deployer contract
        walletDeployer = new WalletDeployer({_gem: address(dvt)});
        vm.label(address(walletDeployer), "WalletDeployer");

        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(), address(dvt));

        // Set Authorizer in Safe Deployer
        walletDeployer.rule(address(authorizer));
        assertEq(walletDeployer.mom(), address(authorizer));

        vm.stopPrank();

        walletDeployer.can(ward, DEPOSIT_ADDRESS);
        // vm.expectRevert();
        // walletDeployer.can(attacker, DEPOSIT_ADDRESS);

        // Fund Safe Deployer with tokens
        initialWalletDeployerTokenBalance = walletDeployer.pay() * 43;
        dvt.transfer(address(walletDeployer), initialWalletDeployerTokenBalance);

        // Ensure these accounts start empty
        assertEq(DEPOSIT_ADDRESS.code.length, 0);
        assertEq(address(walletDeployer.fact()).code.length, 0);
        assertEq(address(walletDeployer.copy()).code.length, 0);

        // Deposit large amount of DVT tokens to the deposit address
        dvt.transfer(DEPOSIT_ADDRESS, DEPOSIT_TOKEN_AMOUNT);

        // Ensure initial balances are set correctly
        assertEq(dvt.balanceOf(DEPOSIT_ADDRESS), DEPOSIT_TOKEN_AMOUNT);
        assertEq(dvt.balanceOf(address(walletDeployer)), initialWalletDeployerTokenBalance);
        assertEq(dvt.balanceOf(attacker), 0);

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
        // Factory account must have code
        assertGt(address(walletDeployer.fact()).code.length, 0);

        // Master copy account must have code
        assertGt(address(walletDeployer.copy()).code.length, 0);

        // Deposit account must have code
        assertGt(DEPOSIT_ADDRESS.code.length, 0);

        // The deposit address and the Safe Deployer contract must not hold tokens
        assertEq(dvt.balanceOf(DEPOSIT_ADDRESS), 0);
        assertEq(dvt.balanceOf(address(walletDeployer)), 0);

        // Player must own all tokens
        assertEq(dvt.balanceOf(attacker), initialWalletDeployerTokenBalance + DEPOSIT_TOKEN_AMOUNT);
    }
}
