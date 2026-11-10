with Ada.Strings.UTF_Encoding.Conversions;

package body Hostkit.Windows_Paths is

   function Is_Separator (Item : Character) return Boolean is (Item in '\' | '/');

   function Long_Path_Form (Path : String) return String is
      Text : String := Path;

      function Has_Dot_Component return Boolean is
         Start : Positive := Text'First;
      begin
         for Index in Text'First .. Text'Last + 1 loop
            if Index > Text'Last or else Text (Index) = '\' then
               declare
                  Component : constant String := Text (Start .. Index - 1);
               begin
                  if Component = "." or else Component = ".." then
                     return True;
                  end if;
               end;
               Start := Index + 1;
            end if;
         end loop;
         return False;
      end Has_Dot_Component;
   begin
      if Path'Length < Long_Path_Threshold then
         return Path;
      end if;
      for Item of Text loop
         if Item = '/' then
            Item := '\';
         end if;
      end loop;
      if Text (Text'First .. Text'First + 3) in "\\?\" | "\\.\" then
         return Path;
      elsif Has_Dot_Component then
         return Path;
      elsif Text (Text'First) in 'A' .. 'Z' | 'a' .. 'z'
        and then Text (Text'First + 1) = ':'
        and then Is_Separator (Text (Text'First + 2))
      then
         return "\\?\" & Text;
      elsif Text (Text'First .. Text'First + 1) = "\\" and then not Is_Separator (Text (Text'First + 2)) then
         return "\\?\UNC\" & Text (Text'First + 2 .. Text'Last);
      else
         return Path;
      end if;
   end Long_Path_Form;

   function Native (Path : String) return Wide_String is
     (Ada.Strings.UTF_Encoding.Conversions.Convert (Long_Path_Form (Path)) & Wide_Character'Val (0));

end Hostkit.Windows_Paths;
