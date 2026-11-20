# BBMA Oma Ally – Signals & Setups

Study notes for coding BBMA (Bollinger Bands + Moving Average), the method by Oma Ally, as MQL5 indicators/EAs.

**Current scope: XAUUSD only.** One indicator that marks signals on the chart so they can be verified by hand, and one EA that trades the same signals. Both use the same signal engine, so what you see on the chart is exactly what the EA trades.

> Terms and exact rules vary between BBMA teachers and communities. These notes describe the commonly taught version; verify against your own course material before trading. Not financial advice.

---

## 1. Indicator setup

| Component | Period | Method | Applied to | Notes |
|---|---|---|---|---|
| Bollinger Bands | 20 | SMA | Close | Deviation 2 → **BB Top**, **BB Mid**, **BB Low** |
| MA5 High | 5 | LWMA | High | Fast upper MA |
| MA10 High | 10 | LWMA | High | Slow upper MA |
| MA5 Low | 5 | LWMA | Low | Fast lower MA |
| MA10 Low | 10 | LWMA | Low | Slow lower MA |
| EMA 50 | 50 | EMA | Close | Trend filter |

### MQL5 handles

```mql5
int hBB    = iBands(_Symbol, _Period, 20, 0, 2.0, PRICE_CLOSE);
int hMA5H  = iMA(_Symbol, _Period, 5,  0, MODE_LWMA, PRICE_HIGH);
int hMA10H = iMA(_Symbol, _Period, 10, 0, MODE_LWMA, PRICE_HIGH);
int hMA5L  = iMA(_Symbol, _Period, 5,  0, MODE_LWMA, PRICE_LOW);
int hMA10L = iMA(_Symbol, _Period, 10, 0, MODE_LWMA, PRICE_LOW);
int hEMA50 = iMA(_Symbol, _Period, 50, 0, MODE_EMA,  PRICE_CLOSE);
// iBands buffers: 0 = BASE_LINE (mid), 1 = UPPER_BAND (top), 2 = LOWER_BAND (low)
```

Always evaluate on **closed candles** (shift 1 and older), never on the live candle (shift 0).

---

## 2. Core signals

### 2.1 Extreme
The first warning of a possible reversal: the MAs stretch outside the Bollinger Band.

- **Sell Extreme:** MA5 High and/or MA10 High closes **above BB Top**.
- **Buy Extreme:** MA5 Low and/or MA10 Low closes **below BB Low**.
- The candle should close back **inside** the band, not ride outside it.
- An extreme alone is **not** an entry; it marks a zone to watch.

```text
SellExtreme[i] = (MA5H[i] > BBTop[i] || MA10H[i] > BBTop[i]) && Close[i] <= BBTop[i]
BuyExtreme[i]  = (MA5L[i] < BBLow[i] || MA10L[i] < BBLow[i]) && Close[i] >= BBLow[i]
```

### 2.2 MHV – Market Hilang Volume ("market loses volume")
After an extreme, price returns to test the same band but **fails** to push out again.

- **Sell MHV:** after a Sell Extreme, price returns near BB Top but the candle does **not** close above it, and the MAs do not make a new extreme.
- **Buy MHV:** the mirror case at BB Low.
- Shows the move is losing strength. It's a sign that reversal is getting more likely.

### 2.3 CSAK – Candlestick Arah Kukuh ("strong direction candle")
The candle that confirms the change of direction.

- **Sell CSAK:** a bearish candle that closes **below BB Mid** and **below MA5/MA10** (ideally also below EMA 50).
- **Buy CSAK:** a bullish candle that closes **above BB Mid** and **above MA5/MA10** (ideally also above EMA 50).
- Strongest when it follows Extreme → MHV.

```text
BuyCSAK[i]  = Close[i] > Open[i] && Close[i] > BBMid[i]
              && Close[i] > MA5H[i] && Close[i] > MA10H[i]
              && Open[i] < BBMid[i]                 // body crosses the mid band
SellCSAK[i] = Close[i] < Open[i] && Close[i] < BBMid[i]
              && Close[i] < MA5L[i] && Close[i] < MA10L[i]
              && Open[i] > BBMid[i]
```

### 2.4 CSM – Candlestick Momentum
A candle that **closes outside** the Bollinger Band while the bands **expand**.

- **Buy Momentum:** close above BB Top, bands widening.
- **Sell Momentum:** close below BB Low, bands widening.
- Means a strong trend is running. **Do not trade against momentum.** Wait for a re-entry in its direction.

```text
BandWidth[i]  = BBTop[i] - BBLow[i]
Expanding     = BandWidth[i] > BandWidth[i+1]
BuyMomentum   = Close[i] > BBTop[i] && Expanding
SellMomentum  = Close[i] < BBLow[i] && Expanding
```

### 2.5 Re-entry
The main entry signal: after CSAK or momentum, price pulls back into the MA5/MA10 zone and then resumes.

- **Buy Re-entry:** after a Buy CSAK or momentum, price dips into MA5/MA10 Low (or toward BB Mid), then a candle closes back up, above the MAs.
- **Sell Re-entry:** the mirror case using MA5/MA10 High.
- Multiple re-entries can happen in one trend. The first one or two are usually the best.

---

## 3. Full setup flow

```text
Extreme  →  MHV  →  CSAK  →  Re-entry  →  (Momentum / trend continues)
  watch      weaken    confirm     ENTRY
```

### Buy setup (reverse for sell)
1. **Extreme:** MA5/MA10 Low below BB Low.
2. **MHV:** price retests BB Low and fails to close below it.
3. **CSAK:** a bullish candle closes above BB Mid and above the MAs.
4. **Re-entry:** price pulls back to MA5/MA10 Low or BB Mid, and a bullish candle closes back up → **BUY**.
5. **Stop loss:** below the recent swing low or below the MA5/MA10 Low zone.
6. **Take profit:** at BB Top, or at the opposite extreme on the higher timeframe.

### Trend filter (EMA 50)
- Prefer buys when price is above EMA 50 and sells when it's below.
- A CSAK that also crosses EMA 50 is stronger.

---

## 4. Multi-timeframe confirmation

BBMA is usually traded top-down:

| Role | Example timeframe | What to look for |
|---|---|---|
| Direction | D1 / H4 | Extreme, MHV, CSAK, or momentum direction |
| Setup | H1 | Re-entry zone aligned with the higher TF |
| Entry | M15 / M5 | Re-entry candle or a small CSAK in the same direction |

Rule of thumb: **only take a lower-TF re-entry in the direction of the higher-TF signal.**

---

## 5. XAUUSD notes

- **Symbol name:** on HFM it may be `XAUUSD` or have a suffix. The code uses the chart's symbol and only warns if the name doesn't contain `XAU`.
- **Price digits:** gold is usually quoted with 2 decimals, so 1 point = 0.01 and a $1 move = 100 points. All SL/TP buffers in the EA are in points.
- **Contract size:** usually 100 oz per lot, so 0.01 lot ≈ $1 per $1 move. Verify on your account (`SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE)`); the EA calculates lot size from tick value, not from this assumption.
- **Spread:** widens at the daily rollover, the Asian open and around news (NFP, CPI, FOMC). The EA has a max-spread input.
- **Active hours:** London and New York sessions give the cleanest BBMA moves. The EA has a trading-hours filter.
- **History:** no gold history has been downloaded yet. Open an XAUUSD chart in MT5 on each timeframe you want, and scroll back so MT5 downloads the bars before backtesting.

---

## 6. Build plan (XAUUSD only)

| File | Purpose | Status |
|---|---|---|
| `Include/BBMA/BBMA_Engine.mqh` | Shared signal logic: Extreme, MHV, CSAK, Momentum, Re-entry | Done |
| `Indicators/BBMA/BBMA_OmaAlly.mq5` | Draws BB, MA5/10 High/Low, EMA 50 and an arrow per signal, for manual checking | Next |
| `Experts/BBMA/BBMA_EA.mq5` | Trades the re-entry setup on XAUUSD | After the indicator is verified |
| `build.sh` | Copies files into MT5's `MQL5` folder, compiles, shows errors | With the indicator |

### Step 1 – Indicator, verify by hand
1. Attach `BBMA_OmaAlly` to XAUUSD on H1 (then H4 and M15).
2. Scroll back through history and check each arrow against your own reading of the chart.
3. Note any signal that is missing, wrong or extra (bar time + timeframe), and adjust the inputs below or the rules in the engine.
4. Repeat until the arrows match how you would mark the chart manually.

### Step 2 – EA
Only after the indicator matches your manual reading:
- Enters on **Re-entry** signals only, on closed candles.
- Optional higher-timeframe filter (e.g. H4 direction for an H1 setup).
- SL beyond the recent swing or MA zone plus a buffer in points; TP at the opposite BB or a fixed R:R.
- Fixed lot or risk % per trade, one position at a time, max spread and trading-hours filters.
- Backtest in the Strategy Tester on XAUUSD, then forward-test on the demo account.

### Rule settings (indicator and EA inputs)
These are the current defaults in the engine. Change them during manual verification until they match your BBMA reading.

| Input | Default | Question it answers |
|---|---|---|
| Extreme mode | MA5 **or** MA10 outside the band | Must both MAs be outside? |
| MHV lookback | 20 bars | How long after an extreme can the retest happen? |
| CSAK needs EMA 50 | No | Must CSAK also close beyond EMA 50? |
| Require MHV before CSAK | No | Is a setup valid without an MHV? |
| Re-entry max bars | 30 | How long after CSAK/momentum is a re-entry still valid? |
| Max re-entries per setup | 2 | How many re-entries to take in one move? |
| Re-entry EMA 50 filter | No | Buy re-entries only above EMA 50, sells only below? |
| SL buffer / TP mode | To decide in the EA | Points beyond the swing; opposite BB or fixed R:R? |
