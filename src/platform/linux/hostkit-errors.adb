package body Hostkit.Errors is

   --  asm-generic/errno-base.h and asm-generic/errno.h.
   function Code_Of (Item : Cause) return Integer is
     (case Item is
         when No_Space             => 28,
         when Quota_Exceeded       => 122,
         when Permission_Denied    => 13,
         when Not_Permitted        => 1,
         when Read_Only_Filesystem => 30,
         when Busy                 => 16,
         when Text_Busy            => 26,
         when Name_Too_Long        => 36);

end Hostkit.Errors;
