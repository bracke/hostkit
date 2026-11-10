package body Hostkit.Errors is

   --  sys/errno.h.
   function Code_Of (Item : Cause) return Integer is
     (case Item is
         when No_Space             => 28,
         when Quota_Exceeded       => 69,
         when Permission_Denied    => 13,
         when Not_Permitted        => 1,
         when Read_Only_Filesystem => 30,
         when Busy                 => 16,
         when Text_Busy            => 26,
         when Name_Too_Long        => 63);

end Hostkit.Errors;
