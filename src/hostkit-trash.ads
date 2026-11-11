with Ada.Calendar;
with Ada.Containers.Vectors;
with Interfaces;

--  Handing a file to the desktop's own trash.
--
--  Two hosts have one and it is a call: the Windows shell's Recycle Bin
--  (IFileOperation with FOFX_RECYCLEONDELETE), and macOS's Finder trash. Linux
--  does not. What Linux has instead is the freedesktop.org trash specification,
--  which is not an API at all but a filesystem layout -- a files/ directory, an
--  info/ directory, and a .trashinfo sidecar per item, with rules about naming
--  and which volume the trash lives on. That is a format, so it belongs to the
--  program implementing it and not here; Available answers False on Linux and
--  the caller does the freedesktop work itself.
--
--  So this is deliberately not "trash a file on any host". It is "does this host
--  have a trash of its own, and if so, put this in it" -- and a caller must have
--  its own answer for when it does not.
--
--  The Recycle Bin is also a layout, under the shell's API: each fixed volume
--  has a $Recycle.Bin folder with a folder per user (named by the user's SID),
--  and an item recycled there is renamed to $R<6 characters><extension> beside a
--  $I file of the same suffix that records where it came from, when and how big
--  it was. Because the layout is the host's own and the same for every program,
--  this package reads it too: Move_To_Recycle_Bin says where the item went, and
--  Recycle_Bin_Entries, Restore and Purge let a caller show, restore and empty
--  the bin as Explorer does. On other hosts they find nothing and do nothing.
--
--  DO NOT SUBSTITUTE A DELETE. Available => False means the host would not take
--  the file, never that the file should go. The whole value of a trash is that
--  the user can change their mind, and a caller that fell back to unlinking
--  would turn a recoverable action into an unrecoverable one at exactly the
--  moment the recoverable one was unavailable.
package Hostkit.Trash is

   --  What this host's trash is. The names and flags are for a caller that
   --  reports what it is about to do -- "Move to Recycle Bin" rather than "Move
   --  to Trash" -- and for diagnostics; Available is the truth about whether it
   --  works.
   type Facility is record
      --  Is there a host trash here that this crate can drive?
      Available : Boolean := False;

      --  The host call behind it, or "" where there is none. Diagnostics.
      Api_Name : UString;

      --  Windows calls its trash the Recycle Bin and users expect that name.
      Uses_Recycle_Bin : Boolean := False;

      --  Does the item keep its timestamps and permissions on the way in?
      Preserves_Metadata : Boolean := False;

      --  Will the host put a prompt in front of the user? Neither of the
      --  current two does -- both are asked to stay silent -- but a caller that
      --  drives its own progress UI needs to know it is not about to be
      --  interrupted.
      Requires_User_Consent : Boolean := False;
   end record;

   --  What this host offers, asked of the body the build selected.
   function Current return Facility;

   --  Put Path in the host's trash.
   --
   --  On Windows this is Move_To_Recycle_Bin without the answer of where the
   --  item went; on macOS the Finder's trash, which does not say.
   --
   --  @param Path The file or directory to trash.
   --  @return True when the host took it. False when it refused, and on a host
   --          with no trash of its own, where nothing was attempted and the file
   --          is untouched.
   function Move_To_Trash (Path : String) return Boolean;

   --  Whether Move_To_Trash would keep Path, so it can be restored, rather
   --  than refuse it or destroy it. Windows answers False for a path on a
   --  network share, a removable or optical drive, or a volume without a
   --  Recycle Bin: asked to recycle there, the shell deletes the item for
   --  good. A host with no trash of its own answers False.
   --
   --  @param Path The file or directory to be trashed.
   --  @return True when the host's trash would hold Path.
   function Can_Hold (Path : String) return Boolean;

   --  What became of a move into the Recycle Bin.
   type Recycle_Outcome is
     (
      --  In the bin; Recycled_Path and Info_Path name its $R item and $I file.
      Recycled,

      --  This host has no Recycle Bin. Nothing was attempted.
      Recycle_Unsupported,

      --  Path's volume has no Recycle Bin (a share, a removable drive), where
      --  the shell would destroy the item. Nothing was attempted.
      Recycle_Volume_Unavailable,

      --  A path the shell cannot take (past 259 characters) goes into the
      --  bin's folder directly, and that folder -- the current user's, on
      --  Path's volume -- does not exist yet. It is the shell's to create (it
      --  does on the first recycle there), so nothing was attempted.
      Recycle_Bin_Missing,

      --  That folder holds a $I file of a version newer than this package
      --  writes, so an item put there by hand might not be one the shell
      --  reads. Nothing was attempted.
      Recycle_Bin_Newer_Format,

      --  The host refused: Path is missing, in use, not ours to move, or the
      --  shell would have deleted it for good rather than recycled it. The
      --  item is where it was.
      Recycle_Refused);

   --  Move Path into the Recycle Bin of its volume and say where it went.
   --
   --  The shell does the move (IFileOperation, which reports the item it made
   --  in the bin) for every path it can take; a longer one -- which the shell
   --  cannot name -- is renamed into the current user's bin folder on the same
   --  volume, beside a $I file written the way the shell writes one, so that
   --  Explorer lists and restores it like any other. Either way the item never
   --  leaves its volume and is never deleted.
   --
   --  @param Path The file or directory to recycle (absolute).
   --  @param Recycled_Path Where the item is now, its $R path, or "" when not
   --    Recycled -- and, Recycled, in the one case the shell took the item
   --    without saying where and no $I record in the bin names it.
   --  @param Info_Path The $I file that records it, or "" when not Recycled.
   --  @return What became of the request.
   function Move_To_Recycle_Bin
     (Path          : String;
      Recycled_Path : out UString;
      Info_Path     : out UString)
      return Recycle_Outcome;

   --  An item in the current user's Recycle Bin, as its $I file records it.
   type Recycle_Bin_Entry is record
      --  The item itself, $R... in the bin folder.
      Recycled_Path : UString;

      --  Its $I file.
      Info_Path : UString;

      --  Where it was recycled from, without any \\?\ prefix.
      Original_Path : UString;

      --  When it was recycled, when Deleted_Known.
      Deleted       : Ada.Calendar.Time := Ada.Calendar.Time_Of (1901, 1, 1);
      Deleted_Known : Boolean := False;

      --  Its size in bytes as recorded: a file's size, a folder's total.
      Size : Interfaces.Integer_64 := 0;
   end record;

   package Recycle_Bin_Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Recycle_Bin_Entry);

   --  The current user's Recycle Bin folder on Path's volume
   --  (<volume>\$Recycle.Bin\<SID>), when it exists.
   --
   --  @param Path Any path on the volume.
   --  @return The folder, or "" when there is none or the host has no bin.
   function Recycle_Bin_Folder (Path : String) return String;

   --  The bin folder a caller shows as "the" Recycle Bin: the one on the
   --  Windows system drive, else the first fixed drive's that exists.
   --
   --  @return The folder, or "" when there is none or the host has no bin.
   function Primary_Recycle_Bin_Folder return String;

   --  The current user's bin folders on every fixed drive, in drive order,
   --  each one that exists.
   --
   --  @return The folders; empty where the host has no bin.
   function Recycle_Bin_Folders return String_Vectors.Vector;

   --  What the current user's Recycle Bin holds, read from the $I files of
   --  their bin folder on each fixed drive (or on Volume's drive only). An
   --  entry whose $R item is gone, or whose $I file cannot be read, is left
   --  out, as Explorer leaves it out.
   --
   --  @param Volume Any path on the one volume to list, or "" for all.
   --  @return The entries, in no particular order; empty elsewhere.
   function Recycle_Bin_Entries (Volume : String := "") return Recycle_Bin_Entry_Vectors.Vector;

   --  Whether Path is an item in one of the current user's bin folders: a
   --  $R... name directly in <volume>\$Recycle.Bin\<their SID>.
   --
   --  @param Path The path to test.
   --  @return True for such an item, whether or not it still exists.
   function Is_Recycled_Item (Path : String) return Boolean;

   --  The entry for one item in the bin, read from its $I file.
   --
   --  @param Recycled_Path The item's $R path.
   --  @param Item The entry, when found.
   --  @return True when Recycled_Path is a recycled item with a readable $I.
   function Entry_Of (Recycled_Path : String; Item : out Recycle_Bin_Entry) return Boolean;

   --  What became of a restore.
   type Restore_Outcome is
     (
      --  Back at its original path; its $I file is gone.
      Restored,

      --  Something is at the original path already. Nothing was moved:
      --  Explorer asks before replacing, and this never replaces.
      Restore_Taken,

      --  Recycled_Path is not an item in the current user's bin, or its $I
      --  file is missing or unreadable.
      Restore_Not_In_Bin,

      --  This host has no Recycle Bin.
      Restore_Unsupported,

      --  The host refused the move (in use, no permission, another volume).
      Restore_Failed);

   --  Put a recycled item back where it was, as Explorer's Restore does: to
   --  its original path, recreating the folders on the way there that have
   --  gone since, never over anything that took its place.
   --
   --  @param Recycled_Path The item's $R path.
   --  @param Destination Where to put it instead of the recorded original
   --    path, or "" for that path.
   --  @return What became of the request.
   function Restore (Recycled_Path : String; Destination : String := "") return Restore_Outcome;

   --  Delete a recycled item for good, with its $I file, as Explorer's
   --  Delete in the bin does. A folder goes with everything in it; a link
   --  is removed, never followed.
   --
   --  @param Recycled_Path The item's $R path.
   --  @return True when the item is gone (its $I file is removed too, or
   --    was already).
   function Purge (Recycled_Path : String) return Boolean;

end Hostkit.Trash;
