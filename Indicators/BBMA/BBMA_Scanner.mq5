//+------------------------------------------------------------------+
//| BBMA_Scanner.mq5                                                 |
//| One-symbol (XAUUSD) multi-timeframe BBMA dashboard row.          |
//| Shows the latest signal on W1/D1/H4/H1/M15/M5 and flags the      |
//| named MTF setups (Full/REE/RRE/RRM/REM/Diamond).                 |
//| Shared logic: BBMA_Engine.mqh.                                   |
//+------------------------------------------------------------------+
#property copyright "learn-mql5"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#include <BBMA/BBMA_Engine.mqh>

input group "Signal rules (match the indicator)"
input int    InpSeqLookback      = 30;
input int    InpReentryMaxBars   = 30;
input int    InpMaxReentries     = 3;
input bool   InpReentryEmaFilter = false;
input double InpMhvProxFactor     = 0.5;
input int    InpWindow           = 10;   // bars back a signal stays "current"

input group "Panel"
input int    InpCorner   = 0;   // 0 LU, 1 RU, 2 LL, 3 RL
input int    InpX        = 12;
input int    InpY        = 20;
input int    InpColW     = 46;
input int    InpRowH     = 18;
input int    InpFont     = 9;
input string InpFontName = "Consolas";
input int    InpRefreshSec = 3;

#define NTF 6
string         PREFIX="BBMAscan_";
ENUM_TIMEFRAMES g_tf[NTF];
string          g_tfName[NTF];
BBMAHandles     g_h[NTF];
BBMASettings    g_set;
#define SCAN_BARS 1500

//--- per-timeframe scan result
struct TFScan
  {
   bool ok;
   int  dRe,dEx,dMHV,dRejGap,dDir,dTPW,dCSM,dCSAK,dFull;
   string label; int ldir;  // most recent signal for the cell
  };
TFScan g_scan[NTF];

//+------------------------------------------------------------------+
int OnInit()
  {
   g_tf[0]=PERIOD_W1;  g_tfName[0]="W1";
   g_tf[1]=PERIOD_D1;  g_tfName[1]="D1";
   g_tf[2]=PERIOD_H4;  g_tfName[2]="H4";
   g_tf[3]=PERIOD_H1;  g_tfName[3]="H1";
   g_tf[4]=PERIOD_M15; g_tfName[4]="M15";
   g_tf[5]=PERIOD_M5;  g_tfName[5]="M5";

   if(StringFind(_Symbol,"XAU")<0)
      Print("BBMA_Scanner: note - built for XAUUSD, current symbol is ",_Symbol);

   BBMADefaults(g_set);
   g_set.seqLookback=InpSeqLookback; g_set.reentryMaxBars=InpReentryMaxBars;
   g_set.maxReentries=InpMaxReentries; g_set.reentryEmaFilter=InpReentryEmaFilter;
   g_set.mhvProxFactor=InpMhvProxFactor;

   for(int i=0;i<NTF;i++)
      if(!BBMACreateHandles(_Symbol,g_tf[i],g_h[i]))
        { Print("BBMA_Scanner: handles failed for ",g_tfName[i]); return(INIT_FAILED); }

   IndicatorSetString(INDICATOR_SHORTNAME,"BBMA Scanner");
   EventSetTimer(MathMax(1,InpRefreshSec));
   Scan(); Draw();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0,PREFIX);
   for(int i=0;i<NTF;i++) BBMAReleaseHandles(g_h[i]);
  }

void OnTimer() { Scan(); Draw(); }
int OnCalculate(const int r,const int p,const int b,const double &pr[]) { return(r); }

//+------------------------------------------------------------------+
//| Fill out[] with per-bar flags for one TF, out[0]=newest closed.  |
//+------------------------------------------------------------------+
int ScanTF(const ENUM_TIMEFRAMES tf,BBMAHandles &h,int &out[])
  {
   int avail=Bars(_Symbol,tf);
   int cnt=MathMin(SCAN_BARS,avail-60);
   if(cnt<80) return(0);
   if(BarsCalculated(h.bb)<cnt+1 || BarsCalculated(h.ema50)<cnt+1) return(0);

   int need=cnt+1;
   double o[],hi[],lo[],cl[],u[],m[],l[],a5h[],a10h[],a5l[],a10l[],e[];
   ArraySetAsSeries(o,true);  ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
   ArraySetAsSeries(cl,true); ArraySetAsSeries(u,true);  ArraySetAsSeries(m,true);
   ArraySetAsSeries(l,true);  ArraySetAsSeries(a5h,true);ArraySetAsSeries(a10h,true);
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

   ArrayResize(out,cnt); ArrayInitialize(out,0);
   CBBMAEngine eng; eng.Init(g_set);
   for(int pos=cnt;pos>=1;pos--)
     {
      BBMABar b;
      b.open=o[pos]; b.high=hi[pos]; b.low=lo[pos]; b.close=cl[pos];
      b.bbTop=u[pos]; b.bbMid=m[pos]; b.bbLow=l[pos];
      b.ma5h=a5h[pos]; b.ma10h=a10h[pos]; b.ma5l=a5l[pos]; b.ma10l=a10l[pos];
      b.ema50=e[pos];
      int f=0;
      if(b.bbTop!=0.0 && b.bbLow!=0.0 && b.ema50!=0.0) f=eng.Step(b);
      out[pos-1]=f;
     }
   return(cnt);
  }

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

//--- decode the most recent bar's top-priority signal for the cell
void CellLabel(const int &f[],const int window,string &label,int &dir)
  {
   label="-"; dir=0;
   int n=MathMin(window,ArraySize(f));
   for(int i=0;i<n;i++)
     {
      int v=f[i];
      if(v==0) continue;
      if((v&BBMA_REENTRY_BUY) !=0){ label="Re";  dir=+1; return; }
      if((v&BBMA_REENTRY_SELL)!=0){ label="Re";  dir=-1; return; }
      if((v&BBMA_DIR_BUY)     !=0){ label="Dir"; dir=+1; return; }
      if((v&BBMA_DIR_SELL)    !=0){ label="Dir"; dir=-1; return; }
      if((v&BBMA_CSM_BUY)     !=0){ label="CSM"; dir=+1; return; }
      if((v&BBMA_CSM_SELL)    !=0){ label="CSM"; dir=-1; return; }
      if((v&BBMA_CSAK_BUY)    !=0){ label="CSAK";dir=+1; return; }
      if((v&BBMA_CSAK_SELL)   !=0){ label="CSAK";dir=-1; return; }
      if((v&BBMA_MHV_BUY)     !=0){ label="MHV"; dir=+1; return; }
      if((v&BBMA_MHV_SELL)    !=0){ label="MHV"; dir=-1; return; }
      if((v&BBMA_TPW_BUY)     !=0){ label="TPW"; dir=+1; return; }
      if((v&BBMA_TPW_SELL)    !=0){ label="TPW"; dir=-1; return; }
      if((v&BBMA_EXTREME_BUY) !=0){ label="CSE"; dir=+1; return; }
      if((v&BBMA_EXTREME_SELL)!=0){ label="CSE"; dir=-1; return; }
      if((v&BBMA_GAP_BUY)     !=0){ label="Gap"; dir=+1; return; }
      if((v&BBMA_GAP_SELL)    !=0){ label="Gap"; dir=-1; return; }
      if((v&BBMA_REJECT_EMA_BUY) !=0){ label="MA50"; dir=+1; return; }
      if((v&BBMA_REJECT_EMA_SELL)!=0){ label="MA50"; dir=-1; return; }
     }
  }

//+------------------------------------------------------------------+
void Scan()
  {
   for(int i=0;i<NTF;i++)
     {
      TFScan s; s.ok=false; s.label="-"; s.ldir=0;
      s.dRe=s.dEx=s.dMHV=s.dRejGap=s.dDir=s.dTPW=s.dCSM=s.dCSAK=s.dFull=0;
      int f[];
      if(ScanTF(g_tf[i],g_h[i],f)>0)
        {
         s.ok=true;
         s.dRe =NearestDir(f,InpWindow,BBMA_REENTRY_BUY,BBMA_REENTRY_SELL);
         s.dEx =NearestDir(f,InpWindow,BBMA_EXTREME_BUY,BBMA_EXTREME_SELL);
         s.dMHV=NearestDir(f,InpWindow,BBMA_MHV_BUY,BBMA_MHV_SELL);
         s.dDir=NearestDir(f,InpWindow,BBMA_DIR_BUY,BBMA_DIR_SELL);
         s.dTPW=NearestDir(f,InpWindow,BBMA_TPW_BUY,BBMA_TPW_SELL);
         s.dCSM=NearestDir(f,InpWindow,BBMA_CSM_BUY,BBMA_CSM_SELL);
         s.dCSAK=NearestDir(f,InpWindow,BBMA_CSAK_BUY,BBMA_CSAK_SELL);
         s.dRejGap=NearestDir(f,InpWindow,
                   BBMA_REJECT_EMA_BUY|BBMA_GAP_BUY,
                   BBMA_REJECT_EMA_SELL|BBMA_GAP_SELL);
         // rough single-TF "full setup": extreme->mhv->dir->reentry same way
         if(s.dEx!=0 && s.dEx==s.dMHV && s.dMHV==s.dDir && s.dDir==s.dRe)
            s.dFull=s.dEx;
         CellLabel(f,InpWindow,s.label,s.ldir);
        }
      g_scan[i]=s;
     }
  }

//--- name the best MTF setup for a (hi,mid,lo) group in direction D
string GroupSetup(const int hi,const int mid,const int lo,int &outDir)
  {
   outDir=0;
   for(int si=0;si<2;si++)
     {
      int D=(si==0)?+1:-1;
      TFScan H=g_scan[hi], M=g_scan[mid], L=g_scan[lo];
      if(!H.ok || !M.ok || !L.ok) continue;
      if(H.dRe!=D) continue;                        // HTF must be a re-entry
      // Diamond: mid reject/gap, lo extreme/mhv/full
      if(M.dRejGap==D && (L.dEx==D || L.dMHV==D || L.dFull==D)) { outDir=D; return("Diamond"); }
      if(M.dRe==D && L.dEx==D)  { outDir=D; return("RRE"); }
      if(M.dRe==D && L.dMHV==D) { outDir=D; return("RRM"); }
      if(M.dEx==D && L.dEx==D)  { outDir=D; return("REE"); }
      if(M.dEx==D && L.dMHV==D) { outDir=D; return("REM"); }
      if(L.dFull==D)            { outDir=D; return("Full"); }
     }
   return("");
  }

//+------------------------------------------------------------------+
void MkLabel(const string tag,const int x,const int y,const string text,
             const color clr,const int fsz)
  {
   string name=PREFIX+tag;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fsz);
   ObjectSetString (0,name,OBJPROP_FONT,InpFontName);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }

color DirColor(const int d){ return d>0?clrLime:(d<0?clrTomato:clrGray); }

void Draw()
  {
   ObjectsDeleteAll(0,PREFIX);
   int x0=InpX, y=InpY;

   MkLabel("title",x0,y,"BBMA "+_Symbol,clrWhite,InpFont+1);
   y+=InpRowH+2;

   // header: blank + TF names
   MkLabel("h_sym",x0,y,"TF",clrSilver,InpFont);
   for(int i=0;i<NTF;i++)
      MkLabel("h_"+g_tfName[i],x0+(i+1)*InpColW,y,g_tfName[i],clrSilver,InpFont);
   y+=InpRowH;

   // signal row
   MkLabel("r_sym",x0,y,"Sig",clrSilver,InpFont);
   for(int i=0;i<NTF;i++)
     {
      color c=g_scan[i].ok?DirColor(g_scan[i].ldir):clrDimGray;
      MkLabel("r_"+g_tfName[i],x0+(i+1)*InpColW,y,g_scan[i].label,c,InpFont);
     }
   y+=InpRowH+4;

   // setups per TF group
   MkLabel("s_hdr",x0,y,"Setups:",clrSilver,InpFont); y+=InpRowH;
   int groups[4][3]; // hi,mid,lo
   groups[0][0]=0; groups[0][1]=1; groups[0][2]=2; // W1 D1 H4
   groups[1][0]=1; groups[1][1]=2; groups[1][2]=3; // D1 H4 H1
   groups[2][0]=2; groups[2][1]=3; groups[2][2]=4; // H4 H1 M15
   groups[3][0]=3; groups[3][1]=4; groups[3][2]=5; // H1 M15 M5
   for(int g=0;g<4;g++)
     {
      int hi=groups[g][0], mid=groups[g][1], lo=groups[g][2];
      string gname=g_tfName[hi]+"-"+g_tfName[mid]+"-"+g_tfName[lo];
      int d=0; string setup=GroupSetup(hi,mid,lo,d);
      string txt=gname+" : "+(setup==""?"-":setup+" "+(d>0?"BUY":"SELL"));
      MkLabel("g_"+(string)g,x0,y,txt,setup==""?clrGray:DirColor(d),InpFont);
      y+=InpRowH;
     }
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
