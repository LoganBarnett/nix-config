################################################################################
# programs.steam (macOS) — a Darwin analogue of NixOS's programs.steam.
#
# NixOS's programs.steam prepares the host (FHS env, 32-bit drivers, udev,
# firewall) and then lets Steam's bootstrapper self-manage its client, runtime,
# and games at runtime.  macOS needs none of that host-prep, but the shape is
# identical: Steam.app is just a launcher stub that downloads and self-updates
# the real client into ~/Library/Application Support/Steam.
#
# So rather than pin Steam.app as an immutable, hashed store package, we install
# it imperatively — once, via a login LaunchAgent — and let Steam do its thing.
# Valve serves a single rolling, *unversioned* installer URL (steam.dmg), so
# there is no stable hash to pin; Homebrew's own cask is likewise
# `sha256 :no_check`.  Installing into the mutable /Applications (not the Nix
# store) also lets Steam's updater rewrite the launcher stub itself.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.steam;

  # Long-form flags are used throughout for self-documentation.  curl and
  # coreutils come from nixpkgs (not the BSD /usr/bin versions) precisely so
  # the long options exist and behave predictably; ditto is macOS-only and
  # has no long-form flags (it takes positional source/destination).
  installer = pkgs.writeShellScript "steam-bootstrap" ''
    set -euo pipefail

    # Already installed — Steam self-updates in place, so there is nothing to
    # do.  Running at every login is therefore cheap, and self-healing if
    # Steam is ever removed.
    if [ -d "${cfg.appPath}" ]; then
      exit 0
    fi

    work="$(${pkgs.coreutils}/bin/mktemp --directory)"
    # Remove the scratch directory on any exit, success or failure.
    trap '${pkgs.coreutils}/bin/rm --recursive --force "$work"' EXIT
    cd "$work"

    # Fetch Valve's rolling installer DMG.  --fail turns a 4xx/5xx into a
    # non-zero exit so the LaunchAgent simply retries at the next login
    # instead of installing an error page.
    ${pkgs.curl}/bin/curl \
      --fail \
      --silent \
      --show-error \
      --location \
      --output steam.dmg \
      "${cfg.installerUrl}"

    # Unpack the .app from the DMG (lzfse UDIF, no license-agreement wall).
    ${pkgs.undmg}/bin/undmg steam.dmg

    # Install with ditto, the macOS-idiomatic bundle copy: it preserves the
    # extended attributes and code signature that a plain cp would strip,
    # keeping Valve's notarisation intact.  ditto takes positional
    # source/destination arguments — it has no long-form flags.
    /usr/bin/ditto "Steam.app" "${cfg.appPath}"
  '';
in
{
  options.programs.steam = {
    enable = mkEnableOption ''
      Steam on macOS.  Installs the Steam.app launcher bootstrapper into
      /Applications at login (via a LaunchAgent) when it is missing, then
      lets Steam self-update — mirroring how NixOS's programs.steam prepares
      the host and lets Steam manage itself'';

    appPath = mkOption {
      type = types.str;
      default = "/Applications/Steam.app";
      description = ''
        Where the Steam.app launcher bootstrapper is installed.  Kept in the
        mutable /Applications (not the Nix store) so Steam's own updater can
        rewrite the launcher stub.
      '';
    };

    installerUrl = mkOption {
      type = types.str;
      default = "https://cdn.cloudflare.steamstatic.com/client/installer/steam.dmg";
      description = ''
        Valve's rolling, unversioned macOS installer DMG.  No integrity hash
        is pinned because the URL always serves the latest installer (as with
        Homebrew's `sha256 :no_check` cask).
      '';
    };
  };

  config = mkIf cfg.enable {
    # A login LaunchAgent (runs in the user's GUI session), not a boot daemon:
    # Steam.app must be owned by and writable to the user so Steam's updater
    # can rewrite the launcher stub.  The installer is idempotent, so
    # RunAtLoad at every login is cheap and self-healing.
    launchd.agents.steam-bootstrap = {
      serviceConfig = {
        RunAtLoad = true;
        # One-shot installer, not a resident service — do not respawn it.
        KeepAlive = false;
        ProgramArguments = [ "${installer}" ];
        StandardOutPath = "/tmp/steam-bootstrap.log";
        StandardErrorPath = "/tmp/steam-bootstrap.log";
      };
    };
  };
}
