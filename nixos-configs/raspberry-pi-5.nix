##
# Provides settings needed to build a Raspberry Pi 5 bootable image.
##
{ flake-inputs, ... }:
{
  imports = [
    ./raspberry-pi-host.nix
    # flake-inputs.nixos-hardware.nixosModules.raspberry-pi-5
    flake-inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.base
    # page-size-16k is left out because it pushes every Rust package off
    # cache.nixos.org.  The module rebuilds jemalloc for 16 KiB pages.  Since
    # rustc links jemalloc, rustc and everything it compiles get new hashes.
    # Stock aarch64 jemalloc targets 64 KiB pages.  That already works on the
    # 16 KiB Pi 5 kernel and only wastes some memory.
    # flake-inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
  ];
  boot.loader.raspberry-pi.bootloader = "kernel";
  # Undocumented from nixos-raspberrypi.  See
  # https://github.com/nvmd/nixos-raspberrypi/blob/f8900910f63477626010938da8d849ba2cc3d011/modules/configtxt-config.nix
  # for now this gets laid down.
  boot.kernelParams = [
    "usbcore.autosuspend=-1"
  ];
  hardware.raspberry-pi = {
    config.all.options = {
      # The USB connection can hypothetically suspend and cause prints to fail.
      # By default this is 2, but setting it to -1 disables it.
      "usbcore.autosuspend" = {
        enable = true;
        value = "-1";
      };
    };
  };
}
