separate (Hostkit.Fs)
function Own_Executable_Directory return String is
   Own : constant String := Own_Executable;
begin
   return (if Own = "" then "" else Directory_Part (Own));
end Own_Executable_Directory;
