################################################################################
# Firefox browser configuration with managed extensions and preferences.
#
# Extensions are sourced from NUR (github:nix-community/NUR) via the
# rycee/nur-expressions addon collection.
#
# The prefers-color-scheme override ensures websites correctly receive the
# dark mode signal — without it, Firefox on macOS does not propagate the OS
# dark mode preference to websites via the prefers-color-scheme media query,
# even when the OS and browser are both set to dark mode.
#
# profiles.ini is managed by home-manager as a read-only Nix store symlink.
# Firefox keys its per-installation profile bookkeeping on a hash of the
# directory holding its binary, which is a Nix store path and so changes on
# every rebuild.  An installation it has not seen must record itself in
# profiles.ini before startup continues; when that write fails, Firefox
# creates an empty throwaway profile and exits with "Firefox couldn't load
# your profile".  The launchd agent below sets MOZ_LEGACY_PROFILES so Firefox
# skips per-installation profiles and opens the Default=1 profile without
# writing anything, which is what the nixpkgs Firefox wrapper does on Linux
# for the same reason.  No pref in this file can help: prefs are read from
# the profile, so only after the profile has already been chosen.  See
# docs/firefox-profile-load-failure.org for the symptoms and what to check.
#
# Sideloaded extension auto-disable: home-manager symlinks the extension
# .xpi files into Profiles/default/extensions/.  Firefox treats anything
# discovered through the filesystem (rather than installed via about:addons
# or AMO) as a "foreign install" and, since Firefox 73, marks them
# userDisabled=true on first discovery — even when signedState=2 (signed by
# Mozilla).  The extensions.autoDisableScopes pref is a bitfield of install
# scopes whose foreign installs should be auto-disabled (default 15 = all:
# profile|user|system|application).  Setting it to 0 lets all scopes through.
# This pref only applies when the addon is *first discovered*; if Firefox
# has already cached an extension as disabled in extensions.json /
# addonStartup.json.lz4, the pref change alone won't re-enable it — those
# state files must be deleted so Firefox rescans the .xpi files and applies
# the new pref to the fresh discovery.
################################################################################
{ lib, pkgs, ... }:
let
  # Firefox reads these before it opens a profile, so they have to come from
  # the launchd GUI domain that LaunchServices spawns apps from; variables
  # exported by a shell never reach an app opened from Alfred or the Dock.
  firefox-env = {
    # Skip per-installation profiles; see the banner comment.
    MOZ_LEGACY_PROFILES = "1";
    # Rolling back to a generation with an older Firefox otherwise trips the
    # profile-downgrade refusal.  Same tradeoff the nixpkgs wrapper accepts.
    MOZ_ALLOW_DOWNGRADE = "1";
  };
in
{
  programs.firefox = {
    enable = true;
    package = pkgs.firefox-bin;
    # Firefox's own updater finds newer releases but cannot install them into
    # the read-only store, so it nags at every launch.  Updates arrive through
    # scripts/firefox-bin-update instead.  On macOS home-manager delivers
    # policies with `defaults import org.mozilla.firefox`, which avoids placing
    # a policies.json inside the signed bundle.
    policies = {
      DisableAppUpdate = true;
    };
    profiles.default = {
      isDefault = true;
      extensions.packages =
        let
          addons = pkgs.nur.repos.rycee.firefox-addons;
        in
        [
          addons."cookies-txt"
          addons."don-t-fuck-with-paste"
          addons.ghosttext
          addons."tab-counter-plus"
          addons.vimium
          # AboveVTT is not in the NUR rycee firefox-addons collection, so we
          # package its signed AMO .xpi directly with the same builder NUR uses
          # for its generated entries.  Bumping it means updating version, url,
          # and sha256 together from the AMO listing
          # (https://addons.mozilla.org/firefox/addon/abovevtt/).
          (addons.buildFirefoxXpiAddon {
            pname = "abovevtt";
            version = "1.55";
            addonId = "{52e126d4-d2d7-483a-a0a1-6e8aace23253}";
            url = "https://addons.mozilla.org/firefox/downloads/file/4840085/abovevtt-1.55.xpi";
            sha256 = "sha256-lmVDzIrlVbcB1mlHVl4JwMGw+6UrRKWmRX6SHe8wBZg=";
            meta = { };
          })
        ];
      settings = {
        # 0 = dark, 1 = light, 2 = follow OS (broken on macOS — OS reports
        # light despite being in dark mode).
        "layout.css.prefers-color-scheme.content-override" = 0;
        # Disable the in-browser multi-profile feature (Firefox 138+); it
        # persists its state through profiles.ini, which is read-only here.
        # It has no bearing on which profile Firefox opens at startup; see
        # the banner comment.
        "browser.profiles.enabled" = false;
        # Suppress the first-run wizard.  Firefox compares
        # homepage_override.mstone against the current build milestone; "ignore"
        # unconditionally skips the new-install/upgrade welcome page.  Each Nix
        # store update changes the binary path, which Firefox treats as a fresh
        # installation, triggering the wizard on every deploy without these.
        "browser.startup.homepage_override.mstone" = "ignore";
        # Do not prompt to become the default browser.
        "browser.shell.checkDefaultBrowser" = false;
        # Accept the data-reporting / telemetry terms so the TOU dialog does
        # not appear.  Version 2 is the current accepted policy version.
        "datareporting.policy.dataSubmissionPolicyAcceptedVersion" = 2;
        # Tell Firefox that the import/migration wizard has already run.
        "browser.migration.version" = 2;
        # Disable the post-first-run "later run" onboarding experience.
        "browser.laterrun.enabled" = false;
        # Disable Pocket entirely — controls the "Popular Today" stories
        # section on the new-tab page.  The activity-stream prefs below are
        # also set but Pocket must be disabled at the extension level too.
        "extensions.pocket.enabled" = false;
        # Remove the "Popular Today" Pocket stories section from new-tab.
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        "browser.newtabpage.activity-stream.showSponsored" = false;
        # Remove the "Top Sites" shortcuts row (pre-populated app suggestions)
        # from the new-tab page entirely.
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        # Remove the default app shortcut suggestions ("Top Sites") that
        # Firefox pre-populates on new-tab.  Setting to an empty string clears
        # the built-in list; any sites the user explicitly pins are unaffected.
        "browser.newtabpage.activity-stream.default.sites" = "";
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        # Suppress Firefox 130+ "Try Profiles" onboarding notification that
        # appears inside the browser window after first launch.  The
        # browser.profiles.enabled = false set above also suppresses the
        # profile-picker dialog; this pref targets the in-browser banner.
        "browser.profiles.createdByDevEdition" = false;
        # Allow filesystem-discovered (foreignInstall=true) extensions —
        # i.e. the .xpi files home-manager symlinks into the profile's
        # extensions/ directory — to be active by default instead of being
        # auto-disabled.  See banner comment above for the full rationale.
        # 0 = no scopes auto-disable; default is 15 (all scopes).
        "extensions.autoDisableScopes" = 0;
        # Scan all install scopes at startup so home-manager-symlinked
        # extensions are picked up after every nix-darwin switch (the symlink
        # target inside the Nix store changes with each generation).  Default
        # is 15 (all scopes) — set explicitly to make intent clear.
        "extensions.startupScanScopes" = 15;
      };
    };
  };

  # nix-darwin's launchd.user.envVariables would be the obvious home for
  # these, but it only runs launchctl setenv during activation and nothing
  # restores the variables at boot.  A RunAtLoad agent re-applies them at
  # every login and immediately on switch.  home-manager only installs
  # launchd agents on macOS; on other hosts this block is inert.
  launchd.agents.firefox-launchd-env = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        (lib.concatStringsSep " && " (
          lib.mapAttrsToList (
            name: value: "/bin/launchctl setenv ${name} ${value}"
          ) firefox-env
        ))
      ];
      RunAtLoad = true;
    };
  };
}
