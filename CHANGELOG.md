# Changelog

Notable changes to hostkit. Format follows [Keep a Changelog](https://keepachangelog.com/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Nothing has been released yet: every commit so far is `0.1.0-dev`, and the
consumers that depend on this crate do so by path pin. Until there is a tag,
**the commit is the version** — a release of a consumer has to record which
commit of hostkit it was verified against.

That is also why this file starts here rather than being reconstructed commit
by commit. What follows is what the crate offers and what changed in it
recently enough to matter to somebody pinning it; the history before that is in
`git log`, where each commit message says what the host actually did.

## [Unreleased]

### Added

- `Hostkit.Host` — which host this program is running on, answered by the body
  the build chose rather than by anything an environment can spoof.
- `Hostkit.Fs` — path facts the host answers differently (and that GNAT gets
  wrong on Windows): joining, canonicalising through reparse points and
  symlinks, the search-path delimiter, the executable suffix, the temporary
  directory, the configuration, cache and data directories, and the device that
  reads as nothing.
- `Hostkit.Metadata` — what the filesystem says about a file, including whether
  the mode bits are the host's own or a rendering of an ACL.
- `Hostkit.Descriptors` — pipes, duplication, inheritance, non-blocking mode,
  waiting for readiness, and reads that tell end-of-file from would-block.
- `Hostkit.Spawn` — starting a program the way a shell has to: descriptors the
  caller made, a process group, a terminal's foreground, a session of its own,
  and no wait.
- `Hostkit.Process` — running a program with its output captured under a
  deadline, locating one on the search path, asking one to stop by id, and
  `End_Now`, which hands a status to the host without unwinding.
- `Hostkit.Pty` — a terminal for a child that did not inherit one: a
  pseudo-terminal on POSIX, a pseudo-console on Windows.
- `Hostkit.Terminal_Control` — terminal modes, window size, the foreground
  process group, raw and interruptible modes, and
  `Interrupt_Reaches_A_Busy_Program`, which says whether a spinning program is
  told about Ctrl-C at all.
- `Hostkit.Signals`, `Hostkit.Locks`, `Hostkit.Watch`, `Hostkit.Trash`,
  `Hostkit.Local_Channel`, `Hostkit.Clock`, `Hostkit.Native`,
  `Hostkit.Windows_Command_Line`, `Hostkit.Filesystem_Rules`, `Hostkit.Shell`.
- `Hostkit.Fs.Creation_Mask` and `Set_Creation_Mask` — the permissions a host
  takes away from files a program creates. POSIX calls it the umask and every
  shell exposes it; Windows has no such thing, so both answer False there
  rather than inventing a number. Reading is done by setting and putting back,
  because POSIX has no way to ask, and the comment says so where a reader will
  wonder.
- `Hostkit.Limits` — the resource limits POSIX calls rlimits and every shell
  exposes as `ulimit`: how many files may be open, how many processes a user
  may have, how large a file, a core dump, the stack, the data segment or the
  address space may grow, how much memory may be locked, and how many seconds
  of processor time a process may use. Soft and hard bounds, read and set. The
  numbers behind the names differ between hosts — `RLIMIT_NPROC` is 6 on Linux
  and 7 on macOS, and `RLIMIT_AS` shares its number with `RLIMIT_RSS` on macOS
  — which is why the table lives in a body per host; a consumer that copied one
  header's numbers would have asked the other host about the wrong resource and
  been answered without complaint. Windows has no per-process limits of this
  kind (a job object is a different thing, attached to a set of processes
  rather than inherited by them, and a process cannot lower its own), so
  `Applies` answers False there and both accessors refuse. A case lowers the
  open-file limit and opens files until the host refuses, which is what catches
  a transposed table: reading and setting a wrong number succeeds.
- `Hostkit.Pty.Write_Fails_When_Unheld` — whether a write to a terminal fails
  once nothing holds the device side. Measured on all three hosts by a case
  that starts a child on a terminal, waits for it to exit and then writes:
  macOS refuses the write (`Transfer_Error`), Linux and Windows take the bytes
  into a buffer nobody will read (`Transfer_Ok`). A consumer that did not know
  this read a refusal as a keystroke that never arrived.

### Fixed

- `Spawn.Wait` no longer raises `Constraint_Error` on a Windows exit code above
  `Integer'Last`. Windows exit codes are unsigned 32-bit; a program that ended
  with `-1` came back as `4294967295` and overflowed the conversion. It is now
  read as two's complement, so a caller sees the number the program passed.
- A console is not a pipe: asking one for readiness the way a pipe is asked
  blocked a read that should have returned. Only a key going down with a
  character on it counts as readable.
- Raw mode asks a Windows console for UTF-8, which it otherwise hands over in
  its own code page.
- A child gets an empty signal mask rather than the caller's.
- The pseudo-console's handles reach a child by inheritance, which they did not
  until they were marked inheritable — a child started on a terminal saw
  nothing at all.
- An empty environment variable is absent on Windows, and now says so.
- A saved terminal mode is no longer promised to restore byte-for-byte: macOS
  answers success and reads back something else, so a restore that did not
  restore is refused and the differing byte is named.

## Releasing

There is no release procedure here yet. When there is one, the first thing it
has to decide is what a version means for a crate with one body per operating
system: a change that only a Windows body can see is still a change every
consumer resolves.
