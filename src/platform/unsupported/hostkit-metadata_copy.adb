package body Hostkit.Metadata_Copy is
   function Capture_Times
     (Path : String; Times : out Entry_Times) return Boolean
   is
      pragma Unreferenced (Path);
   begin
      Times := [others => 0];
      return False;
   end Capture_Times;

   function Apply_Times
     (Path : String; Times : Entry_Times) return Boolean
   is
      pragma Unreferenced (Path, Times);
   begin
      return False;
   end Apply_Times;

   function Capture (Path : String) return Snapshot is
      pragma Unreferenced (Path);
   begin
      return No_Snapshot;
   end Capture;

   function Is_Available (Item : Snapshot) return Boolean is (Item.Available);
   function Link_Count (Item : Snapshot) return Interfaces.Unsigned_64 is (Item.Links);

   procedure Set_Times (Item : in out Snapshot; Times : Entry_Times) is
   begin
      Item.Times := Times;
   end Set_Times;

   function Apply
     (Item : Snapshot; Path : String; Preserve_Ownership : Boolean)
      return Boolean
   is
      pragma Unreferenced (Item, Path, Preserve_Ownership);
   begin
      return False;
   end Apply;
end Hostkit.Metadata_Copy;
