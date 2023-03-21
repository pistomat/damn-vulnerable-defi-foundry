# Challenge #15 - ABI Smuggling
There’s a permissioned vault with 1 million DVT tokens deposited. The vault allows withdrawing funds periodically, as well as taking all funds out in case of emergencies.

The contract has an embedded generic authorization scheme, only allowing known accounts to execute specific actions.

The dev team has received a responsible disclosure saying all funds can be stolen.

Before it’s too late, rescue all funds from the vault, transferring them back to the recovery account.

[See the contracts](https://github.com/pistomat/damn-vulnerable-defi-foundry/tree/master/src/Contracts/abi-smuggling)
<br/>
[Complete the challenge](https://github.com/pistomat/damn-vulnerable-defi-foundry/blob/master/test/Levels/abi-smuggling/ABISmuggling.t.sol)

