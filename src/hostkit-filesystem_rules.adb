with Ada.Characters.Handling;
with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded;

package body Hostkit.Filesystem_Rules is

   use Ada.Strings.Unbounded;

   function Dos_By_Type_Name (Name : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Name);
   begin
      --  The writable Windows-family filesystems, under the identifiers Linux
      --  (vfat/msdos/exfat/ntfs/ntfs3), macOS (msdos/exfat/ntfs) and Windows
      --  (fat/fat32/ntfs/exfat) each report.
      return Lower = "vfat"
        or else Lower = "msdos"
        or else Lower = "fat"
        or else Lower = "fat12"
        or else Lower = "fat16"
        or else Lower = "fat32"
        or else Lower = "exfat"
        or else Lower = "ntfs"
        or else Lower = "ntfs3";
   end Dos_By_Type_Name;

   function Folds_By_Type_Name (Name : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Name);
   begin
      return Dos_By_Type_Name (Name)
        or else Lower = "cifs"
        or else Lower = "smb3"
        or else Lower = "smbfs";
   end Folds_By_Type_Name;

   function Utf16_By_Type_Name (Name : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Name);
   begin
      return Folds_By_Type_Name (Name)
        or else Lower = "apfs"
        or else Lower = "hfs";
   end Utf16_By_Type_Name;

   function Decode_Mount_Field (Value : String) return String is
      function Octal (Item : Character) return Natural is
        (if Item in '0' .. '7' then Character'Pos (Item) - Character'Pos ('0') else Natural'Last);

      Decoded  : Unbounded_String;
      Position : Natural := Value'First;
   begin
      while Position <= Value'Last loop
         if Value (Position) = '\'
           and then Position + 3 <= Value'Last
           and then Octal (Value (Position + 1)) /= Natural'Last
           and then Octal (Value (Position + 2)) /= Natural'Last
           and then Octal (Value (Position + 3)) /= Natural'Last
           and then Octal (Value (Position + 1)) * 64 + Octal (Value (Position + 2)) * 8
                    + Octal (Value (Position + 3)) <= Character'Pos (Character'Last)
         then
            Append
              (Decoded,
               Character'Val
                 (Octal (Value (Position + 1)) * 64 + Octal (Value (Position + 2)) * 8
                  + Octal (Value (Position + 3))));
            Position := Position + 4;
         else
            Append (Decoded, Value (Position));
            Position := Position + 1;
         end if;
      end loop;
      return To_String (Decoded);
   end Decode_Mount_Field;

   --  A mount point M contains P when M is the whole of P, or a leading path
   --  component boundary of P. Root ("/") contains every absolute path.
   function Mount_Contains (Mount_Point : String; Target_Path : String) return Boolean is
   begin
      if Mount_Point = "/" then
         return Target_Path'Length > 0 and then Target_Path (Target_Path'First) = '/';
      elsif Target_Path'Length < Mount_Point'Length then
         return False;
      end if;

      declare
         Head : constant String :=
           Target_Path (Target_Path'First .. Target_Path'First + Mount_Point'Length - 1);
      begin
         if Head /= Mount_Point then
            return False;
         end if;

         --  Exact mount point, or a child under it -- not merely a sibling whose
         --  name starts with the same text (/mnt vs /mnt-backup).
         return Target_Path'Length = Mount_Point'Length
           or else Target_Path (Target_Path'First + Mount_Point'Length) = '/';
      end;
   end Mount_Contains;

   --  The whitespace-separated tokens of one mountinfo line.
   function Tokenize (Line : String) return String_Vectors.Vector is
      Tokens : String_Vectors.Vector;
      First  : Integer := Line'First;
      Index  : Integer := Line'First;
   begin
      while Index <= Line'Last loop
         if Line (Index) = ' ' then
            if Index > First then
               Tokens.Append (To_Unbounded_String (Line (First .. Index - 1)));
            end if;
            First := Index + 1;
         end if;
         Index := Index + 1;
      end loop;

      if Index > First then
         Tokens.Append (To_Unbounded_String (Line (First .. Line'Last)));
      end if;

      return Tokens;
   end Tokenize;

   --  The type and device of the deepest mount point holding Target_Path.
   procedure Find_Mount
     (Mountinfo   : String;
      Target_Path : String;
      Best_Type   : out Unbounded_String;
      Best_Device : out Unbounded_String)
   is
      Best_Length : Integer := -1;
      Line_First  : Integer := Mountinfo'First;

      procedure Consider (Line : String) is
         Tokens : constant String_Vectors.Vector := Tokenize (Line);
         Dash    : Natural := 0;
      begin
         --  mountinfo fields: 1 id, 2 parent, 3 dev, 4 root, 5 mount point,
         --  6 options, then a variable run of optional fields, a "-" separator,
         --  and finally the filesystem type, source and super options.
         if Natural (Tokens.Length) < 7 then
            return;
         end if;

         for Position in 6 .. Natural (Tokens.Length) loop
            if To_String (Tokens (Position)) = "-" then
               Dash := Position;
               exit;
            end if;
         end loop;

         if Dash = 0 or else Dash + 1 > Natural (Tokens.Length) then
            return;
         end if;

         declare
            Mount_Point : constant String := Decode_Mount_Field (To_String (Tokens (5)));
            Fs_Type     : constant String := To_String (Tokens (Dash + 1));
         begin
            if Mount_Point'Length > Best_Length
              and then Mount_Contains (Mount_Point, Target_Path)
            then
               Best_Length := Mount_Point'Length;
               Best_Type := To_Unbounded_String (Fs_Type);
               Best_Device := Tokens (3);
            end if;
         end;
      end Consider;
   begin
      Best_Type := Null_Unbounded_String;
      Best_Device := Null_Unbounded_String;
      for Index in Mountinfo'Range loop
         if Mountinfo (Index) = Ada.Characters.Latin_1.LF then
            if Index > Line_First then
               Consider (Mountinfo (Line_First .. Index - 1));
            end if;
            Line_First := Index + 1;
         end if;
      end loop;

      if Line_First <= Mountinfo'Last then
         Consider (Mountinfo (Line_First .. Mountinfo'Last));
      end if;
   end Find_Mount;

   function Filesystem_Type_For_Mount
     (Mountinfo   : String;
      Target_Path : String)
      return String
   is
      Fs_Type, Device : Unbounded_String;
   begin
      Find_Mount (Mountinfo, Target_Path, Fs_Type, Device);
      return To_String (Fs_Type);
   end Filesystem_Type_For_Mount;

   function Device_For_Mount
     (Mountinfo   : String;
      Target_Path : String)
      return String
   is
      Fs_Type, Device : Unbounded_String;
   begin
      Find_Mount (Mountinfo, Target_Path, Fs_Type, Device);
      return To_String (Device);
   end Device_For_Mount;

   function Fuse_Block_Type (Fs_Type : String; Udev_Record : String) return String is
      Lower  : constant String := Ada.Characters.Handling.To_Lower (Fs_Type);
      Prefix : constant String := "fuseblk";
      Key    : constant String := "E:ID_FS_TYPE=";

      --  A FUSE driver's name as the filesystem it serves.
      function Served (Driver : String) return String is
        (if Driver = "ntfs-3g" or else Driver = "lowntfs-3g" or else Driver = "ntfs3g" then "ntfs"
         elsif Driver = "exfat-fuse" or else Driver = "fuse-exfat" then "exfat"
         else Driver);

      Line_First : Integer := Udev_Record'First;
   begin
      if Lower'Length < Prefix'Length
        or else Lower (Lower'First .. Lower'First + Prefix'Length - 1) /= Prefix
      then
         return Fs_Type;
      elsif Lower'Length > Prefix'Length + 1 and then Lower (Lower'First + Prefix'Length) = '.' then
         return Served (Lower (Lower'First + Prefix'Length + 1 .. Lower'Last));
      elsif Lower'Length /= Prefix'Length then
         return Fs_Type;
      end if;
      for Index in Udev_Record'First .. Udev_Record'Last + 1 loop
         if Index > Udev_Record'Last or else Udev_Record (Index) = Ada.Characters.Latin_1.LF then
            declare
               Line : constant String := Udev_Record (Line_First .. Index - 1);
            begin
               if Line'Length > Key'Length
                 and then Line (Line'First .. Line'First + Key'Length - 1) = Key
               then
                  return Ada.Characters.Handling.To_Lower (Line (Line'First + Key'Length .. Line'Last));
               end if;
            end;
            Line_First := Index + 1;
         end if;
      end loop;
      return Fs_Type;
   end Fuse_Block_Type;

end Hostkit.Filesystem_Rules;
