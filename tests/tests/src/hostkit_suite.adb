with AUnit.Assertions;
with AUnit;
with AUnit.Test_Cases;

with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces.C.Strings;
with Ada.Strings.Unbounded;
with GNAT.OS_Lib;

with Hostkit;
with Hostkit_Shell_Cases;
with Hostkit_Test_Skips;
with Hostkit.Filesystem_Rules;
with Ada.Streams;

with Hostkit.Descriptors;
with Hostkit.Directory_Listing;
with Hostkit.Directory_Write_Access;
with Hostkit.Durability;
with Hostkit.Errors;
with Hostkit.Fs;
with Hostkit.Environment;
with Hostkit.Host;
with Hostkit.Lease_Files;
with Hostkit.Linux_Abi;
with Hostkit.Metadata;
with Hostkit.Metadata_Copy;
with Hostkit.Mounts;
with Hostkit.Path_Text;
with Hostkit.Resources;
with Hostkit.Process;
with Hostkit.Private_Paths;
with Hostkit.Regular_Files;
with Hostkit.Shell;
with Hostkit.Trash;
with Hostkit.Watch;
with Hostkit.Windows_Command_Line;
with Hostkit.Windows_Errors;
with Hostkit.Windows_Paths;
with Hostkit.Command_Line;

package body Hostkit_Suite is
   use AUnit.Assertions;
   use Ada.Strings.Unbounded;
   use type Hostkit.Host.Kind;
   use type Hostkit.Metadata.Account_Id;

   --  A test with nothing to check on this host says so, and is counted:
   --  see Hostkit_Test_Skips.
   procedure Skip (Test : String; Reason : String) renames Hostkit_Test_Skips.Skip;

   --  The suite's own directory: noop and failing are built beside it.
   function Companion (Name : String) return String is
      Self : constant String := Ada.Command_Line.Command_Name;
      Dir  : constant String := Ada.Directories.Containing_Directory (Self);
   begin
      if Ada.Directories.Exists (Ada.Directories.Compose (Dir, Name & ".exe")) then
         return Ada.Directories.Compose (Dir, Name & ".exe");
      end if;

      return Ada.Directories.Compose (Dir, Name);
   exception
      when others =>
         return Name;
   end Companion;

   --  Windows: PowerShell stands for the shell. It starts the sleeper
   --  companion hanging, records its process id, then runs Then_Run -- so the
   --  sleeper is what the group's leader started, in the leader's job.
   function Windows_Leader (Pid_Path : String; Then_Run : String) return Hostkit.String_Vectors.Vector is
      Arguments : Hostkit.String_Vectors.Vector;
   begin
      Arguments.Append (To_Unbounded_String ("-NoProfile"));
      Arguments.Append (To_Unbounded_String ("-NonInteractive"));
      Arguments.Append (To_Unbounded_String ("-Command"));
      Arguments.Append
        (To_Unbounded_String
           ("$p = Start-Process -FilePath '" & Companion ("sleeper") & "' -ArgumentList '--hang'"
            & " -NoNewWindow -PassThru; Set-Content -LiteralPath '" & Pid_Path & "' -Value $p.Id -NoNewline; "
            & Then_Run));
      return Arguments;
   end Windows_Leader;

   --  Windows PowerShell, where Windows is.
   function Power_Shell return String is
     (Hostkit.Environment.Value ("SystemRoot", "C:\Windows") & "\System32\WindowsPowerShell\v1.0\powershell.exe");

   --  Somewhere to put captured output. The host's own temporary directory, because /tmp
   --  is not a place Windows has.
   function Scratch return String is
      Base : constant String :=
        (if Ada.Environment_Variables.Exists ("TMPDIR")
         then Ada.Environment_Variables.Value ("TMPDIR")
         elsif Ada.Environment_Variables.Exists ("TEMP")
         then Ada.Environment_Variables.Value ("TEMP")
         else "/tmp");
   begin
      return Base;
   end Scratch;

   --  A test whose links the host refused says so on standard error, and
   --  fails where HOSTKIT_TESTS_NEED_LINKS is set (as CI sets it), so a
   --  host that skips the link parts cannot pass them unseen.
   procedure Links_Refused (What : String) is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "note: " & What & ": the host refused to make a link; those parts were not run");
      AUnit.Assertions.Assert
        (not Ada.Environment_Variables.Exists ("HOSTKIT_TESTS_NEED_LINKS"),
         What & ": links are needed here and the host refused one");
   end Links_Refused;

   procedure Delete_Tree_If_Present (Path : String) is
   begin
      if Path /= "" and then Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_Tree (Path);
      end if;
   exception
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         null;
   end Delete_Tree_If_Present;

   --  Setting a mode is the fixture here, not the thing under test, so it goes straight
   --  to chmod(2) rather than through Hostkit.Fs.Make_Private, which is one of the
   --  things being tested. A no-op on Windows, where the callers guard for it anyway.
   procedure Chmod (Path : String; Mode : Interfaces.C.int) is
      function C_Chmod (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int)
        return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "chmod";

      C_Path  : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Ignored : constant Interfaces.C.int := C_Chmod (C_Path, Mode);
   begin
      pragma Unreferenced (Ignored);
      Interfaces.C.Strings.Free (C_Path);
   end Chmod;

   --  Write a file with something in it, as a fixture.
   procedure Write_File (Path : String; Text : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, Text);
      Ada.Text_IO.Close (File);
   end Write_File;

   --  The first line of a file, with nothing either side of it.
   function First_Line (Path : String) return String is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);

      if Ada.Text_IO.End_Of_File (File) then
         Ada.Text_IO.Close (File);
         return "";
      end if;

      declare
         Line : constant String := Ada.Text_IO.Get_Line (File);
      begin
         Ada.Text_IO.Close (File);
         return Ada.Strings.Fixed.Trim (Line, Ada.Strings.Both);
      end;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return "";
   end First_Line;

   function File_Contains (Path : String; Text : String) return Boolean is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);

      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            if Ada.Strings.Fixed.Index (Line, Text) > 0 then
               Ada.Text_IO.Close (File);
               return True;
            end if;
         end;
      end loop;

      Ada.Text_IO.Close (File);
      return False;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return False;
   end File_Contains;

   --  Notification is asynchronous on every host, so a change is waited for
   --  rather than expected on the first poll -- up to five seconds, which is far
   --  beyond any plausible delivery and still bounded.
   Settle : constant Duration := 0.05;
   Rounds : constant Natural := 100;

   function Wait_For_Change (State : in out Hostkit.Watch.Watch_State) return Boolean is
   begin
      for Unused_Round in 1 .. Rounds loop
         if Hostkit.Watch.Poll (State) then
            return True;
         end if;

         delay Settle;
      end loop;

      return False;
   end Wait_For_Change;

   --  Swallow the events the fixture's own setup produced, so the assertions
   --  that follow are about the change the test made.
   procedure Drain (State : in out Hostkit.Watch.Watch_State) is
      Ignored : Boolean;
   begin
      delay Settle;
      Ignored := Hostkit.Watch.Poll (State);
      pragma Unreferenced (Ignored);
   end Drain;

   procedure Touch (Directory : String; Name : String) is
      Output : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create
        (Output, Ada.Text_IO.Out_File, Ada.Directories.Compose (Directory, Name));
      Ada.Text_IO.Put_Line (Output, "x");
      Ada.Text_IO.Close (Output);
   end Touch;

   procedure Test_Quoting (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Windows_Command_Line_Quoting
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Windows_Long_Path_Form
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A Windows name that is not well-formed UTF-16 reads as WTF-8 and goes
   --  back as the same units; a name that is UTF-8 converts as it always did.
   procedure Test_Windows_Names_Round_Trip_As_WTF_8
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A Windows system error code is read as the errno a caller asks about,
   --  and a refused create says why through errno on every host.
   procedure Test_Windows_Errors_Read_As_Errno
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Delete_Empty_Directory
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A hard link to a file past Windows' 260-character limit: the existing
   --  file's path needs the long form as much as the new link's does. The
   --  deep path is reached by renaming short folders to long names, which
   --  every host can do whatever its path limit.
   procedure Test_Hard_Link_To_A_Long_Path
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Path_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  Roots, leaves and parents read from text alone, for the drive, share
   --  and long forms and for components past GNAT's Windows limit.
   procedure Test_Path_Text_Roots_Leaves_And_Parents
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  An entry's kind past Windows' 260-character limit and GNAT's
   --  256-character name, reached by renaming short names to long ones.
   procedure Test_Kind_Of_A_Long_Path
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  Size_Of, Modification_Time_Of and the owner's access answer as
   --  Ada.Directories and GNAT.OS_Lib do, for files, folders and links.
   procedure Test_Size_And_Modification_Time_Agree_With_Ada_Directories
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The same past Windows' 260-character limit, reached by renaming short
   --  folders to long names, against what GNAT said while they were short.
   procedure Test_Size_And_Modification_Time_Past_The_Path_Limit
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A modification time set to a known UTC instant reads back as that
   --  instant whatever the local zone.
   procedure Test_Modification_Time_Is_Read_In_UTC
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  Making directories, creating, streaming, listing and deleting files
   --  in a folder past Windows' 260-character limit, reached by renaming
   --  short names to long ones; on POSIX it simply works.
   procedure Test_File_Operations_Past_The_Path_Limit
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A path made absolute and its dots resolved from the text alone, for
   --  POSIX, drive, share and long forms.
   procedure Test_Path_Text_Absolute
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Has_Window_Server
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Removable_Media_Listed_Once
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The user places each host's conventions give, read from a controlled
   --  environment: the whole list, path and kind, and the other hosts'
   --  variables left unread.
   procedure Test_User_Places_Follow_The_Environment
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The font folders each host keeps: the system's, then the user's own.
   procedure Test_Font_Directories_Are_The_Hosts
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The volume places each host lists: its fixed folders, or on Windows
   --  the roots of the drives it has.
   procedure Test_Volume_Places_Are_The_Hosts
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Read_Only_File_Syncs_Promptly
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A file someone holds without sharing writes is synced once they let
   --  go: Windows' Sync_File waits a sharing violation out.
   procedure Test_A_Held_File_Is_Synced_Once_Let_Go
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Windows_Attributes_Are_Copied
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  Linux lists its mounts, "/" among them, with escapes decoded; a host
   --  without a table lists none, and a pseudo filesystem's source is no disk.
   procedure Test_Mount_Table (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   --  The host's default opener names the file by the caller's token, last;
   --  Windows always has one (cmd /c start).
   procedure Test_Default_Opener (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   --  The per-host tables: errno numbers, where volumes live, which mount
   --  types are internal or networked, the opener a settings file keeps, and
   --  Windows root syntax read on any host.
   procedure Test_Host_Tables (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Filesystem_Rules (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Run_Reports_Exit_Status (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Launch_Does_Not_Wait (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Is_Runnable (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Folds_Name_Case (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Current_User_Account (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Path_Containment (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Environment_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Shell_Quoting_Holds (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Captured_Run (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Captured_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Timeout_Kills (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   --  Stopped as a group, a program takes what it started with it: a shell
   --  killed on a deadline leaves no child of its own running.
   procedure Test_Group_Stops_Whole (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   --  A group whose leader ends well takes what it left running with it:
   --  a program sent to the background does not run on after it.
   procedure Test_Group_Ends_With_Leader (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   --  A clean wrapper holds no environment of the caller's: what the
   --  program can read of its parent says nothing it was not given.
   procedure Test_Clean_Wrapper (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Accessible_By_Others (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Directory_Accessible_By_Others
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Create_Temporary_Directory
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A dot is not the only way to hide an entry: Windows and macOS keep a
   --  hidden flag of their own, set here with the host's own tool.
   procedure Test_Is_Hidden
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Move_No_Replace_Outcome
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The fallback a filesystem without a native no-replace rename gets (NFS,
   --  SMB, FUSE). Exercised directly: the local filesystem has the native one.
   procedure Test_Move_Without_Native_No_Replace
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Make_Private (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Private_Paths (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Delete_Tree_No_Follow
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A folder with more entries than one read takes is deleted in batches,
   --  not refused half-way.
   procedure Test_Delete_Tree_Large_Folder
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Relative_Link_Is_Read_From_Its_Folder
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Read_Beneath
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Change_Stamp
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Parent_Watch
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Directory_Listing
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Locate (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_The_Host_Is_Not_Guessed (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Where_This_Program_Is (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Where_This_User_Lives (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_Elevation_Is_Asked_Not_Assumed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  What "this host will run it" means, pinned across the mode matrix, so a
   --  cheaper implementation has to agree with the one it replaces rather than
   --  merely look equivalent.
   --  A cache and the application data directory must not be the same place.
   --  They are on no host, and the reason is not tidiness: the roaming profile
   --  travels between machines and Application Support is backed up, so a cache
   --  put in either comes back from somewhere it was never meant to survive.
   procedure Test_Cache_And_Data_Are_Different_Places
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Executability_Across_Modes (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_A_Directory_Is_Not_Executable (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_The_Host_Answers_For_Its_Own_Trash
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Recycle_Bin_Record_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_The_Recycle_Bin_Says_Where_An_Item_Went
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_The_Host_Locale_Is_Asked_Of_The_Host
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The path of the running executable, resolved.
   --  Asking whether a stream is a terminal is answered, per stream.
   --
   --  A caller uses this to decide whether to colour output, draw progress or
   --  hold a conversation. The question is about the stream and not about the
   --  program: a suite like this one usually runs with its output captured
   --  and its input from nowhere, so the honest expectation here is not that
   --  any particular stream is a terminal but that each is answered
   --  separately and none of them raises.
   --  Joining path segments produces one separator, whatever it is given.
   --
   --  Ada.Directories.Compose is the portable-looking answer that is not:
   --  its Name is a simple name, so a multi-segment tail is outside what it
   --  is for. This is the operation callers actually want, and it is here
   --  rather than in each of them because what goes between two segments is
   --  the host's business.
   procedure Test_Joining_Paths_Uses_One_Separator
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Terminal_Streams_Are_Answered_Separately
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_The_Executable_Path_Locates_This_Program
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Metadata_Reports_What_It_Could_Not_Get
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Mode_And_Ownership_Agree_With_The_Separate_Calls
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Metadata_Update_Is_Bound_To_The_Held_Entry
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A permission edit changes only what its bits concern: on Windows the
   --  entry keeps what it inherits, and the access record it reports puts
   --  the DACL back exactly.
   procedure Test_A_Permission_Edit_Keeps_Inherited_Access
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Lease_File_Pins_Locks_And_Transfers_Bytes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Same_File_Sees_Through_A_Second_Name
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Entry_Identity_And_Revision_Do_Not_Follow_Links
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Device_Id_Reports_A_Comparable_Volume
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Name_Round_Trips_Through_Its_Id
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  Ids from 2**31 up are real -- an idmapped mount's, NFS's nobody at
   --  4294967294 -- and no fixture here owns a file as one, so the type that
   --  carries them is checked on its own: every 32-bit value is held, printed
   --  and read back exactly, and text that is not one is refused rather than
   --  raised on.
   procedure Test_A_Large_Account_Id_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The open(2) flags that differ by Linux machine. Pure logic over the
   --  uname machine name, so every host checks every machine.
   procedure Test_Linux_Open_Flags_Follow_The_Machine
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The open is the check: a regular file opens, and what is not one --
   --  a folder, a link when links are not to be followed -- does not.
   procedure Test_Only_A_Regular_File_Opens
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A read-only folder of one's own is lent its owner write bit through
   --  the held descriptor, and given its mode back by Finish.
   procedure Test_A_Read_Only_Folder_Is_Lent_Write_Access
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  On Windows a mode is a DACL. Setting one on a directory must not reach
   --  into what it holds: a file there that had only the ACEs it inherited
   --  would be left readable by no one.
   procedure Test_A_Folder_Mode_Leaves_Its_Files_Readable
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Volume_Has_Room (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_A_Fresh_Watch_Is_Inactive (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_An_Unwatchable_Path_Fails_Quietly (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   procedure Test_The_Watch_Notices_Changes (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   type Hostkit_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Hostkit_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Hostkit_Test_Case);

   --  AUnit reports when the whole suite ends, so a suite that hangs prints
   --  nothing at all -- which is what two thirty-minute Windows runs came back
   --  with. This says which routine is starting, and flushes, so a run that is
   --  killed still names the one that did not finish.
   overriding procedure Set_Up (T : in out Hostkit_Test_Case);

   overriding function Name (T : Hostkit_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("hostkit");
   end Name;

   Started : Natural := 0;

   overriding procedure Set_Up (T : in out Hostkit_Test_Case) is
      pragma Unreferenced (T);
   begin
      Started := Started + 1;
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "-> hostkit routine" & Natural'Image (Started));
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
   end Set_Up;

   --  The device that reads as nothing is there, and reads as nothing.
   --
   --  A caller reaches for this when it must give a program a stream and has
   --  none to give -- a job started into the background on a host with no job
   --  control, which cannot share the keyboard with the shell that started it.
   --  What that caller needs is end of input, immediately: a path that opened
   --  and then blocked would hang the program it was trying to protect.
   procedure Test_The_Null_Device_Reads_As_Nothing
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_The_Null_Device_Reads_As_Nothing
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_An_Identity_Reads_Beside_Another_Reader
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_An_Identity_Reads_Beside_Another_Reader
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The suite is started with no arguments, so the two answers must agree
   --  on that -- and on a host where the command line has to be asked for and
   --  split (Windows: GetCommandLineW plus CommandLineToArgvW), agreeing at
   --  all is what proves that path works. Where it cannot be asked, the body
   --  falls back to the runtime and the two are the same by construction.
   procedure Test_Command_Line_Arguments
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  What was written is put on the device: a file's contents and a
   --  directory's entries, where the host can say so; where it cannot, it
   --  says that, never that it did.
   procedure Test_Writes_Are_Made_Durable (T : in out AUnit.Test_Cases.Test_Case'Class) is separate;

   overriding procedure Register_Tests (T : in out Hostkit_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Quoting'Access, "shell : the quoting matches the shell it quotes for");
      Register_Routine
        (T, Test_Mount_Table'Access, "mounts : the host's mount table, decoded, or none where it keeps none");
      Register_Routine
        (T, Test_Default_Opener'Access, "process : the default opener names the file by the caller's token");
      Register_Routine
        (T, Test_Host_Tables'Access, "host : errno, volume places, mount kinds, portable opener, Windows roots");
      Register_Routine
        (T, Test_Writes_Are_Made_Durable'Access,
         "durability : what was written is put on the device, or it is said that it cannot be");
      Register_Routine
        (T, Test_Command_Line_Arguments'Access,
         "process : the arguments are the ones the process was started with");
      Register_Routine
        (T, Test_Windows_Command_Line_Quoting'Access,
         "process : the Windows CRT argument quoting round-trips");
      Register_Routine
        (T, Test_Windows_Long_Path_Form'Access,
         "process : a long Windows path is given the \\?\ form only when that keeps its meaning");
      Register_Routine
        (T, Test_Windows_Names_Round_Trip_As_WTF_8'Access,
         "process : a Windows name with a lone surrogate reads as WTF-8 and goes back unchanged");
      Register_Routine
        (T, Test_Windows_Errors_Read_As_Errno'Access,
         "errors : a Windows error code is read as errno, and a refused create says why");
      Register_Routine
        (T, Test_Delete_Empty_Directory'Access,
         "fs : only an empty directory is deleted, and a refusal is an answer");
      Register_Routine
        (T, Test_Hard_Link_To_A_Long_Path'Access,
         "fs : a hard link reaches a file past the Windows path limit");
      Register_Routine
        (T, Test_Path_Text'Access,
         "fs : path text splits Windows and POSIX paths and finds a share's root on any host");
      Register_Routine
        (T, Test_Path_Text_Roots_Leaves_And_Parents'Access,
         "fs : path text finds a root, a leaf and a parent for drive, share and long paths on any host");
      Register_Routine
        (T, Test_Kind_Of_A_Long_Path'Access,
         "fs : an entry's kind is read past the Windows path limit");
      Register_Routine
        (T, Test_Size_And_Modification_Time_Agree_With_Ada_Directories'Access,
         "fs : size, modification time and owner access agree with Ada.Directories and GNAT.OS_Lib");
      Register_Routine
        (T, Test_Size_And_Modification_Time_Past_The_Path_Limit'Access,
         "fs : size, modification time and owner access are read past the Windows path limit");
      Register_Routine
        (T, Test_Modification_Time_Is_Read_In_UTC'Access,
         "fs : a modification time is read in UTC whatever the local zone");
      Register_Routine
        (T, Test_File_Operations_Past_The_Path_Limit'Access,
         "fs : directories, files, streams and listings work past the Windows path limit");
      Register_Routine
        (T, Test_Path_Text_Absolute'Access,
         "fs : path text makes a path absolute and resolves its dots on any host");
      Register_Routine
        (T, Test_Has_Window_Server'Access,
         "host : a window server is an X or Wayland display on Linux, always there elsewhere");
      Register_Routine
        (T, Test_Removable_Media_Listed_Once'Access,
         "fs : removable media are listed by the volume places alone");
      Register_Routine
        (T, Test_User_Places_Follow_The_Environment'Access,
         "fs : the user places are the host's own, read from its environment");
      Register_Routine
        (T, Test_Font_Directories_Are_The_Hosts'Access,
         "fs : the font folders are the host's own, the system's before the user's");
      Register_Routine
        (T, Test_Volume_Places_Are_The_Hosts'Access,
         "mounts : the volume places are the host's folders, or its drives' roots");
      Register_Routine
        (T, Test_Read_Only_File_Syncs_Promptly'Access,
         "durability : a read-only file syncs at once, without waiting out write retries");
      Register_Routine
        (T, Test_A_Held_File_Is_Synced_Once_Let_Go'Access,
         "durability : a file held against writers is synced once it is let go");
      Register_Routine
        (T, Test_Windows_Attributes_Are_Copied'Access,
         "metadata copy : a hidden Windows file's copy is hidden too");
      Register_Routine
        (T, Test_Filesystem_Rules'Access,
         "fs : DOS-ruled filesystems are recognised from the mount table");
      Register_Routine
        (T, Test_Run_Reports_Exit_Status'Access, "process : Run reports the program's own exit status");
      Register_Routine
        (T, Test_Launch_Does_Not_Wait'Access, "process : Launch starts and does not wait");
      Register_Routine (T, Test_Is_Runnable'Access, "process : a path or a name is runnable only if it can start");
      Register_Routine (T, Test_Terminal'Access, "process : the default terminal and how it is opened in a folder");
      Register_Routine
        (T, Test_Folds_Name_Case'Access, "fs : whether a volume folds name case is what it does");
      Register_Routine
        (T, Test_Current_User_Account'Access, "process : the current user account owns what the process makes");
      Register_Routine
        (T, Test_Path_Containment'Access, "fs : separators, containment and rebasing follow the host");
      Register_Routine
        (T, Test_Environment_Value'Access,
         "process : environment values are read through hostkit");
      Register_Routine
        (T, Test_Shell_Quoting_Holds'Access, "shell : an argument cannot become a second command");
      Register_Routine
        (T, Test_A_Directory_Is_Not_Executable'Access, "fs : a directory is not executable");
      Register_Routine
        (T, Test_Executability_Across_Modes'Access,
         "fs : what this host will run, across the mode matrix");
      Register_Routine
        (T, Test_Cache_And_Data_Are_Different_Places'Access,
         "fs : a cache does not live in the application data directory");
      Register_Routine
        (T, Test_Accessible_By_Others'Access, "fs : a group- or world-readable file is flagged");
      Register_Routine
        (T,
         Test_Directory_Accessible_By_Others'Access,
         "fs : a group- or world-readable directory is flagged");
      Register_Routine
        (T, Test_Create_Temporary_Directory'Access,
         "fs : a temporary directory is created privately");
      Register_Routine
        (T, Test_Is_Hidden'Access, "fs : a host's hidden flag is read, apart from the leading dot");
      Register_Routine
        (T, Test_Move_No_Replace_Outcome'Access,
         "fs : a no-replace move says why it failed");
      Register_Routine
        (T, Test_Move_Without_Native_No_Replace'Access,
         "fs : without a native no-replace rename a move still never replaces");
      Register_Routine
        (T, Test_Make_Private'Access, "fs : a path is restricted to its owner");
      Register_Routine
        (T, Test_Private_Paths'Access,
         "private paths : creation and open-file hardening are owner-only");
      Register_Routine
        (T, Test_Delete_Tree_No_Follow'Access,
         "fs : secure tree deletion never follows a link outside the tree");
      Register_Routine
        (T, Test_Delete_Tree_Large_Folder'Access,
         "fs : secure tree deletion empties a folder larger than one read in batches");
      Register_Routine
        (T, Test_Relative_Link_Is_Read_From_Its_Folder'Access,
         "fs : a relative link's target is read from the link's folder");
      Register_Routine
        (T, Test_Change_Stamp'Access,
         "metadata : a change stamp tells a rewrite of the same size from an untouched file");
      Register_Routine
        (T, Test_Read_Beneath'Access,
         "fs : a file below a root is read without following a link on the way");
      Register_Routine
        (T, Test_Parent_Watch'Access,
         "parent watch : an orphan that asked to end with its parent ends");
      Register_Routine
        (T, Test_Directory_Listing'Access,
         "directory listing : each entry with its kind, links not followed");
      Register_Routine
        (T, Test_Locate'Access, "process : a program is found by name");
      Register_Routine
        (T, Test_The_Host_Is_Not_Guessed'Access, "host : the host identifies itself");
      Register_Routine
        (T, Test_Elevation_Is_Asked_Not_Assumed'Access,
         "host : elevation is asked of the host, not assumed");
      Register_Routine
        (T, Test_Where_This_Program_Is'Access,
         "fs : the host says where this program is");
      Register_Routine
        (T, Test_Where_This_User_Lives'Access,
         "fs : the host says where this user keeps things");
      Register_Routine
        (T, Test_Captured_Run'Access, "process : a captured run keeps stdout and stderr apart");
      Register_Routine
        (T, Test_Captured_Input'Access, "process : a captured run reads the file it was given");
      Register_Routine
        (T, Test_Timeout_Kills'Access, "process : a program that will not stop is stopped");
      Register_Routine
        (T, Test_Group_Stops_Whole'Access,
         "process : stopped as a group, a program takes what it started with it");
      Register_Routine
        (T, Test_Group_Ends_With_Leader'Access, "process : a group's leader ending ends what it left running");
      Register_Routine
        (T, Test_Clean_Wrapper'Access, "process : a clean wrapper holds none of the caller's environment");
      Register_Routine
        (T, Test_The_Host_Answers_For_Its_Own_Trash'Access,
         "trash : a host with no trash of its own declines and leaves the file alone");
      Register_Routine
        (T, Test_A_Recycle_Bin_Record_Round_Trips'Access,
         "trash : a recycle bin $I record encodes and decodes, versions 1 and 2");
      Register_Routine
        (T, Test_The_Recycle_Bin_Says_Where_An_Item_Went'Access,
         "trash : the recycle bin says where an item went, restores it and purges it, past MAX_PATH too");
      Register_Routine
        (T, Test_The_Host_Locale_Is_Asked_Of_The_Host'Access,
         "host : the locale is asked of the host, and declined where there is none");
      Register_Routine
        (T, Test_Joining_Paths_Uses_One_Separator'Access,
         "joining path segments produces one separator");
      Register_Routine
        (T, Test_Terminal_Streams_Are_Answered_Separately'Access,
         "terminal streams are answered separately and repeatably");

      Register_Routine
        (T, Test_The_Executable_Path_Locates_This_Program'Access,
         "the host names the running executable, resolved");
      Register_Routine
        (T, Test_Metadata_Reports_What_It_Could_Not_Get'Access,
         "metadata : what the host could not answer is reported, not invented");
      Register_Routine
        (T, Test_Mode_And_Ownership_Agree_With_The_Separate_Calls'Access,
         "metadata : the one-call mode+ownership read agrees with the two it replaces");
      Register_Routine
        (T, Test_Metadata_Update_Is_Bound_To_The_Held_Entry'Access,
         "metadata : updates stay bound to the held entry and report its old value");
      Register_Routine
        (T, Test_A_Permission_Edit_Keeps_Inherited_Access'Access,
         "metadata : a permission edit keeps inherited access, and its record puts the old one back");
      Register_Routine
        (T, Test_Lease_File_Pins_Locks_And_Transfers_Bytes'Access,
         "lease files : secure held identities combine locking and durable bytes");
      Register_Routine
        (T, Test_Same_File_Sees_Through_A_Second_Name'Access,
         "metadata : two names for one file are recognised as the same file");
      Register_Routine
        (T, Test_Entry_Identity_And_Revision_Do_Not_Follow_Links'Access,
         "metadata : entry identities and revisions inspect links without following them");
      Register_Routine
        (T, Test_Device_Id_Reports_A_Comparable_Volume'Access,
         "metadata : device ids identify the volume when the host reports them");
      Register_Routine
        (T, Test_A_Name_Round_Trips_Through_Its_Id'Access,
         "metadata : an owner name round-trips through its numeric id");
      Register_Routine
        (T, Test_Linux_Open_Flags_Follow_The_Machine'Access,
         "linux abi : O_NOFOLLOW and O_DIRECTORY take the machine's own values");
      Register_Routine
        (T, Test_Only_A_Regular_File_Opens'Access,
         "regular files : only a regular file opens, and a link only when followed");
      Register_Routine
        (T, Test_A_Read_Only_Folder_Is_Lent_Write_Access'Access,
         "directory write access : a read-only folder is lent owner write and given its mode back");
      Register_Routine
        (T, Test_A_Folder_Mode_Leaves_Its_Files_Readable'Access,
         "metadata : a folder's mode leaves the files in it readable");
      Register_Routine
        (T, Test_A_Large_Account_Id_Round_Trips'Access,
         "metadata : a user or group id from 2**31 up is held, printed and read back exactly");
      Register_Routine
        (T, Test_A_Volume_Has_Room'Access, "metadata : a mounted volume reports its capacity");
      Register_Routine
        (T, Test_A_Fresh_Watch_Is_Inactive'Access, "watch : a fresh watch is inactive");
      Register_Routine
        (T, Test_An_Unwatchable_Path_Fails_Quietly'Access,
         "watch : a directory that cannot be watched fails quietly");
      Register_Routine
        (T, Test_The_Watch_Notices_Changes'Access,
         "watch : the host's notification facility notices creations and deletions");
      Register_Routine
        (T, Test_The_Null_Device_Reads_As_Nothing'Access,
         "fs : the null device reads as nothing and takes what is written");
      Register_Routine
        (T, Test_An_Identity_Reads_Beside_Another_Reader'Access,
         "process : an identity reads while another reader has its files open");
   end Register_Tests;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Hostkit_Test_Case));

      --  The shell primitives are a separate case rather than more routines in
      --  the one above: that case is already long, and these have their own
      --  fixtures and their own reasons.
      Result.Add_Test
        (AUnit.Test_Cases.Test_Case_Access'(new Hostkit_Shell_Cases.Case_Type));
      return Result;
   end Suite;

end Hostkit_Suite;
