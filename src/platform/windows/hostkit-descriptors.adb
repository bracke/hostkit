with Ada.Strings.UTF_Encoding.Wide_Strings;

with Interfaces.C;

with System.Storage_Elements;
with System;

package body Hostkit.Descriptors is

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Ada.Streams.Stream_Element_Offset;
   use type System.Address;
   use type System.Storage_Elements.Integer_Address;

   subtype C_DWord is Interfaces.C.unsigned_long;

   --  A Descriptor here holds a HANDLE, not a C-runtime file descriptor. The
   --  small integer GNAT.OS_Lib calls a descriptor is an index into whichever
   --  C runtime allocated it, and passing that number to CreateProcess does
   --  nothing at all. The kernel object is the handle, and that is what a child
   --  can be given.
   --
   --  INVALID_HANDLE_VALUE is -1, which is also this package's Invalid, so the
   --  two coincide and no translation is needed for the common failure.

   Invalid_Handle : constant System.Address :=
     System.Storage_Elements.To_Address (-1);

   Std_Input_Handle  : constant C_DWord := 16#FFFF_FFF6#;  --  (DWORD) -10
   Std_Output_Handle : constant C_DWord := 16#FFFF_FFF5#;  --  (DWORD) -11
   Std_Error_Handle  : constant C_DWord := 16#FFFF_FFF4#;  --  (DWORD) -12

   Handle_Flag_Inherit : constant C_DWord := 1;

   Generic_Read  : constant C_DWord := 16#8000_0000#;
   Generic_Write : constant C_DWord := 16#4000_0000#;

   File_Share_Read  : constant C_DWord := 1;
   File_Share_Write : constant C_DWord := 2;

   Create_Always     : constant C_DWord := 2;
   Create_New        : constant C_DWord := 1;
   Open_Existing     : constant C_DWord := 3;
   Open_Always       : constant C_DWord := 4;

   File_Attribute_Normal : constant C_DWord := 16#80#;

   --  FILE_APPEND_DATA without FILE_WRITE_DATA. This is how Windows expresses
   --  what O_APPEND means on POSIX: the write goes to the end atomically,
   --  rather than the caller seeking and then writing, which two processes
   --  appending to one log would interleave wrongly.
   File_Append_Data : constant C_DWord := 4;

   File_Type_Char : constant C_DWord := 2;

   Error_Broken_Pipe : constant C_DWord := 109;
   Error_No_Data     : constant C_DWord := 232;

   --  SECURITY_ATTRIBUTES, needed only to say whether a pipe's handles are
   --  inheritable at creation.
   type Security_Attributes is record
      Length             : C_DWord := 0;
      Security_Descriptor : System.Address := System.Null_Address;
      Inherit_Handle     : Interfaces.C.int := 0;
   end record
     with Convention => C;

   function Create_Pipe_Native
     (Read_Handle  : access System.Address;
      Write_Handle : access System.Address;
      Attributes   : access Security_Attributes;
      Size         : C_DWord) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "CreatePipe";

   function Close_Handle (Handle : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

   function Get_Current_Process return System.Address
     with Import => True, Convention => Stdcall, External_Name => "GetCurrentProcess";

   function Duplicate_Handle
     (Source_Process : System.Address;
      Source         : System.Address;
      Target_Process : System.Address;
      Target         : access System.Address;
      Access_Wanted  : C_DWord;
      Inherit        : Interfaces.C.int;
      Options        : C_DWord) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "DuplicateHandle";

   Duplicate_Same_Access : constant C_DWord := 2;

   function Set_Handle_Information
     (Handle : System.Address;
      Mask   : C_DWord;
      Flags  : C_DWord) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "SetHandleInformation";

   function Get_Std_Handle (Which : C_DWord) return System.Address
     with Import => True, Convention => Stdcall, External_Name => "GetStdHandle";

   function Set_Std_Handle (Which : C_DWord; Handle : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "SetStdHandle";

   function Read_File
     (Handle    : System.Address;
      Buffer    : System.Address;
      To_Read   : C_DWord;
      Did_Read  : access C_DWord;
      Overlapped : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "ReadFile";

   function Write_File
     (Handle     : System.Address;
      Buffer     : System.Address;
      To_Write   : C_DWord;
      Did_Write  : access C_DWord;
      Overlapped : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "WriteFile";

   function Create_File
     (Name        : System.Address;
      Access_Mode : C_DWord;
      Share_Mode  : C_DWord;
      Security    : System.Address;
      Disposition : C_DWord;
      Attributes  : C_DWord;
      Template    : System.Address) return System.Address
     with Import => True, Convention => Stdcall, External_Name => "CreateFileW";

   function Get_File_Type (Handle : System.Address) return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetFileType";

   function Get_Console_Mode
     (Handle : System.Address; Mode : access C_DWord) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "GetConsoleMode";

   function Get_Last_Error return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetLastError";

   function Wide (Value : String) return Wide_String
   is (Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Value) & Wide_Character'Val (0));

   function To_Handle (Item : Descriptor) return System.Address
   is (System.Storage_Elements.To_Address
         (System.Storage_Elements.Integer_Address (Item)));

   function To_Descriptor (Handle : System.Address) return Descriptor;

   -------------------
   -- To_Descriptor --
   -------------------

   function To_Descriptor (Handle : System.Address) return Descriptor is
   begin
      if Handle = Invalid_Handle or else Handle = System.Null_Address then
         return Invalid;
      end if;

      return Descriptor
        (System.Storage_Elements.To_Integer (Handle));
   end To_Descriptor;

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
      Read_Handle  : aliased System.Address := System.Null_Address;
      Write_Handle : aliased System.Address := System.Null_Address;
      Attributes   : aliased Security_Attributes;
   begin
      Ends := (Read_End => Invalid, Write_End => Invalid);

      --  Created non-inheritable, as on POSIX, so a caller has to open that
      --  door deliberately and per child. Windows makes this the easy case:
      --  bInheritHandle false here, and SetHandleInformation for the one end
      --  that should travel.
      Attributes.Length := C_DWord (Security_Attributes'Size / 8);
      Attributes.Inherit_Handle := 0;

      if Create_Pipe_Native
           (Read_Handle'Access, Write_Handle'Access, Attributes'Access, 0) = 0
      then
         return False;
      end if;

      Ends.Read_End  := To_Descriptor (Read_Handle);
      Ends.Write_End := To_Descriptor (Write_Handle);

      return Is_Valid (Ends.Read_End) and then Is_Valid (Ends.Write_End);
   end Create_Pipe;

   -----------
   -- Close --
   -----------

   procedure Close (Item : in out Descriptor) is
      Ignored : Interfaces.C.int;
   begin
      if Item = Invalid then
         return;
      end if;

      Ignored := Close_Handle (To_Handle (Item));
      Item := Invalid;
   end Close;

   ---------------
   -- Duplicate --
   ---------------

   function Duplicate (Item : Descriptor) return Descriptor is
      Copy : aliased System.Address := System.Null_Address;
   begin
      if Item = Invalid then
         return Invalid;
      end if;

      if Duplicate_Handle
           (Get_Current_Process, To_Handle (Item), Get_Current_Process,
            Copy'Access, 0, 0, Duplicate_Same_Access) = 0
      then
         return Invalid;
      end if;

      return To_Descriptor (Copy);
   end Duplicate;

   ---------------------
   -- Set_Inheritable --
   ---------------------

   function Set_Inheritable (Item : Descriptor; Inheritable : Boolean) return Boolean is
   begin
      if Item = Invalid then
         return False;
      end if;

      --  Windows states the question the same way round as this package does,
      --  unlike POSIX, whose FD_CLOEXEC is its inverse.
      return Set_Handle_Information
               (To_Handle (Item),
                Handle_Flag_Inherit,
                (if Inheritable then Handle_Flag_Inherit else 0)) /= 0;
   end Set_Inheritable;

   ----------------------
   -- Set_Non_Blocking --
   ----------------------

   function Set_Non_Blocking (Item : Descriptor; Non_Blocking : Boolean) return Boolean is
      pragma Unreferenced (Item, Non_Blocking);
   begin
      --  An anonymous pipe on Windows has no non-blocking mode. Overlapped I/O
      --  is the host's answer, and it is a different shape of API rather than a
      --  flag on this one -- so this refuses instead of appearing to succeed
      --  and then blocking anyway, which is the worse of the two failures.
      --
      --  A caller that must not block asks Hostkit.Process.Wait_FD first, which
      --  on this host looks at whether the pipe has bytes waiting.
      return False;
   end Set_Non_Blocking;

   -------------------
   -- Wait_Readable --
   -------------------

   --  Asked of the pipe directly, because this host cannot poll one: poll and
   --  select are for sockets here. PeekNamedPipe says how many bytes are
   --  waiting without taking them, in a short loop until there are some or the
   --  deadline passes.
   function Wait_Readable
     (Item : Descriptor; Timeout_Ms : Integer) return Boolean
   is
      function Peek_Named_Pipe
        (Pipe            : System.Address;
         Buffer          : System.Address;
         Buffer_Size     : C_DWord;
         Bytes_Read      : access C_DWord;
         Total_Available : access C_DWord;
         Bytes_Left      : access C_DWord) return Interfaces.C.int
        with Import => True, Convention => Stdcall,
             External_Name => "PeekNamedPipe";

      procedure Sleep (Milliseconds : C_DWord)
        with Import => True, Convention => Stdcall, External_Name => "Sleep";

      Available : aliased C_DWord := 0;
      Waited    : Integer := 0;

      --  Ten milliseconds between asks. Short enough that a caller waiting
      --  fifty does not overshoot by much, long enough not to spin a core.
      Slice : constant Integer := 10;
   begin
      if Item = Invalid then
         return False;
      end if;

      loop
         Available := 0;

         if Peek_Named_Pipe
              (To_Handle (Item), System.Null_Address, 0, null,
               Available'Access, null) = 0
         then
            --  The pipe is gone, which is a readable event rather than a wait
            --  error: the caller's next read returns end-of-file at once. It
            --  is also what a handle that is not a pipe answers, and a caller
            --  told "not ready" about one of those would wait out its whole
            --  deadline for no reason.
            return True;
         end if;

         if Available > 0 then
            return True;
         end if;

         exit when Timeout_Ms >= 0 and then Waited >= Timeout_Ms;

         Sleep (C_DWord (Slice));
         Waited := Waited + Slice;
      end loop;

      return False;
   end Wait_Readable;

   ----------
   -- Read --
   ----------

   function Read
     (Item : Descriptor;
      Into : out Ada.Streams.Stream_Element_Array;
      Last : out Ada.Streams.Stream_Element_Offset) return Transfer_Outcome
   is
      Got : aliased C_DWord := 0;
   begin
      Into := [others => 0];
      Last := Into'First - 1;

      if Item = Invalid then
         return Transfer_Error;
      end if;

      if Into'Length = 0 then
         return Transfer_Ok;
      end if;

      if Read_File (To_Handle (Item), Into'Address, C_DWord (Into'Length),
                    Got'Access, System.Null_Address) = 0
      then
         declare
            Code : constant C_DWord := Get_Last_Error;
         begin
            --  A closed write end is ERROR_BROKEN_PIPE here rather than a zero
            --  byte read. Reported as end-of-file, because that is what it
            --  means and what every caller of this package is written against.
            if Code = Error_Broken_Pipe or else Code = Error_No_Data then
               return Transfer_End_Of_File;
            end if;

            return Transfer_Error;
         end;
      end if;

      if Got = 0 then
         return Transfer_End_Of_File;
      end if;

      Last := Into'First + Ada.Streams.Stream_Element_Offset (Got) - 1;
      return Transfer_Ok;
   end Read;

   -----------
   -- Write --
   -----------

   function Write
     (Item : Descriptor;
      From : Ada.Streams.Stream_Element_Array;
      Last : out Ada.Streams.Stream_Element_Offset) return Transfer_Outcome
   is
      Put : aliased C_DWord := 0;
   begin
      Last := From'First - 1;

      if Item = Invalid then
         return Transfer_Error;
      end if;

      if From'Length = 0 then
         return Transfer_Ok;
      end if;

      if Write_File (To_Handle (Item), From'Address, C_DWord (From'Length),
                     Put'Access, System.Null_Address) = 0
      then
         declare
            Code : constant C_DWord := Get_Last_Error;
         begin
            --  The reader is gone. Windows has no SIGPIPE to have to disarm
            --  first, so this arrives as an ordinary error and the caller sees
            --  the same outcome it would on POSIX.
            if Code = Error_Broken_Pipe or else Code = Error_No_Data then
               return Transfer_Broken_Pipe;
            end if;

            return Transfer_Error;
         end;
      end if;

      Last := From'First + Ada.Streams.Stream_Element_Offset (Put) - 1;
      return Transfer_Ok;
   end Write;

   --------------------
   -- Standard_Input --
   --------------------

   function Standard_Input return Descriptor is
   begin
      return To_Descriptor (Get_Std_Handle (Std_Input_Handle));
   end Standard_Input;

   ---------------------
   -- Standard_Output --
   ---------------------

   function Standard_Output return Descriptor is
   begin
      return To_Descriptor (Get_Std_Handle (Std_Output_Handle));
   end Standard_Output;

   --------------------
   -- Standard_Error --
   --------------------

   function Standard_Error return Descriptor is
   begin
      return To_Descriptor (Get_Std_Handle (Std_Error_Handle));
   end Standard_Error;

   ---------------
   -- Open_File --
   ---------------

   function Open_File
     (Path : String;
      Mode : Open_Mode;
      Item : out Descriptor) return Boolean
   is
      Wide_Path   : aliased Wide_String := Wide (Path);
      Access_Mode : C_DWord;
      Disposition : C_DWord;
      Handle      : System.Address;
      Attributes  : aliased Security_Attributes;
   begin
      Item := Invalid;

      Attributes.Length := C_DWord (Security_Attributes'Size / 8);
      Attributes.Inherit_Handle := 0;

      case Mode is
         when Open_Read =>
            Access_Mode := Generic_Read;
            Disposition := Open_Existing;
         when Open_Write_Truncate =>
            Access_Mode := Generic_Write;
            Disposition := Create_Always;
         when Open_Write_Append =>
            --  FILE_APPEND_DATA alone, deliberately: with GENERIC_WRITE as well
            --  the append becomes an ordinary write at the current position,
            --  and two processes appending to one file would overwrite each
            --  other rather than interleave.
            Access_Mode := File_Append_Data;
            Disposition := Open_Always;
         when Open_Write_Exclusive =>
            Access_Mode := Generic_Write;
            Disposition := Create_New;
         when Open_Read_Write =>
            Access_Mode := Generic_Read + Generic_Write;
            Disposition := Open_Existing;
      end case;

      Handle := Create_File
        (Wide_Path'Address, Access_Mode, File_Share_Read + File_Share_Write,
         Attributes'Address, Disposition, File_Attribute_Normal,
         System.Null_Address);

      Item := To_Descriptor (Handle);
      return Is_Valid (Item);
   end Open_File;

   -----------------
   -- Is_Terminal --
   -----------------

   function Is_Terminal (Item : Descriptor) return Boolean is
      Mode : aliased C_DWord := 0;
   begin
      if Item = Invalid then
         return False;
      end if;

      --  FILE_TYPE_CHAR is necessary but not sufficient: NUL is a character
      --  device too. GetConsoleMode succeeds only on a real console handle,
      --  which is the question actually being asked.
      if Get_File_Type (To_Handle (Item)) /= File_Type_Char then
         return False;
      end if;

      return Get_Console_Mode (To_Handle (Item), Mode'Access) /= 0;
   end Is_Terminal;

   function Terminal_Name (Item : Descriptor) return String is
   begin
      if Is_Terminal (Item) then
         return "CON";
      else
         return "";
      end if;
   exception
      when others =>
         return "";
   end Terminal_Name;

   ------------
   -- Assign --
   ------------

   function Assign (Item : Descriptor; To : Standard_Stream) return Boolean is
      Which : constant C_DWord :=
        (case To is
            when Stream_Input  => Std_Input_Handle,
            when Stream_Output => Std_Output_Handle,
            when Stream_Error  => Std_Error_Handle);
   begin
      if Item = Invalid then
         return False;
      end if;

      --  Windows has no fork, so there is no moment between it and exec in
      --  which to rearrange anything: CreateProcess takes the three handles up
      --  front, in STARTUPINFO. Hostkit.Spawn passes them there and does not
      --  call this. What this does is the other half of the same idea -- change
      --  this process's own standard handles -- which is what a caller
      --  redirecting its own output wants, and it also has to be inheritable to
      --  be worth anything to a child.
      if Set_Handle_Information
           (To_Handle (Item), Handle_Flag_Inherit, Handle_Flag_Inherit) = 0
      then
         return False;
      end if;

      return Set_Std_Handle (Which, To_Handle (Item)) /= 0;
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
