################################################################################
# programs.microsoft-teams (macOS) — installs Microsoft Teams (the "new" Teams,
# com.microsoft.teams2) and lets Microsoft's own updater keep it current.
#
# This is the same shape as darwin-modules/steam.nix: rather than pin Teams as
# an immutable, hashed store package, we install it imperatively — once, via a
# boot LaunchDaemon — and let the vendor manage updates from there.  Teams is a
# good fit for this pattern (documented in README.org §Evergreen Packages)
# because Microsoft serves a single rolling, *unversioned* installer URL
# ("lkg" = last known good) with no stable hash to pin, and because the
# installer bundles Microsoft AutoUpdate (MAU), which is Teams's update
# mechanism on macOS.  Pinning the rolling URL by hash would mean every silent
# upstream rotation breaks the Nix build; installing imperatively side-steps
# that and hands updates to MAU.
#
# Unlike Steam (a user-writable launcher stub, installed by a login LaunchAgent
# with ditto), the Teams .pkg installs into root-owned /Applications and lays
# down MAU and an audio-driver component, so it must run through Apple's
# `installer` as root — hence a LaunchDaemon rather than a LaunchAgent.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.microsoft-teams;

  # Long-form flags throughout for self-documentation.  curl and coreutils come
  # from nixpkgs (not the BSD /usr/bin versions) precisely so the long options
  # exist and behave predictably.  /usr/sbin/installer is macOS-only; it uses
  # single-dash long options (-package, -target, -verbose) and has no short
  # forms, so those are already the self-documenting spelling.
  installer = pkgs.writeShellScript "microsoft-teams-bootstrap" ''
    set -euo pipefail

    # Already installed — Teams self-updates in place via Microsoft AutoUpdate,
    # so there is nothing to do.  This fast path is what makes the daemon cheap
    # to run at every boot and self-healing if Teams is ever removed.  Exiting 0
    # here also tells launchd (KeepAlive.SuccessfulExit = false) to stop
    # relaunching us.
    if [ -d "${cfg.appPath}" ]; then
      exit 0
    fi

    work="$(${pkgs.coreutils}/bin/mktemp --directory)"
    # Remove the scratch directory on any exit, success or failure.
    trap '${pkgs.coreutils}/bin/rm --recursive --force "$work"' EXIT
    cd "$work"

    # Fetch Microsoft's rolling installer .pkg.  --fail turns a 4xx/5xx into a
    # non-zero exit; combined with the LaunchDaemon's KeepAlive policy below
    # that means a transient failure (e.g. network not yet up at boot) simply
    # retries instead of installing an error page.
    ${pkgs.curl}/bin/curl \
      --fail \
      --silent \
      --show-error \
      --location \
      --output MicrosoftTeams.pkg \
      "${cfg.installerUrl}"

    # Install via Apple's installer as root.  This lays down Teams.app in
    # /Applications, Microsoft AutoUpdate, and the Teams audio-driver component
    # — i.e. the full vendor install, exactly as a user double-clicking the pkg
    # would get.  MAU then owns all subsequent updates.
    /usr/sbin/installer \
      -verbose \
      -package MicrosoftTeams.pkg \
      -target /
  '';
in
{
  options.programs.microsoft-teams = {
    enable = mkEnableOption ''
      Microsoft Teams on macOS.  Runs Microsoft's official installer .pkg at
      boot (via a LaunchDaemon) when Teams is missing, then lets Microsoft
      AutoUpdate keep it current — the evergreen-install pattern described in
      README.org §Evergreen Packages'';

    appPath = mkOption {
      type = types.str;
      default = "/Applications/Microsoft Teams.app";
      description = ''
        Where Teams.app is expected to land.  The bootstrapper skips the
        download-and-install entirely when this path already exists, so Teams
        (via Microsoft AutoUpdate) owns the bundle and can rewrite it in place.
      '';
    };

    installerUrl = mkOption {
      type = types.str;
      default = "https://statics.teams.cdn.office.net/production-osx/enterprise/webview2/lkg/MicrosoftTeams.pkg";
      description = ''
        Microsoft's rolling, unversioned macOS installer .pkg ("lkg" = last
        known good).  No integrity hash is pinned because the URL always serves
        the latest installer; updates are handled by Microsoft AutoUpdate after
        the initial install, not by re-fetching this URL.
      '';
    };
  };

  config = mkIf cfg.enable {
    # A boot LaunchDaemon (runs as root), not a login LaunchAgent: installing
    # the .pkg into root-owned /Applications and laying down MAU + the audio
    # driver requires root, which a user agent does not have.
    launchd.daemons.microsoft-teams-bootstrap = {
      serviceConfig = {
        RunAtLoad = true;
        # Retry until the install succeeds (exit 0), then stop: SuccessfulExit
        # = false means "keep alive only while the last run failed".  This
        # rides out a boot where the network is not up yet, and the
        # already-installed fast path makes every later run exit 0 immediately.
        KeepAlive = {
          SuccessfulExit = false;
        };
        # Back off between failed retries so a persistently unreachable URL
        # does not hammer the network in a tight loop.
        ThrottleInterval = 60;
        ProgramArguments = [ "${installer}" ];
        StandardOutPath = "/tmp/microsoft-teams-bootstrap.log";
        StandardErrorPath = "/tmp/microsoft-teams-bootstrap.log";
      };
    };
  };
}
