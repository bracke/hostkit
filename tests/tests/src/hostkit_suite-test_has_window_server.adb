separate (Hostkit_Suite)
procedure Test_Has_Window_Server
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package Env renames Ada.Environment_Variables;
   Had_Display : constant Boolean := Env.Exists ("DISPLAY");
   Display     : constant String := (if Had_Display then Env.Value ("DISPLAY") else "");
   Had_Wayland : constant Boolean := Env.Exists ("WAYLAND_DISPLAY");
   Wayland     : constant String := (if Had_Wayland then Env.Value ("WAYLAND_DISPLAY") else "");

   procedure Restore is
   begin
      if Had_Display then
         Env.Set ("DISPLAY", Display);
      else
         Env.Clear ("DISPLAY");
      end if;
      if Had_Wayland then
         Env.Set ("WAYLAND_DISPLAY", Wayland);
      else
         Env.Clear ("WAYLAND_DISPLAY");
      end if;
   end Restore;
begin
   if Hostkit.Host.Current /= Hostkit.Host.Linux then
      Assert (Hostkit.Host.Has_Window_Server, "macOS and Windows have one for every desktop session");
      return;
   end if;
   Env.Clear ("DISPLAY");
   Env.Clear ("WAYLAND_DISPLAY");
   Assert (not Hostkit.Host.Has_Window_Server, "no DISPLAY and no WAYLAND_DISPLAY: no window server");
   Env.Set ("DISPLAY", "");
   Assert (not Hostkit.Host.Has_Window_Server, "an empty DISPLAY names none");
   Env.Set ("DISPLAY", ":0");
   Assert (Hostkit.Host.Has_Window_Server, "an X display is one");
   Env.Clear ("DISPLAY");
   Env.Set ("WAYLAND_DISPLAY", "wayland-0");
   Assert (Hostkit.Host.Has_Window_Server, "so is a Wayland one");
   Restore;
exception
   when others =>
      Restore;
      raise;
end Test_Has_Window_Server;
