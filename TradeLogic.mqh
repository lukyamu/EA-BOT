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
EntrySignal CheckEntryConditions(
    string symbol, ENUM_TIMEFRAMES timeframe,
    // EMA
    int ema_fast_period, int ema_slow_period,
    // RSI
    int rsi_period, double rsi_overbought, double rsi_oversold,
    // BOS
    int bos_swing_lookback, int bos_confirmation_lookback,
    // FVG
    bool enable_fvg_detection, int fvg_lookback_period, double min_fvg_size_points,
    // OB
    bool enable_ob_detection, int ob_lookback_period, double min_ob_body_percent,
    int ob_bos_validation_lookforward, double ob_bos_min_move_points,
    // Engulfing
    bool enable_engulfing_confirmation,
    // Trade Params
    double tp_rr_ratio, double initial_fixed_sl_pips, // Renamed for clarity
    double sl_buffer_points
)
  {
    EntrySignal signal;
    signal.valid_signal = false;

    // 0. Basic Price Data
    MqlRates current_candle_data[2]; // rates[0] = last closed (shift 1), rates[1] = second to last (shift 2)
    if(CopyRates(symbol, timeframe, 1, 2, current_candle_data) < 2) {
        PrintFormat("Error copying rates for entry conditions on %s", symbol);
        return signal;
    }
    ArraySetAsSeries(current_candle_data, true); // current_candle_data[0] is shift 1 (last closed)

    double current_close = current_candle_data[0].close;
    double current_high = current_candle_data[0].high;
    double current_low = current_candle_data[0].low;
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

    if(ask == 0 || bid == 0 || point == 0) {
        PrintFormat("Invalid market prices for %s. Ask:%.5f, Bid:%.5f, Point:%.5f", symbol, ask, bid, point);
        return signal;
    }

    // 1. Check BOS
    int bos_signal = CheckBOS(symbol, timeframe, bos_swing_lookback, bos_confirmation_lookback);
    if(bos_signal == 0) {
        // PrintFormat("No BOS detected for %s", symbol); // Can be verbose
        return signal;
    }

    // 2. Calculate Indicators (RSI, EMA)
    double ema_fast_current = GetEMA(symbol, timeframe, ema_fast_period, 1);
    double ema_slow_current = GetEMA(symbol, timeframe, ema_slow_period, 1);
    double rsi_current = GetRSI(symbol, timeframe, rsi_period, 1);

    if(ema_fast_current < 0 || ema_slow_current < 0 || rsi_current < 0) { // Error in indicator calc
     PrintFormat("Error calculating indicators for %s. EMA_Fast: %.5f, EMA_Slow: %.5f, RSI: %.2f",
                 symbol, ema_fast_current, ema_slow_current, rsi_current);
     return signal;
    }

    // Determine trade direction based on BOS
    bool is_buy_scenario = (bos_signal == 1);
    bool is_sell_scenario = (bos_signal == -1);

    // Filter based on EMA direction
    if(is_buy_scenario && ema_fast_current <= ema_slow_current) {
        // PrintFormat("EMA not aligned for BUY on %s. Fast: %.5f, Slow: %.5f", symbol, ema_fast_current, ema_slow_current);
        return signal;
    }
    if(is_sell_scenario && ema_fast_current >= ema_slow_current) {
        // PrintFormat("EMA not aligned for SELL on %s. Fast: %.5f, Slow: %.5f", symbol, ema_fast_current, ema_slow_current);
        return signal;
    }

    // Filter based on RSI (Original logic: extremes)
    if(is_buy_scenario && rsi_current >= rsi_oversold) { // Expect RSI < OS for buy
        // PrintFormat("RSI not oversold for BUY on %s. RSI: %.2f, OS Level: %.2f", symbol, rsi_current, rsi_oversold);
        return signal;
    }
    if(is_sell_scenario && rsi_current <= rsi_overbought) { // Expect RSI > OB for sell
        // PrintFormat("RSI not overbought for SELL on %s. RSI: %.2f, OB Level: %.2f", symbol, rsi_current, rsi_overbought);
        return signal;
    }

    // --- FVG/OB Zone Identification & Retest ---
    FVGInfo fvgs[];
    OrderBlockInfo obs[];
    int fvg_count = 0;
    int ob_count = 0;

    if(enable_fvg_detection) {
        fvg_count = IdentifyFVG(symbol, timeframe, fvg_lookback_period, min_fvg_size_points, fvgs);
        // ArrayReverse(fvgs); // Process newest FVGs first if desired
    }
    if(enable_ob_detection) {
        ob_count = IdentifyOrderBlocks(symbol, timeframe, ob_lookback_period, min_ob_body_percent,
                                       ob_bos_validation_lookforward, ob_bos_min_move_points, obs);
        // ArrayReverse(obs); // Process newest OBs first
    }

    // Iterate identified zones (FVGs then OBs) to find a retest and engulfing
    for(int zone_type_iter = 0; zone_type_iter < 2; zone_type_iter++)
    {
        if(zone_type_iter == 0 && (!enable_fvg_detection || fvg_count == 0)) continue;
        if(zone_type_iter == 1 && (!enable_ob_detection || ob_count == 0)) continue;

        int current_zone_count = (zone_type_iter == 0) ? fvg_count : ob_count;

        for(int i = 0; i < current_zone_count; i++)
        {
            bool zone_is_bullish_type = false; // Type of zone (bullish FVG or bullish OB)
            double zone_top_level = 0, zone_bottom_level = 0;
            // datetime zone_bar_time = 0; // For checking freshness if needed

            if(zone_type_iter == 0) // FVG
            {
                if (!fvgs[i].detected) continue;
                zone_is_bullish_type = fvgs[i].is_bullish_fvg;
                zone_top_level = fvgs[i].top_level;
                zone_bottom_level = fvgs[i].bottom_level;
                // zone_bar_time = fvgs[i].bar_time;
            }
            else // Order Block
            {
                if (!obs[i].detected) continue;
                zone_is_bullish_type = obs[i].is_bullish_ob;
                zone_top_level = obs[i].top_level;       // OB high
                zone_bottom_level = obs[i].bottom_level; // OB low
                // zone_bar_time = obs[i].bar_time;
            }

            bool retest_criteria_met = false;
            // For a buy scenario (bullish BOS), we look for retest of a bullish FVG or bullish OB.
            if(is_buy_scenario && zone_is_bullish_type)
            {
                // Last closed candle's low (current_low) dipped into the zone (defined by its bottom and top).
                // Or previous candle dipped and current is an engulfing.
                if(current_low <= zone_top_level && current_low >= zone_bottom_level) { // current candle low tested the zone
                     retest_criteria_met = true;
                }
            }
            // For a sell scenario (bearish BOS), we look for retest of a bearish FVG or bearish OB.
            else if(is_sell_scenario && !zone_is_bullish_type)
            {
                // Last closed candle's high (current_high) tested the zone.
                if(current_high >= zone_bottom_level && current_high <= zone_top_level) {
                    retest_criteria_met = true;
                }
            }

            if(retest_criteria_met)
            {
                bool engulfing_passed = false;
                if(enable_engulfing_confirmation)
                {
                    // Check engulfing on the last closed bar (current_candle_data[0], which has index 0 here due to ArraySetAsSeries and CopyRates shift 1)
                    // The IsEngulfingPattern expects bar_shift relative to current forming bar. So shift 1 is correct for current_candle_data[0].
                    engulfing_passed = IsEngulfingPattern(symbol, timeframe, 1, is_buy_scenario);
                }
                else
                {
                    engulfing_passed = true; // Skip if disabled
                }

                if(engulfing_passed)
                {
                    signal.valid_signal = true;
                    signal.type = is_buy_scenario ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

                    // --- Stop Loss Logic Refinement ---
                    double proposed_sl_price = 0;
                    // point is already available

                    if(is_buy_scenario)
                    {
                        signal.entry_price = ask; // Ensure entry price is set before SL calc
                        double engulfing_low = current_candle_data[0].low;

                        if(zone_type_iter == 1 && obs[i].detected) // OB was the trigger zone
                        {
                            proposed_sl_price = obs[i].bottom_level;
                            if(enable_engulfing_confirmation && engulfing_passed)
                            {
                                proposed_sl_price = MathMin(proposed_sl_price, engulfing_low);
                            }
                        }
                        else if (zone_type_iter == 0 && fvgs[i].detected) // FVG was the trigger zone
                        {
                            if(enable_engulfing_confirmation && engulfing_passed) {
                                proposed_sl_price = engulfing_low;
                            } else { // FVG retest without engulfing (or engulfing disabled)
                                proposed_sl_price = fvgs[i].bottom_level;
                            }
                        }

                        if(proposed_sl_price == 0 && initial_fixed_sl_pips > 0) { // Fallback if no zone SL logic hit
                             proposed_sl_price = signal.entry_price - initial_fixed_sl_pips * point;
                        } else if (proposed_sl_price == 0) { // Absolute fallback if fixed SL is also 0 (should not happen with good inputs)
                             proposed_sl_price = signal.entry_price - 10 * point; // Default 10 points
                        }


                        if (proposed_sl_price != 0) proposed_sl_price -= sl_buffer_points * point;

                        double min_sl_value_from_fixed = signal.entry_price - initial_fixed_sl_pips * point;
                        if(initial_fixed_sl_pips > 0 && (signal.entry_price - proposed_sl_price) < (initial_fixed_sl_pips * point * 0.95) && proposed_sl_price != 0) {
                             proposed_sl_price = min_sl_value_from_fixed;
                        }
                        signal.stop_loss_price = proposed_sl_price;
                    }
                    else // Sell Scenario
                    {
                        signal.entry_price = bid; // Ensure entry price is set
                        double engulfing_high = current_candle_data[0].high;

                        if(zone_type_iter == 1 && obs[i].detected) // OB was the trigger zone
                        {
                            proposed_sl_price = obs[i].top_level;
                            if(enable_engulfing_confirmation && engulfing_passed)
                            {
                                proposed_sl_price = MathMax(proposed_sl_price, engulfing_high);
                            }
                        }
                        else if (zone_type_iter == 0 && fvgs[i].detected) // FVG was the trigger zone
                        {
                            if(enable_engulfing_confirmation && engulfing_passed) {
                                proposed_sl_price = engulfing_high;
                            } else {
                                 proposed_sl_price = fvgs[i].top_level;
                            }
                        }

                        if(proposed_sl_price == 0 && initial_fixed_sl_pips > 0) {
                            proposed_sl_price = signal.entry_price + initial_fixed_sl_pips * point;
                        } else if (proposed_sl_price == 0) {
                             proposed_sl_price = signal.entry_price + 10 * point; // Default 10 points
                        }

                        if (proposed_sl_price != 0) proposed_sl_price += sl_buffer_points * point;

                        double min_sl_value_from_fixed = signal.entry_price + initial_fixed_sl_pips * point;
                        if(initial_fixed_sl_pips > 0 && (proposed_sl_price - signal.entry_price) < (initial_fixed_sl_pips * point * 0.95) && proposed_sl_price != 0) {
                             proposed_sl_price = min_sl_value_from_fixed;
                        }
                        signal.stop_loss_price = proposed_sl_price;
                    }

                    if (is_buy_scenario && (signal.stop_loss_price == 0 || signal.stop_loss_price >= signal.entry_price)) {
                        signal.stop_loss_price = signal.entry_price - (initial_fixed_sl_pips > 0 ? initial_fixed_sl_pips : 10.0) * point - (sl_buffer_points * point);
                    } else if (!is_buy_scenario && (signal.stop_loss_price == 0 || signal.stop_loss_price <= signal.entry_price)) {
                        signal.stop_loss_price = signal.entry_price + (initial_fixed_sl_pips > 0 ? initial_fixed_sl_pips : 10.0) * point + (sl_buffer_points * point);
                    }

                    double sl_pips_for_tp_calc = MathAbs(signal.entry_price - signal.stop_loss_price) / point;
                    if(sl_pips_for_tp_calc <= 0) {
                        sl_pips_for_tp_calc = initial_fixed_sl_pips > 0 ? initial_fixed_sl_pips : 10.0;
                        if (is_buy_scenario) signal.stop_loss_price = signal.entry_price - sl_pips_for_tp_calc * point;
                        else signal.stop_loss_price = signal.entry_price + sl_pips_for_tp_calc * point;
                         PrintFormat("SL recalc fallback used for TP calc on %s. SL pips for TP: %.1f", symbol, sl_pips_for_tp_calc);
                    }

                    signal.take_profit_price = is_buy_scenario ?
                        (signal.entry_price + sl_pips_for_tp_calc * tp_rr_ratio * point) :
                        (signal.entry_price - sl_pips_for_tp_calc * tp_rr_ratio * point);

                    signal.comment = StringFormat("%s: BOS+%s+%s Engulf.RSI:%.1f SLP:%.1f",
                                       (is_buy_scenario ? "BUY" : "SELL"),
                                       (zone_type_iter==0 ? "FVG" : "OB"),
                                       (enable_engulfing_confirmation ? "" : "NoEng."), rsi_current);

                    PrintFormat("%s %s: %s Signal. Zone Retest: %s. Engulf: %s. Price:%.5f SL:%.5f TP:%.5f. Comment: %s",
                               symbol, EnumToString(timeframe), (is_buy_scenario ? "BUY" : "SELL"),
                               (zone_type_iter==0 ? "FVG" : "OB"), (engulfing_passed ? "Yes" : "No/Disabled"),
                               signal.entry_price, signal.stop_loss_price, signal.take_profit_price, signal.comment);
                    return signal; // Signal found
                }
            }
        }
    } // End of zone type iteration (FVG/OB)
    return signal; // No valid signal found
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
