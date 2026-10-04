################################################################################
# The calcium host.  It's all theoretical config and doesn't run on any hardware
# currently.
#
# It can host a lot of disks, so it could back up silicon while silicon gets
# rebuilt as a NixOS machine.
#
# History: The machine is a donation from Tom Sears.
#
# Trivia: Calcium is highly reactive metal and rarely found in elemental form.
# There are many nutritional benefits to calcium (bone strength being a common
# one, but they are also part of neurotransmitters).  Calcium is found in many
# things, including limestone.
################################################################################
{ ... }:
let
  system = "x86_64-linux";
in
{
  imports = [
    (
      { lib, ... }:
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
        networking.hostId = "b4a6639e";
        nixpkgs.hostPlatform = system;

        documentation.enable = lib.mkForce false;
      }
    )
    ../nixos-modules/linux-host.nix
  ];
}
