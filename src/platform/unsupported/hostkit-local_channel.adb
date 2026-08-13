with Hostkit.Process;

package body Hostkit.Local_Channel is

   --  An unknown host: no local endpoint we know how to reach.
   function Connect (Path : String; Item : out Channel) return Boolean is
      pragma Unreferenced (Path);
   begin
      Item.Open := False;
      Item.Native := Invalid;
      return False;
   end Connect;

   function Connect_Abstract (Name : String; Item : out Channel) return Boolean is
      pragma Unreferenced (Name);
   begin
      Item.Open := False;
      Item.Native := Invalid;
      return False;
   end Connect_Abstract;

   function Is_Open (Item : Channel) return Boolean is
   begin
      return Item.Open;
   end Is_Open;

   function Wait_Readable
     (Item       : Channel;
      Timeout_MS : Integer)
      return Hostkit.Process.Wait_Outcome
   is
      pragma Unreferenced (Item, Timeout_MS);
   begin
      return Hostkit.Process.Wait_Error;
   end Wait_Readable;

   function Wait_Writable
     (Item       : Channel;
      Timeout_MS : Integer)
      return Hostkit.Process.Wait_Outcome
   is
      pragma Unreferenced (Item, Timeout_MS);
   begin
      return Hostkit.Process.Wait_Error;
   end Wait_Writable;

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

   function Receive_Some
     (Item : in out Channel;
      Data : out Ada.Streams.Stream_Element_Array)
      return Natural
   is
      pragma Unreferenced (Item);
   begin
      Data := [Data'Range => 0];
      return 0;
   end Receive_Some;

   procedure Close (Item : in out Channel) is
   begin
      Item.Open := False;
      Item.Native := Invalid;
   end Close;

end Hostkit.Local_Channel;
