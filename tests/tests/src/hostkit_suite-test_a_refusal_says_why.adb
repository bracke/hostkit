separate (Hostkit_Suite)
procedure Test_A_Refusal_Says_Why
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   E_Inval : constant := 22;
   --  EINVAL is 22 on Linux, macOS and in the Windows runtime alike.
   Plain   : constant String := Ada.Directories.Compose (Scratch, "hk-refusal-plain");
   Target  : Unbounded_String;
begin
   if Ada.Directories.Exists (Plain) then
      Ada.Directories.Delete_File (Plain);
   end if;
   Write_File (Plain, "plain");

   --  readlink of what is no link is EINVAL; on Windows, where a link is
   --  a reparse point, the same.
   GNAT.OS_Lib.Set_Errno (0);
   Assert (not Hostkit.Fs.Read_Link_Target (Plain, Target), "an ordinary file has no link target");
   Assert (Target = Null_Unbounded_String, "no target is reported for an ordinary file");
   Assert (GNAT.OS_Lib.Errno = E_Inval, "reading the target of what is no link says EINVAL, not nothing");

   if Hostkit.Host.Current = Hostkit.Host.Windows then
      declare
         Held     : constant Hostkit.Metadata.Entry_Identity := Hostkit.Metadata.Entry_Identity_Of (Plain);
         Other    : Hostkit.Metadata.Entry_Identity := Held;
         Updated  : Hostkit.Metadata.Metadata_Update_Result;
         Full     : constant String := Ada.Directories.Full_Name (Plain);
         Long     : constant String := "\\?\" & Full;
         Device   : Long_Long_Integer;
         Known    : Boolean;
         Long_Dev : Long_Long_Integer;
         Long_Known : Boolean;
      begin
         --  An update bound to another entry than the path holds now is
         --  refused, and says so through errno.
         Assert (Held.Available, "an ordinary file on the scratch volume has an identity");
         Other.File_Number := Interfaces."xor" (Other.File_Number, 1);
         GNAT.OS_Lib.Set_Errno (0);
         Updated :=
           Hostkit.Metadata.Update_Entry_Metadata
             (Path           => Plain,
              Expected       => Other,
              Check_Expected => True,
              Kind           => Hostkit.Metadata.Update_Permissions,
              Value          => 8#644#,
              Group          => 0,
              Max_Previous   => Hostkit.Metadata.Identity_Field'Last);
         Assert (not Updated.Success, "an update bound to another entry is refused");
         Assert (GNAT.OS_Lib.Errno /= 0, "a refused update says why through errno");

         --  The volume is found from the long form too: its root, not a
         --  guess from a drive letter.
         Assert
           (Hostkit.Metadata.Volume_Capacity_Of (Long).Name_Max_Known,
            "the name limit is read for a path in the \\?\ form");
         Assert
           (Hostkit.Metadata.Volume_Capacity_Of (Scratch).Name_Max_Known,
            "the name limit is read for a folder inside a volume");

         --  The device is the volume's own number, whichever form names it.
         Device := Hostkit.Metadata.Device_Id (Plain, Known);
         Long_Dev := Hostkit.Metadata.Device_Id (Long, Long_Known);
         Assert (Known and then Long_Known, "a file's device is known in either form");
         Assert (Device = Long_Dev, "the long form names the same volume");
         Assert (Device >= 0, "a device id is never negative");
      end;
   end if;

   Ada.Directories.Delete_File (Plain);
end Test_A_Refusal_Says_Why;
