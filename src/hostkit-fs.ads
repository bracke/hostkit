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

end Hostkit.Fs;
