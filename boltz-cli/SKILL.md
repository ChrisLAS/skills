---
name: boltz-cli
description: Uses node-specific `boltzcli-<your-node>` and `lncli-<your-node>` wrappers to inspect <your-node> Lightning balances, channel health, Boltz wallets, Liquid or LBTC wallets, swap quotes, swap status, and autoswap on <your-host>. Use when the user asks things like "what's <your-node>'s lightning balance?", "how are the channels on <your-node>?", "quote a swap to Liquid", "sweep sats to Liquid", or asks to move sats between Lightning, BTC, and Liquid with explicit approval.
metadata: {"openclaw":{"requires":{"bins":["boltzcli-<your-node>","lncli-<your-node>"]},"emoji":"⚡"}}
---

# Boltz CLI

Use this skill for Lightning, Bitcoin, Liquid, and Boltz tasks that should go through the host-specific wrappers on <your-host>.

## Validation Checklist

For phased smoke testing and operator verification steps, see `TESTING.md` in this same directory. Use it when validating new wrapper behavior, skill-routing changes, or any live-funds workflow before trusting the path in normal use.

## Current Environment

- Use `boltzcli-<your-node>` for Boltz operations against <your-node>.
- Use `lncli-<your-node>` for LND operations against <your-node>.
- Treat <your-node> as the user-facing node name.
- <your-node-ssh> is the SSH or Tailnet transport hostname used internally by the wrappers. Users do not need to know or specify it for normal tasks.
- Unless the user explicitly says they want an internal or named LBTC wallet on <your-node>, interpret "sweep to Liquid" as an external Liquid-address destination.
- These wrappers already handle SSH tunneling, auth, TLS, macaroons, and host selection.
- Do not add `--host`, `--port`, `--rpcserver`, `--tlscert`, `--macaroon`, or password flags unless you are explicitly debugging the wrappers.
- The remote services on <your-node> are localhost-only today, so the wrappers are required.
- For <your-node>, prefer the wrappers first, not host exploration. Do not start by searching the filesystem, probing ports, or using `sudo` to discover Lightning paths if the wrappers exist.
- Do not replace `lncli-<your-node>` with raw `ssh <your-node-ssh> "lncli ..."` for normal operations. Use raw SSH only if `lncli-<your-node>` itself fails and you are explicitly troubleshooting the wrapper.

## Wrapper Selection

- If the user explicitly names <your-node>, use `boltzcli-<your-node>` and `lncli-<your-node>`.
- If future wrapper pairs exist and the user has not identified the target node, ask which node to use.
- Do not fall back to raw `boltzcli` or `lncli` for normal work on <your-node>.

## When To Use This Skill

Use this skill when the user wants to:

- check LND onchain or Lightning balances
- inspect channels, peers, or general LND health
- inspect Boltz BTC or LBTC wallets
- generate a receive address for a named Boltz wallet
- review swap history or a specific swap
- quote a submarine, reverse, or chain swap
- create, claim, or refund a swap with explicit approval
- inspect or change autoswap with explicit approval

Common trigger phrases:

- "what's <your-node>'s lightning balance?"
- "how are the channels on <your-node>?"
- "how much LBTC do I have?"
- "quote swapping 100k sats to Liquid"
- "sweep 100k sats to Liquid"
- "swap 100k sats from Lightning to Liquid on <your-node>"

## Command Surface

Prefer JSON output when the command supports it.

### LND read-only

```bash
lncli-<your-node> getinfo
lncli-<your-node> walletbalance
lncli-<your-node> channelbalance
lncli-<your-node> listchannels
lncli-<your-node> pendingchannels
lncli-<your-node> listpeers
```

Use `lncli-<your-node>` for Lightning state. Do not try to infer channel health from `boltzcli-<your-node>`.
Prefer direct wrapper output over ad hoc shell+Python reducers unless the user asked for a custom report shape.

### Boltz read-only

```bash
boltzcli-<your-node> getinfo
boltzcli-<your-node> getpairs
boltzcli-<your-node> quote --json --send <sats> reverse
boltzcli-<your-node> quote --json --send <sats> --from BTC --to LBTC chain
boltzcli-<your-node> listswaps --json
boltzcli-<your-node> listswaps --json --state pending
boltzcli-<your-node> swapinfo <swap-id>
boltzcli-<your-node> stats
boltzcli-<your-node> wallet list --json
boltzcli-<your-node> wallet transactions --json <wallet-name>
boltzcli-<your-node> autoswap status --json
boltzcli-<your-node> autoswap config --json
boltzcli-<your-node> autoswap recommendations
```

### User-directed but low-risk

Only run these when they directly answer the user’s request:

```bash
boltzcli-<your-node> wallet receive <wallet-name>
```

### Mutating or high-risk

Never run these unless the user explicitly asked for the action in the current conversation and you have confirmed the key details:

```bash
boltzcli-<your-node> wallet send <wallet-name> <destination> <amount>
boltzcli-<your-node> wallet send --sweep <wallet-name> <destination> <amount>
boltzcli-<your-node> wallet create <wallet-name> BTC|LBTC
boltzcli-<your-node> wallet import <wallet-name> BTC|LBTC

boltzcli-<your-node> createswap ...
boltzcli-<your-node> createreverseswap ...
boltzcli-<your-node> createchainswap ...
boltzcli-<your-node> refundswap ...
boltzcli-<your-node> claimswaps ...

boltzcli-<your-node> autoswap setup
boltzcli-<your-node> autoswap enable
boltzcli-<your-node> autoswap disable
boltzcli-<your-node> autoswap config ln ...
boltzcli-<your-node> autoswap config chain ...

boltzcli-<your-node> swapmnemonic get
boltzcli-<your-node> swapmnemonic set ...
```

Treat `lncli-<your-node>` the same way:

- read-only inspection commands are fine when they directly answer the request
- anything that sends funds, opens/closes channels, changes policy, or reveals sensitive data requires explicit confirmation

## Safety Rules

- Always get a quote before creating any swap.
- Always show the expected send amount, receive amount, and fee breakdown before asking for final approval.
- Ask for addresses in plain English only. Example: `What Liquid address should I use?`
- Treat "sweep to Liquid" as an external Liquid-address workflow by default.
- If the user says "sweep" and does not provide a Liquid address, ask for one before proposing execution.
- For `sweep ... to Liquid`, do not ask `Proceed with the swap?` until a destination Liquid address is present in the conversation.
- Only use an internal LBTC wallet when the user explicitly asks to keep funds on <your-node> or names the wallet.
- Never create, import, unlock, or initialize an LBTC wallet as fallback handling for a `sweep ... to Liquid` request.
- If a reverse swap to LBTC fails because no internal LBTC wallet exists, treat that as confirmation that the external-address path must be used instead of trying to create a wallet.
- For `sweep ... to Liquid`, treat Lightning outbound as the default funding source when it is viable.
- If both Lightning outbound and onchain BTC are viable funding sources, prefer Lightning first and only use onchain BTC if the user explicitly asks for it or Lightning is not viable.
- For swap creation commands, prefer `--json` when the command supports it so the result can be parsed without interactive confirmation prompts.
- Never rerun a successful create command just to get more details. Treat the first successful create result as authoritative.
- If a create command hits an interactive confirmation prompt or TTY issue, do not keep retrying with pipes, `yes`, PTY tricks, or alternative wrappers that might create duplicates. Switch once to the documented non-interactive form and stop after the first success.
- After any create command succeeds, do not issue another create command for the same user request unless the user explicitly asks to create another swap.
- Treat "lightning balance" as Lightning channel liquidity first, not the Boltz-managed BTC wallet balance.
- For "what's <your-node>'s lightning balance?" prefer `lncli-<your-node> channelbalance`, and include `walletbalance` only as a clearly separate onchain number if helpful.
- When summarizing sats, preserve magnitudes exactly. Do not accidentally compress `4.99M sats` into `49.9K sats` or similar.
- By default, report sat balances as exact integers only. Do not add `K`/`M` shorthand for sats unless the user explicitly asks for an approximation.
- Never assume the funding source when both LND and Boltz wallets could be used.
- Never assume a wallet name when multiple wallets of the same currency exist.
- Never use `wallet send --sweep` unless the user clearly asked to empty that wallet and you restate the consequence.
- Never use `swapinfo --show-private-keys`.
- Never reveal, repeat, or summarize seed words, swap mnemonic material, imported wallet phrases, certs, macaroons, passwords, or config secrets.
- Never paste raw create-swap JSON to the user when it contains private keys, preimages, blinding keys, refund data, or other sensitive internals. Summarize only the safe fields.
- If a command would move funds, alter config, create or import a wallet, or expose recovery material, pause and confirm.
- If the request is ambiguous, do safe read-only inspection first and then ask a targeted follow-up.
- Do not read secret config files or secret directories unless that is strictly required to debug a broken wrapper and the user has implicitly or explicitly asked for troubleshooting.

## Defaults

- Amounts are satoshis unless the user explicitly asks for BTC formatting too.
- Prefer concise summaries first and raw JSON only when it materially helps.
- For balances, distinguish clearly between:
- LND onchain BTC
- LND Lightning outbound
- LND Lightning inbound
- Boltz BTC wallet balances
- Boltz LBTC wallet balances

## High-Value Fields

### `lncli-<your-node> getinfo`

- `identity_pubkey`
- `alias`
- `num_active_channels`
- `num_peers`
- `block_height`
- `synced_to_chain`
- `synced_to_graph`

### `lncli-<your-node> walletbalance`

- `confirmed_balance`
- `unconfirmed_balance`
- `total_balance`

### `lncli-<your-node> channelbalance`

- `local_balance.sat`
- `remote_balance.sat`
- `pending_open_local_balance`
- `pending_open_remote_balance`

### `lncli-<your-node> listchannels`

- `active`
- `capacity`
- `local_balance`
- `remote_balance`
- peer alias or pubkey when useful
- `chan_id` when suggesting a targeted retry path

### `boltzcli-<your-node> wallet list --json`

- wallet name
- currency
- balance
- readonly status if present

### `boltzcli-<your-node> quote --json ...`

- send amount
- receive amount
- Boltz fee
- network fee
- any routing fee shown for reverse swaps

### `boltzcli-<your-node> swapinfo <id>`

- swap type
- current state
- status text
- amount in and amount out
- fees
- claim or refund implications when relevant

## Workflows

## “What’s my balance?”

Run:

```bash
lncli-<your-node> channelbalance
lncli-<your-node> walletbalance
boltzcli-<your-node> wallet list --json
```

Then summarize:

- LND onchain BTC confirmed
- LND onchain BTC unconfirmed if non-zero
- LND Lightning outbound
- LND Lightning inbound
- Boltz BTC wallet balances by wallet
- Boltz LBTC wallet balances by wallet

If the user specifically asks for "lightning balance", lead with `channelbalance`, not the Boltz wallet list.
Default response style for sat balances: exact sat counts only, for example `4,990,419 sats outbound` and `47,366,455 sats inbound`.

## "How are the channels on <your-node>?"

Run:

```bash
lncli-<your-node> channelbalance
lncli-<your-node> listchannels
```

Summarize:

- total active vs inactive channels
- total local and remote balance
- any obviously imbalanced channels
- any pending HTLCs or notable unsettled balances

Do not route this question through `boltzcli-<your-node>` first.

## "Why did the Lightning -> Liquid sweep fail?"

If a reverse swap times out or cannot be paid, gather actionable Lightning context before suggesting a retry.

Run:

```bash
boltzcli-<your-node> swapinfo <swap-id>
lncli-<your-node> channelbalance
lncli-<your-node> listchannels
```

Summarize:

- whether the reverse swap was ever paid
- the exact swap error and status
- total Lightning outbound and inbound
- top outbound channels by local balance
- whether any single active channel can comfortably support the requested amount
- whether the failure looks transient routing-related versus obviously capacity-limited

For the channel summary, prefer the top 3-5 active channels sorted by `local_balance`, including:

- peer alias or pubkey
- `chan_id`
- local balance
- remote balance
- whether the channel is active

Sort channels numerically by `local_balance`, not lexically. Prefer a `jq` sort such as:

```bash
lncli-<your-node> listchannels | jq '
  .channels
  | map(select(.active == true))
  | sort_by(-(.local_balance | tonumber))
  | .[:5]
' 
```

Then offer the next action:

- retry the reverse swap
- retry while targeting a specific `chan_id` if that looks useful and the user wants it
- fall back to the onchain BTC wallet path

Make the retry advice concrete. If there are plausible channel candidates, explicitly name the top 1-3 channels and say which one you would try first.
Present retry candidates as flat bullets, not markdown tables.

## “How much would a swap cost?”

1. Determine the intended path:
- `submarine` = BTC or LBTC -> Lightning
- `reverse` = Lightning -> BTC or LBTC
- `chain` = BTC <-> LBTC

2. Run the matching quote command.

Examples:

```bash
boltzcli-<your-node> quote --json --send <sats> reverse
boltzcli-<your-node> quote --json --send <sats> --from BTC --to LBTC chain
boltzcli-<your-node> quote --json --receive <sats> submarine
```

3. Show:
- send amount
- estimated receive amount
- Boltz fee
- network fee
- routing fee when relevant

4. Do not create the swap unless the user clearly says to proceed.

## “Sweep X sats to Liquid”

1. Inspect available sources:

```bash
lncli-<your-node> channelbalance
lncli-<your-node> walletbalance
boltzcli-<your-node> wallet list --json
```

2. Treat the destination as an external Liquid address by default.

- If the user already gave a Liquid address, use it in the quote and proposal.
- If the user did not give a Liquid address, ask for one and stop there.
- Do not silently switch this request to an internal LBTC wallet.
- Do not create or initialize any wallet during this workflow unless the user explicitly changes the request to an internal-wallet workflow.

3. Present the viable source options:
- Lightning outbound -> reverse swap to LBTC
- BTC wallet -> chain swap to external LBTC address

Default policy for this phrase:

- If Lightning outbound is sufficient, propose the Lightning -> LBTC reverse swap path first.
- Only propose the onchain BTC wallet path first when the user explicitly says to use onchain funds.
- If Lightning is not viable for the requested amount, explain why and then offer the onchain BTC wallet path as the fallback.

4. If no Liquid address has been provided yet, stop after asking for it.

5. Quote the chosen path only after a Liquid address is provided.

6. Present a final approval summary with:
- source
- amount to send
- estimated amount to receive
- fee breakdown
- destination Liquid address

7. Execute only after confirmation.

Examples:

```bash
boltzcli-<your-node> createreverseswap --json lbtc <sats> <liquid-address>
boltzcli-<your-node> createchainswap --json --from-wallet <btc-wallet-name> --to-address <liquid-address> <sats>
```

8. Monitor with:

```bash
boltzcli-<your-node> swapinfo <swap-id>
boltzcli-<your-node> listswaps --json --state pending
```

## “Move X sats into <your-node>'s Liquid wallet”

Use this only when the user explicitly wants an internal LBTC wallet on <your-node> for future liquidity management or names the destination wallet.

1. Inspect available wallets:

```bash
boltzcli-<your-node> wallet list --json
```

2. If no suitable LBTC wallet exists, stop and say so. Offer to create one only with explicit approval.

3. If exactly one suitable LBTC wallet exists, propose it.

4. If multiple suitable LBTC wallets exist, ask which one to use.

5. Quote and execute only after explicit approval.

Examples:

```bash
boltzcli-<your-node> createreverseswap --to-wallet <lbtc-wallet-name> lbtc <sats>
boltzcli-<your-node> createchainswap --from-wallet <btc-wallet-name> --to-wallet <lbtc-wallet-name> <sats>
```

## “Rebalance my channels” or “Set up autoswap”

1. Inspect:

```bash
boltzcli-<your-node> autoswap status --json
boltzcli-<your-node> autoswap config --json
boltzcli-<your-node> autoswap recommendations
```

2. Summarize current status, config shape, and recommendations.

3. Do not change autoswap unless the user explicitly approves.

4. Before any config change or enablement, restate:
- what will change
- what wallet or balance target it affects
- what risk or automation it introduces

5. After a change, verify again with:

```bash
boltzcli-<your-node> autoswap status --json
boltzcli-<your-node> autoswap config --json
```

## “A swap failed, refund it”

1. Inspect failure state:

```bash
boltzcli-<your-node> listswaps --json --state error
boltzcli-<your-node> swapinfo <swap-id>
boltzcli-<your-node> getinfo
```

2. Determine whether the swap is refundable or claimable.

3. If an address or wallet target is needed and the user did not provide one, ask.

4. Before running the mutation, restate:
- swap id
- intended destination
- expected action

5. Only then execute the claim or refund command.

## Failure Handling

If a command fails:

- do not guess
- explain the command intent in plain English
- summarize the error briefly
- suggest the next best safe diagnostic command
- if the failed command was a create operation, check whether a swap was already created before retrying anything

Common cases:

- wrapper cannot open the SSH tunnel to <your-node-ssh>
- missing wallet name
- missing Liquid address for an external sweep
- multiple plausible wallets
- insufficient funds
- no LBTC destination wallet
- quote unavailable for that pair or amount
- swap is not refundable or claimable
- autoswap is disabled or misconfigured

For `sweep ... to Liquid`, if no address has been provided yet, the next best step is not another CLI command. Ask the user for the destination Liquid address.

For swap creation:

- if the first create attempt returns a swap id, stop creating and move immediately to monitoring with `swapinfo <id>`
- if the first create attempt fails due to an interactive prompt, use the documented `--json` form once
- if a later command unexpectedly returns a second swap id, stop and tell the user duplicate swaps may have been created

If a reverse swap fails with `FAILURE_REASON_TIMEOUT`:

- do not reduce the explanation to "no outbound channel" unless the channel data actually supports that conclusion
- inspect `channelbalance` and `listchannels`
- return the top outbound channels so the user gets actionable information
- mention whether a targeted retry with `--chan-id` may be worth trying
- include `chan_id` values for the top retry candidates
- if one channel is clearly the best candidate, say so explicitly
- do not treat `chanIds: []` as proof of a specific internal routing mechanism failure; describe it as evidence consistent with a routing or path-selection problem unless stronger evidence exists
- do not describe high remote balance as "no inbound liquidity" or imply the node lacks inbound when `remote_balance` is large
- if recommending a retry amount, default to the same amount that failed unless there is concrete evidence that a different amount is more likely to succeed
- absent strong evidence, prefer retrying the smaller amount before a larger one
- describe `chanIds: []` as "no targeted channel was recorded" rather than claiming a specific HTLC lifecycle event did or did not happen

If the wrappers themselves appear broken, verify with:

```bash
ssh <your-node-ssh> hostname
boltzcli-<your-node> getinfo
lncli-<your-node> getinfo
```

Only after the wrapper checks fail should you inspect lower-level host details or secret-backed config paths.
Only after the wrapper checks fail should you use raw `ssh <your-node-ssh> "lncli ..."` commands.

## Output Style

Prefer this order:

1. short answer
2. key amounts and state
3. important caveats or fees
4. raw details only if they help the user decide

## Sensitive Data Handling

Never casually expose:

- seed words
- swap mnemonic material
- wallet import phrases
- TLS certs, macaroons, passwords, or secret config contents

If the user explicitly asks for recovery material, slow down, confirm intent, and keep the response minimal.
