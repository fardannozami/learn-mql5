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
- **History:** XAUUSD history is downloaded — W1/D1/H4/H1 back to 2021, M15 back to 2022-08, M5 back to 2025-06 (see `Scripts/BBMA/DownloadHistory.mq5`). Re-run it to extend coverage before a longer backtest.
- The guidebook's CSAK, CSM, Re-entry, Extreme, Rejected EMA 50 and Gap examples are all **XAUUSD H4/D1 charts**, so they're good test cases for checking the indicator.

---

## 6. Build plan (XAUUSD only)

| File | Purpose | Status |
|---|---|---|
| `Include/BBMA/BBMA_Engine.mqh` | Shared signal logic, matched to the guidebook | **Done** (compiles clean) |
| `Indicators/BBMA/BBMA_OmaAlly.mq5` | Draws BB, MA5/10 High/Low, EMA 50 and a label per signal (CSE, TPW, MHV, CSAK, CSM, Dir, Re, MA50, Gap), for manual checking | **Done** (compiles clean) |
| `build.sh` | Copies files into MT5's `MQL5` folder, compiles, shows errors | **Done** |
| `Experts/BBMA/BBMA_EA.mq5` | Trades XAUUSD re-entries, with the multi-timeframe setups as filters | **Done** (compiles clean) |

### EA logic (as built)
Enters on an **entry-TF Re-entry** (acts once per closed bar), then applies, in order:
- **Entry-quality — HTF EMA50 trend filter** (`InpUseHtfEma`, default on): the trade is only taken in the direction of the HTF EMA50 (price the right side of EMA50, and with `InpHtfEmaSlope` the EMA50 must also slope that way). This is the strongest win-rate lever — it drops the losing counter-trend re-entries in ranging markets and is neutral when the market trends. Optional `InpUseEntryEma` adds the same check on the entry TF.
- **HTF** (default H4): most recent extreme / MHV / Dir / CSAK / CSM / Re-entry must point the same way. An opposing HTF signal blocks the trade.
- **Mid** (default H1): a recent Reject-EMA50 / Gap / Re-entry in the same direction.
- `MinConfirm` sets how many of the two must agree (default 1). *Note:* with the EMA filter on, `MinConfirm = 2` becomes meaningful again (it was a no-op before, because the nearest-signal confirmation almost always agreed).

**Exit — two modes:**
- **Fixed TP/SL (default):** SL at the swing over `SwingLookback` bars plus `SlBufferPts`; TP = `RiskRatio` × SL distance (default **1.5**). Profit comes from letting winners run to the TP, so a 2:1-ish target matters.
- **Dynamic signal exit** (`InpUseSignalExit`, default **off**): close the position when BBMA reverses — an **opposite CSAK on the entry TF**, or **≥ `InpExitCsmCount` opposite CSM on `InpExitLowerTF`** (M5) within `InpExitCsmWindow` bars. A swing SL stays as a backstop (`InpUseHardSL`). This roughly **halves drawdown** but lowers win% and net (it caps the winners), so it is off by default — turn it on when you value a smoother equity curve over win rate.

Defaults: timeframe group **H4 – H1 – M15**; one position at a time; fixed 0.01 lot (set `RiskPercent` > 0 to size by risk); max-spread and optional session filters. All signal thresholds match the indicator's inputs.

**Tuning dials (for win rate vs net):** `RiskRatio` is the main knob with the filter on — **1.5** ≈ balanced (highest all-round), **2.0** pushes win% highest in ranging markets, **2.5–3.0** maximises net at a lower win%.

### Backtesting the EA
1. Open an XAUUSD chart on M15, H1 and H4 and scroll back so history downloads for all three.
2. In MT5: **View → Strategy Tester** (Ctrl+R) → Expert `BBMA\BBMA_EA`, Symbol XAUUSD, a date range covered by the downloaded history.
3. Start with "Every tick based on real ticks" off (use "1 minute OHLC") for a quick first pass; switch to real ticks once the logic looks right.
4. The EA reads M15/H1/H4 together, so make sure all three have history or it will simply not trade.

#### Backtest results so far (XAUUSD M15, 0.01 lot, deposit 10 000)
Reports in `backtests/`. The "edge" row uses the edge-triggered engine (current); the others used the earlier per-bar engine.

| Period | Engine | MinConfirm | Net profit | Profit factor | Trades | Win % | Max DD |
|---|---|---|---|---|---|---|---|
| 2024–2025 | per-bar | 1 | +$494.61 | 1.09 | 844 | ~33% | — |
| 2026 | per-bar | 1 | −$35.24 | 0.99 | 455 | — | — |
| 2024–2026 | per-bar | 2 | +$534.53 | 1.05 | 1 198 | — | — |
| 2024–2025 | **edge** | 1 | **+$279.04** | **1.06** | **774** | **34.6%** | **4.82%** |

The edge-triggered engine is more faithful to the guidebook (sparser, correct signals) but, for this EA, the 2024–2025 edge was slightly *lower* than the per-bar version — some consecutive-bar re-entries that happened to win are now filtered out. Treat the edge as a correctness fix for the indicator, not a profit improvement for the EA.

#### Win-rate tuning (edge engine, XAUUSD M15)
Goal: raise win rate without killing net. Key finding — **this EA profits from a few big winners, so simply moving TP closer raises win% but turns net negative.** The real lever is the **HTF EMA50 trend filter**, which lifts the whole curve:

| Config (2024–2025) | Net | PF | Trades | Win % | Max DD |
|---|---|---|---|---|---|
| base, no filter, RR2.0 | +$279 | 1.06 | 774 | 34.6% | 4.82% |
| no filter, RR1.0 (TP=SL) | −$282 | 0.95 | 1 077 | 49.0% | 6.21% |
| dynamic signal exit, no filter | +$257 | 1.07 | 1 095 | 27.2% | 2.55% |
| **filter, RR1.5 (default)** | **+$325** | **1.08** | **724** | **40.3%** | **3.83%** |
| filter, RR2.0 | +$125 | 1.03 | 924 | 55.4% | 2.34% |
| filter, RR2.5 | +$600 | 1.16 | 563 | 30.4% | 5.23% |
| filter, RR3.0 | +$787 | 1.21 | 531 | 27.5% | 4.94% |

Out-of-sample 2026 (strong trend): filter RR1.5 = +$775 / **42.6%** win / DD 4.54%; filter RR2.0 = +$815 / 36% (identical to base — in a clean trend the filter rejects nothing). The filter never hurts: it removes losing counter-trend re-entries in chop and is neutral in trends.

**Chosen default = filter on + RR1.5** (signal exit off, fixed TP on). Re-confirmed with the shipped compiled defaults: 2024–2025 +$259 / **40.7%** win / DD 3.96%, and 2026 +$775 / **42.6%** win / DD 4.54% — beating the old base on every metric in both periods (higher win%, higher net, lower drawdown). Set `RiskRatio = 2.0` to push win% higher in ranging markets, or 2.5–3.0 to maximise net at a lower win rate. The dynamic signal exit (`InpUseSignalExit`) is off by default — it halves drawdown but lowers win% and net.

### How the engine implements each signal (as built)
**Edge-triggered:** CSE, CSAK, CSM and Re fire only on the single candle that *crosses* — the bar that actually breaks the level while the previous bar was still on the other side — not on every bar that stays beyond it. This matches the guidebook, which marks the breaking candle, and stops the indicator from labelling a whole run of bars.
- **CSE (Extreme):** MA5 or MA10 (low) below Lower BB with a bullish candle; mirror for sell. Fires once per episode — the first reversal candle while the MAs are outside the band — and re-arms only after the MAs come back inside. Cancelled if an opposite CSM later breaks the extreme level.
- **TPW:** after an extreme, the first bar that touches the MA5/10 zone.
- **MHV:** after TPW, a bar that retests near the extreme (within `MhvProxFactor` × band width) but holds, with no opposite CSM breaking it.
- **CSAK:** the candle that *closes through* MA5/10 (previous bar still on the other side) **and** beyond Mid BB (but not the outer band).
- **CSM:** the candle that *closes through* the outer BB (previous bar still inside the band) **and** beyond MA5/10.
- **Dir:** the first CSAK/CSM after an MHV.
- **Re (Re-entry):** after any CSAK/CSM, a candle pulls back to MA5/10 and is rejected, closing back the trend way. Edge-triggered: one touch-and-reject = one signal (the raw condition must have been false on the previous bar). This is the EA's entry signal. Limited to `MaxReentries` within `ReentryMaxBars` bars.
- **MA50 (Rejected EMA 50):** EMA 50 on the far side of Mid BB, candle rejects EMA 50.
- **Gap:** EMA 50 beyond the band, candle rejects the band.

#### Multi-timeframe signal validation (TF above)
A CSM or CSE is only "real" when the timeframe above confirms it (`InpUseMtfValidate`, default on; `InpMtfParentWindow` = parent bars to look back, default 3):
- **CSM valid** only if the TF above printed a **CSAK** in the same direction within the window.
- **CSE (Extreme) valid** only if the TF above printed an **MHV** in the same direction within the window.

The "TF above" follows the BBMA ladder **M5 → M15 → H1 → H4 → D1 → W1** (`BBMAParentTF`). Shared helpers live in `BBMA_Engine.mqh` (`BBMABuildSeries`, `BBMAApplyMtfValidation`) so the indicator, EA and scanner all use the same rule.

- **Indicator:** unconfirmed CSM/CSE labels are not drawn. On an H4 chart (parent D1) this removed ~35% of CSM and ~61% of CSE labels — the chart now matches the methodology instead of marking every break.
- **EA:** the HTF trend read validates its CSM/CSE against the TF above (H4 → D1). Effect on results is small (the EA enters on Re-entry, not on CSM/CSE directly): 2024–2025 unchanged, 2026 net slipped ~15% with the same win rate. Kept on by default for consistency; set `InpUseMtfValidate = false` in the EA if you prefer the extra net.

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

### Step 2 – Multi-timeframe dashboard row — `Indicators/BBMA/BBMA_Scanner.mq5` (**Done**)
A small on-chart panel for XAUUSD:
- **Sig row:** the latest signal on W1, D1, H4, H1, M15, M5 (green = buy, red = sell, grey = none).
- **Setups:** each TF group (W1-D1-H4, D1-H4-H1, H4-H1-M15, H1-M15-M5) shows its best matching named setup (Diamond / RRE / RRM / REE / REM / Full) and direction, or `-`.
- Updates on a timer (default 3 s). Inputs match the indicator's rule settings, plus panel position/size.
- Attach it to any XAUUSD chart; it scans all six timeframes itself, so each needs downloaded history.

> The Full-Setup / named-setup detection is approximate (nearest signal per category within a window), meant as a study aid to compare against the guidebook's dashboard, not an exact clone of the paid EA.

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
