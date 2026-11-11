separate (Hostkit_Suite)
procedure Test_Terminal_Streams_Are_Answered_Separately
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Answers : array (Hostkit.Host.Stream_Kind) of Boolean;
begin
   for Stream in Hostkit.Host.Stream_Kind loop
      Answers (Stream) := Hostkit.Host.Is_Terminal (Stream);
   end loop;

   --  Asked twice, the same answer: this reads the state of a descriptor
   --  and must not consume or change anything.
   for Stream in Hostkit.Host.Stream_Kind loop
      Assert (Hostkit.Host.Is_Terminal (Stream) = Answers (Stream),
              "asking twice about "
              & Hostkit.Host.Stream_Kind'Image (Stream)
              & " gave two answers");
   end loop;

   --  A host with no way to ask says no rather than guessing yes, because
   --  treating an unknown destination as a terminal is what puts escape
   --  sequences into a log file.
   if Hostkit.Host.Current = Hostkit.Host.Unsupported then
      for Stream in Hostkit.Host.Stream_Kind loop
         Assert (not Answers (Stream),
                 "a host that cannot answer claimed a terminal");
      end loop;
   end if;
end Test_Terminal_Streams_Are_Answered_Separately;
