with GNAT.OS_Lib;
with Interfaces.C;

--  Lending a directory its owner's write bit for the length of a rename.
--
--  Renaming a directory to another parent rewrites its ".." entry, which POSIX
--  allows only when the directory itself is writable -- so moving a read-only
--  directory you own fails although you could chmod it and try again. Doing
--  that by path chmods whatever the path names by then. Here the directory is
--  opened once without following a link, its owner and mode are read from
--  that descriptor, and the mode is changed and restored through it: Linux
--  holds an O_PATH descriptor and chmods its /proc/self/fd entry (fchmod
--  refuses O_PATH), macOS holds an O_EVTONLY descriptor and fchmods it.
--  Windows has no such rule and nothing to lend, so Prepare there is a no-op.
package Hostkit.Directory_Write_Access is

   type Context is limited private;

   --  Temporarily make a directory owner-writable for a rename, retaining the
   --  descriptor-bound original mode for restoration. Nothing is changed for
   --  a link, a non-directory, a directory owned by another account, or one
   --  that is already owner-writable.
   --  @param Path Directory that the upcoming rename must traverse.
   --  @param State Held restoration state; released by Finish or Release.
   --  @return True when the path is ready or required no temporary change.
   function Prepare (Path : String; State : in out Context) return Boolean;

   --  Restore the mode captured by Prepare and release the held descriptor.
   --  @param State Restoration state returned by Prepare.
   --  @return True when restoration succeeded or no restoration was needed.
   function Finish (State : in out Context) return Boolean;

   --  Release held state without attempting a mode restoration.
   --  @param State Restoration state to discard.
   procedure Release (State : in out Context);

private
   type Context is limited record
      Descriptor : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Mode       : Interfaces.C.unsigned := 0;
      Restore    : Boolean := False;
   end record;
end Hostkit.Directory_Write_Access;
