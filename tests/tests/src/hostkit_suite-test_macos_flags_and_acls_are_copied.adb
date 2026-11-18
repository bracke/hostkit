separate (Hostkit_Suite)
procedure Test_Macos_Flags_And_Acls_Are_Copied
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Source  : constant String := Ada.Directories.Compose (Scratch, "hostkit-flags-source");
   Target  : constant String := Ada.Directories.Compose (Scratch, "hostkit-flags-target");
   Listing : constant String := Ada.Directories.Compose (Scratch, "hostkit-flags-listing");
   File    : Ada.Text_IO.File_Type;
   Done    : Boolean;
   Code    : Integer;

   --  The listing's lines, one text.
   function Read_Listing return String is
      Input : Ada.Text_IO.File_Type;
      Text  : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Ada.Text_IO.Open (Input, Ada.Text_IO.In_File, Listing);
      while not Ada.Text_IO.End_Of_File (Input) loop
         Ada.Strings.Unbounded.Append (Text, Ada.Text_IO.Get_Line (Input) & " ");
      end loop;
      Ada.Text_IO.Close (Input);
      return Ada.Strings.Unbounded.To_String (Text);
   end Read_Listing;

   procedure Run (Program : String; Arguments : String) is
      Parts : GNAT.OS_Lib.Argument_List_Access := GNAT.OS_Lib.Argument_String_To_List (Arguments);
   begin
      GNAT.OS_Lib.Spawn (Program, Parts.all, Done);
      GNAT.OS_Lib.Free (Parts);
   end Run;
   --  Name with its ACL and hidden flag taken off, then gone.
   procedure Remove (Name : String) is
   begin
      if Ada.Directories.Exists (Name) then
         Run ("/bin/chmod", "-N " & Name);
         Run ("/usr/bin/chflags", "nohidden " & Name);
         Ada.Directories.Delete_File (Name);
      end if;
   end Remove;

   --  An empty file at Name.
   procedure Fresh (Name : String) is
   begin
      Remove (Name);
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Name);
      Ada.Text_IO.Close (File);
   end Fresh;
begin
   if Hostkit.Host.Current /= Hostkit.Host.MacOS then
      Skip ("Test_Macos_Flags_And_Acls_Are_Copied", "needs macOS file flags and ACLs");
      return;
   end if;
   Fresh (Source);
   Fresh (Target);
   --  What listxattr does not show: the Finder's hidden flag, and an
   --  extended ACL entry.
   Run ("/usr/bin/chflags", "hidden " & Source);
   Assert (Done and then Hostkit.Fs.Is_Hidden (Source), "the source is hidden");
   Run ("/bin/chmod", "+a ""everyone deny delete"" " & Source);
   Assert (Done, "the source has an ACL entry");
   Assert
     (Hostkit.Metadata_Copy.Apply (Hostkit.Metadata_Copy.Capture (Source), Target, Preserve_Ownership => False),
      "its metadata is applied to the copy");
   Assert (Hostkit.Fs.Is_Hidden (Target), "the copy is hidden too");
   declare
      Parts : GNAT.OS_Lib.Argument_List_Access := GNAT.OS_Lib.Argument_String_To_List ("-le " & Target);
   begin
      GNAT.OS_Lib.Spawn ("/bin/ls", Parts.all, Listing, Done, Code);
      GNAT.OS_Lib.Free (Parts);
   end;
   Assert (Done and then Code = 0, "the copy is listed with its ACL");
   declare
      Text : constant String := Read_Listing;
   begin
      Assert (Ada.Strings.Fixed.Index (Text, "deny delete") > 0, "and it has the source's ACL entry: " & Text);
   end;
   Remove (Source);
   Remove (Target);
   Ada.Directories.Delete_File (Listing);
end Test_Macos_Flags_And_Acls_Are_Copied;
