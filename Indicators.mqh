#ifndef INDICATORS_MQH
#define INDICATORS_MQH

//+------------------------------------------------------------------+
//| Calculate Exponential Moving Average (EMA)                       |
//+------------------------------------------------------------------+
double GetEMA(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift)
  {
   double ema_buffer[];
   if(CopyBuffer(iMA(symbol, timeframe, period, 0, MODE_EMA, PRICE_CLOSE), 0, shift, 1, ema_buffer) > 0)
     {
      return(ema_buffer[0]);
     }
   else
     {
      PrintFormat("Error copying EMA buffer. Symbol: %s, Timeframe: %s, Period: %d, Error: %d",
                  symbol, EnumToString(timeframe), period, GetLastError());
      return(-1); // Or handle error appropriately
     }
  }

//+------------------------------------------------------------------+
//| Calculate Relative Strength Index (RSI)                          |
//+------------------------------------------------------------------+
double GetRSI(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift)
  {
   double rsi_buffer[];
   if(CopyBuffer(iRSI(symbol, timeframe, period, PRICE_CLOSE), 0, shift, 1, rsi_buffer) > 0)
     {
      return(rsi_buffer[0]);
     }
   else
     {
      PrintFormat("Error copying RSI buffer. Symbol: %s, Timeframe: %s, Period: %d, Error: %d",
                  symbol, EnumToString(timeframe), period, GetLastError());
      return(-1); // Or handle error appropriately
     }
  }

#endif // INDICATORS_MQH
