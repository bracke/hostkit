with Ada.Strings.Unbounded;

with Interfaces.C;
with System;

package body Hostkit.Host is
   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;

   function GetUserDefaultLocaleName
     (Locale_Name : System.Address;
      Locale_Size : Interfaces.C.int)
      return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "GetUserDefaultLocaleName";

   function Current return Kind is
   begin
      return Windows;
   end Current;

   --  Windows has no root. An administrator's process runs with a filtered
   --  token unless it was elevated, so membership of the Administrators group
   --  is not the question -- whether this token is elevated is.
   function Is_Elevated return Boolean is
      use type Interfaces.C.unsigned_long;
      use type System.Address;

      subtype C_DWord is Interfaces.C.unsigned_long;

      Token_Query     : constant C_DWord := 16#0008#;
      Token_Elevation : constant Interfaces.C.int := 20;

      function Get_Current_Process return System.Address
        with Import => True, Convention => Stdcall,
             External_Name => "GetCurrentProcess";

      function Open_Process_Token
        (Process : System.Address;
         Access_Way : C_DWord;
         Token : access System.Address)
         return Interfaces.C.int
        with Import => True, Convention => Stdcall,
             External_Name => "OpenProcessToken";

      function Get_Token_Information
        (Token       : System.Address;
         Class       : Interfaces.C.int;
         Information : System.Address;
         Length      : C_DWord;
         Returned    : access C_DWord)
         return Interfaces.C.int
        with Import => True, Convention => Stdcall,
             External_Name => "GetTokenInformation";

      function Close_Handle (Handle : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

      Token     : aliased System.Address := System.Null_Address;
      Elevated  : aliased C_DWord := 0;
      Returned  : aliased C_DWord := 0;
      Queried   : Interfaces.C.int;
      Ignored   : Interfaces.C.int;
   begin
      if Open_Process_Token
           (Get_Current_Process, Token_Query, Token'Access) = 0
      then
         return False;
      end if;

      Queried :=
        Get_Token_Information
          (Token, Token_Elevation, Elevated'Address, 4, Returned'Access);
      Ignored := Close_Handle (Token);

      return Queried /= 0 and then Elevated /= 0;
   end Is_Elevated;

   function Native_Locale return String is
      Buffer : aliased Wide_String (1 .. 85) := [others => Wide_Character'Val (0)];
      Length : constant Interfaces.C.int :=
        GetUserDefaultLocaleName (Buffer'Address, Interfaces.C.int (Buffer'Length));
      Result : Unbounded_String;
   begin
      if Length <= 1 then
         return "";
      end if;

      for Index in Buffer'First .. Buffer'Last loop
         exit when Buffer (Index) = Wide_Character'Val (0);
         if Wide_Character'Pos (Buffer (Index)) <= Character'Pos (Character'Last) then
            Append (Result, Character'Val (Wide_Character'Pos (Buffer (Index))));
         end if;
      end loop;

      return To_String (Result);
   exception
      when others =>
         return "";
   end Native_Locale;

   ------------------------
   -- Executable_Path --
   ------------------------

   function Executable_Path return String is
      function Get_Module_File_Name
        (Module : System.Address;
         Buffer : System.Address;
         Size   : Interfaces.C.unsigned_long)
         return Interfaces.C.unsigned_long
      with Import, Convention => Stdcall,
           External_Name => "GetModuleFileNameA";

      use type Interfaces.C.unsigned_long;

      Buffer : aliased Interfaces.C.char_array (1 .. 4096) :=
        [others => Interfaces.C.nul];
      Filled : Interfaces.C.unsigned_long;
   begin
      --  A null module handle asks for this process's own image.
      Filled :=
        Get_Module_File_Name (System.Null_Address, Buffer'Address, 4096);

      if Filled = 0 or else Filled >= 4096 then
         return "";
      end if;

      return Interfaces.C.To_Ada (Buffer);
   exception
      when others =>
         return "";
   end Executable_Path;

   --  Windows answers through the console API rather than through isatty,
   --  whose C name is spelled _isatty here. GetConsoleMode succeeds only for
   --  a handle that really is a console, which is the question being asked.
   type Handle is new Interfaces.C.ptrdiff_t;

   function Get_Std_Handle (Which : Interfaces.C.unsigned_long) return Handle
   with Import, Convention => Stdcall, External_Name => "GetStdHandle";

   function Get_Console_Mode
     (Item : Handle; Mode : access Interfaces.C.unsigned_long)
      return Interfaces.C.int
   with Import, Convention => Stdcall, External_Name => "GetConsoleMode";

   -----------------
   -- Is_Terminal --
   -----------------

   function Is_Terminal (Stream : Stream_Kind) return Boolean is
      use type Interfaces.C.int;

      --  STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE.
      Which : constant Interfaces.C.unsigned_long :=
        (case Stream is
            when Standard_Input  => 16#FFFF_FFF6#,
            when Standard_Output => 16#FFFF_FFF5#,
            when Standard_Error  => 16#FFFF_FFF4#);

      Mode : aliased Interfaces.C.unsigned_long := 0;
   begin
      return Get_Console_Mode (Get_Std_Handle (Which), Mode'Access) /= 0;
   exception
      when others =>
         return False;
   end Is_Terminal;

   function C_Get_Current_Process_Id return Interfaces.C.unsigned_long
     with Import => True, Convention => Stdcall,
          External_Name => "GetCurrentProcessId";

   ---------------------
   -- Own_Process_Id --
   ---------------------

   function Own_Process_Id return Integer is
   begin
      return Integer (C_Get_Current_Process_Id);
   end Own_Process_Id;

end Hostkit.Host;
