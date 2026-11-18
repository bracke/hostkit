separate (Hostkit.Fs)
function Move_Without_Native_No_Replace (Source : String; Target : String) return Move_Outcome is
   C_Source : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Source);
   C_Target : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Target);
   Outcome  : constant Move_Outcome := Without_Native_No_Replace (C_Source, C_Target);
begin
   Interfaces.C.Strings.Free (C_Source);
   Interfaces.C.Strings.Free (C_Target);
   return Outcome;
end Move_Without_Native_No_Replace;
