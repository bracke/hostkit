with Ada.Unchecked_Conversion;

with Interfaces.C;

with System.Storage_Elements;
with System;

package body Hostkit.Pty is

   use type Interfaces.C.long;
   use type Interfaces.C.unsigned;
   use type System.Address;

   subtype C_DWord is Interfaces.C.unsigned_long;

   --  A COORD is two 16-bit counts in one 32-bit word, and the calls below take
   --  one *by value*.
   --
   --  Passed here as the word rather than as a record of two shorts. A record
   --  is what it is in the Windows headers, and a record is also the thing an
   --  Ada compiler is entitled to pass by reference for a foreign convention:
   --  the call then reads the low and high halves of a pointer as a width and
   --  a height, which is a console of some enormous accidental size that
   --  CreatePseudoConsole is content with and ResizePseudoConsole refuses.
   --  Four bytes in a register is what the ABI actually specifies, and an
   --  unsigned 32-bit value is that with nothing left to interpretation.
   subtype Console_Size is Interfaces.C.unsigned;

   --  Columns in the low half, rows in the high half: X then Y, which is the
   --  order the two fields have in the structure.
   function Sized (Rows, Columns : Natural) return Console_Size
   is (Console_Size (Columns mod 65_536)
       + Console_Size (Rows mod 65_536) * 65_536);

   --  The three pseudo-console calls, resolved at run time rather than linked.
   --
   --  They arrived in Windows 10 1809. Linking them would make this crate fail
   --  to *start* on an older host -- for every consumer, including the ones
   --  that never open a terminal -- and would make it fail to *build* against
   --  an import library that predates them. Asking the module that is already
   --  loaded costs one lookup and turns both of those into Is_Supported saying
   --  False, which is the answer this crate is supposed to give.
   type Create_Console_Call is access function
     (Size    : Console_Size;
      Input   : System.Address;
      Output  : System.Address;
      Flags   : C_DWord;
      Console : access System.Address) return Interfaces.C.long
     with Convention => Stdcall;

   type Resize_Console_Call is access function
     (Console : System.Address; Size : Console_Size) return Interfaces.C.long
     with Convention => Stdcall;

   type Close_Console_Call is access procedure (Console : System.Address)
     with Convention => Stdcall;

   --  A layout that is a contract with the OS rather than a description of our
   --  own record: pinned, so a field silently mis-sized is a compile error
   --  rather than a call that passes the wrong number of columns. The pragma
   --  sits after the calls that take one, because a type's size is not static
   --  until something has frozen it.
   pragma Compile_Time_Error
     (Console_Size'Size /= 4 * 8, "COORD is not four bytes wide");

   function Get_Module_Handle (Name : Interfaces.C.char_array)
                               return System.Address
     with Import => True, Convention => Stdcall,
          External_Name => "GetModuleHandleA";

   function Get_Proc_Address
     (Module : System.Address; Name : Interfaces.C.char_array)
      return System.Address
     with Import => True, Convention => Stdcall,
          External_Name => "GetProcAddress";

   function To_Create is new Ada.Unchecked_Conversion
     (System.Address, Create_Console_Call);
   function To_Resize is new Ada.Unchecked_Conversion
     (System.Address, Resize_Console_Call);
   function To_Close is new Ada.Unchecked_Conversion
     (System.Address, Close_Console_Call);

   --  Looked up once. A lookup per call would ask the same question of the
   --  same module for the life of the process.
   Looked_Up : Boolean := False;
   Create    : Create_Console_Call := null;
   Resize    : Resize_Console_Call := null;
   Dismiss   : Close_Console_Call := null;

   procedure Resolve;

   procedure Resolve is
      Kernel : System.Address;
   begin
      if Looked_Up then
         return;
      end if;

      Looked_Up := True;

      --  GetModuleHandle rather than LoadLibrary: kernel32 is in every process
      --  already, and loading it again would take a reference nothing here
      --  would ever put back.
      Kernel := Get_Module_Handle (Interfaces.C.To_C ("kernel32.dll"));

      if Kernel = System.Null_Address then
         return;
      end if;

      declare
         Made   : constant System.Address :=
           Get_Proc_Address (Kernel, Interfaces.C.To_C ("CreatePseudoConsole"));
         Resizer : constant System.Address :=
           Get_Proc_Address (Kernel, Interfaces.C.To_C ("ResizePseudoConsole"));
         Closed : constant System.Address :=
           Get_Proc_Address (Kernel, Interfaces.C.To_C ("ClosePseudoConsole"));
      begin
         --  All three or none. Two of the three would be a host halfway
         --  through gaining the feature, which is not a thing that happens and
         --  is not a thing to write code for.
         if Made = System.Null_Address
           or else Resizer = System.Null_Address
           or else Closed = System.Null_Address
         then
            return;
         end if;

         Create := To_Create (Made);
         Resize := To_Resize (Resizer);
         Dismiss := To_Close (Closed);
      end;
   end Resolve;

   function To_Handle (Item : Hostkit.Descriptors.Descriptor)
                       return System.Address
   is (System.Storage_Elements.To_Address
         (System.Storage_Elements.Integer_Address
            (Hostkit.Descriptors.Native_Value (Item))));

   function To_Native (Item : System.Address) return Long_Long_Integer
   is (Long_Long_Integer
         (System.Storage_Elements.To_Integer (Item)));

   ---------------------------
   -- Write_Fails_When_Unheld --
   ---------------------------

   --  False, measured: the case beside this writes a byte to a terminal whose
   --  child has exited and gets Transfer_Ok here, as on Linux. The input side
   --  is a pipe the pseudo-console holds, and closing the device side does not
   --  close that pipe -- so the bytes are taken by something nobody will read
   --  from, which is a success a caller must not read as delivery.
   --
   --  macOS is the host that answers the other way. A caller wanting to know
   --  whether the child is still there asks about the child.
   function Write_Fails_When_Unheld return Boolean is (False);

   ------------------
   -- Is_Supported --
   ------------------

   function Is_Supported return Boolean is
   begin
      Resolve;
      return Create /= null;
   end Is_Supported;

   ----------
   -- Open --
   ----------

   --  Two ordinary pipes and a pseudo-console over them.
   --
   --  The console takes the read end of the one the parent writes to and the
   --  write end of the one the parent reads from, and keeps copies of both.
   --  The parent closes its own copies of those two ends immediately: while it
   --  still holds the write end of the output pipe, a read of that pipe never
   --  reports end-of-file, and a harness waits for a child that exited long
   --  ago. It is the same count-of-copies rule that a pipe has anywhere else,
   --  and it is the mistake this host makes easy to make.
   function Open (Item : out Pair) return Boolean is
      Into_Child : Hostkit.Descriptors.Pipe_Ends;
      Out_Of_It  : Hostkit.Descriptors.Pipe_Ends;

      Console : aliased System.Address := System.Null_Address;

      --  Eighty by twenty-four, so that a fresh one is usable rather than a
      --  console of no size at all. Windows will not make one measuring zero,
      --  and a caller that means something else calls Set_Size.
      Initial : constant Console_Size := Sized (Rows => 24, Columns => 80);
   begin
      Item := (others => <>);

      Resolve;

      if Create = null then
         return False;
      end if;

      if not Hostkit.Descriptors.Create_Pipe (Into_Child) then
         return False;
      end if;

      if not Hostkit.Descriptors.Create_Pipe (Out_Of_It) then
         Hostkit.Descriptors.Close (Into_Child.Read_End);
         Hostkit.Descriptors.Close (Into_Child.Write_End);
         return False;
      end if;

      if Create (Initial,
                 To_Handle (Into_Child.Read_End),
                 To_Handle (Out_Of_It.Write_End),
                 0,
                 Console'Access) /= 0
      then
         Hostkit.Descriptors.Close (Into_Child.Read_End);
         Hostkit.Descriptors.Close (Into_Child.Write_End);
         Hostkit.Descriptors.Close (Out_Of_It.Read_End);
         Hostkit.Descriptors.Close (Out_Of_It.Write_End);
         return False;
      end if;

      --  The console has its own copies of these two now.
      Hostkit.Descriptors.Close (Into_Child.Read_End);
      Hostkit.Descriptors.Close (Out_Of_It.Write_End);

      Item :=
        (To_Child   => Into_Child.Write_End,
         From_Child => Out_Of_It.Read_End,
         Device     => Hostkit.Descriptors.Invalid,
         Console    => Hostkit.Spawn.Console_From_Native (To_Native (Console)));

      return True;
   end Open;

   ------------
   -- Attach --
   ------------

   function Attach (Item : Pair; To : in out Hostkit.Spawn.Options)
                    return Boolean is
   begin
      --  The console, and *not* the three streams. A child attached to a
      --  pseudo-console is given its handles by the console host; handing it
      --  inherited ones as well would give it two answers to the question of
      --  what its standard output is, and the one it would use is not the one
      --  this pair can read.
      To.Console := Item.Console;
      To.Input := Hostkit.Descriptors.Invalid;
      To.Output := Hostkit.Descriptors.Invalid;
      To.Error_Output := Hostkit.Descriptors.Invalid;

      return Hostkit.Spawn.Is_Attached (Item.Console);
   end Attach;

   -------------------
   -- Close_Device --
   -------------------

   procedure Close_Device (Item : in out Pair) is
      pragma Unreferenced (Item);
   begin
      --  Nothing to give up: the console host holds the child's side, and this
      --  process never had a copy of it to hold open.
      null;
   end Close_Device;

   -----------------
   -- Device_Name --
   -----------------

   function Device_Name (Item : Pair) return String is
      pragma Unreferenced (Item);
   begin
      --  A pseudo-console has no path. Empty is the refusal; a plausible
      --  "CONOUT$" would be a name for something else entirely -- the console
      --  this process is attached to, not the one it just made.
      return "";
   end Device_Name;

   -----------
   -- Close --
   -----------

   procedure Close (Item : in out Pair) is
      Console : constant System.Address :=
        System.Storage_Elements.To_Address
          (System.Storage_Elements.Integer_Address
             (Hostkit.Spawn.Native_Console (Item.Console)));
   begin
      --  The console first. Closing it is what tells the console host to stop,
      --  and it flushes what the child has written into the output pipe on the
      --  way -- so a caller draining the pipe afterwards still gets the last
      --  of the output rather than losing it to a closed pipe.
      if Hostkit.Spawn.Is_Attached (Item.Console) and then Dismiss /= null then
         Dismiss (Console);
      end if;

      Item.Console := Hostkit.Spawn.No_Console;

      Hostkit.Descriptors.Close (Item.To_Child);
      Hostkit.Descriptors.Close (Item.From_Child);
      Hostkit.Descriptors.Close (Item.Device);
   end Close;

   --------------
   -- Set_Size --
   --------------

   function Set_Size
     (Item : Pair;
      To   : Hostkit.Terminal_Control.Window_Size) return Boolean
   is
      Console : constant System.Address :=
        System.Storage_Elements.To_Address
          (System.Storage_Elements.Integer_Address
             (Hostkit.Spawn.Native_Console (Item.Console)));

      Wanted : constant Console_Size :=
        Sized (Rows => To.Rows, Columns => To.Columns);
   begin
      if not Hostkit.Spawn.Is_Attached (Item.Console) or else Resize = null then
         return False;
      end if;

      --  The console host redraws the program under it, which is what a
      --  window-change signal does on the other hosts. Same act, no signal.
      return Resize (Console, Wanted) = 0;
   end Set_Size;

end Hostkit.Pty;
