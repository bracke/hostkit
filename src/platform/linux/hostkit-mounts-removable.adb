with Ada.Directories;
with Ada.Text_IO;

separate (Hostkit.Mounts)
--  Linux: /sys/block/<disk>/removable is "1" for a removable disk. A
--  partition (sdb1, nvme0n1p2, mmcblk0p1) is looked up under its disk.
function Removable (Source : String; Known : out Boolean) return Boolean is
   Prefix : constant String := "/dev/";

   --  sdb1 -> sdb1; the last path component.
   function Device_Name return String is
      Start : Natural := Source'First;
   begin
      for Index in reverse Source'Range loop
         if Source (Index) = '/' then
            Start := Index + 1;
            exit;
         end if;
      end loop;
      return (if Start > Source'Last then "" else Source (Start .. Source'Last));
   end Device_Name;

   --  sdb1 -> sdb, nvme0n1p2 -> nvme0n1: its disk.
   function Disk_Of (Device : String) return String is
      Last : Natural := Device'Last;
   begin
      while Last >= Device'First and then Device (Last) in '0' .. '9' loop
         Last := Last - 1;
      end loop;
      if Last >= Device'First and then Device (Last) = 'p' then
         Last := Last - 1;
      end if;
      return (if Last < Device'First then Device else Device (Device'First .. Last));
   end Disk_Of;

   function First_Line (Path : String) return String is
      File   : Ada.Text_IO.File_Type;
      Buffer : String (1 .. 256);
      Last   : Natural;
   begin
      if not Ada.Directories.Exists (Path) then
         return "";
      end if;
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path, Form => "shared=no");
      Ada.Text_IO.Get_Line (File, Buffer, Last);
      Ada.Text_IO.Close (File);
      return Buffer (1 .. Last);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return "";
   end First_Line;

   Device : constant String := Device_Name;
begin
   Known := False;
   if Device = ""
     or else Source'Length <= Prefix'Length
     or else Source (Source'First .. Source'First + Prefix'Length - 1) /= Prefix
   then
      return False;
   end if;
   declare
      Value : constant String :=
        (if First_Line ("/sys/block/" & Device & "/removable") /= ""
         then First_Line ("/sys/block/" & Device & "/removable")
         else First_Line ("/sys/block/" & Disk_Of (Device) & "/removable"));
   begin
      if Value = "" then
         return False;
      end if;
      Known := True;
      return Value = "1";
   end;
end Removable;
