with Interfaces;

with Hostkit.Metadata;

--  A host with modes and no share modes: nothing can hold a file against
--  writers here, and read-only is a mode without a write bit.
package body Hostkit_Test_Native is

   function Hold_Against_Writers (Path : String; Held : out Exclusive_Hold) return Boolean is
      pragma Unreferenced (Path);
   begin
      Held.Handle := System.Null_Address;
      return False;
   end Hold_Against_Writers;

   procedure Release (Held : in out Exclusive_Hold) is
   begin
      Held.Handle := System.Null_Address;
   end Release;

   function Is_Read_Only (Path : String) return Boolean is
      use type Interfaces.Unsigned_32;
      Write_Bits : constant Interfaces.Unsigned_32 := 8#222#;
      Available  : Boolean;
      Bits       : constant Natural := Hostkit.Metadata.File_Permission_Bits (Path, Available);
   begin
      return Available and then (Interfaces.Unsigned_32 (Bits) and Write_Bits) = 0;
   end Is_Read_Only;

end Hostkit_Test_Native;
