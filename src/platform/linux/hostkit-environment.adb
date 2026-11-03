with Ada.Environment_Variables;

package body Hostkit.Environment is

   function Value (Name : String; Found : out Boolean) return String is
   begin
      Found := Name /= "" and then Ada.Environment_Variables.Exists (Name);
      return (if Found then Ada.Environment_Variables.Value (Name) else "");
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
