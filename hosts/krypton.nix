################################################################################
# Krypton is a noble gas discovered in 1898, known for its use in high-powered
# lamps and photography.
#
# The krypton host is a Mac Mini 7,1 (Late 2014) with an Intel Core i5-4260U
# (Haswell) CPU.
#
# This host runs Kodi in standalone kiosk mode for TV media playback, using
# NFS-mounted media from the silicon host.  It is plugged directly into the TV.
################################################################################
{
  flake-inputs,
  host-id,
  pkgs,
  system,
  ...
}:
{
  imports = [
    (flake-inputs.nixos-hardware + "/apple/macmini")
    ../nixos-modules/linux-host.nix
    ../nixos-configs/kodi-media-player.nix
    ../nixos-configs/cec-adapter.nix
    ../nixos-configs/timezone-pacific.nix
    (
      { lib, ... }:
      {
        boot.initrd.availableKernelModules = [
          "ahci"
          "xhci_pci"
          "usbhid"
          "usb_storage"
          "sd_mod"
        ];
        boot.kernelModules = [ "kvm-intel" ];
        # This hostId is needed by some filesystems like ZFS.
        # Generated using: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
        # You'll want to regenerate this on the actual hardware.
        networking.hostId = "4ead70ae";
        nixpkgs.hostPlatform = system;
      }
    )
    ({
      imports = [
        flake-inputs.disko.nixosModules.default
      ];
      # Very relevant to disko configuration, since not having these settings
      # will cause the grub installation to fail.
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.grub = {
        device = "nodev";
        efiSupport = true;
      };
      disko.devices = {
        disk = {
          os = {
            type = "disk";
            device = "/dev/disk/by-id/ata-APPLE_HDD_HTS545050A7E362_TNS5193T2X33VH";
            content = {
              type = "gpt";
              partitions = {
                boot = {
                  size = "512M";
                  # EFI System Partition.
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                  };
                };
                lvm = {
                  size = "100%";
                  content = {
                    type = "lvm_pv";
                    vg = "vg0";
                  };
                };
              };
            };
          };
        };
        lvm_vg.vg0 = {
          type = "lvm_vg";
          lvs = {
            root = {
              size = "100%FREE";
              content = {
                type = "filesystem";
                format = "btrfs";
                mountpoint = "/";
              };
            };
          };
        };
      };
      # Works around the issue where the installer warns that the boot seed is
      # leaked.  You may still get the warning, but this should actually address
      # the security issue. See
      # https://github.com/NixOS/nixpkgs/issues/279362#issuecomment-1913506090
      # for more discussion.
      fileSystems."/boot".options = [
        "umask=0077"
        "defaults"
      ];
    })
  ];

  # CEC adapter is on HDMI port 3 of the Philips TV.
  services.kodi-standalone.peripheralSettings = {
    "usb_2548_1002_CEC_Adapter".cec_hdmi_port = "3";
    "cec_CEC_Adapter".cec_hdmi_port = "3";
  };

  ##
  # Pin the HDMI connector so the TV cannot drag Kodi's audio engine down with
  # it.
  #
  # The Philips TV drops the HDMI link periodically — roughly hourly while
  # idle, and again whenever it is powered off or switched to another input.
  # Each drop makes xrandr report HDMI-2 disconnected, which fails
  # CXRandR::Query, which fires Kodi's OnLostDisplay and tears the audio sink
  # down.  After about two days of that churn CActiveAE stops acknowledging
  # the teardown within its five second deadline
  # ("ActiveAE::OnLostDisplay - timed out") and eventually deadlocks outright:
  # video keeps playing, MakeStream fails, and there is no audio until Kodi is
  # restarted.  See docs/kodi-audio-engine-wedge.org.
  #
  # Two params, and both are needed:
  #
  # - video=HDMI-A-2:e sets DRM_FORCE_ON, so drm_helper_probe_detect() reports
  #   the connector connected unconditionally.
  # - drm.edid_firmware supplies a captured copy of the TV's EDID.  Without
  #   it, forcing the connector on is not enough and arguably worse: when the
  #   TV is off the EDID read fails, the probe finds no modes, and the helper
  #   falls back to drm_add_modes_noedid()'s ≤1024x768 list.  Kodi would then
  #   see the mode list churn instead of a disconnect, which is no better than
  #   the flap we are trying to kill.
  #
  # The blob was read straight off this host's connector
  # (/sys/class/drm/card1-HDMI-A-2/edid) while the TV was on, so it is the
  # TV's own EDID rather than a synthesised one.
  boot.kernelParams = [
    "video=HDMI-A-2:e"
    "drm.edid_firmware=HDMI-A-2:edid/krypton-philips-ftv.bin"
  ];
  # i915 is loaded from the initrd on this host, so its first probe may run
  # before this firmware is reachable and fall back to reading the real EDID
  # off the wire.  That is harmless — request_firmware is retried on later
  # probes, and X does not start until stage 2.  Verify after a reboot with:
  #   journalctl --boot | grep --ignore-case "edid"
  hardware.firmware = [
    (pkgs.runCommand "krypton-tv-edid" { } ''
      mkdir --parents "$out/lib/firmware/edid"
      cp ${../hardware/edid/krypton-philips-ftv.bin} \
        "$out/lib/firmware/edid/krypton-philips-ftv.bin"
    '')
  ];

  # Additional packages useful for a media server.
  # kodi-media-player.nix registers "kodi-krypton" generically.  This
  # host additionally gets a location-specific alias for the living room.
  networking.dnsAliases = [ "kodi-living-room" ];
  environment.systemPackages = [
    # Let's be able to work with media files if needed.
    pkgs.ffmpeg
    # Useful for debugging media issues.
    pkgs.mediainfo
  ];
}
