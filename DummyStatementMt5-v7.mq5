//+------------------------------------------------------------------+
//|   FakeStatementMt5-GenuineGraphLabelResultsAlign.mq5             |
//|   Outputs a fake MT5 statement HTML, ending like a genuine MT5   |
//|   - NO "Summary" block                                           |
//|   - Mini-summary block above the graph and results               |
//|   - Deals section has a totals row at the end (genuine style)    |
//|   - Image row includes "Graph" label in last cell                |
//|   - "Results" heading is right-shifted (colspan=13, then empty)  |
//+------------------------------------------------------------------+
#property strict

// ================= User Inputs =================
input string AccountName    = "John Doe";
input string BrokerName     = "FakeBroker Ltd";
input int    AccountNumber  = 123456;
input string Currency       = "USD";
input double InitialBalance = 10000.0;
input string Symbols        = "EURUSD,GBPUSD,USDJPY";
input int    NumClosedTrades= 10;
input int    NumOpenPositions=0;
input int    NumDeals       = 23;
input string ProfitOrLoss   = "profit";
input string FromDate       = "2025.03.01";
input string ToDate         = "2025.05.30";

// ================= Structures ==================
struct FakeTrade {
   datetime open_time;
   int      ticket;
   string   symbol;
   string   type;
   double   volume;
   double   open_price;
   double   sl;
   double   tp;
   datetime close_time;
   double   close_price;
   double   commission;
   double   swap;
   double   profit;
   bool     is_open;
};
struct FakeDeal {
   int      deal_id;
   int      position_id;
   datetime time;
   string   type;
   string   entry;
   string   symbol;
   double   volume;
   double   price;
   double   commission;
   double   swap;
   double   profit;
   double   balance; // running balance after this deal (for total row)
};

// ================= Globals =====================
FakeTrade open_positions[];
FakeTrade positions[];
FakeTrade orders[];
FakeDeal  deals[];

double    total_commission = 0;
double    total_swap       = 0;
double    total_profit     = 0;
double    final_balance    = 0;
double    floating_pl      = 0;
double    equity           = 0;
double    margin           = 0;
double    free_margin      = 0;
double    margin_level     = 0;
int       num_wins         = 0;
int       num_losses       = 0;
double    largest_win      = 0;
double    largest_loss     = 0;
double    avg_win          = 0;
double    avg_loss         = 0;
int       max_consec_wins  = 0;
int       max_consec_losses= 0;
double    max_consec_profit= 0;
double    max_consec_loss  = 0;
int       max_consec_profit_count = 0;
int       max_consec_loss_count = 0;
double    profit_factor    = 0;
double    gross_profit     = 0;
double    gross_loss       = 0;
double    expected_payoff  = 0;
double    recovery_factor  = 0;
double    sharpe_ratio     = 0.01;
double    abs_drawdown     = 16276.52;
double    max_drawdown     = 23663.91;
double    rel_drawdown     = 4.62;
int       total_trades     = 0;
int       short_trades     = 0;
int       long_trades      = 0;
double    short_win_pct    = 47.0;
double    long_win_pct     = 54.0;
double    profit_trades_pct= 0.0;
double    loss_trades_pct  = 0.0;
double    avg_consec_wins  = 1.0;
double    avg_consec_losses= 1.0;

// ========= Helper: MT5-style Number Formatting =========
string NumFmt(double x) {
   string s = DoubleToString(MathAbs(x),2);
   int dot = StringFind(s,".");
   if(dot<0) dot=StringLen(s);
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
   StringTrimLeft(t); StringTrimRight(t);
   return(t);
}
string MT5Date(datetime dt) {
   return(TimeToString(dt, TIME_DATE|TIME_SECONDS));
}

// ================ Fake Data Generation ================
void GenerateFakeData() {
   string syms[];
   int sym_count = StringSplit(Symbols,',',syms);
   for(int i=0;i<sym_count;i++) syms[i]=Trim(syms[i]);
   MathSrand((uint)TimeLocal());

   datetime from = StringToTime(FromDate + " 00:00:01");
   datetime to   = StringToTime(ToDate   + " 23:59:59");
   int total_seconds = (int)(to-from);

   int ticket_base = 1000000+MathRand()%100000;
   int deal_base   = 2000000+MathRand()%100000;

   ArrayResize(positions, NumClosedTrades);
   ArrayResize(orders, NumClosedTrades);
   total_commission = 0; total_swap = 0; total_profit = 0;
   num_wins=0; num_losses=0; largest_win=0; largest_loss=0; avg_win=0; avg_loss=0;
   max_consec_wins=0; max_consec_losses=0; max_consec_profit=0; max_consec_loss=0;
   max_consec_profit_count=0; max_consec_loss_count=0;
   gross_profit=0; gross_loss=0;
   double running_balance = InitialBalance;
   double global_profit = (ProfitOrLoss=="profit" ? MathAbs(InitialBalance*0.1) : -MathAbs(InitialBalance*0.1));
   double per_trade = (NumClosedTrades>0) ? global_profit/NumClosedTrades : 0;

   int deal_idx = 0;
   int position_id = ticket_base;
   int cur_consec_win=0, cur_consec_loss=0;
   double sum_win=0, sum_loss=0;
   double cur_consec_profit=0, cur_consec_loss_amt=0;
   int cur_consec_profit_count=0, cur_consec_loss_count=0;
   short_trades=0; long_trades=0;
   for(int i=0;i<NumClosedTrades;i++) {
      FakeTrade t;
      t.ticket = ticket_base + i;
      t.symbol = syms[MathRand()%sym_count];
      t.type = (MathRand()%2==0) ? "buy" : "sell";
      t.volume = NormalizeDouble(0.1 + (MathRand()%10)*0.01,2);
      t.open_time = from + MathRand()%(total_seconds-3600);
      t.close_time= t.open_time + 60*(MathRand()%1440+5);
      int sym_digits = (t.symbol=="USDJPY")?3:5;
      double op = 1.05 + (MathRand()%1000-500)*0.00001;
      if(StringFind(t.symbol,"JPY")>=0) op = 149.0 + (MathRand()%1000-500)*0.001;
      t.open_price = NormalizeDouble(op,sym_digits);
      double cp = op + ((t.type=="buy"?1:-1)*per_trade/(10*t.volume)) + (MathRand()%20-10)*0.00001;
      if(StringFind(t.symbol,"JPY")>=0) cp = op + ((t.type=="buy"?1:-1)*per_trade/(2*t.volume)) + (MathRand()%20-10)*0.001;
      t.close_price = NormalizeDouble(cp,sym_digits);
      t.sl = 0; t.tp = 0;
      t.commission = (MathRand()%2==0) ? 0.0 : NormalizeDouble((MathRand()%3)*-1.0,2);
      t.swap = (MathRand()%2==0) ? 0.0 : NormalizeDouble((MathRand()%21-10)*0.01,2);
      if(i==NumClosedTrades-1)
         t.profit = global_profit - total_profit;
      else
         t.profit = NormalizeDouble(per_trade + (MathRand()%21-10),2);

      t.is_open = false;
      total_commission += t.commission;
      total_swap += t.swap;
      total_profit += t.profit;
      running_balance += t.profit;
      positions[i]=t;
      orders[i]=t;

      if(t.type=="buy") long_trades++; else short_trades++;
      if(t.profit>0) {
         num_wins++; sum_win+=t.profit; gross_profit+=t.profit;
         cur_consec_win++; cur_consec_loss=0;
         cur_consec_profit+=t.profit; cur_consec_profit_count++;
         cur_consec_loss_amt=0; cur_consec_loss_count=0;
         if(t.profit>largest_win || largest_win==0) largest_win=t.profit;
         if(cur_consec_win>max_consec_wins) max_consec_wins = cur_consec_win;
         if(cur_consec_profit>max_consec_profit) { max_consec_profit=cur_consec_profit; max_consec_profit_count=cur_consec_profit_count; }
      } else if(t.profit<0) {
         num_losses++; sum_loss+=t.profit; gross_loss+=t.profit;
         cur_consec_loss++; cur_consec_win=0;
         cur_consec_loss_amt+=t.profit; cur_consec_loss_count++;
         cur_consec_profit=0; cur_consec_profit_count=0;
         if(t.profit<largest_loss || largest_loss==0) largest_loss=t.profit;
         if(cur_consec_loss>max_consec_losses) max_consec_losses = cur_consec_loss;
         if(cur_consec_loss_amt<max_consec_loss) { max_consec_loss=cur_consec_loss_amt; max_consec_loss_count=cur_consec_loss_count; }
      }
      // Deals for closed: open (entry) and close (exit)
      if(deal_idx<NumDeals) {
         FakeDeal d;
         d.deal_id = deal_base + deal_idx;
         d.position_id = t.ticket;
         d.time = t.open_time;
         d.type = t.type;
         d.entry = "in";
         d.symbol = t.symbol;
         d.volume = t.volume;
         d.price = t.open_price;
         d.commission = t.commission/2.0;
         d.swap = 0.0;
         d.profit = 0.0;
         d.balance = running_balance;
         if(ArraySize(deals)<=deal_idx) ArrayResize(deals,deal_idx+1);
         deals[deal_idx++] = d;
      }
      if(deal_idx<NumDeals) {
         FakeDeal d;
         d.deal_id = deal_base + deal_idx;
         d.position_id = t.ticket;
         d.time = t.close_time;
         d.type = (t.type=="buy")?"sell":"buy";
         d.entry = "out";
         d.symbol = t.symbol;
         d.volume = t.volume;
         d.price = t.close_price;
         d.commission = t.commission/2.0;
         d.swap = t.swap;
         d.profit = t.profit;
         d.balance = running_balance;
         if(ArraySize(deals)<=deal_idx) ArrayResize(deals,deal_idx+1);
         deals[deal_idx++] = d;
      }
   }
   final_balance = running_balance;
   avg_win = (num_wins>0) ? sum_win/num_wins : 0;
   avg_loss = (num_losses>0) ? sum_loss/num_losses : 0;

   floating_pl=0;
   if(NumOpenPositions>0) {
      ArrayResize(open_positions,NumOpenPositions);
      for(int i=0;i<NumOpenPositions;i++) {
         FakeTrade t;
         t.ticket = ticket_base + NumClosedTrades + i;
         t.symbol = syms[MathRand()%sym_count];
         t.type = (MathRand()%2==0) ? "buy" : "sell";
         t.volume = NormalizeDouble(0.1 + (MathRand()%10)*0.01,2);
         t.open_time = to - (MathRand()%86400);
         int sym_digits = (t.symbol=="USDJPY")?3:5;
         double op = 1.05 + (MathRand()%1000-500)*0.00001;
         if(StringFind(t.symbol,"JPY")>=0) op = 149.0 + (MathRand()%1000-500)*0.001;
         t.open_price = NormalizeDouble(op,sym_digits);
         t.close_time = 0;
         t.close_price = 0;
         t.sl = 0; t.tp = 0;
         t.commission = 0.0;
         t.swap = 0.0;
         t.profit = NormalizeDouble((MathRand()%200-100),2);
         t.is_open = true;
         open_positions[i]=t;
         floating_pl += t.profit;

         if(deal_idx<NumDeals) {
            FakeDeal d;
            d.deal_id = deal_base + deal_idx;
            d.position_id = t.ticket;
            d.time = t.open_time;
            d.type = t.type;
            d.entry = "in";
            d.symbol = t.symbol;
            d.volume = t.volume;
            d.price = t.open_price;
            d.commission = 0.0;
            d.swap = 0.0;
            d.profit = 0.0;
            d.balance = running_balance;
            if(ArraySize(deals)<=deal_idx) ArrayResize(deals,deal_idx+1);
            deals[deal_idx++] = d;
         }
      }
   }
   equity = final_balance + floating_pl;
   margin = MathMax(0.0, (NumOpenPositions>0) ? MathAbs(final_balance*0.03) : 0.0);
   free_margin = equity - margin;
   margin_level = (margin>0.0) ? (equity/margin)*100.0 : 0.0;

   total_trades = NumClosedTrades;
   profit_factor = (gross_loss != 0) ? MathAbs(gross_profit/gross_loss) : 0;
   expected_payoff = (total_trades>0) ? total_profit/total_trades : 0;
   recovery_factor = (abs_drawdown > 0) ? total_profit/abs_drawdown : 0.77;
   profit_trades_pct = (total_trades>0) ? 100.0*num_wins/total_trades : 0;
   loss_trades_pct = (total_trades>0) ? 100.0*num_losses/total_trades : 0;
}

// ============= Results Section =============
void WriteResultsSection(int f) {
   FileWriteString(f,"  <tr align=\"center\">\r\n    <th colspan=\"13\" style=\"height: 25px\"><div style=\"font: 10pt Tahoma\"><b>Results</b></div></th><th></th>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Total Net Profit:</td><td nowrap><b>"+NumFmt(total_profit)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Gross Profit:</td><td nowrap><b>"+NumFmt(gross_profit)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Gross Loss:</td><td nowrap colspan=\"2\"><b>"+NumFmt(gross_loss)+"</b></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Profit Factor:</td><td nowrap><b>"+DoubleToString(profit_factor,2)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Expected Payoff:</td><td nowrap><b>"+DoubleToString(expected_payoff,2)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\"></td><td nowrap colspan=\"2\"></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Recovery Factor:</td><td nowrap><b>"+DoubleToString(recovery_factor,2)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Sharpe Ratio:</td><td nowrap><b>"+DoubleToString(sharpe_ratio,2)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\"></td><td nowrap colspan=\"2\"></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr><td nowrap style=\"height: 10px\"></td></tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Balance Drawdown:</td></tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Balance Drawdown Absolute:</td><td nowrap><b>"+NumFmt(abs_drawdown)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Balance Drawdown Maximal:</td><td nowrap><b>"+NumFmt(max_drawdown)+" ("+DoubleToString(rel_drawdown,2)+"%)</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Balance Drawdown Relative:</td><td nowrap colspan=\"2\"><b>"+DoubleToString(rel_drawdown,2)+"% ("+NumFmt(max_drawdown)+")</b></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr><td nowrap style=\"height: 10px\"></td></tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Total Trades:</td><td nowrap><b>"+IntegerToString(total_trades)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Short Trades (won %):</td><td nowrap><b>"+IntegerToString(short_trades)+" ("+DoubleToString(short_win_pct,2)+"%)</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Long Trades (won %):</td><td nowrap colspan=\"2\"><b>"+IntegerToString(long_trades)+" ("+DoubleToString(long_win_pct,2)+"%)</b></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"4\"></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Profit Trades (% of total):</td><td nowrap><b>"+IntegerToString(num_wins)+" ("+DoubleToString(profit_trades_pct,2)+"%)</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Loss Trades (% of total):</td><td nowrap colspan=\"2\"><b>"+IntegerToString(num_losses)+" ("+DoubleToString(loss_trades_pct,2)+"%)</b></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"4\"></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Largest profit trade:</td><td nowrap><b>"+NumFmt(largest_win)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Largest loss trade:</td><td nowrap colspan=\"2\"><b>"+NumFmt(largest_loss)+"</b></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"4\"></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Average profit trade:</td><td nowrap><b>"+NumFmt(avg_win)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Average loss trade:</td><td nowrap colspan=\"2\"><b>"+NumFmt(avg_loss)+"</b></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"4\"></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Maximum consecutive wins ($):</td><td nowrap><b>"+IntegerToString(max_consec_wins)+" ("+NumFmt(max_consec_wins*avg_win)+")</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Maximum consecutive losses ($):</td><td nowrap colspan=\"2\"><b>"+IntegerToString(max_consec_losses)+" ("+NumFmt(max_consec_losses*avg_loss)+")</b></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"4\"></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Maximal consecutive profit (count):</td><td nowrap><b>"+NumFmt(max_consec_profit)+" ("+IntegerToString(max_consec_profit_count)+")</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Maximal consecutive loss (count):</td><td nowrap colspan=\"2\"><b>"+NumFmt(max_consec_loss)+" ("+IntegerToString(max_consec_loss_count)+")</b></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td nowrap colspan=\"4\"></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Average consecutive wins:</td><td nowrap><b>"+DoubleToString(avg_consec_wins,0)+"</b></td>");
   FileWriteString(f,"    <td nowrap colspan=\"3\">Average consecutive losses:</td><td nowrap colspan=\"2\"><b>"+DoubleToString(avg_consec_losses,0)+"</b></td>");
   FileWriteString(f,"  </tr>\r\n");
   FileWriteString(f,"  <tr><td nowrap style=\"height: 10px\"></td></tr>\r\n");
}

// ============= Mini-Summary Section =============
void WriteMiniSummarySection(int f) {
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td colspan=\"3\" style=\"height: 20px\">Balance:</td>");
   FileWriteString(f,"    <td colspan=\"2\"><b>"+NumFmt(final_balance)+"</b></td>");
   FileWriteString(f,"    <td></td>");
   FileWriteString(f,"    <td colspan=\"3\">Free Margin:</td>");
   FileWriteString(f,"    <td colspan=\"2\"><b>"+NumFmt(free_margin)+"</b></td>");
   FileWriteString(f,"    <td colspan=\"3\"></td>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td colspan=\"3\" style=\"height: 20px\">Credit Facility:</td>");
   FileWriteString(f,"    <td colspan=\"2\"><b>0.00</b></td>");
   FileWriteString(f,"    <td></td>");
   FileWriteString(f,"    <td colspan=\"3\">Margin:</td>");
   FileWriteString(f,"    <td colspan=\"2\"><b>"+NumFmt(margin)+"</b></td>");
   FileWriteString(f,"    <td colspan=\"3\"></td>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td colspan=\"3\" style=\"height: 20px\">Floating P/L:</td>");
   FileWriteString(f,"    <td colspan=\"2\"><b>"+NumFmt(floating_pl)+"</b></td>");
   FileWriteString(f,"    <td></td>");
   FileWriteString(f,"    <td colspan=\"3\">Margin Level:</td>");
   FileWriteString(f,"    <td colspan=\"2\"><b>"+DoubleToString(margin_level,2)+"%</b></td>");
   FileWriteString(f,"    <td colspan=\"3\"></td>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td colspan=\"3\" style=\"height: 20px\">Equity:</td>");
   FileWriteString(f,"    <td colspan=\"2\"><b>"+NumFmt(equity)+"</b></td>");
   FileWriteString(f,"    <td colspan=\"9\"></td>\r\n  </tr>\r\n");
}

// ============= Deals Totals Row =============
void WriteDealsTotalsRow(int f) {
   double sum_commission=0, sum_fee=0, sum_swap=0, sum_profit=0;
   for(int i=0;i<ArraySize(deals);i++) {
      sum_commission += deals[i].commission;
      sum_swap      += deals[i].swap;
      sum_profit    += deals[i].profit;
   }
   FileWriteString(f,"  <tr align=\"right\">\r\n");
   FileWriteString(f,"    <td colspan=\"8\" style=\"height: 30px\"></td>");
   FileWriteString(f,"    <td><b>"+NumFmt(sum_commission)+"</b></td>");
   FileWriteString(f,"    <td><b>0.00</b></td>");
   FileWriteString(f,"    <td><b>"+NumFmt(sum_swap)+"</b></td>");
   FileWriteString(f,"    <td><b>"+NumFmt(sum_profit)+"</b></td>");
   FileWriteString(f,"    <td><b>"+NumFmt(final_balance)+"</b></td>");
   FileWriteString(f,"    <td></td>\r\n  </tr>\r\n");
}

// ============= Main Export Function =============
void ExportMt5Statement() {
   string fname = StringFormat("ReportHistory-%d.html",AccountNumber);
   int f = FileOpen(fname, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE) { Print("Cannot create file: ",fname); return; }
   FileWriteString(f,"<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">\r\n");
   FileWriteString(f,"<html>\r\n<head>\r\n<title>");
   FileWriteString(f,IntegerToString(AccountNumber)+": "+AccountName+" - Trade History Report</title>\r\n");
   FileWriteString(f,"<meta name=\"generator\" content=\"client terminal\">\r\n");
   FileWriteString(f,"<style type=\"text/css\">\r\n<!--\r\n@media screen { td { font: 8pt  Tahoma,Arial; } th { font: 10pt Tahoma,Arial; } }\r\n@media print { td { font: 7pt Tahoma,Arial; } th { font: 9pt Tahoma,Arial; } }\r\n.msdate { mso-number-format:\"General Date\"; }\r\n.mspt   { mso-number-format:\\#\\,\\#\\#0\\.00;  }\r\n.hidden { display: none; }\r\nbody {margin:1px;}\r\n//-->\r\n</style>\r\n</head>\r\n<body>\r\n");
   FileWriteString(f,"<div align=\"center\">\r\n<table cellspacing=1 cellpadding=3 border=0>\r\n");
   FileWriteString(f,"  <tr align=\"center\">\r\n    <td colspan=14><div style=\"font: 14pt Tahoma\"><b>Trade History Report</b><br></div></td>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"left\">\r\n");
   FileWriteString(f,"    <th colspan=4 nowrap align=right style=\"width: 220px; height: 20px\">Name:</th>\r\n");
   FileWriteString(f,"    <th colspan=10 nowrap align=left  style=\"width: 220px; height: 20px\"><b>"+AccountName+"</b></th>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"left\">\r\n");
   FileWriteString(f,"    <th colspan=4 nowrap align=right style=\"width: 220px; height: 20px\">Account:</th>\r\n");
   FileWriteString(f,"    <th colspan=10 nowrap align=left  style=\"width: 220px; height: 20px\"><b>"+IntegerToString(AccountNumber)+"&nbsp;("+Currency+")</b></th>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"left\">\r\n");
   FileWriteString(f,"    <th colspan=4 nowrap align=right style=\"width: 220px; height: 20px\">Company:</th>\r\n");
   FileWriteString(f,"    <th colspan=10 nowrap align=left  style=\"width: 220px; height: 20px\"><b>"+BrokerName+"</b></th>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"left\">\r\n");
   FileWriteString(f,"    <th colspan=4 nowrap align=right style=\"width: 220px; height: 20px\">Date:</th>\r\n");
   FileWriteString(f,"    <th colspan=10 nowrap align=left  style=\"width: 220px; height: 20px\"><b>"+MT5Date(TimeCurrent())+"</b></th>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr><td nowrap style=\"width: 140px;height: 10px\"></td><td nowrap style=\"width: 60px;\"></td><td nowrap style=\"width: 60px;\"></td><td nowrap style=\"width: 60px;\"></td><td nowrap style=\"width: 70px;\"></td><td nowrap style=\"width: 60px;\"></td><td nowrap style=\"width: 60px;\"></td><td nowrap style=\"width: 60px;\"></td><td nowrap style=\"width: 140px;\"></td><td nowrap style=\"width: 60px;\"></td><td nowrap style=\"width: 60px;\"></td><td nowrap style=\"width: 60px;\"></td><td nowrap style=\"width: 60px;\"></td><td nowrap style=\"width: 100px;\"></td></tr>\r\n");

   // ------------------ Positions Section (closed) ------------------
   FileWriteString(f,"  <tr align=\"center\">\r\n    <th colspan=14 style=\"height: 25px\"><div style=\"font: 10pt Tahoma\"><b>Positions</b></div></th>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"center\" bgcolor=\"#E5F0FC\">\r\n");
   FileWriteString(f,"    <td nowrap style=\"height: 30px\"><b>Time</b></td><td nowrap><b>Position</b></td><td nowrap><b>Symbol</b></td><td nowrap><b>Type</b></td><td nowrap><b>Volume</b></td><td nowrap><b>Price</b></td><td nowrap><b>S / L</b></td><td nowrap><b>T / P</b></td><td nowrap><b>Time</b></td><td nowrap><b>Price</b></td><td nowrap><b>Commission</b></td><td nowrap><b>Swap</b></td><td nowrap colspan=2><b>Profit</b></td>\r\n  </tr>\r\n");
   for(int i=0;i<ArraySize(positions);i++) {
      string bg = (i%2==0)?"#FFFFFF":"#F7F7F7";
      FileWriteString(f,"  <tr bgcolor=\""+bg+"\" align=\"right\">\r\n");
      FileWriteString(f,"    <td>"+MT5Date(positions[i].open_time)+"</td>");
      FileWriteString(f,"    <td>"+IntegerToString(positions[i].ticket)+"</td>");
      FileWriteString(f,"    <td>"+positions[i].symbol+"</td>");
      FileWriteString(f,"    <td>"+positions[i].type+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(positions[i].volume,2)+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(positions[i].open_price,5)+"</td>");
      FileWriteString(f,"    <td>"+(positions[i].sl==0.0?"":DoubleToString(positions[i].sl,5))+"</td>");
      FileWriteString(f,"    <td>"+(positions[i].tp==0.0?"":DoubleToString(positions[i].tp,5))+"</td>");
      FileWriteString(f,"    <td>"+MT5Date(positions[i].close_time)+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(positions[i].close_price,5)+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(positions[i].commission,2)+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(positions[i].swap,2)+"</td>");
      FileWriteString(f,"    <td colspan=2>"+DoubleToString(positions[i].profit,2)+"</td>");
      FileWriteString(f,"  </tr>\r\n");
   }
   // ------------------ Orders Section ------------------
   FileWriteString(f,"  <tr align=\"center\">\r\n    <th colspan=14 style=\"height: 25px\"><div style=\"font: 10pt Tahoma\"><b>Orders</b></div></th>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"center\" bgcolor=\"#E5F0FC\">\r\n");
   FileWriteString(f,"    <td nowrap style=\"height: 30px\"><b>Time</b></td><td nowrap><b>Order</b></td><td nowrap><b>Symbol</b></td><td nowrap><b>Type</b></td><td nowrap><b>Volume</b></td><td nowrap><b>Price</b></td><td nowrap><b>S / L</b></td><td nowrap><b>T / P</b></td><td nowrap><b>Time</b></td><td nowrap><b>Price</b></td><td nowrap colspan=4></td>\r\n  </tr>\r\n");
   for(int i=0;i<ArraySize(orders);i++) {
      string bg = (i%2==0)?"#FFFFFF":"#F7F7F7";
      FileWriteString(f,"  <tr bgcolor=\""+bg+"\" align=\"right\">\r\n");
      FileWriteString(f,"    <td>"+MT5Date(orders[i].open_time)+"</td>");
      FileWriteString(f,"    <td>"+IntegerToString(orders[i].ticket)+"</td>");
      FileWriteString(f,"    <td>"+orders[i].symbol+"</td>");
      FileWriteString(f,"    <td>"+orders[i].type+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(orders[i].volume,2)+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(orders[i].open_price,5)+"</td>");
      FileWriteString(f,"    <td>"+(orders[i].sl==0.0?"":DoubleToString(orders[i].sl,5))+"</td>");
      FileWriteString(f,"    <td>"+(orders[i].tp==0.0?"":DoubleToString(orders[i].tp,5))+"</td>");
      FileWriteString(f,"    <td>"+MT5Date(orders[i].close_time)+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(orders[i].close_price,5)+"</td>");
      FileWriteString(f,"    <td colspan=4></td>");
      FileWriteString(f,"  </tr>\r\n");
   }
   // ------------------ Deals Section ------------------
   FileWriteString(f,"  <tr align=\"center\">\r\n    <th colspan=14 style=\"height: 25px\"><div style=\"font: 10pt Tahoma\"><b>Deals</b></div></th>\r\n  </tr>\r\n");
   FileWriteString(f,"  <tr align=\"center\" bgcolor=\"#E5F0FC\">\r\n");
   FileWriteString(f,"    <td nowrap style=\"height: 30px\"><b>Time</b></td>");
   FileWriteString(f,"    <td nowrap><b>Deal</b></td>");
   FileWriteString(f,"    <td nowrap><b>Position</b></td>");
   FileWriteString(f,"    <td nowrap><b>Type</b></td>");
   FileWriteString(f,"    <td nowrap><b>Entry</b></td>");
   FileWriteString(f,"    <td nowrap><b>Symbol</b></td>");
   FileWriteString(f,"    <td nowrap><b>Volume</b></td>");
   FileWriteString(f,"    <td nowrap><b>Price</b></td>");
   FileWriteString(f,"    <td nowrap><b>Commission</b></td>");
   FileWriteString(f,"    <td nowrap><b>Fee</b></td>");
   FileWriteString(f,"    <td nowrap><b>Swap</b></td>");
   FileWriteString(f,"    <td nowrap><b>Profit</b></td>");
   FileWriteString(f,"    <td nowrap><b>Balance</b></td>");
   FileWriteString(f,"    <td nowrap></td>\r\n  </tr>\r\n");
   for(int i=0;i<ArraySize(deals);i++) {
      string bg = (i%2==0)?"#FFFFFF":"#F7F7F7";
      FileWriteString(f,"  <tr bgcolor=\""+bg+"\" align=\"right\">\r\n");
      FileWriteString(f,"    <td>"+MT5Date(deals[i].time)+"</td>");
      FileWriteString(f,"    <td>"+IntegerToString(deals[i].deal_id)+"</td>");
      FileWriteString(f,"    <td>"+IntegerToString(deals[i].position_id)+"</td>");
      FileWriteString(f,"    <td>"+deals[i].type+"</td>");
      FileWriteString(f,"    <td>"+deals[i].entry+"</td>");
      FileWriteString(f,"    <td>"+deals[i].symbol+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(deals[i].volume,2)+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(deals[i].price,5)+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(deals[i].commission,2)+"</td>");
      FileWriteString(f,"    <td>0.00</td>");
      FileWriteString(f,"    <td>"+DoubleToString(deals[i].swap,2)+"</td>");
      FileWriteString(f,"    <td>"+DoubleToString(deals[i].profit,2)+"</td>");
      FileWriteString(f,"    <td>"+NumFmt(deals[i].balance)+"</td>");
      FileWriteString(f,"    <td></td>");
      FileWriteString(f,"  </tr>\r\n");
   }
   WriteDealsTotalsRow(f);

   // ------------------ Open Positions Section ------------------
   if(ArraySize(open_positions)>0) {
      FileWriteString(f,"  <tr align=\"center\">\r\n    <th colspan=14 style=\"height: 25px\"><div style=\"font: 10pt Tahoma\"><b>Open Positions</b></div></th>\r\n  </tr>\r\n");
      FileWriteString(f,"  <tr align=\"center\" bgcolor=\"#E5F0FC\">\r\n");
      FileWriteString(f,"    <td nowrap style=\"height: 30px\"><b>Time</b></td><td nowrap><b>Position</b></td><td nowrap><b>Symbol</b></td><td nowrap><b>Type</b></td><td nowrap><b>Volume</b></td><td nowrap><b>Price</b></td><td nowrap><b>S / L</b></td><td nowrap><b>T / P</b></td><td nowrap colspan=6></td>\r\n  </tr>\r\n");
      for(int i=0;i<ArraySize(open_positions);i++) {
         string bg = (i%2==0)?"#FFFFFF":"#F7F7F7";
         FileWriteString(f,"  <tr bgcolor=\""+bg+"\" align=\"right\">\r\n");
         FileWriteString(f,"    <td>"+MT5Date(open_positions[i].open_time)+"</td>");
         FileWriteString(f,"    <td>"+IntegerToString(open_positions[i].ticket)+"</td>");
         FileWriteString(f,"    <td>"+open_positions[i].symbol+"</td>");
         FileWriteString(f,"    <td>"+open_positions[i].type+"</td>");
         FileWriteString(f,"    <td>"+DoubleToString(open_positions[i].volume,2)+"</td>");
         FileWriteString(f,"    <td>"+DoubleToString(open_positions[i].open_price,5)+"</td>");
         FileWriteString(f,"    <td>"+(open_positions[i].sl==0.0?"":DoubleToString(open_positions[i].sl,5))+"</td>");
         FileWriteString(f,"    <td>"+(open_positions[i].tp==0.0?"":DoubleToString(open_positions[i].tp,5))+"</td>");
         FileWriteString(f,"    <td colspan=6></td>");
         FileWriteString(f,"  </tr>\r\n");
      }
   }

   // ----------- Mini-summary above graph/results -----------
   WriteMiniSummarySection(f);

   // ----------- Image row with "Graph" label --------------
   FileWriteString(f,"  <tr align=\"center\">\r\n");
   FileWriteString(f,"    <th colspan=\"13\"><img src=\"ReportHistory-"+IntegerToString(AccountNumber)+".png\" title=\"Balance graph\" width=820 height=200 border=0 alt=\"Graph\"></th>\r\n");
   //FileWriteString(f,"    <th>Graph</th>\r\n");
   FileWriteString(f,"  </tr>\r\n");

   // ----------- Results section ---------------------------
   WriteResultsSection(f);

   FileWriteString(f,"</table>\r\n</div>\r\n</body>\r\n</html>\r\n");
   FileClose(f);
   Print("MT5-style statement written to: ",fname);
}

int OnInit() {
   GenerateFakeData();
   ExportMt5Statement();
   return(INIT_SUCCEEDED);
}
void OnTick() {}