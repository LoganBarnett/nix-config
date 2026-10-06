################################################################################
# Replace nixpkgs's opencode with our vendored copy of master's derivation in
# ../derivations/opencode/default.nix.  Its version, source hash and
# node_modules hash come from static.nix, so the version can be bumped via
# scripts/opencode-update without touching nixpkgs.
#
# The pinned nixpkgs ships 1.15.10 and trails the releases the Emacs client
# tracks.  This is a from-source build, the preferred mode.  See "Rapid Package
# Updates" in README.org.  The override works because the derivation consumes
# node_modules through the `finalAttrs` fixpoint, so overrideAttrs on
# `node_modules` actually reaches the build.  When static.nix holds the same
# values the vendored file pins, this override is a no-op and builds
# identically to upstream.
#
# A Bun scoped to opencode is handed to the derivation via callPackage.  Its
# version comes from static.nix.opencode-bun and scripts/opencode-bun-update,
# so it can run ahead of pkgs.bun when a release needs it.  On x86_64 it also
# selects the baseline zip, which pkgs.bun does not.  See the bunFileMap note
# below.  Bun ships only as prebuilt release zips, so this scoped Bun is
# itself a binary download.  See the source-vs-binary policy in README.org.
# From-source opencode unavoidably rests on a prebuilt Bun.
################################################################################
{ system, ... }:
final: prev:
let
  statics = (import ../static.nix).opencode;
  bunStatics = (import ../static.nix).opencode-bun;

  # Bun's release zips have platform-specific names.  Both x86_64 entries take
  # the "baseline" variant.  nixpkgs's own bun derivation uses the AVX2 build for
  # x86_64-linux, but the x86_64-linux hosts here and the remote builder that
  # builds for them are Ivy Bridge, which has AVX and no AVX2.  This Bun gets
  # executed on that hardware twice over: the derivation runs `bun completions`
  # in postPatchelf, and opencode's `bun build --compile` embeds the running
  # Bun into the opencode binary.  The AVX2 build dies with SIGILL at both
  # points; baseline needs only AVX.
  bunFileMap = {
    "aarch64-darwin" = "bun-darwin-aarch64.zip";
    "x86_64-darwin" = "bun-darwin-x64-baseline.zip";
    "aarch64-linux" = "bun-linux-aarch64.zip";
    "x86_64-linux" = "bun-linux-x64-baseline.zip";
  };
  bunFile =
    bunFileMap.${system}
      or (throw "opencode-bun: unsupported system ${system}");

  # Scoped Bun: override only version + src on the global bun derivation, so we
  # inherit its darwin code-signing / linux autoPatchelf handling unchanged.
  opencodeBun = prev.bun.overrideAttrs (_: {
    version = bunStatics.version;
    src = final.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${
        bunStatics.version
      }/${bunFile}";
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
