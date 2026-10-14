################################################################################
# Syncs ICS calendar feeds into org files for org-agenda.
#
# Each calendar gets a launchd agent that queries an ICS URL and converts it to
# org-agenda entries.
#
# A published calendar link usually carries its access token in the URL, so the
# URL is an agenix secret, `ics-<name>-url`, read by the agent at run time.
# Nothing secret lands in the Nix store.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    mapAttrs'
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    types
    ;
  cfg = config.programs.emacs.org-agenda.ics-calendars;
  user = config.programs.emacs.org-agenda.user;
  # macOS keeps every home under /Users.
  home = "/Users/${user}";
  ics-to-org = pkgs.callPackage ../derivations/ics-to-org/default.nix { };
  secretName = name: "ics-${name}-url";
  agentName = name: "ics-${name}-sync";
  outputFile = name: "${cfg.outputDirectory}/${name}.org";
  logFile = name: "${home}/Library/Logs/${agentName name}.log";
in
{
  imports = [ ../agnostic-modules/emacs-org-agenda.nix ];

  options.programs.emacs.org-agenda.ics-calendars = {
    enable = mkEnableOption "syncing ICS calendar feeds into org files";
    outputDirectory = mkOption {
      type = types.str;
      example = "/Users/me/notes/agenda/generated";
      description = ''
        Absolute directory that receives one `<name>.org` per calendar.  It is
        created if missing.
      '';
    };
    interval = mkOption {
      type = types.ints.positive;
      # Thirty minutes was a coin flip.  Publishers refresh with their own lag.
      default = 1800;
      description = "Seconds between syncs of every calendar.";
    };
    calendars = mkOption {
      default = { };
      description = ''
        Calendars to sync, keyed by name.  Each yields the org file
        `<outputDirectory>/<name>.org`, the agenix secret `ics-<name>-url`,
        and the launchd agent `ics-<name>-sync`.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            rekeyFile = mkOption {
              type = types.path;
              description = ''
                The ICS URL, encrypted for agenix-rekey.  By convention
                `secrets/issued/ics-<name>-<host-id>-url.age` in the flake
                that owns the calendar.
              '';
            };
            days = mkOption {
              type = types.ints.unsigned;
              default = 90;
              description = ''
                Window in days on each side of today within which recurring
                events are expanded into individual entries.
              '';
            };
          };
        }
      );
    };
  };

  config = mkIf cfg.enable {
    programs.emacs.org-agenda.files = mapAttrsToList (
      name: _: outputFile name
    ) cfg.calendars;

    age.secrets = mapAttrs' (
      name: calendar:
      nameValuePair (secretName name) {
        inherit (calendar) rekeyFile;
        # The agent runs as the login user, not as root.
        mode = "0400";
        owner = user;
      }
    ) cfg.calendars;

    home-manager.users.${user}.launchd.agents = mapAttrs' (
      name: calendar:
      nameValuePair (agentName name) {
        enable = true;
        config = {
          ProgramArguments = [
            "${ics-to-org}/bin/ics-to-org"
            "--url-file"
            config.age.secrets.${secretName name}.path
            "--output"
            (outputFile name)
            "--days"
            (toString calendar.days)
          ];
          RunAtLoad = true;
          # Runs missed while the machine sleeps fire once on wake.
          StartInterval = cfg.interval;
          StandardOutPath = logFile name;
          StandardErrorPath = logFile name;
        };
      }
    ) cfg.calendars;

    # launchd does not rotate the files it opens for StandardOutPath, so
    # newsyslog does.  Flags: N, no signal on rotation, because the agent exits
    # after each run and reopens the log on the next.  J, bzip2 the archives.
    # Size is in KB and count is archives retained.
    environment.etc."newsyslog.d/ics-calendars.conf".text = ''
      # logfilename [owner:group] mode count size when flags
      ${concatStringsSep "\n" (
        mapAttrsToList (
          name: _: "${logFile name} ${user}:staff 640 5 10240 * NJ"
        ) cfg.calendars
      )}
    '';
  };
}
