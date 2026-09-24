# martingale_grid_basic

A minimal **counter-trend grid martingale** Expert Advisor.

One-bar momentum entry, counter-trend grid adds with doubled lot size,
and a basket exit in account currency. No stop-loss, no trailing stop,
no time filter. Just the core mechanic, kept small enough to read in
one sitting.

Implemented three times, side by side:

- **MQL4** — `martingale_grid_basic.mq4` (MetaTrader 4)
- **MQL5** — `martingale_grid_basic.mq5` (MetaTrader 5, hedging accounts)
- **Python** — `backtest.py` (offline backtesting on OHLC bars)

The three versions share the same logic, the same parameters, and the
same bar-open entry timing, so a signal that fires in the backtest fires
in the EA.

---

## Strategy

### Entry

On the first tick of every new bar, look at the two most recently *closed*
bars. If the last one closed higher than the one before it, go long. If it
closed lower, go short.

```
signal = +1  if  Close[i-2] < Close[i-1]     ->  BUY
signal = -1  if  Close[i-2] > Close[i-1]     ->  SELL
signal =  0  otherwise                       ->  no trade
```

Only fires when the basket is empty. One position, `first_lot`, at the
open of the new bar.

### Grid adds (averaging into the loss)

If price moves **against** the position by `distance_pips`, add another
position **in the same direction** with **double the previous lot size**.

- BUY basket: add when `Open[i] <= last_entry - distance_pips * pip`
- SELL basket: add when `Open[i] >= last_entry + distance_pips * pip`

Repeat on each new bar until `max_orders` is reached. No hedging — the
grid only ever adds in the direction of the first trade.

### Lot progression

```
L_n = first_lot * 2^n
```

With `first_lot = 0.01`:

| n  | lot   |
|----|-------|
| 0  | 0.01  |
| 1  | 0.02  |
| 2  | 0.04  |
| 3  | 0.08  |
| 4  | 0.16  |
| 5  | 0.32  |
| 6  | 0.64  |
| 7  | 1.28  |
| 8  | 2.56  |
| 9  | 5.12  |

### Exit

Close the entire basket when the sum of floating P/L across all open
positions reaches `tp_in_money`, expressed in account currency:

```
sum(Profit_k + Swap_k)  >=  tp_in_money
```

No per-position TP, no SL, no trailing. One number closes the basket.
After the close, the entry logic re-arms and waits for the next signal.

### Timing

Everything runs on the first tick of a new bar. Entries, grid adds, and
the exit check all read `Open[0]` as the fill price and only use data
from bars `Close[1]` and `Close[2]` — no look-ahead.

---

## Why this exists

Grid martingales are a common EA archetype that gets buried in hundreds
of lines of hedging, correlation, time-filter, and news-filter logic.
This project strips all of that away and leaves the bones:

> Enter, average down, double, take profit in money.

It's meant as a clean reference implementation for:

- understanding the mechanic without distractions
- measuring its drawdown behaviour in a backtest
- using as a skeleton for adding your own filters

It is **not** a profitable strategy. It's a well-known way to blow up
an account in a trending market. See the warning below.

---

## Files

```
martingale_grid_basic/
├── martingale_grid_basic.mq4    # MetaTrader 4 version
├── martingale_grid_basic.mq5    # MetaTrader 5 version (hedging)
├── backtest.py                  # Python backtest on OHLC bars
└── README.md
```

---

## Parameters

| Name               | Type   | Default | Meaning                                                |
|--------------------|--------|---------|--------------------------------------------------------|
| `First_lot`        | double | `0.01`  | Initial lot size of each new basket                    |
| `Distance_in_pips` | double | `55`    | Grid step between consecutive orders, in pips          |
| `Max_Orders`       | int    | `10`    | Maximum number of positions in a basket                |
| `TP_in_money`      | double | `0.50`  | Close the basket when floating P/L reaches this        |
| `Lot_Multiplier`   | double | `2.0`   | Lot multiplier applied on each grid add                |
| `MagicNumber`      | ulong  | `345345`| EA identifier so it doesn't touch other trades         |
| `OrderComment`     | string | `"Razrulifatele.Portfolio"` | Comment attached to every order |

---

## Installation

### MetaTrader 4

1. Copy `martingale_grid_basic.mq4` to `MQL4/Experts/`.
2. In MetaEditor, compile (F7).
3. In MT4, drag onto a chart.
4. Enable **AutoTrading**.

### MetaTrader 5

1. Copy `martingale_grid_basic.mq5` to `MQL5/Experts/`.
2. In MetaEditor, compile (F7).
3. In MT5, drag onto a chart.
4. Enable **Algo Trading**.
5. **Make sure the account is a hedging account** — netting accounts
   cannot stack multiple positions on the same symbol, and the grid
   logic will not work as intended.
   Check via `AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`.

### Python backtest

No external dependencies (standard library only).

```bash
python backtest.py
```

Edit `Config` at the top of `backtest.py` to change parameters.
Replace the synthetic-bar generator in `__main__` with a CSV loader
for real data.

---

## Backtesting notes (Python)

The backtest walks 1-minute bars and only acts at bar opens. It assumes:

- **Fills at `open[i]` exactly.** No spread, no slippage, no commission.
- **No swap.** Positions held across days cost nothing.
- **Exit only at bar opens.** A live EA checks the exit on every tick,
  so this will systematically *underestimate* the number of exits.
- **No intrabar grid adds.** If the bar's low dips below a grid level
  but the bar opens above it, no order is added. This matches the EA's
  new-bar gate.
- **Unlimited liquidity, no margin call.** Add a margin check to see
  realistic blow-ups.

For a more faithful simulation you'd need to step tick-by-tick or at
least bar-by-bar over `high`/`low`, and include spread, commission,
and swap.

---

## Warning

This is a **martingale grid**. It has no stop-loss. In a strong
one-directional move it will:

1. keep adding positions with doubling size,
2. keep pushing the average entry further into the move,
3. at some point **blow up the account** because the required margin
   for the next doubling exceeds available equity.

The `TP_in_money` target is small, so the strategy wins most of the
time — until it doesn't. That asymmetry (frequent small wins, rare
catastrophic loss) is the entire point of a martingale and the entire
reason it eventually fails. Do not run this on a live account. Do not
run this on a demo account if you're tempted to move it live. Use it
as a study.

---

## The math, in one block

Let:

- `L_0` = `first_lot`
- `M`   = `lot_multiplier` (2)
- `D`   = `distance_in_pips`
- `p`   = pip size in price units (`10 * Point` on 5/3-digit brokers)
- `N`   = `max_orders`
- `T`   = `tp_in_money`

**Direction:**
```
dir[i] = +1  if Close[i-2] < Close[i-1]
dir[i] = -1  if Close[i-2] > Close[i-1]
```

**Grid step:**
```
ΔP = D * p
```

**Grid add:**
```
BUY:  Open[i] <= P_last - ΔP
SELL: Open[i] >= P_last + ΔP
```

**Lot:**
```
L_n = L_0 * M^n
```

**Exit:**
```
sum_k ( Profit_k + Swap_k ) >= T
```

That's the whole thing.

---

## License

MIT. Do whatever you want with it. If you find a way to make it
profitable, you've solved a problem nobody else has — congratulations,
and please tell us how.
```

