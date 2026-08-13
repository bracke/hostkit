with Ada.Directories;
with Interfaces.C;
with System;

package body Hostkit.Host is
   use type System.Address;
   use type Interfaces.C.int;

   type CF_Index is new Interfaces.C.long;
   type CF_String_Encoding is new Interfaces.C.unsigned;

   CF_String_Encoding_UTF8 : constant CF_String_Encoding := 16#0800_0100#;

   function CFLocaleCopyCurrent return System.Address
     with Import, Convention => C, External_Name => "CFLocaleCopyCurrent";

   function CFLocaleGetIdentifier
     (Locale : System.Address)
      return System.Address
     with Import, Convention => C, External_Name => "CFLocaleGetIdentifier";

   function CFStringGetCString
     (Text      : System.Address;
      Buffer    : System.Address;
      Buffer_Len : CF_Index;
      Encoding  : CF_String_Encoding)
      return Interfaces.C.int
     with Import, Convention => C, External_Name => "CFStringGetCString";

   procedure CFRelease
     (Object : System.Address)
     with Import, Convention => C, External_Name => "CFRelease";

   function Current return Kind is
   begin
      return MacOS;
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

   function Native_Locale return String is
      Locale : System.Address := CFLocaleCopyCurrent;
      Buffer : aliased Interfaces.C.char_array (1 .. 128) := [others => Interfaces.C.nul];
      Success : Interfaces.C.int := 0;
   begin
      if Locale = System.Null_Address then
         return "";
      end if;

      declare
         Identifier : constant System.Address := CFLocaleGetIdentifier (Locale);
      begin
         if Identifier /= System.Null_Address then
            Success :=
              CFStringGetCString
                (Identifier,
                 Buffer'Address,
                 CF_Index (Buffer'Length),
                 CF_String_Encoding_UTF8);
         end if;
      end;

      CFRelease (Locale);
      --  Null the handle so the exception handler below cannot release it a
      --  second time if anything after this point (e.g. To_Ada) raises.
      Locale := System.Null_Address;

      if Success = 0 then
         return "";
      end if;

      return Interfaces.C.To_Ada (Buffer);
   exception
      when others =>
         if Locale /= System.Null_Address then
            CFRelease (Locale);
         end if;

         return "";
   end Native_Locale;

   ------------------------
   -- Executable_Path --
   ------------------------

   function Executable_Path return String is
      --  _NSGetExecutablePath writes the path the process was started with,
      --  which may contain symbolic links or relative segments; Full_Name
      --  resolves them.
      function Get_Executable_Path
        (Buffer : System.Address; Size : access Interfaces.C.unsigned_long)
         return Interfaces.C.int
      with Import, Convention => C, External_Name => "_NSGetExecutablePath";

      Room   : aliased Interfaces.C.unsigned_long := 4096;
      Buffer : aliased Interfaces.C.char_array (1 .. 4096) :=
        [others => Interfaces.C.nul];
   begin
      if Get_Executable_Path (Buffer'Address, Room'Access) /= 0 then
         return "";
      end if;

      declare
         Raw : constant String := Interfaces.C.To_Ada (Buffer);
      begin
         if Raw = "" then
            return "";
         end if;
         return Ada.Directories.Full_Name (Raw);
      end;
   exception
      when others =>
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
