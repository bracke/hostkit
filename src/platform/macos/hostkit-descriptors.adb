with Interfaces.C.Strings;
with Interfaces.C;

with System;

package body Hostkit.Descriptors is

   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.Strings.chars_ptr;
   use type Ada.Streams.Stream_Element_Offset;

   subtype C_Int is Interfaces.C.int;
   subtype C_Long is Interfaces.C.long;

   --  macOS, sys/fcntl.h. Written in hexadecimal as that header does. These
   --  are NOT the Linux values and the difference is not cosmetic: Linux
   --  O_CREAT is 0o100 and O_TRUNC 0o1000, which on macOS mean O_ASYNC and
   --  O_CREAT. A body that copied Linux's numbers here would open capture
   --  files without ever truncating them, and stale output would survive every
   --  re-run -- which is exactly the confident wrong answer this crate exists
   --  to prevent, and exactly the bug that was in this directory before.
   O_Rdonly   : constant C_Int := 16#0000#;
   O_Wronly   : constant C_Int := 16#0001#;
   O_Rdwr     : constant C_Int := 16#0002#;
   O_Nonblock : constant C_Int := 16#0004#;
   O_Append   : constant C_Int := 16#0008#;
   O_Creat    : constant C_Int := 16#0200#;
   O_Trunc    : constant C_Int := 16#0400#;
   O_Excl     : constant C_Int := 16#0800#;

   --  fcntl commands and the close-on-exec flag. These do agree with Linux.
   F_Getfd : constant C_Int := 1;
   F_Setfd : constant C_Int := 2;
   F_Getfl : constant C_Int := 3;
   F_Setfl : constant C_Int := 4;

   FD_Cloexec : constant C_Int := 1;

   --  errno values this package distinguishes, from sys/errno.h. EAGAIN is 35
   --  here and 11 on Linux; reading the Linux value would misreport a
   --  would-block as an error and lose the last buffer of a pipeline.
   E_Intr       : constant C_Int := 4;
   E_Again      : constant C_Int := 35;
   E_Pipe       : constant C_Int := 32;
   E_Wouldblock : constant C_Int := E_Again;  --  same value on macOS

   --  Ada defines no bitwise operators on signed integer types, and every flag
   --  word here is a C int. These convert for the bit work and back. Composing
   --  open flags uses "+" instead, as the rest of this crate does: the flags
   --  are disjoint bits, so a sum and a bitwise or are the same value and the
   --  sum reads as the header does.
   function Bit_Set (Value, Mask : C_Int) return C_Int
   is (C_Int (Interfaces.C.unsigned (Value) or Interfaces.C.unsigned (Mask)));

   function Bit_Clear (Value, Mask : C_Int) return C_Int
   is (C_Int (Interfaces.C.unsigned (Value) and not Interfaces.C.unsigned (Mask)));

   function C_Pipe (Fds : System.Address) return C_Int
     with Import => True, Convention => C, External_Name => "pipe";
   function C_Close (Fd : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "close";
   function C_Dup (Fd : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "dup";
   function C_Fcntl (Fd : C_Int; Command : C_Int; Argument : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "fcntl";
   function C_Open
     (Path  : Interfaces.C.Strings.chars_ptr;
      Flags : C_Int;
      Mode  : Interfaces.C.unsigned) return C_Int
     with Import => True, Convention => C, External_Name => "open";
   function C_Read (Fd : C_Int; Buffer : System.Address; Count : C_Long) return C_Long
     with Import => True, Convention => C, External_Name => "read";
   function C_Write (Fd : C_Int; Buffer : System.Address; Count : C_Long) return C_Long
     with Import => True, Convention => C, External_Name => "write";
   function C_Isatty (Fd : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "isatty";
   function C_Ttyname (Fd : C_Int) return Interfaces.C.Strings.chars_ptr
     with Import => True, Convention => C, External_Name => "ttyname";
   function C_Dup2 (Old_Fd, New_Fd : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "dup2";

   --  errno is a macro over a per-thread location; __error is the function it
   --  expands to on macOS, where glibc's __errno_location does not exist.
   --  Reading a global named "errno" would read the wrong thread's value.
   function Errno_Location return System.Address
     with Import => True, Convention => C, External_Name => "__error";

   function Errno return C_Int;
   --  The current thread's errno.

   function To_Descriptor (Fd : C_Int) return Descriptor
   is (if Fd < 0 then Invalid else Descriptor (Fd));

   function To_Fd (Item : Descriptor) return C_Int
   is (C_Int (Item));

   -----------
   -- Errno --
   -----------

   function Errno return C_Int is
      Value : C_Int
        with Import => True, Address => Errno_Location;
   begin
      return Value;
   end Errno;

   --------------
   -- Is_Valid --
   --------------

   function Is_Valid (Item : Descriptor) return Boolean is
   begin
      return Item /= Invalid;
   end Is_Valid;

   -----------------
   -- Create_Pipe --
   -----------------

   function Create_Pipe (Ends : out Pipe_Ends) return Boolean is
      Fds : aliased array (0 .. 1) of aliased C_Int := [others => -1];
   begin
      Ends := (Read_End => Invalid, Write_End => Invalid);

      if C_Pipe (Fds'Address) /= 0 then
         return False;
      end if;

      Ends.Read_End  := To_Descriptor (Fds (0));
      Ends.Write_End := To_Descriptor (Fds (1));

      --  Non-inheritable until someone says otherwise. pipe(2) hands back
      --  descriptors without FD_CLOEXEC, so the default is the dangerous one:
      --  a read end that leaks into later children keeps the pipe's write count
      --  above zero and the reader never sees end-of-file. Closing that door
      --  here means a consumer has to open it deliberately, per child.
      if not Set_Inheritable (Ends.Read_End, False)
        or else not Set_Inheritable (Ends.Write_End, False)
      then
         Close (Ends.Read_End);
         Close (Ends.Write_End);
         return False;
      end if;

      return True;
   end Create_Pipe;

   -----------
   -- Close --
   -----------

   procedure Close (Item : in out Descriptor) is
      Ignored : C_Int;
   begin
      if Item = Invalid then
         return;
      end if;

      Ignored := C_Close (To_Fd (Item));

      --  Invalid whether or not close reported success. A descriptor that
      --  close(2) rejected is gone regardless -- EBADF means it was never
      --  ours, and EINTR does not leave it open on Linux -- and keeping the
      --  number would invite the double close this exists to prevent.
      Item := Invalid;
   end Close;

   ---------------
   -- Duplicate --
   ---------------

   function Duplicate (Item : Descriptor) return Descriptor is
      Copy : C_Int;
   begin
      if Item = Invalid then
         return Invalid;
      end if;

      Copy := C_Dup (To_Fd (Item));

      if Copy < 0 then
         return Invalid;
      end if;

      --  dup(2) clears FD_CLOEXEC on the copy whatever the original had, so
      --  the copy is inheritable unless we say otherwise. Saying otherwise
      --  keeps the rule of this package uniform: inheritance is opt-in.
      declare
         Result : constant Descriptor := To_Descriptor (Copy);
      begin
         if not Set_Inheritable (Result, False) then
            declare
               Doomed : Descriptor := Result;
            begin
               Close (Doomed);
            end;
            return Invalid;
         end if;

         return Result;
      end;
   end Duplicate;

   ---------------------
   -- Set_Inheritable --
   ---------------------

   function Set_Inheritable (Item : Descriptor; Inheritable : Boolean) return Boolean is
      Flags : C_Int;
   begin
      if Item = Invalid then
         return False;
      end if;

      Flags := C_Fcntl (To_Fd (Item), F_Getfd, 0);

      if Flags < 0 then
         return False;
      end if;

      --  POSIX states the inverse of the question: FD_CLOEXEC set means the
      --  descriptor is closed by exec, that is, not inherited.
      if Inheritable then
         Flags := Bit_Clear (Flags, FD_Cloexec);
      else
         Flags := Bit_Set (Flags, FD_Cloexec);
      end if;

      return C_Fcntl (To_Fd (Item), F_Setfd, Flags) = 0;
   end Set_Inheritable;

   ----------------------
   -- Set_Non_Blocking --
   ----------------------

   function Set_Non_Blocking (Item : Descriptor; Non_Blocking : Boolean) return Boolean is
      Flags : C_Int;
   begin
      if Item = Invalid then
         return False;
      end if;

      Flags := C_Fcntl (To_Fd (Item), F_Getfl, 0);

      if Flags < 0 then
         return False;
      end if;

      if Non_Blocking then
         Flags := Bit_Set (Flags, O_Nonblock);
      else
         Flags := Bit_Clear (Flags, O_Nonblock);
      end if;

      return C_Fcntl (To_Fd (Item), F_Setfl, Flags) = 0;
   end Set_Non_Blocking;

   --------------------
   -- Wait_Readable --
   --------------------

   function Wait_Readable
     (Item : Descriptor; Timeout_Ms : Integer) return Boolean
   is
      type Poll_Entry is record
         Fd      : C_Int := -1;
         Events  : Interfaces.C.short := 0;
         Revents : Interfaces.C.short := 0;
      end record
        with Convention => C;

      Poll_In : constant Interfaces.C.short := 1;

      function C_Poll
        (Entries : access Poll_Entry;
         Count   : Interfaces.C.unsigned_long;
         Timeout : C_Int) return C_Int
        with Import => True, Convention => C, External_Name => "poll";

      Watched : aliased Poll_Entry;
      Answer  : C_Int;
   begin
      if Item = Invalid then
         return False;
      end if;

      Watched.Fd := C_Int (Native_Value (Item));
      Watched.Events := Poll_In;

      loop
         Answer := C_Poll (Watched'Access, 1, C_Int (Timeout_Ms));

         --  Interrupted before anything happened. Asked again rather than
         --  reported as a timeout: a signal arriving is not an answer to the
         --  question, and a caller told "not ready" would spin.
         exit when Answer >= 0 or else Errno /= E_Intr;
      end loop;

      --  Any answer at all -- readable, hung up, or an error on the
      --  descriptor -- means a read returns rather than waits, which is the
      --  question that was asked.
      return Answer > 0;
   end Wait_Readable;

   ----------
   -- Read --
   ----------

   function Read
     (Item : Descriptor;
      Into : out Ada.Streams.Stream_Element_Array;
      Last : out Ada.Streams.Stream_Element_Offset) return Transfer_Outcome
   is
      Count : C_Long;
   begin
      Last := Into'First - 1;

      if Item = Invalid then
         return Transfer_Error;
      end if;

      if Into'Length = 0 then
         return Transfer_Ok;
      end if;

      Count := C_Read (To_Fd (Item), Into'Address, C_Long (Into'Length));

      if Count > 0 then
         Last := Into'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
         return Transfer_Ok;
      end if;

      --  Zero from read(2) on a pipe means every write end is closed. It is
      --  not an error and it is not "nothing right now"; a reader that treats
      --  it as either spins forever on a finished child.
      if Count = 0 then
         return Transfer_End_Of_File;
      end if;

      declare
         Code : constant C_Int := Errno;
      begin
         if Code = E_Intr then
            return Transfer_Interrupted;
         elsif Code = E_Again or else Code = E_Wouldblock then
            return Transfer_Would_Block;
         else
            return Transfer_Error;
         end if;
      end;
   end Read;

   -----------
   -- Write --
   -----------

   function Write
     (Item : Descriptor;
      From : Ada.Streams.Stream_Element_Array;
      Last : out Ada.Streams.Stream_Element_Offset) return Transfer_Outcome
   is
      Count : C_Long;
   begin
      Last := From'First - 1;

      if Item = Invalid then
         return Transfer_Error;
      end if;

      if From'Length = 0 then
         return Transfer_Ok;
      end if;

      Count := C_Write (To_Fd (Item), From'Address, C_Long (From'Length));

      if Count >= 0 then
         Last := From'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
         return Transfer_Ok;
      end if;

      declare
         Code : constant C_Int := Errno;
      begin
         if Code = E_Intr then
            return Transfer_Interrupted;
         elsif Code = E_Again or else Code = E_Wouldblock then
            return Transfer_Would_Block;
         elsif Code = E_Pipe then
            --  The reader is gone. Reported rather than fatal, but only
            --  because the shell blocks SIGPIPE -- without that this process
            --  dies here and never reaches this line. See Hostkit.Signals.
            return Transfer_Broken_Pipe;
         else
            return Transfer_Error;
         end if;
      end;
   end Write;

   --------------------
   -- Standard_Input --
   --------------------

   function Standard_Input return Descriptor is
   begin
      return Descriptor (0);
   end Standard_Input;

   ---------------------
   -- Standard_Output --
   ---------------------

   function Standard_Output return Descriptor is
   begin
      return Descriptor (1);
   end Standard_Output;

   --------------------
   -- Standard_Error --
   --------------------

   function Standard_Error return Descriptor is
   begin
      return Descriptor (2);
   end Standard_Error;

   ---------------
   -- Open_File --
   ---------------

   function Open_File
     (Path : String;
      Mode : Open_Mode;
      Item : out Descriptor) return Boolean
   is
      Flags  : C_Int;
      Path_C : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Opened : C_Int;
   begin
      Item := Invalid;

      case Mode is
         when Open_Read            => Flags := O_Rdonly;
         when Open_Write_Truncate  =>
               Flags := C_Int
                 (Interfaces.C.unsigned (O_Wronly)
                  or Interfaces.C.unsigned (O_Creat)
                  or Interfaces.C.unsigned (O_Trunc));
         when Open_Write_Append    =>
               Flags := C_Int
                 (Interfaces.C.unsigned (O_Wronly)
                  or Interfaces.C.unsigned (O_Creat)
                  or Interfaces.C.unsigned (O_Append));
         when Open_Write_Exclusive =>
               Flags := C_Int
                 (Interfaces.C.unsigned (O_Wronly)
                  or Interfaces.C.unsigned (O_Creat)
                  or Interfaces.C.unsigned (O_Excl));
         when Open_Read_Write      => Flags := O_Rdwr;
      end case;

      Opened := C_Open (Path_C, Flags, 8#644#);
      Interfaces.C.Strings.Free (Path_C);

      if Opened < 0 then
         return False;
      end if;

      Item := To_Descriptor (Opened);

      if not Set_Inheritable (Item, False) then
         Close (Item);
         return False;
      end if;

      return True;
   end Open_File;

   -----------------
   -- Is_Terminal --
   -----------------

   function Is_Terminal (Item : Descriptor) return Boolean is
   begin
      if Item = Invalid then
         return False;
      end if;

      return C_Isatty (To_Fd (Item)) = 1;
   end Is_Terminal;

   function Terminal_Name (Item : Descriptor) return String is
      Name : Interfaces.C.Strings.chars_ptr;
   begin
      if not Is_Terminal (Item) then
         return "";
      end if;

      Name := C_Ttyname (To_Fd (Item));
      if Name = Interfaces.C.Strings.Null_Ptr then
         return "/dev/tty";
      else
         return Interfaces.C.Strings.Value (Name);
      end if;
   exception
      when others =>
         return "";
   end Terminal_Name;

   ------------
   -- Assign --
   ------------

   function Assign (Item : Descriptor; To : Standard_Stream) return Boolean is
      Target : constant C_Int :=
        (case To is
            when Stream_Input  => 0,
            when Stream_Output => 1,
            when Stream_Error  => 2);
      Flags : C_Int;
   begin
      if Item = Invalid then
         return False;
      end if;

      if To_Fd (Item) = Target then
         --  Already in place. dup2 of a descriptor onto itself is defined to do
         --  nothing at all -- including not clearing FD_CLOEXEC -- so the flag
         --  has to come off by hand, or the stream this call was meant to
         --  install is closed by the exec that follows.
         Flags := C_Fcntl (Target, F_Getfd, 0);

         if Flags < 0 then
            return False;
         end if;

         return C_Fcntl (Target, F_Setfd, Bit_Clear (Flags, FD_Cloexec)) = 0;
      end if;

      --  dup2 clears FD_CLOEXEC on the new descriptor, which is what makes the
      --  assignment survive the exec.
      return C_Dup2 (To_Fd (Item), Target) = Target;
   end Assign;

   ------------------
   -- Native_Value --
   ------------------

   function Native_Value (Item : Descriptor) return Long_Long_Integer is
   begin
      return Long_Long_Integer (Item);
   end Native_Value;

   -----------------------
   -- From_Native_Value --
   -----------------------

   function From_Native_Value (Value : Long_Long_Integer) return Descriptor is
   begin
      if Value < 0 then
         return Invalid;
      end if;

      return Descriptor (Value);
   end From_Native_Value;

end Hostkit.Descriptors;
