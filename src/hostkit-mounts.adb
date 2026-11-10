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

   function Lower (Text : String) return String is
      Result : String := Text;
   begin
      for C of Result loop
         if C in 'A' .. 'Z' then
            C := Character'Val (Character'Pos (C) + 32);
         end if;
      end loop;
      return Result;
   end Lower;

   function Is_Pseudo (Filesystem_Type : String) return Boolean is
     (Lower (Filesystem_Type) in
        "" | "autofs" | "binfmt_misc" | "bpf" | "cgroup" | "cgroup2" | "configfs" | "debugfs" | "devpts"
        | "devtmpfs" | "efivarfs" | "fusectl" | "hugetlbfs" | "mqueue" | "nsfs" | "overlay" | "proc"
        | "pstore" | "ramfs" | "rpc_pipefs" | "securityfs" | "squashfs" | "sysfs" | "tmpfs" | "tracefs");

   function Is_Network (Filesystem_Type : String) return Boolean is
     (Lower (Filesystem_Type) in
        "9p" | "afpfs" | "cifs" | "davfs" | "fuse.gvfsd-fuse" | "fuse.sshfs" | "ncpfs" | "nfs" | "nfs4"
        | "smb3" | "sshfs");

   function Table return Mount_Vectors.Vector is separate;

   function Volume_Places return Volume_Place_List is separate;

   function Removable (Source : String; Known : out Boolean) return Boolean is separate;

end Hostkit.Mounts;
