with Interfaces.C;
with Interfaces.C.Strings;
with System;

--  readdir, its d_type the kind: DT_DIR, DT_REG, DT_LNK, DT_UNKNOWN.
package body Hostkit.Directory_Listing is

   use type System.Address;

   type Dirent is record
      Inode         : Interfaces.C.unsigned_long;
      Offset        : Interfaces.C.long;
      Record_Length : Interfaces.C.unsigned_short;
      Kind          : Interfaces.C.unsigned_char;
      Name          : Interfaces.C.char_array (0 .. 255);
   end record with Convention => C;

   function C_Opendir (Name : Interfaces.C.Strings.chars_ptr) return System.Address
     with Import, Convention => C, External_Name => "opendir";
   function C_Readdir (Directory : System.Address) return System.Address
     with Import, Convention => C, External_Name => "readdir";
   function C_Closedir (Directory : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "closedir";

   function List (Path : String; Entries : out Entry_Vectors.Vector) return Boolean is
      C_Name    : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Handle    : constant System.Address := C_Opendir (C_Name);
      Pointer   : System.Address;
      Ignored   : Interfaces.C.int;
   begin
      Interfaces.C.Strings.Free (C_Name);
      Entries.Clear;
      if Handle = System.Null_Address then
         return False;
      end if;
      loop
         Pointer := C_Readdir (Handle);
         exit when Pointer = System.Null_Address;
         declare
            Item : Dirent with Import, Address => Pointer;
            Name : constant String := Interfaces.C.To_Ada (Item.Name);
            Kind : constant Entry_Kind :=
              (case Item.Kind is
                 when 4 => Directory,
                 when 8 => Regular_File,
                 when 10 => Symbolic_Link,
                 when 0 => Unknown,
                 when others => Other);
         begin
            if Name /= "." and then Name /= ".." then
               Entries.Append (Listed_Entry'(Length => Name'Length, Kind => Kind, Name => Name));
            end if;
         end;
      end loop;
      Ignored := C_Closedir (Handle);
      return True;
   exception
      when others =>
         Ignored := C_Closedir (Handle);
         return False;
   end List;

end Hostkit.Directory_Listing;
