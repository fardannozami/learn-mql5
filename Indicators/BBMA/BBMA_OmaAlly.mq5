//+------------------------------------------------------------------+
//| BBMA_OmaAlly.mq5                                                 |
//| Draws BBMA (Oma Ally) lines + labels every signal on the chart   |
//| so the rules can be verified by hand. Logic: BBMA_Engine.mqh.     |
//| Signals: CSE(extreme) TPW MHV CSAK CSM Dir Re MA50(rejEMA) Gap    |
//+------------------------------------------------------------------+
#property copyright "learn-mql5"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8

#include <BBMA/BBMA_Engine.mqh>

//--- plots: the BBMA line set
#property indicator_label1  "BB Upper";  #property indicator_type1  DRAW_LINE; #property indicator_color1  clrLimeGreen; #property indicator_style1 STYLE_SOLID
#property indicator_label2  "BB Mid";    #property indicator_type2  DRAW_LINE; #property indicator_color2  clrLimeGreen; #property indicator_style2 STYLE_DOT
#property indicator_label3  "BB Lower";  #property indicator_type3  DRAW_LINE; #property indicator_color3  clrLimeGreen; #property indicator_style3 STYLE_SOLID
#property indicator_label4  "MA5 High";  #property indicator_type4  DRAW_LINE; #property indicator_color4  clrRed
#property indicator_label5  "MA10 High"; #property indicator_type5  DRAW_LINE; #property indicator_color5  clrOrangeRed
#property indicator_label6  "MA5 Low";   #property indicator_type6  DRAW_LINE; #property indicator_color6  clrDodgerBlue
#property indicator_label7  "MA10 Low";  #property indicator_type7  DRAW_LINE; #property indicator_color7  clrRoyalBlue
#property indicator_label8  "EMA 50";    #property indicator_type8  DRAW_LINE; #property indicator_color8  clrAqua; #property indicator_width8 2

input group "Signal rules (verify on chart)"
input int    InpSeqLookback     = 30;    // bars after extreme for TPW/MHV/Dir
input int    InpReentryMaxBars  = 30;    // bars after CSAK/CSM a re-entry stays valid
input int    InpMaxReentries    = 3;     // re-entries per CSAK/CSM impulse
input bool   InpReentryEmaFilter= false; // buy re-entry only above EMA50
input double InpMhvProxFactor    = 0.5;  // retest proximity to extreme (x band width)

input group "Which labels to show"
input bool   InpShowExtreme = true;
input bool   InpShowTPW     = true;
input bool   InpShowMHV     = true;
input bool   InpShowCSAK    = true;
input bool   InpShowCSM     = true;
input bool   InpShowDir     = true;
input bool   InpShowReentry = true;
input bool   InpShowRejEMA  = true;
input bool   InpShowGap     = true;

input group "Appearance"
input int    InpFontSize    = 8;
input string InpFontName    = "Arial";
input bool   InpShowLines   = true;      // draw BB / MA / EMA lines
input bool   InpAlertReentry= false;     // popup alert on a new re-entry

//--- buffers
double BufBBU[], BufBBM[], BufBBL[], BufMA5H[], BufMA10H[], BufMA5L[], BufMA10L[], BufEMA[];

//--- state
BBMAHandles  g_h;
CBBMAEngine  g_engine;
int          g_processed = 0;
string       PREFIX = "BBMA_";
#define      WARMUP 60

//--- one label definition
struct SigDef { int mask; string txt; color clr; bool buy; bool show; };
SigDef g_defs[18];
int    g_nDefs = 0;

void AddDef(const int mask,const string txt,const color clr,const bool buy,const bool show)
  { g_defs[g_nDefs].mask=mask; g_defs[g_nDefs].txt=txt; g_defs[g_nDefs].clr=clr;
    g_defs[g_nDefs].buy=buy;   g_defs[g_nDefs].show=show; g_nDefs++; }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(StringFind(_Symbol,"XAU")<0)
      Print("BBMA_OmaAlly: note - built for XAUUSD, current symbol is ",_Symbol);

   SetIndexBuffer(0,BufBBU,  INDICATOR_DATA);
   SetIndexBuffer(1,BufBBM,  INDICATOR_DATA);
   SetIndexBuffer(2,BufBBL,  INDICATOR_DATA);
   SetIndexBuffer(3,BufMA5H, INDICATOR_DATA);
   SetIndexBuffer(4,BufMA10H,INDICATOR_DATA);
   SetIndexBuffer(5,BufMA5L, INDICATOR_DATA);
   SetIndexBuffer(6,BufMA10L,INDICATOR_DATA);
   SetIndexBuffer(7,BufEMA,  INDICATOR_DATA);

   for(int i=0;i<8;i++) PlotIndexSetInteger(i,PLOT_DRAW_TYPE, InpShowLines?PlotIndexGetInteger(i,PLOT_DRAW_TYPE):DRAW_NONE);

   if(!BBMACreateHandles(_Symbol,_Period,g_h))
     { Print("BBMA_OmaAlly: failed to create indicator handles"); return(INIT_FAILED); }

   IndicatorSetString(INDICATOR_SHORTNAME,"BBMA Oma Ally");

   //--- label catalog (order controls stacking)
   g_nDefs=0;
   AddDef(BBMA_EXTREME_BUY ,"CSE" ,clrOrange     ,true ,InpShowExtreme);
   AddDef(BBMA_TPW_BUY     ,"TPW" ,clrGold       ,true ,InpShowTPW);
   AddDef(BBMA_MHV_BUY     ,"MHV" ,clrMagenta    ,true ,InpShowMHV);
   AddDef(BBMA_CSAK_BUY    ,"CSAK",clrAqua       ,true ,InpShowCSAK);
   AddDef(BBMA_CSM_BUY     ,"CSM" ,clrDeepSkyBlue,true ,InpShowCSM);
   AddDef(BBMA_DIR_BUY     ,"Dir" ,clrWhite      ,true ,InpShowDir);
   AddDef(BBMA_REJECT_EMA_BUY,"MA50",clrChartreuse,true,InpShowRejEMA);
   AddDef(BBMA_GAP_BUY     ,"Gap" ,clrViolet     ,true ,InpShowGap);
   AddDef(BBMA_REENTRY_BUY ,"Re"  ,clrLime       ,true ,InpShowReentry);

   AddDef(BBMA_EXTREME_SELL,"CSE" ,clrOrange     ,false,InpShowExtreme);
   AddDef(BBMA_TPW_SELL    ,"TPW" ,clrGold       ,false,InpShowTPW);
   AddDef(BBMA_MHV_SELL    ,"MHV" ,clrMagenta    ,false,InpShowMHV);
   AddDef(BBMA_CSAK_SELL   ,"CSAK",clrAqua       ,false,InpShowCSAK);
   AddDef(BBMA_CSM_SELL    ,"CSM" ,clrDeepSkyBlue,false,InpShowCSM);
   AddDef(BBMA_DIR_SELL    ,"Dir" ,clrWhite      ,false,InpShowDir);
   AddDef(BBMA_REJECT_EMA_SELL,"MA50",clrChartreuse,false,InpShowRejEMA);
   AddDef(BBMA_GAP_SELL    ,"Gap" ,clrViolet     ,false,InpShowGap);
   AddDef(BBMA_REENTRY_SELL,"Re"  ,clrRed        ,false,InpShowReentry);

   g_processed=0;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,PREFIX);
   BBMAReleaseHandles(g_h);
  }

//+------------------------------------------------------------------+
void DrawBarSignals(const datetime t,const double hi,const double lo,
                    const int flags,const double bw)
  {
   double off = (bw>0.0 ? bw*0.06 : 10*_Point);
   int buySlot=0, sellSlot=0;
   for(int k=0;k<g_nDefs;k++)
     {
      if(!g_defs[k].show) continue;
      if((flags & g_defs[k].mask)==0) continue;

      double price; ENUM_ANCHOR_POINT anchor;
      if(g_defs[k].buy){ price=lo-off*(1+buySlot);  anchor=ANCHOR_UPPER; buySlot++; }
      else            { price=hi+off*(1+sellSlot); anchor=ANCHOR_LOWER; sellSlot++; }

      string name=PREFIX+g_defs[k].txt+(g_defs[k].buy?"_B_":"_S_")+(string)(long)t;
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TEXT,0,t,price);
      ObjectSetDouble (0,name,OBJPROP_PRICE,price);
      ObjectSetInteger(0,name,OBJPROP_TIME,t);
      ObjectSetString (0,name,OBJPROP_TEXT,g_defs[k].txt);
      ObjectSetInteger(0,name,OBJPROP_COLOR,g_defs[k].clr);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,InpFontSize);
      ObjectSetString (0,name,OBJPROP_FONT,InpFontName);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
     }
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   if(rates_total<WARMUP+2) return(0);
   if(BarsCalculated(g_h.bb)<rates_total || BarsCalculated(g_h.ema50)<rates_total)
      return(prev_calculated);  // indicator data not ready yet

   ArraySetAsSeries(time,false);  ArraySetAsSeries(open,false);
   ArraySetAsSeries(high,false);  ArraySetAsSeries(low,false);
   ArraySetAsSeries(close,false);

   //--- fill the line buffers straight from the sub-indicators
   if(CopyBuffer(g_h.bb,   1,0,rates_total,BufBBU)  <=0) return(prev_calculated);
   if(CopyBuffer(g_h.bb,   0,0,rates_total,BufBBM)  <=0) return(prev_calculated);
   if(CopyBuffer(g_h.bb,   2,0,rates_total,BufBBL)  <=0) return(prev_calculated);
   if(CopyBuffer(g_h.ma5h, 0,0,rates_total,BufMA5H) <=0) return(prev_calculated);
   if(CopyBuffer(g_h.ma10h,0,0,rates_total,BufMA10H)<=0) return(prev_calculated);
   if(CopyBuffer(g_h.ma5l, 0,0,rates_total,BufMA5L) <=0) return(prev_calculated);
   if(CopyBuffer(g_h.ma10l,0,0,rates_total,BufMA10L)<=0) return(prev_calculated);
   if(CopyBuffer(g_h.ema50,0,0,rates_total,BufEMA)  <=0) return(prev_calculated);

   //--- (re)start the signal engine on a full recalculation
   if(prev_calculated==0)
     {
      ObjectsDeleteAll(0,PREFIX);
      BBMASettings s; BBMADefaults(s);
      s.seqLookback=InpSeqLookback; s.reentryMaxBars=InpReentryMaxBars;
      s.maxReentries=InpMaxReentries; s.reentryEmaFilter=InpReentryEmaFilter;
      s.mhvProxFactor=InpMhvProxFactor;
      g_engine.Init(s);
      g_processed=WARMUP;
     }

   int closedBars=rates_total-1;           // last bar is still forming
   for(int i=g_processed;i<closedBars;i++)
     {
      BBMABar b;
      b.open=open[i];  b.high=high[i];  b.low=low[i];  b.close=close[i];
      b.bbTop=BufBBU[i]; b.bbMid=BufBBM[i]; b.bbLow=BufBBL[i];
      b.ma5h=BufMA5H[i]; b.ma10h=BufMA10H[i]; b.ma5l=BufMA5L[i]; b.ma10l=BufMA10L[i];
      b.ema50=BufEMA[i];
      if(b.bbTop==0.0 || b.bbLow==0.0 || b.ema50==0.0) continue;

      int flags=g_engine.Step(b);
      if(flags!=0)
        {
         DrawBarSignals(time[i],high[i],low[i],flags,b.bbTop-b.bbLow);
         if(InpAlertReentry && i==closedBars-1 &&
            (flags&(BBMA_REENTRY_BUY|BBMA_REENTRY_SELL))!=0)
            Alert(_Symbol," ",EnumToString(_Period)," BBMA Re-entry ",
                  ((flags&BBMA_REENTRY_BUY)!=0)?"BUY":"SELL");
        }
     }
   g_processed=closedBars;
   return(rates_total);
  }
//+------------------------------------------------------------------+
