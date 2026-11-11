with Ada.Strings.Unbounded;

package body Hostkit.Trash is
   use Ada.Strings.Unbounded;

   --  Linux has no host trash to call. The desktops implement the
   --  freedesktop.org trash specification instead, which is a filesystem layout
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

   --  Nothing is attempted here, so nothing is held.
   function Can_Hold (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Can_Hold;

   --  No Recycle Bin here: nothing is moved, listed, restored or purged.
   function Move_To_Recycle_Bin
     (Path          : String;
      Recycled_Path : out UString;
      Info_Path     : out UString)
      return Recycle_Outcome
   is
      pragma Unreferenced (Path);
   begin
      Recycled_Path := Null_Unbounded_String;
      Info_Path := Null_Unbounded_String;
      return Recycle_Unsupported;
   end Move_To_Recycle_Bin;

   function Recycle_Bin_Folder (Path : String) return String is
      pragma Unreferenced (Path);
   begin
      return "";
   end Recycle_Bin_Folder;

   function Primary_Recycle_Bin_Folder return String is ("");

   function Recycle_Bin_Folders return String_Vectors.Vector is (String_Vectors.Empty_Vector);

   function Recycle_Bin_Entries (Volume : String := "") return Recycle_Bin_Entry_Vectors.Vector is
      pragma Unreferenced (Volume);
   begin
      return Recycle_Bin_Entry_Vectors.Empty_Vector;
   end Recycle_Bin_Entries;

   function Is_Recycled_Item (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Is_Recycled_Item;

   function Entry_Of (Recycled_Path : String; Item : out Recycle_Bin_Entry) return Boolean is
      pragma Unreferenced (Recycled_Path);
   begin
      Item := (others => <>);
      return False;
   end Entry_Of;

   function Restore (Recycled_Path : String; Destination : String := "") return Restore_Outcome is
      pragma Unreferenced (Recycled_Path, Destination);
   begin
      return Restore_Unsupported;
   end Restore;

   function Purge (Recycled_Path : String) return Boolean is
      pragma Unreferenced (Recycled_Path);
   begin
      return False;
   end Purge;

end Hostkit.Trash;
