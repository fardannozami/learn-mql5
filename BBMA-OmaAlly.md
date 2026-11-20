# BBMA Oma Ally – Signals & Setups

Study notes for coding BBMA (Bollinger Bands + Moving Average), the method by Oma Ally, as MQL5 indicators/EAs.

**Current scope: XAUUSD only.** One indicator that marks signals on the chart so they can be verified by hand, and one EA that trades the same signals. Both use the same signal engine, so what you see on the chart is exactly what the EA trades.

**Reference:** *SIGNAL IDENTIFICATION BBMA OMA ALLY.pdf* (BBMA Oma Ally Analyzer Dashboard EA V4.50 guidebook), in
`../BBMA/november/BBMA Oma ally Analyzer Dashboard EA V4.50/BBMA Oma Ally Analyzer Dashboard EA/GUIDEBOOK/English/`.
Rule text in quotes below is from the guidebook (Malay words translated). Anything marked *(interpretation)* is my reading of its chart examples and should be checked.

> Not financial advice. Verify every rule against the chart before trading real money.

---

## 1. Indicator setup

| Component | Period | Method | Applied to | Chart colour (guidebook) |
|---|---|---|---|---|
| Bollinger Bands | 20 | SMA | Close | Green – **Upper BB**, **Mid BB**, **Lower BB** (deviation 2) |
| MA5 High | 5 | LWMA | High | Red |
| MA10 High | 10 | LWMA | High | Red |
| MA5 Low | 5 | LWMA | Low | Blue |
| MA10 Low | 10 | LWMA | Low | Blue |
| EMA 50 | 50 | EMA | Close | Cyan / white |

The guidebook charts also draw dotted lines between MA5 and MA10 as a visual fill; they aren't part of the rules.

### MQL5 handles

```mql5
int hBB    = iBands(_Symbol, _Period, 20, 0, 2.0, PRICE_CLOSE);
int hMA5H  = iMA(_Symbol, _Period, 5,  0, MODE_LWMA, PRICE_HIGH);
int hMA10H = iMA(_Symbol, _Period, 10, 0, MODE_LWMA, PRICE_HIGH);
int hMA5L  = iMA(_Symbol, _Period, 5,  0, MODE_LWMA, PRICE_LOW);
int hMA10L = iMA(_Symbol, _Period, 10, 0, MODE_LWMA, PRICE_LOW);
int hEMA50 = iMA(_Symbol, _Period, 50, 0, MODE_EMA,  PRICE_CLOSE);
// iBands buffers: 0 = BASE_LINE (mid), 1 = UPPER_BAND, 2 = LOWER_BAND
```

Always evaluate on **closed candles** (shift 1 and older), never on the live candle (shift 0).

---

## 2. Single-timeframe signals

Chart labels used by the guidebook / dashboard: **CSE / EXT** (extreme), **TPW**, **MHV**, **CSAK**, **CSM**, **Dir** (direction), **Re** (re-entry), **MA50** (rejected EMA 50), **Gap**, **FS** (full setup).

### 2.1 Extreme (CSE / EXT)
| Buy | Sell |
|---|---|
| "MA5/10 Low **below** Lower BB" | "MA5/10 High **above** Upper BB" |
| "there is a **reversal candle**" | "there is a **reversal candle**" |

An extreme is a warning that the move is stretched, not an entry.

```text
BuyExtreme  = (MA5L < LowerBB || MA10L < LowerBB) && reversal candle (bullish, closes back inside the band)
SellExtreme = (MA5H > UpperBB || MA10H > UpperBB) && reversal candle (bearish, closes back inside the band)
```
*(interpretation: "reversal candle" = a candle in the new direction that closes back inside the band.)*

### 2.2 TPW (hit MA 5/10)
Step 2 of the Full Setup: "TPW (hit MA 5/10)".
*(interpretation from the charts: after an extreme, price pulls back and touches the opposite MA5/10 – after a buy extreme it rises to touch MA5/10 High; after a sell extreme it falls to touch MA5/10 Low.)*

```text
BuyTPW  = after BuyExtreme,  High >= MA5H or MA10H
SellTPW = after SellExtreme, Low  <= MA5L or MA10L
```

### 2.3 MHV – Market Hilang Volume ("market loses volume")
| Buy | Sell |
|---|---|
| After an **Extreme Buy** | After an **Extreme Sell** |
| "**no CSM Sell** that breaks the extreme" | "**no CSM Buy** that breaks the extreme" |

Price comes back to test the extreme area but can't produce a momentum candle beyond it, so the move is losing strength.

```text
BuyMHV  = after BuyExtreme (and TPW), price returns toward Lower BB,
          but no CSM Sell closes below the extreme
SellMHV = after SellExtreme (and TPW), price returns toward Upper BB,
          but no CSM Buy closes above the extreme
```

### 2.4 CSAK / CSD – direction candle
| Buy | Sell |
|---|---|
| "Break **MA5/10 High** and break **Mid BB**" | "Break **MA5/10 Low** and break **Mid BB**" |

```text
BuyCSAK  = Close > MA5H && Close > MA10H && Close > MidBB   (candle crosses Mid BB upward)
SellCSAK = Close < MA5L && Close < MA10L && Close < MidBB   (candle crosses Mid BB downward)
```

### 2.5 CSM – momentum candle
| Buy | Sell |
|---|---|
| "Break **MA5/10 High** and break **Upper BB**" | "Break **MA5/10 Low** and break **Lower BB**" |

```text
BuyCSM  = Close > MA5H && Close > MA10H && Close > UpperBB
SellCSM = Close < MA5L && Close < MA10L && Close < LowerBB
```
The guidebook doesn't require the bands to be expanding.

### 2.6 Direction (Dir)
"Direction = the **first CSAK/CSM after MHV**." This sets the trading direction for the re-entry.

### 2.7 Re-entry (Re)
| Buy | Sell |
|---|---|
| "**Rejected MA5/10 Low**" | "**Rejected MA5/10 High**" |
| "after a **CSAK/CSM Buy**" | "after a **CSAK/CSM Sell**" |

```text
BuyReentry  = after BuyCSAK/BuyCSM:   Low  <= MA5L/MA10L && Close > MA5L/MA10L
SellReentry = after SellCSAK/SellCSM: High >= MA5H/MA10H && Close < MA5H/MA10H
```

### 2.8 Rejected EMA 50 (MA50) – used while the higher timeframe is in re-entry
| Buy | Sell |
|---|---|
| "EMA 50 **below** Mid BB" | "EMA 50 **above** Mid BB" |
| "candle **rejects** EMA 50" | "candle **rejects** EMA 50" |

```text
BuyRejectEMA50  = EMA50 < MidBB && Low  <= EMA50 && Close > EMA50
SellRejectEMA50 = EMA50 > MidBB && High >= EMA50 && Close < EMA50
```

### 2.9 Gap BB to EMA50 – used while the higher timeframe is in re-entry
| Buy | Sell |
|---|---|
| "EMA 50 **below** Lower BB" | "EMA 50 **above** Upper BB" |
| "candle **rejects** Lower BB" | "candle **rejects** Upper BB" |

```text
BuyGap  = EMA50 < LowerBB && Low  <= LowerBB && Close > LowerBB
SellGap = EMA50 > UpperBB && High >= UpperBB && Close < UpperBB
```

---

## 3. Full Setup (FS)

```text
Extreme  →  TPW  →  MHV  →  Direction  →  Re-entry
```

1. **Extreme** – "not broken by a CSM".
2. **TPW** – "hit MA 5/10".
3. **MHV** – "no CSM".
4. **Direction** – "first CSAK/CSM after MHV".
5. **Re-entry** – "lower timeframe rejects Upper/Lower BB, or rejects EMA 50".

### Trade management (not in the guidebook – my defaults for the EA)
- **Stop loss:** beyond the re-entry candle's swing, or beyond the MA5/10 zone, plus a buffer in points.
- **Take profit:** the opposite BB, or a fixed risk:reward.

---

## 4. Multi-timeframe analysis

Timeframe groups (higher → middle → lower):

| Group | HTF | Middle | Lower |
|---|---|---|---|
| 1 | W1 | D1 | H4 |
| 2 | D1 | H4 | H1 |
| 3 | H4 | H1 | M15 |
| 4 | H1 | M15 | M5 |

Named setups – the letters are the signal on each timeframe, **HTF → middle → lower**:

| # | Setup | HTF | Middle TF | Lower TF |
|---|---|---|---|---|
| 1 | **Full Setup** | Extreme → TPW → MHV → Direction → Re-entry (across the timeframes) | | |
| 2 | **REE** | Re-entry | Extreme | Extreme |
| 3 | **RRE** | Re-entry | Re-entry | Extreme |
| 4 | **RRM** | Re-entry | Re-entry | MHV |
| 5 | **REM** | Re-entry | Extreme | MHV |
| 6 | **Diamond** | Re-entry | Reject EMA 50 **or** Gap | Extreme / MHV / Full Setup |

All signals in a setup must point the **same way** (all buy or all sell).

---

## 5. XAUUSD notes

- **Symbol name:** on HFM it may be `XAUUSD` or have a suffix. The code uses the chart's symbol and only warns if the name doesn't contain `XAU`.
- **Price digits:** gold is usually quoted with 2 decimals, so 1 point = 0.01 and a $1 move = 100 points. All SL/TP buffers in the EA are in points.
- **Contract size:** usually 100 oz per lot, so 0.01 lot ≈ $1 per $1 move. Verify on your account (`SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE)`); the EA calculates lot size from tick value, not from this assumption.
- **Spread:** widens at the daily rollover, the Asian open and around news (NFP, CPI, FOMC). The EA has a max-spread input.
- **Active hours:** London and New York sessions give the cleanest BBMA moves. The EA has a trading-hours filter.
- **History:** no gold history has been downloaded yet. Open an XAUUSD chart in MT5 on each timeframe you want, and scroll back so MT5 downloads the bars before backtesting.
- The guidebook's CSAK, CSM, Re-entry, Extreme, Rejected EMA 50 and Gap examples are all **XAUUSD H4/D1 charts**, so they're good test cases for checking the indicator.

---

## 6. Build plan (XAUUSD only)

| File | Purpose | Status |
|---|---|---|
| `Include/BBMA/BBMA_Engine.mqh` | Shared signal logic, matched to the guidebook | **Done** (compiles clean) |
| `Indicators/BBMA/BBMA_OmaAlly.mq5` | Draws BB, MA5/10 High/Low, EMA 50 and a label per signal (CSE, TPW, MHV, CSAK, CSM, Dir, Re, MA50, Gap), for manual checking | **Done** (compiles clean) |
| `build.sh` | Copies files into MT5's `MQL5` folder, compiles, shows errors | **Done** |
| `Experts/BBMA/BBMA_EA.mq5` | Trades XAUUSD re-entries, with the multi-timeframe setups as filters | Next, after the indicator is verified |

### How the engine implements each signal (as built)
- **CSE (Extreme):** MA5 or MA10 (low) below Lower BB with a bullish candle; mirror for sell. Cancelled if an opposite CSM later breaks the extreme level.
- **TPW:** after an extreme, the first bar that touches the MA5/10 zone.
- **MHV:** after TPW, a bar that retests near the extreme (within `MhvProxFactor` × band width) but holds, with no opposite CSM breaking it.
- **CSAK:** candle closes beyond MA5/10 **and** Mid BB (but not the outer band).
- **CSM:** candle closes beyond MA5/10 **and** the outer BB.
- **Dir:** the first CSAK/CSM after an MHV.
- **Re (Re-entry):** after any CSAK/CSM, a candle is rejected at MA5/10 and closes back the trend way. This is the EA's entry signal. Limited to `MaxReentries` within `ReentryMaxBars` bars.
- **MA50 (Rejected EMA 50):** EMA 50 on the far side of Mid BB, candle rejects EMA 50.
- **Gap:** EMA 50 beyond the band, candle rejects the band.

All signals are inputs you can toggle, and the thresholds (`SeqLookback`, `ReentryMaxBars`, `MaxReentries`, `MhvProxFactor`, EMA filter) are inputs to tune while verifying.

### How to run it
1. In a terminal: `cd /run/media/xcode/DATA/coding/mql5/learn-mql5 && ./build.sh`
2. In MT5: open an **XAUUSD** chart, then drag **Indicators → BBMA → BBMA Oma Ally** onto it.
3. The BB/MA/EMA lines are drawn and each signal is labelled on its candle (buy labels below the bar, sell labels above).
4. Compare against the guidebook's XAUUSD H4 examples and your own reading; note any mismatch and we adjust the inputs or the engine.

### Step 1 – Indicator, verify by hand
1. Attach `BBMA_OmaAlly` to XAUUSD on H4 and compare with the guidebook's XAUUSD examples (Dec 2023 – Jan 2024).
2. Check H1, M15 and D1 the same way.
3. Note any signal that is missing, wrong or extra (bar time + timeframe), then adjust the inputs or the engine.
4. Repeat until the labels match your own reading of the chart.

### Step 2 – Multi-timeframe dashboard row
Show the latest signal for XAUUSD on W1, D1, H4, H1, M15 and M5 (like one row of the Analyzer Dashboard), and highlight Full Setup, REE, RRE, RRM, REM and Diamond when they line up.

### Step 3 – EA
Only after the indicator matches your manual reading:
- Enter on the lower-timeframe **re-entry** when one of the enabled MTF setups (Full Setup / REE / RRE / RRM / REM / Diamond) lines up.
- Each setup on/off as an input, plus the timeframe group (e.g. H4–H1–M15).
- SL/TP as in section 3; fixed lot or risk % per trade.
- One position at a time; max spread and trading-hours filters.
- Backtest in the Strategy Tester on XAUUSD, then forward-test on the demo account.

### Open questions to check on the chart
| Question | Current default |
|---|---|
| Extreme: is one MA (MA5 **or** MA10) outside the band enough? | Yes – either |
| What exactly counts as a "reversal candle"? | Candle in the new direction that closes back inside the band |
| TPW: which MA must be touched – MA5 or MA10? | Either |
| How many bars after the extreme can TPW / MHV still happen? | 20 bars |
| CSAK: must the candle *open* on the other side of Mid BB, or is the previous close enough? | Previous close on the other side |
| Re-entry: how many bars after CSAK/CSM is it still valid, and how many re-entries per move? | 30 bars, 2 re-entries |
| SL buffer and TP mode | SL = swing + buffer; TP = opposite BB |
