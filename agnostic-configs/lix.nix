################################################################################
# Use Lix as this host's Nix implementation.
#
# Lix comes straight from nixpkgs here rather than through
# lix-project/nixos-module.  One would reach for that module, but its overlay
# cannot work against nixpkgs 26.05 on two counts: it resolves
# `lixVersions.lix_<major>_<minor>`, which 26.05 moved to `lixPackageSets`, and
# it overrides `nix-eval-jobs` with a `nix` argument that 26.05 replaced with
# `nixComponents`.  No module release targets the Lix 2.94 that 26.05 ships, so
# no pairing of versions avoids both.  See lix-project/nixos-module#108 and
# #107.
#
# Only `nix.package` is set.  Pulling the Lix-built ecosystem packages into the
# top-level scope through an overlay is the infinite recursion that
# lix-project/lix#980 tracks, so take one from
# `pkgs.lixPackageSets.stable.<pkg>` at its use site instead.
################################################################################
{ pkgs, ... }:
{
  nix.package = pkgs.lixPackageSets.stable.lix;
}
