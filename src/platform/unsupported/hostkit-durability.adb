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

   --  An unknown host cannot say the room is had.
   function Reserve_Space (Path : String; Length : Long_Long_Integer) return Outcome is
      pragma Unreferenced (Path, Length);
   begin
      return Not_Supported;
   end Reserve_Space;

   function Sync_Mapping
     (Start : System.Address; Length : Long_Long_Integer) return Outcome
   is
      pragma Unreferenced (Start, Length);
   begin
      return Not_Supported;
   end Sync_Mapping;

end Hostkit.Durability;
