//+------------------------------------------------------------------+
//| BBMA_EA.mq5                                                      |
//| BBMA Oma Ally re-entry EA for XAUUSD.                             |
//| Guidebook logic: the trade is always a RE-ENTRY (after CSAK/CSM) |
//| on the entry timeframe, validated by higher timeframes:          |
//|   - HTF : trend is the same direction (extreme/mhv/dir/reentry)  |
//|   - Mid : a Reject-EMA50 / Gap / Re-entry in the same direction  |
//| Signal logic shared with the indicator via BBMA_Engine.mqh.      |
//+------------------------------------------------------------------+
#property copyright "learn-mql5"
#property version   "1.00"

#include <BBMA/BBMA_Engine.mqh>
#include <Trade/Trade.mqh>

//--- timeframes (default group H4 - H1 - M15)
input group "Timeframes"
input ENUM_TIMEFRAMES InpHtfTF   = PERIOD_H4;   // Higher TF (trend)
input ENUM_TIMEFRAMES InpMidTF   = PERIOD_H1;   // Middle TF (gap / reject EMA50)
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M15;  // Entry TF (re-entry)

input group "Signal rules (match the indicator)"
input int    InpSeqLookback      = 30;
input int    InpReentryMaxBars   = 30;
input int    InpMaxReentries     = 3;
input bool   InpReentryEmaFilter = false;
input double InpMhvProxFactor     = 0.5;

input group "Multi-timeframe confirmation"
input bool   InpUseHTF     = true;   // require HTF trend agreement
input int    InpHtfWindow  = 10;     // bars back to read HTF signal
input bool   InpUseMid     = true;   // require Mid-TF gap/reject/reentry
input int    InpMidWindow  = 10;     // bars back to read Mid signal
input int    InpMinConfirm = 1;      // how many of the above must agree

input group "Risk & execution"
input double InpFixedLot      = 0.01; // used when RiskPercent = 0
input double InpRiskPercent   = 0.0;  // % of balance risked per trade (0 = fixed lot)
input int    InpSwingLookback = 10;   // bars for the swing SL
input int    InpSlBufferPts   = 50;   // extra SL buffer, points (gold: 100 = $1)
input double InpRiskRatio     = 2.0;  // TP = RiskRatio x SL distance
input bool   InpOnePosition   = true; // only one position at a time
input long   InpMagic         = 250011;
input int    InpMaxSpreadPts  = 60;   // skip if spread above this (points)
input int    InpSlippagePts   = 30;

input group "Session filter (server time)"
input bool   InpUseHours   = false;
input int    InpStartHour  = 7;
input int    InpEndHour    = 21;

input group "Dynamic exit (signal-based SL/TP)"
input bool InpUseSignalExit = true;            // close on an opposite BBMA signal
input ENUM_TIMEFRAMES InpExitLowerTF = PERIOD_M5; // lower TF for the CSM exit
input int  InpExitCsmCount  = 2;               // opposite CSM candles on lower TF to exit
input int  InpExitCsmWindow = 6;               // bars back on lower TF to count them
input bool InpUseHardSL     = true;            // keep a protective swing SL (backstop)
input bool InpUseFixedTP    = false;           // also keep the RiskRatio TP target

//--- handles per timeframe
BBMAHandles  g_hEnt, g_hMid, g_hHtf, g_hExit;
BBMASettings g_set;
CTrade       g_trade;
datetime     g_lastBar = 0;
datetime     g_lastExitEnt = 0;   // last entry-TF bar checked for exit
datetime     g_lastExitLow = 0;   // last lower-TF bar checked for exit

#define SCAN_BARS 1200

//+------------------------------------------------------------------+
int OnInit()
  {
   if(StringFind(_Symbol,"XAU")<0)
      Print("BBMA_EA: note - built for XAUUSD, current symbol is ",_Symbol);

   BBMADefaults(g_set);
   g_set.seqLookback=InpSeqLookback; g_set.reentryMaxBars=InpReentryMaxBars;
   g_set.maxReentries=InpMaxReentries; g_set.reentryEmaFilter=InpReentryEmaFilter;
   g_set.mhvProxFactor=InpMhvProxFactor;

   if(!BBMACreateHandles(_Symbol,InpEntryTF,g_hEnt) ||
      !BBMACreateHandles(_Symbol,InpMidTF, g_hMid) ||
      !BBMACreateHandles(_Symbol,InpHtfTF, g_hHtf))
     { Print("BBMA_EA: failed to create indicator handles"); return(INIT_FAILED); }
   if(InpUseSignalExit && !BBMACreateHandles(_Symbol,InpExitLowerTF,g_hExit))
     { Print("BBMA_EA: failed to create lower-TF exit handles"); return(INIT_FAILED); }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePts);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   BBMAReleaseHandles(g_hEnt);
   BBMAReleaseHandles(g_hMid);
   BBMAReleaseHandles(g_hHtf);
   if(InpUseSignalExit) BBMAReleaseHandles(g_hExit);
  }

//+------------------------------------------------------------------+
//| Scan one timeframe: fill out[] with per-bar flags, out[0]=newest |
//| closed bar. Returns number of bars written (0 on failure).       |
//+------------------------------------------------------------------+
int ScanTF(const ENUM_TIMEFRAMES tf,BBMAHandles &h,int &out[])
  {
   int avail=Bars(_Symbol,tf);
   int cnt=MathMin(SCAN_BARS,avail-60);
   if(cnt<100) return(0);
   if(BarsCalculated(h.bb)<cnt+1 || BarsCalculated(h.ema50)<cnt+1) return(0);

   int need=cnt+1; // include the forming bar at index 0
   double o[],hi[],lo[],cl[];
   double u[],m[],l[],a5h[],a10h[],a5l[],a10l[],e[];
   ArraySetAsSeries(o,true);  ArraySetAsSeries(hi,true);
   ArraySetAsSeries(lo,true); ArraySetAsSeries(cl,true);
   ArraySetAsSeries(u,true);  ArraySetAsSeries(m,true);  ArraySetAsSeries(l,true);
   ArraySetAsSeries(a5h,true);ArraySetAsSeries(a10h,true);
   ArraySetAsSeries(a5l,true);ArraySetAsSeries(a10l,true);ArraySetAsSeries(e,true);

   if(CopyOpen(_Symbol,tf,0,need,o)  <need) return(0);
   if(CopyHigh(_Symbol,tf,0,need,hi) <need) return(0);
   if(CopyLow(_Symbol,tf,0,need,lo)  <need) return(0);
   if(CopyClose(_Symbol,tf,0,need,cl)<need) return(0);
   if(CopyBuffer(h.bb,   1,0,need,u)  <need) return(0);
   if(CopyBuffer(h.bb,   0,0,need,m)  <need) return(0);
   if(CopyBuffer(h.bb,   2,0,need,l)  <need) return(0);
   if(CopyBuffer(h.ma5h, 0,0,need,a5h)<need) return(0);
   if(CopyBuffer(h.ma10h,0,0,need,a10h)<need)return(0);
   if(CopyBuffer(h.ma5l, 0,0,need,a5l)<need) return(0);
   if(CopyBuffer(h.ma10l,0,0,need,a10l)<need)return(0);
   if(CopyBuffer(h.ema50,0,0,need,e)  <need) return(0);

   ArrayResize(out,cnt);
   ArrayInitialize(out,0);

   CBBMAEngine eng; eng.Init(g_set);
   for(int pos=cnt;pos>=1;pos--)   // oldest -> newest closed bar
     {
      BBMABar b;
      b.open=o[pos]; b.high=hi[pos]; b.low=lo[pos]; b.close=cl[pos];
      b.bbTop=u[pos]; b.bbMid=m[pos]; b.bbLow=l[pos];
      b.ma5h=a5h[pos]; b.ma10h=a10h[pos]; b.ma5l=a5l[pos]; b.ma10l=a10l[pos];
      b.ema50=e[pos];
      int f=0;
      if(b.bbTop!=0.0 && b.bbLow!=0.0 && b.ema50!=0.0) f=eng.Step(b);
      out[pos-1]=f;   // out[0] = last closed bar
     }
   return(cnt);
  }

//--- direction (+1/-1/0) of the nearest bar carrying a buy/sell mask
int NearestDir(const int &f[],const int window,const int buyMask,const int sellMask)
  {
   int n=MathMin(window,ArraySize(f));
   for(int i=0;i<n;i++)
     {
      if((f[i]&buyMask) !=0) return(+1);
      if((f[i]&sellMask)!=0) return(-1);
     }
   return(0);
  }

//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagic)
         return(true);
     }
   return(false);
  }

double CalcLot(const double slDistance)
  {
   if(InpRiskPercent<=0.0 || slDistance<=0.0) return(InpFixedLot);
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSz =SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickVal<=0.0 || tickSz<=0.0) return(InpFixedLot);
   double lossPerLot=slDistance/tickSz*tickVal;
   if(lossPerLot<=0.0) return(InpFixedLot);
   double risk=AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPercent/100.0;
   double lot =risk/lossPerLot;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step>0.0) lot=MathFloor(lot/step)*step;
   lot=MathMax(vmin,MathMin(vmax,lot));
   return(lot);
  }

bool HoursOk()
  {
   if(!InpUseHours) return(true);
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   if(InpStartHour<=InpEndHour) return(t.hour>=InpStartHour && t.hour<InpEndHour);
   return(t.hour>=InpStartHour || t.hour<InpEndHour); // wraps midnight
  }

//--- our position direction: +1 long, -1 short, 0 none
int GetPositionDir()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagic)
         return((PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?+1:-1);
     }
   return(0);
  }

void CloseOurPositions(const string why)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagic)
        {
         if(!g_trade.PositionClose(tk))
            PrintFormat("BBMA_EA: close failed #%I64u ret=%d %s",tk,
                        g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
         else
            PrintFormat("BBMA_EA: signal exit (%s)",why);
        }
     }
  }

//+------------------------------------------------------------------+
//| Dynamic SL/TP: close an open trade when BBMA reverses --          |
//|  - an opposite CSAK closes on the entry TF, or                    |
//|  - >= InpExitCsmCount opposite CSM candles print on the lower TF  |
//|    within InpExitCsmWindow bars.                                  |
//+------------------------------------------------------------------+
void ManageExit()
  {
   int pdir=GetPositionDir();
   if(pdir==0) return;

   bool newEnt=false, newLow=false;
   datetime te=iTime(_Symbol,InpEntryTF,0);
   datetime tl=iTime(_Symbol,InpExitLowerTF,0);
   if(te!=g_lastExitEnt){ g_lastExitEnt=te; newEnt=true; }
   if(tl!=g_lastExitLow){ g_lastExitLow=tl; newLow=true; }
   if(!newEnt && !newLow) return;   // nothing new closed yet

   //--- opposite CSAK on the entry TF (just-closed bar)
   if(newEnt)
     {
      int fe[];
      if(ScanTF(InpEntryTF,g_hEnt,fe)>0)
        {
         int oppCsak=(pdir>0)?BBMA_CSAK_SELL:BBMA_CSAK_BUY;
         if((fe[0]&oppCsak)!=0){ CloseOurPositions("opposite CSAK on entry TF"); return; }
        }
     }

   //--- opposite CSM cluster on the lower TF
   if(newLow)
     {
      int fl[];
      if(ScanTF(InpExitLowerTF,g_hExit,fl)>0)
        {
         int oppCsm=(pdir>0)?BBMA_CSM_SELL:BBMA_CSM_BUY;
         int w=MathMin(InpExitCsmWindow,ArraySize(fl));
         int c=0;
         for(int i=0;i<w;i++) if((fl[i]&oppCsm)!=0) c++;
         if(c>=InpExitCsmCount){ CloseOurPositions("opposite CSM on lower TF"); return; }
        }
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- dynamic exit first, so a reversal can close before anything else
   if(InpUseSignalExit) ManageExit();

   //--- act once per entry-TF bar
   datetime t=iTime(_Symbol,InpEntryTF,0);
   if(t==g_lastBar) return;
   g_lastBar=t;

   if(InpOnePosition && HasOpenPosition()) return;
   if(!HoursOk()) return;
   if(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>InpMaxSpreadPts) return;

   int fe[]; if(ScanTF(InpEntryTF,g_hEnt,fe)<=0) return;

   int dir=0;
   if((fe[0]&BBMA_REENTRY_BUY) !=0) dir=+1;
   else if((fe[0]&BBMA_REENTRY_SELL)!=0) dir=-1;
   if(dir==0) return;   // no fresh re-entry on the just-closed entry bar

   //--- higher-timeframe confirmations
   int confirm=0;
   if(InpUseHTF)
     {
      int fh[]; if(ScanTF(InpHtfTF,g_hHtf,fh)<=0) return;
      int hd=NearestDir(fh,InpHtfWindow,
             BBMA_EXTREME_BUY|BBMA_MHV_BUY|BBMA_DIR_BUY|BBMA_REENTRY_BUY|BBMA_CSAK_BUY|BBMA_CSM_BUY,
             BBMA_EXTREME_SELL|BBMA_MHV_SELL|BBMA_DIR_SELL|BBMA_REENTRY_SELL|BBMA_CSAK_SELL|BBMA_CSM_SELL);
      if(hd==dir) confirm++; else if(hd==-dir) return; // HTF opposes -> skip
     }
   if(InpUseMid)
     {
      int fm[]; if(ScanTF(InpMidTF,g_hMid,fm)<=0) return;
      int md=NearestDir(fm,InpMidWindow,
             BBMA_REJECT_EMA_BUY|BBMA_GAP_BUY|BBMA_REENTRY_BUY,
             BBMA_REJECT_EMA_SELL|BBMA_GAP_SELL|BBMA_REENTRY_SELL);
      if(md==dir) confirm++; else if(md==-dir) return;
     }
   if(confirm<InpMinConfirm) return;

   //--- swing-based stop
   int sl_lb=MathMax(2,InpSwingLookback);
   double lows[],highs[];
   if(CopyLow(_Symbol,InpEntryTF,1,sl_lb,lows)  <sl_lb) return;
   if(CopyHigh(_Symbol,InpEntryTF,1,sl_lb,highs)<sl_lb) return;
   double buf=InpSlBufferPts*_Point;
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   int dg=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);

   double entry,sl,tp,slDist;
   if(dir>0)
     {
      entry=ask;
      sl=lows[ArrayMinimum(lows)]-buf;
      slDist=entry-sl;
      if(slDist<=buf) return;
      tp=entry+InpRiskRatio*slDist;
     }
   else
     {
      entry=bid;
      sl=highs[ArrayMaximum(highs)]+buf;
      slDist=sl-entry;
      if(slDist<=buf) return;
      tp=entry-InpRiskRatio*slDist;
     }
   //--- with dynamic exit on, the swing SL is only a backstop and the
   //    fixed TP is off by default (let the reversal signal take profit).
   double slOut=(InpUseHardSL ? NormalizeDouble(sl,dg) : 0.0);
   double tpOut=(InpUseFixedTP ? NormalizeDouble(tp,dg) : 0.0);
   double lot=CalcLot(slDist);

   bool ok = (dir>0) ? g_trade.Buy(lot,_Symbol,0.0,slOut,tpOut,"BBMA Re-entry")
                     : g_trade.Sell(lot,_Symbol,0.0,slOut,tpOut,"BBMA Re-entry");
   if(!ok)
      PrintFormat("BBMA_EA: order failed dir=%d ret=%d %s",
                  dir,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
  }
//+------------------------------------------------------------------+
