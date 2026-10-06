################################################################################
# gpclient + gpauth overlay using fully-vendored derivations from
# ../derivations/gpauth and ../derivations/gpclient.  Both pull version, src
# hash, and cargoHash from static.nix so the rapid-updater
# (scripts/gpclient-update) can bump them without touching this file or the
# derivations.
#
# Why fully vendored instead of overrideAttrs: the vendored derivations were
# copied from nixpkgs-unstable when the pinned nixpkgs still carried the 2.4.x
# packaging shape.  The pinned nixpkgs now ships 2.6.4 with the 2.5.x shape.
# The vendoring remains so the rapid updater can pin a version independently
# of nixpkgs.
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
