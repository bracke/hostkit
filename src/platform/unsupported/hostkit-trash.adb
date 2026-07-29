with Ada.Strings.Unbounded;

package body Hostkit.Trash is
   use Ada.Strings.Unbounded;

   --  A host Hostkit has no body for is not assumed to have a trash. The desktops implement the
   --  freedesktop.org specification is what a caller can fall back to: a layout
   --  -- $XDG_DATA_HOME/Trash with files/ and info/ directories and a
   --  .trashinfo sidecar per item -- rather than an API. That is a format, and
   --  formats belong to the program that writes them, so this declines and the
   --  caller does that work itself.
   --
   --  Declining is not "delete it": see the note on the spec.
   function Current return Facility is
   begin
      return
        (Available             => False,
         Api_Name              => Null_Unbounded_String,
         Uses_Recycle_Bin      => False,
         Preserves_Metadata    => False,
         Requires_User_Consent => False);
   end Current;

   function Move_To_Trash (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Move_To_Trash;

end Hostkit.Trash;
