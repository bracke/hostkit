private with Ada.Strings.Unbounded;
private with Interfaces.C;

--  Being told when a directory's contents change.
--
--  There is no portable way to ask. Linux has inotify, macOS has kqueue's
--  EVFILT_VNODE, Windows has change-notification handles, and each is a
--  different shape of call with a different idea of what an event is -- so this
--  is per host by necessity, and the body the build selected is the only one
--  that ever runs.
--
--  What a caller gets instead is one contract that holds everywhere: a watch is
--  established or it quietly is not, and Poll answers "did anything change since
--  you last asked" without ever blocking. It is safe to call every frame.
--
--  FAILURE IS ALLOWED AND MEANS ONE THING. Any host can refuse: the notification
--  facility may be absent, its per-user limit exhausted, or the directory on a
--  filesystem that does not deliver events at all. A watch that cannot be
--  established simply stays inactive, and the caller falls back to re-reading
--  the directory on a timer. That costs responsiveness, never correctness --
--  which is why nothing here raises and nothing reports an error code. A caller
--  that treated Is_Active as a precondition for showing fresh contents would
--  have rebuilt, on its own side, the bug this arrangement avoids.
package Hostkit.Watch is

   type Watch_State is private;

   --  Point the watch at Path, releasing any directory it was watching before.
   --  Watching the same path twice running is a no-op, so this is cheap to call
   --  every frame. An empty Path releases the watch.
   --
   --  @param State The watch.
   --  @param Path The directory to watch.
   procedure Watch_Path (State : in out Watch_State; Path : String);

   --  Drop the watch and its native handles.
   --
   --  @param State The watch.
   procedure Release (State : in out Watch_State);

   --  Consume any pending change notifications without blocking.
   --
   --  When the watched directory itself goes -- deleted, moved away from the
   --  path, its volume unmounted -- that is reported as a change, and the watch
   --  is released: nothing more would ever arrive on it. Is_Active then answers
   --  False, and a later Watch_Path on the same path, a directory made there
   --  again included, arms a fresh watch rather than being taken for a repeat.
   --
   --  @param State The watch.
   --  @return True when the watched directory changed since the last call.
   function Poll (State : in out Watch_State) return Boolean;

   --  Whether a native watch is currently established. Diagnostics and fallback
   --  decisions only -- see the note above on what False does and does not mean.
   --
   --  @param State The watch.
   --  @return True when the host is delivering notifications.
   function Is_Active (State : Watch_State) return Boolean;

   --  Whether this host's watch also reports a write inside a file already
   --  there (a download growing, a log appended to), and not only entries
   --  added, removed or renamed. Where it does not, a caller that shows sizes
   --  and times must keep re-reading the directory on a short timer.
   --
   --  @return True where an active watch sees writes within files.
   function Sees_File_Writes return Boolean;

   --  How many notifications this watch has consumed, for diagnostics.
   --
   --  @param State The watch.
   --  @return The running count.
   function Event_Count (State : Watch_State) return Natural;

private

   --  The two handles mean whatever the host's body needs. On Linux they are
   --  the inotify descriptor and the watch descriptor; on macOS the kqueue and
   --  the open directory; on Windows the change-notification handle alone.
   use type Interfaces.C.ptrdiff_t;

   Unset : constant Interfaces.C.ptrdiff_t := -1;

   type Watch_State is record
      Handle : Interfaces.C.ptrdiff_t := Unset;
      Extra  : Interfaces.C.ptrdiff_t := Unset;
      Path   : Ada.Strings.Unbounded.Unbounded_String;
      Events : Natural := 0;
   end record;

end Hostkit.Watch;
