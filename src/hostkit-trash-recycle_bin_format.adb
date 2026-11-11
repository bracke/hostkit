with Ada.Calendar.Formatting;
with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;

with Hostkit.Windows_Paths;

package body Hostkit.Trash.Recycle_Bin_Format is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;

   subtype Byte_Array is Ada.Streams.Stream_Element_Array;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   function To_Signed is new Ada.Unchecked_Conversion (Interfaces.Unsigned_64, Interfaces.Integer_64);
   function To_Unsigned is new Ada.Unchecked_Conversion (Interfaces.Integer_64, Interfaces.Unsigned_64);

   --  Version 1 keeps the path in a fixed MAX_PATH field.
   Version_1_Path_Units : constant := 260;
   Header_Bytes         : constant := 24;

   --  A path longer than the longest Windows path is not one.
   Longest_Path_Units : constant := 32_768;

   --  Seconds from 1601-01-01 to 1970-01-01, and FILETIME ticks per second.
   Unix_Epoch_Seconds : constant Interfaces.Integer_64 := 11_644_473_600;
   Ticks_Per_Second   : constant Interfaces.Integer_64 := 10_000_000;

   function Unix_Epoch return Ada.Calendar.Time is
     (Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0.0, Time_Zone => 0));

   procedure Put
     (Into  : in out Byte_Array;
      At_Of : Offset;
      Value : Interfaces.Unsigned_64;
      Count : Positive)
   is
      Rest : Interfaces.Unsigned_64 := Value;
   begin
      for Index in 0 .. Offset (Count) - 1 loop
         Into (At_Of + Index) := Ada.Streams.Stream_Element (Rest and 16#FF#);
         Rest := Interfaces.Shift_Right (Rest, 8);
      end loop;
   end Put;

   function Get (From : Byte_Array; At_Of : Offset; Count : Positive) return Interfaces.Unsigned_64 is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Index in reverse 0 .. Offset (Count) - 1 loop
         Result := Interfaces.Shift_Left (Result, 8) or Interfaces.Unsigned_64 (From (At_Of + Index));
      end loop;
      return Result;
   end Get;

   function Encode (Item : Info_Record) return Ada.Streams.Stream_Element_Array is
      Path   : constant Wide_String :=
        Hostkit.Windows_Paths.From_UTF_8 (Without_Long_Prefix (To_String (Item.Original_Path)));
      Units  : constant Natural := Path'Length + 1;
      Result : Byte_Array (1 .. Offset (Header_Bytes + 4 + 2 * Units)) := [others => 0];
      Cursor : Offset := Result'First + Header_Bytes + 4;
   begin
      Put (Result, Result'First, Newest_Version, 8);
      Put (Result, Result'First + 8, To_Unsigned (Item.Size), 8);
      Put (Result, Result'First + 16, To_Unsigned (Item.Deleted), 8);
      Put (Result, Result'First + Header_Bytes, Interfaces.Unsigned_64 (Units), 4);
      for Unit of Path loop
         Put (Result, Cursor, Interfaces.Unsigned_64 (Wide_Character'Pos (Unit)), 2);
         Cursor := Cursor + 2;
      end loop;
      --  The terminating NUL is already there.
      return Result;
   end Encode;

   function Decode (Bytes : Ada.Streams.Stream_Element_Array; Item : out Info_Record) return Boolean is
      First : constant Offset := Bytes'First;

      --  Count units from Start, up to the first NUL.
      function Path_From (Start : Offset; Count : Natural) return Wide_String is
         Text : Wide_String (1 .. Count);
         Last : Natural := 0;
      begin
         for Index in 1 .. Count loop
            declare
               Unit : constant Interfaces.Unsigned_64 := Get (Bytes, Start + Offset (2 * (Index - 1)), 2);
            begin
               exit when Unit = 0;
               Last := Index;
               Text (Index) := Wide_Character'Val (Unit);
            end;
         end loop;
         return Text (1 .. Last);
      end Path_From;
   begin
      Item := (others => <>);
      if Bytes'Length < Header_Bytes then
         return False;
      end if;
      Item.Version := To_Signed (Get (Bytes, First, 8));
      Item.Size := To_Signed (Get (Bytes, First + 8, 8));
      Item.Deleted := To_Signed (Get (Bytes, First + 16, 8));
      declare
         Path : Unbounded_String;
      begin
         case Item.Version is
            when 1 =>
               if Bytes'Length < Header_Bytes + 2 * Version_1_Path_Units then
                  return False;
               end if;
               Path := To_Unbounded_String
                 (Hostkit.Windows_Paths.To_UTF_8 (Path_From (First + Header_Bytes, Version_1_Path_Units)));
            when 2 =>
               if Bytes'Length < Header_Bytes + 4 then
                  return False;
               end if;
               declare
                  Units : constant Interfaces.Unsigned_64 := Get (Bytes, First + Header_Bytes, 4);
               begin
                  if Units = 0
                    or else Units > Longest_Path_Units
                    or else Offset (Bytes'Length) < Header_Bytes + 4 + 2 * Offset (Units)
                  then
                     return False;
                  end if;
                  Path := To_Unbounded_String
                    (Hostkit.Windows_Paths.To_UTF_8 (Path_From (First + Header_Bytes + 4, Natural (Units))));
               end;
            when others =>
               return False;
         end case;
         if Length (Path) = 0 then
            return False;
         end if;
         Item.Original_Path := Path;
      end;
      --  A lone surrogate is kept, as WTF-8: NTFS stores one in a name, so
      --  a recycled item's path can hold one.
      return True;
   end Decode;

   function Version_Of (Bytes : Ada.Streams.Stream_Element_Array) return Interfaces.Integer_64 is
     (if Bytes'Length < 8 then -1 else To_Signed (Get (Bytes, Bytes'First, 8)));

   function To_Filetime (Value : Ada.Calendar.Time) return Interfaces.Integer_64 is
      Since    : constant Duration := Value - Unix_Epoch;
      Seconds  : constant Interfaces.Integer_64 := Interfaces.Integer_64 (Since);
      Fraction : constant Duration := Since - Duration (Seconds);
   begin
      return (Seconds + Unix_Epoch_Seconds) * Ticks_Per_Second
        + Interfaces.Integer_64 (Fraction * Integer (Ticks_Per_Second));
   end To_Filetime;

   function To_Time (Filetime : Interfaces.Integer_64; Value : out Ada.Calendar.Time) return Boolean is
      --  Ada.Calendar runs from 1901 to 2399 and a Duration holds about 292
      --  years either way, so the seconds since 1970 are taken in two steps
      --  where they could not be added in one.
      Ticks   : constant Interfaces.Integer_64 := Filetime - Unix_Epoch_Seconds * Ticks_Per_Second;
      Seconds : constant Interfaces.Integer_64 := Ticks / Ticks_Per_Second;
      Rest    : constant Interfaces.Integer_64 := Ticks rem Ticks_Per_Second;
      Half    : constant Interfaces.Integer_64 := 4_000_000_000;
   begin
      Value := Unix_Epoch;
      if Filetime <= 0 or else Seconds < -2 * Half or else Seconds > 3 * Half then
         return False;
      end if;
      declare
         First_Step : constant Interfaces.Integer_64 :=
           Interfaces.Integer_64'Max (-Half, Interfaces.Integer_64'Min (Half, Seconds));
      begin
         Value := Unix_Epoch + Duration (First_Step);
         Value := Value + Duration (Seconds - First_Step);
         Value := Value + Duration (Rest) / Integer (Ticks_Per_Second);
      end;
      return True;
   exception
      when Ada.Calendar.Time_Error | Constraint_Error =>
         Value := Unix_Epoch;
         return False;
   end To_Time;

   function Has_Prefix (Name : String; Prefix : String) return Boolean is
     (Name'Length > Prefix'Length
      and then Ada.Characters.Handling.To_Upper (Name (Name'First .. Name'First + Prefix'Length - 1)) = Prefix);

   function Is_Recycled_Name (Name : String) return Boolean is (Has_Prefix (Name, "$R"));

   function Info_Name_Of (Recycled_Name : String) return String is
     (if Is_Recycled_Name (Recycled_Name)
      then "$I" & Recycled_Name (Recycled_Name'First + 2 .. Recycled_Name'Last)
      else "");

   function Recycled_Name_Of (Info_Name : String) return String is
     (if Has_Prefix (Info_Name, "$I")
      then "$R" & Info_Name (Info_Name'First + 2 .. Info_Name'Last)
      else "");

   function Recycled_Name_For (Suffix : String; Original_Leaf : String; Is_Directory : Boolean) return String is
      Dot : Natural := 0;
   begin
      if not Is_Directory then
         for Index in reverse Original_Leaf'Range loop
            exit when Original_Leaf (Index) in '/' | '\';
            if Original_Leaf (Index) = '.' then
               Dot := Index;
               exit;
            end if;
         end loop;
      end if;
      --  A leading dot (".profile") is a name, not an extension.
      if Dot <= Original_Leaf'First then
         return "$R" & Suffix;
      end if;
      return "$R" & Suffix & Original_Leaf (Dot .. Original_Leaf'Last);
   end Recycled_Name_For;

   function Without_Long_Prefix (Path : String) return String is
   begin
      if Path'Length >= 8 and then Path (Path'First .. Path'First + 3) = "\\?\"
        and then Ada.Characters.Handling.To_Upper (Path (Path'First + 4 .. Path'First + 7)) = "UNC\"
      then
         return "\\" & Path (Path'First + 8 .. Path'Last);
      elsif Path'Length >= 6 and then Path (Path'First .. Path'First + 3) = "\\?\"
        and then Ada.Characters.Handling.Is_Letter (Path (Path'First + 4))
        and then Path (Path'First + 5) = ':'
      then
         return Path (Path'First + 4 .. Path'Last);
      end if;
      --  \\?\Volume{...}\ and the like have no other form.
      return Path;
   end Without_Long_Prefix;

   function Inside_Recycle_Bin (Path : String) return Boolean is
      Part_First : Positive := Path'First;
   begin
      for Index in Path'First .. Path'Last + 1 loop
         if Index > Path'Last or else Path (Index) in '/' | '\' then
            if Ada.Characters.Handling.To_Upper (Path (Part_First .. Index - 1)) = "$RECYCLE.BIN" then
               return True;
            end if;
            Part_First := Index + 1;
         end if;
      end loop;
      return False;
   end Inside_Recycle_Bin;

end Hostkit.Trash.Recycle_Bin_Format;
