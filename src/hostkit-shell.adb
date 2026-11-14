with Hostkit.Environment;
with Ada.Strings.Unbounded;

with Hostkit.Host;

package body Hostkit.Shell is
   use Ada.Strings.Unbounded;

   function Value (Name : String) return String is
   begin
      return Hostkit.Environment.Value (Name, Default => "");
   exception
      when others =>
         return "";
   end Value;

   --  Which shell family applies is decided by the host the build targets, not
   --  by the environment: COMSPEC is set on Linux machines that run Wine, and
   --  choosing cmd (with its /C and "" quoting) there broke every shell action.
   function Is_Command_Shell return Boolean is
      use type Hostkit.Host.Kind;
   begin
      return Hostkit.Host.Current = Hostkit.Host.Windows;
   end Is_Command_Shell;

   function Executable return String is
      Comspec : constant String := Value ("COMSPEC");
   begin
      if Is_Command_Shell then
         return (if Comspec /= "" then Comspec else "cmd.exe");
      end if;

      --  The shell Sh_Quote quotes for, whatever the user logs in to: POSIX
      --  puts sh at /bin/sh on every host this crate has a body for.
      return "/bin/sh";
   end Executable;

   function Interactive_Executable return String is
      Shell : constant String := Value ("SHELL");
   begin
      if Is_Command_Shell then
         return Executable;
      elsif Shell /= "" then
         return Shell;
      else
         return "/bin/sh";
      end if;
   end Interactive_Executable;

   function Command_Option return String is
   begin
      return (if Is_Command_Shell then "/C" else "-c");
   end Command_Option;

   function Sh_Quote (Value : String) return String is
      Result : Unbounded_String;
   begin
      Append (Result, "'");
      for Character_Value of Value loop
         if Character_Value = ASCII.NUL then
            return "";
         elsif Character_Value = ''' then
            Append (Result, "'\''");
         else
            Append (Result, Character_Value);
         end if;
      end loop;
      Append (Result, "'");
      return To_String (Result);
   end Sh_Quote;

   function Cmd_Quote (Value : String) return String is
      Result : Unbounded_String;
   begin
      --  cmd groups an argument with double quotes, and an embedded " is doubled.
      --  Single quotes group nothing here -- cmd passes them straight through as
      --  part of the text -- so quoting cmd's arguments the way sh wants them was
      --  not merely unidiomatic, it did not work at all.
      Append (Result, '"');
      for Character_Value of Value loop
         case Character_Value is
            when '%' | ASCII.CR | ASCII.LF | ASCII.NUL =>
               --  Expanded inside the quotes, or the end of the command: no
               --  quoting keeps this text as it is (see the specification).
               return "";
            when '"' =>
               Append (Result, """""");
            when others =>
               Append (Result, Character_Value);
         end case;
      end loop;
      Append (Result, '"');
      return To_String (Result);
   end Cmd_Quote;

   function Quote (Value : String) return String is
     (if Is_Command_Shell then Cmd_Quote (Value) else Sh_Quote (Value));

   function Command_Line
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return String
   is
      Quoted_Program : constant String := Quote (Program);
      Result         : Unbounded_String := To_Unbounded_String (Quoted_Program);
   begin
      if Quoted_Program = "" then
         return "";
      end if;

      for Argument of Arguments loop
         declare
            Quoted : constant String := Quote (To_String (Argument));
         begin
            if Quoted = "" then
               return "";
            end if;
            Append (Result, " ");
            Append (Result, Quoted);
         end;
      end loop;

      return To_String (Result);
   end Command_Line;

end Hostkit.Shell;
