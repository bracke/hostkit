with Ada.Strings.Unbounded;

with GNAT.OS_Lib;

with Interfaces.C;

with System;

package body Hostkit.Native is
   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;
   use type GNAT.OS_Lib.Process_Id;
   use type GNAT.OS_Lib.String_Access;

   WNOHANG : constant Interfaces.C.int := 1;

   --  waitpid (-1, NULL, WNOHANG): any child, and do not block. It returns the pid of
   --  a child it collected, 0 when children exist but none have finished, and -1 when
   --  there are none at all -- so this drains what is ready and stops.
   function Waitpid
     (Pid     : Interfaces.C.int;
      Status  : System.Address;
      Options : Interfaces.C.int)
      return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "waitpid";

   procedure Reap_Finished_Children is
      Collected : Interfaces.C.int;
   begin
      loop
         Collected := Waitpid (-1, System.Null_Address, WNOHANG);
         exit when Collected <= 0;
      end loop;
   exception
      when others =>
         null;
   end Reap_Finished_Children;

   --  sh takes "-c" and the command as ordinary vector elements, and nothing rewrites
   --  them on the way. There is nothing for a raw command line to fix.
   function Supports_Raw_Command_Line return Boolean is
   begin
      return False;
   end Supports_Raw_Command_Line;

   function Run_Command_Line
     (Command     : String;
      Wait        : Boolean;
      Exit_Status : out Integer)
      return Boolean
   is
      pragma Unreferenced (Command, Wait);
   begin
      Exit_Status := -1;
      return False;
   end Run_Command_Line;

   function Open_Native (Path : String) return Boolean is
      --  xdg-open is the freedesktop way to hand a path to whatever handles it.
      Opener   : constant String := "xdg-open";
      Located  : GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Locate_Exec_On_Path (Opener);
      Argument : aliased String := Path;
      Args     : constant GNAT.OS_Lib.Argument_List :=
        [1 => Argument'Unchecked_Access];
      Started  : GNAT.OS_Lib.Process_Id;
   begin
      if Located = null then
         return False;
      end if;

      Started := GNAT.OS_Lib.Non_Blocking_Spawn (Located.all, Args);
      GNAT.OS_Lib.Free (Located);

      if Started = GNAT.OS_Lib.Invalid_Pid then
         return False;
      end if;

      Reap_Finished_Children;
      return True;
   exception
      when others =>
         if Located /= null then
            GNAT.OS_Lib.Free (Located);
         end if;
         return False;
   end Open_Native;

end Hostkit.Native;
