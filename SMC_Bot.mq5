//+------------------------------------------------------------------+
//|                                                      SMC_Bot.mq5 |
//|                                              AI Generated EA |
//|                                     mailto:your_email@example.com |
//+------------------------------------------------------------------+
#property copyright "AI Generated EA"
#property link      "mailto:your_email@example.com"
#property version   "1.00"
#property strict
#property description "Smart Money Concepts Bot with RSI and EMA confirmation."

#include "Indicators.mqh"
#include "SMC.mqh"
#include "TradeLogic.mqh"
#include "TradeExecution.mqh"
#include "RiskManagement.mqh"
#include "Telegram.mqh"
#include "Logging.mqh"

//--- General Settings
input ulong MagicNumber = 12345; // EA Magic Number
input int Slippage = 3;          // Slippage in points

//--- Risk Management
input double Risk_Percent = 1.0; // Risk per trade as a percentage of account balance
input double TP_Risk_Reward_Ratio = 2.0; // Take Profit Risk to Reward Ratio (e.g., 2.0 for 1:2)
input double Partial_Close_RR_Ratio = 1.0; // RR ratio for partial close (e.g., 1.0 for 1:1)
input double Partial_Close_Percent = 60.0; // Percentage of position to close at Partial_Close_RR_Ratio
input int    Daily_Max_Trades = 3;       // Maximum trades per day
input double Daily_Max_Drawdown_Percent = 3.0; // Maximum daily drawdown percentage

//--- EMA Settings
input int EMA_Fast_Period = 20;    // Fast EMA Period
input int EMA_Slow_Period = 50;    // Slow EMA Period

//--- RSI Settings
input int RSI_Period = 14;         // RSI Period
input double RSI_Overbought = 70.0; // RSI Overbought level
input double RSI_Oversold = 30.0;   // RSI Oversold level

//--- SMC Settings
input int BOS_Swing_Lookback_Period = 20; // Period to identify previous swing high/low for BOS
input int BOS_Confirmation_Lookback = 1;  // Number of recent bars to confirm BOS

//--- Trade Logic Settings
input double Fixed_SL_Pips = 15.0; // Fixed Stop Loss in Pips/Points (e.g. 15 for XAUUSD means $0.15 if point size is 0.01 and 1 pip = 1 point, or $1.5 if 1 pip = 10 points). User must verify for their symbol & broker.

//--- Timeframe & Symbols (Note: Symbol list will be handled in OnTick logic later)
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5; // Trading timeframe

//--- Telegram Alerts
input string Telegram_Token = "";       // Telegram Bot Token
input string Telegram_ChatID = "";      // Telegram Chat ID
input bool   Enable_Telegram_Alerts = true; // Enable/Disable Telegram alerts

//--- Logging
input bool Enable_Trade_Logging = true; // Enable/Disable trade logging to CSV

//--- Symbol Settings
input string Symbols_To_Trade = "XAUUSD,EURUSD,BTCUSD,GER40,CRASH100"; // Comma-separated list of symbols

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   PrintFormat("%s: Initialized. Version %s", MQLInfoString(MQL_PROGRAM_NAME), MQLInfoString(MQL_PROGRAM_VERSION));
   InitLogFile(Enable_Trade_Logging, "SMC_TradeLog", MagicNumber);

   // Parse Symbols_To_Trade and select them in MarketWatch
   string symbols_array[];
   ushort separator = StringGetCharacter(",", 0);
   StringSplit(Symbols_To_Trade, separator, symbols_array);
   for(int i = 0; i < ArraySize(symbols_array); i++) {
      string sym_to_select = symbols_array[i];
      Trim(sym_to_select); // Use the Trim function defined below
      if(sym_to_select != "") {
         if(!SymbolExist(sym_to_select, false)) { // Check if symbol exists
             PrintFormat("Symbol %s does not exist. Please check input Symbols_To_Trade.", sym_to_select);
         } else if(!SymbolSelect(sym_to_select, true)) { // Attempt to select
             PrintFormat("Failed to select symbol %s in MarketWatch. Error: %d", sym_to_select, GetLastError());
         } else {
             PrintFormat("Symbol %s selected in MarketWatch.", sym_to_select);
         }
      }
   }

   // Further initializations for indicators, etc., will be added later
   if(Enable_Trade_Logging){
       LogEvent(TimeCurrent(), "EA_INIT", MQLInfoString(MQL_PROGRAM_NAME) + " Initialized. Version " + MQLInfoString(MQL_PROGRAM_VERSION), Symbol(), MagicNumber, Enable_Trade_Logging);
   }
   if(Enable_Telegram_Alerts && Telegram_Token != "" && Telegram_ChatID != ""){
       SendTelegramMessage(Telegram_Token, Telegram_ChatID, MQLInfoString(MQL_PROGRAM_NAME) + " Initialized. Version " + MQLInfoString(MQL_PROGRAM_VERSION) + " on " + Symbol() + " (and other selected symbols).", Enable_Telegram_Alerts);
   }
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   PrintFormat("%s: Deinitialized. Reason code: %d", MQLInfoString(MQL_PROGRAM_NAME), reason);
   if(Enable_Trade_Logging){
       LogEvent(TimeCurrent(), "EA_DEINIT", MQLInfoString(MQL_PROGRAM_NAME) + " Deinitialized. Reason: " + IntegerToString(reason), Symbol(), MagicNumber, Enable_Trade_Logging);
   }
   if(Enable_Telegram_Alerts && Telegram_Token != "" && Telegram_ChatID != ""){
       SendTelegramMessage(Telegram_Token, Telegram_ChatID, MQLInfoString(MQL_PROGRAM_NAME) + " Deinitialized on " + Symbol() + ". Reason: " + IntegerToString(reason), Enable_Telegram_Alerts);
   }
   DeinitLogFile(Enable_Trade_Logging);
   // Clean up resources if any
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 0. Check if trading is allowed globally (e.g., by Expert Advisor settings button)
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !IsExpertEnabled())
     {
      return;
     }

   // 1. Perform Risk Management Checks (Daily Limits)
   bool is_dd_hit = false;
   bool is_trade_limit_hit = false;
   if(!CheckTradingLimits(MagicNumber, Daily_Max_Trades, Daily_Max_Drawdown_Percent, is_dd_hit, is_trade_limit_hit))
     {
      // Optional: Log this state or send one-time alert
      static datetime last_risk_alert_time = 0;
      if(TimeCurrent() - last_risk_alert_time > 3600) { // Alert once per hour if still limited
          string limit_reason = (is_dd_hit ? "DD limit" : "") + (is_trade_limit_hit ? (is_dd_hit ? " & Trade limit" : "Trade limit") : "");
          LogEvent(TimeCurrent(), "RiskLimitHit", "Trading paused due to: " + limit_reason, "", MagicNumber, Enable_Trade_Logging);
          SendTelegramMessage(Telegram_Token, Telegram_ChatID, MQLInfoString(MQL_PROGRAM_NAME) + ": Trading paused due to " + limit_reason, Enable_Telegram_Alerts);
          last_risk_alert_time = TimeCurrent();
      }
      return;
     }

   // 2. Parse Symbols_To_Trade input string
   string symbols_array[];
   ushort separator = StringGetCharacter(",", 0);
   StringSplit(Symbols_To_Trade, separator, symbols_array);

   // 3. Iterate through each symbol
   for(int i = 0; i < ArraySize(symbols_array); i++)
     {
      string current_symbol = symbols_array[i];
      Trim(current_symbol);
      if(current_symbol == "") continue;

      if(!SymbolSelect(current_symbol, true))
      {
         PrintFormat("Symbol %s is not selected in MarketWatch or not available. Skipping. (OnTick)", current_symbol);
         continue;
      }
      MqlTick latest_tick;
      if(!SymbolInfoTick(current_symbol, latest_tick))
      {
          PrintFormat("Could not get latest tick for %s. Skipping.", current_symbol);
          continue;
      }

      // 4. Trade Management for existing positions on this symbol
      for(int j = PositionsTotal() - 1; j >= 0; j--)
        {
         ulong position_ticket = PositionGetTicket(j);
         if(PositionGetString(POSITION_SYMBOL) == current_symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
           {
            double position_open_price = PositionGetDouble(POSITION_OPEN_PRICE);
            double position_volume = PositionGetDouble(POSITION_VOLUME);
            ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double current_sl = PositionGetDouble(POSITION_SL);
            double current_tp = PositionGetDouble(POSITION_TP);
            double point_value = SymbolInfoDouble(current_symbol, SYMBOL_POINT);
            double initial_sl_pips_as_points = Fixed_SL_Pips; // Assuming Fixed_SL_Pips is in points

            // --- Partial Close at 1R ---
            // Check if position has already been partially closed (e.g. by checking a comment or stored state)
            // For simplicity, we'll assume it can only happen once. A robust solution needs better state management.
            // This example does not implement a perfect "only once" check for partial close without external state.
            // It will attempt partial close if conditions are met and volume allows.
            if(Partial_Close_Percent > 0 && Partial_Close_Percent < 100 && Partial_Close_RR_Ratio > 0)
              {
               double target_profit_price_for_partial_close = 0;
               if(position_type == POSITION_TYPE_BUY)
                 target_profit_price_for_partial_close = position_open_price + initial_sl_pips_as_points * Partial_Close_RR_Ratio * point_value;
               else
                 target_profit_price_for_partial_close = position_open_price - initial_sl_pips_as_points * Partial_Close_RR_Ratio * point_value;

               bool take_partial_profit = false;
               if(position_type == POSITION_TYPE_BUY && latest_tick.bid >= target_profit_price_for_partial_close)
                 take_partial_profit = true;
               else if(position_type == POSITION_TYPE_SELL && latest_tick.ask <= target_profit_price_for_partial_close)
                 take_partial_profit = true;

               // Check if remaining volume after partial close would be >= min_lot
               double volume_to_close = NormalizeDouble(PositionGetDouble(POSITION_VOLUME_INITIAL) * (Partial_Close_Percent / 100.0), (int)SymbolInfoInteger(current_symbol, SYMBOL_VOLUME_MIN_DIGITS));
               double min_vol = SymbolInfoDouble(current_symbol, SYMBOL_VOLUME_MIN);
               if(volume_to_close < min_vol) volume_to_close = min_vol; // Ensure we try to close at least min_vol

               if(take_partial_profit && (position_volume - volume_to_close >= min_vol || position_volume - volume_to_close == 0) && volume_to_close > 0 && volume_to_close < position_volume)
                 {
                  string close_comment = StringFormat("Partial Close at ~%.1fR (%.0f%%)", Partial_Close_RR_Ratio, Partial_Close_Percent);
                  if(ClosePositionByTicket(position_ticket, volume_to_close, close_comment))
                    {
                     string alert_msg = StringFormat("PARTIAL CLOSE: %s %s %.2f lots. %s",
                                                     EnumToString(position_type), current_symbol, volume_to_close, close_comment);
                     SendTelegramMessage(Telegram_Token, Telegram_ChatID, alert_msg, Enable_Telegram_Alerts);
                     LogEvent(TimeCurrent(), "PartialClose", alert_msg, current_symbol, MagicNumber, Enable_Trade_Logging);
                     // Potentially move SL to BreakEven+1 after partial close
                     // This part is not in the original request but is a common follow-up
                    }
                 }
              }

            // --- Trailing Stop (Simple fixed pip trailing) ---
            // Example: Trail by 50% of initial SL distance, start trailing when price moves 100% of initial SL distance in profit
            double trailing_start_points = initial_sl_pips_as_points;
            double trailing_distance_points = initial_sl_pips_as_points * 0.5;

            if (trailing_distance_points > 0) {
                double new_sl = current_sl;
                bool modify_sl = false;

                if(position_type == POSITION_TYPE_BUY) {
                    if(latest_tick.bid > position_open_price + trailing_start_points * point_value) {
                        double potential_new_sl = latest_tick.bid - trailing_distance_points * point_value;
                        if(potential_new_sl > current_sl || current_sl == 0) { // SL must only move in profit direction or be set if 0
                           // Ensure new SL is not too close to current price (respects SYMBOL_TRADE_STOPS_LEVEL)
                           if (potential_new_sl < latest_tick.bid - SymbolInfoInteger(current_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value) {
                                new_sl = potential_new_sl;
                                modify_sl = true;
                           }
                        }
                    }
                } else { // POSITION_TYPE_SELL
                    if(latest_tick.ask < position_open_price - trailing_start_points * point_value) {
                        double potential_new_sl = latest_tick.ask + trailing_distance_points * point_value;
                        if(potential_new_sl < current_sl || current_sl == 0) { // SL must only move in profit direction or be set if 0
                            // Ensure new SL is not too close to current price
                            if (potential_new_sl > latest_tick.ask + SymbolInfoInteger(current_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value) {
                                new_sl = potential_new_sl;
                                modify_sl = true;
                            }
                        }
                    }
                }

                if(modify_sl && new_sl != current_sl) {
                    if(ModifyPosition(position_ticket, new_sl, current_tp, "Trailing SL")) {
                        string alert_msg = StringFormat("TRAILING SL: %s %s. New SL: %.5f", EnumToString(position_type), current_symbol, new_sl);
                        SendTelegramMessage(Telegram_Token, Telegram_ChatID, alert_msg, Enable_Telegram_Alerts);
                        LogEvent(TimeCurrent(), "TrailingSL", alert_msg, current_symbol, MagicNumber, Enable_Trade_Logging);
                    }
                }
            }
            goto next_symbol_label;
           }
        }

      // 5. Check for New Trade Entry if no position is open for this symbol by this EA
      bool position_exists_for_symbol = false;
      for(int k_pos=0; k_pos < PositionsTotal(); k_pos++) {
          if(PositionGetTicket(k_pos)>0 && PositionGetString(POSITION_SYMBOL) == current_symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
              position_exists_for_symbol = true;
              break;
          }
      }

      if(!position_exists_for_symbol) {
         EntrySignal signal = CheckEntryConditions(current_symbol, Timeframe,
                                                   EMA_Fast_Period, EMA_Slow_Period,
                                                   RSI_Period, RSI_Overbought, RSI_Oversold,
                                                   BOS_Swing_Lookback_Period, BOS_Confirmation_Lookback,
                                                   TP_Risk_Reward_Ratio, Fixed_SL_Pips); // Fixed_SL_Pips is in points

         if(signal.valid_signal) {
            double point_size = SymbolInfoDouble(current_symbol, SYMBOL_POINT);
            double min_stop_level_points = SymbolInfoInteger(current_symbol, SYMBOL_TRADE_STOPS_LEVEL); // This is in points
            double current_spread_points = (SymbolInfoDouble(current_symbol, SYMBOL_ASK) - SymbolInfoDouble(current_symbol, SYMBOL_BID)) / point_size;


            if(signal.type == ORDER_TYPE_BUY) {
                if((signal.entry_price - signal.stop_loss_price)/point_size < min_stop_level_points) {
                    PrintFormat("SL too close for BUY on %s. Entry: %.5f, SL: %.5f. Min Distance Points: %.0f. Adjusting SL or skipping.",
                                current_symbol, signal.entry_price, signal.stop_loss_price, min_stop_level_points);
                    goto next_symbol_label;
                }
            } else { // ORDER_TYPE_SELL
                if((signal.stop_loss_price - signal.entry_price)/point_size < min_stop_level_points) {
                    PrintFormat("SL too close for SELL on %s. Entry: %.5f, SL: %.5f. Min Distance Points: %.0f. Adjusting SL or skipping.",
                                current_symbol, signal.entry_price, signal.stop_loss_price, min_stop_level_points);
                    goto next_symbol_label;
                }
            }

            double sl_dist_points = MathAbs(signal.entry_price - signal.stop_loss_price) / point_size;
            if (sl_dist_points == 0) { // Avoid division by zero in lot size calc
                PrintFormat("Stop loss distance is zero for %s. Skipping trade.", current_symbol);
                goto next_symbol_label;
            }
            double lot_size = CalculateLotSize(current_symbol, Risk_Percent, sl_dist_points);

            if(lot_size >= SymbolInfoDouble(current_symbol, SYMBOL_VOLUME_MIN)) {
               ulong ticket = OpenMarketOrder(current_symbol, signal.type, lot_size, signal.entry_price,
                                  signal.stop_loss_price, signal.take_profit_price,
                                  MagicNumber, Slippage, signal.comment);
               if(ticket > 0) {
                  // Fetch actual entry price from position info if possible, or use signal.entry_price (market order may fill differently)
                  // For simplicity, logging signal.entry_price for now.
                  string alert_msg = StringFormat("NEW TRADE: %s %s %.2f lots at ~%.5f. SL: %.5f, TP: %.5f. %s",
                                                  EnumToString(signal.type), current_symbol, lot_size, signal.entry_price,
                                                  signal.stop_loss_price, signal.take_profit_price, signal.comment);
                  SendTelegramMessage(Telegram_Token, Telegram_ChatID, alert_msg, Enable_Telegram_Alerts);
                  LogOpenedTrade(TimeCurrent(), current_symbol, signal.type, lot_size, signal.entry_price,
                                 signal.stop_loss_price, signal.take_profit_price, MagicNumber, ticket,
                                 signal.comment, Enable_Trade_Logging);
                  goto next_symbol_label;
                 }
            } else {
               PrintFormat("Lot size (%.2f) for %s is less than Min Lot (%.2f) or zero. SL Points: %.1f. Skipping trade.",
                           lot_size, current_symbol, SymbolInfoDouble(current_symbol, SYMBOL_VOLUME_MIN), sl_dist_points);
               LogEvent(TimeCurrent(), "LotSizeSkipped", StringFormat("Lot size %.2f (SL pts %.1f) < min lot %.2f or zero.", lot_size, sl_dist_points, SymbolInfoDouble(current_symbol, SYMBOL_VOLUME_MIN)), current_symbol, MagicNumber, Enable_Trade_Logging);
            }
         }
      }
      next_symbol_label:;
     } // End of symbol iteration loop
  } // End of OnTick()

// Helper function to remove leading/trailing whitespace
string Trim(string &str)
  {
   str = StringTrimLeft(str);
   str = StringTrimRight(str);
   return str;
  }
//+------------------------------------------------------------------+
