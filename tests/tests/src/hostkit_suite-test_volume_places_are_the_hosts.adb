separate (Hostkit_Suite)
procedure Test_Volume_Places_Are_The_Hosts
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Mounts.Volume_Place_Kind;

   Places : constant Hostkit.Mounts.Volume_Place_List := Hostkit.Mounts.Volume_Places;

   function Image (List : Hostkit.Mounts.Volume_Place_List) return String is
      Result : Unbounded_String;
   begin
      for Item of List loop
         Append (Result, "[" & To_String (Item.Path) & " " & Hostkit.Mounts.Volume_Place_Kind'Image (Item.Kind) & "]");
      end loop;
      return To_String (Result);
   end Image;

   --  The whole list, in order: path and kind of each place.
   procedure Expect (Wanted : Hostkit.Mounts.Volume_Place_List) is
   begin
      Assert
        (Places'Length = Wanted'Length
           and then (for all Index in 0 .. Places'Length - 1 =>
                       Places (Places'First + Index).Path = Wanted (Wanted'First + Index).Path
                         and then Places (Places'First + Index).Kind = Wanted (Wanted'First + Index).Kind),
         "the volume places: wanted " & Image (Wanted) & ", got " & Image (Places));
   end Expect;

   function Place (Path : String; Kind : Hostkit.Mounts.Volume_Place_Kind) return Hostkit.Mounts.Volume_Place
   is ((Path => To_Unbounded_String (Path), Kind => Kind));
begin
   case Hostkit.Host.Current is
      when Hostkit.Host.Linux =>
         Expect
           ([Place ("/mnt", Hostkit.Mounts.Volumes_Folder),
             Place ("/media", Hostkit.Mounts.Volumes_Folder),
             Place ("/run/media", Hostkit.Mounts.User_Volumes_Folder)]);
      when Hostkit.Host.MacOS =>
         Expect
           ([Place ("/Volumes", Hostkit.Mounts.Volumes_Folder),
             Place ("/System/Volumes", Hostkit.Mounts.Volumes_Folder)]);
      when Hostkit.Host.Windows =>
         --  The drives GetLogicalDrives reports, each once and in order, as
         --  a root; the runner's system drive among them.
         for Index in Places'Range loop
            declare
               Path : constant String := To_String (Places (Index).Path);
            begin
               Assert (Places (Index).Kind = Hostkit.Mounts.Drive_Root, Path & " is listed as a drive root");
               Assert
                 (Path'Length = 3
                    and then Path (Path'First) in 'A' .. 'Z'
                    and then Path (Path'First + 1 .. Path'Last) = ":\",
                  Path & " is a drive's root, X:\");
               Assert
                 (Index = Places'First or else To_String (Places (Index - 1).Path) < Path,
                  Path & " follows the drive before it, once: " & Image (Places));
            end;
         end loop;
         Assert
           ((for some Item of Places => To_String (Item.Path) = "C:\"),
            "the system drive C:\ is listed: " & Image (Places));
      when Hostkit.Host.Unsupported =>
         Assert (Places'Length = 0, "a host this crate does not know names no volume places");
   end case;
end Test_Volume_Places_Are_The_Hosts;
