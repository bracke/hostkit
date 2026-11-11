package body Hostkit.Errors is

   --  An unknown host's numbers are unknown.
   function Code_Of (Item : Cause) return Integer is
      pragma Unreferenced (Item);
   begin
      return 0;
   end Code_Of;

   --  An unknown host has no last error to read.
   procedure Set_Errno_From_Last_Error is null;

end Hostkit.Errors;
