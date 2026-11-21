//+------------------------------------------------------------------+
//| DownloadHistory.mq5                                              |
//| Forces MT5 to download XAUUSD history for the BBMA timeframes,    |
//| then writes a summary to MQL5/Files/bbma_download.txt.            |
//| Run inside a logged-in terminal (history needs a connection).    |
//+------------------------------------------------------------------+
#property script_show_inputs
#property version "1.00"

input datetime InpStart = D'2021.01.01';  // earliest date to pull

string FindGold()
  {
   if(SymbolSelect("XAUUSD",true)) return("XAUUSD");
   int tot=SymbolsTotal(false);
   for(int i=0;i<tot;i++)
     {
      string nm=SymbolName(i,false);
      if(StringFind(nm,"XAU")>=0 && StringFind(nm,"USD")>=0)
        { SymbolSelect(nm,true); return(nm); }
     }
   return("XAUUSD");
  }

void OnStart()
  {
   string sym=FindGold();
   datetime endt=D'2027.01.01';

   ENUM_TIMEFRAMES tfs[]={PERIOD_W1,PERIOD_D1,PERIOD_H4,PERIOD_H1,PERIOD_M15,PERIOD_M5};
   string names[]={"W1","D1","H4","H1","M15","M5"};

   int fh=FileOpen("bbma_download.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   string hdr=StringFormat("symbol=%s  start>=%s",sym,TimeToString(InpStart,TIME_DATE));
   Print("DownloadHistory: ",hdr);
   if(fh!=INVALID_HANDLE) FileWriteString(fh,hdr+"\r\n");

   for(int t=0;t<ArraySize(tfs) && !IsStopped();t++)
     {
      MqlRates r[];
      int got=0; datetime earliest=0; int stable=0;
      for(int k=0;k<40 && !IsStopped();k++)       // ~20s per timeframe
        {
         ResetLastError();
         int n=CopyRates(sym,tfs[t],InpStart,endt,r);
         if(n>0)
           {
            if(n==got) stable++; else stable=0;
            got=n; earliest=r[0].time;
            if(stable>=4) break;                   // count settled -> done
           }
         Sleep(500);
        }
      string line=StringFormat("%-4s bars=%-7d earliest=%s",
                  names[t],got,(earliest>0?TimeToString(earliest,TIME_DATE):"-"));
      Print("DownloadHistory: ",line);
      if(fh!=INVALID_HANDLE) FileWriteString(fh,line+"\r\n");
     }

   if(fh!=INVALID_HANDLE) { FileWriteString(fh,"DONE\r\n"); FileClose(fh); }
   Print("DownloadHistory: finished");
  }
