with Hostkit.Windows_Paths;

with Interfaces.C;
with System;

package body Hostkit.Environment is
   use type Interfaces.C.unsigned_long;

   function Get_Environment_Variable_W
     (Name   : System.Address;
      Buffer : System.Address;
      Size   : Interfaces.C.unsigned_long)
      return Interfaces.C.unsigned_long
     with Import, Convention => Stdcall, External_Name => "GetEnvironmentVariableW";

   function Set_Environment_Variable_W
     (Name  : System.Address;
      Value : System.Address)
      return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "SetEnvironmentVariableW";

   --  The C runtime keeps its own copy of the environment, which getenv and
   --  Ada.Environment_Variables read; _wputenv updates it (from wide text,
   --  so nothing is lost on the way) as well as the process's own block.
   function Wide_Put_Env (Assignment : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "_wputenv";

   function Wide_Of (Text : String) return Wide_String is
     (Hostkit.Windows_Paths.From_UTF_8 (Text) & Wide_Character'Val (0));

   function Value (Name : String; Found : out Boolean) return String is
      Wide_Name : aliased constant Wide_String :=
        Hostkit.Windows_Paths.From_UTF_8 (Name) & Wide_Character'Val (0);
      Probe     : aliased Wide_String (1 .. 1);
      Needed    : Interfaces.C.unsigned_long;
   begin
      Found := False;
      if Name = "" then
         return "";
      end if;
      --  The size it needs, NUL included; 0 when it is not set.
      Needed := Get_Environment_Variable_W (Wide_Name'Address, Probe'Address, 0);
      if Needed = 0 then
         return "";
      end if;
      declare
         Buffer : aliased Wide_String (1 .. Natural (Needed));
         Length : constant Interfaces.C.unsigned_long :=
           Get_Environment_Variable_W (Wide_Name'Address, Buffer'Address, Needed);
      begin
         --  Changed in between (longer now, or gone): taken as not set.
         if Length = 0 or else Length >= Needed then
            return "";
         end if;
         Found := True;
         return Hostkit.Windows_Paths.To_UTF_8 (Buffer (1 .. Natural (Length)));
      end;
   exception
      when others =>
         Found := False;
         return "";
   end Value;

   function Value (Name : String; Default : String) return String is
      Found : Boolean;
      Text  : constant String := Value (Name, Found);
   begin
      return (if Found then Text else Default);
   end Value;

   --  Not through Ada.Environment_Variables: the C runtime hands its value
   --  to Windows in the ANSI code page, and Value, reading the wide block,
   --  would get those bytes back as other characters. Both copies are set
   --  from the wide text: the C runtime's, and the process block Value reads.
   procedure Set (Name : String; Value : String) is
      Wide_Name   : aliased constant Wide_String := Wide_Of (Name);
      Wide_Value  : aliased constant Wide_String := Wide_Of (Value);
      Assignment  : aliased constant Wide_String := Wide_Of (Name & "=" & Value);
      Runtime_Set : constant Interfaces.C.int := Wide_Put_Env (Assignment'Address);
      Block_Set   : constant Interfaces.C.int :=
        Set_Environment_Variable_W
          (Wide_Name'Address, (if Value = "" then System.Null_Address else Wide_Value'Address));
      pragma Unreferenced (Runtime_Set, Block_Set);
   begin
      null;
   end Set;

   procedure Clear (Name : String) is
      Wide_Name     : aliased constant Wide_String := Wide_Of (Name);
      Assignment    : aliased constant Wide_String := Wide_Of (Name & "=");
      Runtime_Clear : constant Interfaces.C.int := Wide_Put_Env (Assignment'Address);
      Block_Clear   : constant Interfaces.C.int := Set_Environment_Variable_W (Wide_Name'Address, System.Null_Address);
      pragma Unreferenced (Runtime_Clear, Block_Clear);
   begin
      null;
   end Clear;

end Hostkit.Environment;
