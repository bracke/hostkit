with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Hostkit.Metadata_Copy is
   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.Strings.chars_ptr;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_64;

   subtype C_Int is Interfaces.C.int;
   subtype C_Long is Interfaces.C.long;
   subtype C_U16 is Interfaces.C.unsigned_short;
   subtype C_U32 is Interfaces.C.unsigned;
   subtype C_U64 is Interfaces.C.unsigned_long;
   subtype C_S64 is Interfaces.C.long;

   type U16_Array is array (Positive range <>) of C_U16 with Convention => C;
   type U64_Array is array (Positive range <>) of C_U64 with Convention => C;
   type Byte_Array is array (Natural range <>) of aliased Interfaces.Unsigned_8
     with Convention => C;

   type Statx_Timestamp is record
      Seconds : C_S64;
      Nanoseconds, Reserved : C_U32;
   end record with Convention => C;

   type Statx_Record is record
      Mask, Block_Size : C_U32;
      Attributes : C_U64;
      Link_Count, User_Id, Group_Id : C_U32;
      Mode : C_U16;
      Spare_0 : U16_Array (1 .. 1);
      Inode, Size, Blocks, Attributes_Mask : C_U64;
      Access_Time, Birth_Time, Change_Time, Modified_Time : Statx_Timestamp;
      Device_Major, Device_Minor, File_Major, File_Minor : C_U32;
      Mount_Id : C_U64;
      Direct_Io_Memory_Align, Direct_Io_Offset_Align : C_U32;
      Spare_3 : U64_Array (1 .. 12);
   end record with Convention => C;

   type Timespec is record
      Seconds, Nanoseconds : C_S64;
   end record with Convention => C;
   type Timespec_Array is array (Positive range 1 .. 2) of Timespec
     with Convention => C;

   At_Fdcwd : constant C_Int := -100;
   At_Symlink_Nofollow : constant C_U32 := 16#100#;
   Statx_Basic_Stats : constant C_U32 := 16#7FF#;
   File_Type_Mask : constant C_U16 := 8#170000#;
   Link_Type : constant C_U16 := 8#120000#;
   Maximum_Attribute_Bytes : constant := 64 * 1_024 * 1_024;
   E_No_Data : constant C_Int := 61;
   E_Not_Supported : constant C_Int := 95;

   function C_Statx
     (Directory_Fd : C_Int; Path : Interfaces.C.Strings.chars_ptr;
      Flags, Mask : C_U32; Info : access Statx_Record) return C_Int
     with Import, Convention => C, External_Name => "statx";
   function C_Llistxattr
     (Path : Interfaces.C.Strings.chars_ptr; Names : System.Address;
      Size : Interfaces.C.size_t) return C_Long
     with Import, Convention => C, External_Name => "llistxattr";
   function C_Lgetxattr
     (Path, Name : Interfaces.C.Strings.chars_ptr; Value : System.Address;
      Size : Interfaces.C.size_t) return C_Long
     with Import, Convention => C, External_Name => "lgetxattr";
   function C_Lsetxattr
     (Path, Name : Interfaces.C.Strings.chars_ptr; Value : System.Address;
      Size : Interfaces.C.size_t; Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "lsetxattr";
   function C_Lremovexattr
     (Path, Name : Interfaces.C.Strings.chars_ptr) return C_Int
     with Import, Convention => C, External_Name => "lremovexattr";
   function C_Lchown
     (Path : Interfaces.C.Strings.chars_ptr; Owner, Group : C_U32) return C_Int
     with Import, Convention => C, External_Name => "lchown";
   function C_Chmod
     (Path : Interfaces.C.Strings.chars_ptr; Mode : C_U32) return C_Int
     with Import, Convention => C, External_Name => "chmod";
   function C_Utimensat
     (Directory_Fd : C_Int; Path : Interfaces.C.Strings.chars_ptr;
      Times : access Timespec_Array; Flags : C_U32) return C_Int
     with Import, Convention => C, External_Name => "utimensat";
   function Errno_Location return System.Address
     with Import, Convention => C, External_Name => "__errno_location";

   function Errno return C_Int is
      Value : C_Int with Import, Address => Errno_Location;
   begin
      return Value;
   end Errno;

   procedure Free (Item : in out Interfaces.C.Strings.chars_ptr) is
   begin
      if Item /= Interfaces.C.Strings.Null_Ptr then
         Interfaces.C.Strings.Free (Item);
      end if;
   end Free;

   function Stat (Path : String; Info : access Statx_Record) return Boolean is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Ok : constant Boolean := C_Statx
        (At_Fdcwd, C_Path, At_Symlink_Nofollow, Statx_Basic_Stats, Info) = 0;
   begin
      Free (C_Path);
      return Ok and then (Info.Mask and Statx_Basic_Stats) = Statx_Basic_Stats;
   exception
      when others =>
         Free (C_Path);
         return False;
   end Stat;

   function Capture_Times
     (Path : String; Times : out Entry_Times) return Boolean
   is
      Info : aliased Statx_Record;
   begin
      Times := [others => 0];
      if not Stat (Path, Info'Access) then
         return False;
      end if;
      Times :=
        [Interfaces.Integer_64 (Info.Access_Time.Seconds),
         Interfaces.Integer_64 (Info.Access_Time.Nanoseconds),
         Interfaces.Integer_64 (Info.Modified_Time.Seconds),
         Interfaces.Integer_64 (Info.Modified_Time.Nanoseconds)];
      return True;
   end Capture_Times;

   function Apply_Times
     (Path : String; Times : Entry_Times) return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Values : aliased Timespec_Array :=
        [(C_S64 (Times (1)), C_S64 (Times (2))),
         (C_S64 (Times (3)), C_S64 (Times (4)))];
      Ok : constant Boolean := C_Utimensat
        (At_Fdcwd, C_Path, Values'Access, At_Symlink_Nofollow) = 0;
   begin
      Free (C_Path);
      return Ok;
   exception
      when others =>
         Free (C_Path);
         return False;
   end Apply_Times;

   function Capture (Path : String) return Snapshot is
      Result : Snapshot;
      Info : aliased Statx_Record;
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Names_Size, Actual, Value_Size : C_Long;
      Total : Natural := 0;
   begin
      if not Stat (Path, Info'Access) then
         return No_Snapshot;
      end if;
      Result.Available := True;
      Result.Times :=
        [Interfaces.Integer_64 (Info.Access_Time.Seconds),
         Interfaces.Integer_64 (Info.Access_Time.Nanoseconds),
         Interfaces.Integer_64 (Info.Modified_Time.Seconds),
         Interfaces.Integer_64 (Info.Modified_Time.Nanoseconds)];
      Result.Links := Interfaces.Unsigned_64 (Info.Link_Count);
      Result.Mode := Interfaces.Unsigned_64 (Info.Mode);
      Result.Owner := Interfaces.Unsigned_64 (Info.User_Id);
      Result.Group := Interfaces.Unsigned_64 (Info.Group_Id);
      Result.Is_Link := (Info.Mode and File_Type_Mask) = Link_Type;

      C_Path := Interfaces.C.Strings.New_String (Path);
      Names_Size := C_Llistxattr (C_Path, System.Null_Address, 0);
      if Names_Size < 0 then
         if Errno = E_Not_Supported then
            Free (C_Path);
            return Result;
         end if;
         Free (C_Path);
         return No_Snapshot;
      elsif Names_Size = 0 then
         Free (C_Path);
         return Result;
      elsif Names_Size > C_Long (Maximum_Attribute_Bytes) then
         Free (C_Path);
         return No_Snapshot;
      end if;

      declare
         Names : aliased Byte_Array (0 .. Natural (Names_Size) - 1);
      begin
         Actual := C_Llistxattr
           (C_Path, Names'Address, Interfaces.C.size_t (Names'Length));
         if Actual < 0 or else Actual > Names_Size then
            Free (C_Path);
            return No_Snapshot;
         end if;
         Total := Natural (Actual);
         declare
            Offset : Natural := 0;
         begin
            while Offset < Natural (Actual) loop
               declare
                  Last : Natural := Offset;
               begin
                  while Last < Natural (Actual) and then Names (Last) /= 0 loop
                     Last := Last + 1;
                  end loop;
                  if Last = Natural (Actual) then
                     Free (C_Path);
                     return No_Snapshot;
                  end if;
                  declare
                     Name : String (1 .. Last - Offset);
                  begin
                     for Index in Name'Range loop
                        Name (Index) := Character'Val
                          (Names (Offset + Index - Name'First));
                     end loop;
                     Offset := Last + 1;
                     if Name /= "security.capability" then
                        declare
                           C_Name : Interfaces.C.Strings.chars_ptr :=
                             Interfaces.C.Strings.New_String (Name);
                        begin
                           Value_Size := C_Lgetxattr
                             (C_Path, C_Name, System.Null_Address, 0);
                           if Value_Size < 0
                             or else Value_Size > C_Long (Maximum_Attribute_Bytes - Total)
                           then
                              Free (C_Name);
                              Free (C_Path);
                              return No_Snapshot;
                           end if;
                           Total := Total + Natural (Value_Size);
                           if Value_Size = 0 then
                              Result.Attributes.Append
                                (Attribute'
                                   (To_Unbounded_String (Name),
                                    Null_Unbounded_String));
                           else
                              declare
                                 Value : aliased Byte_Array
                                   (0 .. Natural (Value_Size) - 1);
                                 Got : C_Long;
                                 Text : String (1 .. Natural (Value_Size));
                              begin
                                 Got := C_Lgetxattr
                                   (C_Path, C_Name, Value'Address,
                                    Interfaces.C.size_t (Value'Length));
                                 if Got /= Value_Size then
                                    Free (C_Name);
                                    Free (C_Path);
                                    return No_Snapshot;
                                 end if;
                                 for Index in Text'Range loop
                                    Text (Index) := Character'Val
                                      (Value (Index - Text'First));
                                 end loop;
                                 Result.Attributes.Append
                                   (Attribute'
                                      (To_Unbounded_String (Name),
                                       To_Unbounded_String (Text)));
                              end;
                           end if;
                           Free (C_Name);
                        end;
                     end if;
                  end;
               end;
            end loop;
         end;
      end;
      Free (C_Path);
      return Result;
   exception
      when others =>
         Free (C_Path);
         return No_Snapshot;
   end Capture;

   function Is_Available (Item : Snapshot) return Boolean is (Item.Available);
   function Link_Count (Item : Snapshot) return Interfaces.Unsigned_64 is (Item.Links);

   procedure Set_Times (Item : in out Snapshot; Times : Entry_Times) is
   begin
      Item.Times := Times;
   end Set_Times;

   function Has_Attribute (Item : Snapshot; Name : String) return Boolean is
   begin
      for Attribute of Item.Attributes loop
         if To_String (Attribute.Name) = Name then
            return True;
         end if;
      end loop;
      return False;
   end Has_Attribute;

   function Apply_Attribute
     (Path : Interfaces.C.Strings.chars_ptr; Item : Attribute) return Boolean
   is
      Name_Text : constant String := To_String (Item.Name);
      Value_Text : constant String := To_String (Item.Value);
      C_Name : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Name_Text);
      Value : aliased Byte_Array (0 .. Natural'Max (1, Value_Text'Length) - 1) :=
        [others => 0];
      Ok : Boolean;
   begin
      for Index in Value_Text'Range loop
         Value (Index - Value_Text'First) := Character'Pos (Value_Text (Index));
      end loop;
      Ok := C_Lsetxattr
        (Path, C_Name, Value'Address,
         Interfaces.C.size_t (Value_Text'Length), 0) = 0;
      Free (C_Name);
      return Ok;
   exception
      when others =>
         Free (C_Name);
         return False;
   end Apply_Attribute;

   function Apply
     (Item : Snapshot; Path : String; Preserve_Ownership : Boolean)
      return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Current : aliased Statx_Record;
      Status : C_Int;
      Ok : Boolean := Item.Available;
      Acl_Access : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Acl_Default : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
   begin
      if Ok and then Preserve_Ownership then
         Ok := Stat (Path, Current'Access);
         if Ok and then
           (Interfaces.Unsigned_64 (Current.User_Id) /= Item.Owner
            or else Interfaces.Unsigned_64 (Current.Group_Id) /= Item.Group)
         then
            Ok := C_Lchown
              (C_Path, C_U32 (Item.Owner), C_U32 (Item.Group)) = 0;
         end if;
      end if;
      if Ok and then not Item.Is_Link then
         Acl_Access := Interfaces.C.Strings.New_String
           ("system.posix_acl_access");
         Acl_Default := Interfaces.C.Strings.New_String
           ("system.posix_acl_default");
         if not Has_Attribute (Item, "system.posix_acl_access") then
            Status := C_Lremovexattr (C_Path, Acl_Access);
            Ok := Status = 0 or else Errno = E_No_Data
              or else Errno = E_Not_Supported;
         end if;
         if Ok and then not Has_Attribute (Item, "system.posix_acl_default") then
            Status := C_Lremovexattr (C_Path, Acl_Default);
            Ok := Status = 0 or else Errno = E_No_Data
              or else Errno = E_Not_Supported;
         end if;
      end if;
      for Acl_Pass in Boolean loop
         for Attribute of Item.Attributes loop
            declare
               Name : constant String := To_String (Attribute.Name);
               Is_Acl : constant Boolean :=
                 Name = "system.posix_acl_access"
                 or else Name = "system.posix_acl_default";
            begin
               if Ok and then Is_Acl = Acl_Pass then
                  Ok := Apply_Attribute (C_Path, Attribute);
               end if;
            end;
         end loop;
      end loop;
      if Ok and then not Item.Is_Link then
         Ok := C_Chmod (C_Path, C_U32 (Item.Mode and 8#1777#)) = 0;
      end if;
      Free (Acl_Access);
      Free (Acl_Default);
      Free (C_Path);
      return Ok and then Apply_Times (Path, Item.Times);
   exception
      when others =>
         Free (Acl_Access);
         Free (Acl_Default);
         Free (C_Path);
         return False;
   end Apply;
end Hostkit.Metadata_Copy;
