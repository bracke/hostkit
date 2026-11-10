package body Hostkit.Path_Text is

   function Share_Root_Last (Path : String) return Natural is
      function Sep (C : Character) return Boolean is (Is_Separator_In (Path, C));
      Server_Start : Natural;
      Share_Start  : Natural;
   begin
      if Path'Length < 5 or else not Sep (Path (Path'First)) or else not Sep (Path (Path'First + 1)) then
         return 0;
      end if;
      Server_Start := Path'First + 2;
      while Server_Start <= Path'Last and then Sep (Path (Server_Start)) loop
         Server_Start := Server_Start + 1;
      end loop;
      for Index in Server_Start .. Path'Last loop
         if Sep (Path (Index)) then
            Share_Start := Index + 1;
            while Share_Start <= Path'Last and then Sep (Path (Share_Start)) loop
               Share_Start := Share_Start + 1;
            end loop;
            for Share_End in Share_Start .. Path'Last loop
               if Sep (Path (Share_End)) then
                  return Share_End;
               end if;
            end loop;
            return Path'Last;
         end if;
      end loop;
      return 0;
   end Share_Root_Last;

end Hostkit.Path_Text;
