################################################################################
# Generator for a Nix binary cache signing keypair, in the format that
# `nix key generate-secret` emits ("<name>:<base64 secret||public>").
#
# The public half ("<name>:<base64 public>") is written to a .pub sidecar next
# to the .age file and added to git, so consumers can read it at evaluation
# time for trusted-public-keys.  Requires `settings.keyName` on the secret.
################################################################################
{ lib, ... }:
{
  age.generators.nix-cache-signing-key =
    {
      file,
      gitAdd,
      name,
      pkgs,
      secret,
      ...
    }:
    let
      keyName =
        secret.settings.keyName
          or (throw "age.secrets.${name}: generator nix-cache-signing-key requires settings.keyName");
      nix = "${pkgs.nix}/bin/nix --extra-experimental-features nix-command";
      pubFile = lib.escapeShellArg (lib.removeSuffix ".age" file + ".pub");
    in
    ''
      set -euo pipefail
      ${pkgs.coreutils}/bin/mkdir --parents "$(${pkgs.coreutils}/bin/dirname ${pubFile})"
      secret="$(${nix} key generate-secret --key-name ${lib.escapeShellArg keyName})"
      printf '%s' "$secret" \
        | ${nix} key convert-secret-to-public \
        | ${pkgs.coreutils}/bin/tr --delete '\n' > ${pubFile}
      ${gitAdd} ${pubFile}
      printf '%s' "$secret"
    '';
}
