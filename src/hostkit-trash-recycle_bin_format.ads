with Ada.Calendar;
with Ada.Streams;
with Interfaces;

--  The Recycle Bin's own file layout, as text and bytes.
--
--  An item recycled on Windows is renamed to $R<suffix> in the user's bin
--  folder, beside $I<suffix>: a small binary record of where it came from.
--  Windows Vista to 8.1 wrote version 1, a fixed 260-character path; Windows
--  10 and later write version 2, a counted one, which is what this writes:
--
--     offset  0  Int64   version (2)
--     offset  8  Int64   size in bytes (a folder's total)
--     offset 16  Int64   deletion time, a FILETIME (100 ns since 1601, UTC)
--     offset 24  UInt32  path length in UTF-16 units, its NUL included
--     offset 28  UTF-16LE path, NUL-terminated, with no \\?\ prefix
--
--  All of it little-endian. Version 1 has the path at offset 24 as 260
--  UTF-16 units, NUL-padded. Nothing here touches a file, so it is shared
--  source and tested on every host.
package Hostkit.Trash.Recycle_Bin_Format is

   --  The newest $I version this package reads and the one it writes.
   Newest_Version : constant := 2;

   --  One $I file's contents.
   type Info_Record is record
      Version : Interfaces.Integer_64 := Newest_Version;

      --  Bytes: a file's size, a folder's total.
      Size : Interfaces.Integer_64 := 0;

      --  A FILETIME: 100-nanosecond intervals since 1601-01-01 UTC.
      Deleted : Interfaces.Integer_64 := 0;

      --  The item's original path, UTF-8.
      Original_Path : UString;
   end record;

   --  Item as a version 2 $I file.
   --
   --  @param Item What to record; its Version is ignored.
   --  @return The bytes.
   function Encode (Item : Info_Record) return Ada.Streams.Stream_Element_Array;

   --  A $I file's contents, version 1 or 2.
   --
   --  @param Bytes The whole file.
   --  @param Item The record, when the bytes are one.
   --  @return False for a short or malformed file or an unknown version. A
   --    lone surrogate in the path is kept, as WTF-8 (Windows_Paths.To_UTF_8).
   function Decode (Bytes : Ada.Streams.Stream_Element_Array; Item : out Info_Record) return Boolean;

   --  The version a $I file's first eight bytes declare.
   --
   --  @param Bytes At least the file's start.
   --  @return The version, or -1 when there are fewer than eight bytes.
   function Version_Of (Bytes : Ada.Streams.Stream_Element_Array) return Interfaces.Integer_64;

   --  Value as a FILETIME.
   --
   --  @param Value A time.
   --  @return 100-nanosecond intervals since 1601-01-01 UTC.
   function To_Filetime (Value : Ada.Calendar.Time) return Interfaces.Integer_64;

   --  A FILETIME as a time, where Ada.Calendar can hold it.
   --
   --  @param Filetime 100-nanosecond intervals since 1601-01-01 UTC.
   --  @param Value The time, when the result is True.
   --  @return False for a FILETIME outside what Ada.Calendar holds.
   function To_Time (Filetime : Interfaces.Integer_64; Value : out Ada.Calendar.Time) return Boolean;

   --  Whether Name is a recycled item's name: $R followed by something.
   --
   --  @param Name A leaf name.
   --  @return True for $R..., in either case.
   function Is_Recycled_Name (Name : String) return Boolean;

   --  The $I name beside a recycled item.
   --
   --  @param Recycled_Name The item's leaf name, $R....
   --  @return $I with the same suffix, or "" when Recycled_Name is not one.
   function Info_Name_Of (Recycled_Name : String) return String;

   --  The $R name beside a $I file.
   --
   --  @param Info_Name The $I file's leaf name.
   --  @return $R with the same suffix, or "" when Info_Name is not one.
   function Recycled_Name_Of (Info_Name : String) return String;

   --  The name an item recycled as Suffix gets: $R, the six characters, and
   --  for a file its extension (".txt" of "notes.txt"), as Explorer names it.
   --
   --  @param Suffix The six random characters.
   --  @param Original_Leaf The item's own leaf name.
   --  @param Is_Directory Whether the item is a folder, which keeps no extension.
   --  @return The $R name.
   function Recycled_Name_For (Suffix : String; Original_Leaf : String; Is_Directory : Boolean) return String;

   --  Path without a \\?\ prefix: \\?\C:\x is C:\x and \\?\UNC\s\x is \\s\x.
   --  A volume GUID path (\\?\Volume{...}\x) has no other form and is kept.
   --  The rule is Hostkit.Windows_Paths.Win32_Form's, which this is.
   --
   --  @param Path Any path.
   --  @return Path in the form the shell and a $I file use.
   function Without_Long_Prefix (Path : String) return String;

   --  Whether Path names a $Recycle.Bin folder or anything inside one.
   --
   --  @param Path Any path, with / or \ separators.
   --  @return True when one of its parts is $Recycle.Bin, in any case.
   function Inside_Recycle_Bin (Path : String) return Boolean;

end Hostkit.Trash.Recycle_Bin_Format;
