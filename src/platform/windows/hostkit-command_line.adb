with Ada.Command_Line;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.UTF_Encoding.Wide_Strings;

with Interfaces.C;

with System;

package body Hostkit.Command_Line is

   use type System.Address;
   use type Interfaces.C.int;

   --  Windows starts a process with one command-line *string*; the vector a
   --  program sees is whatever its C runtime parsed out of it, and some
   --  runtimes expand a wildcard against the current directory on the way.
   --  GetCommandLineW returns that string untouched, and CommandLineToArgvW
   --  splits it by the documented quoting rules and expands nothing.
   function Get_Command_Line return System.Address
     with Import, Convention => Stdcall, External_Name => "GetCommandLineW";

   function Command_Line_To_Argv
     (Command_Line : System.Address;
      Count        : access Interfaces.C.int)
      return System.Address
     with Import, Convention => Stdcall,
          External_Name => "CommandLineToArgvW";

   --  CommandLineToArgvW returns one LocalAlloc block holding the vector and
   --  the strings; the caller frees it with LocalFree.
   function Local_Free (Memory : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "LocalFree";

   package String_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, String);

   Arguments : String_Vectors.Vector;
   Asked     : Boolean := False;
   Answered  : Boolean := False;

   --  The Index'th pointer of the vector CommandLineToArgvW returned.
   function Element_At (Base : System.Address; Index : Natural)
     return System.Address;

   --  A NUL-terminated UTF-16 string at Location, as UTF-8.
   function Decoded (Location : System.Address) return String;

   procedure Ask;

   function Element_At (Base : System.Address; Index : Natural)
     return System.Address
   is
      type Address_Array is array (Natural range <>) of System.Address;

      Table : constant Address_Array (0 .. Index)
        with Import, Address => Base;
   begin
      return Table (Index);
   end Element_At;

   function Decoded (Location : System.Address) return String is
      --  Long enough for any command line Windows will start a process with
      --  (32767 characters is the documented limit); the scan stops at the
      --  NUL either way, so no byte past the string itself is read.
      Limit : constant := 32_768;

      Text : constant Wide_String (1 .. Limit)
        with Import, Address => Location;

      Last : Natural := 0;
   begin
      while Last < Limit
        and then Text (Last + 1) /= Wide_Character'Val (0)
      loop
         Last := Last + 1;
      end loop;

      return Ada.Strings.UTF_Encoding.Wide_Strings.Encode (Text (1 .. Last));
   end Decoded;

   procedure Ask is
      Line   : constant System.Address := Get_Command_Line;
      Count  : aliased Interfaces.C.int := 0;
      Vector : System.Address;
   begin
      Asked := True;

      if Line = System.Null_Address then
         return;
      end if;

      Vector := Command_Line_To_Argv (Line, Count'Access);

      if Vector = System.Null_Address or else Count < 1 then
         return;
      end if;

      --  Element 0 is the program name, which Ada.Command_Line reports
      --  separately; the arguments start at 1.
      for Index in 1 .. Natural (Count) - 1 loop
         Arguments.Append (Decoded (Element_At (Vector, Index)));
      end loop;

      declare
         Unused : constant System.Address := Local_Free (Vector);
      begin
         pragma Unreferenced (Unused);
      end;

      Answered := True;
   exception
      --  A host that will not answer leaves the runtime's own vector as the
      --  only thing there is; a wrong answer would be worse than the
      --  mangling this exists to avoid.
      when others =>
         Answered := False;
   end Ask;

   function Argument_Count return Natural is
   begin
      if not Asked then
         Ask;
      end if;

      if Answered then
         return Natural (Arguments.Length);
      end if;

      return Ada.Command_Line.Argument_Count;
   end Argument_Count;

   function Argument (Index : Positive) return String is
   begin
      if not Asked then
         Ask;
      end if;

      if Answered then
         return Arguments (Index);
      end if;

      return Ada.Command_Line.Argument (Index);
   end Argument;

end Hostkit.Command_Line;
