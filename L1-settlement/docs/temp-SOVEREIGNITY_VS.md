# Rollup Sovereignty vs Compose Governance

This document compares two governance models for integrating existing OP Stack rollups with Compose shared settlement and Super Roots.

- **Hybrid A (Lockbox-only shared governance)**
- **Non-hybrid (Full Compose SuperchainConfig for participating rollups)**

The goal is to clarify: implementation complexity, migration likelihood, and the exact sovereignty/composability tradeoffs.

---

## 1. Models at a Glance

### Hybrid A – Lockbox-Only Shared Governance

**Definition**

- Existing rollup keeps its original `SystemConfig.superchainConfig` ("rollup SuperchainConfig").
- All core OP Stack L1 contracts (Portal, L1StandardBridge, L1XDM, L1ERC721Bridge, standard ETHLockbox) continue to read pause state via that rollup `SystemConfig`.
- **ComposeETHLockbox** uses its own `superChainConfig` ("Compose SuperchainConfig") to control:
  - Global/lockbox-level pause
  - Which portals are authorized
- The current strict check in `ComposeETHLockbox._authorizePortal` is relaxed:
  ```solidity
  // Current
  if (_portal.superchainConfig() != superchainConfig()) revert ETHLockbox_DifferentSuperchainConfig();

  // Hybrid A: allow portals whose SystemConfig.superchainConfig != Compose's
  // (possibly with a softer allowlist/validation instead of strict equality)
  ```

**Effect**

- Rollup governance continues to own **its own SuperchainConfig** and pause semantics for its L1 contracts.
- Compose governance controls only the **shared ETH lockbox** and any functionality gated by that lockbox.
- When Compose pauses, ETH outflows through the Compose lockbox stop, but the rollup can still operate its own portal/bridges independently.

---

### Non-Hybrid – Shared Compose SuperchainConfig

**Definition**

- Rollup upgrades its `SystemConfig.superchainConfig` to point to the **Compose SuperchainConfig**.
- All OP Stack L1 contracts that depend on `SystemConfig.paused()` or `SystemConfig.superchainConfig()` now effectively inherit Compose-level governance:
  - `OptimismPortal2` / `OptimismPortalInterop`
  - `L1StandardBridge`
  - `L1CrossDomainMessenger`
  - `L1ERC721Bridge`
- `ComposeETHLockbox` *also* uses the Compose SuperchainConfig. The strict check in `_authorizePortal` remains valid (portal and lockbox share the same SuperchainConfig).

**Effect**

- Compose governance becomes the **L1 emergency / coordination authority** for all participating rollups’ core L1 infra.
- Rollups opt into a single shared SuperchainConfig (guardian/DAO/committee), gaining coordinated security but giving up some direct L1 control while they participate.

---

## 2. Comparison Table

| Dimension | Hybrid A: Lockbox-only Shared Governance | Non-Hybrid: Shared Compose SuperchainConfig |
|----------|-------------------------------------------|---------------------------------------------|
| **Core idea** | Rollup keeps its own SuperchainConfig; Compose governs only the shared ETH lockbox. | All core L1 contracts read pause state from Compose SuperchainConfig. |
| **SystemConfig.superchainConfig** | Stays **rollup-owned**. | Set to **Compose-owned** for participating rollups. |
| **Portal pause source** | Rollup’s SuperchainConfig via `SystemConfig.paused()`. | Compose SuperchainConfig via `SystemConfig.paused()` (since that now points to Compose). |
| **Bridges & L1XDM pause source** | Rollup’s SuperchainConfig (no change). | Compose SuperchainConfig. |
| **Shared ETH Lockbox (ComposeETHLockbox)** | Uses Compose SuperchainConfig, independent of rollup’s SuperchainConfig. | Uses Compose SuperchainConfig (same as rollup’s SystemConfig). |
| **Compose can stop ETH outflows via lockbox?** | **Yes**: pausing ComposeETHLockbox stops unlocks / payouts routed through it. | **Yes**: same, plus pause propagates to other L1 contracts via shared SuperchainConfig. |
| **Compose can pause rollup portal/bridges?** | **No**: those depend on rollup’s own SuperchainConfig. Compose only controls the shared lockbox. | **Yes**: portal, bridges, messenger respect Compose-level pause via SystemConfig. |
| **Rollup can still run L1 infra while Compose lockbox is paused?** | **Yes**: portal/bridges can continue; only ETH leaving the lockbox is frozen. | Mostly **no**: if Compose pauses globally or chain-specifically, core L1 infra is paused. |
| **Rollup L2 governance** | Unchanged. Still fully rollup-controlled. | Unchanged. Still fully rollup-controlled. |
| **Who owns SuperchainConfig ProxyAdmin?** | Rollup keeps its own SuperchainConfig contract & ProxyAdmin; Compose has its own separate SuperchainConfig for the lockbox. | Compose owns the SuperchainConfig contract used by SystemConfig; rollup’s previous SuperchainConfig can be deprecated or repurposed. |
| **Ease of implementation (for Compose)** | **High**: mainly relax `_authorizePortal` and document semantics. No forked portal, no SystemConfig changes beyond existing OP Stack. | **Medium**: need migrations so `SystemConfig.superchainConfig` points to Compose’s contract. Operational/runbook implications for all affected contracts. |
| **Ease of adoption (for existing rollups)** | **High**: minimal change to their existing governance; they plug into shared settlement while retaining L1 pause control. | **Medium–Low**: rollups must accept that Compose guardian/DAO can now pause their core L1 infra. Stronger trust requirement. |
| **Migration friction** | Lower: can be framed as “opt into shared settlement & shared ETH lockbox, keep your own emergency levers”. | Higher: must be comfortable migrating SuperchainConfig authority (or at least pausing authority) to Compose. |
| **Rollup sovereignty (L1)** | **Strong**: rollup still controls portal, bridges, XDM pause and upgrades; can exit Compose by simply de-authorizing the lockbox and/or reverting lockbox routing. | **Weaker while opted-in**: L1 emergency controls over portal, bridges & XDM are effectively shared with / delegated to Compose SuperchainConfig. Rollup can regain full control by migrating off Compose. |
| **Rollup sovereignty (L2)** | Fully preserved. | Fully preserved. |
| **Compose sovereignty** | Limited but strong where it matters for settlement: can freeze ETH outflows from the shared lockbox, but cannot pause rollup’s own portal/bridges. | Broad: can coordinate global or per-chain pauses across portal, bridges, XDM, standard lockbox, and ComposeETHLockbox with a single guardian decision. |
| **Security blast radius of a bad Compose decision** | Limited to funds and flows that pass through shared lockbox. Rollup infra can, in theory, still operate independently. | Larger: a bad or captured Compose guardian directly affects portal/bridges of all opted-in rollups. |
| **Operational simplicity** | Slightly more complex mental model (two independent SuperchainConfigs), but less invasive to existing rollups. | Logically simpler: “one SuperchainConfig to rule them all”, but with heavier governance/coordination implications. |
| **Alignment with current descriptor in `ComposeETHLockbox`** | Requires adjusting the comment and logic that currently assumes strict equality of `superchainConfig()` between portal and lockbox. | Matches the current strict check and comment exactly. |

---

## 3. Rollup Sovereignty in Each Model

### Hybrid A – What the Rollup Still Controls

- **L1 SuperchainConfig (rollup)**
  - Rollup governance controls its own `SuperchainConfig` and its guardian.
  - `SystemConfig.paused()` uses rollup’s superchainConfig.
  - Portal, L1StandardBridge, L1XDM, L1ERC721Bridge all take their pause semantics from this rollup-owned config.
- **L2 Governance**
  - Sequencer set, upgrade schedule, protocol parameters, app-level governance remain entirely rollup-controlled.
- **Participation in Compose**
  - Rollup can opt in/out of using ComposeETHLockbox + Super Roots by:
    - Authorizing / de-authorizing its portal in `ComposeETHLockbox`.
    - Routing or not routing withdrawals through the shared settlement path.

**Net effect:** while integrated, the rollup shares a **liquidity and settlement facility** (Compose), but retains primary control over L1 infra and can still operate independently if Compose is paused.

### Non-Hybrid – What the Rollup Still Controls

- **L2 Governance**
  - Same as Hybrid A: fully rollup-controlled.
- **ProxyAdmin for its L1 contracts**
  - Rollup can upgrade implementations of Portal, Bridges, XDM, etc., subject to whatever standards Compose requires.
- **Choice to participate**
  - Rollup can, in principle, migrate away from Compose by:
    - Re-pointing `SystemConfig.superchainConfig` to a rollup-owned contract.
    - Migrating off the shared lockbox / Super Roots.

**But while opted in:**

- The **effective L1 emergency authority** over portal & bridges is shared with Compose via the common SuperchainConfig.
- A Compose guardian decision to pause is binding for that rollup’s core L1 infra as long as it stays in the system.

---

## 4. Compose Governance Power

### Hybrid A – Targeted Settlement Power

Compose governs:

- **Shared ETH Lockbox (`ComposeETHLockbox`)**
  - Can globally or locally pause the lockbox via its own SuperchainConfig.
  - Can gate which portals are authorized to interact with the lockbox.
- **Impact of a Compose pause**
  - ETH payouts from the lockbox are frozen.
  - SuperRoots-based withdrawal finalization that relies on the lockbox stops.
  - Rollup’s own L1 infra (portal, bridges, XDM) *can* continue, but users relying on Compose settlement flows are effectively frozen.

This is a **narrow but strong** power: Compose is in the critical path for shared settlement, but not in the full L1 control loop of each rollup.

### Non-Hybrid – Full L1 Coordination Layer

Compose governs:

- **SuperchainConfig used by SystemConfig** for all participating rollups.
- Consequently:
  - Portal proving/finalization can be globally or selectively paused.
  - Bridges and L1XDM pause semantics are unified.
  - Standard ETHLockbox + ComposeETHLockbox also follow the same governance.

This is a **broad coordination power**: one guardian decision can halt or resume L1 operations across many rollups simultaneously.

---

## 5. Implementation & Migration Considerations

### Hybrid A – Implementation Notes

- **Code changes (high-level):**
  - Relax or replace the strict equality check in `ComposeETHLockbox._authorizePortal`:
    - Option 1: remove SuperchainConfig equality entirely.
    - Option 2: replace with a softer allowlist or capability check.
  - Clarify semantics in documentation: Compose governs the lockbox; rollups govern their SuperchainConfig.
- **Risk profile:**
  - Does not alter rollup SystemConfig wiring.
  - Limited blast radius: changes localized to Compose contracts and migration flows.

- **Migration likelihood:**
  - **Higher** for existing rollups, especially those that never explicitly opted into Optimism’s “Superchain” shared governance.
  - Easy to pitch as: *“Plug into a shared settlement + Super Roots layer without surrendering your existing L1 pause controls.”*

### Non-Hybrid – Implementation Notes

- **Code changes (high-level):**
  - Migration script(s) to update `SystemConfig.superchainConfig` to Compose’s contract.
  - Ensure all affected contracts (Portal, Bridges, XDM, any ETHLockbox) behave correctly with the new governance.
  - Keep strict SuperchainConfig equality in ComposeETHLockbox.
- **Risk profile:**
  - Changes the governance root-of-trust for critical L1 contracts.
  - Requires clear social/legal agreements around who controls the Compose SuperchainConfig guardian.

- **Migration likelihood:**
  - **Lower** for existing sovereign-minded rollups.
  - More attractive for new rollups or those already comfortable with a shared Superchain-style governance model.

---

## 6. Summary for Decision Makers

- **Hybrid A**
  - Easiest to ship and easiest to adopt for existing rollups.
  - Preserves strong rollup L1 sovereignty while still giving Compose decisive control over shared settlement flows.
  - Slightly more complex to reason about (two different SuperchainConfigs exist), but safer politically and operationally.

- **Non-Hybrid**
  - Conceptually clean: a single SuperchainConfig for all participating chains.
  - Maximizes Compose’s ability to coordinate and secure the entire ecosystem from a single control point.
  - Requires rollups to be comfortable delegating significant L1 emergency powers to Compose governance.

**Key strategic choice:**

- If the priority is **rapid integration and respect for existing rollup sovereignty**, Hybrid A is the more pragmatic starting point.
- If the long-term vision is a **tightly governed Superchain cluster** with strong central coordination, the non-hybrid model aligns better, but may need more buy-in, communication, and possibly a staged rollout (start with Hybrid A, then offer an opt-in path to the full shared SuperchainConfig later).
