with Ada.Strings.UTF_Encoding;
with Ada.Strings.UTF_Encoding.Conversions;
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

   function Value (Name : String; Found : out Boolean) return String is
      Wide_Name : aliased constant Wide_String :=
        Ada.Strings.UTF_Encoding.Conversions.Convert (Name) & Wide_Character'Val (0);
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
         return Ada.Strings.UTF_Encoding.Conversions.Convert
           (Buffer (1 .. Natural (Length)), Output_Scheme => Ada.Strings.UTF_Encoding.UTF_8);
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

end Hostkit.Environment;
