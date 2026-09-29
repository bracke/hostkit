package body Hostkit.Durability is

   --  An unknown host cannot say the data is on the device.

   function Sync_File (Path : String) return Outcome is
      pragma Unreferenced (Path);
   begin
      return Not_Supported;
   end Sync_File;

   function Sync_Directory (Path : String) return Outcome is
      pragma Unreferenced (Path);
   begin
      return Not_Supported;
   end Sync_Directory;

end Hostkit.Durability;
