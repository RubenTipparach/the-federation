# 10. Shipyard

Where a captain refits: buy, sell, install, and strip, all as one pending
transaction that is only charged when it is confirmed.

Status: **rules agreed, screen awaiting mockup approval** (CLAUDE.md section 6).
Nothing in this document is implemented yet.

---

## 1. The three places an item can be

| Place | What it means | Capacity rule |
|---|---|---|
| **Shop** (left) | The yard's stock. Infinite for prototype purposes: taking from it is buying, giving to it is selling. | None |
| **Ship** (centre) | Fitted to a mount, or part of the hull. Governed by the existing fitting validator. | Mount size and family, plus the four budgets |
| **Cargo** (right) | Carried, not fitted. Stock you own and have not sold. | The hull's cargo capacity, in space units |

Every drag is one of six moves, and each is either free, a purchase, or a sale:

| Drag | Effect | Money |
|---|---|---|
| Shop to Ship | Buy and fit in one move | Purchase |
| Shop to Cargo | Buy and stow | Purchase |
| Cargo to Ship | Fit something already owned | Free |
| Ship to Cargo | Strip a mount and stow the item | Free |
| Ship to Shop | Strip a mount and sell the item | Sale |
| Cargo to Shop | Sell from the hold | Sale |

There is no Shop to Shop or Cargo to Cargo: dropping an item back where it came
from cancels the drag.

---

## 2. Nothing is charged until Confirm

The screen edits a **pending transaction**, not the player's account. Dragging
changes the working fit, the working cargo, and a running tally. Money moves
once, when Confirm is pressed.

The tally shows, at all times:

- **Purchases**, the sum of the list price of everything taken from the shop.
- **Sales**, the sum of the sale price of everything given to the shop.
- **Balance**, `sales - purchases`. Negative means the captain owes the yard.
- **Credits after**, `credits + balance`, which is the number that has to stay
  at or above zero.

Cancel discards the whole pending transaction and restores the fit and the hold
as they were on entry.

---

## 3. Prices

Each catalog item carries a `price` in credits in `data/weapons.json`, next to
its costs, per CLAUDE.md section 5.4. The yard's two prices come from it:

- **List price**, what the shop charges. This is `price` exactly.
- **Sale price**, what the shop pays. This is `price * sell_back_frac`, with
  `sell_back_frac` in `data/tuning.json` under `shipyard`, starting at `0.6`.

The spread is the yard's margin, and it is what stops a player buying and
selling repeatedly to farm anything. A damaged item sells for the same fraction
of its remaining boxes: `price * sell_back_frac * boxes / boxes_max`, so a
shot-up phaser is worth less than a fresh one, and a destroyed one is worth
nothing.

---

## 4. When Confirm is allowed

Confirm is enabled only when **all** of the following hold. The screen states
which one is failing rather than simply greying the button out.

1. **The hold is not overfull.** The sum of `costs.space` for every item in
   cargo is at most the hull's `cargo_space`. Cargo capacity is a hull stat, so
   a freighter can carry what a frigate cannot.
2. **The balance can be settled.** `credits + balance >= 0`. A captain may spend
   down to zero but not past it, and a sale in the same transaction can pay for
   a purchase, which is the point of tallying before charging.
3. **The fit is legal.** Every fitted weapon passes the existing
   `ShipFit.is_legal` check for its mount, and no budget is exceeded except
   crew, which is allowed to run over exactly as it does on the fitting screen.
4. **The transaction is not empty.** Nothing to confirm means the button reads
   as done rather than inviting a no-op.

Rules 1 and 2 are the two the player will hit in practice, and both are shown
live: the cargo bar turns red when overfull, and Credits after turns red when
negative.

---

## 5. Where the rules live

One implementation, in the simulation, not in the screen (CLAUDE.md 4.1):

- `ShipFit` already owns legality and the budgets. The shipyard calls it, it
  does not re-check anything itself.
- A new `Shipyard` class in `src/sim/` owns the pending transaction: the moves,
  the tally, the capacity check, and whether Confirm is allowed. It has no Node
  dependencies and is tested headless, so the rules above are assertions in
  `tests/run_tests.gd` before any of it is drawn.
- The screen drags icons around and asks `Shipyard` what it is allowed to do.

This matters more here than almost anywhere else in the game: a shop that
computes its own totals is a shop that eventually disagrees with the account it
charges.
