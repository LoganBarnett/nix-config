################################################################################
# Integrates blocky-lists-updater with the existing Blocky DNS configuration.
#
# This configuration enables dynamic blocklist management by:
# 1. Setting up blocky-lists-updater to fetch and aggregate remote blocklists
# 2. Configuring Blocky to consume the aggregated lists via HTTP
# 3. Supporting local custom lists that can be dynamically updated
#
# The lists-updater serves files via HTTP on port 8081, and Blocky fetches them
# from there. When lists change, the updater calls Blocky's /api/lists/refresh
# endpoint to reload without restart.
################################################################################
{
  config,
  facts,
  host-id,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) optionals;
  inherit (lib.attrsets) mapAttrs' mapAttrsToList;
  inherit (lib.lists)
    any
    flatten
    filter
    unique
    ;

  # URL where blocky-lists-updater serves aggregated lists.
  listsBaseUrl = "http://localhost:${toString config.services.blocky-lists-updater.webPort}/downloaded";
  watchListsBaseUrl = "http://localhost:${toString config.services.blocky-lists-updater.webPort}/watch";
in
{
  imports = [
    ../nixos-configs/blocky.nix
    ../nixos-modules/blocky-lists-updater.nix
  ];

  services.blocky-lists-updater = {
    enable = true;
    blockyUrl = "http://localhost:4000";
    # Changed from 8081 to 8082 to avoid conflict with goss-exporter.
    webPort = 8082;

    # Remote sources to download and aggregate.
    sources = {
      ads = [
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
        "https://big.oisd.nl/domainswild"
        "https://blocklistproject.github.io/Lists/ads.txt"
        "https://blocklistproject.github.io/Lists/tracking.txt"
      ];
      adult = [
        "https://blocklistproject.github.io/Lists/porn.txt"
      ];
      # Not a blocklist.  This is a curated list of domains that blocklists
      # commonly get wrong -- entries that are technically telemetry but are
      # load-bearing for a site's function.  See the `allowlists` wiring below
      # for why we subscribe to it.
      allowlist = [
        "https://raw.githubusercontent.com/ShadowWhisperer/BlockLists/master/Whitelists/Whitelist"
      ];
      malware = [
        "https://blocklistproject.github.io/Lists/abuse.txt"
        "https://blocklistproject.github.io/Lists/crypto.txt"
        "https://blocklistproject.github.io/Lists/fraud.txt"
        "https://blocklistproject.github.io/Lists/phishing.txt"
        "https://blocklistproject.github.io/Lists/piracy.txt"
        "https://blocklistproject.github.io/Lists/ransomware.txt"
        "https://blocklistproject.github.io/Lists/scam.txt"
      ];
      social = [
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/social-only/hosts"
      ];
      video = [
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
      ];
    };

    # Local watch lists for dynamic additions (e.g., from your classifier).
    watchLists = {
      # This file can be updated dynamically and will trigger Blocky refresh.
      classifier-blocks = "";
    };

    # Update lists daily.
    updateInterval = 86400;
    initialDelay = 60;
    logLevel = "INFO";
  };

  # Override Blocky configuration to use the updater-served lists.
  services.blocky.settings.blocking = {
    blackLists = {
      ads = [ "${listsBaseUrl}/ads.txt" ];
      adult = [ "${listsBaseUrl}/adult.txt" ];
      malware = [ "${listsBaseUrl}/malware.txt" ];
      social = [ "${listsBaseUrl}/social.txt" ];
      video = [ "${listsBaseUrl}/video.txt" ];
      # Add the classifier watch list as a dynamic source.
      classifier = [ "${watchListsBaseUrl}/classifier-blocks.txt" ];
    };
    # Rescue domains that upstream blocklists block by mistake.
    #
    # Motivating case: blocklistproject's tracking.txt gained `acs.aliexpress.us`
    # in commit e3a5695 (2026-07-04), one of 128,817 domains added by a bot in a
    # single unreviewed commit.  That host is Alibaba's MTOP API gateway -- the
    # endpoint AliExpress product pages call for their detail JSON -- so blocking
    # it makes every listing render a client-side 404 while the document request
    # still returns 200.  Maddening to diagnose from the browser.
    #
    # ShadowWhisperer (the upstream that blocklistproject imports *from*) caught
    # this and moved the domain to their Whitelist with the note "Breaks Site -
    # AliExpress (Gives 404 Error on every listing)".  That correction never
    # propagates downstream: blocklistproject's sync only ever adds domains, and
    # it reads their upstream's block lists without ever reading its whitelist.
    # Subscribing to the whitelist directly is what closes that gap, and it
    # covers the whole class rather than just the domain that bit us.
    #
    # IMPORTANT: only ever attach an allowlist to a group that also has
    # denylists.  Per blocky's docs, "If a group has only allowlist entries,
    # only domains from this list are allowed, and all others be blocked" -- so
    # an allowlist on an otherwise-empty group silently turns into a deny-all.
    # `ads` is the right target here regardless: it is the group carrying
    # blocklistproject's ads.txt and tracking.txt, which is where this class of
    # false positive originates.
    allowlists = {
      ads = [ "${listsBaseUrl}/allowlist.txt" ];
    };
    # Keep the existing clientGroupsBlock configuration from blocky.nix.
    # It will inherit from the parent import.
  };

  # Open the updater's web port for local access.
  networking.firewall.allowedTCPPorts = [
    config.services.blocky-lists-updater.webPort
  ];
}
