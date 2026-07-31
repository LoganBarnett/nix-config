################################################################################
# Ruckus ICX 7150-48ZP switch — silicon-side pieces.
#
# The switch itself is configured imperatively over its console or SSH until a
# FastIron nix-hapi provider exists.  This module owns what silicon needs to
# hold up its end: the generated admin password and the SSH client tooling to
# use it.
#
# FastIron's SSH stack (RomSShell) is old.  Modern OpenSSH clients need legacy
# options to connect:
#
#   sshpass -f /run/agenix/ruckus-48zp-admin-password \
#     ssh -o HostKeyAlgorithms=+ssh-rsa \
#         -o KexAlgorithms=+diffie-hellman-group14-sha1 \
#         super@10.99.0.2
################################################################################
{ pkgs, ... }:
{
  # FastIron local-user passwords cap at 48 characters and the CLI cannot
  # accept spaces, so the standard long-passphrase generator (10
  # space-delimited words) does not fit.  Five hyphen-delimited words of at
  # most 7 characters tops out at 39 characters.
  age.generators.cli-safe-passphrase =
    { pkgs, ... }:
    "${pkgs.xkcdpass}/bin/xkcdpass --numwords=5 --min=4 --max=7 --delimiter=-";

  age.secrets.ruckus-48zp-admin-password = {
    generator.script = "cli-safe-passphrase";
  };

  # For imperative management of the switch until the nix-hapi provider
  # exists.
  environment.systemPackages = [ pkgs.sshpass ];
}
