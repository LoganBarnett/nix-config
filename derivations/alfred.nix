# Alfred 5 — macOS launcher / productivity app.  Replaces the homebrew
# `alfred` cask, which did nothing but unpack the official archive and copy
# the .app — so this stdenvNoCC derivation reproduces it exactly.  Alfred
# ships a plain .tar.gz (not a DMG), so no undmg is needed.
#
# In-app updates can't write into the read-only Nix store; bump `version`,
# the build number in `url`, and `hash` here to update (a scripts/alfred-update
# helper, à la scripts/firefox-bin-update, could automate that later).
{
  stdenvNoCC,
  fetchurl,
  lib,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "alfred";
  version = "5.7.3";

  src = fetchurl {
    # Alfred's URL carries a build number (2320) alongside the version;
    # bump both on update.
    url = "https://cachefly.alfredapp.com/Alfred_${finalAttrs.version}_2320.tar.gz";
    hash = "sha256-NAYMY5AXXzalMnDRfWvikNBskHm9UlEkDqcnU72UmM0=";
  };

  sourceRoot = ".";

  # Preserve Running with Crayons' notarised signature — any fixup-phase
  # mutation of the bundle invalidates it.  Same rationale as
  # overlays/firefox-bin.nix.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    mv "Alfred 5.app" "$out/Applications/Alfred 5.app"
    runHook postInstall
  '';

  meta = {
    description = "Productivity application and app launcher for macOS";
    homepage = "https://www.alfredapp.com/";
    license = lib.licenses.unfree;
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
