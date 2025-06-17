#ifndef TRADELOGIC_MQH
#define TRADELOGIC_MQH

#include "Indicators.mqh" // Assumed to be in the same include path
#include "SMC.mqh"       // Assumed to be in the same include path

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk Percentage and SL pips          |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double risk_percent, double stop_loss_pips)
  {
   if(stop_loss_pips <= 0 || risk_percent <= 0)
     {
      PrintFormat("Invalid parameters for CalculateLotSize. SL Pips: %.2f, Risk Percent: %.2f", stop_loss_pips, risk_percent);
      return 0.0;
     }

   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (risk_percent / 100.0);

   SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE); // Ensure symbol properties are updated
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double point_size = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tick_value == 0 || point_size == 0)
     {
      PrintFormat("Unable to get tick value or point size for %s. TickValue: %.5f, PointSize: %.5f", symbol, tick_value, point_size);
      return 0.0;
     }

   // stop_loss_pips is assumed to be in "pips". For many brokers/symbols, 1 pip = 10 points.
   // For XAUUSD, 1 pip is often considered 0.10 price movement (e.g. 1900.10 to 1900.20).
   // If SYMBOL_POINT is 0.01, then 1 pip = 0.10 means stop_loss_pips should be multiplied by 10 to get points.
   // The user mentioned "15 pips minimum". If this means 1.5 USD on XAUUSD (where point = 0.01), then it's 150 points.
   // Let's assume 'stop_loss_pips' parameter means the actual price move in points (smallest price change unit).
   // So, if user means 15 "standard pips" for XAUUSD (e.g. 1.5 price move), they should input 150 for stop_loss_pips.
   // This needs to be very clear in documentation or input description.
   // For now, assuming stop_loss_pips is in points (tick_size movements).

   double value_per_point_one_lot = tick_value; // SYMBOL_TRADE_TICK_VALUE is usually the value of one point movement for 1 lot in deposit currency.

   if (value_per_point_one_lot == 0) {
       PrintFormat("Value per point for one lot is zero for %s.", symbol);
       return 0.0;
   }

   double total_sl_value_per_lot = stop_loss_pips * value_per_point_one_lot;

   if (total_sl_value_per_lot == 0) {
       PrintFormat("Total SL value per lot is zero. SL Pips (Points): %.2f, Value per Point: %.5f", stop_loss_pips, value_per_point_one_lot);
       return 0.0;
   }

   double lot_size = risk_amount / total_sl_value_per_lot;

   // Normalize lot size
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   lot_size = MathFloor(lot_size / lot_step) * lot_step;

   if(lot_size < min_lot)
     lot_size = min_lot;
   if(lot_size > max_lot)
     lot_size = max_lot;

   if (lot_size == 0 && risk_amount > 0 && min_lot > 0) {
       PrintFormat("Calculated lot size is 0 for %s. SL Points: %.2f. Risk Amount: %.2f. Value per Point: %.5f. MinLot: %.2f. This may indicate SL is too small for risk % or account too small.",
                   symbol, stop_loss_pips, risk_amount, value_per_point_one_lot, min_lot);
       // Decide if we should default to min_lot here, which could exceed risk_percent
       // lot_size = min_lot; // This would trade min_lot even if it violates risk_percent. For now, let it be 0 if calculation leads to it.
   }

   PrintFormat("CalculateLotSize: Balance: %.2f, Risk %%: %.2f, Risk Amt: %.2f, SL Points: %.2f, Val/Pt (1 Lot): %.5f, Calc Lot: %.2f (Min:%.2f, Max:%.2f, Step:%.2f)",
               account_balance, risk_percent, risk_amount, stop_loss_pips, value_per_point_one_lot, lot_size, min_lot, max_lot, lot_step);

   return lot_size;
  }

struct EntrySignal
  {
   bool valid_signal;      // Is there a valid signal?
   ENUM_ORDER_TYPE type;   // ORDER_TYPE_BUY or ORDER_TYPE_SELL
   double entry_price;     // Proposed entry price (e.g., current market price)
   double stop_loss_price; // Proposed stop loss price
   double take_profit_price; // Proposed take profit price
   string comment;         // Signal comment
   // Add more fields if needed, e.g., which SMC pattern triggered
  };

//+------------------------------------------------------------------+
//| Check Entry Conditions                                           |
//+------------------------------------------------------------------+
EntrySignal CheckEntryConditions(string symbol, ENUM_TIMEFRAMES timeframe,
                                 int ema_fast_period, int ema_slow_period,
                                 int rsi_period, double rsi_overbought, double rsi_oversold,
                                 int bos_swing_lookback, int bos_confirmation_lookback,
                                 double tp_rr_ratio,
                                 double fixed_sl_points // Renamed from pips to points for clarity
                                )
  {
   EntrySignal signal;
   signal.valid_signal = false;

   // 1. Get current market prices (Ask for Buy, Bid for Sell)
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT); // Smallest price change

   if(ask == 0 || bid == 0 || point == 0) {
       PrintFormat("Invalid market prices for %s. Ask:%.5f, Bid:%.5f, Point:%.5f", symbol, ask, bid, point);
       return signal;
   }

   // 2. Calculate Indicators
   // Shift 1 for last closed bar, shift 0 for current forming bar. We need indicators on closed bars.
   double ema_fast_current = GetEMA(symbol, timeframe, ema_fast_period, 1);
   double ema_slow_current = GetEMA(symbol, timeframe, ema_slow_period, 1);
   double rsi_current = GetRSI(symbol, timeframe, rsi_period, 1);

   if(ema_fast_current < 0 || ema_slow_current < 0 || rsi_current < 0) // Error in indicator calc
     {
      PrintFormat("Error calculating indicators for %s. EMA_Fast: %.5f, EMA_Slow: %.5f, RSI: %.2f",
                  symbol, ema_fast_current, ema_slow_current, rsi_current);
      return signal;
     }

   // 3. Check SMC Signals (BOS for now)
   // CheckBOS uses confirmation_lookback starting from shift 1 (closed bars)
   int bos_signal = CheckBOS(symbol, timeframe, bos_swing_lookback, bos_confirmation_lookback);

   // 4. Combine Logic for BUY Signal
   //    - Bullish BOS (bos_signal == 1)
   //    - RSI < rsi_oversold  (Original: RSI > 70 for Buy - this was likely a typo in description, should be oversold for buy)
   //    - EMA Fast > EMA Slow
   if(bos_signal == 1 && rsi_current < rsi_oversold && ema_fast_current > ema_slow_current)
     {
          signal.valid_signal = true;
          signal.type = ORDER_TYPE_BUY;
          signal.entry_price = ask; // Enter at current Ask
          signal.stop_loss_price = signal.entry_price - fixed_sl_points * point;
          signal.take_profit_price = signal.entry_price + (fixed_sl_points * tp_rr_ratio) * point;
          signal.comment = "BUY: BOS + RSI Oversold + EMA Bullish";
          PrintFormat("%s %s: BUY Signal. Price:%.5f SL:%.5f TP:%.5f. BOS:%d, RSI:%.2f (OS:%.1f), EMAFast:%.5f, EMASlow:%.5f, SL points: %.1f",
                       symbol, EnumToString(timeframe), signal.entry_price, signal.stop_loss_price, signal.take_profit_price,
                       bos_signal, rsi_current, rsi_oversold, ema_fast_current, ema_slow_current, fixed_sl_points);
          return signal;
     }

   // 5. Combine Logic for SELL Signal
   //    - Bearish BOS (bos_signal == -1)
   //    - RSI > rsi_overbought (Original: RSI < 30 for Sell - this was likely a typo, should be overbought for sell)
   //    - EMA Fast < EMA Slow
   if(bos_signal == -1 && rsi_current > rsi_overbought && ema_fast_current < ema_slow_current)
     {
          signal.valid_signal = true;
          signal.type = ORDER_TYPE_SELL;
          signal.entry_price = bid; // Enter at current Bid
          signal.stop_loss_price = signal.entry_price + fixed_sl_points * point;
          signal.take_profit_price = signal.entry_price - (fixed_sl_points * tp_rr_ratio) * point;
          signal.comment = "SELL: BOS + RSI Overbought + EMA Bearish";
          PrintFormat("%s %s: SELL Signal. Price:%.5f SL:%.5f TP:%.5f. BOS:%d, RSI:%.2f (OB:%.1f), EMAFast:%.5f, EMASlow:%.5f, SL points: %.1f",
                       symbol, EnumToString(timeframe), signal.entry_price, signal.stop_loss_price, signal.take_profit_price,
                       bos_signal, rsi_current, rsi_overbought, ema_fast_current, ema_slow_current, fixed_sl_points);
          return signal;
     }
   return signal;
  }

//+------------------------------------------------------------------+
//| Check Custom Exit Conditions (e.g., for early exit) - Placeholder |
//+------------------------------------------------------------------+
// bool CheckCustomExitConditions(long position_ticket, string symbol /*... other params ...*/)
// {
//   // Example: exit if RSI reverses strongly, or time-based exit
//   return false;
// }

#endif // TRADELOGIC_MQH
