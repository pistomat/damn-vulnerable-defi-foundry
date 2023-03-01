// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {AuthorizedExecutor} from "../../../src/Contracts/abi-smuggling/AuthorizedExecutor.sol";
import {SelfAuthorizedVault} from "../../../src/Contracts/abi-smuggling/SelfAuthorizedVault.sol";

import "forge-std/Test.sol";

contract ABISmuggling is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    SelfAuthorizedVault internal vault;

    address[] internal users;
    address payable internal deployer;
    address payable internal recovery;
    address payable internal attacker;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(2);

        deployer = payable(users[0]);
        vm.label(deployer, "Deployer");
        recovery = payable(users[1]);
        vm.label(recovery, "Recovery");

        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        vm.startPrank(deployer, deployer);

        // Deploy Damn Valuable Token contract
        dvt = new DamnValuableToken();

        // Deploy Vault
        vault = new SelfAuthorizedVault();

        assertGt(vault.getLastWithdrawalTimestamp(), 0);

        // Set permissions
        bytes32 deployerPermission = vault.getActionId(bytes4(0x85fb709d), deployer, address(vault));
        bytes32 attackerPermission = vault.getActionId(bytes4(0xd9caed12), attacker, address(vault));

        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = attackerPermission;
        vault.setPermissions(permissions);

        assertTrue(vault.permissions(deployerPermission));
        assertTrue(vault.permissions(attackerPermission));

        // Make sure Vault is initialized
        assertTrue(vault.initialized());

        // Deposit tokens into the vault
        dvt.transfer(address(vault), VAULT_TOKEN_BALANCE);

        assertEq(dvt.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(attacker)), 0);

        vm.stopPrank();

        // Cannot call Vault directly
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(dvt)));

        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(dvt), attacker, 10 ** 18);
    }
}
