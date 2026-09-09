################################################################################
# Replace nixpkgs's claude-code (25.11's Node.js-bundle build of an old release)
# with our vendored copy of master's derivation
# (../derivations/claude-code/default.nix), which installs the native binary
# Claude Code now ships as.  Master reads the version and per-platform
# checksums from its `manifest` argument; that manifest is built here from
# static.nix so the version can be bumped via scripts/claude-code-update
# without re-touching nixpkgs.  This is the only deviation from upstream: the
# derivation file itself is unaltered.
################################################################################
{ system, ... }:
final: prev:
let
  statics = (import ../static.nix).claude-code;
  inherit (final.stdenv.hostPlatform) node;
in
{
  claude-code = final.callPackage ../derivations/claude-code/default.nix {
    # The shape of upstream's manifest.zst.json, reduced to the platform being
    # built.  Upstream carries hex checksums; fetchurl accepts the SRI form
    # static.nix uses just as well.
    manifest = {
      inherit (statics) version;
      platforms."${node.platform}-${node.arch}" = {
        binary = "claude.zst";
        checksum = statics.${system}.hash;
      };
    };
  };
}
