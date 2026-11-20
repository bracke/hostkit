--  Owner-only files and directories, including the host ACL work that chmod
--  alone does not express.
--
--  What this makes private on a volume that keeps access control,
--  Hostkit.Metadata.Private_To_Current_User calls private. On Windows that
--  means the entry ends owned by the process token's user, with a protected
--  DACL of one ACE (full access for OWNER RIGHTS): an elevated process,
--  whose default owner is Administrators, hands what it creates or
--  restricts to its user. On macOS the extended ACL is cleared as well as
--  the mode bits.
--
--  A FAT or exFAT volume (a USB stick, a memory card) keeps no owner and no
--  access of its own: its modes come from how it is mounted, and on Windows
--  it has no access control lists (Linux ignores a chmod there). There is
--  nothing to restrict on one, and each call below succeeds with what the
--  volume gives. On Windows a regular file there is as private as the volume
--  can make it, and Private_To_Current_User answers True for it, by the same
--  rule; on Linux and macOS it answers by the mode the volume shows.
package Hostkit.Private_Paths is

   type Create_Outcome is
     (Created,
      Already_Exists,
      Create_Error);

   --  Atomically create Path as an owner-only directory. Inherited ACLs are
   --  removed before success is reported. An existing pathname is distinct
   --  from every other failure so callers can choose a new candidate.
   function Create_Directory (Path : String) return Create_Outcome;

   --  Create Path when absent, or verify and harden the existing directory.
   --  Links and directories not owned by the current account are refused.
   function Ensure_Directory (Path : String) return Boolean;

   --  Restrict an already-open, newly-created regular file to its owner and
   --  remove inherited access ACLs. Descriptor is a GNAT/C-runtime file
   --  descriptor, not a native Windows HANDLE.
   function Restrict_Open_File (Descriptor : Integer) return Boolean;

end Hostkit.Private_Paths;
