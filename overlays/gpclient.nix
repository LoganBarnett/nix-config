################################################################################
# gpclient + gpauth overlay using fully-vendored derivations from
# ../derivations/gpauth and ../derivations/gpclient.  Both pull version, src
# hash, and cargoHash from static.nix so the rapid-updater
# (scripts/gpclient-update) can bump them without touching this file or the
# derivations.
#
# Why fully vendored instead of overrideAttrs: nixpkgs's pinned gpauth is
# still on 2.4.6, which uses an entirely different packaging shape
# (externally-linked openconnect, different hardcoded paths to patch).  The
# 2.5.x line statically links OpenConnect from a git submodule and the build
# pipeline diverges enough that overrideAttrs cannot bridge the gap cleanly.
# We pick up the 2.5.x packaging from nixpkgs-unstable so we can sit on top
# of the upstream auth/callback fixes.
################################################################################
final: prev:
let
  statics = (import ../static.nix).globalprotect-openconnect;
  inherit (statics) version hash cargoHash;
in
{
  gpauth = final.callPackage ../derivations/gpauth/default.nix {
    inherit version hash cargoHash;
  };
  gpclient = final.callPackage ../derivations/gpclient/default.nix { };
}
