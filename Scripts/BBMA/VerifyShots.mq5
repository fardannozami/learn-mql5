//+------------------------------------------------------------------+
//| VerifyShots.mq5                                                  |
//| Runs on an XAUUSD H4 chart (its own startup chart), attaches     |
//| BBMA_OmaAlly, navigates to the guidebook example dates and saves  |
//| screenshots to MQL5/Files for visual verification.               |
//+------------------------------------------------------------------+
#property version "1.00"

void StyleChart(const long cid)
  {
   ChartSetInteger(cid,CHART_MODE,CHART_CANDLES);
   ChartSetInteger(cid,CHART_SHOW_GRID,false);
   ChartSetInteger(cid,CHART_COLOR_BACKGROUND,clrBlack);
   ChartSetInteger(cid,CHART_COLOR_FOREGROUND,clrWhite);
   ChartSetInteger(cid,CHART_COLOR_CHART_UP,clrWhite);
   ChartSetInteger(cid,CHART_COLOR_CHART_DOWN,clrWhite);
   ChartSetInteger(cid,CHART_COLOR_CANDLE_BULL,clrLime);
   ChartSetInteger(cid,CHART_COLOR_CANDLE_BEAR,clrRed);
   ChartSetInteger(cid,CHART_SCALE,3);
   ChartSetInteger(cid,CHART_AUTOSCROLL,false);
   ChartSetInteger(cid,CHART_SHIFT,false);
   ChartSetInteger(cid,CHART_SHOW_PERIOD_SEP,true);
  }

void OnStart()
  {
   string sym=_Symbol;
   ENUM_TIMEFRAMES tf=_Period;
   long cid=ChartID();

   int fh=FileOpen("bbma_shots.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   FileWriteString(fh,StringFormat("chart=%s %s\r\n",sym,EnumToString(tf)));

   StyleChart(cid);

   int ind=iCustom(sym,tf,"BBMA\\BBMA_OmaAlly");
   if(ind==INVALID_HANDLE){ FileWriteString(fh,"iCustom FAILED\r\n"); FileClose(fh); return; }
   ResetLastError();
   bool added=ChartIndicatorAdd(cid,0,ind);
   FileWriteString(fh,StringFormat("ChartIndicatorAdd=%s err=%d\r\n",(added?"ok":"fail"),GetLastError()));

   for(int w=0;w<30;w++){ if(BarsCalculated(ind)>2000) break; Sleep(1000); }
   FileWriteString(fh,StringFormat("BarsCalculated=%d\r\n",BarsCalculated(ind)));
   Sleep(2000);

   string dates[]={ "2023.10.31 00:00", "2023.12.19 00:00",
                    "2024.01.11 00:00", "2024.01.05 00:00" };
   string tags[] ={ "A_2023-10-31", "B_2023-12-19",
                    "C_2024-01-11", "D_2024-01-05" };

   for(int i=0;i<ArraySize(dates);i++)
     {
      datetime d=StringToTime(dates[i]);
      // make sure history around the date is loaded
      MqlRates rr[]; CopyRates(sym,tf,d-PeriodSeconds(tf)*300,d+PeriodSeconds(tf)*300,rr);
      int shift=iBarShift(sym,tf,d,false);
      int vis=(int)ChartGetInteger(cid,CHART_VISIBLE_BARS); if(vis<=0) vis=200;

      // navigate so the target sits near the middle, retry until it lands
      datetime gotTime=0;
      for(int k=0;k<10;k++)
        {
         int nav=shift-vis/2; if(nav<0) nav=0;
         ChartNavigate(cid,CHART_END,-nav);
         ChartRedraw(cid);
         Sleep(600);
         int fvb=(int)ChartGetInteger(cid,CHART_FIRST_VISIBLE_BAR);
         gotTime=iTime(sym,tf,fvb);
         if(MathAbs(fvb-(shift+vis/2))<=vis) break;
        }
      Sleep(800);
      string fn="bbma_"+tags[i]+".png";
      bool ok=ChartScreenShot(cid,fn,1600,900,ALIGN_LEFT);
      FileWriteString(fh,StringFormat("%s target=%s shift=%d vis=%d firstVisTime=%s saved=%s\r\n",
                      tags[i],dates[i],shift,vis,TimeToString(gotTime,TIME_DATE|TIME_MINUTES),(ok?"yes":"no")));
     }
   FileWriteString(fh,"DONE\r\n"); FileClose(fh);
  }
