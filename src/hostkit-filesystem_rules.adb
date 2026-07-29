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

   function Filesystem_Type_For_Mount
     (Mountinfo   : String;
      Target_Path : String)
      return String
   is
      Best_Length : Integer := -1;
      Best_Type   : Unbounded_String := Null_Unbounded_String;
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
            Mount_Point : constant String := To_String (Tokens (5));
            Fs_Type     : constant String := To_String (Tokens (Dash + 1));
         begin
            if Mount_Point'Length > Best_Length
              and then Mount_Contains (Mount_Point, Target_Path)
            then
               Best_Length := Mount_Point'Length;
               Best_Type := To_Unbounded_String (Fs_Type);
            end if;
         end;
      end Consider;
   begin
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

      return To_String (Best_Type);
   end Filesystem_Type_For_Mount;

end Hostkit.Filesystem_Rules;
