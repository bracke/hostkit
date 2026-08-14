package body Hostkit.Terminal_Control.Differences is

   ----------------------
   -- First_Difference --
   ----------------------

   function First_Difference
     (Left   : Mode;
      Right  : Mode;
      Was    : out Interfaces.Unsigned_8;
      Became : out Interfaces.Unsigned_8) return Natural
   is
      use type Interfaces.Unsigned_8;
   begin
      Was    := 0;
      Became := 0;

      for Position in Left.Bytes'Range loop
         if Left.Bytes (Position) /= Right.Bytes (Position) then
            Was    := Left.Bytes (Position);
            Became := Right.Bytes (Position);
            return Position;
         end if;
      end loop;

      return 0;
   end First_Difference;

end Hostkit.Terminal_Control.Differences;
