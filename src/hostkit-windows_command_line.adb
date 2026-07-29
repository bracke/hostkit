with Ada.Strings.Unbounded;

package body Hostkit.Windows_Command_Line is

   use Ada.Strings.Unbounded;

   function Quote_Argument (Value : String) return String is
      Result : Unbounded_String;
      Needs  : Boolean := Value = "";
      Index  : Natural;
      Runs   : Natural;
   begin
      for Character_Value of Value loop
         if Character_Value = ' '
           or else Character_Value = '"'
           or else Character_Value = ASCII.HT
         then
            Needs := True;
         end if;
      end loop;

      if not Needs then
         return Value;
      end if;

      Append (Result, '"');
      Index := Value'First;
      while Index <= Value'Last loop
         Runs := 0;
         while Index <= Value'Last and then Value (Index) = '\' loop
            Runs := Runs + 1;
            Index := Index + 1;
         end loop;

         if Index > Value'Last then
            --  Backslashes that run up to the closing quote: double them so the
            --  quote stays the closing quote instead of being escaped.
            Append (Result, String'(1 .. 2 * Runs => '\'));
         elsif Value (Index) = '"' then
            --  Backslashes before an embedded quote are doubled, then one more
            --  backslash escapes the quote itself.
            Append (Result, String'(1 .. 2 * Runs + 1 => '\'));
            Append (Result, '"');
            Index := Index + 1;
         else
            --  Backslashes not before a quote are literal; emit them as-is.
            Append (Result, String'(1 .. Runs => '\'));
            Append (Result, Value (Index));
            Index := Index + 1;
         end if;
      end loop;
      Append (Result, '"');

      return To_String (Result);
   end Quote_Argument;

   function Build (Program : String; Arguments : String_Vectors.Vector) return String is
      Result : Unbounded_String := To_Unbounded_String (Quote_Argument (Program));
   begin
      for Argument of Arguments loop
         Append (Result, " ");
         Append (Result, Quote_Argument (To_String (Argument)));
      end loop;

      return To_String (Result);
   end Build;

end Hostkit.Windows_Command_Line;
