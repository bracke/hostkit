with GNAT.OS_Lib;

--  Reading a file only when it is a regular file, and writing a sparse copy.
--
--  Opening and then asking "is this a regular file?" of the path is two
--  questions about what may be two different files: a FIFO swapped in between
--  hangs the reader, a link swapped in sends it elsewhere. Here the open is
--  the check -- the descriptor that comes back is asked what it is -- and
--  every host does that differently: Linux opens without following and asks
--  statx of the descriptor, macOS asks fstat, Windows opens the reparse point
--  itself and asks GetFileInformationByHandle before handing the handle to the
--  C runtime.
package Hostkit.Regular_Files is

   --  Open only a regular file. When Follow_Links is False, inspect the entry
   --  itself and refuse symbolic links. Supported is False only on hosts that
   --  cannot provide the required no-follow primitive.
   --  @param Path File to open.
   --  @param Follow_Links Whether a final symbolic link may be followed.
   --  @param Supported False only when the host lacks the requested primitive.
   --  @return Open descriptor, or Invalid_FD on refusal or failure.
   function Open_Read
     (Path         : String;
      Follow_Links : Boolean;
      Supported    : out Boolean) return GNAT.OS_Lib.File_Descriptor;

   --  Advance a sparse output without physically writing Count zero bytes.
   --  @param Descriptor Open output descriptor.
   --  @param Count Number of zero bytes represented by the hole.
   --  @return True when the host advanced the sparse output.
   function Skip_Zeros
     (Descriptor : GNAT.OS_Lib.File_Descriptor;
      Count      : Integer) return Boolean;

   --  Materialize the final sparse extent at the descriptor's current offset.
   --  @param Descriptor Open sparse output descriptor.
   --  @return True when the final file length was established.
   function Finish_Sparse (Descriptor : GNAT.OS_Lib.File_Descriptor) return Boolean;

end Hostkit.Regular_Files;
