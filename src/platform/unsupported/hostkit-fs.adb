with Ada.Calendar;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;

package body Hostkit.Fs is

   --  An unknown host: nothing is claimed, and nothing is pretended.
   function Is_Link (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Is_Link;

   function Create_Link
     (Target    : String;
      Link_Path : String)
      return Boolean
   is
      pragma Unreferenced (Target, Link_Path);
   begin
      return False;
   end Create_Link;

   function Is_Executable (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Is_Executable;

   --  No mode bits on Windows; access is by ACL, and reading it is not done here. Answer
   --  False -- decline to guess rather than reject a key the profile ACL already protects.
   function Accessible_By_Others (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Accessible_By_Others;

   --  No mode bits here; see the comment on the file-level answer.
   function Directory_Accessible_By_Others (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Directory_Accessible_By_Others;

   --  No mode bits to set, and this does not write an ACL; see the spec.

   --  None of these exist on this host; see the spec for what each would mean.
   function Set_Owner (Path : String; User : Integer; Group : Integer) return Boolean is
      pragma Unreferenced (Path, User, Group);
   begin
      return False;
   end Set_Owner;

   function Set_Extended_Attribute
     (Path  : String;
      Name  : String;
      Value : Ada.Streams.Stream_Element_Array) return Boolean
   is
      pragma Unreferenced (Path, Name, Value);
   begin
      return False;
   end Set_Extended_Attribute;

   function Create_FIFO (Path : String; Mode : Natural) return Boolean is
      pragma Unreferenced (Path, Mode);
   begin
      return False;
   end Create_FIFO;

   function Create_Socket (Path : String; Mode : Natural) return Boolean is
      pragma Unreferenced (Path, Mode);
   begin
      return False;
   end Create_Socket;

   function Special_File_Info_Of (Path : String) return Special_File_Info is
      pragma Unreferenced (Path);
   begin
      return (Available => False, Kind => Not_Special, Device => 0, Mode => 0);
   end Special_File_Info_Of;

   function Create_Device
     (Path   : String;
      Kind   : Device_Kind;
      Device : Interfaces.Unsigned_64;
      Mode   : Natural) return Boolean
   is
      pragma Unreferenced (Path, Kind, Device, Mode);
   begin
      return False;
   end Create_Device;

   function Create_Hard_Link (Target : String; Link_Path : String) return Boolean is
      pragma Unreferenced (Target, Link_Path);
   begin
      return False;
   end Create_Hard_Link;

   function Make_Private (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Make_Private;

   function Replace_File
     (Source : String;
      Target : String)
      return Boolean
   is
      pragma Unreferenced (Source, Target);
   begin
      return False;
   end Replace_File;

   function Read_Link_Target
     (Path   : String;
      Target : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean
   is
      pragma Unreferenced (Path);
   begin
      Target := Ada.Strings.Unbounded.Null_Unbounded_String;
      return False;
   end Read_Link_Target;

   function Delete_Link (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Delete_Link;

   function Real_Path (Path : String) return String is
      pragma Unreferenced (Path);
   begin
      return "";
   end Real_Path;

   --  No body for this host: say so by saying nothing, rather than guessing at
   --  a layout that may not exist.
   function Own_Executable return String is
   begin
      return "";
   end Own_Executable;

   function Own_Executable_Directory return String is
   begin
      return "";
   end Own_Executable_Directory;

   function Home_Directory return String is
   begin
      if Ada.Environment_Variables.Exists ("HOME") then
         return Ada.Environment_Variables.Value ("HOME");
      end if;
      return "";
   end Home_Directory;

   function Application_Data_Directory return String is
   begin
      return "";
   end Application_Data_Directory;

   function Cache_Directory return String is
   begin
      return "";
   end Cache_Directory;

   function Config_Directory return String is
   begin
      return "";
   end Config_Directory;

   function Temp_Directory return String is
   begin
      if Ada.Environment_Variables.Exists ("TMPDIR")
        and then Ada.Environment_Variables.Value ("TMPDIR") /= ""
      then
         return Ada.Environment_Variables.Value ("TMPDIR");
      end if;
      return "/tmp";
   end Temp_Directory;

   function Create_Temporary_Directory (Prefix : String) return String is
      Base : constant String := Temp_Directory;

      function Image (Value : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Left));

      function Time_Image return String is
         Raw : constant String := Duration'Image (Ada.Calendar.Seconds (Ada.Calendar.Clock));
         Result : String := Raw;
      begin
         for C of Result loop
            if C = ' ' or else C = '.' then
               C := '-';
            end if;
         end loop;
         return Result;
      end Time_Image;

      function Safe_Prefix return String is
         Result : String := Prefix;
      begin
         for C of Result loop
            if not (C in 'A' .. 'Z' or else C in 'a' .. 'z'
                    or else C in '0' .. '9' or else C = '-' or else C = '_')
            then
               C := '-';
            end if;
         end loop;
         return (if Result = "" then "hostkit-temp" else Result);
      end Safe_Prefix;
   begin
      for Attempt in 1 .. 1000 loop
         declare
            Candidate : constant String :=
              Ada.Directories.Compose
                (Containing_Directory => Base,
                 Name => Safe_Prefix & "-" & Time_Image & "-" & Image (Attempt));
         begin
            Ada.Directories.Create_Directory (Candidate);
            return Candidate;
         exception
            when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
               null;
         end;
      end loop;
      return "";
   end Create_Temporary_Directory;

   function Uses_Dos_Filename_Rules (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      --  A host Hostkit has no body for: decline to guess a restriction.
      return False;
   end Uses_Dos_Filename_Rules;

   ---------------
   -- Separator --
   ---------------

   --  A host this build does not know is assumed to write the separator
   --  that most of them do.
   function Separator return Character is ('/');

   ---------------------------
   -- Search_Path_Delimiter --
   ---------------------------

   function Search_Path_Delimiter return Character is
   begin
      return ':';
   end Search_Path_Delimiter;

   ------------------------
   -- Executable_Suffix --
   ------------------------

   function Executable_Suffix return String is
   begin
      return "";
   end Executable_Suffix;

   -----------------------
   -- Starts_When_Named --
   -----------------------

   --  The same question as Is_Executable here: a file the kernel will start is
   --  one with the bit set, and what it does with a `#!` line is its own
   --  business rather than the caller's.
   function Starts_When_Named (Path : String) return Boolean
   is (Is_Executable (Path));

   ------------------
   -- Null_Device --
   ------------------

   function Null_Device return String is
   begin
      --  A host this crate knows nothing about is not promised to have one,
      --  and a plausible guess would be a caller opening something else.
      return "";
   end Null_Device;

end Hostkit.Fs;
