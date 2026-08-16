with Ada.Streams;
with Ada.Strings.Unbounded;
with Interfaces;

--  Facts about a path that the host answers differently -- and that GNAT gets wrong on
--  Windows without saying so.
package Hostkit.Fs is

   --  Is this path a link?
   --
   --  GNAT.OS_Lib.Is_Symbolic_Link answers False for every path on Windows: it wants an
   --  lstat, and there is none, so it says "not a link" rather than "I cannot tell".
   --  That made every link invisible -- to a file manager that showed none, and to a
   --  Delete_Tree that followed them out of the tree it was deleting.
   --
   --  Windows has links: a symbolic link and a junction are both reparse points, and
   --  that is what is asked here.
   function Is_Link (Path : String) return Boolean;

   --  Create a symbolic link at Link_Path pointing at Target.
   --
   --  False when the host will not: Windows needs Developer Mode or a privilege, and
   --  refusing is a normal answer there, not an error.
   function Create_Link
     (Target    : String;
      Link_Path : String)
      return Boolean;

   --  Will this host run this file?
   --
   --  GNAT.OS_Lib.Is_Executable_File answers True for every file that exists on
   --  Windows -- and for a directory. An open action pointing at a directory passed its
   --  preflight and was launched.
   --
   --  POSIX asks the mode bits. Windows does not have the concept: every ordinary file
   --  carries FILE_EXECUTE in its DACL, so the bit says nothing, and what runs is
   --  decided by the extension. A chmod +x "run.sh" is an executable on one and a plain
   --  file on the other, and both answers are right.
   function Is_Executable (Path : String) return Boolean;

   --  Will this host start this file when it is named to Spawn?
   --
   --  The narrower question, and the one a caller about to hand a name over is
   --  actually asking. Is_Executable says whether the host counts the file a
   --  program at all, and on Windows that takes in a `.ps1` and an `.msi`,
   --  which nothing starts from a name: one is read by another shell and the
   --  other by the installer, and naming either is a policy about what a
   --  consumer's language means rather than a fact about the host.
   --
   --  A `.bat` and a `.cmd` *are* started, because the host starts the command
   --  interpreter for them itself -- which is a fact about the host, and one
   --  that reading the documentation the other way round gets wrong. It was
   --  wrong here until a case on that host said otherwise.
   --
   --  The same answer as Is_Executable everywhere else, where a file with the
   --  bit set is started by the kernel and a `#!` line is the kernel's
   --  business rather than the caller's.
   --
   --  @param Path The file.
   --  @return True when Spawn could start it by name.
   function Starts_When_Named (Path : String) return Boolean;

   --  Can anyone but the owner get at this file?
   --
   --  A private key must not be. OpenSSH refuses one whose file is group- or world-readable,
   --  and this is the fact that check needs: on POSIX, whether any group or other permission
   --  bit is set (mode and 8#077#). It answers for a regular file only -- a directory's bits
   --  mean something else -- and False for anything it cannot read, so a missing file is
   --  "not exposed" rather than a spurious rejection.
   --
   --  On Windows there are no such bits; access is by ACL, and a file in the user's profile
   --  is already owner-scoped by the default ACL. This does not read the ACL, so it answers
   --  False there -- it does not enforce the check on Windows, it declines to guess.
   function Accessible_By_Others (Path : String) return Boolean;

   --  Can anyone but the owner get at this directory?
   --
   --  The same mode test (mode and 8#077#), asked separately because a directory's bits
   --  do not mean what a file's mean -- r is listing it, x is traversing it -- and
   --  because a caller wanting one is rarely asking about the other. A private tree is
   --  the case that needs it: a CA root, an ssh directory, a keyring. It answers for a
   --  directory only, and False for anything it cannot read.
   --
   --  On Windows there are no such bits; access is by ACL, and this does not read the
   --  ACL, so it answers False there -- it declines to guess rather than reporting a
   --  private directory as exposed, or an exposed one as private.
   function Directory_Accessible_By_Others (Path : String) return Boolean;

   --  Restrict Path to its owner: 0600 for a regular file, 0700 for a directory, which
   --  needs the owner's execute bit to be entered at all.
   --
   --  The usual way to do this is to spawn chmod, and that is the trouble: on Windows
   --  there is no chmod to find, so the spawn is skipped, the write goes on, and a
   --  private key ends up with whatever permissions it was created with -- silently,
   --  because a caller that spawns a tool it cannot find learns nothing from its
   --  absence. This is a call, not a spawn: it needs no PATH and it has a result.
   --
   --  @return True when the host applied it. False on Windows, where there are no mode
   --          bits and this does not write an ACL -- the caller has *not* been handed a
   --          private path, and if that matters it has to say so rather than assume.
   --          False for a path that does not exist, and for anything that is neither a
   --          regular file nor a directory.
   function Make_Private (Path : String) return Boolean;

   --  Give Path to another owner.
   --
   --  POSIX ownership is a pair of numbers and a privileged operation; Windows has
   --  no such pair, and an owner there is a SID in a security descriptor. False on
   --  Windows means it was not done, not that it succeeded silently.
   --  @return True when the host applied it
   function Set_Owner (Path : String; User : Integer; Group : Integer) return Boolean;

   --  Attach an extended attribute to Path.
   --
   --  Windows has alternate data streams, which are not the same thing and are not
   --  written here; this declines there rather than approximating.
   --  @return True when the host applied it
   function Set_Extended_Attribute
     (Path  : String;
      Name  : String;
      Value : Ada.Streams.Stream_Element_Array) return Boolean;

   --  Create a named pipe in the filesystem at Path.
   --
   --  A Windows named pipe lives in its own namespace, never in a directory, so
   --  there is nothing here to create and this declines.
   --  @return True when the host created one
   function Create_FIFO (Path : String; Mode : Natural) return Boolean;

   --  Create a Unix-domain socket node in the filesystem at Path.
   --
   --  Windows named pipes and Winsock sockets do not create a POSIX pathname
   --  socket, so Windows declines.
   --  @return True when the host created one
   function Create_Socket (Path : String; Mode : Natural) return Boolean;

   type Device_Kind is (Character_Device, Block_Device);

   type Special_File_Kind is
     (Not_Special,
      FIFO,
      Character_Device,
      Block_Device,
      Socket,
      Other_Special);

   type Special_File_Info is record
      Available : Boolean := False;
      Kind      : Special_File_Kind := Not_Special;
      Device    : Interfaces.Unsigned_64 := 0;
      Mode      : Natural := 0;
   end record;

   function Special_File_Info_Of (Path : String) return Special_File_Info;

   --  Create a device node at Path.
   --
   --  Device is the host's own encoding of major and minor, which differs between
   --  Linux, BSD and Solaris -- the caller decides that, because a caller reading an
   --  archive knows which layout wrote it. Windows has no device nodes in the
   --  filesystem and declines.
   --  @return True when the host created one
   function Create_Device
     (Path   : String;
      Kind   : Device_Kind;
      Device : Interfaces.Unsigned_64;
      Mode   : Natural) return Boolean;

   --  Create a second name for an existing file.
   --
   --  Unlike the rest of these, Windows does have this one: CreateHardLinkW, on a
   --  volume that supports it.
   --  @return True when Link_Path now names the same file as Target
   function Create_Hard_Link (Target : String; Link_Path : String) return Boolean;

   --  Atomically replace Target with Source (a completed temp file), on one filesystem.
   --
   --  An atomic write ends by renaming the temp file over the real one. POSIX rename does
   --  that in a single step even when Target already exists; Windows rename -- and
   --  GNAT.OS_Lib.Rename_File with it -- fails when it does, so rewriting a file that was
   --  already there reported a write failure. This asks the host for a replacing rename:
   --  rename on POSIX, MoveFileEx with MOVEFILE_REPLACE_EXISTING on Windows.
   --
   --  @return True when Target now holds what Source held and Source is gone.
   function Replace_File
     (Source : String;
      Target : String)
      return Boolean;

   --  Read the literal target of the symbolic link (or junction) at Path.
   --
   --  POSIX has readlink. Windows has no such call: a link is a reparse point, so this
   --  opens it without following (FILE_FLAG_OPEN_REPARSE_POINT) and reads the target out
   --  of the reparse data. GNAT offers nothing here -- its own reader is a Windows stub
   --  that always fails, which made a scanner treat every Windows link as broken.
   --
   --  @return False when Path is not a link or the target cannot be read; Target is then
   --          empty. On success Target holds the link's own target text.
   function Read_Link_Target
     (Path   : String;
      Target : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean;

   --  Remove the link at Path -- the link itself, never what it points at.
   --
   --  A link to a directory is a link on POSIX and a directory on Windows, and the two
   --  hosts remove it with different calls: unlink there, RemoveDirectoryW here for a
   --  directory reparse point and DeleteFileW for any other. Ada.Directories.Delete_File
   --  is the file call on both, so a Windows directory symlink refused it -- and, having
   --  asked a stat that followed the link, reported the refusal as "file does not exist".
   --
   --  Not following is the point. The target is someone else's -- often deliberately
   --  outside the tree being cleared -- and a caller that followed the link would delete
   --  it. This removes a link or nothing.
   --
   --  @return True when the link is gone. False when Path is not a link (a regular file
   --          or directory is left alone) or the host refused to remove it.
   function Delete_Link (Path : String) return Boolean;

   --  Resolve Path to its canonical absolute form, following symbolic links and
   --  reparse points -- POSIX realpath, Windows GetFinalPathNameByHandleW.
   --  Ada.Directories.Full_Name cannot be used: on POSIX it resolves links, but on
   --  Windows it is GetFullPathName (purely lexical, does not follow reparse points).
   --  @return Empty string if Path cannot be resolved; otherwise the resolved path
   --          (on Windows with the \\?\ and \\?\UNC\ prefix stripped).
   function Real_Path (Path : String) return String;

   --  The host's directory for temporary/scratch files, without a trailing
   --  separator. On POSIX this is $TMPDIR, else /tmp. On Windows it is
   --  GetTempPathA, which consults TMP/TEMP/USERPROFILE and falls back to the
   --  Windows directory -- so it is valid even when the process environment
   --  carries no temp variable (a spawned tool often has none), unlike reading
   --  %TEMP% directly. Never empty.
   --  This program's own executable, in full.
   --
   --  Not argv[0], which is whatever the caller passed: a relative path that
   --  stops meaning anything once the program changes directory, a bare name
   --  that a PATH search may resolve to a different program of the same name,
   --  or the link rather than what it points at. A program that finds its data
   --  files beside itself is asking a question with an exact answer, and every
   --  host has one -- /proc/self/exe, _NSGetExecutablePath, GetModuleFileNameW.
   --
   --  @return The path, or "" where the host will not say.
   function Own_Executable return String;

   --  The directory holding this program's own executable, or "" with it.
   function Own_Executable_Directory return String;

   --  The character this host writes between path segments.
   --
   --  Windows accepts both and writes a backslash; everywhere else it is a
   --  forward slash. Asked rather than assumed because a path built with the
   --  wrong one is the kind of mistake that works until it does not: the Win32
   --  file calls take either, so a forward slash survives until something
   --  shows the path to a person or hands it to a tool that does not.
   function Separator return Character;

   --  The suffix this host supplies for itself when a program is named
   --  without one.
   --
   --  "" on POSIX, where a program is its file name and nothing is added.
   --  ".exe" on Windows, where the loader appends exactly that to a name with
   --  no extension -- which is why `run ("git")` starts `git.exe` there and
   --  why a caller offering a name to a user should take it off again.
   --
   --  Not the whole of PATHEXT. A `.bat` or a `.cmd` is run by the command
   --  interpreter rather than by the loader, so its name has to be written
   --  out; this is only the one suffix a name may leave off.
   --
   --  @return The suffix, with its dot, or "".
   function Executable_Suffix return String;

   --  The path of the device that reads as nothing and swallows what is
   --  written to it.
   --
   --  For a caller that must give a program a stream and has none to give: a
   --  job started into the background on a host with no job control cannot
   --  share the keyboard with the shell that started it, and a program whose
   --  input is this reads end-of-file rather than racing for keystrokes.
   --
   --  A path rather than an open descriptor, because a caller opens it the way
   --  it opens any other file and closes it the same way. Every host this
   --  crate supports has one; "" would mean a host that does not, and a caller
   --  finding "" must not open it.
   --
   --  @return "/dev/null", "NUL", or "" on a host without one.
   function Null_Device return String;

   --  The character this host writes between the entries of a search path.
   --
   --  A colon on POSIX and a semicolon on Windows, where a colon is part of a
   --  drive letter and could not be a separator at all. A consumer splitting
   --  PATH has to ask: the two hosts differ, and a split on the wrong one
   --  turns `C:\Windows` into two directories that do not exist.
   --
   --  @return The delimiter.
   function Search_Path_Delimiter return Character;

   --  Join two path segments the way this host writes them.
   --
   --  Ada.Directories.Compose looks like the portable answer and is not: its
   --  Name is a *simple* name, so composing a multi-segment tail is not what
   --  it is for, and what it does with one is not something to rely on. This
   --  takes either side as it finds it, joins with one separator, and returns
   --  the other side alone when one is empty.
   --
   --  @param Base Leading part, possibly empty.
   --  @param Part Trailing part, possibly empty.
   --  @return The two joined by exactly one separator.
   function Join (Base : String; Part : String) return String
   is (if Base = "" then Part
       elsif Part = "" then Base
       elsif Base (Base'Last) = '/' or else Base (Base'Last) = '\'
       then Base & Part
       else Base & Separator & Part);

   --  This user's home directory.
   --
   --  HOME is a convention a process can be started without; the host has a
   --  record -- getpwuid on POSIX, the profile folder on Windows -- and that is
   --  the fallback here. Empty only where neither will say, which is worth
   --  telling apart from "the home directory is the current directory".
   function Home_Directory return String;

   --  Where this host keeps per-user application data: %APPDATA% on Windows,
   --  ~/Library/Application Support on macOS, $XDG_DATA_HOME or ~/.local/share
   --  elsewhere. The three are not interchangeable and nothing but the host
   --  knows which one applies.
   function Application_Data_Directory return String;

   --  Where this host keeps per-user caches -- regenerable data that may be
   --  deleted behind the program's back without losing anything.
   --
   --  A different place from Application_Data_Directory on every host, and the
   --  difference has consequences rather than being tidiness: %LOCALAPPDATA%
   --  rather than %APPDATA% because the roaming profile is copied between
   --  machines at login and nobody wants a thumbnail cache travelling with it;
   --  ~/Library/Caches rather than Application Support because the first is
   --  excluded from backups and the second is not; $XDG_CACHE_HOME rather than
   --  $XDG_DATA_HOME for the same reason the specification separates them.
   --
   --  Putting a cache in the data directory works, right up until the user
   --  restores a backup or signs in on another machine.
   --
   --  @return The directory, or "" where the host will not say.
   function Cache_Directory return String;

   --  Where this host keeps per-user configuration -- what the user chose, which
   --  is the one of these three that cannot be regenerated if it is lost.
   --
   --  On Linux this is a different place from the data directory
   --  ($XDG_CONFIG_HOME, not $XDG_DATA_HOME); on Windows and macOS it is the same
   --  place. That is exactly why a caller should not work it out itself: whether
   --  the host separates configuration from data is the host's business, and a
   --  program that hard-codes ~/.config gets it right on one host in three.
   --
   --  Roaming is correct here, unlike for a cache: %APPDATA% rather than
   --  %LOCALAPPDATA%, because what the user chose should follow them to another
   --  machine.
   --
   --  macOS answers ~/Library/Application Support rather than
   --  ~/Library/Preferences deliberately. Preferences is for the plists
   --  NSUserDefaults manages; writing a hand-editable text file into it puts it
   --  where the system expects to own the contents.
   --
   --  @return The directory, or "" where the host will not say.
   function Config_Directory return String;

   function Temp_Directory return String;

   --  Create a private temporary directory under Temp_Directory.
   --
   --  Prefix is used as a readable filename prefix only; the returned path is
   --  host-chosen and should be treated as opaque by callers.
   --
   --  @return Full path to the created directory, or "" when none could be made.
   function Create_Temporary_Directory (Prefix : String) return String;

   --  Does the filesystem holding Path enforce DOS/Windows filename rules --
   --  case-insensitive, forbidding \ : < > " | ? *, the reserved device names
   --  and a trailing dot? True for a FAT, exFAT or NTFS volume, so a caller can
   --  refuse a name the destination cannot store even when the host itself is
   --  POSIX (a FAT USB stick on a Linux box).
   --
   --  Path is any path on the filesystem in question -- typically the directory
   --  a file is about to be created in. When the filesystem cannot be
   --  determined the answer follows the host: False on POSIX (do not invent a
   --  restriction), True on Windows (its volumes are DOS-family in practice), so
   --  an unknown case is never worse than validating by host alone.
   --
   --  Linux reads /proc/self/mountinfo; macOS answers False (its native volumes
   --  are POSIX and a removable one is enforced by the OS at write time);
   --  Windows answers True.
   function Uses_Dos_Filename_Rules (Path : String) return Boolean;

end Hostkit.Fs;
