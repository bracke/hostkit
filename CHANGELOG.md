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

- `Regular_Files` (Open_Read, Skip_Zeros, Finish_Sparse) and
  `Directory_Write_Access` (Prepare, Finish, Release), moved from files, which
  bound open/statx/fstat/fchmod/lseek/ftruncate and CreateFileW itself in
  per-OS bodies of its own. Behaviour unchanged.

- `Metadata.Account_Id` (mod 2**32) for user and group ids, with
  `Account_Image`, `Parse_Account_Id` and `Fits_Natural`. `File_Ownership`,
  `File_Mode_And_Ownership`, `Set_Ownership`, `User_Id_For_Name`,
  `Group_Id_For_Name`, `User_Name_For_Id` and `Group_Name_For_Id` take and
  give it; their Natural forms remain as overloads for existing callers. A
  call with an integer literal for the id (`User_Name_For_Id (0)`) is now
  ambiguous and needs `Account_Id'(0)`.

- `Linux_Abi`: the statx record and the machine-dependent O_NOFOLLOW and
  O_DIRECTORY values, shared by the Linux bodies instead of copied into each.

- `Metadata.Change_Stamp` on macOS (stat: modification and change times to
  the nanosecond, size, inode) and Windows (FILE_BASIC_INFO's LastWriteTime and
  ChangeTime as Unix seconds and nanoseconds, size, file index), in Linux's
  words; both said `Available => False` before, so their callers could only
  trust size and modification time, which an unpacker or a script sets back.

- `Fs.Read_Beneath`: read an ordinary file at a path below a root without
  following a symbolic link or reparse point anywhere on the way, the check
  being the open itself. POSIX walks from a descriptor of the root with openat
  and O_NOFOLLOW; Windows opens each part as itself, refuses a reparse point and
  holds each directory without FILE_SHARE_DELETE until the read is done. A
  check-then-read (Real_Path, then open) leaked the outside file 7-42 times in
  20,000 swaps of a directory for a link; this leaked none. `Read_Unsupported`
  on an unknown host.

- `Durability.Reserve_Space`: a file given its blocks up front (posix_fallocate
  on Linux), so a file written through a shared mapping is refused before it is
  written rather than faulting its writer when the disk fills; `Not_Supported`
  on macOS, Windows and unknown hosts.

- `Process.Run_Captured (Clean_Wrapper => True)`: with `Whole_Group`, on Linux,
  the shell that stands for the group starts with no environment but `PATH`, so
  a caller that passes its program only what it may have (`env -i`) leaves
  nothing else readable in `/proc/<parent>/environ`. Ignored on other hosts.

### Fixed

- **On arm, powerpc and m68k Linux, a final symbolic link was followed where
  it must not be.** `Lease_Files`, `Private_Paths`, `Fs` (the no-follow tree
  delete and `Read_Beneath`) and `Metadata.Update_Entry_Metadata` spelled
  O_NOFOLLOW and O_DIRECTORY as their x86 numbers, which on those machines are
  O_LARGEFILE and O_DIRECT. They take the machine's values from `Linux_Abi`
  now, and the release check refuses a Linux body that spells either as a
  number.

- A file owned by a uid or gid from 2**31 up (idmapped mounts, NFS's nobody
  at 4294967294) reported no ownership and, on Linux, no permissions either:
  the conversion to Natural raised, and the handler cleared the mode with the
  ownership. Ownership is now an Account_Id, and a failure on the ownership
  side of `File_Mode_And_Ownership` never clears `Mode_Available`.

- **A file another task has open is read all the same.** GNAT's default
  open form refuses a file the program already has open (`Use_Error:
  reopening shared file`), so `Process.Identity_Of` answered "" -- an
  unknown process -- whenever another task was reading the boot's id at
  the same moment. Every open for reading now says `shared=no`
  (`Process.Identity_Of`, the child's stdin file, `Fs`'s mount table).
  Tested with the boot's id held open.

- The suite's link tests no longer pass in silence on a host that refuses
  links: each says so on standard error, and fails where
  `HOSTKIT_TESTS_NEED_LINKS` is set, as CI now sets it on every runner, so the
  Windows job's link race and no-follow parts are known to have run.

- Linux `Durability.Reserve_Space` opens the file for reading and writing, as
  glibc's emulation on file systems without fallocate needs, retries an
  interrupted call, and answers `Not_Supported` where the file system cannot
  reserve rather than `Failed`.

- Linux `Run_Captured`: a stop that found the leader already ended reaped it
  before sending the group its kill, giving its id up while still in use and
  losing how it ended; the leader is now asked without being reaped.
- `Run_Captured (Clean_Wrapper)` says what it does not do: the caller's own
  `/proc/<pid>/environ` stays readable to a program under the same user.

- Linux `Run_Captured` with `Whole_Group`: the program starts in a session of its
  own (`setsid`), with no controlling terminal to stop on; when the group's
  leader ends, what it left running in the group is killed before the leader is
  reaped; and a capture file that cannot be opened ends the child (127) rather
  than letting it write to the caller's terminal.
- `Fs.Own_Executable` on Linux: a program replaced on disk while it runs is
  named without the kernel's ` (deleted)` suffix, so starting itself again
  starts the new copy.

### Added

- **`Parent_Watch.End_With_Parent`**: a child program that should not
  outlive the one that started it ends when that one does -- Linux by the
  kernel's parent-death signal, macOS by a detached thread watching the
  parent; False where the host cannot.
- **`Directory_Listing.List`**: a directory's entries with the kind the
  directory records for each (file, directory, link, other) without
  following a link or asking each entry; `Unknown` where the filesystem or
  host does not say, for the caller to ask itself.
- **`Metadata.Entry_Identity_Of` and `Entry_Revision_Of`**: stable,
  no-follow facts for detecting replacement and change without treating a
  symbolic link as its target. Windows keeps the complete 128-bit file ID.
- **`Metadata.Update_Entry_Metadata`**: change permissions or ownership through
  a held descriptor/handle, optionally requiring a previously captured entry
  identity, and return the old value from that same entry. Symbolic links and
  Windows reparse points are refused.
- **`Hostkit.Lease_Files`**: securely create or open an owner-held lease without
  following links, take shared or exclusive process-lifetime locks, perform
  durable positioned I/O, and verify that a pathname still names the held file.
- **`Hostkit.Private_Paths`**: create an owner-only directory, safely harden an
  existing owned directory without following a link, and restrict an already
  open regular file. POSIX bodies remove inherited ACLs; Windows writes a
  protected owner-only DACL.
- **`Hostkit.Metadata_Copy`**: no-follow capture and application of entry
  timestamps and complete copy metadata. POSIX preserves ownership, modes,
  ACLs, and extended attributes while refusing file capabilities; Windows
  preserves the metadata its filesystem exposes for this operation.
- `Terminal_Control.Show_Control_Keys`: whether the terminal echoes a control
  key as a caret and a letter (ECHOCTL), so a program that reads Esc as a key
  of its own does not leave `^[` on the line. Linux only; elsewhere it answers
  False.
- `Terminal_Control.Set_Echo`: whether the terminal shows what is typed. A
  program that lets its user type ahead while it writes output of its own
  turns echo off for that time and shows the line when it reads it. Linux
  only; elsewhere it answers False.
- `Terminal_Control.Keep_Input_On_Interrupt`: whether Ctrl-C leaves what was typed
  ahead in the terminal's queue. POSIX throws it away with the signal unless
  `NOFLSH` is set; a program that lets its user type the next command while it
  works, and stops that work at Ctrl-C, sets it for the work and clears it
  after. Linux only; elsewhere it answers False rather than claim the input is
  kept.
- **`Fs.Move_No_Replace`**: move an entry atomically without replacing one
  already at the target -- `renameat2 (RENAME_NOREPLACE)` on Linux,
  `renamex_np (RENAME_EXCL)` on macOS, `MoveFileExW` without replacement on
  Windows; unsupported hosts refuse.
- **`Fs.Delete_Tree_No_Follow`**: recursively remove an entry while anchoring
  traversal to open descriptors or handles and verifying child identities.
  Symbolic links and Windows reparse points are removed, never followed.
- **`Spawn.Release`**: let go of a finished, collected process's handle --
  Windows closes it; on POSIX nothing is left after the wait.

- **`Terminal_Control.Enter_Alternate_Screen` and
  `Leave_Alternate_Screen`:** a full-screen list draws on a screen of its own
  and leaves the one there was as it was -- no line it scrolled left behind.

- **`Run_Captured (..., Whole_Group => True)`** starts the program as a
  process group of its own and, on a deadline or a cancellation, stops the
  whole group: a shell killed on its deadline no longer leaves what it
  started running. A process group on POSIX, a job on Windows.

- **`Hostkit.Durability`**: `Sync_File` and `Sync_Directory` put a file's
  contents, or a directory's entries, on the device -- `fsync` on Linux,
  `F_FULLFSYNC` on macOS (`fsync` where the file system does not take it),
  `_commit` on Windows. A directory on Windows, and any host the crate does
  not know, answer `Not_Supported`, never `Synced`.

- `Hostkit.Process.Presence_Of` — whether a process on this machine, by id, is
  still there: `Present`, `Absent`, or `Unknown` where the host did not say.
  POSIX asks with signal 0 (EPERM still counts as there, ESRCH as gone);
  Windows opens the process for its exit code. For a process one did not start
  and cannot wait on — the holder of a lock or a lease that may have died.
- `Hostkit.Command_Line` — the arguments this process was actually started
  with. Windows starts a process with one command-line *string*, and the
  vector a program sees is whatever its C runtime parsed out of it — some
  runtimes expand a wildcard against the current directory on the way, so a
  tool whose arguments are patterns answers about the wrong thing. This asks
  the system (`GetCommandLineW` plus `CommandLineToArgvW`, which expands
  nothing) and splits it here; elsewhere the kernel's vector is untouched and
  `Ada.Command_Line` is the answer.
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
- `Hostkit.Process.Become` — replace the running image, keeping the process:
  what a shell's `exec` does. The process id, the open descriptors, the
  terminal's foreground group and whatever is waiting for this process all stay
  pointed at the program that takes over, which is the whole reason it is not
  "start a child and exit with its status". `execvp` on POSIX, so a name is
  looked up on the search path the way the host does it. Windows refuses:
  CreateProcess makes a *new* process, so anything built on it changes the
  process id and leaves the original waiting or gone — precisely what a caller
  reaching for this is avoiding.
- `Hostkit.Fs.Home_Directory_Of` — another user's home directory by name, which
  is what a shell needs for `~other` and cannot work out for itself: the answer
  is in the host's user database (`getpwnam` on POSIX) and nowhere else. Windows
  answers "" for every account: a profile folder belongs to whoever is logged in,
  and there is no supported way to ask about another one without its credentials
  — guessing at `C:\Users\<name>` is a convention rather than a rule and is
  wrong on a domain-joined machine. A consumer that gets "" leaves the path as
  the user wrote it.
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

- **A group run no longer outlives its caller on Linux.** `Run_Captured`
  with `Whole_Group` starts the program through a small shell that stands
  for the group, and asks the kernel (`PR_SET_PDEATHSIG`) to tell it when
  the caller dies -- `kill -9` included; told, it kills every process in the
  group, what the program started as well. The child's signal mask is also
  cleared before `exec`: a caller that takes its signals on a thread of its
  own (Ada.Interrupts) blocked them in everything it ran, which then could
  not be told to stop. Elsewhere a group run still ends only when it ends.

- **A lock is not handed to a program this one starts** (`O_CLOEXEC`): a
  child that outlived the session kept the lock's file open and held it for
  nobody.
- **`Run_Captured` with one file for both streams** no longer loses output:
  standard output and standard error were each opened on the file and wrote
  over each other; the second is now the first, duplicated.
- **The Windows and macOS bodies build without a word, which nobody could see
  until CI asked.** `alr build` exits 0 with warnings on its output, and a
  platform body only compiles on the platform that owns it — so twenty-four
  complaints had collected in the two bodies a Linux machine never builds:
  redundant `with` clauses, `use type` clauses shadowed by the same clause at
  the top of the file, blank lines in pairs, a `()` aggregate GNAT now calls
  obsolescent, an assignment overwritten before it was read, a `char_array`
  that could be constant, and an orphaned comment header. The build step reads
  its own output now and fails on any line naming a file and a position.

- **The Windows executable-extension test allocates nothing.** Both bodies that
  ask whether a name runs — `Fs.Is_Executable` and `Metadata`'s own — built an
  array of `access constant String` from six `new String'(".exe")` allocations
  on **every call**, none of which anything frees, to hold six literals known
  at compile time. The extension is taken from the last dot and compared.

- `Descriptors.Assign` moves this program's own writing on Windows, not only
  what a child is given. `SetStdHandle` changes the standard handle; a runtime
  that opened its output once goes on writing where it did, so a caller
  redirecting itself got nothing — its own line on the console with the file it
  had redirected to empty. The Windows body now duplicates the handle into a
  runtime descriptor and puts that over the standard one (`_open_osfhandle`,
  `_flushall`, `_dup2`), which is what `dup2` does in a single call elsewhere.
  A case asserts it on every host by writing through `Ada.Text_IO` and reading
  the file back, which is the thing that was silently untrue.

- The macOS body reads macOS's own `struct passwd`. BSD keeps a change time and
  a login class between the group id and the gecos field, and an expiry after
  the shell; a record copied from the Linux body compiles, links, and reads the
  wrong pointer. `Home_Directory` never showed it because it answers from `HOME`
  first — `Home_Directory_Of`, which cannot, answered nothing for `root` on that
  host and correctly on the other two. Found by the tri-platform run, on the
  first commit that asked the question.

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
