with Ada.Strings.Unbounded;

--  Facts about a path that the host answers differently -- and that GNAT gets wrong on
--  Windows without saying so.
package Hostkit.Fs is

   --  Is this path a link?
   --
   --  GNAT.OS_Lib.Is_Symbolic_Link answers False for every path on Windows: it wants an
   --  lstat, and there is none, so it says "not a link" rather than "I cannot tell".
   --  That made every link invisible -- to a file manager that showed none, and to a
   --  Delete_Tree that followed them out of the tree it was deleting.
   --
   --  Windows has links: a symbolic link and a junction are both reparse points, and
   --  that is what is asked here.
   function Is_Link (Path : String) return Boolean;

   --  Create a symbolic link at Link_Path pointing at Target.
   --
   --  False when the host will not: Windows needs Developer Mode or a privilege, and
   --  refusing is a normal answer there, not an error.
   function Create_Link
     (Target    : String;
      Link_Path : String)
      return Boolean;

   --  Will this host run this file?
   --
   --  GNAT.OS_Lib.Is_Executable_File answers True for every file that exists on
   --  Windows -- and for a directory. An open action pointing at a directory passed its
   --  preflight and was launched.
   --
   --  POSIX asks the mode bits. Windows does not have the concept: every ordinary file
   --  carries FILE_EXECUTE in its DACL, so the bit says nothing, and what runs is
   --  decided by the extension. A chmod +x "run.sh" is an executable on one and a plain
   --  file on the other, and both answers are right.
   function Is_Executable (Path : String) return Boolean;

   --  Can anyone but the owner get at this file?
   --
   --  A private key must not be. OpenSSH refuses one whose file is group- or world-readable,
   --  and this is the fact that check needs: on POSIX, whether any group or other permission
   --  bit is set (mode and 8#077#). It answers for a regular file only -- a directory's bits
   --  mean something else -- and False for anything it cannot read, so a missing file is
   --  "not exposed" rather than a spurious rejection.
   --
   --  On Windows there are no such bits; access is by ACL, and a file in the user's profile
   --  is already owner-scoped by the default ACL. This does not read the ACL, so it answers
   --  False there -- it does not enforce the check on Windows, it declines to guess.
   function Accessible_By_Others (Path : String) return Boolean;

   --  Atomically replace Target with Source (a completed temp file), on one filesystem.
   --
   --  An atomic write ends by renaming the temp file over the real one. POSIX rename does
   --  that in a single step even when Target already exists; Windows rename -- and
   --  GNAT.OS_Lib.Rename_File with it -- fails when it does, so rewriting a file that was
   --  already there reported a write failure. This asks the host for a replacing rename:
   --  rename on POSIX, MoveFileEx with MOVEFILE_REPLACE_EXISTING on Windows.
   --
   --  @return True when Target now holds what Source held and Source is gone.
   function Replace_File
     (Source : String;
      Target : String)
      return Boolean;

   --  Read the literal target of the symbolic link (or junction) at Path.
   --
   --  POSIX has readlink. Windows has no such call: a link is a reparse point, so this
   --  opens it without following (FILE_FLAG_OPEN_REPARSE_POINT) and reads the target out
   --  of the reparse data. GNAT offers nothing here -- its own reader is a Windows stub
   --  that always fails, which made a scanner treat every Windows link as broken.
   --
   --  @return False when Path is not a link or the target cannot be read; Target is then
   --          empty. On success Target holds the link's own target text.
   function Read_Link_Target
     (Path   : String;
      Target : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean;

   --  Remove the link at Path -- the link itself, never what it points at.
   --
   --  A link to a directory is a link on POSIX and a directory on Windows, and the two
   --  hosts remove it with different calls: unlink there, RemoveDirectoryW here for a
   --  directory reparse point and DeleteFileW for any other. Ada.Directories.Delete_File
   --  is the file call on both, so a Windows directory symlink refused it -- and, having
   --  asked a stat that followed the link, reported the refusal as "file does not exist".
   --
   --  Not following is the point. The target is someone else's -- often deliberately
   --  outside the tree being cleared -- and a caller that followed the link would delete
   --  it. This removes a link or nothing.
   --
   --  @return True when the link is gone. False when Path is not a link (a regular file
   --          or directory is left alone) or the host refused to remove it.
   function Delete_Link (Path : String) return Boolean;

   --  Resolve Path to its canonical absolute form, following symbolic links and
   --  reparse points -- POSIX realpath, Windows GetFinalPathNameByHandleW.
   --  Ada.Directories.Full_Name cannot be used: on POSIX it resolves links, but on
   --  Windows it is GetFullPathName (purely lexical, does not follow reparse points).
   --  @return Empty string if Path cannot be resolved; otherwise the resolved path
   --          (on Windows with the \\?\ and \\?\UNC\ prefix stripped).
   function Real_Path (Path : String) return String;

end Hostkit.Fs;
