################################################################################
# Install a pre-generated SSH host key from the FIRMWARE partition.
#
# The key is installed before agenix runs, so a freshly imaged host decrypts
# all of its secrets on its very first boot.  Without this, first boot
# generates a brand new host key which matches nothing in secrets/, and no
# secret can be decrypted until the key is scanned and everything is rekeyed.
# See the Raspberry Pi section of README.org for the full flow.
################################################################################
{ pkgs, ... }:
let
  firmware-host-key-install =
    pkgs.callPackage ../derivations/firmware-host-key-install/default.nix
      { };
in
{
  system.activationScripts.firmwareHostKeyInstall = {
    deps = [ "specialfs" ];
    text = "${firmware-host-key-install}/bin/firmware-host-key-install";
  };
  # agenix decrypts secrets during its agenixInstall activation script using
  # age.identityPaths, which defaults to the openssh host key paths.  Run our
  # install first so the very first activation already has the real identity.
  # Note that agenix only defines its activation scripts when systemd.sysusers
  # is disabled (the default everywhere in this repository); if sysusers is
  # ever enabled, this deps-only definition will fail evaluation and need
  # revisiting.
  system.activationScripts.agenixInstall.deps = [ "firmwareHostKeyInstall" ];
}
