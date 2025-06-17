#ifndef RISKMANAGEMENT_MQH
#define RISKMANAGEMENT_MQH

//+------------------------------------------------------------------+
//| Get Count of Trades Opened Today by This EA                      |
//+------------------------------------------------------------------+
int GetTodaysTradeCount(ulong magic_number)
  {
   int count = 0;
   datetime today_start = StructToTime((MqlDateTime){TimeCurrent().year, TimeCurrent().mon, TimeCurrent().day, 0, 0, 0});

   HistorySelect(today_start, TimeCurrent()); // Select history from start of today until now

   for(uint i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket > 0)
        {
         if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == magic_number)
           {
            // Count only entry deals that were executed today
            if (HistoryDealGetInteger(deal_ticket, DEAL_TIME) >= today_start)
            {
                ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
                // DEAL_ENTRY_IN: Entry into the market.
                // DEAL_ENTRY_OUT: Reversal of a position (effectively an entry in the opposite direction).
                // DEAL_ENTRY_INOUT: Combined entry and exit (e.g. closing one and opening another simultaneously).
                // We are interested in actual new market entries.
                if(deal_entry == DEAL_ENTRY_IN || deal_entry == DEAL_ENTRY_OUT)
                  {
                   count++;
                  }
            }
           }
        }
     }
   // PrintFormat("GetTodaysTradeCount for magic %d: %d", magic_number, count);
   return count;
  }

//+------------------------------------------------------------------+
//| Get Profit/Loss from Trades Closed Today by This EA              |
//+------------------------------------------------------------------+
double GetTodaysProfitLoss(ulong magic_number)
  {
   double total_profit = 0;
   datetime today_start = StructToTime((MqlDateTime){TimeCurrent().year, TimeCurrent().mon, TimeCurrent().day, 0, 0, 0});

   HistorySelect(today_start, TimeCurrent());

   for(uint i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket > 0)
        {
         if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == magic_number)
           {
            // Sum profit/loss from all deals that occurred today with the specified magic number.
            // This includes realized profit from closed trades, commission, and swap if part of the deal.
            if (HistoryDealGetInteger(deal_ticket, DEAL_TIME) >= today_start)
            {
                total_profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
            }
           }
        }
     }
   // PrintFormat("GetTodaysProfitLoss for magic %d: %.2f", magic_number, total_profit);
   return total_profit;
  }

//+------------------------------------------------------------------+
//| Check Trading Limits (Daily Trades and Drawdown)                 |
//+------------------------------------------------------------------+
bool CheckTradingLimits(ulong magic_number, int daily_max_trades, double daily_max_drawdown_percent,
                          bool &is_dd_hit, bool &is_trade_limit_hit) // Pass by reference to update status
  {
   is_dd_hit = false;
   is_trade_limit_hit = false;

   // 1. Check Max Trades
   if(daily_max_trades > 0) // Only check if limit is set (daily_max_trades > 0)
     {
      int trades_today = GetTodaysTradeCount(magic_number);
      if(trades_today >= daily_max_trades)
        {
         PrintFormat("%s: Daily trade limit reached for magic %d. Trades today: %d, Limit: %d. No new trades allowed.",
                     TimeToString(TimeCurrent(), TIME_SECONDS), magic_number, trades_today, daily_max_trades);
         is_trade_limit_hit = true;
         // return false; // Don't return immediately, check DD as well, then main OnTick can decide
        }
     }

   // 2. Check Max Drawdown
   if(daily_max_drawdown_percent > 0) // Only check if limit is set (daily_max_drawdown_percent > 0)
     {
      double profit_today = GetTodaysProfitLoss(magic_number);
      double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Max allowed loss amount based on current equity.
      // Drawdown percent is usually negative, e.g., -3%. So absolute value of it.
      double max_loss_amount = (MathAbs(daily_max_drawdown_percent) / 100.0) * current_equity;

      // If today's profit is negative (a loss) and its absolute value exceeds max_loss_amount
      if(profit_today < 0 && MathAbs(profit_today) >= max_loss_amount)
        {
         PrintFormat("%s: Daily drawdown limit reached for magic %d. Today's P/L: %.2f, Max Allowed Loss: %.2f (%.2f%% of current equity %.2f). No new trades allowed.",
                     TimeToString(TimeCurrent(), TIME_SECONDS), magic_number, profit_today, max_loss_amount, daily_max_drawdown_percent, current_equity);
         is_dd_hit = true;
         // return false; // Don't return immediately
        }
     }

   if(is_dd_hit || is_trade_limit_hit)
     {
      return false; // Trading not allowed if either limit is hit
     }

   return true; // Trading allowed
  }

//+------------------------------------------------------------------+
//| Check for High-Impact News (Placeholder)                         |
//+------------------------------------------------------------------+
// bool IsNewsTime(string symbol)
// {
//   // TODO: Implement news checking logic (e.g., from an external source or calendar)
//   // For now, always returns false (no news impact)
//   return false;
// }

#endif // RISKMANAGEMENT_MQH
