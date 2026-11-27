################################################################################
# This is some boilerplate for Raspberry Pi hosts.
#
# We can make some assumptions about building Raspberry Pis since we can create
# the entire bootable image from scratch, and we don't need to deal with UEFI
# nonsense.
################################################################################
{
  flake-inputs,
  host-id,
  lib,
  ...
}:
{
  imports = [
    flake-inputs.nixos-raspberrypi.nixosModules.sd-image
    flake-inputs.nixos-raspberrypi.lib.inject-overlays
    ./raspberry-pi-firmware-host-key.nix
  ];
  # /boot/firmware must be kept small intentionally.
  boot.loader.generic-extlinux-compatible.configurationLimit = 8;
  # boot.loader.grub.enable = false;
  # boot.loader.generic-extlinux-compatible.enable = true;
  # Removed in nixpkgs, but it now comes from nixos-raspberrypi.
  # Unfortunately the options are presently undocumented, so see
  # https://github.com/nvmd/nixos-raspberrypi/blob/f8900910f63477626010938da8d849ba2cc3d011/modules/system/boot/loader/raspberrypi/default.nix
  # for the options.
  boot.loader.raspberry-pi = {
    enable = true;
    # This is set differently between 4 and 5.
    # bootloader = "kernel";
  };
  # This set of labels might not work for fresh images, but it's what the old
  # raspberry-pi-nix `sdImage` output would lay down.  We might need to make
  # this configurable if I ever start emitting new RPi5 images again.  Perhaps
  # move this to its own module at that juncture.
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
    };
    "/boot/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
    };
  };
  # No disk swap.  These boot from SD cards or USB sticks with abysmal write
  # speeds, and a swap device would wear them out.  zram below is the
  # substitute.
  swapDevices = lib.mkForce [ ];
  # Compressed swap in RAM.  It gives the kernel somewhere to put idle anonymous
  # pages, so a host under pressure degrades into swapping and then an OOM kill
  # instead of the swapless livelock that took bromine down on 2026-11-24.  It
  # writes nothing to the card.
  zramSwap.enable = true;
  # The Pi firmware prepends cgroup_disable=memory to the kernel command line.
  # Without the memory controller a unit's MemoryMax is accepted and ignored.
  # cgroup_memory=1 stops the firmware adding the disable, and
  # cgroup_enable=memory wins over it when it is added anyway.
  boot.kernelParams = [
    "cgroup_enable=memory"
    "cgroup_memory=1"
  ];
  # Reboot through the SoC watchdog when PID 1 stops responding.  A memory
  # livelock starves PID 1 along with everything else.  The BCM2835 watchdog
  # counts at most 15 seconds.  The kernel rejects a longer timeout with EINVAL
  # and systemd then runs with no watchdog at all, so this value is the hardware
  # maximum rather than a choice.
  systemd.settings.Manager.RuntimeWatchdogSec = "15s";
  # By default, Raspberry Pis are disallowed from doing their own builds.  We
  # have a single Raspberry Pi build host - a host with sufficient memory and no
  # other services on it.  This prevents any local builds from occurring.
  nix.settings.max-jobs = 0;
}
