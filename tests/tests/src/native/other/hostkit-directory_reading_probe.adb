with System;
with Hostkit.Posix;

package body Hostkit.Directory_Reading_Probe is

   function Available return Boolean is (True);

   function Read (How : Ending; Visited : out Natural) return Boolean is
      Entry_Bytes : aliased Character := 'x';
      Calls       : Natural := 0;

      --  The scripted readdir: one entry, then the end How names.
      function Readdir (Directory : System.Address) return System.Address is
         pragma Unreferenced (Directory);
      begin
         Calls := Calls + 1;
         if Calls = 1 then
            return Entry_Bytes'Address;
         elsif How = Failed_Midway then
            Hostkit.Posix.Set_Errno (5);
         end if;
         return System.Null_Address;
      end Readdir;

      --  Count the entry; leave errno set or stop the read as How asks.
      function Visit (Item : System.Address) return Boolean is
         pragma Unreferenced (Item);
      begin
         Visited := Visited + 1;
         if How = Stale_Errno_End then
            Hostkit.Posix.Set_Errno (5);
         end if;
         return How /= Visit_Stops;
      end Visit;

      --  The read under test.
      function Read_All is new Hostkit.Posix.Read_Directory (Readdir, Visit);
   begin
      Visited := 0;
      return Read_All (System.Null_Address);
   end Read;

end Hostkit.Directory_Reading_Probe;
