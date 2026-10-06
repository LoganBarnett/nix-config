################################################################################
# Replace nixpkgs's claude-code with our vendored copy of master's derivation
# in ../derivations/claude-code/default.nix.
#
# The pinned nixpkgs ships the native binary too, but it trails releases and
# reads the older uncompressed manifest.  Master reads the version and
# per-platform checksums of the zstd distribution from its `manifest`
# argument.  That manifest is built here from static.nix, so the version can
# be bumped via scripts/claude-code-update without touching nixpkgs.  This is
# the only deviation from upstream.  The derivation file itself is unaltered.
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
