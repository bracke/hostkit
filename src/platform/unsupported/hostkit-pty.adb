package body Hostkit.Pty is

   --  A host this build does not know. Is_Supported is False, so a consumer
   --  degrades on the question rather than on a failed Open.

   ---------------------------
   -- Write_Fails_When_Unheld --
   ---------------------------

   --  There are no terminals here to write to, so this is the refusal every
   --  other answer in this body is: a caller who got here has nothing to ask
   --  about.
   function Write_Fails_When_Unheld return Boolean is (False);

   function Is_Supported return Boolean is
   begin
      return False;
   end Is_Supported;

   function Open (Item : out Pair) return Boolean is
   begin
      Item := (others => <>);
      return False;
   end Open;

   function Device_Name (Item : Pair) return String is
      pragma Unreferenced (Item);
   begin
      return "";
   end Device_Name;

   function Attach (Item : Pair; To : in out Hostkit.Spawn.Options)
                    return Boolean
   is
      pragma Unreferenced (Item, To);
   begin
      --  Nothing to attach. Open refused, so there is no pair to have got here
      --  with, and filling anything in would be inventing a terminal.
      return False;
   end Attach;

   procedure Close_Device (Item : in out Pair) is
   begin
      Hostkit.Descriptors.Close (Item.Device);
   end Close_Device;

   procedure Close (Item : in out Pair) is
   begin
      Hostkit.Descriptors.Close (Item.To_Child);
      Hostkit.Descriptors.Close (Item.From_Child);
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
