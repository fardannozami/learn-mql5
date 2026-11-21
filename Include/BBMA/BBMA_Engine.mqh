//+------------------------------------------------------------------+
//| BBMA_Engine.mqh                                                  |
//| Shared BBMA (Oma Ally) single-timeframe signal logic.            |
//| Rules follow the guidebook:                                      |
//|   SIGNAL IDENTIFICATION BBMA OMA ALLY.pdf                         |
//|   BBMA Oma Ally Analyzer Dashboard EA MT5 V1.27.pdf              |
//| Feed CLOSED bars oldest -> newest through Step().                 |
//+------------------------------------------------------------------+
#ifndef BBMA_ENGINE_MQH
#define BBMA_ENGINE_MQH

//--- signal flags returned by Step()
#define BBMA_EXTREME_BUY     (1<<0)
#define BBMA_EXTREME_SELL    (1<<1)
#define BBMA_TPW_BUY         (1<<2)
#define BBMA_TPW_SELL        (1<<3)
#define BBMA_MHV_BUY         (1<<4)
#define BBMA_MHV_SELL        (1<<5)
#define BBMA_CSAK_BUY        (1<<6)
#define BBMA_CSAK_SELL       (1<<7)
#define BBMA_CSM_BUY         (1<<8)
#define BBMA_CSM_SELL        (1<<9)
#define BBMA_DIR_BUY         (1<<10)
#define BBMA_DIR_SELL        (1<<11)
#define BBMA_REENTRY_BUY     (1<<12)
#define BBMA_REENTRY_SELL    (1<<13)
#define BBMA_REJECT_EMA_BUY  (1<<14)
#define BBMA_REJECT_EMA_SELL (1<<15)
#define BBMA_GAP_BUY         (1<<16)
#define BBMA_GAP_SELL        (1<<17)

//--- tunable rule settings (verify each on the chart)
struct BBMASettings
  {
   int    seqLookback;      // bars after an extreme in which TPW/MHV/Dir may form
   int    reentryMaxBars;   // bars after a CSAK/CSM in which a re-entry is still valid
   int    maxReentries;     // re-entries allowed per CSAK/CSM impulse
   bool   reentryEmaFilter; // buy re-entry only above EMA50, sell only below
   double mhvProxFactor;    // how close (x band width) a retest must come to the extreme
  };

void BBMADefaults(BBMASettings &s)
  {
   s.seqLookback      = 30;
   s.reentryMaxBars   = 30;
   s.maxReentries     = 3;
   s.reentryEmaFilter = false;
   s.mhvProxFactor    = 0.5;
  }

//--- one closed bar plus its indicator values
struct BBMABar
  {
   double open, high, low, close;
   double bbTop, bbMid, bbLow;
   double ma5h, ma10h, ma5l, ma10l;
   double ema50;
  };

//--- full-setup sequence state for one direction
struct BBMASide
  {
   int    phase;        // 0 none, 1 extreme, 2 tpw, 3 mhv, 4 direction
   int    extremeBar;
   double extremeLevel; // extreme candle's low (buy) / high (sell)
  };

class CBBMAEngine
  {
private:
   BBMASettings m_s;
   int       m_bar;          // index of current bar (increments each Step)
   BBMASide  m_buy;
   BBMASide  m_sell;
   int       m_impBuyBar;    // bar of the last buy CSAK/CSM (arms buy re-entry)
   int       m_impSellBar;
   int       m_impBuyRe;     // buy re-entries taken since that impulse
   int       m_impSellRe;
   //--- edge-trigger state (fire only on the breaking candle) ---------
   bool      m_hasPrev;      // a previous bar is stored
   BBMABar   m_prev;         // previous closed bar + its values
   bool      m_exBuyEp;      // a buy-extreme already fired this MA-outside episode
   bool      m_exSellEp;
   bool      m_prevReBuy;    // previous bar met the raw re-entry condition
   bool      m_prevReSell;

   void ResetSide(BBMASide &s) { s.phase=0; s.extremeBar=-100000; s.extremeLevel=0.0; }

public:
   void Init(const BBMASettings &s)
     {
      m_s        = s;
      m_bar      = -1;
      ResetSide(m_buy);
      ResetSide(m_sell);
      m_impBuyBar=-100000;  m_impSellBar=-100000;
      m_impBuyRe =0;        m_impSellRe =0;
      m_hasPrev  =false;
      m_exBuyEp  =false;    m_exSellEp  =false;
      m_prevReBuy=false;    m_prevReSell=false;
     }

   int  BuyPhase()  const { return m_buy.phase;  }
   int  SellPhase() const { return m_sell.phase; }

   //--- process one closed bar, return its signal flags
   int  Step(const BBMABar &b)
     {
      m_bar++;
      int flags = 0;

      double maHiMax = MathMax(b.ma5h, b.ma10h);
      double maHiMin = MathMin(b.ma5h, b.ma10h);
      double maLoMax = MathMax(b.ma5l, b.ma10l);
      double maLoMin = MathMin(b.ma5l, b.ma10l);
      double bw      = b.bbTop - b.bbLow;
      bool   bull    = b.close > b.open;
      bool   bear    = b.close < b.open;

      //--- edge comparisons against the previous bar ----------------
      double pMaHiMax = m_hasPrev ? MathMax(m_prev.ma5h, m_prev.ma10h) : 0.0;
      double pMaLoMin = m_hasPrev ? MathMin(m_prev.ma5l, m_prev.ma10l) : 0.0;

      //--- instantaneous signals (edge-triggered) ------------------
      // Extreme (CSE): MA5/10 outside the band + first reversal candle
      // of the episode. Re-arms once the MAs come back inside the band.
      bool maBelow = (b.ma5l < b.bbLow || b.ma10l < b.bbLow);
      bool maAbove = (b.ma5h > b.bbTop || b.ma10h > b.bbTop);
      if(!maBelow) m_exBuyEp  = false;
      if(!maAbove) m_exSellEp = false;
      bool exBuy  = false, exSell = false;
      if(maBelow && bull && !m_exBuyEp)  { exBuy  = true; m_exBuyEp  = true; }
      if(maAbove && bear && !m_exSellEp) { exSell = true; m_exSellEp = true; }

      // CSM: the candle that CLOSES through the Upper/Lower BB (prev bar
      // was still inside the band) while also beyond MA5/10.
      bool csmBuyLvl  = bull && b.close > maHiMax && b.close > b.bbTop;
      bool csmSellLvl = bear && b.close < maLoMin && b.close < b.bbLow;
      bool csmBuy  = csmBuyLvl  && (!m_hasPrev || m_prev.close <= m_prev.bbTop);
      bool csmSell = csmSellLvl && (!m_hasPrev || m_prev.close >= m_prev.bbLow);

      // CSAK: the candle that CLOSES through MA5/10 (prev bar was still on
      // the other side of the MAs), beyond Mid BB, and not already a CSM.
      bool csakBuyLvl  = bull && b.close > maHiMax && b.close > b.bbMid;
      bool csakSellLvl = bear && b.close < maLoMin && b.close < b.bbMid;
      bool csakBuy  = csakBuyLvl  && !csmBuy  && (!m_hasPrev || m_prev.close <= pMaHiMax);
      bool csakSell = csakSellLvl && !csmSell && (!m_hasPrev || m_prev.close >= pMaLoMin);

      // Rejected EMA50 (EMA50 on the far side of Mid BB)
      bool rejBuy  = bull && b.ema50 < b.bbMid && b.low  <= b.ema50 && b.close > b.ema50;
      bool rejSell = bear && b.ema50 > b.bbMid && b.high >= b.ema50 && b.close < b.ema50;

      // Gap BB to EMA50 (EMA50 beyond the band)
      bool gapBuy  = bull && b.ema50 < b.bbLow && b.low  <= b.bbLow && b.close > b.bbLow;
      bool gapSell = bear && b.ema50 > b.bbTop && b.high >= b.bbTop && b.close < b.bbTop;

      if(exBuy)   flags |= BBMA_EXTREME_BUY;
      if(exSell)  flags |= BBMA_EXTREME_SELL;
      if(csmBuy)  flags |= BBMA_CSM_BUY;
      if(csmSell) flags |= BBMA_CSM_SELL;
      if(csakBuy) flags |= BBMA_CSAK_BUY;
      if(csakSell)flags |= BBMA_CSAK_SELL;
      if(rejBuy)  flags |= BBMA_REJECT_EMA_BUY;
      if(rejSell) flags |= BBMA_REJECT_EMA_SELL;
      if(gapBuy)  flags |= BBMA_GAP_BUY;
      if(gapSell) flags |= BBMA_GAP_SELL;

      //--- arm re-entry: every CSAK/CSM sets the direction -----------
      if(csakBuy || csmBuy)  { m_impBuyBar  = m_bar; m_impBuyRe  = 0; }
      if(csakSell || csmSell){ m_impSellBar = m_bar; m_impSellRe = 0; }

      //--- full-setup sequence (buy) --------------------------------
      if(exBuy) { m_buy.phase=1; m_buy.extremeBar=m_bar; m_buy.extremeLevel=b.low; }
      if(m_buy.phase>=1 && m_bar-m_buy.extremeBar<=m_s.seqLookback)
        {
         if(csmSell && b.close < m_buy.extremeLevel)            // extreme broken
            m_buy.phase=0;
         else
           {
            if(m_buy.phase==1 && b.low<=maLoMax && b.high>=maLoMin) // TPW: hit MA5/10
              { m_buy.phase=2; flags|=BBMA_TPW_BUY; }
            if(m_buy.phase==2 && bull &&
               b.low<=m_buy.extremeLevel+bw*m_s.mhvProxFactor && b.low>m_buy.extremeLevel)
              { m_buy.phase=3; flags|=BBMA_MHV_BUY; }      // retest held, no break
            if(m_buy.phase==3 && (csakBuy||csmBuy))
              { m_buy.phase=4; flags|=BBMA_DIR_BUY; }      // first CSAK/CSM after MHV
           }
        }
      else if(m_buy.phase>=1 && m_bar-m_buy.extremeBar>m_s.seqLookback)
         m_buy.phase=0;

      //--- full-setup sequence (sell) -------------------------------
      if(exSell){ m_sell.phase=1; m_sell.extremeBar=m_bar; m_sell.extremeLevel=b.high; }
      if(m_sell.phase>=1 && m_bar-m_sell.extremeBar<=m_s.seqLookback)
        {
         if(csmBuy && b.close > m_sell.extremeLevel)
            m_sell.phase=0;
         else
           {
            if(m_sell.phase==1 && b.high>=maHiMin && b.low<=maHiMax)
              { m_sell.phase=2; flags|=BBMA_TPW_SELL; }
            if(m_sell.phase==2 && bear &&
               b.high>=m_sell.extremeLevel-bw*m_s.mhvProxFactor && b.high<m_sell.extremeLevel)
              { m_sell.phase=3; flags|=BBMA_MHV_SELL; }
            if(m_sell.phase==3 && (csakSell||csmSell))
              { m_sell.phase=4; flags|=BBMA_DIR_SELL; }
           }
        }
      else if(m_sell.phase>=1 && m_bar-m_sell.extremeBar>m_s.seqLookback)
         m_sell.phase=0;

      //--- re-entry: pull back to MA5/10 then reject, after a CSAK/CSM.
      // Edge-triggered: one touch-and-reject = one signal (the raw
      // condition must have been false on the previous bar).
      bool reBuyCond  = bull && b.low  <= maLoMax && b.close > maLoMax;
      bool reSellCond = bear && b.high >= maHiMin && b.close < maHiMin;
      bool reBuyEdge  = reBuyCond  && !m_prevReBuy;
      bool reSellEdge = reSellCond && !m_prevReSell;
      if(m_impBuyBar>0 && m_bar>m_impBuyBar && m_bar-m_impBuyBar<=m_s.reentryMaxBars &&
         m_impBuyRe<m_s.maxReentries && reBuyEdge &&
         (!m_s.reentryEmaFilter || b.close>b.ema50))
        { flags|=BBMA_REENTRY_BUY; m_impBuyRe++; }
      if(m_impSellBar>0 && m_bar>m_impSellBar && m_bar-m_impSellBar<=m_s.reentryMaxBars &&
         m_impSellRe<m_s.maxReentries && reSellEdge &&
         (!m_s.reentryEmaFilter || b.close<b.ema50))
        { flags|=BBMA_REENTRY_SELL; m_impSellRe++; }

      //--- remember this bar for next step's edge comparisons --------
      m_prevReBuy  = reBuyCond;
      m_prevReSell = reSellCond;
      m_prev       = b;
      m_hasPrev    = true;

      return flags;
     }
  };

//+------------------------------------------------------------------+
//| Indicator handles for one symbol/timeframe                       |
//+------------------------------------------------------------------+
struct BBMAHandles { int bb, ma5h, ma10h, ma5l, ma10l, ema50; };

bool BBMACreateHandles(const string sym, const ENUM_TIMEFRAMES tf, BBMAHandles &h)
  {
   h.bb    = iBands(sym, tf, 20, 0, 2.0, PRICE_CLOSE);
   h.ma5h  = iMA(sym, tf, 5,  0, MODE_LWMA, PRICE_HIGH);
   h.ma10h = iMA(sym, tf, 10, 0, MODE_LWMA, PRICE_HIGH);
   h.ma5l  = iMA(sym, tf, 5,  0, MODE_LWMA, PRICE_LOW);
   h.ma10l = iMA(sym, tf, 10, 0, MODE_LWMA, PRICE_LOW);
   h.ema50 = iMA(sym, tf, 50, 0, MODE_EMA,  PRICE_CLOSE);
   return h.bb!=INVALID_HANDLE && h.ma5h!=INVALID_HANDLE && h.ma10h!=INVALID_HANDLE &&
          h.ma5l!=INVALID_HANDLE && h.ma10l!=INVALID_HANDLE && h.ema50!=INVALID_HANDLE;
  }

void BBMAReleaseHandles(BBMAHandles &h)
  {
   IndicatorRelease(h.bb);    IndicatorRelease(h.ma5h);  IndicatorRelease(h.ma10h);
   IndicatorRelease(h.ma5l);  IndicatorRelease(h.ma10l); IndicatorRelease(h.ema50);
  }

//+------------------------------------------------------------------+
//| Multi-timeframe signal validation                                |
//|   - a CSM is valid only if the TF above printed a CSAK (same dir) |
//|   - an Extreme (CSE) is valid only if the TF above printed an MHV |
//| The "TF above" follows the BBMA ladder M5-M15-H1-H4-D1-W1.        |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES BBMAParentTF(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return(PERIOD_M5);
      case PERIOD_M5:  return(PERIOD_M15);
      case PERIOD_M15: return(PERIOD_H1);
      case PERIOD_M30: return(PERIOD_H1);
      case PERIOD_H1:  return(PERIOD_H4);
      case PERIOD_H4:  return(PERIOD_D1);
      case PERIOD_D1:  return(PERIOD_W1);
      case PERIOD_W1:  return(PERIOD_MN1);
      default:         return(PERIOD_D1);
     }
  }

//--- build a time-indexed flag series for one TF (index 0 = newest closed)
int BBMABuildSeries(const string sym,const ENUM_TIMEFRAMES tf,BBMAHandles &h,
                    const BBMASettings &s,const int maxBars,int &out[],datetime &outTime[])
  {
   int avail=Bars(sym,tf);
   int cnt=MathMin(maxBars,avail-60);
   if(cnt<100) return(0);
   if(BarsCalculated(h.bb)<cnt+1 || BarsCalculated(h.ema50)<cnt+1) return(0);

   int need=cnt+1;
   double o[],hi[],lo[],cl[],u[],m[],l[],a5h[],a10h[],a5l[],a10l[],e[];
   datetime tm[];
   ArraySetAsSeries(o,true); ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
   ArraySetAsSeries(cl,true);ArraySetAsSeries(u,true);  ArraySetAsSeries(m,true);
   ArraySetAsSeries(l,true); ArraySetAsSeries(a5h,true); ArraySetAsSeries(a10h,true);
   ArraySetAsSeries(a5l,true);ArraySetAsSeries(a10l,true);ArraySetAsSeries(e,true);
   ArraySetAsSeries(tm,true);

   if(CopyTime(sym,tf,0,need,tm)   <need) return(0);
   if(CopyOpen(sym,tf,0,need,o)    <need) return(0);
   if(CopyHigh(sym,tf,0,need,hi)   <need) return(0);
   if(CopyLow(sym,tf,0,need,lo)    <need) return(0);
   if(CopyClose(sym,tf,0,need,cl)  <need) return(0);
   if(CopyBuffer(h.bb,   1,0,need,u)  <need) return(0);
   if(CopyBuffer(h.bb,   0,0,need,m)  <need) return(0);
   if(CopyBuffer(h.bb,   2,0,need,l)  <need) return(0);
   if(CopyBuffer(h.ma5h, 0,0,need,a5h)<need) return(0);
   if(CopyBuffer(h.ma10h,0,0,need,a10h)<need)return(0);
   if(CopyBuffer(h.ma5l, 0,0,need,a5l)<need) return(0);
   if(CopyBuffer(h.ma10l,0,0,need,a10l)<need)return(0);
   if(CopyBuffer(h.ema50,0,0,need,e)  <need) return(0);

   ArrayResize(out,cnt);     ArrayInitialize(out,0);
   ArrayResize(outTime,cnt);

   CBBMAEngine eng; eng.Init(s);
   for(int pos=cnt;pos>=1;pos--)   // oldest -> newest closed bar
     {
      BBMABar b;
      b.open=o[pos]; b.high=hi[pos]; b.low=lo[pos]; b.close=cl[pos];
      b.bbTop=u[pos]; b.bbMid=m[pos]; b.bbLow=l[pos];
      b.ma5h=a5h[pos]; b.ma10h=a10h[pos]; b.ma5l=a5l[pos]; b.ma10l=a10l[pos];
      b.ema50=e[pos];
      int f=0;
      if(b.bbTop!=0.0 && b.bbLow!=0.0 && b.ema50!=0.0) f=eng.Step(b);
      out[pos-1]=f;
      outTime[pos-1]=tm[pos];
     }
   return(cnt);
  }

//--- true if the parent series carries `mask` within `window` bars up to t
bool BBMASeriesHasBefore(const int &pf[],const datetime &pt[],const datetime t,
                         const int window,const int mask)
  {
   int n=ArraySize(pf);
   if(n<=0) return(false);
   int start=-1;                         // newest parent bar at or before t
   for(int i=0;i<n;i++) if(pt[i]<=t){ start=i; break; }
   if(start<0) return(false);
   int last=MathMin(n-1,start+window-1);
   for(int i=start;i<=last;i++) if((pf[i]&mask)!=0) return(true);
   return(false);
  }

//--- the parent series' time span covers t (so validation is meaningful)
bool BBMASeriesCovers(const datetime &pt[],const datetime t)
  {
   int n=ArraySize(pt);
   return(n>0 && t>=pt[n-1]);
  }

//--- strip CSM/CSE bits that the TF above does not confirm
int BBMAApplyMtfValidation(int flags,const datetime t,const int &pf[],
                           const datetime &pt[],const int window)
  {
   if(!BBMASeriesCovers(pt,t)) return(flags);   // outside coverage -> leave as-is
   if((flags&BBMA_CSM_BUY)     !=0 && !BBMASeriesHasBefore(pf,pt,t,window,BBMA_CSAK_BUY))  flags&=~BBMA_CSM_BUY;
   if((flags&BBMA_CSM_SELL)    !=0 && !BBMASeriesHasBefore(pf,pt,t,window,BBMA_CSAK_SELL)) flags&=~BBMA_CSM_SELL;
   if((flags&BBMA_EXTREME_BUY) !=0 && !BBMASeriesHasBefore(pf,pt,t,window,BBMA_MHV_BUY))   flags&=~BBMA_EXTREME_BUY;
   if((flags&BBMA_EXTREME_SELL)!=0 && !BBMASeriesHasBefore(pf,pt,t,window,BBMA_MHV_SELL))  flags&=~BBMA_EXTREME_SELL;
   return(flags);
  }

#endif
