separate (Hostkit.Mounts)
function Volume_Places return Volume_Place_List is
   use Ada.Strings.Unbounded;
   Result : Volume_Place_List (1 .. 26);
begin
   for Drive in Character range 'A' .. 'Z' loop
      Result (Character'Pos (Drive) - Character'Pos ('A') + 1) :=
        (To_Unbounded_String (Drive & ":\"), Drive_Root);
   end loop;
   return Result;
end Volume_Places;
