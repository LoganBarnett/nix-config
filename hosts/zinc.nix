################################################################################
# zinc is no longer in use.
################################################################################
{
  disko-proper,
  flake-inputs,
  host-id,
  nixpkgs,
  system,
}:
{
  imports = [
    ../nixos-modules/linux-host.nix
    (
      { pkgs, ... }:
      {
        # networking.hostId is needed by the filesystem stuffs.
        # An arbitrary ID needed for zfs so a pool isn't accidentally imported on
        # a wrong machine (I'm not even sure what that means).  See
        # https://search.nixos.org/options?channel=24.05&show=networking.hostId&from=0&size=50&sort=relevance&type=packages&query=networking.hostId
        # for docs.
        # Get from an existing machine using:
        # head -c 8 /etc/machine-id
        # Generate for a new machine using:
        # head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
        networking.hostId = "f8732ff6";
        nixpkgs.hostPlatform = system;
      }
    )
  ];
}
