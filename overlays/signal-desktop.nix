################################################################################
# Signal gets its own section just because it's special.  I don't mean that
# kindly.
#
# I can't use the normal nixpkgs for this, becuase Signal insists on
# frequently updating itself.  This update will never work due to
# immutability (thank goodness), but it still means we need to have a
# means of getting latest.  This is because Signal Desktop disables
# itself after an update becomes available.  Meanies.
################################################################################
{ flake-inputs, system, ... }:
final: prev: {
  signal-desktop-bin =
    prev.signal-desktop-bin
    # Ugh this is rather hopeless.  Nixpkgs drifts behind so some hero needs to
    # keep it updated, and I'm not that hero.
    .overrideAttrs
      (
        old:
        let
          statics = (import ../static.nix).signal-desktop-bin;
          inherit (statics) version hash;
        in
        {
          inherit version;
          src = final.fetchurl {
            url = "https://updates.signal.org/desktop/signal-desktop-mac-universal-${version}.dmg";
            inherit hash;
          };
          # As of 8.18.0 Signal renamed the DMG volume from "Signal" to
          # "Signal Installer", so 7z unpacks Signal.app one level down under a
          # "Signal Installer/" wrapper directory.  The stock nixpkgs derivation
          # assumes sourceRoot="." with Signal.app at the root and fails with
          # `cp: cannot stat 'Signal.app'`.  Locate Signal.app wherever it lands
          # so a future volume rename doesn't break us again.
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/Applications"
            cp -r "$(find . -maxdepth 2 -name Signal.app -print -quit)" \
              "$out/Applications/"
            runHook postInstall
          '';
        }
      );
}
