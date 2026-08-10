private with Interfaces;

--  Advisory locks on a file, so that two processes do not write it at once.
--
--  What this is for: a shell's history, its settings, its caches -- state on
--  disk that more than one session will reach for, because a user runs more than
--  one shell. Without a lock, two sessions exiting at the same moment both
--  rewrite the history file and one of them wins entirely; the other session's
--  commands are simply gone, and nothing reports it.
--
--  Advisory, and the word is load-bearing. A lock here stops another process
--  that *also asks*. It does not stop a text editor, a backup program, or a
--  consumer of this crate that forgot to call Acquire. Locking is a protocol
--  between willing participants, and a caller that treats it as enforcement has
--  misread it.
--
--  A lock is not a substitute for writing atomically. The two solve different
--  halves: the lock keeps two writers from interleaving, and an atomic replace
--  -- Hostkit.Fs.Replace_File -- keeps a reader from ever seeing a half-written
--  file, including after a crash, when no lock is held by anyone. Persistent
--  state wants both, and a caller that has only the lock still loses the file to
--  a power cut.
--
--  The lock is released when the Lock is closed and, whatever happens, when the
--  process ends. That last part is the reason to prefer this over a lock file a
--  caller creates and deletes: a process killed between creating and deleting
--  one leaves it behind for ever, and every later session then waits for a
--  process that no longer exists.
package Hostkit.Locks is

   --  What kind of access a lock reserves.
   type Lock_Kind is
     (
      --  Several readers at once, but no writer. For loading state that must
      --  not change underneath the read.
      Lock_Shared,

      --  One holder, no readers. For rewriting.
      Lock_Exclusive);

   --  What became of an attempt to take a lock.
   type Lock_Outcome is
     (
      --  Held.
      Lock_Ok,

      --  Someone else holds it, and the attempt did not wait. Not an error: it
      --  is the answer, and a caller decides whether to wait, to skip the
      --  write, or to tell the user.
      Lock_Busy,

      --  This host has no advisory locking, or none over this file -- a network
      --  filesystem that does not carry them, most often. Distinct from
      --  Lock_Error because it will not succeed on a retry, and distinct from
      --  Lock_Ok because nothing is protecting the file. A caller that treats
      --  this as success has an unprotected write it believes is guarded.
      Lock_Unsupported,

      --  The file could not be opened, or the host refused for another reason.
      Lock_Error);

   --  A held lock.
   --
   --  Holds the open file the lock lives on, so it is limited: copying it would
   --  produce two values that both believe they own one release.
   type Lock is limited private;

   --  Take a lock on a file, creating the file if it is not there.
   --
   --  The file is opened for writing and is not truncated: a lock taken on the
   --  state file itself must not destroy the state it is protecting. Callers
   --  that would rather lock something separate can name a sibling path.
   --
   --  @param Path File to lock.
   --  @param Kind Shared or exclusive.
   --  @param Wait True to block until the lock is free, False to report
   --         Lock_Busy at once. A shell exiting should not wait for ever on
   --         another session that has hung.
   --  @param Item The lock, held only when this returns Lock_Ok.
   --  @return What became of the attempt.
   function Acquire
     (Path : String;
      Kind : Lock_Kind;
      Wait : Boolean;
      Item : out Lock) return Lock_Outcome;

   --  Release a lock and close its file.
   --
   --  Idempotent, like Hostkit.Descriptors.Close and for the same reason: the
   --  double release on an error path should be harmless rather than release
   --  something a later Acquire has since taken.
   --
   --  @param Item Lock to release; not held afterwards.
   procedure Release (Item : in out Lock);

   --  Whether a lock is currently held.
   --
   --  @param Item Lock to inspect.
   --  @return True when Item holds a lock.
   function Is_Held (Item : Lock) return Boolean;

private

   use type Interfaces.Integer_64;

   type Lock is limited record
      --  The host value of the open file the lock lives on. Kept as a plain
      --  integer rather than a Hostkit.Descriptors.Descriptor because the POSIX
      --  bodies open it with flags that package does not offer, and the Windows
      --  body needs the handle for UnlockFileEx as well as for closing.
      Handle : Interfaces.Integer_64 := Interfaces.Integer_64'(-1);
      Held   : Boolean := False;
   end record;

end Hostkit.Locks;
