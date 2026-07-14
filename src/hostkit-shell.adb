with Ada.Environment_Variables;
with Ada.Strings.Unbounded;

package body Hostkit.Shell is
   use Ada.Strings.Unbounded;

   function Value (Name : String) return String is
   begin
      if Ada.Environment_Variables.Exists (Name) then
         return Ada.Environment_Variables.Value (Name);
      end if;

      return "";
   exception
      when others =>
         return "";
   end Value;

   function Is_Command_Shell return Boolean is
   begin
      return Value ("COMSPEC") /= "";
   end Is_Command_Shell;

   function Executable return String is
      Comspec : constant String := Value ("COMSPEC");
      Shell   : constant String := Value ("SHELL");
   begin
      if Comspec /= "" then
         return Comspec;
      elsif Shell /= "" then
         return Shell;
      else
         return "/bin/sh";
      end if;
   end Executable;

   function Command_Option return String is
   begin
      return (if Is_Command_Shell then "/C" else "-c");
   end Command_Option;

   function Quote (Value : String) return String is
      Result : Unbounded_String;
   begin
      if Is_Command_Shell then
         --  cmd groups an argument with double quotes, and an embedded " is doubled.
         --  Single quotes group nothing here -- cmd passes them straight through as
         --  part of the text -- so quoting cmd's arguments the way sh wants them was
         --  not merely unidiomatic, it did not work at all.
         Append (Result, '"');
         for Character_Value of Value loop
            if Character_Value = '"' then
               Append (Result, """""");
            else
               Append (Result, Character_Value);
            end if;
         end loop;
         Append (Result, '"');
         return To_String (Result);
      end if;

      Append (Result, "'");
      for Character_Value of Value loop
         if Character_Value = ''' then
            Append (Result, "'\''");
         else
            Append (Result, Character_Value);
         end if;
      end loop;
      Append (Result, "'");
      return To_String (Result);
   end Quote;

   function Command_Line
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return String
   is
      Result : Unbounded_String := To_Unbounded_String (Quote (Program));
   begin
      for Argument of Arguments loop
         Append (Result, " ");
         Append (Result, Quote (To_String (Argument)));
      end loop;

      return To_String (Result);
   end Command_Line;

end Hostkit.Shell;
