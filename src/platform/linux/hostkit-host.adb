with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Environment_Variables;
with Ada.Directories;
with Interfaces;
with Interfaces.C;
with System;

package body Hostkit.Host is
   use type Interfaces.C.int;

   subtype Uts_Field is Interfaces.C.char_array (0 .. 64);

   function To_Ada (Item : Uts_Field) return String is
     (Interfaces.C.To_Ada (Interfaces.C.char_array (Item)));

   type Utsname is record
      Sysname    : Uts_Field;
      Nodename   : Uts_Field;
      Release    : Uts_Field;
      Version    : Uts_Field;
      Machine    : Uts_Field;
      Domainname : Uts_Field;
   end record
     with Convention => C;

   function C_Uname (Name : access Utsname) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "uname";

   function Uname_Field (Selector : Positive) return String is
      Info : aliased Utsname;
   begin
      if C_Uname (Info'Access) /= Interfaces.C.int'(0) then
         return "";
      end if;

      case Selector is
         when 1 =>
            return To_Ada (Info.Sysname);
         when 2 =>
            return To_Ada (Info.Nodename);
         when 3 =>
            return To_Ada (Info.Release);
         when 4 =>
            return To_Ada (Info.Version);
         when 5 =>
            return To_Ada (Info.Machine);
         when others =>
            return "";
      end case;
   exception
      when others =>
         return "";
   end Uname_Field;

   function Current return Kind is
   begin
      return Linux;
   end Current;

   --  Effective, not real: a program run through sudo has the privileges of the
   --  effective id, and the real one still says who invoked it.
   function Is_Elevated return Boolean is
      use type Interfaces.C.unsigned;

      function Geteuid return Interfaces.C.unsigned
        with Import => True, Convention => C, External_Name => "geteuid";
   begin
      return Geteuid = 0;
   end Is_Elevated;

   --  POSIX has no call for this; the locale is an environment convention the
   --  caller reads for itself. See the spec: "" means ask the environment.
   function Native_Locale return String is
   begin
      return "";
   end Native_Locale;

   --  The value of Key in the configuration file at Path: in its Section
   --  ([Section] header), or before any section when Section is "". A value
   --  in one matching pair of quotes is returned without them; "" when the
   --  file or the key is not there, or the file is over the size cap.
   function Locale_File_Value (Path, Section, Key : String) return String is
      use type Ada.Directories.File_Kind;
      use type Ada.Directories.File_Size;
      Max_Bytes : constant := 256 * 1024;
   begin
      if not Ada.Directories.Exists (Path)
        or else Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File
        or else Ada.Directories.Size (Path) > Max_Bytes
      then
         return "";
      end if;
      declare
         File       : Ada.Streams.Stream_IO.File_Type;
         Content    : String (1 .. Natural (Ada.Directories.Size (Path)));
         In_Section : Boolean := Section = "";
         First      : Positive := 1;
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
         begin
            String'Read (Ada.Streams.Stream_IO.Stream (File), Content);
         exception
            when others =>
               Ada.Streams.Stream_IO.Close (File);
               raise;
         end;
         Ada.Streams.Stream_IO.Close (File);
         while First <= Content'Last loop
            declare
               Newline   : constant Natural :=
                 Ada.Strings.Fixed.Index (Content (First .. Content'Last), [1 => ASCII.LF]);
               Line_End  : constant Natural := (if Newline = 0 then Content'Last else Newline - 1);
               --  A CR before the LF (a file saved with Windows line ends) is
               --  not part of the line.
               Line_Last : constant Natural :=
                 (if Line_End >= First and then Content (Line_End) = ASCII.CR then Line_End - 1 else Line_End);
               Trimmed   : constant String :=
                 Ada.Strings.Fixed.Trim
                   ((if Line_Last < First then "" else Content (First .. Line_Last)), Ada.Strings.Both);
               Equals    : constant Natural := Ada.Strings.Fixed.Index (Trimmed, "=");
            begin
               if Trimmed'Length = 0 or else Trimmed (Trimmed'First) in '#' | ';' then
                  null;
               elsif Trimmed'Length > 2
                 and then Trimmed (Trimmed'First) = '['
                 and then Trimmed (Trimmed'Last) = ']'
               then
                  In_Section := Trimmed (Trimmed'First + 1 .. Trimmed'Last - 1) = Section;
               elsif In_Section and then Equals > 0
                 and then Ada.Strings.Fixed.Trim (Trimmed (Trimmed'First .. Equals - 1), Ada.Strings.Both) = Key
               then
                  declare
                     Value : constant String :=
                       (if Equals < Trimmed'Last
                        then Ada.Strings.Fixed.Trim (Trimmed (Equals + 1 .. Trimmed'Last), Ada.Strings.Both)
                        else "");
                  begin
                     --  Shell syntax: LANG="de_DE.UTF-8".
                     if Value'Length >= 2
                       and then Value (Value'First) in '"' | '''
                       and then Value (Value'Last) = Value (Value'First)
                     then
                        return Value (Value'First + 1 .. Value'Last - 1);
                     end if;
                     return Value;
                  end;
               end if;
               exit when Newline = 0;
               First := Newline + 1;
            end;
         end loop;
         return "";
      end;
   exception
      when others =>
         --  A file that cannot be read gives no answer; the next is asked.
         return "";
   end Locale_File_Value;

   function Configured_Format_Locale (Category : Format_Category; Home : String) return String is
      Category_Key : constant String :=
        (case Category is
            when Time_Formats   => "LC_TIME",
            when Number_Formats => "LC_NUMERIC");

      --  The category's key, then LANG, in the file at Path.
      function From (Path, Section : String) return String is
         Own : constant String := (if Path = "" then "" else Locale_File_Value (Path, Section, Category_Key));
      begin
         if Own /= "" or else Path = "" then
            return Own;
         end if;
         return Locale_File_Value (Path, Section, "LANG");
      end From;

      Plasma : constant String :=
        From ((if Home = "" then "" else Home & "/.config/plasma-localerc"), "Formats");
   begin
      if Plasma /= "" then
         return Plasma;
      end if;
      declare
         System_Wide : constant String := From ("/etc/locale.conf", "");
      begin
         if System_Wide /= "" then
            return System_Wide;
         end if;
      end;
      return From ("/etc/default/locale", "");
   end Configured_Format_Locale;

   ------------------------
   -- Executable_Path --
   ------------------------

   function Executable_Path return String is
   begin
      --  procfs resolves symbolic links and survives a PATH lookup. It is
      --  absent in a chroot or a container built without /proc, which is why
      --  an empty answer is expected rather than exceptional.
      if Ada.Directories.Exists ("/proc/self/exe") then
         begin
            return Ada.Directories.Full_Name ("/proc/self/exe");
         exception
            when others =>
               return "";
         end;
      end if;

      return "";
   end Executable_Path;

   --  POSIX names the predicate isatty and numbers the streams zero, one and
   --  two. A descriptor that is closed or not a terminal answers zero, and an
   --  error answers zero as well, which is the answer this wants either way.
   function C_Isatty (Descriptor : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "isatty";

   -----------------
   -- Is_Terminal --
   -----------------

   function Is_Terminal (Stream : Stream_Kind) return Boolean is
      Descriptor : constant Interfaces.C.int :=
        (case Stream is
            when Standard_Input  => 0,
            when Standard_Output => 1,
            when Standard_Error  => 2);
   begin
      return C_Isatty (Descriptor) = 1;
   exception
      when others =>
         return False;
   end Is_Terminal;

   function C_Getpid return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "getpid";

   ---------------------
   -- Own_Process_Id --
   ---------------------

   function Own_Process_Id return Integer is
   begin
      return Integer (C_Getpid);
   end Own_Process_Id;

   function System_Name return String is
   begin
      return Uname_Field (1);
   end System_Name;

   function Node_Name return String is
   begin
      return Uname_Field (2);
   end Node_Name;

   function Set_Node_Name (Name : String) return Boolean is
      Raw : Interfaces.C.char_array := Interfaces.C.To_C (Name, Append_Nul => False);

      function C_Sethostname
        (Name : System.Address;
         Size : Interfaces.C.size_t)
         return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "sethostname";
   begin
      if Name = "" then
         return False;
      end if;

      return C_Sethostname (Raw'Address, Raw'Length) = 0;
   exception
      when others =>
         return False;
   end Set_Node_Name;

   function Release_Name return String is
   begin
      return Uname_Field (3);
   end Release_Name;

   function Version_Name return String is
   begin
      return Uname_Field (4);
   end Version_Name;

   function Machine_Name return String is
   begin
      return Uname_Field (5);
   end Machine_Name;

   function Login_Name return String is
      Buffer : aliased Interfaces.C.char_array (1 .. 256) := [others => Interfaces.C.nul];

      function Getlogin_R
        (Name : System.Address;
         Size : Interfaces.C.size_t)
         return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "getlogin_r";
   begin
      if Getlogin_R (Buffer'Address, Buffer'Length) = 0 then
         return Interfaces.C.To_Ada (Buffer);
      end if;

      return "";
   exception
      when others =>
         return "";
   end Login_Name;

   -----------------------
   -- Usable_Processors --
   -----------------------

   function Usable_Processors (Set : out Processor_Set) return Boolean is
      use type Interfaces.Unsigned_64;

      --  The kernel's mask, a bit a processor, a word of sixty-four at a
      --  time: glibc's cpu_set_t at its default size.
      type Mask is array (0 .. Most_Processors / 64 - 1) of Interfaces.Unsigned_64
        with Convention => C;

      function sched_getaffinity
        (Pid : Interfaces.C.int; Size : Interfaces.C.size_t; Into : System.Address)
         return Interfaces.C.int
        with Import, Convention => C, External_Name => "sched_getaffinity";

      Bits : Mask := [others => 0];
      Any  : Boolean := False;
   begin
      Set := [others => False];
      if sched_getaffinity (0, Interfaces.C.size_t (Bits'Size / 8), Bits'Address) /= 0 then
         return False;
      end if;
      for Index in Set'Range loop
         Set (Index) :=
           (Interfaces.Shift_Right (Bits (Index / 64), Index mod 64) and 1) = 1;
         Any := Any or else Set (Index);
      end loop;
      --  A mask with nothing in it is not one a running process can have.
      if not Any then
         Set := [others => False];
      end if;
      return Any;
   end Usable_Processors;

   function Has_Window_Server return Boolean is
     ((Ada.Environment_Variables.Exists ("DISPLAY") and then Ada.Environment_Variables.Value ("DISPLAY") /= "")
      or else (Ada.Environment_Variables.Exists ("WAYLAND_DISPLAY")
               and then Ada.Environment_Variables.Value ("WAYLAND_DISPLAY") /= ""));

end Hostkit.Host;
