################################################################################
# Replace nixpkgs's opencode (pinned at 25.11's older 1.0.105) with our vendored
# copy of master's derivation (../derivations/opencode/default.nix), and drive
# its version + source hash + node_modules hash from static.nix so the version
# can be bumped via scripts/opencode-update without re-touching nixpkgs.
#
# This is a from-source build (the preferred mode — see "Rapid Package Updates"
# in README.org).  The override works because the vendored derivation consumes
# node_modules through the `finalAttrs` fixpoint (`cp -R ${finalAttrs.node_modules}`),
# so overrideAttrs on `node_modules` actually reaches the build — unlike 25.11's
# `let`-bound copy.  When static.nix holds the same values the vendored file
# pins, this override is a no-op and builds identically to upstream.
#
# opencode 1.17.x's build embeds its web UI via a Bun virtual-module entrypoint
# that needs a newer Bun than 25.11 ships (1.3.2).  Rather than bump the global
# pkgs.bun (which everything else depends on), we pin a Bun *scoped to opencode*
# (static.nix.opencode-bun / scripts/opencode-bun-update) and hand it to the
# derivation via callPackage.  Bun ships only as prebuilt release zips, so this
# scoped Bun is itself a binary download — see the source-vs-binary policy in
# README.org; here from-source opencode unavoidably rests on a prebuilt Bun.
################################################################################
{ system, ... }:
final: prev:
let
  statics = (import ../static.nix).opencode;
  bunStatics = (import ../static.nix).opencode-bun;

  # Bun's release zips have platform-specific names (note the x86_64-darwin
  # "baseline" variant), matching nixpkgs's own bun derivation.
  bunFileMap = {
    "aarch64-darwin" = "bun-darwin-aarch64.zip";
    "x86_64-darwin" = "bun-darwin-x64-baseline.zip";
    "aarch64-linux" = "bun-linux-aarch64.zip";
    "x86_64-linux" = "bun-linux-x64.zip";
  };
  bunFile =
    bunFileMap.${system} or (throw "opencode-bun: unsupported system ${system}");

  # Scoped Bun: override only version + src on the global bun derivation, so we
  # inherit its darwin code-signing / linux autoPatchelf handling unchanged.
  opencodeBun = prev.bun.overrideAttrs (_: {
    version = bunStatics.version;
    src = final.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${bunStatics.version}/${bunFile}";
      hash = bunStatics.${system}.hash;
    };
  });

  base = final.callPackage ../derivations/opencode/default.nix {
    bun = opencodeBun;
  };
in
{
  opencode = base.overrideAttrs (
    finalAttrs: prevAttrs: {
      version = statics.version;

      src = final.fetchFromGitHub {
        owner = "anomalyco";
        repo = "opencode";
        tag = "v${statics.version}";
        hash = statics.srcHash;
      };

      # node_modules is a fixed-output derivation whose dependency tree (and thus
      # hash) changes on most releases.  Rebuild it from the overridden src and
      # pin its hash separately; the bun install + bundle steps (and the scoped
      # Bun) carry over from the vendored derivation unchanged.
      node_modules = prevAttrs.node_modules.overrideAttrs (_: {
        inherit (finalAttrs) version src;
        outputHash = statics.nodeModulesHash;
      });
    }
  );
}
