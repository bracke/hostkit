separate (Hostkit.Fs)
function Temp_Directory return String is
begin
   if Ada.Environment_Variables.Exists ("TMPDIR")
     and then Ada.Environment_Variables.Value ("TMPDIR") /= ""
   then
      return Ada.Environment_Variables.Value ("TMPDIR");
   end if;
   return "/tmp";
end Temp_Directory;
