package body Hostkit.Lease_Files is
   function Create (Path : String; Item : out Lease) return Open_Outcome is
      pragma Unreferenced (Path);
   begin
      Item := (Handle => -1, Held => False);
      return Unsupported;
   end Create;

   function Open
     (Path : String; Kind : Lock_Kind; Writable : Boolean;
      Item : out Lease) return Open_Outcome
   is
      pragma Unreferenced (Path, Kind, Writable);
   begin
      Item := (Handle => -1, Held => False);
      return Unsupported;
   end Open;

   procedure Release (Item : in out Lease) is
   begin
      Item.Handle := -1;
      Item.Held := False;
   end Release;

   function Is_Held (Item : Lease) return Boolean is (Item.Held);

   function Write_At
     (Item : Lease; Data : Ada.Streams.Stream_Element_Array;
      Offset : Ada.Streams.Stream_Element_Offset := 0) return Boolean
   is
      pragma Unreferenced (Item, Data, Offset);
   begin
      return False;
   end Write_At;

   function Read_At
     (Item : Lease; Data : out Ada.Streams.Stream_Element_Array;
      Offset : Ada.Streams.Stream_Element_Offset := 0) return Boolean
   is
      pragma Unreferenced (Item, Offset);
   begin
      Data := [others => 0];
      return False;
   end Read_At;

   function Size (Item : Lease) return Long_Long_Integer is
      pragma Unreferenced (Item);
   begin
      return -1;
   end Size;

   function Identity (Item : Lease) return Lease_Identity is
      pragma Unreferenced (Item);
   begin
      return (others => <>);
   end Identity;

   function Path_Matches (Item : Lease; Path : String) return Boolean is
      pragma Unreferenced (Item, Path);
   begin
      return False;
   end Path_Matches;
end Hostkit.Lease_Files;
