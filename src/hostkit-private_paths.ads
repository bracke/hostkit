--  Owner-only files and directories, including the host ACL work that chmod
--  alone does not express.
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
