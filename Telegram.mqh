#ifndef TELEGRAM_MQH
#define TELEGRAM_MQH

//+------------------------------------------------------------------+
//| Send Message to Telegram Bot                                     |
//+------------------------------------------------------------------+
void SendTelegramMessage(string token, string chat_id, string message, bool enable_alerts_input)
  {
   if(!enable_alerts_input)
     {
      return; // Alerts are disabled by user input
     }

   if(token == "" || chat_id == "")
     {
      // Print only once or less frequently to avoid log spam
      static datetime last_print_time_missing_details = 0;
      if(TimeCurrent() - last_print_time_missing_details > 300) // Print every 5 minutes if still an issue
        {
         Print("Telegram alerts enabled but Token or ChatID is missing in EA inputs. Message not sent: " + message);
         last_print_time_missing_details = TimeCurrent();
        }
      return;
     }

   if(message == "")
     {
      Print("Telegram: Attempted to send an empty message.");
      return;
     }

   // Prepare URL for Telegram API
   string url_encoded_message = "";
   int msg_len = StringLen(message);
   for(int i = 0; i < msg_len; i++)
     {
      ushort char_code = StringGetCharacter(message, i);
      // Allowed characters based on RFC 3986 (excluding percent-encoding itself)
      if((char_code >= 'a' && char_code <= 'z') ||
         (char_code >= 'A' && char_code <= 'Z') ||
         (char_code >= '0' && char_code <= '9') ||
         char_code == '-' || char_code == '_' || char_code == '.' || char_code == '~')
        {
         StringAdd(url_encoded_message, CharToString(char_code));
        }
      else if (char_code == ' ') // Special handling for space, common practice
        {
         url_encoded_message += "+";
        }
      else
        {
         url_encoded_message += StringFormat("%%%02X", char_code);
        }
     }

   // Using parse_mode=HTML allows for some basic formatting like <b>bold</b>, <i>italic</i>, <code>fixed-width</code>, <a href="...">links</a>
   // Remember to escape HTML special characters in your message if using HTML parse_mode: < > &
   // For simplicity, we are not escaping HTML specific characters here, assuming plain text or pre-formatted HTML.
   string url = "https://api.telegram.org/bot" + token + "/sendMessage?chat_id=" + chat_id + "&text=" + url_encoded_message + "&parse_mode=HTML";

   char post_data[]; // Not used for GET
   char result_data[];
   string result_headers;
   int timeout = 5000; // 5 seconds timeout

   // Resetting last error
   ResetLastError();
   int res = WebRequest("GET", url, NULL, NULL, timeout, post_data, 0, result_data, result_headers);

   if(res == -1)
     {
      PrintFormat("Telegram WebRequest failed. Error code: %d. URL: %s", GetLastError(), url);
      if(GetLastError() == 4060) // Not allowed URL (ERR_NETWORK_WEBREQUEST_NOT_ALLOWED)
        {
         static datetime last_print_time_url_disabled = 0;
         if(TimeCurrent() - last_print_time_url_disabled > 300)
           {
            Print("Telegram Error: The URL https://api.telegram.org is not in the list of allowed URLs. Please add it in Tools -> Options -> Expert Advisors tab -> 'Allow WebRequest for listed URL:'.");
            last_print_time_url_disabled = TimeCurrent();
           }
        }
     }
   else
     {
      string response = CharArrayToString(result_data);
      // Successful Telegram API responses usually contain ""ok":true"
      if(StringFind(response, "\"ok\":true") != -1)
        {
         // PrintFormat("Telegram message sent successfully: \"%s\"", message); // Avoid printing full message to log if too frequent
         static datetime last_success_print_time = 0;
         if(TimeCurrent() - last_success_print_time > 10) // Print success max every 10s
         {
            Print("Telegram message sent successfully.");
            last_success_print_time = TimeCurrent();
         }
        }
      else
        {
         PrintFormat("Telegram API Error. URL: %s, Response: %s", url, response);
        }
     }
  }

#endif // TELEGRAM_MQH
