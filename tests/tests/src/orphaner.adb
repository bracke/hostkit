with Ada.Strings.Unbounded;
with Ada.Command_Line;
with Ada.Directories;

with Hostkit;
with Hostkit.Process;

--  Starts `watched` beside it, without waiting, and ends -- leaving it an
--  orphan, which is what the parent watch is for. Waits for the child's
--  record first, so the child has asked before its parent goes.
procedure Orphaner is
   Dir       : constant String := Ada.Directories.Containing_Directory (Ada.Command_Line.Command_Name);
   Record_At : constant String := Ada.Command_Line.Argument (1);
   Arguments : Hostkit.String_Vectors.Vector;
   Program   : constant String :=
     (if Ada.Directories.Exists (Ada.Directories.Compose (Dir, "watched.exe"))
      then Ada.Directories.Compose (Dir, "watched.exe")
      else Ada.Directories.Compose (Dir, "watched"));
begin
   Arguments.Append (Ada.Strings.Unbounded.To_Unbounded_String (Record_At));
   if Hostkit.Process.Launch (Program, Arguments) then
      for Try in 1 .. 100 loop
         exit when Ada.Directories.Exists (Record_At);
         delay 0.05;
      end loop;
   end if;
end Orphaner;
