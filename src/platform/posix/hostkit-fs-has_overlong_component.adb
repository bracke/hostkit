separate (Hostkit.Fs)
function Has_Overlong_Component (Path : String) return Boolean is
   Name_Max : constant := 255;
   Run      : Natural := 0;
begin
   for C of Path loop
      if C = '/' then
         Run := 0;
      else
         Run := Run + 1;
         if Run > Name_Max then
            return True;
         end if;
      end if;
   end loop;
   return False;
end Has_Overlong_Component;
