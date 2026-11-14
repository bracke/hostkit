with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body Hostkit.Path_Text is

   function Share_Root_Last (Path : String) return Natural is
      function Sep (C : Character) return Boolean is (Is_Separator_In (Path, C));
      Server_Start : Natural;
      Share_Start  : Natural;
   begin
      if Path'Length < 5 or else not Sep (Path (Path'First)) or else not Sep (Path (Path'First + 1)) then
         return 0;
      end if;
      Server_Start := Path'First + 2;
      while Server_Start <= Path'Last and then Sep (Path (Server_Start)) loop
         Server_Start := Server_Start + 1;
      end loop;
      for Index in Server_Start .. Path'Last loop
         if Sep (Path (Index)) then
            Share_Start := Index + 1;
            while Share_Start <= Path'Last and then Sep (Path (Share_Start)) loop
               Share_Start := Share_Start + 1;
            end loop;
            if Share_Start > Path'Last then
               return 0;
            end if;
            for Share_End in Share_Start .. Path'Last loop
               if Sep (Path (Share_End)) then
                  return Share_End;
               end if;
            end loop;
            return Path'Last;
         end if;
      end loop;
      return 0;
   end Share_Root_Last;

   function Root_Length (Path : String) return Natural is
      function Sep (C : Character) return Boolean is (Is_Separator_In (Path, C));

      --  The length of a drive root starting at From: "C:\" or, as all that
      --  is left of Path, "C:".
      function Drive_At (From : Positive) return Natural is
        (if From < Path'Last
           and then Path (From) in 'A' .. 'Z' | 'a' .. 'z'
           and then Path (From + 1) = ':'
         then (if From + 1 = Path'Last then 2 elsif Sep (Path (From + 2)) then 3 else 0)
         else 0);

      --  Where a "server\share" starting at From ends: the share's last
      --  character, or Path's end when no share follows the server.
      function Share_Last (From : Positive) return Natural is
         Index : Natural := From;
      begin
         while Index <= Path'Last and then not Sep (Path (Index)) loop
            Index := Index + 1;
         end loop;
         while Index <= Path'Last and then Sep (Path (Index)) loop
            Index := Index + 1;
         end loop;
         if Index > Path'Last then
            return Path'Last;
         end if;
         while Index <= Path'Last and then not Sep (Path (Index)) loop
            Index := Index + 1;
         end loop;
         return Index - 1;
      end Share_Last;

      --  Where the component starting at From ends.
      function Component_Last (From : Positive) return Natural is
         Index : Natural := From;
      begin
         while Index <= Path'Last and then not Sep (Path (Index)) loop
            Index := Index + 1;
         end loop;
         return Index - 1;
      end Component_Last;

      First : constant Positive := Path'First;
   begin
      if Path = "" then
         return 0;
      elsif Path'Length >= 2
        and then Sep (Path (First))
        and then Sep (Path (First + 1))
        and then (Hostkit.Fs.Has_Windows_Root (Path) or else Hostkit.Fs.Separator = '\')
      then
         --  "\\?\" and "\\.\": the long and device forms.
         if Path'Length >= 4 and then Path (First + 2) in '?' | '.' and then Sep (Path (First + 3)) then
            declare
               Rest : constant Positive := First + 4;
            begin
               if Rest + 3 <= Path'Last
                 and then Ada.Characters.Handling.To_Upper (Path (Rest .. Rest + 2)) = "UNC"
                 and then Sep (Path (Rest + 3))
               then
                  return (if Rest + 4 > Path'Last then Path'Length else Share_Last (Rest + 4) - First + 1);
               elsif Rest > Path'Last then
                  return Path'Length;
               elsif Drive_At (Rest) > 0 then
                  return 4 + Drive_At (Rest);
               else
                  --  A volume or a device: "\\?\Volume{...}".
                  return Component_Last (Rest) - First + 1;
               end if;
            end;
         end if;
         return Share_Last (First + 2) - First + 1;
      elsif Drive_At (First) > 0 then
         return Drive_At (First);
      elsif Sep (Path (First)) then
         return 1;
      end if;
      return 0;
   end Root_Length;

   --  Path's text from From to Last, indexed from 1.
   function From_One (Path : String; From : Positive; Last : Natural) return String is
      Result : constant String (1 .. Last - From + 1) := Path (From .. Last);
   begin
      return Result;
   end From_One;

   --  Where Path's leaf starts and ends; Last < First for none.
   procedure Leaf_Bounds (Path : String; First : out Positive; Last : out Natural) is
      Root_Last : constant Natural := Path'First + Root_Length (Path) - 1;
   begin
      Last := Path'Last;
      while Last > Root_Last and then Is_Separator_In (Path, Path (Last)) loop
         Last := Last - 1;
      end loop;
      First := Last + 1;
      if Last <= Root_Last then
         return;
      end if;
      First := Last;
      while First > Root_Last + 1 and then not Is_Separator_In (Path, Path (First - 1)) loop
         First := First - 1;
      end loop;
   end Leaf_Bounds;

   function Leaf (Path : String) return String is
      First : Positive;
      Last  : Natural;
   begin
      Leaf_Bounds (Path, First, Last);
      return From_One (Path, First, Last);
   end Leaf;

   function Parent (Path : String) return String is
      Root_Last : constant Natural := Path'First + Root_Length (Path) - 1;
      First     : Positive;
      Last      : Natural;
   begin
      Leaf_Bounds (Path, First, Last);
      if Last < First then
         return "";
      end if;
      Last := First - 1;
      while Last > Root_Last and then Is_Separator_In (Path, Path (Last)) loop
         Last := Last - 1;
      end loop;
      return From_One (Path, Path'First, Last);
   end Parent;

   --  Whether Path is in the \\?\ or \\.\ form, which Windows reads as written.
   function Is_Long_Or_Device (Path : String) return Boolean is
     (Path'Length >= 4 and then Path (Path'First .. Path'First + 3) in "\\?\" | "\\.\");

   --  The separator Path's components are joined with: the one its root
   --  ends in, else the first it has, else '\' for a Windows path and the
   --  host's own elsewhere.
   function Style_Of (Path : String) return Character is
      Root : constant Natural := Root_Length (Path);
   begin
      if Root > 0 and then Is_Separator_In (Path, Path (Path'First + Root - 1)) then
         return Path (Path'First + Root - 1);
      end if;
      for C of Path loop
         if Is_Separator_In (Path, C) then
            return C;
         end if;
      end loop;
      return (if Hostkit.Fs.Has_Windows_Root (Path) then '\' else Hostkit.Fs.Separator);
   end Style_Of;

   --  Relative appended to Base with one separator in Base's style.
   function Joined (Base : String; Relative : String) return String is
     (if Base = "" then Relative
      elsif Is_Separator_In (Base, Base (Base'Last)) then Base & Relative
      else Base & Style_Of (Base) & Relative);

   --  Path with its "." and ".." components resolved and its empty ones
   --  dropped, the root kept as written.
   --
   --  A path in the \\?\ or \\.\ form is Windows' to read as written, so
   --  its components are names, "." and ".." among them -- all of them when
   --  Relative_First is 0, else those that start before Relative_First: the
   --  base a relative path was joined onto. The relative part's own dots,
   --  from Relative_First on, are still resolved, against that base, with
   --  the prefix and its root as the root: Windows will not do it for them.
   function Resolved (Path : String; Relative_First : Natural := 0) return String is
      use Ada.Strings.Unbounded;
      type Bounds is record
         First   : Positive;
         Last    : Natural;
         Literal : Boolean;
      end record;
      Root_Last : constant Natural := Path'First + Root_Length (Path) - 1;
      Sep       : constant Character := Style_Of (Path);
      Long      : constant Boolean := Is_Long_Or_Device (Path);
      Kept      : array (1 .. Path'Length) of Bounds := [others => (First => 1, Last => 0, Literal => False)];
      Count     : Natural := 0;
      Start     : Positive := Root_Last + 1;
      Result    : Unbounded_String;
   begin
      if Long and then Relative_First = 0 then
         return From_One (Path, Path'First, Path'Last);
      end if;
      for Index in Root_Last + 1 .. Path'Last + 1 loop
         if Index > Path'Last or else Is_Separator_In (Path, Path (Index)) then
            declare
               Part : constant String := Path (Start .. Index - 1);
            begin
               if Long and then Start < Relative_First then
                  --  The long base's own: a name, whatever it says.
                  if Part /= "" then
                     Count := Count + 1;
                     Kept (Count) := (First => Start, Last => Index - 1, Literal => True);
                  end if;
               elsif Part = ".."
                 and then Count > 0
                 and then (Kept (Count).Literal or else Path (Kept (Count).First .. Kept (Count).Last) /= "..")
               then
                  Count := Count - 1;
               elsif Part = "" or else Part = "." or else (Part = ".." and then Root_Last >= Path'First) then
                  --  Nothing, or the root's own "..", which is the root.
                  null;
               else
                  Count := Count + 1;
                  Kept (Count) := (First => Start, Last => Index - 1, Literal => False);
               end if;
            end;
            Start := Index + 1;
         end if;
      end loop;
      Result := To_Unbounded_String (Path (Path'First .. Root_Last));
      for Item of Kept (1 .. Count) loop
         if Length (Result) > 0 and then not Is_Separator_In (Path, Element (Result, Length (Result))) then
            Append (Result, Sep);
         end if;
         Append (Result, Path (Item.First .. Item.Last));
      end loop;
      if Length (Result) = 0 then
         return (if Path = "" then "" else ".");
      end if;
      return To_String (Result);
   end Resolved;

   --  Relative joined onto Base and resolved: where Base is in the long or
   --  device form, the relative part's dots are resolved against it.
   function Resolved_Join (Base : String; Relative : String) return String is
      Whole : constant String := Joined (Base, Relative);
   begin
      return Resolved (Whole, Relative_First => Whole'Last - Relative'Length + 1);
   end Resolved_Join;

   --  The drive letter Path is on, "C:\dir" or "\\?\C:\dir" alike, or ' '
   --  for none.
   function Drive_Of (Path : String) return Character is
      Letter : constant Natural := (if Is_Long_Or_Device (Path) then Path'First + 4 else Path'First);
   begin
      if Letter < Path'Last and then Path (Letter + 1) = ':' and then Path (Letter) in 'A' .. 'Z' | 'a' .. 'z' then
         return Path (Letter);
      end if;
      return ' ';
   end Drive_Of;

   function Absolute (Path : String; Base : String) return String is
      Windows_Base : constant Boolean := Hostkit.Fs.Has_Windows_Root (Base);
   begin
      if Path = "" then
         return Resolved (Base);
      elsif Is_Long_Or_Device (Path) then
         return From_One (Path, Path'First, Path'Last);
      end if;
      declare
         First : constant Positive := Path'First;
         Root  : constant Natural := Root_Length (Path);
         --  "C:dir": a drive with no separator after it.
         Drive_Relative : constant Boolean :=
           Root = 0
           and then (Windows_Base or else Hostkit.Fs.Separator = '\')
           and then Path'Length > 2
           and then Path (First) in 'A' .. 'Z' | 'a' .. 'z'
           and then Path (First + 1) = ':';
      begin
         --  "\dir" on Base's drive or share -- a backslash being a separator
         --  in a Windows path wherever it is read -- is Base's root, less the
         --  separator that may close it, and Path.
         if Windows_Base and then Root <= 1 and then Path (First) in '/' | '\' then
            declare
               Base_Root : constant String := Base (Base'First .. Base'First + Root_Length (Base) - 1);
               Last      : constant Natural :=
                 (if Is_Separator_In (Base, Base_Root (Base_Root'Last)) then Base_Root'Last - 1 else Base_Root'Last);
            begin
               declare
                  Whole : constant String := Base_Root (Base_Root'First .. Last) & Path;
               begin
                  return Resolved (Whole, Relative_First => Whole'Last - Path'Length + 1);
               end;
            end;
         elsif Root > 0 then
            return Resolved (Path);
         elsif Drive_Relative then
            if Windows_Base
              and then Ada.Characters.Handling.To_Upper (Drive_Of (Base))
                       = Ada.Characters.Handling.To_Upper (Path (First))
            then
               return Resolved_Join (Base, Path (First + 2 .. Path'Last));
            end if;
            return Resolved (Path (First .. First + 1) & '\' & Path (First + 2 .. Path'Last));
         end if;
         return Resolved_Join (Base, Path);
      end;
   end Absolute;

end Hostkit.Path_Text;
