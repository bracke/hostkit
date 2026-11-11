with Ada.Strings.UTF_Encoding;

with Hostkit.Windows_Paths;
with Interfaces.C;
with System;

package body Hostkit.Shell_Paths is
   use type Interfaces.C.unsigned_long;

   subtype C_DWord is Interfaces.C.unsigned_long;

   function Get_Short_Path_Name_W
     (Long_Path  : System.Address;
      Short_Path : System.Address;
      Buffer     : C_DWord)
      return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetShortPathNameW";

   NUL : constant Wide_Character := Wide_Character'Val (0);

   function For_Shell
     (Path      : String;
      Limit     : Positive;
      Usable    : out Boolean;
      Shortened : out Boolean)
      return Wide_String
   is
      Plain : constant Wide_String := Hostkit.Windows_Paths.From_UTF_8 (Path);
   begin
      Usable := False;
      Shortened := False;
      if Plain'Length <= Limit then
         Usable := True;
         return Plain & NUL;
      end if;

      declare
         --  The long form: GetShortPathNameW is a file API and takes it.
         Long : aliased constant Wide_String := Hostkit.Windows_Paths.Native (Path);
         Room : aliased Wide_String (1 .. 32_768) := [others => NUL];
         Got  : constant C_DWord := Get_Short_Path_Name_W (Long'Address, Room'Address, Room'Length);
      begin
         --  0 is a failure (no such path, no access); a count past the room
         --  is the size it would have needed, which no path has.
         if Got = 0 or else Got >= Room'Length then
            return "" & NUL;
         end if;

         declare
            Short : constant Wide_String := Room (1 .. Natural (Got));
            --  The shell takes no \\?\ form: \\?\C:\x is C:\x, \\?\UNC\s\x is \\s\x.
            Bare  : constant Wide_String :=
              (if Short'Length >= 8 and then Short (1 .. 8) = "\\?\UNC\" then "\\" & Short (9 .. Short'Last)
               elsif Short'Length >= 4 and then Short (1 .. 4) = "\\?\" then Short (5 .. Short'Last)
               else Short);
         begin
            --  With short names disabled the "short" form is the long one.
            if Bare'Length > Limit then
               return "" & NUL;
            end if;
            Usable := True;
            Shortened := True;
            return Bare & NUL;
         end;
      end;
   exception
      when Ada.Strings.UTF_Encoding.Encoding_Error =>
         --  Not UTF-8: no form of it is a path.
         Usable := False;
         Shortened := False;
         return "" & NUL;
   end For_Shell;

end Hostkit.Shell_Paths;
