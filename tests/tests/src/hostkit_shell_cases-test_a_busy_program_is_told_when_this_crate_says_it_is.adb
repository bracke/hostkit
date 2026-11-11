separate (Hostkit_Shell_Cases)
procedure Test_A_Busy_Program_Is_Told_When_This_Crate_Says_It_Is
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Terminal : Hostkit.Pty.Pair;
   Options  : Hostkit.Spawn.Options;
   Child    : Hostkit.Spawn.Process_Handle;
   Result   : Hostkit.Spawn.Status;

   Asked : Hostkit.String_Vectors.Vector;

   Ctrl_C : constant Ada.Streams.Stream_Element_Array :=
     [1 => Ada.Streams.Stream_Element (3)];
   Last   : Ada.Streams.Stream_Element_Offset;

   Where : constant String :=
     Ada.Directories.Compose
       (Ada.Directories.Containing_Directory (Ada.Command_Line.Command_Name),
        "busy-watcher.txt");

   Said : Ada.Strings.Unbounded.Unbounded_String;

   function Wrote (Text : String) return Boolean
   is (Ada.Strings.Fixed.Index
         (Ada.Strings.Unbounded.To_String (Said), Text) > 0);
begin
   if not Hostkit.Pty.Is_Supported
     or else not Hostkit.Signals.Can_Record
                   (Hostkit.Signals.Signal_Interrupt)
   then
      --  A host that cannot record an interrupt at all has nothing to be
      --  told with, and the question below is not one it can be asked.
      Skip
        ("Test_A_Busy_Program_Is_Told_When_This_Crate_Says_It_Is",
         "this host cannot record an interrupt from a terminal");
      return;
   end if;

   if Ada.Directories.Exists (Where) then
      Ada.Directories.Delete_File (Where);
   end if;

   Asked.Append (Ada.Strings.Unbounded.To_Unbounded_String (Where));
   Asked.Append (Ada.Strings.Unbounded.To_Unbounded_String ("3"));

   Assert (Hostkit.Pty.Open (Terminal), "could not open a terminal");
   Assert (Hostkit.Pty.Attach (Terminal, Options),
           "could not arrange to start the watcher on a terminal");

   Assert (Hostkit.Spawn.Start
             (Companion ("busy_watcher"), Asked, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "the busy watcher would not start on a terminal");

   Hostkit.Pty.Close_Device (Terminal);

   --  A moment to take the terminal and reach its loop. Waiting for a line
   --  would be better, but a program writing a line is a program that is
   --  not yet busy, and being busy is the whole measurement.
   delay 0.5;

   Assert (D.Write (Terminal.To_Child, Ctrl_C, Last) = D.Transfer_Ok,
           "could not type into the terminal");

   for Attempt in 1 .. 200 loop
      exit when Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result)
                and then Result.State /= Hostkit.Spawn.Wait_Running;

      --  Drained while it runs: a terminal nobody reads fills up, and a
      --  program writing into a full one waits instead of finishing.
      --
      --  Only when there is something there. This watcher writes nothing to
      --  its terminal -- it writes to a file, which is the whole point of
      --  the file -- and a read of a pipe nothing has been written to
      --  blocks until something is. That hung the suite on the one host
      --  this case exists for.
      if D.Wait_Readable (Terminal.From_Child, 0) then
         declare
            Buffer : Ada.Streams.Stream_Element_Array (1 .. 512);
            Taken  : Ada.Streams.Stream_Element_Offset;
            Ignored : constant D.Transfer_Outcome :=
              D.Read (Terminal.From_Child, Buffer, Taken);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      end if;

      delay 0.05;
   end loop;

   Hostkit.Pty.Close (Terminal);

   if Ada.Directories.Exists (Where) then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Where);

         while not Ada.Text_IO.End_Of_File (File) loop
            Ada.Strings.Unbounded.Append
              (Said, Ada.Text_IO.Get_Line (File) & " ");
         end loop;

         Ada.Text_IO.Close (File);
      end;
   end if;

   Assert (Wrote ("told="),
           "the busy watcher never ran: ["
           & Ada.Strings.Unbounded.To_String (Said) & "]");

   --  Both directions. A host that says True and does not tell is a broken
   --  promise; a host that says False and does tell is a caller building an
   --  elaborate arrangement it did not need.
   if Hostkit.Terminal_Control.Interrupt_Reaches_A_Busy_Program then
      Assert (Wrote ("told=TRUE"),
              "this crate says a busy program is told and it was not: ["
              & Ada.Strings.Unbounded.To_String (Said) & "]");
   else
      Assert (Wrote ("told=FALSE") and then Wrote ("after=FALSE"),
              "this crate says a busy program is not told and it was: ["
              & Ada.Strings.Unbounded.To_String (Said) & "]");
   end if;
end Test_A_Busy_Program_Is_Told_When_This_Crate_Says_It_Is;
