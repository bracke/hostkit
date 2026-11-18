separate (Hostkit.Fs)
function Without_Native_No_Replace (From, To : Interfaces.C.Strings.chars_ptr) return Move_Outcome is
   Error : Integer;
begin
   if Link_Entry (From, To) = 0 then
      if C_Unlink (From) = 0 then
         return Moved;
      end if;
      if C_Unlink (To) /= 0 then
         null;
      end if;
      return Move_Refused;
   end if;
   Error := GNAT.OS_Lib.Errno;
   if Error = Fallback_Exdev then
      return Move_Cross_Device;
   elsif not Link_Unsupported (Error) then
      --  The target is taken, or the move is refused for good.
      return Move_Refused;
   end if;
   if Present (To) then
      return Move_Refused;
   elsif C_Plain_Rename (From, To) = 0 then
      return Moved;
   elsif GNAT.OS_Lib.Errno = Fallback_Exdev then
      return Move_Cross_Device;
   end if;
   return Move_Refused;
end Without_Native_No_Replace;
