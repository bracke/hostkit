package body Hostkit.Local_Channel is

   --  An unknown host: no local endpoint we know how to reach.
   function Connect (Path : String; Item : out Channel) return Boolean is
      pragma Unreferenced (Path);
   begin
      Item.Open := False;
      Item.Native := Invalid;
      return False;
   end Connect;

   function Is_Open (Item : Channel) return Boolean is
   begin
      return Item.Open;
   end Is_Open;

   function Send
     (Item : in out Channel;
      Data : Ada.Streams.Stream_Element_Array)
      return Boolean
   is
      pragma Unreferenced (Item, Data);
   begin
      return False;
   end Send;

   function Receive
     (Item : in out Channel;
      Data : out Ada.Streams.Stream_Element_Array)
      return Boolean
   is
      pragma Unreferenced (Item);
   begin
      Data := [Data'Range => 0];
      return False;
   end Receive;

   procedure Close (Item : in out Channel) is
   begin
      Item.Open := False;
      Item.Native := Invalid;
   end Close;

end Hostkit.Local_Channel;
