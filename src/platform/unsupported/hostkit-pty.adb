package body Hostkit.Pty is

   --  A host this build does not know. Is_Supported is False, so a consumer
   --  degrades on the question rather than on a failed Open.

   function Is_Supported return Boolean is
   begin
      return False;
   end Is_Supported;

   function Open (Item : out Pair) return Boolean is
   begin
      Item := (Controller => Hostkit.Descriptors.Invalid,
               Device     => Hostkit.Descriptors.Invalid);
      return False;
   end Open;

   function Device_Name (Item : Pair) return String is
      pragma Unreferenced (Item);
   begin
      return "";
   end Device_Name;

   procedure Close (Item : in out Pair) is
   begin
      Hostkit.Descriptors.Close (Item.Controller);
      Hostkit.Descriptors.Close (Item.Device);
   end Close;

   function Set_Size
     (Item : Pair;
      To   : Hostkit.Terminal_Control.Window_Size) return Boolean
   is
      pragma Unreferenced (Item, To);
   begin
      return False;
   end Set_Size;

end Hostkit.Pty;
