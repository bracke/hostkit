with Ada.Directories;
with Interfaces.C;

package body Hostkit.Host is

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
      use type Interfaces.C.int;

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

end Hostkit.Host;
