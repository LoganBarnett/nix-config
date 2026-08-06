################################################################################
# Configures zwave-js-ui as a headless Z-Wave driver for OpenHAB.  OpenHAB's
# native Z-Wave binding lacks S2 security support, so we run zwave-js-ui to
# manage the Aeotec Z-Stick 7 and expose a websocket that OpenHAB connects to
# via the zwavejs binding.
#
# zwave-js-ui gives a lot of control over things, but you lose a lot of logs
# (unless maybe you set the log level to "silly", but I haven't confirmed this
# yet).  I think it also uses saner defaults for things, and overall seems to
# actually be active.  By contrast, zwave-js-server (node-zwave-server) does not
# appear to be active anymore.
#
# Keep in mind when provisioning / pairing / including new devices, it can take
# minutes for the "interview" to complete.
#
# This service's configuration structure is woefully undocumented.  It is meant
# to just beat up its configuration constantly.  This configuration, along with
# my copy from nixpkgs, copies the settings file out of the store and into
# /var/lib/zwave-js-ui/settings.json.  You can make changes in the UI and
# inspect/diff the file to see what changed.  Do be mindful to move anything you
# want to keep into this configuration, lest the next restart blow it away.
# At some point I should make a read-only mode to lock things down, but I expect
# I'll be tweaking it for a while.
################################################################################
{
  config,
  facts,
  host-id,
  lib,
  pkgs,
  ...
}:
{
  networking.dnsAliases = [ "zwave-js-ui" ];
  services.https.fqdns."zwave-js-ui.${facts.network.domain}" = {
    enable = true;
    internalPort = 8091;
  };
  systemd.services.zwave-js-ui = {
    after = [ "run-agenix.d.mount" ];
    requires = [ "run-agenix.d.mount" ];
    serviceConfig = {
      LoadCredential = [
        "zwave-js-secret:${config.age.secrets.aeotec-z-stick-7-zwave-js-ui-security-file.path}"
      ];
    };
  };
  services.zwave-js-ui = {
    enable = true;
    serialPort = config.hardware.aeotec-z-stick-7.serialPort;
    secretsConfigFile = "/run/credentials/zwave-js-ui.service/zwave-js-secret";
    declarativeSettings = {
      # See
      # https://github.com/zwave-js/zwave-js-ui/blob/26f2e698354e56b7ec1b82cd3a99e106fedcf923/api/lib/ZwaveClient.ts#L588
      # for the closest thing to a document for some of these settings.
      zwave = {
        port = config.hardware.aeotec-z-stick-7.serialPort;
        commandsTimeout = 30;
        serverEnabled = true;
        serverHost = "127.0.0.1";
        serverPort = 3004;
        enableStatistics = false;
        disclaimerVersion = 1;
        # Logging is declared with these root-level keys, and must never go in
        # zwave.options.logConfig.  Anything under zwave.options is handed to
        # the zwave-js driver by reference, and zwave-js-ui attaches live
        # winston transports to options.logConfig at driver start
        # (api/lib/ZwaveClient.ts: `zwaveOptions.logConfig.transports =
        # [logTransport]`).  Those transports make the in-memory settings
        # object circular, so GET /api/settings — the UI's first bootstrap
        # request — crashes in res.json() with "Converting circular structure
        # to JSON".  The crash is an unhandled rejection that never answers
        # the request, nginx 504s after 60 seconds, and the UI hangs forever
        # on its loading screen.  The root-level keys below are instead copied
        # into a fresh logConfig object on each driver start
        # (api/lib/utils.ts buildLogConfig), so nothing the driver mutates is
        # reachable from the settings.
        #
        # https://github.com/zwave-js/zwave-js-ui/discussions/2166#discussioncomment-1948873
        # suggests the opposite — declaring all logging under options — but
        # following that advice is precisely what produced the serialization
        # failure it warns about.
        logEnabled = true;
        # Winston levels: "silly" (6) is the most verbose; "debug" (5) is one
        # notch down.
        logLevel = "debug";
        logToFile = false;
        # Force driver logs to stdout so journald captures them.  Upstream
        # only forces console logging under Docker (stdout is not a TTY under
        # systemd, so nothing would be logged otherwise).  This key is added
        # by our patch in ../overlays/zwave-js-ui.nix — a candidate for
        # upstreaming; without the patch the key is ignored.
        forceConsole = true;
      };
      # This section has settings that are set by the UI on startup.  We'll set
      # them first.
      securityKeysLongRange = { };
      deviceConfigPriorityDir = "/var/lib/zwave-js-ui/config";
      enableSoftReset = true;
      disableChangelog = false;
      # Backup what, exactly?
      backup = {
        storeBackup = false;
        storeCron = "0 0 * * *";
        storeKeep = 7;
        nvmBackup = false;
        nvmBackupOnEvent = false;
        nvmCron = "0 0 * * *";
        nvmKeep = 7;
      };
      # A packet sniffer of sorts.  I'm not even sure I have hardware that can
      # do this, just leave it disabled.
      zniffer = {
        enabled = false;
        port = "";
        logEnabled = true;
        logToFile = true;
        maxFiles = 7;
        securityKeys = {
          S2_Unauthenticated = "";
          S2_Authenticated = "";
          S2_AccessControl = "";
          S0_Legacy = "";
        };
        securityKeysLongRange = {
          S2_Authenticated = "";
          S2_AccessControl = "";
        };
        convertRSSI = false;
      };
      ui = {
        darkMode = true;
        navTabs = false;
        compactMode = false;
        streamerMode = false;
      };
    };
  };
}
