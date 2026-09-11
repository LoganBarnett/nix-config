################################################################################
# stats overlay to use version and hash from static.nix.
#
# Stats (exelban/stats) is the menu bar system monitor.  Upstream releases
# every few weeks and the stable nixpkgs branch this flake tracks never picks
# those up, so the version is pinned here and bumped with scripts/stats-update.
#
# This is a direct binary download, which README.org §Rapid Package Updates
# treats as an exception needing sign-off and an in-file justification.
# Approved by Logan on 2026-09-10.  A from-source build is not practical:
#
# - Stats is an Xcode project with several Swift targets.  nixpkgs has no
#   Xcode, and xcbuild does not handle a modern multi-target Swift project, so
#   there is nothing for Nix to drive the build with.
# - The SMC helper that reads sensors and drives fans is installed through
#   SMJobBless.  The SMPrivilegedExecutables and SMAuthorizedClients
#   requirements in the Info.plists are anchored to upstream's Developer ID
#   certificate.  The rcodesign ad-hoc pass used by derivations/obs-studio and
#   derivations/prusa-slicer gives a bundle a code identity, but an ad-hoc
#   signature cannot satisfy a certificate-anchored requirement, so those
#   plists would also need patching to identifier-only requirements.
#
# The nixpkgs derivation ships the same upstream DMG for the same reasons, so
# the only thing this overlay changes is which release it fetches.
################################################################################
final: prev:
if !prev.stdenv.hostPlatform.isDarwin then
  { }
else
  let
    statics = (import ../static.nix).stats;
    inherit (statics) version hash;
  in
  {
    stats = prev.stats.overrideAttrs (_: {
      inherit version;
      src = final.fetchurl {
        url = "https://github.com/exelban/stats/releases/download/v${version}/Stats.dmg";
        name = "Stats.dmg";
        inherit hash;
      };
      # Do not let Nix's fixup phase touch the bundle; any modification breaks
      # the notarised signature that SMJobBless checks before installing the
      # helper.
      dontFixup = true;
    });
  }
