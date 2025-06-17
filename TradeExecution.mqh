#ifndef TRADEEXECUTION_MQH
#define TRADEEXECUTION_MQH

// #include "TradeLogic.mqh" // May not be directly needed here but good for context
                               // We'll pass EntrySignal struct or its components.

//+------------------------------------------------------------------+
//| Open Market Order                                                |
//+------------------------------------------------------------------+
ulong OpenMarketOrder(string symbol, ENUM_ORDER_TYPE type, double volume,
                     double price, double sl_price, double tp_price,
                     ulong magic_number, int slippage, string comment = "")
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL; // Market order
   request.symbol = symbol;
   request.volume = volume;
   request.type = type;

   // For market orders, price is current market price. MT5 handles this if price is 0.
   // However, it's better to explicitly set it for clarity and control if needed.
   if (type == ORDER_TYPE_BUY)
     request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
   else if (type == ORDER_TYPE_SELL)
     request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
   else {
     PrintFormat("Invalid order type for OpenMarketOrder: %s", EnumToString(type));
     return 0; // Changed return type
   }

   // NormalizeDouble the price passed in if it's a pending order,
   // but for market orders, use current market price.
   // The 'price' parameter in this function for market order is more of a placeholder or for logging.
   // request.price is set above to current Ask/Bid.
   // request.price = NormalizeDouble(request.price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)); // This line is fine.

   // If a specific price was passed for a market order (unusual), we should use it,
   // but generally for market orders, price field in request can be 0 or current market price.
   // The code correctly sets it to Ask/Bid above, so this specific 'price' param isn't directly used for request.price.

   // For clarity, ensure request.price is normalized if it were to be taken from the 'price' parameter.
   // However, current logic uses SymbolInfoDouble(symbol, SYMBOL_ASK/BID) which is correct for market orders.
   request.price = NormalizeDouble(request.price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)); // Normalizing the fetched Ask/Bid
   request.sl = NormalizeDouble(sl_price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   request.tp = NormalizeDouble(tp_price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   request.deviation = slippage;
   request.magic = magic_number;
   request.comment = comment;
   request.type_filling = ORDER_FILLING_FOK; // Or ORDER_FILLING_IOC, depending on broker/preference

   // Ensure symbol properties are up to date
   SymbolInfoTick(symbol);

   if(!OrderSend(request, result))
     {
      PrintFormat("OrderSend failed for %s. Error: %d. Retcode: %d. Comment: %s. Request Price: %.5f, Result Price: %.5f",
                  symbol, GetLastError(), result.retcode, result.comment, request.price, result.price);
      // Additional details for debugging common errors
      if(result.retcode == TRADE_RETCODE_INVALID_PRICE || result.retcode == TRADE_RETCODE_INVALID_STOPS) {
          PrintFormat("Invalid price/stops. Symbol: %s, Ask: %.5f, Bid: %.5f, SL: %.5f, TP: %.5f",
                      symbol, SymbolInfoDouble(symbol, SYMBOL_ASK), SymbolInfoDouble(symbol, SYMBOL_BID), sl_price, tp_price);
      }
      if(result.retcode == TRADE_RETCODE_NO_MONEY) {
          PrintFormat("Not enough money. Required margin: %.2f, Free margin: %.2f",
                      result.margin, AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      }
      return 0; // Changed return type
     }

   PrintFormat("OrderSend successful for %s. Order #%d. Type: %s, Volume: %.2f, Entry Price: %.5f, SL: %.5f, TP: %.5f, Comment: %s",
               symbol, result.order, EnumToString(type), volume, result.price, sl_price, tp_price, comment);
   return result.order; // Changed return type
  }

//+------------------------------------------------------------------+
//| Close Position by Ticket (Full or Partial)                       |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(long ticket, double volume_to_close = 0, string comment = "") // 0 volume means close all
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   // Select position by ticket
   if(!PositionSelectByTicket(ticket))
     {
      PrintFormat("Failed to select position by ticket %d. Error: %d", ticket, GetLastError());
      // If position already closed, PositionSelectByTicket might fail. Check GetLastError()
      if(GetLastError() == ERR_TRADE_POSITION_NOT_FOUND) {
          PrintFormat("Position #%d not found. It might have been already closed.", ticket);
      }
      return false;
     }

   double position_volume = PositionGetDouble(POSITION_VOLUME);
   string symbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE); // POSITION_TYPE_BUY or POSITION_TYPE_SELL

   // Ensure symbol properties are up to date for price fetching
   SymbolInfoTick(symbol);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.magic = (ulong)PositionGetInteger(POSITION_MAGIC); // Use position's magic number, cast to ulong
   request.comment = comment == "" ? "Position Close" : comment;
   request.type_filling = ORDER_FILLING_FOK; // Or ORDER_FILLING_IOC

   if(volume_to_close <= 0 || volume_to_close >= position_volume) // Use <=0 for full close
     {
      request.volume = position_volume; // Close entire position
     }
   else
     {
      request.volume = volume_to_close; // Partial close
     }

   // For closing, type is opposite of position type
   if(type == POSITION_TYPE_BUY)
     {
      request.type = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(symbol, SYMBOL_BID); // Close buy at Bid
     }
   else if(type == POSITION_TYPE_SELL)
     {
      request.type = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);  // Close sell at Ask
     }
   else
     {
      PrintFormat("Unknown position type (%d) for ticket %d", (int)type, ticket);
      return false;
     }

   request.price = NormalizeDouble(request.price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   request.position = ticket; // Specify the ticket of the position to close/reduce

   if(!OrderSend(request, result))
     {
      PrintFormat("OrderSend failed for closing position #%d (%s). Error: %d. Retcode: %d. Comment: %s. Request Price: %.5f, Result Price: %.5f",
                  ticket, symbol, GetLastError(), result.retcode, result.comment, request.price, result.price);
      return false;
     }

   PrintFormat("OrderSend successful for closing position #%d (%s). Volume closed: %.2f. Result Price: %.5f. Comment: %s",
               ticket, symbol, request.volume, result.price, comment);
   return true;
  }

//+------------------------------------------------------------------+
//| Modify Position SL/TP                                            |
//+------------------------------------------------------------------+
bool ModifyPosition(long ticket, double new_sl_price, double new_tp_price, string comment = "")
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   // Select position by ticket to get its properties
   if(!PositionSelectByTicket(ticket))
     {
      PrintFormat("Failed to select position by ticket %d for modification. Error: %d", ticket, GetLastError());
      if(GetLastError() == ERR_TRADE_POSITION_NOT_FOUND) {
          PrintFormat("Position #%d not found for modification. It might have been closed.", ticket);
      }
      return false;
     }

   string symbol = PositionGetString(POSITION_SYMBOL);

   // Ensure symbol properties are up to date for normalization
   SymbolInfoTick(symbol);

   request.action = TRADE_ACTION_SLTP;
   request.symbol = symbol;
   request.position = ticket; // Specify the ticket of the position to modify

   // Normalize SL and TP prices. A zero value means no change or remove SL/TP.
   // Be careful: if new_sl_price is 0, it means remove SL. If it's an invalid price (e.g. too close), it will be rejected.
   request.sl = NormalizeDouble(new_sl_price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS));
   request.tp = NormalizeDouble(new_tp_price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS));
   request.comment = comment == "" ? "Modify SL/TP" : comment;


   if(!OrderSend(request, result))
     {
      PrintFormat("OrderSend failed for modifying position #%d (%s). Error: %d. Retcode: %d. Comment: %s. New SL: %.5f, New TP: %.5f",
                  ticket, request.symbol, GetLastError(), result.retcode, result.comment, new_sl_price, new_tp_price);
      // Additional details for debugging common errors
      if(result.retcode == TRADE_RETCODE_INVALID_STOPS) {
          PrintFormat("Invalid SL/TP for modification. Symbol: %s, Ask: %.5f, Bid: %.5f, Current SL: %.5f, Current TP: %.5f, New SL: %.5f, New TP: %.5f",
                      request.symbol,
                      SymbolInfoDouble(request.symbol, SYMBOL_ASK),
                      SymbolInfoDouble(request.symbol, SYMBOL_BID),
                      PositionGetDouble(POSITION_SL),
                      PositionGetDouble(POSITION_TP),
                      new_sl_price, new_tp_price);
      }
      return false;
     }

   PrintFormat("OrderSend successful for modifying position #%d (%s). New SL: %.5f, New TP: %.5f. Comment: %s",
               ticket, request.symbol, new_sl_price, new_tp_price, comment);
   return true;
  }

// Placeholder for Trailing Stop - to be implemented in trade management logic
// void ManageTrailingStop(long ticket, double trailing_stop_pips, double trigger_pips) { ... }

#endif // TRADEEXECUTION_MQH
