with Ada.Characters.Handling;

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

end Hostkit.Path_Text;
