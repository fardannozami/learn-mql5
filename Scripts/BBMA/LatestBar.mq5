#property version "1.00"
void OnStart()
  {
   string sym="XAUUSD"; SymbolSelect(sym,true);
   ENUM_TIMEFRAMES tf[]={PERIOD_W1,PERIOD_D1,PERIOD_H4,PERIOD_H1,PERIOD_M15,PERIOD_M5,PERIOD_M1};
   string nm[]={"W1","D1","H4","H1","M15","M5","M1"};
   int fh=FileOpen("bbma_latest.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   for(int i=0;i<ArraySize(tf);i++)
     {
      MqlRates r[]; datetime latest=0,first=0; int n=0;
      for(int k=0;k<20 && !IsStopped();k++)
        { n=CopyRates(sym,tf[i],0,100000,r); if(n>0){latest=r[n-1].time; first=r[0].time;} Sleep(300); if(n>0&&k>2) break; }
      string line=StringFormat("%-4s bars=%-7d first=%s last=%s",nm[i],n,
                  TimeToString(first,TIME_DATE|TIME_MINUTES),TimeToString(latest,TIME_DATE|TIME_MINUTES));
      Print(line); if(fh!=INVALID_HANDLE) FileWriteString(fh,line+"\r\n");
     }
   if(fh!=INVALID_HANDLE){ FileWriteString(fh,"DONE\r\n"); FileClose(fh); }
  }
