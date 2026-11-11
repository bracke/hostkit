separate (Hostkit_Suite)
procedure Test_User_Places_Follow_The_Environment
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.User_Place_Kind;

   --  Every variable some host's User_Places reads, set here to known values
   --  and put back as found, whatever the test comes to.
   type Name_List is array (Positive range <>) of Unbounded_String;
   Names : constant Name_List :=
     [To_Unbounded_String ("HOME"), To_Unbounded_String ("XDG_RUNTIME_DIR"),
      To_Unbounded_String ("USERPROFILE"), To_Unbounded_String ("HOMEDRIVE"), To_Unbounded_String ("HOMEPATH"),
      To_Unbounded_String ("SystemDrive"), To_Unbounded_String ("HOMESHARE"), To_Unbounded_String ("OneDrive"),
      To_Unbounded_String ("OneDriveCommercial"), To_Unbounded_String ("OneDriveConsumer")];

   type Saved_Value is record
      Found : Boolean := False;
      Value : Unbounded_String;
   end record;

   function Save (Name : String) return Saved_Value is
      Found : Boolean;
      Value : constant String := Hostkit.Environment.Value (Name, Found);
   begin
      return (Found => Found, Value => To_Unbounded_String (Value));
   end Save;

   type Saved_List is array (Positive range <>) of Saved_Value;
   Saved : constant Saved_List (Names'Range) := [for Index in Names'Range => Save (To_String (Names (Index)))];

   procedure Restore is
   begin
      for Index in Names'Range loop
         if Saved (Index).Found then
            Hostkit.Environment.Set (To_String (Names (Index)), To_String (Saved (Index).Value));
         else
            Hostkit.Environment.Clear (To_String (Names (Index)));
         end if;
      end loop;
   end Restore;

   function Place (Path : String; Kind : Hostkit.Fs.User_Place_Kind) return Hostkit.Fs.User_Place
   is ((Path => To_Unbounded_String (Path), Kind => Kind));

   function Image (Places : Hostkit.Fs.User_Place_List) return String is
      Result : Unbounded_String;
   begin
      for Item of Places loop
         Append (Result, "[" & To_String (Item.Path) & " " & Hostkit.Fs.User_Place_Kind'Image (Item.Kind) & "]");
      end loop;
      return To_String (Result);
   end Image;

   --  The whole list, in order: path and kind of each place.
   procedure Expect (What : String; Wanted : Hostkit.Fs.User_Place_List) is
      Got : constant Hostkit.Fs.User_Place_List := Hostkit.Fs.User_Places;
   begin
      Assert
        (Got'Length = Wanted'Length
           and then (for all Index in 0 .. Got'Length - 1 =>
                       Got (Got'First + Index).Path = Wanted (Wanted'First + Index).Path
                         and then Got (Got'First + Index).Kind = Wanted (Wanted'First + Index).Kind),
         What & ": wanted " & Image (Wanted) & ", got " & Image (Got));
   end Expect;

   procedure Set (Name : String; Value : String) renames Hostkit.Environment.Set;
   procedure Clear (Name : String) renames Hostkit.Environment.Clear;
begin
   case Hostkit.Host.Current is
      when Hostkit.Host.Linux =>
         Set ("HOME", "/hk-places/home");
         Set ("XDG_RUNTIME_DIR", "/run/user/4242");
         --  The Windows profile variables are not read here.
         Set ("USERPROFILE", "C:\Users\hk");
         Set ("HOMESHARE", "\\server\hk");
         Set ("OneDrive", "C:\Users\hk\OneDrive");
         Expect
           ("the home, then the desktop's own mounts under the runtime folder",
            [Place ("/hk-places/home", Hostkit.Fs.Home_Place),
             Place ("/run/user/4242/gvfs", Hostkit.Fs.Desktop_Mounts_Parent)]);
         Clear ("XDG_RUNTIME_DIR");
         Expect ("without a runtime folder, the home alone", [Place ("/hk-places/home", Hostkit.Fs.Home_Place)]);
         Set ("XDG_RUNTIME_DIR", "");
         Expect ("an empty runtime folder names none", [Place ("/hk-places/home", Hostkit.Fs.Home_Place)]);
      when Hostkit.Host.MacOS =>
         Set ("HOME", "/Users/hk-places");
         --  Neither the freedesktop runtime folder nor the Windows profile
         --  variables are read here.
         Set ("XDG_RUNTIME_DIR", "/run/user/4242");
         Set ("USERPROFILE", "C:\Users\hk");
         Set ("HOMESHARE", "\\server\hk");
         Set ("OneDrive", "C:\Users\hk\OneDrive");
         Expect ("the home alone", [Place ("/Users/hk-places", Hostkit.Fs.Home_Place)]);
      when Hostkit.Host.Windows =>
         Clear ("HOME");
         Set ("XDG_RUNTIME_DIR", "/run/user/4242");
         Set ("USERPROFILE", "C:\Users\hk");
         Set ("HOMEDRIVE", "H:");
         Set ("HOMEPATH", "\hk-home");
         Set ("SystemDrive", "C:");
         Set ("HOMESHARE", "\\server\hk");
         Set ("OneDrive", "C:\Users\hk\OneDrive");
         Clear ("OneDriveCommercial");
         Clear ("OneDriveConsumer");
         Expect
           ("the profile, the home drive and folder, the system drive, the home share, OneDrive",
            [Place ("C:\Users\hk", Hostkit.Fs.Home_Place),
             Place ("H:\", Hostkit.Fs.Drive_Place),
             Place ("H:\hk-home", Hostkit.Fs.Profile_Place),
             Place ("C:\", Hostkit.Fs.Drive_Place),
             Place ("\\server\hk", Hostkit.Fs.Network_Place),
             Place ("C:\Users\hk\OneDrive", Hostkit.Fs.Cloud_Place)]);
         Clear ("USERPROFILE");
         Clear ("HOMESHARE");
         Clear ("OneDrive");
         Expect
           ("without a profile variable the home is HOMEDRIVE and HOMEPATH",
            [Place ("H:\hk-home", Hostkit.Fs.Home_Place),
             Place ("H:\", Hostkit.Fs.Drive_Place),
             Place ("H:\hk-home", Hostkit.Fs.Profile_Place),
             Place ("C:\", Hostkit.Fs.Drive_Place)]);
         Clear ("HOMEDRIVE");
         Clear ("HOMEPATH");
         Set ("OneDriveCommercial", "D:\Work\OneDrive");
         Set ("OneDriveConsumer", "D:\Own\OneDrive");
         Expect
           ("with no home at all, the system drive and both OneDrive folders",
            [Place ("C:\", Hostkit.Fs.Drive_Place),
             Place ("D:\Work\OneDrive", Hostkit.Fs.Cloud_Place),
             Place ("D:\Own\OneDrive", Hostkit.Fs.Cloud_Place)]);
      when Hostkit.Host.Unsupported =>
         Expect ("a host this crate does not know names no places", []);
   end case;
   Restore;
exception
   when others =>
      Restore;
      raise;
end Test_User_Places_Follow_The_Environment;
