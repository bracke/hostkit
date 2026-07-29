--  Handing a file to the desktop's own trash.
--
--  Two hosts have one and it is a call: the Windows shell's Recycle Bin
--  (SHFileOperationW with FOF_ALLOW_UNDO), and macOS's Finder trash. Linux does
--  not. What Linux has instead is the freedesktop.org trash specification, which
--  is not an API at all but a filesystem layout -- a files/ directory, an info/
--  directory, and a .trashinfo sidecar per item, with rules about naming and
--  which volume the trash lives on. That is a format, so it belongs to the
--  program implementing it and not here; Available answers False on Linux and
--  the caller does the freedesktop work itself.
--
--  So this is deliberately not "trash a file on any host". It is "does this host
--  have a trash of its own, and if so, put this in it" -- and a caller must have
--  its own answer for when it does not.
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
   --  The shell owns the item afterwards and does not say where it went, so
   --  there is no path to hand back -- which is also why a caller cannot offer
   --  an undo for this the way it can for a move it performed itself.
   --
   --  @param Path The file or directory to trash.
   --  @return True when the host took it. False when it refused, and on a host
   --          with no trash of its own, where nothing was attempted and the file
   --          is untouched.
   function Move_To_Trash (Path : String) return Boolean;

end Hostkit.Trash;
