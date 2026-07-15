with Ada.Streams;

--  A byte channel to a local endpoint named by a path.
--
--  What the path names depends on the host: a Unix-domain socket on POSIX, a named pipe on
--  Windows. An ssh-agent is reached this way, and the two hosts disagree about what "the
--  agent socket" even is -- a filesystem socket on one, "\\.\pipe\..." on the other -- so a
--  caller cannot just open a socket and have it work on both. This hides that difference:
--  connect by path, send bytes, receive bytes, close.
package Hostkit.Local_Channel is

   type Channel is limited private;

   --  Connect to the local endpoint at Path. On POSIX Path is a Unix-domain socket; on
   --  Windows it is a named pipe. False when the endpoint is absent or refuses.
   function Connect (Path : String; Item : out Channel) return Boolean;

   function Is_Open (Item : Channel) return Boolean;

   --  Send every byte of Data. False if the whole of it could not be written.
   function Send
     (Item : in out Channel;
      Data : Ada.Streams.Stream_Element_Array)
      return Boolean;

   --  Read exactly Data'Length bytes into Data. False if that many could not be read
   --  (a short read is a closed or broken channel, not a partial success).
   function Receive
     (Item : in out Channel;
      Data : out Ada.Streams.Stream_Element_Array)
      return Boolean;

   procedure Close (Item : in out Channel);

private

   --  The native handle, kept OS-neutral so the spec is shared: a file descriptor on POSIX,
   --  a HANDLE on Windows, both of which fit here. Closed is Invalid.
   Invalid : constant := -1;

   type Channel is limited record
      Open   : Boolean := False;
      Native : Long_Integer := Invalid;
   end record;

end Hostkit.Local_Channel;
