################################################################################
# programs.blackhole (macOS) — installs the BlackHole 2ch virtual audio driver,
# an open-source (GPL-3.0) CoreAudio loopback device.  It exposes a virtual
# output whose audio reappears on a virtual input, so any app's sound can be
# routed into a "microphone" another app selects — e.g. feeding Apple Music
# (mixed with your mic in OBS) into Discord.  See README.org and
# https://github.com/ExistentialAudio/BlackHole.
#
# WHY THIS IS NOT SHAPED LIKE steam.nix / microsoft-teams.nix --------------------
# Those two use the *evergreen* pattern (README §Evergreen Packages): a vendor
# that serves a single rolling, unversioned URL with no stable hash AND ships a
# self-updater, so we install once and delegate updates to the vendor.  BlackHole
# is the opposite on both counts:
#
#   * Existential Audio publishes stable, *versioned*, hashable artifacts
#     (existential.audio/downloads/BlackHole2ch-<ver>.pkg), so we can and should
#     pin version + hash — README §Rapid Package Updates ("prefer Rapid Package
#     Updates whenever a versioned URL exists").
#   * BlackHole has *no* self-updater.  An evergreen "exists? then exit" check
#     would freeze the host on whatever build installed first, forever, with no
#     record of which.  So the version bump must arrive via Nix (static.nix), and
#     the idempotency check below is *version-aware*: it reinstalls when the
#     installed pkg receipt differs from the pinned version.
#
# WHY A PINNED BINARY AND NOT A FROM-SOURCE BUILD (README binary-download
# exception, requires sign-off — granted) -------------------------------------
# README's default is from-source.  That is infeasible here: a CoreAudio HAL
# driver must be Apple Developer-ID *code-signed and notarized* or coreaudiod
# refuses to load it under SIP on Apple Silicon.  We cannot reproduce Existential
# Audio's signature, so a self-built .driver simply would not load.  BlackHole is
# a first-party, GPL-3.0, signed release — it clears the trust bar — and the .pkg
# is pinned by version + hash in static.nix (fetched as a fixed-output store
# path), which is the most reproducibility we can get for an unbuildable artifact.
#
# Like microsoft-teams.nix this is a root LaunchDaemon (not a LaunchAgent): the
# .pkg lays a driver into root-owned /Library/Audio/Plug-Ins/HAL via Apple's
# `installer`, which needs root.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.blackhole;

  # Version + hash live in static.nix alongside the other independently-pinned
  # packages; bump them with scripts/blackhole-update.  Imported directly here
  # (rather than via an overlay like firefox-bin/zoom-us) because the artifact
  # is not a usable nixpkgs package — it is a .pkg consumed solely by the
  # installer invocation below, so exposing it as a global pkgs attr would be a
  # forced fit.
  statics = (import ../static.nix).blackhole;

  # The signed, notarized installer .pkg as a fixed-output store path.  Because
  # the hash is pinned, this is fetched at build time and verified — the
  # bootstrapper does no network I/O, it just hands this local path to
  # `installer`.
  pkgFile = pkgs.fetchurl {
    url = "https://existential.audio/downloads/BlackHole2ch-${statics.version}.pkg";
    name = "BlackHole2ch-${statics.version}.pkg";
    inherit (statics) hash;
  };

  # gnused for the receipt parse; /usr/sbin/{pkgutil,installer} are macOS-only
  # and have no nixpkgs equivalent.  Their flags are single-dash long forms
  # (-package, -target, -verbose, --pkg-info) with no short variants, so those
  # are already the self-documenting spelling.
  installer = pkgs.writeShellScript "blackhole-bootstrap" ''
    set -euo pipefail

    # Version-aware idempotency.  pkgutil reports the installed pkg receipt's
    # version (empty/non-zero exit if BlackHole is absent — the `|| true` turns
    # that into an empty string under `set -o pipefail`).  We reinstall only on
    # a miss: absent, or a stale build after a static.nix bump.  Matching the
    # pinned version and exiting 0 is the cheap common path at every boot, and
    # it tells launchd (KeepAlive.SuccessfulExit = false) to stop relaunching.
    want="${statics.version}"
    have="$(/usr/sbin/pkgutil --pkg-info audio.existential.BlackHole2ch 2>/dev/null \
      | ${pkgs.gnused}/bin/sed --quiet 's/^version: //p' || true)"

    if [ "$have" = "$want" ]; then
      exit 0
    fi

    # Install the pinned .pkg as root.  No download happens here — pkgFile is a
    # verified store path — so `installer` just lays the signed HAL driver into
    # /Library/Audio/Plug-Ins/HAL.  BlackHole's own postinstall restarts
    # coreaudiod, so the device normally appears in Audio MIDI Setup without a
    # reboot; if it does not, log out and back in.  We deliberately do NOT
    # killall coreaudiod ourselves: this daemon's RunAtLoad fires immediately on
    # deploy (mid-session), and yanking CoreAudio out from under a running
    # session would cut all audio — the pkg's own scripting handles it at the
    # right moment.
    /usr/sbin/installer \
      -verbose \
      -package "${pkgFile}" \
      -target /
  '';
in
{
  options.programs.blackhole = {
    enable = mkEnableOption ''
      the BlackHole 2ch virtual audio driver on macOS.  A boot LaunchDaemon
      installs the pinned, notarized .pkg (version/hash in static.nix) whenever
      the installed version differs, then leaves it in place.  See
      darwin-modules/blackhole.nix for why this is pinned rather than evergreen,
      and scripts/blackhole-update to bump the version'';
  };

  config = mkIf cfg.enable {
    # Root LaunchDaemon, not a login LaunchAgent: installing a .pkg into
    # root-owned /Library/Audio/Plug-Ins/HAL requires root.
    launchd.daemons.blackhole-bootstrap = {
      serviceConfig = {
        RunAtLoad = true;
        # Relaunch only while the last run failed (then stop once it exits 0).
        # The version-aware fast path makes every later run exit 0 immediately,
        # and this rides out a transient install hiccup at boot.
        KeepAlive = {
          SuccessfulExit = false;
        };
        # Back off between failed retries so a persistent install failure does
        # not loop tightly.
        ThrottleInterval = 60;
        ProgramArguments = [ "${installer}" ];
        StandardOutPath = "/tmp/blackhole-bootstrap.log";
        StandardErrorPath = "/tmp/blackhole-bootstrap.log";
      };
    };
  };
}
