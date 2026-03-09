## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

EXPLANATION OF ASSSESSMENT

 multi-signature vault with Merkle-based airdrop claims, a 1-hour timelock on all privileged transactions, and threshold-gated pause/unpause. The original single-file monolith has been decomposed into a modular project and all critical vulnerabilities have been fixed.


IEvictionVault.sol  : Public interface (vault-specific functions)

VaultStorage.sol : Shared storage layout (structs + state vars)

MultiSigBase.sol : Multi-sig lifecycle: submit → confirm → execute

EvictionVault.sol : Concrete implementation with all fixes applied


test/
  EvictionVault.ts           8 positive Hardhat tests
foundry.toml                Forge configuration

legacy/vault.sol.bck: previous existing vault.sol (origianl copy backedup)

Security Fixes

### 1. `setMerkleRoot` — Callable by Anyone

**Original:** any EOA could overwrite the Merkle root and let arbitrary addresses drain airdrop funds.

**Fix:** `setMerkleRoot` is now guarded by the `onlyViaMultisig` modifier, which requires `msg.sender == address(this)`. The only way to satisfy this is to submit an encoded `setMerkleRoot(root)` call as a multisig transaction, obtain the required number of owner confirmations, wait for the 1-hour timelock, and then execute — exactly the same process as any other privileged action.


### 2. `emergencyWithdrawAll` — Public Drain

**Original:** any address could call `emergencyWithdrawAll()` and transfer the entire contract balance to themselves.

**Fix:** same `onlyViaMultisig` guard as above. The function signature was also changed to `emergencyWithdrawAll(address payable recipient)` so the destination address is explicitly set in the multisig proposal rather than being `msg.sender`.


### 3. `pause` / `unpause` — Single-Owner Control

**Original:** any individual owner could pause or unpause the vault unilaterally, enabling a single compromised or rogue key to halt the protocol.

**Fix:** `pause()` / `unpause()` have been replaced with `votePause()` / `voteUnpause()`. Each owner may cast one vote per cycle; the action fires only when the accumulated votes reach the configured `threshold`. Votes are reset after each state transition. This requires the same level of consensus as any other multisig decision.


### 4. `receive()` — Uses `tx.origin`

**Original:** `receive()` credited `tx.origin` instead of `msg.sender`. If a contract forwarded ETH to the vault the funds would be attributed to the originating EOA rather than the forwarding contract, which is incorrect and exploitable.

**Fix:** `receive()` now uses `msg.sender` (same as `deposit()`).


### 5. `withdraw` & `claim` — Uses `.transfer`

**Original:** both functions used `.transfer()`, which forwards a hard-coded 2 300-gas stipend. This breaks when the recipient is a smart contract with any non-trivial `receive()` / `fallback()` logic.

**Fix:** both functions now use low-level `.call{value: amount}("")` and check the boolean return value. `ReentrancyGuard` (`nonReentrant` modifier) has been applied to all ETH-sending functions (`withdraw`, `claim`, `emergencyWithdrawAll`) to mitigate the extra re-entrancy surface introduced by `.call`.



### 6. Timelock Bypass When `threshold == 1`

**Original:** `submitTransaction` always set `executionTime = 0`. The timelock was only started inside `confirmTransaction` when `confirmations == threshold`. For a 1-of-n multisig the submitter's initial confirmation (counted in `submitTransaction`) already satisfied `threshold`, so `confirmTransaction` was never called and `executionTime` remained 0. The check `block.timestamp >= executionTime` evaluated to `block.timestamp >= 0`, which is always true — completely bypassing the timelock.

**Fix (MultiSigBase.submitTransaction):** if `threshold <= 1`, `executionTime` is set to `block.timestamp + TIMELOCK_DURATION` immediately inside `submitTransaction`, before the function returns. A matching guard `require(txn.executionTime > 0)` in `executeTransaction` provides an explicit safety net.

BUILD AND TEST

forge build


forge test --match-path test/EvictionVault.t.sol
[⠊] Compiling...
No files changed, compilation skipped
Ran 8 tests for test/EvictionVault.t.sol:EvictionVaultTest
[PASS] test_Deployment_SetsOwnerAndThreshold() (gas: 20365)
[PASS] test_Deposit_TracksETH() (gas: 48377)
[PASS] test_Deposit_ViaReceive() (gas: 48299)
[PASS] test_EmergencyWithdraw_DrainsVaultOnlyViaMulsig() (gas: 270051)
[PASS] test_MerkleClaim_WhitelistedAddressCanClaimAfterRootSet() (gas: 333414)
[PASS] test_PauseUnpause_WhenThresholdVotesReached() (gas: 157108)
[PASS] test_Timelock_ExecutesETHTransferAfterDelay() (gas: 222501)
[PASS] test_Withdraw_ReturnsETHToDepositor() (gas: 50644)
Suite result: ok. 8 passed; 0 failed; 0 skipped; finished in 7.91ms (10.31ms CPU time)
