# Trading System — BNT‑Redux (v1)

**Purpose.** Establish a simple, tunable economy that rewards round‑trip trade routes, makes distance/turns + cargo meaningful, and sets up future automation and upgrades.

---

## 1) Core Concepts

### Commodities

`ore`, `organics`, `goods`, `energy`.

### Port Types

* **kind ∈ { ore, organics, goods, energy, special }**
* **Commodity port (kind=k)**: *Sells* only its own commodity `k`. *Buys* the other three resources `r ≠ k`.
* **Special port**: no commodity trade; used for equipment, repairs, upgrades.

### Visibility (fog of war)

* `port.kind`, stock, and prices are visible only if the sector is **visited** or **scanned**.

---

## 2) Prices & Spreads (static; easy to tune)

**Base prices**

```
P_BASE = { ore: 10.00, organics: 12.00, goods: 20.00, energy: 6.00 }
```

**Multipliers** (guarantee cross‑port profit):

```
M_SELL_NATIVE = 0.90   # price when player BUYS the port’s native commodity
M_BUY_OTHER   = 1.10   # price when port BUYS non‑native commodities from player
```

**Effective prices at a commodity port of type k**

* Native commodity `k` (player **buys**):  `SELL_PRICE(k) = P_BASE[k] * M_SELL_NATIVE`
* Non‑native `r ≠ k` (player **sells**):   `BUY_PRICE(r)  = P_BASE[r] * M_BUY_OTHER`

> Optional flavor (not required now): per‑port biases in ±5% range.

---

## 3) Stock Rules

* Commodity ports start with **stock only for their native commodity**; the other three start at 0 and **only increase** when players sell to that port.
* Special ports keep stock at 0 for all commodities.
* Players cannot buy more than the port currently has in stock for the native resource.

---

## 4) Actions (server‑authoritative)

All trade actions cost **0 turns**.

### BUY (native only)

* Allowed only for the port’s native commodity `k`.
* Quantity limit:

```
qty ≤ min( port_stock[k], cargo_free, floor(credits / SELL_PRICE(k)) )
```

### SELL (non‑native only)

* Allowed only for `r ≠ k`.
* Quantity limit: `qty ≤ inventory[r]`.

### TRADE (auto‑route at a commodity port)

Atomic sequence:

1. **Auto‑sell** all non‑native resources {r ≠ k} at `BUY_PRICE(r)`; increase the port’s stock for each sold resource.
2. Compute `credits' = credits + proceeds_from_sells` and `cargo_free'` after the sells.
3. **Auto‑buy** native `k` at `SELL_PRICE(k)` with:

```
Q = min( port_stock[k], floor( credits' / SELL_PRICE(k) ), cargo_free' )
```

4. Return summary:

```
{ sold: {ore,organics,goods,energy}, bought: {resource:k, qty:Q},
  credits_after, inventory_after, port_stock_after }
```

**Error codes**: `invalid_port_kind`, `resource_not_allowed`, `insufficient_stock`, `insufficient_credits`, `insufficient_cargo`.

---

## 5) Movement & Route Economics

### Hyperspace turn cost

From sector A→B with engine level E≥1:

```
distance = |A - B|
turn_cost = max(1, ceil(distance / E))
```

Realspace remains 1 turn/warp.

### Profit per turn (PPT)

For a two‑port loop (src kind = k1, dest kind = k2):

```
gross_per_unit = (BUY_PRICE_at_dest(k1) - SELL_PRICE_at_src(k1))
                + (BUY_PRICE_at_src(k2) - SELL_PRICE_at_dest(k2))
turns = travel_out + travel_back   # trading itself costs 0 turns
PPT = (gross_per_unit * traded_qty_each_leg) / max(1, turns)
```

**Implication**: farther routes can beat closer ones if engines are upgraded and cargo is high.

---

## 6) Ship Attributes (trading‑adjacent)

*(Inspired by classic BNT; effects constrained to trading/navigation for now.)*

| Attribute                  | Purpose (current)                                                              | Future hooks                                              |
| -------------------------- | ------------------------------------------------------------------------------ | --------------------------------------------------------- |
| **Cargo**                  | Max units carried. Limits BUY/TRADE qty.                                       | Upgrades increase capacity; modules add slots.            |
| **Engines** (`engine_lvl`) | Reduces hyperspace turn cost via formula above.                                | Gate autopilot speed; fuel cost if introduced.            |
| **Computer** (`comp_lvl`)  | UI aids: route planning, auto‑trade preview accuracy, saved route slots.       | Automation depth (multi‑leg routes), smarter price intel. |
| **Sensors** (`sensor_lvl`) | Increases free **full‑scan radius** and improves map detail fidelity/duration. | Detect hidden objects; scan through cloaks.               |
| **Hull**                   | Hit points; affects repair cost/time (Special ports).                          | Loss penalties on ship destruction (cargo drop).          |
| **Shields**                | Damage mitigation; not used in trading.                                        | Energy drain / recharge.                                  |
| **Fighters/Torpedoes**     | PvP; not used in trading.                                                      | Convoy defense affecting trade safety.                    |

**Upgrade costs (current simple rules)**

* Engine upgrade: `cost_next = 500 * (engine_lvl + 1)` (Special ports only).
* Repair hull: `2 cr per point` up to 100 (Special ports only).

> Computer/Sensors upgrade effects should be *UI/UX only* until we implement route automation.

---

## 7) API & RPC Contracts

### Sector payload (when visible)

```
GET /api/sector?number=N → {
  sector: { number },
  warps: number[],
  port: {
    id, kind, stock: { ore, organics, goods, energy },
    prices: { ore, organics, goods, energy }
  } | null,
  planet?: { id, name, owner: boolean } | null
}
```

### Trade endpoints

* `POST /api/trade` `{ portId, action:'buy'|'sell', resource, qty }` → snapshot.
* `POST /api/trade/auto` `{ portId }` → summary + snapshots (see **TRADE** above).

**Auth**: `Authorization: Bearer <access_token>` header; server verifies, then uses service role.

---

## 8) UI Requirements (Port Trading Overlay)

Single stacked panel:

1. **Header**: `TRADING PORT: <TYPE>` + icon/badge.
2. **Stock**: 2×2 grid for current port stock (non‑native usually 0 unless players sold to this port).
3. **Action selector**: **Buy | Sell | Trade** (segmented). Constrain resources per rules:

   * *Buy*: resource fixed to native commodity. Show qty, *Price/Total/After*, **Max Buy**.
   * *Sell*: dropdown with the other three commodities. Show qty, *Price/Total/After*, **Max Sell**.
   * *Trade*: read‑only preview of auto‑sell list + auto‑buy quantity.
4. **Submit**: single wide button with contextual label (`Buy X`, `Sell X`, `Trade route (auto)`).
5. **Feedback**: one‑line success/error summary. On success, revalidate `/api/me` and `/api/sector` and keep overlay open with refreshed numbers.

---

## 9) Balancing Knobs

* `P_BASE`, `M_SELL_NATIVE`, `M_BUY_OTHER`.
* Port native stock baselines (affect out‑of‑stock frequency).
* Optional **per‑port bias** (±5%).
* Optional drift caps: floors at `0.70 * P_BASE[r]`, ceilings at `1.40 * P_BASE[r]`.

---

## 10) Worked Example (10‑unit cargo)

* Ore port: buy ore at `0.90×10 = 9.00` → pay **90**.
* Goods port: sell ore at `1.10×10 = 11.00` → receive **110** (**+20**). Then buy goods at `0.90×20 = 18.00` → pay **180**.
* Back to Ore port: sell goods at `1.10×20 = 22.00` → receive **220** (**+40**).
* **Cycle profit per unit:** `+6.00`. For 10 units: `+60.00`.
* If distance is 5 each way and `engine_lvl=1` → \~10 turns round trip → **6.0 cr/turn**. At `engine_lvl=2` → \~6 turns → **10.0 cr/turn**.

---

## 11) Implementation Checklist (Cursor)

* Enforce buy/sell constraints server‑side for commodity vs. special ports.
* Ensure sector payload includes `port.kind`, `stock`, `prices` when visible.
* Confirm RPCs: `game_trade` (explicit) and `game_trade_auto` (auto) implement formulas above atomically with clear errors.
* Keep trade turn cost = 0; movements spend turns via realspace/hyperspace.
* Overlay UX matches **§8** and revalidates `/api/me` + `/api/sector` on success.
* Append Change Log in `/docs/CONTEXT.md` after any change.
