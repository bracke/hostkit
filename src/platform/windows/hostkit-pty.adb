package body Hostkit.Pty is

   --  Windows has no pseudo-terminal of this shape.
   --
   --  Its answer is the pseudo-console: CreatePseudoConsole takes a pair of
   --  ordinary pipes and an initial size and hands back an HPCON, which is then
   --  passed to CreateProcess through an attribute list rather than as a
   --  descriptor a child inherits as its standard streams. There is no device
   --  side to hand over, no path to name, and no line discipline to put into raw
   --  mode -- the console host does that work on the far side. It is a different
   --  API with a different shape, not this one under another name, and mapping
   --  it onto Pair would misrepresent both.
   --
   --  So this refuses, and Is_Supported says so in advance. A consumer that
   --  needs a terminal for a child on this host degrades explicitly -- which for
   --  a shell means running the child on ordinary pipes and accepting that it
   --  will line-buffer and will not colour.
   --
   --  Implementing it belongs here when a consumer needs it, and would want its
   --  own type rather than this record.

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
      --  A pseudo-console has no path. Empty is the refusal; a plausible-looking
      --  "CONOUT$" would be a name for something else entirely.
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
