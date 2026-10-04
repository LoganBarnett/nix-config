################################################################################
# Make this host substitute from the LAN caches on silicon.
#
# Nix orders substituters by the priority each one advertises, not by this
# list: attic answers first with locally built paths, ncps fronts
# cache.nixos.org, and cache.nixos.org itself stays as the fallback for a host
# that is off the LAN.  The extra-* settings keep that default in place; a bare
# `substituters` would replace it.
################################################################################
{ facts, lib, ... }:
let
  inherit (facts.network) binaryCache domain;
  pubFile = ../secrets/generated/attic-signing-key.pub;
  atticPublicKey =
    assert lib.assertMsg (builtins.pathExists pubFile) ''
      ${toString pubFile} is missing or not tracked by git.  Run
      `agenix rekey generate --rekey --add-to-git` and commit the .pub sidecar
      first.
    '';
    lib.trim (builtins.readFile pubFile);
in
{
  nix.settings = {
    extra-substituters = [
      "https://${binaryCache.atticAlias}.${domain}/${binaryCache.atticCache}"
      "https://${binaryCache.ncpsAlias}.${domain}"
    ];
    extra-trusted-public-keys = [ atticPublicKey ];
    # Off the LAN the .proton caches are unreachable; fail fast so Nix moves on
    # to cache.nixos.org instead of hanging on every path.
    connect-timeout = 5;
  };
}
