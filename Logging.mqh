#ifndef LOGGING_MQH
#define LOGGING_MQH

// Global file handle for logging
int ExtLogFileHandle = INVALID_HANDLE;
string ExtLogFileName = ""; // Will be set in InitLogFile

//+------------------------------------------------------------------+
//| Initialize Log File (call from OnInit)                           |
//+------------------------------------------------------------------+
void InitLogFile(bool enable_logging_input, string base_filename = "TradeLog", ulong magic_number = 0)
  {
   if(!enable_logging_input)
     {
      // Print("Trade logging is disabled by input.");
      return;
     }

   // Check if EA is allowed to run fully, except in tester where it might be called before full init
   if(MQLInfoInteger(MQL_PROGRAM_TYPE) == PROGRAM_EXPERT && !MQLInfoInteger(MQL_TESTER) && !IsExpertEnabled())
     {
      Print("Cannot initialize log file: Expert Advisor is not enabled or allowed to trade.");
      return;
     }

   ExtLogFileName = base_filename + "_" + MQLInfoString(MQL_PROGRAM_NAME) + "_" + (string)magic_number + "_" + Symbol() + "_" + EnumToString(Period()) + ".csv";

   // Ensure the "Files" directory exists for sandboxed operations
   string path_separator = PathSeparator();
   string common_files_path = MQLInfoString(MQL_DATA_PATH) + path_separator + "Files"; // Common path for tester & live
   if(TerminalInfoInteger(TERMINAL_SANDBOX_MODE)) // If running in strict sandbox (e.g. Market)
    {
        common_files_path = MQLInfoString(MQL_LOCAL_PATH) + path_separator + "Files";
        // For local path, may need to ensure "Files" directory exists if not automatically created.
        // However, FileOpen in MQL_LOCAL_PATH/Files should generally work.
    }


   string full_log_path = "Files" + path_separator + ExtLogFileName; // Relative path for FileOpen, will be inside MQL5/Files or Tester/Files/...

   // Attempt to open in the "Files" directory which is generally writable
   ExtLogFileHandle = FileOpen(full_log_path, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ',');

   if(ExtLogFileHandle == INVALID_HANDLE)
     {
      // If failed, try the local path directly (might happen in some non-sandboxed setups or if "Files" dir is problematic)
      // This is more for robustness, standard should be MQL5/Files/
      ExtLogFileHandle = FileOpen(ExtLogFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
      if(ExtLogFileHandle != INVALID_HANDLE) {
          PrintFormat("Log file opened in local EA folder: %s", ExtLogFileName);
          full_log_path = ExtLogFileName; // Update path for header check
      } else {
          PrintFormat("Error opening log file %s (tried in MQL5/Files/ and local). Error: %d", ExtLogFileName, GetLastError());
          return;
      }
     }

   // If file is new or empty, write headers
   if(FileSize(ExtLogFileHandle) == 0)
     {
      FileWrite(ExtLogFileHandle, "Timestamp", "EventType", "Symbol", "OrderType", "Volume", "EntryPrice", "SL", "TP", "ExitPrice", "Profit", "MagicNumber", "Ticket", "Comment");
      FileFlush(ExtLogFileHandle);
     }
   // Move to end of file for appending new logs
   FileSeek(ExtLogFileHandle, 0, SEEK_END);
   PrintFormat("Trade log file initialized: %s (Handle: %d)", full_log_path, ExtLogFileHandle);
  }

//+------------------------------------------------------------------+
//| Deinitialize Log File (call from OnDeinit)                       |
//+------------------------------------------------------------------+
void DeinitLogFile(bool enable_logging_input)
  {
   if(!enable_logging_input) return;

   if(ExtLogFileHandle != INVALID_HANDLE)
     {
      FileClose(ExtLogFileHandle);
      ExtLogFileHandle = INVALID_HANDLE;
      PrintFormat("Trade log file closed: %s", ExtLogFileName);
     }
  }

//+------------------------------------------------------------------+
//| Log Opened Trade to CSV                                          |
//+------------------------------------------------------------------+
void LogOpenedTrade(datetime timestamp, string symbol, ENUM_ORDER_TYPE order_type,
                    double volume, double entry_price, double sl, double tp,
                    ulong magic_number, ulong ticket, string comment, bool enable_logging_input)
  {
   if(!enable_logging_input || ExtLogFileHandle == INVALID_HANDLE) return;
    // No IsExpertEnabled() check here as it might be called from OnTradeTransaction where EA might be temporarily "disabled"

   FileSeek(ExtLogFileHandle, 0, SEEK_END); // Ensure writing at the end
   FileWrite(ExtLogFileHandle,
             TimeToString(timestamp, TIME_DATE|TIME_SECONDS), // Timestamp
             "TradeOpen",                                    // EventType
             symbol,                                         // Symbol
             EnumToString(order_type),                       // OrderType
             DoubleToString(volume, 2),                      // Volume
             DoubleToString(entry_price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)), // EntryPrice
             DoubleToString(sl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),          // SL
             DoubleToString(tp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),          // TP
             "",                                             // ExitPrice (empty for open)
             "",                                             // Profit (empty for open)
             (string)magic_number,                           // MagicNumber
             (string)ticket,                                 // Ticket
             comment                                         // Comment
            );
   FileFlush(ExtLogFileHandle); // Write immediately
  }

//+------------------------------------------------------------------+
//| Log Closed Trade to CSV                                          |
//+------------------------------------------------------------------+
void LogClosedTrade(datetime timestamp, string symbol, ENUM_ORDER_TYPE order_type, // Original order type
                    double volume, double entry_price, // Original entry
                    double exit_price, double profit,
                    ulong magic_number, long ticket, string comment, bool enable_logging_input)
  {
   if(!enable_logging_input || ExtLogFileHandle == INVALID_HANDLE) return;

   FileSeek(ExtLogFileHandle, 0, SEEK_END);
   FileWrite(ExtLogFileHandle,
             TimeToString(timestamp, TIME_DATE|TIME_SECONDS), // Timestamp (close time)
             "TradeClose",                                   // EventType
             symbol,                                         // Symbol
             EnumToString(order_type),                       // OrderType
             DoubleToString(volume, 2),                      // Volume
             DoubleToString(entry_price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)), // EntryPrice
             "",                                             // SL (can be empty or last known SL)
             "",                                             // TP (can be empty or last known TP)
             DoubleToString(exit_price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)), // ExitPrice
             DoubleToString(profit, 2),                      // Profit
             (string)magic_number,                           // MagicNumber
             (string)ticket,                                 // Ticket
             comment                                         // Comment
            );
   FileFlush(ExtLogFileHandle);
  }

//+------------------------------------------------------------------+
//| Log General Event/Error to CSV                                   |
//+------------------------------------------------------------------+
void LogEvent(datetime timestamp, string event_type, string message,
              string symbol_context = "", ulong magic_number_context = 0, bool enable_logging_input = true)
  {
   if(!enable_logging_input || ExtLogFileHandle == INVALID_HANDLE) return;

   // Check to avoid logging if EA is disabled, except in tester where full init might be later
   if(MQLInfoInteger(MQL_PROGRAM_TYPE) == PROGRAM_EXPERT && !MQLInfoInteger(MQL_TESTER)) {
       if (!IsExpertEnabled() && event_type != "EA_INIT" && event_type != "EA_DEINIT") { // Allow init/deinit messages
           return;
       }
   }

   FileSeek(ExtLogFileHandle, 0, SEEK_END);
   FileWrite(ExtLogFileHandle,
             TimeToString(timestamp, TIME_DATE|TIME_SECONDS), // Timestamp
             event_type,                                     // EventType
             symbol_context,                                 // Symbol (optional)
             "",                                             // OrderType (empty)
             "",                                             // Volume (empty)
             "",                                             // EntryPrice (empty)
             "",                                             // SL (empty)
             "",                                             // TP (empty)
             "",                                             // ExitPrice (empty)
             "",                                             // Profit (empty)
             (magic_number_context == 0 ? "" : (string)magic_number_context), // MagicNumber (optional)
             "",                                             // Ticket (empty)
             message                                         // Comment/Message
            );
   FileFlush(ExtLogFileHandle);
  }

#endif // LOGGING_MQH
