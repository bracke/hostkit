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

   --  Give a file its blocks up to Length now, rather than as it is
   --  written: a file mapped and written through memory on a disk that
   --  fills part way faults the writer (SIGBUS) where no check can see it;
   --  a refusal here comes before anything is written. The file is grown
   --  to Length where it is shorter, never cut.
   --
   --  @param Path The file; it must exist.
   --  @param Length The bytes it is to hold room for.
   --  @return Synced when the room is the file's, Failed when it cannot be
   --    had -- no space, no such file -- or Not_Supported where the host
   --    or the file system cannot reserve it (macOS, an unknown host, a
   --    file system without the operation), and the file is as it was.
   function Reserve_Space (Path : String; Length : Long_Long_Integer) return Outcome;

end Hostkit.Durability;
