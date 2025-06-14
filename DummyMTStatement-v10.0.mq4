//+------------------------------------------------------------------+
//| DummyMTStatement-v9.9q5.mq4                                      |
//| Generates a fake MT4 statement from real M1 data.                |
//| EVENLY distributes trades across time and randomly mixes symbols. |
//+------------------------------------------------------------------+
#property strict

extern string AccountName      = "Hugues Dubois";
extern string BrokerName       = "Swissquote Bank SA";
extern int    AccountNumber    = 651083;
extern string Currency         = "EUR";
extern double InitialBalance   = 500000.0;
extern string Symbols          = "EURUSD,GBPUSD,USDJPY";
extern int    NumClosedTrades  = 50;
extern int    NumOpenPositions = 2;
extern double LossPercent      = 30.0;
extern string FromDate         = "2024.08.01";
extern string ToDate           = "2025.05.30";
extern int    TicketStart      = 1000000;
extern int    TicketDigits     = 8;
extern int    RandomTicketIncrement = 5;
extern int    MaxHoldDays      = 0;
extern bool   DoNotTradeIfMissingPriceData = true;

extern double FixedLotSize = 0.0;
extern double VariableLot  = 0.1;
extern string BalEntryDateTime1 = "2025.05.01 00:00:01";
extern string BalEntryText1     = "UT>CAC 857064138";
extern string BalEntryAmount1   = "15 000.00";
extern string BalEntryDateTime2 = "";
extern string BalEntryText2     = "";
extern string BalEntryAmount2   = "";
extern string BalEntryDateTime3 = "";
extern string BalEntryText3     = "";
extern string BalEntryAmount3   = "";
extern string BalEntryDateTime4 = "";
extern string BalEntryText4     = "";
extern string BalEntryAmount4   = "";
extern string BalEntryDateTime5 = "";
extern string BalEntryText5     = "";
extern string BalEntryAmount5   = "";

enum RowType { RowTrade, RowBalance };
struct FakeTrade {
   datetime open_time;
   string   ticket;
   string   symbol;
   string   type;
   double   volume;
   double   open_price;
   double   market_price;
   double   sl;
   double   tp;
   datetime close_time;
   double   close_price;
   double   commission;
   double   taxes;
   double   swap;
   double   profit;
   bool     is_open;
   double   profit_eur;
   double   swap_eur;
};
struct BalanceEntry {
   string   datetime_str;
   datetime dt;
   string   text;
   string   amount;
   double   dAmount;
   string   ticket;
};
struct ClosedRow {
   RowType type;
   datetime dt;
   string ticket;
   FakeTrade trade;
   string bal_datetime_str;
   string bal_text;
   string bal_amount;
   double bal_dAmount;
};

FakeTrade closed_trades[];
FakeTrade open_trades[];
FakeTrade working_orders[];
BalanceEntry balance_entries[];
ClosedRow closed_rows[];
double    total_commission = 0;
double    total_swap       = 0;
double    total_taxes      = 0;
double    total_profit     = 0;
double    floating_pl      = 0;
double    final_balance    = 0;
double    equity           = 0;
double    margin           = 0;
double    free_margin      = 0;
double    total_deposit_withdrawal = 0;

string EURUSDSymbol = "";
string FindRealSymbol(string s) {
   if(iBars(s, PERIOD_M1) > 1) return s;
   string suffixes[] = {"", "m", ".m", "r", ".r", "pro", ".pro"};
   for(int i=0; i<ArraySize(suffixes); i++) {
      string test = s + suffixes[i];
      if(iBars(test, PERIOD_M1) > 1) return test;
   }
   int total = SymbolsTotal(true);
   for(int j=0; j<total; j++) {
      string sym = SymbolName(j, true);
      if(StringFind(sym, s) == 0 && iBars(sym, PERIOD_M1) > 1) return sym;
   }
   return s;
}
string GetRealEURUSD() {
   if(EURUSDSymbol != "") return EURUSDSymbol;
   EURUSDSymbol = FindRealSymbol("EURUSD");
   return EURUSDSymbol;
}
string NumFmt(double x) {
   string s = DoubleToStr(MathAbs(x), 2);
   int dot = StringFind(s, ".");
   if(dot<0) dot = StringLen(s);
   string intp=StringSubstr(s,0,dot), decp=StringSubstr(s,dot);
   string r="";
   int n=StringLen(intp), cnt=0;
   for(int i=n-1;i>=0;i--) {
      if(cnt==3) { r=" "+r; cnt=0; }
      r=StringSubstr(intp,i,1)+r; cnt++;
   }
   if(x<0) r="-"+r;
   return r+decp;
}
string Trim(const string s) {
   string t = s;
   while(StringLen(t)>0 && StringGetChar(t,0)<=32) t = StringSubstr(t,1);
   while(StringLen(t)>0 && StringGetChar(t,StringLen(t)-1)<=32) t = StringSubstr(t,0,StringLen(t)-1);
   return(t);
}
string ToLower(const string s) {
   string r = "";
   for(int i=0;i<StringLen(s);i++) {
      int c = StringGetChar(s,i);
      if(c >= 'A' && c <= 'Z') c += 'a'-'A';
      r += StringFormat("%c", c);
   }
   return(r);
}
string FormatStatementDate(datetime dt) {
   string months[12] = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
   int y = TimeYear(dt), m = TimeMonth(dt), d = TimeDay(dt), h = TimeHour(dt), mi = TimeMinute(dt);
   return(StringFormat("%d %s %02d, %02d:%02d", y, months[m-1], d, h, mi));
}
string MT4Date(datetime dt) {
   return(TimeToStr(dt, TIME_DATE|TIME_SECONDS));
}
string FormatTicket(int val) {
   string s = IntegerToString(val);
   int pad = TicketDigits - StringLen(s);
   while(pad > 0) { s = "0" + s; pad--; }
   if(StringLen(s) > TicketDigits) s = StringSubstr(s, StringLen(s)-TicketDigits);
   return s;
}
int TicketCompare(string t1, string t2) {
   int i1 = StrToInteger(t1);
   int i2 = StrToInteger(t2);
   if(i1<i2) return -1;
   if(i1>i2) return 1;
   return 0;
}
double GetExactM1BarPrice(string symbol, datetime t) {
   int bars = iBars(symbol, PERIOD_M1);
   int shift = iBarShift(symbol, PERIOD_M1, t, false);
   if(shift < 0) return -1;
   if(iTime(symbol, PERIOD_M1, shift) != t) return -1;
   if(shift >= bars) {
      Print("GetExactM1BarPrice: shift out of range! symbol=", symbol, " t=", t, " shift=", shift, " bars=", bars);
      return -1;
   }
   double px = iClose(symbol, PERIOD_M1, shift);
   if(px <= 0) return -1;
   return px;
}
double GetEURUSDRate(datetime time) { return(GetExactM1BarPrice(GetRealEURUSD(), time)); }
double GetHistoricalPrice(string symbol, datetime time) { return(GetExactM1BarPrice(symbol, time)); }
double ParseAmount(string s) {
   s = Trim(s);
   if(s=="") return 0;
   string clean = "";
   for(int i=0; i<StringLen(s); i++) {
      int c = StringGetChar(s,i);
      if((c>='0' && c<='9') || c=='-' || c=='+' || c=='.')
         clean += StringSubstr(s,i,1);
   }
   return(StrToDouble(clean));
}
void CollectBalanceEntries() {
   string dt_strs[5];
   string texts[5];
   string amounts[5];
   dt_strs[0] = BalEntryDateTime1; texts[0] = BalEntryText1; amounts[0] = BalEntryAmount1;
   dt_strs[1] = BalEntryDateTime2; texts[1] = BalEntryText2; amounts[1] = BalEntryAmount2;
   dt_strs[2] = BalEntryDateTime3; texts[2] = BalEntryText3; amounts[2] = BalEntryAmount3;
   dt_strs[3] = BalEntryDateTime4; texts[3] = BalEntryText4; amounts[3] = BalEntryAmount4;
   dt_strs[4] = BalEntryDateTime5; texts[4] = BalEntryText5; amounts[4] = BalEntryAmount5;
   int cnt = 0;
   total_deposit_withdrawal = 0;
   for(int i=0;i<5;i++) {
      string s = Trim(dt_strs[i]);
      if(s == "") continue;
      BalanceEntry be;
      be.datetime_str = s;
      be.dt = StrToTime(s);
      be.text = texts[i];
      be.amount = amounts[i];
      be.dAmount = ParseAmount(amounts[i]);
      be.ticket = "";
      total_deposit_withdrawal += be.dAmount;
      cnt++;
      ArrayResize(balance_entries, cnt);
      balance_entries[cnt-1] = be;
   }
}
void BuildClosedRows() {
   int nTrade = ArraySize(closed_trades);
   int nBal = ArraySize(balance_entries);
   int idx = 0;
   ArrayResize(closed_rows, nTrade + nBal);

   for(int i=0; i<nBal; i++) {
      closed_rows[idx].type = RowBalance;
      closed_rows[idx].dt = balance_entries[i].dt;
      closed_rows[idx].bal_datetime_str = balance_entries[i].datetime_str;
      closed_rows[idx].bal_text = balance_entries[i].text;
      closed_rows[idx].bal_amount = balance_entries[i].amount;
      closed_rows[idx].bal_dAmount = balance_entries[i].dAmount;
      closed_rows[idx].ticket = "";
      idx++;
   }
   for(int i=0; i<nTrade; i++) {
      closed_rows[idx].type = RowTrade;
      closed_rows[idx].dt = closed_trades[i].open_time;
      closed_rows[idx].trade = closed_trades[i];
      closed_rows[idx].ticket = "";
      closed_rows[idx].bal_datetime_str = "";
      closed_rows[idx].bal_text = "";
      closed_rows[idx].bal_amount = "";
      closed_rows[idx].bal_dAmount = 0;
      idx++;
   }
   int N = ArraySize(closed_rows);
   for(int i=0;i<N-1;i++) {
      for(int j=i+1;j<N;j++) {
         if(
            closed_rows[j].dt < closed_rows[i].dt
            || (closed_rows[j].dt == closed_rows[i].dt && closed_rows[j].type < closed_rows[i].type)
         ) {
            ClosedRow temp = closed_rows[i];
            closed_rows[i] = closed_rows[j];
            closed_rows[j] = temp;
         }
      }
   }
   int ticket_val = TicketStart;
   closed_rows[0].ticket = FormatTicket(ticket_val);
   for(int i=1; i<N; i++) {
       int secdiff = (int)(closed_rows[i].dt - closed_rows[i-1].dt);
       if(secdiff < 0) secdiff = 1;
       int randomnumber = (RandomTicketIncrement > 0) ? (1 + MathRand() % RandomTicketIncrement) : 1;
       int increment = 1 + (secdiff / 20) + randomnumber;
       if(increment < 1) increment = 1;
       ticket_val += increment;
       closed_rows[i].ticket = FormatTicket(ticket_val);
   }
   int b = 0, t = 0;
   for(int i=0;i<N;i++) {
      if(closed_rows[i].type == RowBalance) {
         balance_entries[b++].ticket = closed_rows[i].ticket;
      } else {
         closed_trades[t++].ticket = closed_rows[i].ticket;
      }
   }
}
void GetBarTimesInRange(string symbol, datetime from_dt, datetime to_dt, datetime &bar_times[]) {
   int bars = iBars(symbol, PERIOD_M1);
   ArrayResize(bar_times, 0);
   for(int i=bars-1; i>=0; i--) { // oldest to newest!
      datetime t = iTime(symbol, PERIOD_M1, i);
      if(t < from_dt || t > to_dt) continue;
      int n = ArraySize(bar_times);
      ArrayResize(bar_times, n+1);
      bar_times[n] = t;
   }
}

// Main data generation: EVEN time distribution, RANDOM symbol for each trade

void GenerateFakeData() {
   struct SymbolBars {
      string symbol;
      datetime bars[];
   };
   string syms[10];
   int sym_count = StringSplit(Symbols,',',syms);
   for(int i=0;i<sym_count;i++) syms[i]=Trim(syms[i]);
   MathSrand((int)TimeLocal());
   ArrayResize(closed_trades, 0);
   ArrayResize(open_trades, 0);
   total_commission = 0; total_swap = 0; total_taxes = 0; total_profit = 0;
   floating_pl = 0;
   CollectBalanceEntries();

   datetime from_dt = StrToTime(FromDate);
   datetime to_dt   = StrToTime(ToDate);

   SymbolBars symbolBars[10];
   int symbolBarsCount = 0;
   for(int s=0; s<sym_count; s++) {
      string baseSym = syms[s];
      string symbol = FindRealSymbol(baseSym);
      datetime bars[600000];
      GetBarTimesInRange(symbol, from_dt, to_dt, bars);
      int bar_count = ArraySize(bars);
      if(bar_count >= 10) {
         symbolBars[symbolBarsCount].symbol = symbol;
         ArrayResize(symbolBars[symbolBarsCount].bars, bar_count);
         for(int j=0;j<bar_count;j++) symbolBars[symbolBarsCount].bars[j]=bars[j];
         symbolBarsCount++;
         Print("Storing ", bar_count, " bars for ", symbol, " from ", TimeToString(bars[0], TIME_DATE), " to ", TimeToString(bars[bar_count-1], TIME_DATE));
      } else {
         Print("Skipping ", symbol, " (not enough bars in range: found ", bar_count, ")");
      }
   }
   if(symbolBarsCount == 0) {
      Print("ERROR: No symbols have enough bar data in the selected date range!");
      return;
   }

   int trades_needed = NumClosedTrades;
   double interval = double(to_dt-from_dt)/trades_needed;

   int made = 0;
   for(int i=0; i<trades_needed; i++) {
      datetime target = from_dt + int(i*interval);

      // Gather all symbols with a bar >= target (prefer nearest, within 1 hour)
      string candidates[10];
      int cand_idxs[10];
      int ccount = 0;
      for(int s=0; s<symbolBarsCount; s++) {
         int N = ArraySize(symbolBars[s].bars);
         for(int j=0; j<N; j++) {
            datetime btime = symbolBars[s].bars[j];
            if(btime >= target) {
               if(MathAbs(btime-target) <= 3600) { // within 1 hour
                  candidates[ccount] = symbolBars[s].symbol;
                  cand_idxs[ccount] = j;
                  ccount++;
               }
               break;
            }
         }
      }
      if(ccount == 0) continue; // no symbols have a bar in this window

      int pick = MathRand() % ccount;
      string best_symbol = candidates[pick];
      int sidx = -1;
      for(int s=0;s<symbolBarsCount;s++) if(symbolBars[s].symbol==best_symbol) sidx=s;
      int open_idx = cand_idxs[pick];
      int N = ArraySize(symbolBars[sidx].bars);

      // Valid close_idx logic
      int min_close_offset = 5, max_close_offset = MathMin(120, N - open_idx - 1);
      if(max_close_offset < min_close_offset) continue;
      int close_offset = min_close_offset + MathRand() % (max_close_offset - min_close_offset + 1);
      int close_idx = open_idx + close_offset;
      if(close_idx >= N) continue;

      datetime open_time = symbolBars[sidx].bars[open_idx];
      datetime close_time = symbolBars[sidx].bars[close_idx];
      double opx = GetExactM1BarPrice(best_symbol, open_time);
      double cpx = GetExactM1BarPrice(best_symbol, close_time);
      if(opx < 0 || cpx < 0) continue;
      if(open_time >= close_time) continue;

      FakeTrade t;
      t.symbol = best_symbol;
      t.open_time = open_time;
      t.close_time = close_time;
      t.open_price = NormalizeDouble(opx, (StringFind(best_symbol,"JPY")>=0)?3:5);
      t.close_price = NormalizeDouble(cpx, (StringFind(best_symbol,"JPY")>=0)?3:5);
      t.type = (MathRand()%2==0) ? "buy" : "sell";
      double lots = 0.1 + (MathRand()%10)*0.01;
      if(FixedLotSize > 0)
         lots = FixedLotSize;
      else if(VariableLot > 0)
         lots = MathMax(0.01, NormalizeDouble((VariableLot * InitialBalance)/100000.0, 2));
      t.volume = lots;
      t.sl = 0; t.tp = 0;
      t.commission = 0.0;
      t.taxes = 0.0;
      t.swap = 0.0;
      double profit_usd = 0;
      if(StringFind(best_symbol,"JPY")>=0) {
         if(t.type == "buy")
            profit_usd = (t.close_price - t.open_price) * t.volume * 100000.0 / t.close_price;
         else
            profit_usd = (t.open_price - t.close_price) * t.volume * 100000.0 / t.close_price;
      } else {
         if(t.type == "buy")
            profit_usd = (t.close_price - t.open_price) * t.volume * 100000.0;
         else
            profit_usd = (t.open_price - t.close_price) * t.volume * 100000.0;
      }
      t.profit = profit_usd;
      t.market_price = 0;
      t.is_open = false;
      t.profit_eur = t.profit;
      t.swap_eur = t.swap;
      int idx = ArraySize(closed_trades);
      ArrayResize(closed_trades, idx+1);
      closed_trades[idx]=t;
      made++;
   }

   // --- OPEN TRADES PATCHED SECTION ---
   int total_open = 0;
   int max_open_attempts = NumOpenPositions * 50;
   int open_attempts = 0;
   int max_hold = (MaxHoldDays > 0) ? MaxHoldDays : 1;
   while(total_open < NumOpenPositions && open_attempts < max_open_attempts) {
      open_attempts++;
      int sidx = MathRand() % symbolBarsCount;
      int N = ArraySize(symbolBars[sidx].bars);
      if(N < 10) continue;

      // Find eligible open indexes: only open trades in the last MaxHoldDays (or 1 day if 0)
      datetime last_bar_time = symbolBars[sidx].bars[N-1];
      datetime earliest_open_time = last_bar_time - 86400 * max_hold;
      int eligible_start = 0;
      while(eligible_start < N-1 && symbolBars[sidx].bars[eligible_start] < earliest_open_time)
         eligible_start++;
      if(eligible_start >= N-1) continue; // no eligible bars

      int open_idx = eligible_start + MathRand() % (N - eligible_start - 1);
      datetime open_time = symbolBars[sidx].bars[open_idx];
      double opx = GetExactM1BarPrice(symbolBars[sidx].symbol, open_time);
      double market_px = GetExactM1BarPrice(symbolBars[sidx].symbol, symbolBars[sidx].bars[N-1]);
      if(opx<0 || market_px<0) continue;
      FakeTrade t;
      t.symbol = symbolBars[sidx].symbol;
      t.open_time = open_time;
      t.open_price = NormalizeDouble(opx, (StringFind(t.symbol,"JPY")>=0)?3:5);
      t.market_price = NormalizeDouble(market_px, (StringFind(t.symbol,"JPY")>=0)?3:5);
      t.ticket = "";
      t.type = (MathRand()%2==0) ? "buy" : "sell";
      double lots = 0.1 + (MathRand()%10)*0.01;
      if(FixedLotSize > 0)
         lots = FixedLotSize;
      else if(VariableLot > 0)
         lots = MathMax(0.01, NormalizeDouble((VariableLot * InitialBalance)/100000.0, 2));
      t.volume = lots;
      t.close_time = 0; t.close_price = 0;
      t.sl = 0; t.tp = 0;
      t.commission = 0.0;
      t.taxes = 0.0;
      t.swap = 0.0;
      double profit_usd = 0;
      if(StringFind(t.symbol,"JPY")>=0) {
         if(t.type=="buy")
            profit_usd = (t.market_price-t.open_price) * t.volume * 100000.0 / t.market_price;
         else
            profit_usd = (t.open_price-t.market_price) * t.volume * 100000.0 / t.market_price;
      } else {
         if(t.type=="buy")
            profit_usd = (t.market_price-t.open_price) * t.volume * 100000.0;
         else
            profit_usd = (t.open_price-t.market_price) * t.volume * 100000.0;
      }
      t.profit = profit_usd;
      t.is_open = true;
      int idx = ArraySize(open_trades);
      ArrayResize(open_trades, idx+1);
      open_trades[idx]=t;
      floating_pl += t.profit;
      total_open++;
   }

   BuildClosedRows();

   // --- SORT open_trades by open_time ASC and assign tickets in sequence ---
   // Sort open_trades by open_time ascending
   for(int i=0;i<ArraySize(open_trades)-1;i++) {
      for(int j=i+1;j<ArraySize(open_trades);j++) {
         if(open_trades[j].open_time < open_trades[i].open_time) {
            FakeTrade tmp = open_trades[i];
            open_trades[i] = open_trades[j];
            open_trades[j] = tmp;
         }
      }
   }
   // Now assign tickets in order of open_time after closed_trades/tickets
   int last_ticket_val = (ArraySize(closed_rows) > 0) ? StrToInteger(closed_rows[ArraySize(closed_rows)-1].ticket) : TicketStart;
   datetime last_dt = (ArraySize(closed_rows) > 0) ? closed_rows[ArraySize(closed_rows)-1].dt : from_dt;
   for(int i=0;i<ArraySize(open_trades);i++) {
      int secdiff = (int)(open_trades[i].open_time - last_dt);
      if(secdiff < 0) secdiff = 1;
      int randomnumber = (RandomTicketIncrement > 0) ? (1 + MathRand() % RandomTicketIncrement) : 1;
      int increment = 1 + (secdiff / 20) + randomnumber;
      if(increment < 1) increment = 1;
      last_ticket_val += increment;
      open_trades[i].ticket = FormatTicket(last_ticket_val);
      last_dt = open_trades[i].open_time;
   }

   total_profit = 0.0;
   total_swap = 0.0;
   if(ToLower(Currency) == "eur") {
      for(int i=0; i<ArraySize(closed_rows); i++) {
         if(closed_rows[i].type == RowTrade) {
            FakeTrade t = closed_rows[i].trade;
            double eurusd = GetEURUSDRate(t.close_time);
            if(eurusd <= 0.0001) eurusd = 1.10;
            closed_rows[i].trade.profit_eur = t.profit / eurusd;
            closed_rows[i].trade.swap_eur = t.swap / eurusd;
            total_profit += closed_rows[i].trade.profit_eur;
            total_swap += closed_rows[i].trade.swap_eur;
         }
      }
   } else {
      for(int i=0; i<ArraySize(closed_rows); i++) {
         if(closed_rows[i].type == RowTrade) {
            FakeTrade t = closed_rows[i].trade;
            closed_rows[i].trade.profit_eur = t.profit;
            closed_rows[i].trade.swap_eur = t.swap;
            total_profit += t.profit;
            total_swap += t.swap;
         }
      }
   }
   final_balance = InitialBalance + total_deposit_withdrawal + total_profit;
   equity = final_balance + floating_pl;
   margin = MathMax(0.0, (ArraySize(open_trades)>0) ? MathAbs(final_balance*0.03) : 0.0);
   free_margin = equity - margin;
   ArrayResize(working_orders,0);

   if(made==0) Print("WARNING: No trades could be generated!");
}

// --- [rest of your code including ExportMt4Statement()/OnInit() unchanged] ---


void ExportMt4Statement() {
   string fname = StringFormat("Statement-%d.htm",AccountNumber);
   int f = FileOpen(fname, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE) { Print("Cannot create file: ",fname); return; }

   FileWriteString(f,"<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">\r\n");
   FileWriteString(f,"<html>\r\n<head>\r\n<title>Statement: "+AccountNumber+" - "+AccountName+"</title>\r\n");
   FileWriteString(f,"<style type=\"text/css\" media=\"screen\">\r\ntd { font: 8pt Tahoma,Arial; }\r\n</style>\r\n");
   FileWriteString(f,"<style type=\"text/css\" media=\"print\">\r\ntd { font: 7pt Tahoma,Arial; }\r\n</style>\r\n");
   FileWriteString(f,"<style type=\"text/css\">\r\n.msdate { mso-number-format:\"General Date\"; }\r\n.mspt   { mso-number-format:\\#\\,\\#\\#0\\.00;  }\r\n</style>\r\n");
   FileWriteString(f,"</head>\r\n<body topmargin=1 marginheight=1>\r\n<div align=center>\r\n");
   FileWriteString(f,"<div style=\"font: 20pt Times New Roman\"><b>"+BrokerName+"</b></div><br>\r\n");
   FileWriteString(f,"<table cellspacing=1 cellpadding=3 border=0>\r\n");

   FileWriteString(f,"<tr align=left>");
   FileWriteString(f,"<td colspan=2><b>Account: "+AccountNumber+"</b></td>");
   FileWriteString(f,"<td colspan=5><b>Name: "+AccountName+"</b></td>");
   FileWriteString(f,"<td colspan=2><b>Currency: "+Currency+"</b></td>");
   FileWriteString(f,"<td colspan=2><b>Leverage: <!--LEVERAGE--></b></td>");
   FileWriteString(f,"<td colspan=3 align=right><b>"+FormatStatementDate(TimeCurrent())+"</b></td>");
   FileWriteString(f,"</tr>\r\n");

   FileWriteString(f,"<tr align=left><td colspan=14><b>Closed Transactions:</b></td></tr>\r\n");
   FileWriteString(f,"<tr align=center bgcolor=\"#C0C0C0\">");
   FileWriteString(f,"<td>Ticket</td><td nowrap>Open Time</td><td>Type</td><td>Size</td><td>Item</td>");
   FileWriteString(f,"<td>Price</td><td>S / L</td><td>T / P</td><td nowrap>Close Time</td>");
   FileWriteString(f,"<td>Price</td><td>Commission</td><td>Taxes</td><td>Swap</td><td>Profit</td></tr>\r\n");

   for(int i=0;i<ArraySize(closed_rows);i++) {
      string bg = (i%2==0)?"":" bgcolor=#E0E0E0";
      if(closed_rows[i].type == RowTrade) {
         FakeTrade t = closed_rows[i].trade;
         FileWriteString(f,"<tr align=right"+bg+">");
         FileWriteString(f,"<td>"+closed_rows[i].ticket+"</td>");
         FileWriteString(f,"<td class=msdate nowrap>"+MT4Date(t.open_time)+"</td>");
         FileWriteString(f,"<td>"+t.type+"</td>");
         FileWriteString(f,"<td class=mspt>"+DoubleToStr(t.volume,2)+"</td>");
         FileWriteString(f,"<td>"+ToLower(t.symbol)+"</td>");
         FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">"+DoubleToStr(t.open_price,5)+"</td>");
         FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">0.00000</td>");
         FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">0.00000</td>");
         FileWriteString(f,"<td class=msdate nowrap>"+MT4Date(t.close_time)+"</td>");
         FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">"+DoubleToStr(t.close_price,5)+"</td>");
         FileWriteString(f,"<td>0.00</td>");
         FileWriteString(f,"<td>0.00</td>");
         if(ToLower(Currency) == "eur") {
            FileWriteString(f,"<td>"+NumFmt(t.swap_eur)+"</td>");
            FileWriteString(f,"<td>"+NumFmt(t.profit_eur)+"</td>");
         } else {
            FileWriteString(f,"<td>"+NumFmt(t.swap)+"</td>");
            FileWriteString(f,"<td>"+NumFmt(t.profit)+"</td>");
         }
         FileWriteString(f,"</tr>\r\n");
      } else {
         FileWriteString(f,"<tr align=right"+bg+">");
         FileWriteString(f,"<td>"+closed_rows[i].ticket+"</td>");
         FileWriteString(f,"<td class=msdate nowrap>"+closed_rows[i].bal_datetime_str+"</td>");
         FileWriteString(f,"<td>balance</td>");
         FileWriteString(f,"<td colspan=10 align=left>"+closed_rows[i].bal_text+"</td>");
         FileWriteString(f,"<td class=mspt>"+closed_rows[i].bal_amount+"</td>");
         FileWriteString(f,"</tr>\r\n");
      }
   }

   double sum_swap=0, sum_profit=0;
   for(int i=0;i<ArraySize(closed_rows);i++) {
      if(closed_rows[i].type == RowTrade) {
         FakeTrade t = closed_rows[i].trade;
         if(ToLower(Currency) == "eur") {
            sum_swap += t.swap_eur;
            sum_profit += t.profit_eur;
         } else {
            sum_swap += t.swap;
            sum_profit += t.profit;
         }
      }
   }
   FileWriteString(f,"<tr align=right><td colspan=10>&nbsp;</td>");
   FileWriteString(f,"<td class=mspt>0.00</td>");
   FileWriteString(f,"<td class=mspt>0.00</td>");
   FileWriteString(f,"<td class=mspt>"+NumFmt(sum_swap)+"</td>");
   FileWriteString(f,"<td class=mspt>"+NumFmt(sum_profit)+"</td>");
   FileWriteString(f,"</tr>\r\n");

   FileWriteString(f,"<tr align=right><td colspan=12 align=right><b>Closed P/L:</b></td>");
   FileWriteString(f,"<td colspan=2 align=right class=mspt><b>"+NumFmt(sum_profit)+"</b></td></tr>\r\n");

   FileWriteString(f,"<tr align=left><td colspan=14><b>Open Trades:</b></td></tr>\r\n");
   FileWriteString(f,"<tr align=center bgcolor=\"#C0C0C0\">");
   FileWriteString(f,"<td>Ticket</td><td nowrap>Open Time</td><td>Type</td><td>Size</td><td>Item</td>");
   FileWriteString(f,"<td>Price</td><td>S / L</td><td>T / P</td><td></td><td>Price</td>");
   FileWriteString(f,"<td>Commission</td><td>Taxes</td><td>Swap</td><td>Profit</td></tr>\r\n");

   for(int i=0;i<ArraySize(open_trades);i++) {
      string bg = (i%2==0)?"":" bgcolor=#E0E0E0";
      FileWriteString(f,"<tr align=right"+bg+">");
      FileWriteString(f,"<td>"+open_trades[i].ticket+"</td>");
      FileWriteString(f,"<td class=msdate nowrap>"+MT4Date(open_trades[i].open_time)+"</td>");
      FileWriteString(f,"<td>"+open_trades[i].type+"</td>");
      FileWriteString(f,"<td class=mspt>"+DoubleToStr(open_trades[i].volume,2)+"</td>");
      FileWriteString(f,"<td>"+ToLower(open_trades[i].symbol)+"</td>");
      FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">"+DoubleToStr(open_trades[i].open_price,5)+"</td>");
      FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">0.00000</td>");
      FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">0.00000</td>");
      FileWriteString(f,"<td></td>");
      FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">"+DoubleToStr(open_trades[i].market_price,5)+"</td>");
      FileWriteString(f,"<td>0.00</td>");
      FileWriteString(f,"<td>0.00</td>");
      FileWriteString(f,"<td>"+DoubleToStr(open_trades[i].swap,2)+"</td>");
      FileWriteString(f,"<td>"+NumFmt(open_trades[i].profit)+"</td>");
      FileWriteString(f,"</tr>\r\n");
   }

   double open_swap_total = 0, open_profit_total = 0;
   for (int i = 0; i < ArraySize(open_trades); i++) {
      open_swap_total += open_trades[i].swap;
      open_profit_total += open_trades[i].profit;
   }
   FileWriteString(f,"<tr align=right><td colspan=10>&nbsp;</td>");
   FileWriteString(f,"<td class=mspt>0.00</td><td class=mspt>0.00</td>");
   FileWriteString(f,"<td class=mspt>"+NumFmt(open_swap_total)+"</td>");
   FileWriteString(f,"<td class=mspt>"+NumFmt(open_profit_total)+"</td>");
   FileWriteString(f,"</tr>\r\n");

   FileWriteString(f,"<tr><td colspan=10>&nbsp;</td><td colspan=2 align=right><b>Floating P/L:</b></td>");
   FileWriteString(f,"<td colspan=2 align=right class=mspt><b>"+NumFmt(floating_pl)+"</b></td></tr>\r\n");

   FileWriteString(f,"<tr align=left><td colspan=14><b>Working Orders:</b></td></tr>\r\n");
   FileWriteString(f,"<tr align=center bgcolor=\"#C0C0C0\">");
   FileWriteString(f,"<td>Ticket</td><td nowrap>Open Time</td><td>Type</td><td>Size</td><td>Item</td>");
   FileWriteString(f,"<td>Price</td><td>S / L</td><td>T / P</td><td colspan=2 nowrap>Market Price</td><td colspan=4>&nbsp;</td></tr>\r\n");
   if(ArraySize(working_orders)==0) {
      FileWriteString(f,"<tr align=right><td colspan=13 align=center>No transactions</td></tr>\r\n");
   }
   FileWriteString(f,"<tr><td colspan=14 style=\"font: 1pt arial\">&nbsp;</td></tr>\r\n");

   FileWriteString(f,"<tr align=left><td colspan=14><b>Summary:</b></td></tr>\r\n");
   FileWriteString(f,"<tr align=right>");
   FileWriteString(f,"<td colspan=2><b>Deposit/Withdrawal:</b></td>");
   FileWriteString(f,"<td colspan=2 class=mspt><b>"+NumFmt(total_deposit_withdrawal)+"</b></td>");
   FileWriteString(f,"<td colspan=4><b>Credit Facility:</b></td>");
   FileWriteString(f,"<td class=mspt><b>0.00</b></td>");
   FileWriteString(f,"<td colspan=5>&nbsp;</td></tr>\r\n");

   FileWriteString(f,"<tr align=right>");
   FileWriteString(f,"<td colspan=2><b>Closed Trade P/L:</b></td>");
   FileWriteString(f,"<td colspan=2 class=mspt><b>"+NumFmt(sum_profit)+"</b></td>");
   FileWriteString(f,"<td colspan=4><b>Floating P/L:</b></td>");
   FileWriteString(f,"<td class=mspt><b>"+NumFmt(floating_pl)+"</b></td>");
   FileWriteString(f,"<td colspan=3><b>Margin:</b></td>");
   FileWriteString(f,"<td colspan=2 class=mspt><b>"+NumFmt(margin)+"</b></td></tr>\r\n");

   FileWriteString(f,"<tr align=right>");
   FileWriteString(f,"<td colspan=2><b>Balance:</b></td>");
   FileWriteString(f,"<td colspan=2 class=mspt><b>"+NumFmt(final_balance)+"</b></td>");
   FileWriteString(f,"<td colspan=4><b>Equity:</b></td>");
   FileWriteString(f,"<td class=mspt><b>"+NumFmt(equity)+"</b></td>");
   FileWriteString(f,"<td colspan=3><b>Free Margin:</b></td>");
   FileWriteString(f,"<td colspan=2 class=mspt><b>"+NumFmt(free_margin)+"</b></td></tr>\r\n");

   FileWriteString(f,"</table>\r\n</div></body></html>\r\n");
   FileClose(f);
   Print("MT4-style statement written to: ",fname);
}

int OnInit() {
   GenerateFakeData();
   ExportMt4Statement();
   return(INIT_SUCCEEDED);
}