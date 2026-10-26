package body Hostkit.Mounts is

   use type Ada.Strings.Unbounded.Unbounded_String;

   function Find (Mounts : Mount_Vectors.Vector; Mount_Point : String; Found : out Boolean) return Mount is
   begin
      for Item of Mounts loop
         if Item.Mount_Point = Mount_Point then
            Found := True;
            return Item;
         end if;
      end loop;
      Found := False;
      return (others => <>);
   end Find;

   function Table return Mount_Vectors.Vector is separate;

   function Removable (Source : String; Known : out Boolean) return Boolean is separate;

end Hostkit.Mounts;
