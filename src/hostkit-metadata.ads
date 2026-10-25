with Ada.Calendar;
with Interfaces;

--  What the filesystem says about a file, when the hosts do not say it the same way.
--
--  These are read with one call on Linux (statx), a different one on macOS, and on
--  Windows with a set of calls that answer a differently-shaped question: Windows
--  has no mode bits and no uid/gid pair at all, only an owner SID in a security
--  descriptor. So a POSIX permission or ownership answer there is synthesised, or
--  honestly refused -- which is why every one of these reports whether it got an
--  answer instead of returning a plausible-looking default.
--
--  "NOT AVAILABLE" IS NOT "ZERO". Available => False means this host would not
--  tell, and the accompanying value is not a fact about the file. A caller that
--  displayed the returned 0 as the mode, or compared it, would be inventing
--  something the host declined to say. Permissions_Supported and
--  Ownership_Supported answer that question once, ahead of the per-file calls, so
--  a caller can leave the whole concept out of its interface on a host that has no
--  such notion rather than showing every file as mode 0.
--
--  Creating links and restricting a path to its owner are in Hostkit.Fs -- they
--  act on a file rather than ask about one. Setting ownership is here instead,
--  and Set_Ownership below says why: it is the write half of File_Ownership and
--  only means anything for the ids this package handed out.
package Hostkit.Metadata is

   subtype Identity_Field is Interfaces.Unsigned_64;

   --  A numeric user or group id: uid_t and gid_t are unsigned 32-bit on
   --  every POSIX host this crate has a body for, and every value is a real
   --  one -- an idmapped mount shows ids from 2**31 up, and NFS's nobody is
   --  4294967294. Natural ends at 2**31 - 1, and when these were Natural a
   --  file owned by such an id answered no ownership and no permissions at
   --  all. On Windows the number is one this package minted for an owner SID
   --  and always fits Natural, but the type is the same.
   type Account_Id is mod 2**32;

   --  Account_Id'Image without its leading space: "4294967294".
   function Account_Image (Id : Account_Id) return String is
     (Account_Id'Image (Id) (2 .. Account_Id'Image (Id)'Last));

   --  The outcome of reading an id out of text.
   type Parsed_Account_Id is record
      Valid : Boolean := False;
      Id    : Account_Id := 0;
   end record;

   --  Read a decimal id typed or stored as text: one or more ASCII digits and
   --  nothing else (no sign, no blanks, no base), at most 4294967295.
   --  Account_Id'Value is not this: it accepts blanks, underscores and
   --  16#FF#, and raises rather than answering for a value out of range.
   --
   --  @param Text Candidate decimal text.
   --  @return Valid => True with the id, or Valid => False and 0.
   function Parse_Account_Id (Text : String) return Parsed_Account_Id is
     (if Text'Length in 1 .. 10
        and then (for all Char of Text => Char in '0' .. '9')
        and then Long_Long_Integer'Value (Text) <= Long_Long_Integer (Account_Id'Last)
      then (Valid => True, Id => Account_Id (Long_Long_Integer'Value (Text)))
      else (Valid => False, Id => 0));

   --  Can Id be held by a caller that keeps ids as Natural?
   function Fits_Natural (Id : Account_Id) return Boolean is
     (Id <= Account_Id (Natural'Last));

   --  A no-follow identity for one directory entry. The generation fields
   --  carry birth time on POSIX and the upper half of a 128-bit file ID on
   --  Windows. Available is False rather than returning an inode alone when
   --  the host cannot distinguish reuse of that inode.
   type Entry_Identity is record
      Available       : Boolean := False;
      Volume          : Identity_Field := 0;
      File_Number     : Identity_Field := 0;
      Generation_High : Identity_Field := 0;
      Generation_Low  : Identity_Field := 0;
   end record;

   --  Metadata used to tell whether an entry changed without following it.
   --  Fields that a host does not have are zero; Available says whether the
   --  complete host-specific revision was obtained.
   type Entry_Revision is record
      Available            : Boolean := False;
      Modified_Seconds     : Identity_Field := 0;
      Modified_Nanoseconds : Identity_Field := 0;
      Changed_Seconds      : Identity_Field := 0;
      Changed_Nanoseconds  : Identity_Field := 0;
      Size                 : Identity_Field := 0;
      Mode                 : Identity_Field := 0;
      User_Id              : Identity_Field := 0;
      Group_Id             : Identity_Field := 0;
   end record;

   --  Inspect Path itself, including a symbolic link rather than its target.
   function Entry_Identity_Of (Path : String) return Entry_Identity;
   function Entry_Revision_Of (Path : String) return Entry_Revision;

   type Metadata_Update_Kind is (Update_Permissions, Update_Ownership);

   type Metadata_Update_Result is record
      Success        : Boolean := False;
      Previous       : Identity_Field := 0;
      Previous_Group : Identity_Field := 0;
      Identity       : Entry_Identity;
   end record;

   --  Change metadata through a handle that pins Path to one filesystem entry.
   --  Symbolic links are refused. When Check_Expected is True, the mutation is
   --  performed only when the held entry has Expected's identity. Previous
   --  values and the identity are captured from that same held entry, so a
   --  pathname replacement cannot redirect a history or undo operation.
   --
   --  Owner_Name and Group_Name are used only on hosts whose native ownership
   --  API needs names as well as the ids Hostkit reported. Max_Previous lets a
   --  narrower caller refuse an undo value it could not retain losslessly.
   function Update_Entry_Metadata
     (Path           : String;
      Expected       : Entry_Identity;
      Check_Expected : Boolean;
      Kind           : Metadata_Update_Kind;
      Value          : Identity_Field;
      Group          : Identity_Field;
      Max_Previous   : Identity_Field;
      Owner_Name     : String := "";
      Group_Name     : String := "") return Metadata_Update_Result;

   --  What a filesystem has room for. All byte and inode counts saturate: a value
   --  beyond this host's range is clamped to 'Last rather than wrapping.
   --
   --  The *_Known flags exist because a host can answer some of this and not the
   --  rest -- Windows reports free and total bytes but has no inode count to give,
   --  so Inodes_Known is False there and Inode_Count says nothing.
   type Volume_Capacity is record
      Available        : Boolean := False;
      Capacity_Bytes   : Long_Long_Integer := 0;
      Free_Bytes       : Long_Long_Integer := 0;
      Inode_Count      : Long_Long_Integer := 0;
      Free_Inode_Count : Long_Long_Integer := 0;
      Name_Max         : Natural := 0;
      Read_Only        : Boolean := False;
      Inodes_Known     : Boolean := False;
      Name_Max_Known   : Boolean := False;
      Read_Only_Known  : Boolean := False;
   end record;

   --  The capacity of the filesystem holding Path.
   --
   --  @param Path A path located on the volume to ask about.
   --  @return Available is False when the host would not answer.
   function Volume_Capacity_Of (Path : String) return Volume_Capacity;

   --  When this file was created -- birth time, not the modification time.
   --
   --  Not every filesystem records it even on a host whose API can ask: ext4 does,
   --  older filesystems do not, which is why this reports availability per file
   --  rather than per host.
   --
   --  @param Path Path to inspect.
   --  @param Available True when a creation time was obtained.
   --  @return The birth time when Available; otherwise a sentinel past date that
   --          is not a fact about the file.
   function File_Creation_Time
     (Path      : String;
      Available : out Boolean)
      return Ada.Calendar.Time;

   --  The last access time of Path.
   --
   --  @param Path Path to inspect.
   --  @param Available True when an access time was obtained.
   --  @return The access time when Available; otherwise a sentinel past date that
   --          is not a fact about the file.
   function File_Access_Time
     (Path      : String;
      Available : out Boolean)
      return Ada.Calendar.Time;

   --  The POSIX permission bits of Path: the low 12 mode bits -- setuid, setgid,
   --  sticky, and the nine rwxrwxrwx bits.
   --
   --  @param Path Path to inspect.
   --  @param Available True when permission bits were obtained.
   --  @return Bits in 0 .. 8#7777#, or 0 when Available is False.
   function File_Permission_Bits
     (Path      : String;
      Available : out Boolean)
      return Natural;

   --  Set the POSIX permission bits of Path -- chmod(2).
   --
   --  Hostkit.Fs.Make_Private is the narrower, portable version of this: restrict
   --  a path to its owner, which is a request every host can honour some way.
   --  This one takes literal POSIX bits, so it only means something where they do.
   --
   --  @param Path Path whose mode is changed.
   --  @param Mode New permission bits.
   --  @return True when the host applied it.
   function Set_Permissions
     (Path : String;
      Mode : Natural)
      return Boolean;

   --  Set Path's access and modification timestamps independently.
   --
   --  @param Path Path whose timestamps are changed.
   --  @param Access_Time New access timestamp.
   --  @param Modified_Time New modification timestamp.
   --  @return True when the host applied both timestamps.
   function Set_File_Times
     (Path          : String;
      Access_Time   : Long_Long_Integer;
      Modified_Time : Long_Long_Integer)
      return Boolean;

   --  Does this host have POSIX permission bits to read and set at all? Ask once,
   --  rather than per file, to decide whether the concept exists here.
   function Permissions_Supported return Boolean;

   --  Are the bits File_Permission_Bits reports the host's own, or a rendering?
   --
   --  A separate question from Permissions_Supported, which is True on Windows
   --  because the request can be honoured there -- it writes an ACL and reads a
   --  mode back out of one. That mode is this package's rendering of an ACL into
   --  POSIX shape, not a field the filesystem stores, so it need not agree
   --  bit-for-bit with whatever else on that host claims to answer the same
   --  question.
   --
   --  A caller that wants to derive something from the bits -- "is this readable
   --  by its owner" -- rather than display them should ask this first, and ask
   --  the host directly where it answers False.
   function Mode_Bits_Are_Native return Boolean;

   --  The numeric owner and group of Path.
   --
   --  @param Path Path to inspect.
   --  @param User_Id Owning user id when Available.
   --  @param Group_Id Owning group id when Available.
   --  @param Available True when ownership ids were obtained.
   procedure File_Ownership
     (Path      : String;
      User_Id   : out Account_Id;
      Group_Id  : out Account_Id;
      Available : out Boolean);

   --  The permission bits and the ownership of Path, in one call to the host.
   --
   --  Exactly File_Permission_Bits and File_Ownership together, and the values are
   --  identical -- but where the host can answer both from one query (Linux: a
   --  single statx with mode|uid|gid) it does, which halves the metadata syscalls
   --  a directory listing pays per file. Hosts that cannot delegate to the two
   --  individual calls and are therefore behaviour-identical either way.
   --
   --  The two answers are independent: an ownership the host would not give
   --  never takes the mode with it. Mode_Available is exactly what
   --  File_Permission_Bits would have said.
   --
   --  @param Path Path to inspect.
   --  @param Mode_Bits Permission bits in 0 .. 8#7777# when Mode_Available.
   --  @param Mode_Available True when permission bits were obtained.
   --  @param User_Id Owning user id when Ownership_Available.
   --  @param Group_Id Owning group id when Ownership_Available.
   --  @param Ownership_Available True when ownership ids were obtained.
   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Account_Id;
      Group_Id            : out Account_Id;
      Ownership_Available : out Boolean);

   --  Set the owner and group of Path to ids this package handed out.
   --
   --  NOT the same operation as Hostkit.Fs.Set_Owner, which is why both exist.
   --  That one applies a POSIX uid/gid pair that came from somewhere else -- an
   --  archive entry, a manifest -- and declines on Windows, where those numbers
   --  mean nothing and inventing an owner from them would be a guess.
   --
   --  This one closes the loop with File_Ownership: it sets an identity this
   --  package reported for some file, so on Windows the number is one it minted
   --  from a real owner SID and can therefore turn back into that SID. An id
   --  from anywhere else fails here, and says so rather than writing an owner
   --  the caller did not mean.
   --
   --  Changing an owner is privileged on POSIX, so an unprivileged process
   --  normally gets False for anything but a no-op.
   --
   --  @param Path Path whose ownership is changed.
   --  @param User_Id New owning user id.
   --  @param Group_Id New owning group id.
   --  @return True when the host applied it.
   function Set_Ownership
     (Path     : String;
      User_Id  : Account_Id;
      Group_Id : Account_Id)
      return Boolean;

   --  Does this host have file ownership to read and set? See Set_Ownership
   --  above for why setting it is a separate question from having it.
   function Ownership_Supported return Boolean;

   --  Do Left and Right name the same underlying file?
   --
   --  The question a case-insensitive host makes necessary: there, "report.txt"
   --  and "Report.txt" are one file, and a caller renaming one to the other must
   --  tell that apart from a collision with a genuinely different file. Getting it
   --  wrong destroys data -- a rename that treats the two as distinct can delete
   --  the source it was supposed to be renaming.
   --
   --  POSIX compares device and inode, which also makes two hard links to one
   --  inode answer True -- correctly: they are the same file. Windows compares the
   --  normalised path case-insensitively, its filesystem being case-insensitive.
   --  A host with no way to tell compares the paths exactly, which can only ever
   --  under-report.
   --
   --  @param Left First path.
   --  @param Right Second path.
   --  @return True when both exist and are the same file.
   function Same_File (Left : String; Right : String) return Boolean;

   --  A stamp of Path's contents as the filesystem records them: equal while
   --  nothing has written to the file, different after any write -- its
   --  modification and status-change times to the nanosecond, its size and
   --  its file number. For telling whether a file changed without reading
   --  it; never compared across hosts.
   --
   --  @param Path Path to inspect.
   --  @param Available True when the host gave a stamp; False where it has
   --    no times that fine, and the caller must look another way.
   --  @return The stamp when Available; "" otherwise.
   function Change_Stamp
     (Path      : String;
      Available : out Boolean)
      return String;

   --  The filesystem device identifier that contains Path.
   --
   --  POSIX find -xdev needs to compare the device id of a starting point with
   --  each candidate before descending. Available is False where the host cannot
   --  provide a stable comparable id.
   function Device_Id
     (Path      : String;
      Available : out Boolean)
      return Long_Long_Integer;

   --  A user name to its numeric id -- getpwnam(3) and its equivalents.
   --
   --  @param Name User name to resolve.
   --  @param Found True when the name resolved.
   --  @return The id when Found, otherwise 0.
   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Account_Id;

   --  A group name to its numeric id -- getgrnam(3) and its equivalents.
   --
   --  @param Name Group name to resolve.
   --  @param Found True when the name resolved.
   --  @return The id when Found, otherwise 0.
   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Account_Id;

   --  A numeric user id back to its name -- getpwuid(3) and its equivalents.
   --
   --  @param Id User id to resolve.
   --  @return The name, or the empty string when it does not resolve.
   function User_Name_For_Id (Id : Account_Id) return String;

   --  A numeric group id back to its name -- getgrgid(3) and its equivalents.
   --
   --  @param Id Group id to resolve.
   --  @return The name, or the empty string when it does not resolve.
   function Group_Name_For_Id (Id : Account_Id) return String;

   --  The same questions for a caller that holds ids as Natural, which every
   --  one did before Account_Id. Each answers as its Account_Id twin does,
   --  except that an id above Natural'Last cannot be handed back: such an
   --  owner reads as Available/Found => False (the mode, in
   --  File_Mode_And_Ownership, is still reported). Prefer the Account_Id
   --  forms; these keep existing consumers building.

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Natural;
      Group_Id  : out Natural;
      Available : out Boolean);

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Natural;
      Group_Id            : out Natural;
      Ownership_Available : out Boolean);

   function Set_Ownership
     (Path     : String;
      User_Id  : Natural;
      Group_Id : Natural)
      return Boolean is
     (Set_Ownership (Path, Account_Id (User_Id), Account_Id (Group_Id)));

   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural;

   function User_Name_For_Id (Id : Natural) return String is
     (User_Name_For_Id (Account_Id (Id)));

   function Group_Name_For_Id (Id : Natural) return String is
     (Group_Name_For_Id (Account_Id (Id)));

end Hostkit.Metadata;
