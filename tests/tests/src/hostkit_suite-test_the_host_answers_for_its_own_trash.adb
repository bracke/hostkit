separate (Hostkit_Suite)
procedure Test_The_Host_Answers_For_Its_Own_Trash
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Facility : constant Hostkit.Trash.Facility := Hostkit.Trash.Current;
begin
   --  Which hosts have a trash of their own is a fact about the hosts, not a
   --  configuration: Windows and macOS do, Linux has a specification for the
   --  caller to implement instead.
   case Hostkit.Host.Current is
      when Hostkit.Host.Windows | Hostkit.Host.MacOS =>
         Assert (Facility.Available, "this host has a trash of its own");
         Assert (Facility.Api_Name /= Null_Unbounded_String, "and names the call behind it");
         Assert
           (Facility.Uses_Recycle_Bin = (Hostkit.Host.Current = Hostkit.Host.Windows),
            "only Windows calls its trash the Recycle Bin");

         --  The call itself, on macOS: the runner has a Finder trash, and
         --  NSFileManager reached through objc_msgSend goes wrong at run
         --  time, not at the compile, if a prototype is off.
         if Hostkit.Host.Current = Hostkit.Host.MacOS then
            declare
               Path : constant String := Ada.Directories.Compose (Scratch, "hk-trash-taken");
            begin
               Write_File (Path, "to the trash");
               Assert (Hostkit.Trash.Move_To_Trash (Path), "macOS takes a file into its trash");
               Assert (not Ada.Directories.Exists (Path), "and it is gone from where it was");
               Assert
                 (not Hostkit.Trash.Move_To_Trash (Path),
                  "a path that is no longer there is refused, not reported as trashed");
            end;
         end if;

         --  Where the Recycle Bin is not, the shell destroys what it is
         --  asked to recycle; Can_Hold must say so first. The runner's
         --  own drive has a bin; an administrative share of the same
         --  drive is a network path, which has none.
         if Hostkit.Host.Current = Hostkit.Host.Windows then
            declare
               Path : constant String := Ada.Directories.Compose (Scratch, "hk-trash-held");
            begin
               Write_File (Path, "kept");
               Assert (Hostkit.Trash.Can_Hold (Path), "a file on the local drive can go to the Recycle Bin");
               Assert
                 (not Hostkit.Trash.Can_Hold ("\\localhost\C$\Windows\win.ini"),
                  "a file on a network share cannot");
               Ada.Directories.Delete_File (Path);
            end;
         else
            Assert (Hostkit.Trash.Can_Hold (Scratch), "macOS keeps whatever its trash takes");
         end if;

      when Hostkit.Host.Linux | Hostkit.Host.Unsupported =>
         Assert (not Facility.Available, "this host has no trash of its own to call");
         Assert (Facility.Api_Name = Null_Unbounded_String, "and names no call");

         --  The refusal must leave the file alone. A caller falling back to a
         --  delete here would turn a recoverable action into a permanent one,
         --  so the one thing this must never do is succeed by removing it.
         declare
            Path : constant String := Ada.Directories.Compose (Scratch, "hk-trash-untouched");
         begin
            Write_File (Path, "still here");
            Assert (not Hostkit.Trash.Move_To_Trash (Path), "a host with no trash declines");
            Assert (Ada.Directories.Exists (Path), "and leaves the file exactly where it was");
            Assert (not Hostkit.Trash.Can_Hold (Path), "and holds nothing");
            Ada.Directories.Delete_File (Path);
         end;
   end case;
end Test_The_Host_Answers_For_Its_Own_Trash;
