separate (Hostkit.Fs)
function Directory_Part (Path : String) return String is
begin
   for Index in reverse Path'Range loop
      if Path (Index) = '/' then
         return (if Index = Path'First then "/" else Path (Path'First .. Index - 1));
      end if;
   end loop;
   return "";
end Directory_Part;
