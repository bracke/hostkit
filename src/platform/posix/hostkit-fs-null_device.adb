separate (Hostkit.Fs)
function Null_Device return String is
begin
   --  A character device every POSIX host has, in the place every POSIX
   --  host keeps it.
   return "/dev/null";
end Null_Device;
