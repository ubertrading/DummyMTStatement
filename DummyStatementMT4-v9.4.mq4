//+------------------------------------------------------------------+
//|   DummyMTStatement-v9.4.mq4                                      |
//|   MT4 statement generator EA with correct balance/trade order    |
//|   - Balance entries and closed trades merged, sorted by date     |
//|   - Deposit/Withdrawal summary at bottom reflects balances       |
//|   - If Currency == "EUR", PNL and swap are converted from USD    |
//|     using historical EURUSD close rate at trade close time       |
//+------------------------------------------------------------------+
#property strict

extern string AccountName      = "Hugues Dubois";
extern string BrokerName       = "Swissquote Bank SA";
extern int    AccountNumber    = 651083;
extern string Currency         = "EUR"; // USD or EUR (will convert if EUR with rate at time of trade)
extern double InitialBalance   = 10000.0;
extern string Symbols          = "EURUSD,GBPUSD,USDJPY";
extern int    NumClosedTrades  = 10;
extern int    NumOpenPositions = 0;
extern double LossPercent      = 30.0; // % of closed trades that are losses (0–100)
extern string FromDate         = "2025.05.01";
extern string ToDate           = "2025.05.30";
extern int    TicketStart      = 1000000;
extern int    TicketDigits     = 8;
extern int    MaxHoldDays      = 0; // Maximum hold time for positions (in days). 0 = close same day, no swap.

// User-defined balance entries (up to 5)
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

// --- Structures ---
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
   // For trades:
   FakeTrade trade;
   double trade_pnl_eur;
   double trade_swap_eur;
   // For balance:
   string bal_datetime_str;
   string bal_text;
   string bal_amount;
   double bal_dAmount;
};

// --- Globals ---
FakeTrade closed_trades[];
FakeTrade open_trades[];
FakeTrade working_orders[];
BalanceEntry balance_entries[];
ClosedRow closed_rows[];
double    total_commission = 0;
double    total_swap       = 0;
double    total_taxes      = 0;
double    total_profit     = 0; // sum in account currency
double    floating_pl      = 0;
double    final_balance    = 0;
double    equity           = 0;
double    margin           = 0;
double    free_margin      = 0;
double    total_deposit_withdrawal = 0;

// --- Helper Functions ---
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

// --- Triple Wednesday swap logic for open positions ---
int CalculateSwapDays(datetime open_time, datetime now) {
   int days_open = MathMax(1, MathCeil((now - open_time) / 86400.0));
   int swap_days = 0;
   datetime temp_time = open_time;
   for (int d = 0; d < days_open; d++) {
      if (TimeDayOfWeek(temp_time) == 3) // Wednesday
         swap_days += 3;
      else
         swap_days += 1;
      temp_time += 86400;
   }
   return(swap_days);
}

// --- Parse balance entry amount string to double ---
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

// --- EURUSD conversion at trade close time ---
double GetEURUSDRate(datetime time) {
   int shift = iBarShift("EURUSD", PERIOD_M1, time, true);
   if(shift >= 0)
      return(iClose("EURUSD", PERIOD_M1, shift));
   // fallback: try H1
   shift = iBarShift("EURUSD", PERIOD_H1, time, true);
   if(shift >= 0)
      return(iClose("EURUSD", PERIOD_H1, shift));
   // fallback: try D1
   shift = iBarShift("EURUSD", PERIOD_D1, time, true);
   if(shift >= 0)
      return(iClose("EURUSD", PERIOD_D1, shift));
   // fallback: static
   return(1.10); // fallback if no data
}

// --- Balance Entry Helper ---
void CollectBalanceEntries(int &next_ticket) {
   string dt_strs[5];
   string texts[5];
   string amounts[5];

   dt_strs[0] = BalEntryDateTime1;
   dt_strs[1] = BalEntryDateTime2;
   dt_strs[2] = BalEntryDateTime3;
   dt_strs[3] = BalEntryDateTime4;
   dt_strs[4] = BalEntryDateTime5;

   texts[0] = BalEntryText1;
   texts[1] = BalEntryText2;
   texts[2] = BalEntryText3;
   texts[3] = BalEntryText4;
   texts[4] = BalEntryText5;

   amounts[0] = BalEntryAmount1;
   amounts[1] = BalEntryAmount2;
   amounts[2] = BalEntryAmount3;
   amounts[3] = BalEntryAmount4;
   amounts[4] = BalEntryAmount5;

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
      be.ticket = FormatTicket(next_ticket++);
      total_deposit_withdrawal += be.dAmount;
      cnt++;
      ArrayResize(balance_entries, cnt);
      balance_entries[cnt-1] = be;
   }
}

// --- Merge & Sort Closed Trades and Balance Entries ---
void BuildClosedRows() {
   int nTrade = ArraySize(closed_trades);
   int nBal = ArraySize(balance_entries);
   int idx = 0;
   ArrayResize(closed_rows, nTrade + nBal);
   for(int i=0; i<nTrade; i++) {
      closed_rows[idx].type = RowTrade;
      closed_rows[idx].dt = closed_trades[i].open_time;
      closed_rows[idx].ticket = closed_trades[i].ticket;
      closed_rows[idx].trade = closed_trades[i];
      closed_rows[idx].trade_pnl_eur = 0.0; // will be set later
      closed_rows[idx].trade_swap_eur = 0.0;
      closed_rows[idx].bal_datetime_str = "";
      closed_rows[idx].bal_text = "";
      closed_rows[idx].bal_amount = "";
      closed_rows[idx].bal_dAmount = 0;
      idx++;
   }
   for(int i=0; i<nBal; i++) {
      closed_rows[idx].type = RowBalance;
      closed_rows[idx].dt = balance_entries[i].dt;
      closed_rows[idx].ticket = balance_entries[i].ticket;
      closed_rows[idx].bal_datetime_str = balance_entries[i].datetime_str;
      closed_rows[idx].bal_text = balance_entries[i].text;
      closed_rows[idx].bal_amount = balance_entries[i].amount;
      closed_rows[idx].bal_dAmount = balance_entries[i].dAmount;
      closed_rows[idx].trade_pnl_eur = 0.0;
      closed_rows[idx].trade_swap_eur = 0.0;
      idx++;
   }
   // Sort by dt, then ticket (ascending)
   for(int i=0; i<ArraySize(closed_rows)-1; i++) {
      for(int j=i+1;j<ArraySize(closed_rows);j++) {
         if(closed_rows[j].dt < closed_rows[i].dt ||
           (closed_rows[j].dt == closed_rows[i].dt && TicketCompare(closed_rows[j].ticket,closed_rows[i].ticket)<0)) {
            ClosedRow temp = closed_rows[i];
            closed_rows[i] = closed_rows[j];
            closed_rows[j] = temp;
         }
      }
   }
}

// --- Fake Data Generation ---
void GenerateFakeData() {
   string syms[10];
   int sym_count = StringSplit(Symbols,',',syms);
   for(int i=0;i<sym_count;i++) syms[i]=ToLower(Trim(syms[i]));
   MathSrand((int)TimeLocal());

   datetime from = StrToTime(FromDate + " 00:00:01");
   datetime to   = StrToTime(ToDate   + " 23:59:59");
   int total_seconds = (int)(to-from);

   ArrayResize(closed_trades, NumClosedTrades);
   ArrayResize(open_trades, NumOpenPositions);
   total_commission = 0; total_swap = 0; total_taxes = 0; total_profit = 0;
   double running_balance = InitialBalance;

   // 1. Determine count of loss/profit trades
   double lossPercent = LossPercent;
   if(lossPercent < 0) lossPercent = 0;
   if(lossPercent > 100) lossPercent = 100;
   int numLosses = (int)MathFloor(NumClosedTrades * lossPercent / 100.0);
   int numProfits = NumClosedTrades - numLosses;
   if(numLosses > NumClosedTrades) numLosses = NumClosedTrades;
   if(numProfits < 0) numProfits = 0;

   // 2. Determine total P/L
   double target_total = InitialBalance * 0.1; // 10% of InitialBalance
   if(lossPercent > 50.0) target_total = -MathAbs(target_total);
   if(lossPercent == 50.0) target_total = 0.0;

   // 3. Generate raw profit/loss values, then scale to match total
   double profitsum = 0, losssum = 0;
   double profit_trades[]; ArrayResize(profit_trades, numProfits);
   double loss_trades[];   ArrayResize(loss_trades, numLosses);
   for(int i=0;i<numProfits;i++) {
      profit_trades[i] = NormalizeDouble(10 + MathRand()%90 + MathRand()%100*0.01, 2);
      profitsum += profit_trades[i];
   }
   for(int i=0;i<numLosses;i++) {
      loss_trades[i] = -NormalizeDouble(10 + MathRand()%90 + MathRand()%100*0.01, 2);
      losssum += loss_trades[i];
   }
   double scale = 1.0;
   if(numProfits > 0 && numLosses > 0)
      scale = (target_total - losssum) / profitsum;
   else if(numProfits > 0)
      scale = target_total / profitsum;
   else if(numLosses > 0)
      scale = target_total / losssum;
   for(int i=0;i<numProfits;i++) profit_trades[i] = NormalizeDouble(profit_trades[i]*scale,2);
   for(int i=0;i<numLosses;i++)  loss_trades[i] = NormalizeDouble(loss_trades[i],2);

   int tradeTypeArr[]; ArrayResize(tradeTypeArr, NumClosedTrades);
   for(int i=0;i<NumClosedTrades;i++) tradeTypeArr[i] = (i<numProfits) ? 1 : 0;
   for(int i=NumClosedTrades-1;i>0;i--) {
      int j = MathRand()%(i+1);
      int tmp = tradeTypeArr[i]; tradeTypeArr[i]=tradeTypeArr[j]; tradeTypeArr[j]=tmp;
   }

   // --- Balance Entries: Collect and sort (by date) ---
   int ticket_val = TicketStart;
   CollectBalanceEntries(ticket_val);

   // --- Closed Trades ---
   datetime last_open_time = from;
   int profIdx=0, lossIdx=0;
   for(int i=0;i<NumClosedTrades;i++) {
      FakeTrade t;
      if(i==0)
         t.open_time = from + MathRand()%(total_seconds-3600);
      else
         t.open_time = last_open_time + MathRand()%3600+1;
      last_open_time = t.open_time;

      t.ticket = FormatTicket(ticket_val++);

      t.symbol = ToLower(syms[MathRand()%sym_count]);
      t.type = (MathRand()%2==0) ? "buy" : "sell";
      t.volume = NormalizeDouble(0.1 + (MathRand()%10)*0.01,2);

      // --- MaxHoldDays logic for close_time and swap ---
      if(MaxHoldDays == 0) {
         t.close_time = t.open_time + MathRand()%3600+60; // close within same day (within an hour)
         t.swap = 0.0;
      } else {
         t.close_time= t.open_time + MathRand()%3600+60 + (MaxHoldDays-1)*86400;
      }

      int sym_digits = (t.symbol=="usdjpy")?3:5;
      double op = 1.05 + (MathRand()%1000-500)*0.00001;
      if(StringFind(t.symbol,"jpy")>=0) op = 149.0 + (MathRand()%1000-500)*0.001;
      t.open_price = NormalizeDouble(op,sym_digits);

      t.sl = 0; t.tp = 0;
      t.commission = 0.0;
      t.taxes = 0.0;

      // --- Assign swap ---
      if(MaxHoldDays == 0) {
         t.swap = 0.0;
      } else {
         t.swap = (MathRand()%2==0) ? 0.0 : NormalizeDouble((MathRand()%21-10)*0.01,2);
         int hold_days = (int)MathFloor((t.close_time - t.open_time)/86400.0);
         if(hold_days < 1) t.swap = 0.0;
      }

      if(tradeTypeArr[i]==1 && profIdx<numProfits)
         t.profit = profit_trades[profIdx++];
      else if(tradeTypeArr[i]==0 && lossIdx<numLosses)
         t.profit = loss_trades[lossIdx++];
      else if(profIdx < numProfits)
         t.profit = profit_trades[profIdx++];
      else if(lossIdx < numLosses)
         t.profit = loss_trades[lossIdx++];
      else
         t.profit = 0.0;

      // CORRECT CLOSE PRICE CALCULATION
      if(StringFind(t.symbol,"jpy")>=0) {
         if(t.type=="buy")
            t.close_price = NormalizeDouble(t.open_price + t.profit * t.open_price / (t.volume * 100000), sym_digits);
         else
            t.close_price = NormalizeDouble(t.open_price - t.profit * t.open_price / (t.volume * 100000), sym_digits);
      } else {
         if(t.type=="buy")
            t.close_price = NormalizeDouble(t.open_price + t.profit / (t.volume * 100000), sym_digits);
         else
            t.close_price = NormalizeDouble(t.open_price - t.profit / (t.volume * 100000), sym_digits);
      }

      t.market_price = 0;
      t.is_open = false;
      total_commission += t.commission;
      total_swap += t.swap;
      total_taxes += t.taxes;
      closed_trades[i]=t;
   }

   // --- Open Trades ---
   floating_pl=0;
   if(NumOpenPositions>0) {
      datetime open_start = to - 86400;
      int prev_ticket_val = ticket_val;
      datetime prev_open_time = open_start;
      for(int i=0;i<NumOpenPositions;i++) {
         FakeTrade t;
         if(MaxHoldDays == 0) {
            t.open_time = TimeCurrent() - MathRand()%3600; // opened within the last hour (today)
         } else {
            t.open_time = prev_open_time + MathRand()%3600+1;
         }
         prev_open_time = t.open_time;
         int sec_incr = (i==0) ? 0 : (int)(t.open_time - open_trades[i-1].open_time);
         int random_incr = 1 + MathRand()%100;
         int ticket_val2 = (i==0) ? prev_ticket_val : StrToInteger(open_trades[i-1].ticket) + sec_incr + random_incr;
         t.ticket = FormatTicket(ticket_val2);
         prev_ticket_val = StrToInteger(t.ticket) + 1;
         t.symbol = ToLower(syms[MathRand()%sym_count]);
         t.type = (MathRand()%2==0) ? "buy" : "sell";
         t.volume = NormalizeDouble(0.1 + (MathRand()%10)*0.01,2);
         int sym_digits = (t.symbol=="usdjpy")?3:5;
         double op = 1.05 + (MathRand()%1000-500)*0.00001;
         if(StringFind(t.symbol,"jpy")>=0) op = 149.0 + (MathRand()%1000-500)*0.001;
         t.open_price = NormalizeDouble(op,sym_digits);

         double pip_move = (MathRand()%30 - 15) * (sym_digits==3 ? 0.01 : 0.0001);
         t.market_price = NormalizeDouble(t.open_price + ((t.type=="buy") ? pip_move : -pip_move), sym_digits);

         t.close_time = 0;
         t.close_price = 0;
         t.sl = 0; t.tp = 0;
         t.commission = 0.0;
         t.taxes = 0.0;

         // --- Assign swap ---
         if(MaxHoldDays == 0) {
            t.swap = 0.0;
         } else {
            double swapLong  = MarketInfo(t.symbol, MODE_SWAPLONG);
            double swapShort = MarketInfo(t.symbol, MODE_SWAPSHORT);
            int swap_days = CalculateSwapDays(t.open_time, TimeCurrent());
            if (t.type == "buy")
               t.swap = NormalizeDouble(swapLong * t.volume * swap_days, 2);
            else
               t.swap = NormalizeDouble(swapShort * t.volume * swap_days, 2);
            int hold_days = (int)MathFloor((TimeCurrent()-t.open_time)/86400.0);
            if(hold_days < 1) t.swap = 0.0;
         }

         // Profit calculation for open trades
         if(StringFind(t.symbol,"jpy")>=0) {
            if(t.type=="buy")
               t.profit = NormalizeDouble((t.market_price-t.open_price) * t.volume * 100000 / t.market_price, 2);
            else
               t.profit = NormalizeDouble((t.open_price-t.market_price) * t.volume * 100000 / t.market_price, 2);
         } else {
            if(t.type=="buy")
               t.profit = NormalizeDouble((t.market_price-t.open_price) * t.volume * 100000, 2);
            else
               t.profit = NormalizeDouble((t.open_price-t.market_price) * t.volume * 100000, 2);
         }

         t.is_open = true;
         open_trades[i]=t;
         floating_pl += t.profit;
      }
   }

   // --- Apply currency conversion for trades if needed ---
   BuildClosedRows();
   total_profit = 0.0;
   total_swap = 0.0;
   if(ToLower(Currency) == "eur") {
      for(int i=0; i<ArraySize(closed_rows); i++) {
         if(closed_rows[i].type == RowTrade) {
            FakeTrade t = closed_rows[i].trade;
            double eurusd = GetEURUSDRate(t.close_time);
            if(eurusd <= 0.0001) eurusd = 1.10;
            closed_rows[i].trade_pnl_eur = t.profit / eurusd;
            closed_rows[i].trade_swap_eur = t.swap / eurusd;
            total_profit += closed_rows[i].trade_pnl_eur;
            total_swap += closed_rows[i].trade_swap_eur;
         }
      }
   } else {
      for(int i=0; i<ArraySize(closed_rows); i++) {
         if(closed_rows[i].type == RowTrade) {
            FakeTrade t = closed_rows[i].trade;
            closed_rows[i].trade_pnl_eur = t.profit;
            closed_rows[i].trade_swap_eur = t.swap;
            total_profit += t.profit;
            total_swap += t.swap;
         }
      }
   }

   final_balance = InitialBalance + total_deposit_withdrawal + total_profit;
   equity = final_balance + floating_pl;
   margin = MathMax(0.0, (NumOpenPositions>0) ? MathAbs(final_balance*0.03) : 0.0);
   free_margin = equity - margin;

   ArrayResize(working_orders,0);
}

// --- Export Function ---
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

   // --- Info Row: Account/Name/Currency/Leverage/Date ---
   FileWriteString(f,"<tr align=left>");
   FileWriteString(f,"<td colspan=2><b>Account: "+AccountNumber+"</b></td>");
   FileWriteString(f,"<td colspan=5><b>Name: "+AccountName+"</b></td>");
   FileWriteString(f,"<td colspan=2><b>Currency: "+Currency+"</b></td>");
   FileWriteString(f,"<td colspan=2><b>Leverage: <!--LEVERAGE--></b></td>");
   FileWriteString(f,"<td colspan=3 align=right><b>"+FormatStatementDate(TimeCurrent())+"</b></td>");
   FileWriteString(f,"</tr>\r\n");

   // ---- Closed Trades ----
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
         FileWriteString(f,"<td>"+t.ticket+"</td>");
         FileWriteString(f,"<td class=msdate nowrap>"+MT4Date(t.open_time)+"</td>");
         FileWriteString(f,"<td>"+t.type+"</td>");
         FileWriteString(f,"<td class=mspt>"+DoubleToStr(t.volume,2)+"</td>");
         FileWriteString(f,"<td>"+t.symbol+"</td>");
         FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">"+DoubleToStr(t.open_price,5)+"</td>");
         FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">0.00000</td>");
         FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">0.00000</td>");
         FileWriteString(f,"<td class=msdate nowrap>"+MT4Date(t.close_time)+"</td>");
         FileWriteString(f,"<td style=\"mso-number-format:0\\.00000;\">"+DoubleToStr(t.close_price,5)+"</td>");
         FileWriteString(f,"<td>0.00</td>");
         FileWriteString(f,"<td>0.00</td>");
         if(ToLower(Currency) == "eur") {
            FileWriteString(f,"<td>"+NumFmt(closed_rows[i].trade_swap_eur)+"</td>");
            FileWriteString(f,"<td>"+NumFmt(closed_rows[i].trade_pnl_eur)+"</td>");
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

   // Totals in summary row
   double sum_swap=0, sum_profit=0;
   for(int i=0;i<ArraySize(closed_rows);i++) {
      if(closed_rows[i].type == RowTrade) {
         if(ToLower(Currency) == "eur") {
            sum_swap += closed_rows[i].trade_swap_eur;
            sum_profit += closed_rows[i].trade_pnl_eur;
         } else {
            sum_swap += closed_rows[i].trade.swap;
            sum_profit += closed_rows[i].trade.profit;
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

   // ---- Open Trades ----
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
      FileWriteString(f,"<td>"+open_trades[i].symbol+"</td>");
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

   // ---- Working Orders ----
   FileWriteString(f,"<tr align=left><td colspan=14><b>Working Orders:</b></td></tr>\r\n");
   FileWriteString(f,"<tr align=center bgcolor=\"#C0C0C0\">");
   FileWriteString(f,"<td>Ticket</td><td nowrap>Open Time</td><td>Type</td><td>Size</td><td>Item</td>");
   FileWriteString(f,"<td>Price</td><td>S / L</td><td>T / P</td><td colspan=2 nowrap>Market Price</td><td colspan=4>&nbsp;</td></tr>\r\n");
   if(ArraySize(working_orders)==0) {
      FileWriteString(f,"<tr align=right><td colspan=13 align=center>No transactions</td></tr>\r\n");
   }
   FileWriteString(f,"<tr><td colspan=14 style=\"font: 1pt arial\">&nbsp;</td></tr>\r\n");

   // ---- Summary ----
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

// --- EA Entry Point ---
int OnInit() {
   GenerateFakeData();
   ExportMt4Statement();
   return(INIT_SUCCEEDED);
}