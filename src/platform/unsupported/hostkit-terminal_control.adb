package body Hostkit.Terminal_Control is

   --  A host this build does not know. Every answer is a deliberate refusal:
   --  "cannot tell" is not "fine", and a size of zero by zero would be believed.

   function Supports_Foreground_Group return Boolean is
   begin
      return False;
   end Supports_Foreground_Group;

   function Foreground_Group
     (Terminal : Hostkit.Descriptors.Descriptor;
      Group    : out Integer) return Boolean
   is
      pragma Unreferenced (Terminal);
   begin
      Group := -1;
      return False;
   end Foreground_Group;

   function Set_Foreground_Group
     (Terminal : Hostkit.Descriptors.Descriptor;
      Group    : Integer) return Boolean
   is
      pragma Unreferenced (Terminal, Group);
   begin
      return False;
   end Set_Foreground_Group;

   function Save_Mode
     (Terminal : Hostkit.Descriptors.Descriptor;
      Into     : out Mode) return Boolean
   is
      pragma Unreferenced (Terminal);
   begin
      Into := (Bytes => [others => 0], Valid => False);
      return False;
   end Save_Mode;

   function Restore_Mode
     (Terminal : Hostkit.Descriptors.Descriptor;
      From     : Mode) return Boolean
   is
      pragma Unreferenced (Terminal, From);
   begin
      return False;
   end Restore_Mode;

   function Set_Raw (Terminal : Hostkit.Descriptors.Descriptor) return Boolean is
      pragma Unreferenced (Terminal);
   begin
      return False;
   end Set_Raw;

   function Size
     (Terminal : Hostkit.Descriptors.Descriptor;
      Into     : out Window_Size) return Boolean
   is
      pragma Unreferenced (Terminal);
   begin
      Into := (Rows => 0, Columns => 0);
      return False;
   end Size;

   function Set_Size
     (Terminal : Hostkit.Descriptors.Descriptor;
      To       : Window_Size) return Boolean
   is
      pragma Unreferenced (Terminal, To);
   begin
      return False;
   end Set_Size;

   function Supports_Cursor_Control
     (Terminal : Hostkit.Descriptors.Descriptor) return Boolean
   is
      pragma Unreferenced (Terminal);
   begin
      return False;
   end Supports_Cursor_Control;

   function Control
     (Terminal : Hostkit.Descriptors.Descriptor;
      Action   : Cursor_Action;
      Count    : Natural := 1) return Boolean
   is
      pragma Unreferenced (Terminal, Action, Count);
   begin
      return False;
   end Control;

end Hostkit.Terminal_Control;
