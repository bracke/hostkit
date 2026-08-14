with Ada.Directories;
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

end Hostkit.Host;
