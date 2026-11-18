with Ada.Directories;
with Hostkit.Filesystem_Rules;
with Ada.Text_IO;

separate (Hostkit.Mounts)
--  Linux: /proc/mounts, read whole. A line longer than a record can be, or
--  more lines than a host has mounts, ends the reading rather than the
--  program.
function Table return Mount_Vectors.Vector is
   Max_Line   : constant := 64 * 1024;
   Max_Mounts : constant := 16_384;
   Result : Mount_Vectors.Vector;
   File   : Ada.Text_IO.File_Type;
   Buffer : String (1 .. Max_Line);
   Last   : Natural;

   --  A field with its \ooo escapes decoded.
   function Decode (Value : String) return String renames Hostkit.Filesystem_Rules.Decode_Mount_Field;

   --  The Index-th space-separated field of Line, decoded; "" past the last.
   function Field (Line : String; Index : Positive) return String is
      Current : Positive := 1;
      Start   : Natural := 0;
   begin
      for Position in Line'Range loop
         if Line (Position) /= ' ' and then Start = 0 then
            Start := Position;
         elsif Line (Position) = ' ' and then Start /= 0 then
            if Current = Index then
               return Decode (Line (Start .. Position - 1));
            end if;
            Current := Current + 1;
            Start := 0;
         end if;
      end loop;
      return (if Start /= 0 and then Current = Index then Decode (Line (Start .. Line'Last)) else "");
   end Field;
begin
   if not Ada.Directories.Exists ("/proc/mounts") then
      return Result;
   end if;
   Ada.Text_IO.Open (File, Ada.Text_IO.In_File, "/proc/mounts", Form => "shared=no");
   while not Ada.Text_IO.End_Of_File (File) and then Natural (Result.Length) < Max_Mounts loop
      Ada.Text_IO.Get_Line (File, Buffer, Last);
      --  A line longer than a record can be (an overlay's lowerdir list):
      --  skipped -- the rest of it read away -- and the table read on.
      if Last = Buffer'Last then
         while not Ada.Text_IO.End_Of_File (File) loop
            Ada.Text_IO.Get_Line (File, Buffer, Last);
            exit when Last < Buffer'Last;
         end loop;
         goto Next_Line;
      end if;
      declare
         Line : constant String := Buffer (1 .. Last);
      begin
         if Field (Line, 2) /= "" then
            Result.Append
              (Mount'(Source          => Ada.Strings.Unbounded.To_Unbounded_String (Field (Line, 1)),
                Mount_Point     => Ada.Strings.Unbounded.To_Unbounded_String (Field (Line, 2)),
                Filesystem_Type => Ada.Strings.Unbounded.To_Unbounded_String (Field (Line, 3)),
                Options         => Ada.Strings.Unbounded.To_Unbounded_String (Field (Line, 4))));
         end if;
      end;
      <<Next_Line>>
   end loop;
   Ada.Text_IO.Close (File);
   return Result;
exception
   when others =>
      if Ada.Text_IO.Is_Open (File) then
         Ada.Text_IO.Close (File);
      end if;
      return Result;
end Table;
