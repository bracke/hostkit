with Interfaces.C;
with System;

package body Hostkit.Host is

   function Current return Kind is
   begin
      return Windows;
   end Current;

   --  Windows has no root. An administrator's process runs with a filtered
   --  token unless it was elevated, so membership of the Administrators group
   --  is not the question -- whether this token is elevated is.
   function Is_Elevated return Boolean is
      use type Interfaces.C.int;
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

end Hostkit.Host;
