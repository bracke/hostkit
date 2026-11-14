with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Strings.Unbounded;
with GNAT.OS_Lib;

with Hostkit.Directory_Listing;
with Hostkit.Environment;
with Hostkit.Fs;
with Hostkit.Process;
with Hostkit.Regular_Files;

package body Hostkit.Desktop_Entries is
   use Ada.Strings.Unbounded;

   --  Entries are found in folders anybody may write to (XDG_DATA_HOME), so
   --  each is bounded before it is read. Real entries are a few KiB; one MiB
   --  leaves room for many localized keys and action groups.
   Max_File_Bytes     : constant Natural := 1 * 1024 * 1024;
   Max_Line_Bytes     : constant Natural := 64 * 1024;
   Max_Lines          : constant Natural := 4_096;
   Max_List_Items     : constant Natural := 256;
   Max_Exec_Arguments : constant Natural := 256;
   Max_Scan_Depth     : constant Natural := 64;
   Max_Scan_Entries   : constant Natural := 100_000;

   package Name_Sets is new Ada.Containers.Indefinite_Ordered_Sets (Element_Type => String);

   --  Text without the blanks around it. Lines are split at LF and CR alike,
   --  and a CR left over is a blank, so a CRLF file reads as its LF twin.
   function Trim_Blanks (Text : String) return String is
      First : Integer := Text'First;
      Last  : Integer := Text'Last;

      function Blank (Value : Character) return Boolean is
        (Value = ' ' or else Value = ASCII.HT or else Value = ASCII.CR);
   begin
      while First <= Last and then Blank (Text (First)) loop
         First := First + 1;
      end loop;
      while Last >= First and then Blank (Text (Last)) loop
         Last := Last - 1;
      end loop;
      return Text (First .. Last);
   end Trim_Blanks;

   --  A locale name without its encoding: "da_DK.UTF-8@euro" is "da_DK@euro".
   function Strip_Locale_Encoding (Locale : String) return String is
      Dot      : Natural := 0;
      Modifier : Natural := 0;
   begin
      for Index in Locale'Range loop
         if Locale (Index) = '.' and then Dot = 0 then
            Dot := Index;
         elsif Locale (Index) = '@' and then Modifier = 0 then
            Modifier := Index;
         end if;
      end loop;

      if Dot = 0 then
         return Locale;
      elsif Modifier > Dot then
         return Locale (Locale'First .. Dot - 1) & Locale (Modifier .. Locale'Last);
      else
         return Locale (Locale'First .. Dot - 1);
      end if;
   end Strip_Locale_Encoding;

   function Locale_Candidates (Locale : String) return String_Vectors.Vector is
      Result : String_Vectors.Vector;

      procedure Append_Unique (Value : String) is
      begin
         if Value = "" then
            return;
         end if;
         for Existing of Result loop
            if To_String (Existing) = Value then
               return;
            end if;
         end loop;
         Result.Append (To_Unbounded_String (Value));
      end Append_Unique;

      Name      : constant String := Strip_Locale_Encoding (Trim_Blanks (Locale));
      Underline : Natural := 0;
      Modifier  : Natural := 0;
   begin
      for Index in Name'Range loop
         if Name (Index) = '_' and then Underline = 0 then
            Underline := Index;
         elsif Name (Index) = '@' and then Modifier = 0 then
            Modifier := Index;
         end if;
      end loop;

      Append_Unique (Name);
      if Underline /= 0 then
         Append_Unique (Name (Name'First .. (if Modifier > Underline then Modifier - 1 else Name'Last)));
      end if;
      if Modifier /= 0 then
         Append_Unique
           (Name (Name'First .. (if Underline /= 0 then Underline - 1 else Modifier - 1))
            & Name (Modifier .. Name'Last));
      end if;
      if Underline /= 0 or else Modifier /= 0 then
         Append_Unique (Name (Name'First .. (if Underline /= 0 then Underline - 1 else Modifier - 1)));
      end if;
      return Result;
   end Locale_Candidates;

   function Message_Locale_Candidates return String_Vectors.Vector is
      function Set (Name : String) return String is
        (Trim_Blanks (Hostkit.Environment.Value (Name, Default => "")));

      LC_All      : constant String := Set ("LC_ALL");
      LC_Messages : constant String := Set ("LC_MESSAGES");
   begin
      return Locale_Candidates
        (if LC_All /= "" then LC_All elsif LC_Messages /= "" then LC_Messages else Set ("LANG"));
   end Message_Locale_Candidates;

   function Current_Desktops return String is
     (Hostkit.Environment.Value ("XDG_CURRENT_DESKTOP", Default => ""));

   --  How well Key, a localized form of Base_Key ("Name[da_DK]"), matches
   --  Candidates: 1 for the first, 2 for the second, and so on; 0 when it
   --  is no localized form of Base_Key or names a locale not asked for.
   function Localized_Key_Rank
     (Key        : String;
      Base_Key   : String;
      Candidates : String_Vectors.Vector)
      return Natural
   is
      Prefix_Length : constant Natural := Base_Key'Length + 1;
   begin
      if Key'Length <= Base_Key'Length + 2
        or else Key (Key'First .. Key'First + Base_Key'Length) /= Base_Key & "["
        or else Key (Key'Last) /= ']'
      then
         return 0;
      end if;

      declare
         Locale : constant String := Strip_Locale_Encoding (Key (Key'First + Prefix_Length .. Key'Last - 1));
         Rank   : Natural := 1;
      begin
         for Candidate of Candidates loop
            if Locale = To_String (Candidate) then
               return Rank;
            end if;
            Rank := Rank + 1;
         end loop;
      end;
      return 0;
   end Localized_Key_Rank;

   function Decode_Value (Value : String; Decoded : out UString) return Boolean is
      Position : Integer := Value'First;
   begin
      Decoded := Null_Unbounded_String;
      while Position <= Value'Last loop
         if Value (Position) /= '\' then
            Append (Decoded, Value (Position));
         elsif Position = Value'Last then
            Decoded := Null_Unbounded_String;
            return False;
         else
            Position := Position + 1;
            case Value (Position) is
               when 's' => Append (Decoded, ' ');
               when 'n' => Append (Decoded, ASCII.LF);
               when 't' => Append (Decoded, ASCII.HT);
               when 'r' => Append (Decoded, ASCII.CR);
               when '\' => Append (Decoded, '\');
               when others =>
                  Decoded := Null_Unbounded_String;
                  return False;
            end case;
         end if;
         Position := Position + 1;
      end loop;
      return True;
   end Decode_Value;

   function Decode_List (Value : String; Items : out String_Vectors.Vector) return Boolean is
      Current  : Unbounded_String;
      Position : Integer := Value'First;
   begin
      Items.Clear;
      while Position <= Value'Last loop
         if Value (Position) = ';' then
            if Natural (Items.Length) >= Max_List_Items then
               Items.Clear;
               return False;
            end if;
            Items.Append (Current);
            Current := Null_Unbounded_String;
         elsif Value (Position) /= '\' then
            Append (Current, Value (Position));
         elsif Position = Value'Last then
            Items.Clear;
            return False;
         else
            Position := Position + 1;
            case Value (Position) is
               when 's' => Append (Current, ' ');
               when 'n' => Append (Current, ASCII.LF);
               when 't' => Append (Current, ASCII.HT);
               when 'r' => Append (Current, ASCII.CR);
               when '\' => Append (Current, '\');
               when ';' => Append (Current, ';');
               when others =>
                  Items.Clear;
                  return False;
            end case;
         end if;
         Position := Position + 1;
      end loop;

      --  The last item needs no ';' after it.
      if Length (Current) > 0 or else (Value'Length > 0 and then Value (Value'Last) /= ';') then
         if Natural (Items.Length) >= Max_List_Items then
            Items.Clear;
            return False;
         end if;
         Items.Append (Current);
      end if;
      return True;
   end Decode_List;

   function List_Contains (List : String_Vectors.Vector; Item : String) return Boolean is
   begin
      if Item = "" then
         return False;
      end if;
      for Existing of List loop
         if To_String (Existing) = Item then
            return True;
         end if;
      end loop;
      return False;
   end List_Contains;

   function Lists_Overlap (Left, Right : String_Vectors.Vector) return Boolean is
   begin
      for Item of Left loop
         if List_Contains (Right, To_String (Item)) then
            return True;
         end if;
      end loop;
      return False;
   end Lists_Overlap;

   --  OnlyShowIn and NotShowIn, decoded, applied to each of the
   --  ':'-separated current desktops.
   function Allows
     (Only_Show_In    : String_Vectors.Vector;
      Have_Only       : Boolean;
      Not_Show_In     : String_Vectors.Vector;
      Have_Not        : Boolean;
      Current_Desktop : String)
      return Boolean
   is
      First        : Integer := Current_Desktop'First;
      Last         : Integer;
      Only_Matched : Boolean := False;
   begin
      --  Both keys may be given, but one desktop name cannot be in both.
      if Have_Only and then Have_Not and then Lists_Overlap (Only_Show_In, Not_Show_In) then
         return False;
      end if;

      while First <= Current_Desktop'Last loop
         Last := First;
         while Last <= Current_Desktop'Last and then Current_Desktop (Last) /= ':' loop
            Last := Last + 1;
         end loop;
         declare
            Desktop : constant String := Current_Desktop (First .. Last - 1);
         begin
            --  An exclusion applies to the whole set of current desktops: an
            --  earlier OnlyShowIn match does not get past a later exclusion.
            if Have_Not and then List_Contains (Not_Show_In, Desktop) then
               return False;
            end if;
            Only_Matched := Only_Matched or else (Have_Only and then List_Contains (Only_Show_In, Desktop));
         end;
         First := Last + 1;
      end loop;

      --  An unmatched OnlyShowIn hides the entry; an unmatched NotShowIn does not.
      return not Have_Only or else Only_Matched;
   end Allows;

   function Shown_In
     (Only_Show_In    : String;
      Not_Show_In     : String;
      Current_Desktop : String)
      return Boolean
   is
      Only     : String_Vectors.Vector;
      Excluded : String_Vectors.Vector;
   begin
      if (Only_Show_In /= "" and then not Decode_List (Only_Show_In, Only))
        or else (Not_Show_In /= "" and then not Decode_List (Not_Show_In, Excluded))
      then
         return False;
      end if;
      return Allows (Only, Only_Show_In /= "", Excluded, Not_Show_In /= "", Current_Desktop);
   end Shown_In;

   --  Exec values are argument vectors, not shell command lines: quotes and
   --  backslashes group characters and are removed before the vector reaches
   --  the process. A field code inside quotes is invalid by the
   --  specification; refusing it also keeps its argument boundaries from
   --  changing silently.
   function Split_Exec (Exec : String; Arguments : out String_Vectors.Vector) return Boolean is
      Current   : Unbounded_String;
      Position  : Integer := Exec'First;
      In_Quotes : Boolean := False;
      --  An argument has begun: "" is an argument, a run of spaces is not.
      Started   : Boolean := False;

      function Finish_Argument return Boolean is
      begin
         if Started then
            if Natural (Arguments.Length) >= Max_Exec_Arguments then
               return False;
            end if;
            Arguments.Append (Current);
            Current := Null_Unbounded_String;
            Started := False;
         end if;
         return True;
      end Finish_Argument;
   begin
      Arguments.Clear;
      if Exec'Length > Max_Line_Bytes then
         return False;
      end if;

      while Position <= Exec'Last loop
         if Exec (Position) = '\' then
            if Position = Exec'Last then
               Arguments.Clear;
               return False;
            end if;
            Position := Position + 1;
            Append (Current, Exec (Position));
            Started := True;
         elsif Exec (Position) = '"' then
            In_Quotes := not In_Quotes;
            Started := True;
         elsif (Exec (Position) = ' ' or else Exec (Position) = ASCII.HT) and then not In_Quotes then
            if not Finish_Argument then
               Arguments.Clear;
               return False;
            end if;
         elsif In_Quotes and then Exec (Position) = '%' then
            --  Field codes are not allowed inside quotes; an escaped "%%" is.
            --  Both characters are kept (Expand_Field_Codes makes them one)
            --  and the second is stepped over, which would otherwise be read
            --  as the start of a field code.
            if Position = Exec'Last or else Exec (Position + 1) /= '%' then
               Arguments.Clear;
               return False;
            end if;
            Append (Current, "%%");
            Started := True;
            Position := Position + 1;
         else
            Append (Current, Exec (Position));
            Started := True;
         end if;
         Position := Position + 1;
      end loop;

      if In_Quotes or else not Finish_Argument then
         Arguments.Clear;
         return False;
      end if;
      return True;
   end Split_Exec;

   function Expand_Field_Codes
     (Arguments    : String_Vectors.Vector;
      Name         : String;
      Icon         : String;
      Location     : String;
      Targets      : String_Vectors.Vector;
      Command      : out String_Vectors.Vector;
      Target_Field : out Boolean)
      return Boolean
   is
      Valid   : Boolean := True;
      Program : Unbounded_String;

      --  The program may hold %% and no other field code.
      procedure Decode_Program (Token : String) is
         Position : Integer := Token'First;
      begin
         while Position <= Token'Last loop
            if Token (Position) /= '%' then
               Append (Program, Token (Position));
               Position := Position + 1;
            elsif Position = Token'Last or else Token (Position + 1) /= '%' then
               Valid := False;
               return;
            else
               Append (Program, '%');
               Position := Position + 2;
            end if;
         end loop;
      end Decode_Program;

      procedure Append_Expanded (Token : String) is
         Expanded  : Unbounded_String;
         Position  : Integer := Token'First;
         Had_Field : Boolean := False;

         procedure Use_Target is
         begin
            if Target_Field then
               Valid := False;
               return;
            end if;
            Target_Field := True;
            if not Targets.Is_Empty then
               Append (Expanded, To_String (Targets.First_Element));
            end if;
         end Use_Target;
      begin
         if Token = "%F" or else Token = "%U" then
            if Target_Field then
               Valid := False;
               return;
            end if;
            Target_Field := True;
            for Target of Targets loop
               Command.Append (Target);
            end loop;
            return;
         elsif Token = "%i" then
            if Icon /= "" then
               Command.Append (To_Unbounded_String ("--icon"));
               Command.Append (To_Unbounded_String (Icon));
            end if;
            return;
         end if;

         while Position <= Token'Last loop
            if Token (Position) /= '%' then
               Append (Expanded, Token (Position));
               Position := Position + 1;
            elsif Position = Token'Last then
               Valid := False;
               return;
            else
               Had_Field := True;
               case Token (Position + 1) is
                  when '%' =>
                     Append (Expanded, '%');
                  when 'f' | 'u' =>
                     Use_Target;
                     if not Valid then
                        return;
                     end if;
                  when 'c' =>
                     Append (Expanded, Name);
                  when 'k' =>
                     Append (Expanded, Location);
                  when 'd' | 'D' | 'n' | 'N' | 'v' | 'm' =>
                     --  Deprecated: nothing.
                     null;
                  when others =>
                     --  %F %U and %i expand to several arguments, so they are
                     --  only valid as a whole one; anything else is unknown.
                     Valid := False;
                     return;
               end case;
               Position := Position + 2;
            end if;
         end loop;

         --  An argument that was only field codes expanding to nothing goes.
         if Length (Expanded) > 0 or else not Had_Field then
            Command.Append (Expanded);
         end if;
      end Append_Expanded;
   begin
      Command.Clear;
      Target_Field := False;
      if Arguments.Is_Empty then
         return False;
      end if;

      Decode_Program (To_String (Arguments.First_Element));
      if not Valid or else Length (Program) = 0 or else Index (Program, "=") /= 0 then
         return False;
      end if;
      Command.Append (Program);

      for Position in Arguments.First_Index + 1 .. Arguments.Last_Index loop
         Append_Expanded (To_String (Arguments (Position)));
         exit when not Valid;
      end loop;

      if not Valid then
         Command.Clear;
         Target_Field := False;
         return False;
      end if;
      return True;
   end Expand_Field_Codes;

   function Command_For
     (Exec         : String;
      Name         : String;
      Icon         : String;
      Location     : String;
      Targets      : String_Vectors.Vector;
      Command      : out String_Vectors.Vector;
      Target_Field : out Boolean)
      return Boolean
   is
      Arguments : String_Vectors.Vector;
   begin
      Command.Clear;
      Target_Field := False;
      if not Split_Exec (Exec, Arguments) then
         return False;
      end if;
      return Expand_Field_Codes (Arguments, Name, Icon, Location, Targets, Command, Target_Field);
   end Command_For;

   function Takes_One_Target (Exec : String) return Boolean is
      Arguments : String_Vectors.Vector;
   begin
      if not Split_Exec (Exec, Arguments) or else Arguments.Is_Empty then
         return False;
      end if;

      for Argument_Index in Arguments.First_Index + 1 .. Arguments.Last_Index loop
         declare
            Token    : constant String := To_String (Arguments (Argument_Index));
            Position : Integer := Token'First;
         begin
            while Position <= Token'Last loop
               if Token (Position) = '%' and then Position < Token'Last then
                  if Token (Position + 1) = 'f' or else Token (Position + 1) = 'u' then
                     return True;
                  end if;
                  Position := Position + 2;
               else
                  Position := Position + 1;
               end if;
            end loop;
         end;
      end loop;
      return False;
   end Takes_One_Target;

   --  The whole regular file at Path (a link to one followed) when it holds
   --  at most Max_File_Bytes: the open itself refuses a FIFO or a device, so
   --  nothing blocks on one.
   function Read_Bounded (Path : String; Content : out Unbounded_String) return Boolean is
      use type GNAT.OS_Lib.File_Descriptor;
      File      : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Supported : Boolean;
      Buffer    : String (1 .. 32 * 1024);
      Count     : Integer;
      Total     : Natural := 0;
   begin
      Content := Null_Unbounded_String;
      if Path = "" or else (for some C of Path => C = ASCII.NUL) then
         return False;
      end if;
      File := Hostkit.Regular_Files.Open_Read (Path, Follow_Links => True, Supported => Supported);
      if File = GNAT.OS_Lib.Invalid_FD then
         return False;
      end if;

      loop
         Count := GNAT.OS_Lib.Read (File, Buffer'Address, Buffer'Length);
         if Count < 0 or else Count > Max_File_Bytes - Total then
            GNAT.OS_Lib.Close (File);
            Content := Null_Unbounded_String;
            return False;
         end if;
         exit when Count = 0;
         Append (Content, Buffer (1 .. Count));
         Total := Total + Count;
      end loop;
      GNAT.OS_Lib.Close (File);
      return True;
   exception
      when others =>
         if File /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (File);
         end if;
         Content := Null_Unbounded_String;
         return False;
   end Read_Bounded;

   procedure Parse
     (Path            : String;
      Item            : out Desktop_Entry;
      Found           : out Boolean;
      Id              : String := "";
      Locales         : String_Vectors.Vector := String_Vectors.Empty_Vector;
      Current_Desktop : String := Current_Desktops)
   is
      Group_Header : constant String := "[Desktop Entry]";

      In_Group       : Boolean := False;
      Have_Group     : Boolean := False;
      Have_Any_Group : Boolean := False;
      Groups_Seen    : Name_Sets.Set;
      Keys_Seen      : Name_Sets.Set;
      Is_App         : Boolean := False;
      No_Display     : Boolean := False;
      Hidden         : Boolean := False;
      Terminal_Value : Boolean := False;

      Name_Value            : Unbounded_String;
      Localized_Name_Value  : Unbounded_String;
      Exec_Value            : Unbounded_String;
      Icon_Value            : Unbounded_String;
      Localized_Icon_Value  : Unbounded_String;
      Try_Exec_Value        : Unbounded_String;
      Path_Value            : Unbounded_String;
      --  Comment and MimeType are kept raw and decoded at the end: a bad one
      --  is dropped rather than hiding the application.
      Comment_Raw           : Unbounded_String;
      Localized_Comment_Raw : Unbounded_String;
      Mime_Raw              : Unbounded_String;
      Only_Show_In          : String_Vectors.Vector;
      Not_Show_In           : String_Vectors.Vector;

      Have_Type              : Boolean := False;
      Have_Name              : Boolean := False;
      Have_Icon              : Boolean := False;
      Have_Try_Exec          : Boolean := False;
      Have_Only_Show_In      : Boolean := False;
      Have_Not_Show_In       : Boolean := False;
      Have_Localized_Name    : Boolean := False;
      Have_Localized_Icon    : Boolean := False;
      Have_Localized_Comment : Boolean := False;
      Any_Localized_Icon     : Boolean := False;
      Name_Rank              : Natural := Natural'Last;
      Icon_Rank              : Natural := Natural'Last;
      Comment_Rank           : Natural := Natural'Last;
      Entry_Valid            : Boolean := True;
      Line_Count             : Natural := 0;
      Content                : Unbounded_String;

      procedure Assign_Decoded (Raw : String; Target : out Unbounded_String) is
      begin
         if not Decode_Value (Raw, Target) then
            Entry_Valid := False;
         end if;
      end Assign_Decoded;

      procedure Assign_Boolean (Raw : String; Target : out Boolean) is
         Trimmed : constant String := Trim_Blanks (Raw);
      begin
         Target := Trimmed = "true";
         if Trimmed /= "true" and then Trimmed /= "false" then
            Entry_Valid := False;
         end if;
      end Assign_Boolean;

      procedure Assign_List (Raw : String; Target : out String_Vectors.Vector) is
      begin
         if not Decode_List (Raw, Target) then
            Entry_Valid := False;
         end if;
      end Assign_List;

      --  Take Raw for Target when Key is a localized Base_Key better matched
      --  than any before it: decoded when Strict (an invalid value then
      --  invalidates the entry), else kept raw.
      procedure Consider_Localized
        (Key        : String;
         Base_Key   : String;
         Raw        : String;
         Strict     : Boolean;
         Target     : in out Unbounded_String;
         Have_Value : in out Boolean;
         Best_Rank  : in out Natural)
      is
         Rank : constant Natural := Localized_Key_Rank (Key, Base_Key, Locales);
      begin
         if Rank > 0 and then Rank < Best_Rank then
            if Strict then
               Assign_Decoded (Raw, Target);
            else
               Target := To_Unbounded_String (Raw);
            end if;
            Have_Value := True;
            Best_Rank := Rank;
         end if;
      end Consider_Localized;

      function Starts (Key : String; Prefix : String) return Boolean is
        (Key'Length > Prefix'Length and then Key (Key'First .. Key'First + Prefix'Length - 1) = Prefix);

      procedure Process_Key (Key : String; Value : String) is
      begin
         if Key = "Type" then
            Is_App := Value = "Application";
            Have_Type := True;
         elsif Key = "Name" then
            Assign_Decoded (Value, Name_Value);
            Have_Name := True;
         elsif Starts (Key, "Name[") then
            Consider_Localized
              (Key, "Name", Value, True, Localized_Name_Value, Have_Localized_Name, Name_Rank);
         elsif Key = "Exec" then
            Assign_Decoded (Value, Exec_Value);
         elsif Key = "Icon" then
            Assign_Decoded (Value, Icon_Value);
            Have_Icon := True;
         elsif Starts (Key, "Icon[") then
            Any_Localized_Icon := True;
            Consider_Localized
              (Key, "Icon", Value, True, Localized_Icon_Value, Have_Localized_Icon, Icon_Rank);
         elsif Key = "Comment" then
            Comment_Raw := To_Unbounded_String (Value);
         elsif Starts (Key, "Comment[") then
            Consider_Localized
              (Key, "Comment", Value, False, Localized_Comment_Raw, Have_Localized_Comment, Comment_Rank);
         elsif Key = "TryExec" then
            Assign_Decoded (Value, Try_Exec_Value);
            Have_Try_Exec := True;
         elsif Key = "OnlyShowIn" then
            Assign_List (Value, Only_Show_In);
            Have_Only_Show_In := True;
         elsif Key = "NotShowIn" then
            Assign_List (Value, Not_Show_In);
            Have_Not_Show_In := True;
         elsif Key = "NoDisplay" then
            Assign_Boolean (Value, No_Display);
         elsif Key = "Hidden" then
            Assign_Boolean (Value, Hidden);
         elsif Key = "Terminal" then
            Assign_Boolean (Value, Terminal_Value);
         elsif Key = "Path" then
            Assign_Decoded (Value, Path_Value);
         elsif Key = "MimeType" then
            Mime_Raw := To_Unbounded_String (Value);
         end if;
      end Process_Key;

      procedure Process_Line (Line : String) is
         Equals : Natural := 0;
      begin
         if Line'Length = 0 or else Line (Line'First) = '#' then
            null;
         elsif Line_Count >= Max_Lines then
            Entry_Valid := False;
         elsif Line (Line'First) = '[' then
            Line_Count := Line_Count + 1;
            Keys_Seen.Clear;
            In_Group := False;
            --  A group header holds printable ASCII and no other bracket.
            if Line'Length < 3
              or else Line (Line'Last) /= ']'
              or else (for some C of Line (Line'First + 1 .. Line'Last - 1) =>
                         C in '[' | ']' or else Character'Pos (C) not in 32 .. 126)
            then
               Entry_Valid := False;
            else
               declare
                  Group_Name : constant String := Line (Line'First + 1 .. Line'Last - 1);
               begin
                  Have_Any_Group := True;
                  if Groups_Seen.Contains (Group_Name) then
                     Entry_Valid := False;
                  else
                     Groups_Seen.Insert (Group_Name);
                  end if;
                  In_Group := Line = Group_Header;
                  Have_Group := Have_Group or else In_Group;
               end;
            end if;
         else
            Line_Count := Line_Count + 1;
            for Index in Line'Range loop
               if Line (Index) = '=' then
                  Equals := Index;
                  exit;
               end if;
            end loop;

            --  A key belongs to a group and has a name.
            if not Have_Any_Group or else Equals <= Line'First then
               Entry_Valid := False;
            else
               declare
                  Key   : constant String := Trim_Blanks (Line (Line'First .. Equals - 1));
                  Value : constant String := Trim_Blanks (Line (Equals + 1 .. Line'Last));
               begin
                  if Keys_Seen.Contains (Key) then
                     Entry_Valid := False;
                  else
                     Keys_Seen.Insert (Key);
                     if In_Group then
                        Process_Key (Key, Value);
                     end if;
                  end if;
               end;
            end if;
         end if;
      end Process_Line;
   begin
      Item := (others => <>);
      Found := False;
      if not Read_Bounded (Path, Content) then
         return;
      end if;

      declare
         Cursor : Positive := 1;
         Last   : Natural;
         Count  : constant Natural := Length (Content);
      begin
         while Cursor <= Count and then Entry_Valid loop
            Last := Cursor;
            while Last <= Count
              and then Element (Content, Last) /= ASCII.LF
              and then Element (Content, Last) /= ASCII.CR
            loop
               Last := Last + 1;
            end loop;
            if Last - Cursor > Max_Line_Bytes then
               Entry_Valid := False;
            else
               Process_Line (Trim_Blanks (if Last = Cursor then "" else Slice (Content, Cursor, Last - 1)));
            end if;
            --  A line ends at LF, CR or CRLF.
            if Last <= Count then
               declare
                  First_Mark : constant Character := Element (Content, Last);
               begin
                  Last := Last + 1;
                  if First_Mark = ASCII.CR and then Last <= Count and then Element (Content, Last) = ASCII.LF then
                     Last := Last + 1;
                  end if;
               end;
            end if;
            Cursor := Last;
         end loop;
      end;

      if Have_Localized_Name then
         Name_Value := Localized_Name_Value;
      end if;
      if Have_Localized_Icon then
         Icon_Value := Localized_Icon_Value;
      end if;
      if Have_Localized_Comment then
         Comment_Raw := Localized_Comment_Raw;
      end if;
      --  A localized value stands in for its base key, which must be there.
      if Any_Localized_Icon and then not Have_Icon then
         Entry_Valid := False;
      end if;

      if not Entry_Valid
        or else not Have_Group
        or else not Have_Type
        or else not Is_App
        or else not Have_Name
        or else No_Display
        or else Hidden
        or else Name_Value = ""
        or else Exec_Value = ""
        or else not Allows (Only_Show_In, Have_Only_Show_In, Not_Show_In, Have_Not_Show_In, Current_Desktop)
        or else (Have_Try_Exec and then not Hostkit.Process.Is_Runnable (To_String (Try_Exec_Value)))
      then
         return;
      end if;

      declare
         Command      : String_Vectors.Vector;
         Target_Field : Boolean;
         Comment      : Unbounded_String;
         Mime_Types   : String_Vectors.Vector;
      begin
         --  An Exec that does not make a command is nothing to start.
         if not Command_For
           (To_String (Exec_Value), To_String (Name_Value), To_String (Icon_Value), Path,
            String_Vectors.Empty_Vector, Command, Target_Field)
         then
            return;
         end if;
         if not Decode_Value (To_String (Comment_Raw), Comment) then
            Comment := Null_Unbounded_String;
         end if;
         if not Decode_List (To_String (Mime_Raw), Mime_Types) then
            Mime_Types.Clear;
         end if;

         Item :=
           (Id                => To_Unbounded_String (Id),
            Location          => To_Unbounded_String (Path),
            Name              => Name_Value,
            Exec              => Exec_Value,
            Icon              => Icon_Value,
            Comment           => Comment,
            Terminal          => Terminal_Value,
            Working_Directory => Path_Value,
            Mime_Types        => Mime_Types);
         Found := True;
      end;
   exception
      when others =>
         Item := (others => <>);
         Found := False;
   end Parse;

   function Application_Folders return String_Vectors.Vector is
      Result : String_Vectors.Vector;
   begin
      for Base of Hostkit.Fs.Application_Data_Directories loop
         Result.Append (To_Unbounded_String (Hostkit.Fs.Join (To_String (Base), "applications")));
      end loop;
      return Result;
   end Application_Folders;

   --  Read Folder, whose entries' ids begin with Id_Prefix, and its
   --  subfolders into Entries. Claimed holds the ids already read: an entry
   --  claims its id even when it is not listed, so a later folder's entry
   --  under it cannot make that application visible again.
   procedure Scan_Folder
     (Folder          : String;
      Id_Prefix       : String;
      Locales         : String_Vectors.Vector;
      Current_Desktop : String;
      Depth           : Natural;
      Claimed         : in out Name_Sets.Set;
      Scanned         : in out Natural;
      Entries         : in out Entry_Vectors.Vector)
   is
      use type Hostkit.Fs.Entry_Kind;
      Suffix  : constant String := ".desktop";
      Listing : Hostkit.Directory_Listing.Entry_Vectors.Vector;

      procedure Visit (Listed : Hostkit.Directory_Listing.Listed_Entry) is
         Full : constant String := Hostkit.Fs.Join (Folder, Listed.Name);
         --  What the entry is, a link followed; whether it is a link at all.
         Kind   : Hostkit.Fs.Entry_Kind;
         Linked : Boolean;
      begin
         case Listed.Kind is
            when Hostkit.Directory_Listing.Regular_File =>
               Kind := Hostkit.Fs.Ordinary_File_Entry;
               Linked := False;
            when Hostkit.Directory_Listing.Directory =>
               --  Asked all the same: a host may list a junction as a folder.
               Kind := Hostkit.Fs.Directory_Entry;
               Linked := Hostkit.Fs.Is_Link (Full);
            when Hostkit.Directory_Listing.Other =>
               return;
            when Hostkit.Directory_Listing.Symbolic_Link | Hostkit.Directory_Listing.Unknown =>
               Kind := Hostkit.Fs.Kind_Of (Full);
               Linked := Kind = Hostkit.Fs.Directory_Entry and then Hostkit.Fs.Is_Link (Full);
         end case;

         --  Only ordinary files and folders count.
         if Kind not in Hostkit.Fs.Ordinary_File_Entry | Hostkit.Fs.Directory_Entry then
            return;
         end if;
         Scanned := Scanned + 1;

         if Kind = Hostkit.Fs.Directory_Entry then
            --  A linked folder can lead back to an ancestor (or out of the
            --  tree), so it is never descended into.
            if not Linked then
               Scan_Folder
                 (Full, Id_Prefix & Listed.Name & "-", Locales, Current_Desktop, Depth + 1,
                  Claimed, Scanned, Entries);
            end if;
         elsif Listed.Name'Length > Suffix'Length
           and then Listed.Name (Listed.Name'Last - Suffix'Length + 1 .. Listed.Name'Last) = Suffix
         then
            declare
               Id    : constant String := Id_Prefix & Listed.Name;
               Item  : Desktop_Entry;
               Found : Boolean;
            begin
               if not Claimed.Contains (Id) then
                  Claimed.Insert (Id);
                  Parse (Full, Item, Found, Id, Locales, Current_Desktop);
                  if Found then
                     Entries.Append (Item);
                  end if;
               end if;
            end;
         end if;
      exception
         when others =>
            --  One entry that cannot be read is not listed; the rest still are.
            null;
      end Visit;
   begin
      if Depth > Max_Scan_Depth or else not Hostkit.Directory_Listing.List (Folder, Listing) then
         return;
      end if;
      for Listed of Listing loop
         exit when Scanned >= Max_Scan_Entries;
         Visit (Listed);
      end loop;
   exception
      when others =>
         --  A folder that cannot be read holds nothing to list.
         null;
   end Scan_Folder;

   function Scan
     (Folders         : String_Vectors.Vector;
      Locales         : String_Vectors.Vector := String_Vectors.Empty_Vector;
      Current_Desktop : String := Current_Desktops)
      return Entry_Vectors.Vector
   is
      Claimed : Name_Sets.Set;
      Scanned : Natural := 0;
      Entries : Entry_Vectors.Vector;
   begin
      for Folder of Folders loop
         Scan_Folder (To_String (Folder), "", Locales, Current_Desktop, 0, Claimed, Scanned, Entries);
         exit when Scanned >= Max_Scan_Entries;
      end loop;
      return Entries;
   end Scan;

end Hostkit.Desktop_Entries;
