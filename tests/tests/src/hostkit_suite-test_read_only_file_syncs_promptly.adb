with Ada.Real_Time;

with Hostkit_Test_Native;

separate (Hostkit_Suite)
procedure Test_Read_Only_File_Syncs_Promptly
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Ada.Real_Time.Time;
   use type Ada.Real_Time.Time_Span;
   use type Hostkit.Durability.Outcome;
   Path    : constant String := Ada.Directories.Compose (Scratch, "hostkit-read-only-sync");
   File    : Ada.Text_IO.File_Type;
   Started : Ada.Real_Time.Time;
   Result  : Hostkit.Durability.Outcome;
begin
   if Ada.Directories.Exists (Path) then
      Assert (Hostkit.Metadata.Set_Permissions (Path, 8#644#), "a leftover is made writable again");
      Ada.Directories.Delete_File (Path);
   end if;
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put_Line (File, "kept");
   Ada.Text_IO.Close (File);
   --  As a copy is made read-only: the attribute on Windows (a mode there
   --  is an ACL, which leaves the file unsyncable), the mode elsewhere.
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      declare
         use type GNAT.OS_Lib.String_Access;
         Attrib : constant GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Locate_Exec_On_Path ("attrib.exe");
         Done   : Boolean := False;
      begin
         if Attrib /= null then
            GNAT.OS_Lib.Spawn (Attrib.all, GNAT.OS_Lib.Argument_String_To_List ("+R " & Path).all, Done);
         end if;
         Assert (Done, "the file is made read-only");
      end;
   else
      Assert (Hostkit.Metadata.Set_Permissions (Path, 8#444#), "the file is made read-only");
   end if;
   --  On Windows the sync used to retry the refused write-open for 1.1 s
   --  before it looked at the read-only attribute: per file, in a move.
   Assert (Hostkit_Test_Native.Is_Read_Only (Path), "the fixture is read-only before the sync");
   --  The monotonic clock: a wall clock stepped by the host's time service
   --  in the middle would make the bound say nothing.
   Started := Ada.Real_Time.Clock;
   Result := Hostkit.Durability.Sync_File (Path);
   Assert
     (Ada.Real_Time.Clock - Started < Ada.Real_Time.Milliseconds (500),
      "a read-only file syncs without waiting out retries");
   Assert (Result /= Hostkit.Durability.Failed, "and it syncs");
   --  Windows drops the attribute to flush and must put it back: a copy
   --  made read-only that a sync left writable has lost what it was given.
   Assert (Hostkit_Test_Native.Is_Read_Only (Path), "the file is still read-only after the sync");
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      declare
         Attrib : constant GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Locate_Exec_On_Path ("attrib.exe");
         Done   : Boolean;
      begin
         GNAT.OS_Lib.Spawn (Attrib.all, GNAT.OS_Lib.Argument_String_To_List ("-R " & Path).all, Done);
         Assert (Done, "it can be made writable again");
      end;
   else
      Assert (Hostkit.Metadata.Set_Permissions (Path, 8#644#), "it can be made writable again");
   end if;
   Ada.Directories.Delete_File (Path);
end Test_Read_Only_File_Syncs_Promptly;
