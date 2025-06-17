#ifndef SMC_MQH
#define SMC_MQH

//+------------------------------------------------------------------+
//| Get the highest high value over a specified number of bars       |
//+------------------------------------------------------------------+
double GetHighestHigh(string symbol, ENUM_TIMEFRAMES timeframe, int period, int start_shift)
  {
   MqlRates rates[];
   if(CopyRates(symbol, timeframe, start_shift, period, rates) < period)
     {
      PrintFormat("Error copying rates for GetHighestHigh. Symbol: %s, Error: %d", symbol, GetLastError());
      return -1.0;
     }
   double max_high = 0;
   for(int i = 0; i < period; i++)
     {
      if(rates[i].high > max_high)
         max_high = rates[i].high;
     }
   return max_high;
  }

//+------------------------------------------------------------------+
//| Get the lowest low value over a specified number of bars         |
//+------------------------------------------------------------------+
double GetLowestLow(string symbol, ENUM_TIMEFRAMES timeframe, int period, int start_shift)
  {
   MqlRates rates[];
   if(CopyRates(symbol, timeframe, start_shift, period, rates) < period)
     {
      PrintFormat("Error copying rates for GetLowestLow. Symbol: %s, Error: %d", symbol, GetLastError());
      return -1.0; // Using -1.0 might be problematic if actual lows can be negative. Consider DBL_MAX
     }
   double min_low = DBL_MAX; // Initialize with a very large value
   for(int i = 0; i < period; i++)
     {
      if(rates[i].low < min_low)
         min_low = rates[i].low;
     }
   return min_low;
  }

//+------------------------------------------------------------------+
//| Check for Break of Structure (BOS)                               |
//| Returns: 1 for bullish BOS, -1 for bearish BOS, 0 for no BOS   |
//+------------------------------------------------------------------+
int CheckBOS(string symbol, ENUM_TIMEFRAMES timeframe, int swing_lookback_period, int confirmation_lookback)
  {
   // Get current price data (last closed bar)
   MqlRates current_rates[];
   if(CopyRates(symbol, timeframe, 1, confirmation_lookback, current_rates) < confirmation_lookback)
     {
      PrintFormat("Error copying current rates for CheckBOS. Symbol: %s, Error: %d", symbol, GetLastError());
      return 0;
     }

   // Determine the actual high and low over the confirmation_lookback period
   double confirmation_period_high = current_rates[0].high;
   double confirmation_period_low = current_rates[0].low;
   for(int i = 1; i < confirmation_lookback; i++)
   {
       if(current_rates[i].high > confirmation_period_high) confirmation_period_high = current_rates[i].high;
       if(current_rates[i].low < confirmation_period_low) confirmation_period_low = current_rates[i].low;
   }

   // Define the period for identifying the previous swing high/low
   // The swing point should be identified from bars prior to the confirmation candle(s)
   int swing_point_shift = confirmation_lookback + 0; // Start looking for swing point from bar immediately before confirmation period starts (e.g. if confirmation_lookback is 1, this is 1, if it's 3, this is 3)


   double previous_swing_high = GetHighestHigh(symbol, timeframe, swing_lookback_period, swing_point_shift);
   double previous_swing_low = GetLowestLow(symbol, timeframe, swing_lookback_period, swing_point_shift);

   if(previous_swing_high <= 0 || previous_swing_low <= 0) // Error in fetching swing points
    {
     // PrintFormat("Error fetching swing points for BOS. Prev Swing High: %f, Prev Swing Low: %f", previous_swing_high, previous_swing_low);
     return 0;
    }

   // Check for Bullish BOS
   // Current high breaks above the previous swing high
   if(confirmation_period_high > previous_swing_high)
     {
      PrintFormat("%s %s: Bullish BOS detected. Prev Swing High: %f, Confirmation Period High: %f",
                  symbol, EnumToString(timeframe), previous_swing_high, confirmation_period_high);
      return 1; // Bullish BOS
     }

   // Check for Bearish BOS
   // Current low breaks below the previous swing low
   if(confirmation_period_low < previous_swing_low)
     {
      PrintFormat("%s %s: Bearish BOS detected. Prev Swing Low: %f, Confirmation Period Low: %f",
                  symbol, EnumToString(timeframe), previous_swing_low, confirmation_period_low);
      return -1; // Bearish BOS
     }

   return 0; // No BOS
  }

// Structure to hold Fair Value Gap information
struct FVGInfo
  {
   bool   detected;         // True if a valid FVG is identified
   double top_level;        // Top price level of the FVG
   double bottom_level;     // Bottom price level of the FVG
   bool   is_bullish_fvg;   // True for bullish FVG (price expected to find support), false for bearish (resistance)
   datetime bar_time;       // Timestamp of the middle bar (bar 2) that creates the FVG
   bool   is_mitigated;     // Has this FVG been touched/mitigated by subsequent price action?
   // Add more details if needed, e.g., index of the bar
  };

//+------------------------------------------------------------------+
//| Identify Fair Value Gaps (FVGs)                                  |
//+------------------------------------------------------------------+
// Returns the number of FVGs found and populates the fvgs_array
int IdentifyFVG(string symbol, ENUM_TIMEFRAMES timeframe, int lookback_bars, double min_fvg_size_points, FVGInfo &fvgs_array[])
  {
   ArrayFree(fvgs_array); // Clear the array before populating

   MqlRates rates[];
   // Request lookback_bars + 2 to ensure enough data for the 3-bar patterns
   // e.g., if lookback_bars = 50, we need bars 0 to 51 (total 52 bars)
   // rates[i], rates[i-1], rates[i-2]. If i_max = lookback_bars+1, then rates[lookback_bars+1], rates[lookback_bars], rates[lookback_bars-1]
   // So, copy 'lookback_bars + 2' bars.
   if(CopyRates(symbol, timeframe, 0, lookback_bars + 2, rates) < lookback_bars + 2)
     {
      PrintFormat("Error copying rates for IdentifyFVG. Symbol: %s, TF: %s, Count: %d, Error: %d",
                  symbol, EnumToString(timeframe), lookback_bars + 2, GetLastError());
      return 0;
     }
   ArraySetAsSeries(rates, true); // rates[0] is the most recent bar (potentially current forming bar)

   int fvgs_found = 0;
   // Loop considers 3 bars at a time: C1 (older), C2 (middle), C3 (newer).
   // FVG is between C1 and C3, around C2.
   // The most recent FVG is formed by C1=rates[2], C2=rates[1], C3=rates[0] (if rates[0] is a closed bar).
   // We iterate from oldest possible C1 up to the point where C3 is rates[0].
   // So, 'i' represents the index of C1. Loop from 'lookback_bars + 1' down to 2.
   for(int i = lookback_bars + 1; i >= 2; i--)
     {
      // C1: rates[i]
      // C2: rates[i-1] (FVG occurs around this bar)
      // C3: rates[i-2]

      double c1_high = rates[i].high;
      double c1_low  = rates[i].low;
      // Middle candle (rates[i-1]) is not directly used for FVG levels, but its presence creates the gap.
      double c3_high = rates[i-2].high;
      double c3_low  = rates[i-2].low;
      datetime fvg_bar_time = rates[i-1].time; // FVG is associated with the middle bar's time

      FVGInfo current_fvg;
      current_fvg.detected = false;
      current_fvg.is_mitigated = false; // Default state

      double point_val = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point_val == 0) { // Avoid division by zero if SYMBOL_POINT is invalid
          PrintFormat("Invalid SYMBOL_POINT for %s", symbol);
          continue;
      }

      // Check for Bullish FVG: Low of C3 is above High of C1
      if(c3_low > c1_high)
        {
         double fvg_size_actual = c3_low - c1_high;
         if(fvg_size_actual / point_val >= min_fvg_size_points)
           {
            current_fvg.detected = true;
            current_fvg.is_bullish_fvg = true;
            current_fvg.top_level = c3_low;       // Top of the bullish FVG zone
            current_fvg.bottom_level = c1_high;   // Bottom of the bullish FVG zone
            current_fvg.bar_time = fvg_bar_time;

            ArrayResize(fvgs_array, fvgs_found + 1);
            fvgs_array[fvgs_found] = current_fvg;
            fvgs_found++;
           }
        }
      // Check for Bearish FVG: High of C3 is below Low of C1
      else if(c3_high < c1_low)
        {
         double fvg_size_actual = c1_low - c3_high;
         if(fvg_size_actual / point_val >= min_fvg_size_points)
           {
            current_fvg.detected = true;
            current_fvg.is_bullish_fvg = false;
            current_fvg.top_level = c1_low;       // Top of the bearish FVG zone
            current_fvg.bottom_level = c3_high;   // Bottom of the bearish FVG zone
            current_fvg.bar_time = fvg_bar_time;

            ArrayResize(fvgs_array, fvgs_found + 1);
            fvgs_array[fvgs_found] = current_fvg;
            fvgs_found++;
           }
        }
     }
   // FVGs are currently added from oldest to newest based on C1's index.
   // If newest FVGs (by bar_time) are preferred first, ArrayReverse can be used after loop.
   // ArrayReverse(fvgs_array); // To have newest FVGs at index 0
   return fvgs_found;
  }

// Structure to hold Order Block information
struct OrderBlockInfo
  {
   bool   detected;         // True if a valid OB is identified
   double top_level;        // Top price level of the OB (e.g., high of the candle)
   double bottom_level;     // Bottom price level of the OB (e.g., low of the candle)
   double open_price;       // Open price of the OB candle
   double close_price;      // Close price of the OB candle
   bool   is_bullish_ob;    // True for bullish OB (price expected to find support), false for bearish (resistance)
   datetime bar_time;       // Timestamp of the OB candle
   bool   is_mitigated;     // Has this OB been touched/mitigated?
   bool   bos_confirmed;    // Did this OB lead to a Break of Structure?
   // Add more details if needed, e.g., index of the bar
  };

//+------------------------------------------------------------------+
//| Identify Order Blocks (OBs)                                      |
//+------------------------------------------------------------------+
// Returns the number of OBs found and populates the obs_array
int IdentifyOrderBlocks(string symbol, ENUM_TIMEFRAMES timeframe,
                          int lookback_bars,          // How far back to look for OB candidates
                          double min_ob_body_percent, // Min body size relative to candle range (0-100)
                          int bos_validation_lookforward, // How many bars after OB to check for BOS
                          double bos_min_move_points, // Min points for the move after OB to be considered significant for BOS
                          OrderBlockInfo &obs_array[])
  {
   ArrayFree(obs_array);
   MqlRates rates[];
   // Total bars needed = lookback_bars (for the OB candidates themselves) + bos_validation_lookforward (for confirming BOS after the OB)
   // Add a small buffer like +5 just in case, though strict calculation is lookback_bars + bos_validation_lookforward
   int rates_to_copy = lookback_bars + bos_validation_lookforward + 5;
   if(CopyRates(symbol, timeframe, 0, rates_to_copy, rates) < rates_to_copy)
     {
      PrintFormat("Error copying rates for IdentifyOrderBlocks. Symbol: %s, Count: %d, Error: %d", symbol, rates_to_copy, GetLastError());
      return 0;
     }
   ArraySetAsSeries(rates, true); // rates[0] is current/last closed bar

   int obs_found = 0;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point == 0) {
       PrintFormat("Invalid SYMBOL_POINT for %s in IdentifyOrderBlocks", symbol);
       return 0;
   }

   // Iterate from 'lookback_bars -1 + bos_validation_lookforward' down to 'bos_validation_lookforward'
   // This ensures that rates[i] is the OB candidate, and we have 'bos_validation_lookforward' bars after it (towards index 0).
   // Example: lookback_bars = 50, bos_validation_lookforward = 5
   // Oldest OB candidate: rates[50-1+5] = rates[54]
   // Newest OB candidate: rates[5] (so rates[4]...rates[0] are available for BOS check)
   for(int i = lookback_bars -1 + bos_validation_lookforward; i >= bos_validation_lookforward; i--)
     {
      MqlRates ob_candidate_bar = rates[i];
      double body_size_abs = MathAbs(ob_candidate_bar.open - ob_candidate_bar.close);
      double range = ob_candidate_bar.high - ob_candidate_bar.low;

      if(range == 0) continue; // Avoid division by zero for doji-like candles

      double body_percent = (body_size_abs / range) * 100.0;

      if(min_ob_body_percent > 0 && body_percent < min_ob_body_percent)
        {
         continue;
        }

      OrderBlockInfo current_ob;
      current_ob.detected = false; // Will be set to true if all conditions met
      current_ob.is_mitigated = false; // Default
      current_ob.bos_confirmed = false; // Default
      current_ob.bar_time = ob_candidate_bar.time;
      current_ob.top_level = ob_candidate_bar.high;
      current_ob.bottom_level = ob_candidate_bar.low;
      current_ob.open_price = ob_candidate_bar.open;
      current_ob.close_price = ob_candidate_bar.close;

      bool potential_ob_identified = false;

      // Potential Bullish OB: A down candle (close < open)
      if(ob_candidate_bar.close < ob_candidate_bar.open)
        {
         current_ob.is_bullish_ob = true;
         potential_ob_identified = true;
         // Check for an upward BOS after this candle
         for(int k = 1; k <= bos_validation_lookforward; k++)
           {
            if(i-k < 0) break; // Should not happen with loop bounds, but good for safety
            // If any of the subsequent 'k' bars' high breaks above the OB candidate's high by a minimum amount
            if(rates[i-k].high > ob_candidate_bar.high && (rates[i-k].high - ob_candidate_bar.high) / point >= bos_min_move_points)
              {
               current_ob.bos_confirmed = true;
               break;
              }
           }
        }
      // Potential Bearish OB: An up candle (close > open)
      else if(ob_candidate_bar.close > ob_candidate_bar.open)
        {
         current_ob.is_bullish_ob = false;
         potential_ob_identified = true;
         // Check for a downward BOS after this candle
         for(int k = 1; k <= bos_validation_lookforward; k++)
           {
            if(i-k < 0) break;
            // If any of the subsequent 'k' bars' low breaks below the OB candidate's low by a minimum amount
            if(rates[i-k].low < ob_candidate_bar.low && (ob_candidate_bar.low - rates[i-k].low) / point >= bos_min_move_points)
              {
               current_ob.bos_confirmed = true;
               break;
              }
           }
        }

      if(potential_ob_identified && current_ob.bos_confirmed)
        {
         current_ob.detected = true;
         ArrayResize(obs_array, obs_found + 1);
         obs_array[obs_found] = current_ob;
         obs_found++;
        }
     }
   // OBs are added from oldest to newest based on OB candidate bar time.
   // If newest OBs are preferred at index 0, reverse the array.
   // ArrayReverse(obs_array);
   return obs_found;
  }

//+------------------------------------------------------------------+
//| Check for Engulfing Candle Pattern                               |
//| bar_shift: The shift of the engulfing candle (e.g., 1 for last closed bar from current) |
//| is_bullish_engulfing_expected: True to check for bullish engulfing, false for bearish |
//+------------------------------------------------------------------+
bool IsEngulfingPattern(string symbol, ENUM_TIMEFRAMES timeframe, int bar_shift, bool is_bullish_engulfing_expected)
  {
   MqlRates rates[]; // Need 2 bars: engulfing and engulfed
   // CopyRates: bar_shift is the starting bar index from present towards past.
   // Count = 2 means we get bars at 'bar_shift' and 'bar_shift+1'.
   if(CopyRates(symbol, timeframe, bar_shift, 2, rates) < 2)
     {
      PrintFormat("Error copying rates for IsEngulfingPattern. Symbol: %s, Shift: %d, Error: %d", symbol, bar_shift, GetLastError());
      return false;
     }
   ArraySetAsSeries(rates, true); // rates[0] is the newest (bar at 'bar_shift')
                                  // rates[1] is the older (bar at 'bar_shift+1')

   MqlRates engulfing_candle = rates[0]; // This is the bar at 'bar_shift' (e.g. last closed if bar_shift=1)
   MqlRates engulfed_candle = rates[1];  // This is the bar at 'bar_shift+1' (e.g. second last closed if bar_shift=1)

   bool pattern_detected = false;

   if(is_bullish_engulfing_expected)
     {
      // Bullish Engulfing:
      // 1. Engulfing candle (current) is bullish (close > open).
      // 2. Engulfed candle (previous) is bearish (close < open).
      // 3. Engulfing candle's body completely engulfs the previous candle's body.
      if(engulfing_candle.close > engulfing_candle.open &&      // Engulfing is bullish
         engulfed_candle.close < engulfed_candle.open &&        // Engulfed is bearish
         engulfing_candle.close > engulfed_candle.open &&       // Engulfing close is above engulfed open
         engulfing_candle.open < engulfed_candle.close)         // Engulfing open is below engulfed close
        {
         pattern_detected = true;
        }
     }
   else // Bearish Engulfing Expected
     {
      // Bearish Engulfing:
      // 1. Engulfing candle (current) is bearish (close < open).
      // 2. Engulfed candle (previous) is bullish (close > open).
      // 3. Engulfing candle's body completely engulfs the previous candle's body.
      if(engulfing_candle.close < engulfing_candle.open &&      // Engulfing is bearish
         engulfed_candle.close > engulfed_candle.open &&        // Engulfed is bullish
         engulfing_candle.close < engulfed_candle.open &&       // Engulfing close is below engulfed open
         engulfing_candle.open > engulfed_candle.close)         // Engulfing open is above engulfed close
        {
         pattern_detected = true;
        }
     }

   // Debug print (optional, can be very verbose)
   /*
   if(pattern_detected)
     {
      PrintFormat("%s Engulfing Pattern on %s. Engulfing Bar Time: %s (Shift: %d). Engulfing: O=%.5f H=%.5f L=%.5f C=%.5f. Engulfed: O=%.5f H=%.5f L=%.5f C=%.5f",
         (is_bullish_engulfing_expected ? "Bullish" : "Bearish"), symbol, TimeToString(engulfing_candle.time), bar_shift,
         engulfing_candle.open, engulfing_candle.high, engulfing_candle.low, engulfing_candle.close,
         engulfed_candle.open, engulfed_candle.high, engulfed_candle.low, engulfed_candle.close);
     }
   */
   return pattern_detected;
  }

#endif // SMC_MQH
