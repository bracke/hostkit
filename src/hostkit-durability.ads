--  Making what was written stay written: a file's contents, or a
--  directory's entries -- a rename into it, a file made or removed -- put
--  on the storage device, not only handed to the operating system, so that
--  a power loss or a crash of the machine after the call cannot take them
--  back.
--
--  A write and a close say nothing about this: the system keeps the data
--  in memory and writes it when it likes. A commit that renames a marker
--  over its records needs those records on the device first, and the
--  rename after them, or the marker can survive what it marks.
package Hostkit.Durability is

   --  What asking came to. Not_Supported is not success: the host cannot
   --  say the data is on the device, and a caller that needs it to be is
   --  told so rather than told it is.
   type Outcome is (Synced, Failed, Not_Supported);

   --  Put a file's contents on the device.
   --
   --  @param Path The file.
   --  @return Synced, Failed when it cannot be opened or synced, or
   --    Not_Supported.
   function Sync_File (Path : String) return Outcome;

   --  Put a directory's entries on the device: the names made, renamed and
   --  removed in it.
   --
   --  @param Path The directory.
   --  @return Synced, Failed, or Not_Supported where the host has no such
   --    operation -- Windows journals directory entries itself.
   function Sync_Directory (Path : String) return Outcome;

end Hostkit.Durability;
