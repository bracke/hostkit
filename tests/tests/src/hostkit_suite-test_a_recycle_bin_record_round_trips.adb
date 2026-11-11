with Ada.Calendar.Formatting;
with Hostkit.Trash.Recycle_Bin_Format;
separate (Hostkit_Suite)
procedure Test_A_Recycle_Bin_Record_Round_Trips
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package Format renames Hostkit.Trash.Recycle_Bin_Format;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Integer_64;

   --  "C:\Users\Ö\notes €.txt" -- a character outside Latin-1 (U+20AC) too,
   --  so the UTF-16 is not just the bytes widened.
   Path : constant String :=
     "C:\Users\" & Character'Val (16#C3#) & Character'Val (16#96#) & "\notes "
     & Character'Val (16#E2#) & Character'Val (16#82#) & Character'Val (16#AC#) & ".txt";

   Item : constant Format.Info_Record :=
     (Version       => 2,
      Size          => 1_234_567,
      Deleted       => 133_000_000_000_000_000,
      Original_Path => To_Unbounded_String (Path));

   Bytes   : constant Ada.Streams.Stream_Element_Array := Format.Encode (Item);
   Decoded : Format.Info_Record;
   Units   : constant Natural := 23;  --  22 characters and the NUL
begin
   --  The layout Windows 10 writes, byte for byte where it is fixed.
   Assert (Bytes'Length = 28 + 2 * Units, "a version 2 record is a 28-byte header and the counted path");
   Assert (Bytes (Bytes'First .. Bytes'First + 7) = [2, 0, 0, 0, 0, 0, 0, 0], "version 2, little-endian");
   Assert (Bytes (Bytes'First + 24 .. Bytes'First + 27) = [Ada.Streams.Stream_Element (Units), 0, 0, 0],
           "the path's length in UTF-16 units, its NUL included");
   Assert (Bytes (Bytes'First + 28 .. Bytes'First + 29) = [Character'Pos ('C'), 0], "the path is UTF-16LE");
   Assert (Bytes (Bytes'Last - 1 .. Bytes'Last) = [0, 0], "and NUL-terminated");
   Assert (Format.Version_Of (Bytes) = 2, "the version is read back from the first eight bytes");

   Assert (Format.Decode (Bytes, Decoded), "a record it wrote decodes");
   Assert (Decoded.Size = Item.Size and then Decoded.Deleted = Item.Deleted, "size and time round-trip");
   Assert (To_String (Decoded.Original_Path) = Path, "the original path round-trips, UTF-8 to UTF-16 and back");

   --  A \\?\ prefix is never recorded: Explorer would show it.
   Assert
     (Format.Decode
        (Format.Encode ((Item with delta Original_Path => To_Unbounded_String ("\\?\C:\long\path"))), Decoded)
      and then To_String (Decoded.Original_Path) = "C:\long\path",
      "a long-form path is recorded without its prefix");

   --  Version 1, as Windows Vista to 8.1 wrote it: the path in 260 units.
   declare
      Old   : Ada.Streams.Stream_Element_Array (1 .. 24 + 520) := [others => 0];
      Text  : constant String := "D:\old.doc";
   begin
      Old (1) := 1;
      Old (9) := 16#10#;
      for Index in Text'Range loop
         Old (24 + Ada.Streams.Stream_Element_Offset (2 * Index - 1)) := Character'Pos (Text (Index));
      end loop;
      Assert (Format.Decode (Old, Decoded), "a version 1 record decodes");
      Assert (Decoded.Version = 1 and then Decoded.Size = 16, "with its version and size");
      Assert (To_String (Decoded.Original_Path) = Text, "and its fixed-length path");
   end;

   --  What is not a record is refused, never guessed at.
   Assert (not Format.Decode (Bytes (Bytes'First .. Bytes'First + 20), Decoded), "a short header is refused");
   Assert (not Format.Decode (Bytes (Bytes'First .. Bytes'Last - 2), Decoded), "a cut-off path is refused");
   declare
      Newer : Ada.Streams.Stream_Element_Array := Bytes;
      Lone  : Ada.Streams.Stream_Element_Array := Bytes;
   begin
      Newer (Newer'First) := 3;
      Assert (not Format.Decode (Newer, Decoded), "a version this does not know is refused");
      Assert (Format.Version_Of (Newer) = 3, "but its version is still read, so a writer can refuse beside it");
      --  A lone high surrogate where the 'C' was: NTFS keeps one in a name,
      --  so a recycled path can hold it. It reads as WTF-8 -- the three bytes
      --  of its code point -- and is written back as the same unit.
      Lone (Lone'First + 28) := 16#00#;
      Lone (Lone'First + 29) := 16#D8#;
      Assert (Format.Decode (Lone, Decoded), "a path holding a lone surrogate decodes");
      Assert
        (To_String (Decoded.Original_Path)
         = Character'Val (16#ED#) & Character'Val (16#A0#) & Character'Val (16#80#)
           & Path (Path'First + 1 .. Path'Last),
         "the lone surrogate reads as its own three bytes");
      Assert (Format.Encode (Decoded) = Lone, "and is written back as the unit it was");
   end;
   Assert (Format.Version_Of (Bytes (Bytes'First .. Bytes'First + 3)) = -1, "too short to hold a version");

   --  FILETIME: 100 ns since 1601, UTC.
   declare
      Epoch : constant Ada.Calendar.Time := Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0.0, Time_Zone => 0);
      Back  : Ada.Calendar.Time;
      Now   : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      use type Ada.Calendar.Time;
   begin
      Assert (Format.To_Filetime (Epoch) = 116_444_736_000_000_000, "1970 is 11644473600 seconds after 1601");
      Assert (Format.To_Time (116_444_736_000_000_000, Back) and then Back = Epoch, "and back");
      Assert (Format.To_Time (Format.To_Filetime (Now), Back) and then abs (Back - Now) < 0.000_001,
              "the time now round-trips to the 100 ns a FILETIME holds");
      Assert (not Format.To_Time (0, Back), "a zero FILETIME is no time");
   end;

   --  Names: $R<suffix> beside $I<suffix>, a file keeping its extension.
   Assert
     (Format.Recycled_Name_For ("AB12CD", "report.final.pdf", False) = "$RAB12CD.pdf", "a file keeps its extension");
   Assert (Format.Recycled_Name_For ("AB12CD", "photos.2024", True) = "$RAB12CD", "a folder keeps none");
   Assert
     (Format.Recycled_Name_For ("AB12CD", ".profile", False) = "$RAB12CD", "a leading dot is not an extension");
   Assert (Format.Info_Name_Of ("$RAB12CD.pdf") = "$IAB12CD.pdf", "the $I name of an item");
   Assert (Format.Recycled_Name_Of ("$iab12cd.pdf") = "$Rab12cd.pdf", "the $R name of a record, in any case");
   Assert (Format.Info_Name_Of ("notes.txt") = "", "an ordinary name has no record");
   Assert (Format.Is_Recycled_Name ("$r123456") and then not Format.Is_Recycled_Name ("$R"), "an item's name");

   --  Paths.
   Assert (Format.Without_Long_Prefix ("\\?\UNC\server\share\x") = "\\server\share\x", "a long share path");
   Assert (Format.Without_Long_Prefix ("\\?\Volume{1}\x") = "\\?\Volume{1}\x", "a volume path has no other form");
   Assert (Format.Inside_Recycle_Bin ("C:\$RECYCLE.BIN\S-1-5-21\$Rabc"), "an item in a bin is in it");
   Assert (Format.Inside_Recycle_Bin ("D:/$Recycle.Bin"), "and so is the bin itself");
   Assert (not Format.Inside_Recycle_Bin ("C:\Users\$Recycle.Bin.txt"), "a name that only begins so is not");
end Test_A_Recycle_Bin_Record_Round_Trips;
