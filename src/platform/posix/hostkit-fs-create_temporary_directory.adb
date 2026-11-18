separate (Hostkit.Fs)
function Create_Temporary_Directory (Prefix : String) return String is
   Base : constant String := Temp_Directory;

   function Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Left));

   function Time_Image return String is
      Raw : constant String := Duration'Image (Ada.Calendar.Seconds (Ada.Calendar.Clock));
      Result : String := Raw;
   begin
      for C of Result loop
         if C = ' ' or else C = '.' then
            C := '-';
         end if;
      end loop;
      return Result;
   end Time_Image;

   function Safe_Prefix return String is
      Result : String := Prefix;
   begin
      for C of Result loop
         if not (C in 'A' .. 'Z' or else C in 'a' .. 'z'
                 or else C in '0' .. '9' or else C = '-' or else C = '_')
         then
            C := '-';
         end if;
      end loop;
      return (if Result = "" then "hostkit-temp" else Result);
   end Safe_Prefix;
begin
   for Attempt in 1 .. 1000 loop
      declare
         Candidate : constant String :=
           Ada.Directories.Compose
             (Containing_Directory => Base,
              Name => Safe_Prefix & "-" & Time_Image & "-" & Image (Attempt));
      begin
         Ada.Directories.Create_Directory (Candidate);
         return Candidate;
      exception
         when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
            null;
      end;
   end loop;
   return "";
end Create_Temporary_Directory;
