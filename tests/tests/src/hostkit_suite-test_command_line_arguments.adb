separate (Hostkit_Suite)
procedure Test_Command_Line_Arguments
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
begin
   Assert
     (Hostkit.Command_Line.Argument_Count
        = Ada.Command_Line.Argument_Count,
      "the argument count must be the one the process was started with;"
      & " asked" & Natural'Image (Hostkit.Command_Line.Argument_Count)
      & ", runtime" & Natural'Image (Ada.Command_Line.Argument_Count));

   for Index in 1 .. Ada.Command_Line.Argument_Count loop
      Assert
        (Hostkit.Command_Line.Argument (Index)
           = Ada.Command_Line.Argument (Index),
         "argument" & Natural'Image (Index)
         & " must be the one the process was started with; asked '"
         & Hostkit.Command_Line.Argument (Index) & "', runtime '"
         & Ada.Command_Line.Argument (Index) & "'");
   end loop;
end Test_Command_Line_Arguments;
