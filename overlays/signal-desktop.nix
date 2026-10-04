################################################################################
# Stop Signal Desktop from expiring itself.
#
# Signal refuses to send messages once a build is older than its expiry window,
# which is 30 days for a build it cannot auto-update -- and a Nix-installed app
# can never auto-update itself.  nixpkgs already patches that window to a flat
# 90 days; this goes the rest of the way and neutralises the check, so a working
# install keeps working until we choose to bump it.
#
# `hasBuildExpired` is the single predicate behind the lockout.  It also refuses
# to trust an expiry set too far in the future, so pushing the timestamp out
# instead would report the build as expired rather than extend it.
#
# This appends to `postPatch` rather than `patches` because `pnpmDeps` inherits
# `patches` into its fixed-output derivation, and leaving that alone avoids
# disturbing its pinned hash.
################################################################################
final: prev: {
  signal-desktop = prev.signal-desktop.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace ts/util/buildExpiration.std.ts \
        --replace-fail \
          '}: HasBuildExpiredOptionsType): boolean {' \
          '}: HasBuildExpiredOptionsType): boolean { return false;'
    '';
  });
}
