separate (Hostkit.Fs)
function Move_No_Replace_Outcome
  (Source : String;
   Target : String)
   return Move_Outcome
is
   C_Source : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Source);
   C_Target : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Target);
   Status   : Interfaces.C.int;
   Error    : Integer;
begin
   Status := Rename_No_Replace (C_Source, C_Target);
   Error := GNAT.OS_Lib.Errno;
   if Status /= 0 and then Lacks_No_Replace_Rename (Error) then
      --  The filesystem lacks the no-replace rename itself.
      declare
         Outcome : constant Move_Outcome := Without_Native_No_Replace (C_Source, C_Target);
      begin
         Interfaces.C.Strings.Free (C_Source);
         Interfaces.C.Strings.Free (C_Target);
         return Outcome;
      end;
   end if;
   Interfaces.C.Strings.Free (C_Source);
   Interfaces.C.Strings.Free (C_Target);
   if Status = 0 then
      return Moved;
   elsif Error = Fallback_Exdev then
      return Move_Cross_Device;
   end if;
   return Move_Refused;
exception
   when others =>
      return Move_Refused;
end Move_No_Replace_Outcome;
