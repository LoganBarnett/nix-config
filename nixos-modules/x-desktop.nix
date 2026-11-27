################################################################################
# Make this host an X server based desktop.
################################################################################
{
  config,
  flake-inputs,
  lib,
  pkgs,
  ...
}:
{
  # Hint to Electron apps to use Wayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.systemPackages = [
    # Allow controlling displays from the command line.
    pkgs.ddcutil
    # Full screen, hardware accelerated screenshots.  Works for Wayland.
    pkgs.grim
    pkgs.i3status
    pkgs.i3blocks
    pkgs.i3lock-color
    # Full screen, hardware accelerated screenshots.  Works for X11.
    pkgs.scrot
    pkgs.wmctrl
    pkgs.wmname
    pkgs.wezterm
    # Query the current terminal's ANSI 16-color palette via OSC 4.
    (pkgs.callPackage ../derivations/terminal-color-query.nix { })
  ];
  # Required for touchpad support, and some managers such as hyprland require
  # it.
  services.libinput = {
    enable = true;
  };
  # Strangely, this is required to enable Gnome.  I haven't been able to find
  # any tickets on this and the only documentation I can find about Gnome
  # (https://nixos.wiki/wiki/GNOME) carries no mention of it.
  allowUnfreePackagePredicates = [
    (
      pkg:
      builtins.elem (lib.getName pkg) [
        "vpnc"
      ]
    )
  ];
  services.desktopManager = {
    gnome.enable = true;
  };
  services.displayManager.gdm = {
    enable = true;
    wayland = true;
  };
  services.xserver = {
    enable = true;
    displayManager.startx.enable = true;
    windowManager = {
      qtile.enable = true;
      bspwm.enable = true;
      i3.enable = true;
      dwm.enable = true;
    };
    # Keyboard settings.
    xkb = {
      layout = "us";
      # Caps Lock acts as Control.  This matches the macOS remap in darwin.nix.
      options = "caps:ctrl_modifier";
      variant = "";
    };
  };
  # The virtual consoles follow the xkb layout and options above.
  console.useXkbConfig = true;
  # GNOME reads keyboard options from dconf rather than from the xkb settings
  # above.  The lock keeps a user's own dconf value from overriding them.
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/input-sources".xkb-options =
        lib.splitString ","
          config.services.xserver.xkb.options;
      locks = [ "/org/gnome/desktop/input-sources/xkb-options" ];
    }
  ];
  # ydotool injects input at the uinput layer.  That works over SSH under both
  # X11 and Wayland.  Its main job here is clearing a stuck Caps Lock.  Every
  # normal user already belongs to the users group.  No per-user group
  # membership is needed.
  programs.ydotool = {
    enable = true;
    group = "users";
  };
  # TODO: Move this to separate module.
  # Enable sound with pipewire.
  # Actually this is broken per: https://github.com/NixOS/nixpkgs/issues/319809
  # sound.enable = true;
  services.pulseaudio = {
    enable = false;
    support32Bit = false;
  };
  # Enable RealtimeKit, which allows real time scheduling priority for user
  # processes.  This allows the PulseAudio server to do its work in real time.
  security.rtkit.enable = true;
  # A security policy manager that should interact somehow with rtkit...
  # TODO: This doesn't belong here, I think.  I'm not even sure what
  # setting this accomplished.  It was part of a desperate debugging
  # effort that is now over.
  security.polkit.enable = true;
  # TODO: This doesn't belong here, I think.  I'm not even sure what
  # setting this accomplished.  It was part of a desperate debugging
  # effort that is now over.
  hardware.nvidia.forceFullCompositionPipeline = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    # Use the example session manager (no others are packaged yet so this is
    # enabled by default, no need to redefine it in your config for now).
    # media-session.enable = true;
  };
}
