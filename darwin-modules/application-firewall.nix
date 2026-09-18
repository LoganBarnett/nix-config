# Vendored from nix-darwin's modules/networking/applicationFirewall.nix to
# fix a command-ordering bug on macOS 26.  ALF encodes block-all into its
# global state (0 = off, 1 = on, 2 = on + block-all), and socketfilterfw
# implements `--setblockall off` as "set global state to 1".  Upstream
# emits setglobalstate first and setblockall second, so a configuration
# that declares the firewall off while also managing blockAllIncoming has
# its "off" clobbered milliseconds later — every activation force-enables
# the firewall.  Verified in the unified log: two consecutive
# socketfilterfw PIDs write GlobalState = 0 then GlobalState = 1, 24ms
# apart, during darwin-rebuild activation.
#
# The fix: only emit `--setblockall` when the firewall is not declared
# off.  With the firewall on, `--setblockall` writes the correct state (1
# for off, 2 for on) regardless of ordering; with the firewall off,
# block-all is meaningless and emitting it would re-enable the firewall.
#
# Drop this module (and its import in darwin.nix) once the fix lands
# upstream in nix-darwin.
{ config, lib, ... }:
let
  cfg = config.networking.applicationFirewall;

  socketfilterfw =
    option: value:
    lib.concatStringsSep " " [
      "/usr/libexec/ApplicationFirewall/socketfilterfw"
      "--${option}"
      (if value then "on" else "off")
    ];
in
{
  disabledModules = [ "networking/applicationFirewall.nix" ];

  options.networking.applicationFirewall = {
    enable = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      example = true;
      description = "Whether to enable application firewall.";
    };

    blockAllIncoming = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      example = true;
      description = "Whether to block all incoming connections.";
    };

    allowSigned = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      example = true;
      description = "Whether to allow built-in software to receive incoming connections.";
    };

    allowSignedApp = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      example = true;
      description = "Whether to allow downloaded signed software to receive incoming connections.";
    };

    enableStealthMode = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      example = true;
      description = "Whether to enable stealth mode.";
    };
  };

  config = {
    system.activationScripts.networking.text = ''
      echo "configuring application firewall..." >&2

      ${lib.optionalString (cfg.enable != null) (
        socketfilterfw "setglobalstate" cfg.enable
      )}
      ${lib.optionalString (cfg.blockAllIncoming != null && cfg.enable != false) (
        socketfilterfw "setblockall" cfg.blockAllIncoming
      )}
      ${lib.optionalString (cfg.allowSigned != null) (
        socketfilterfw "setallowsigned" cfg.allowSigned
      )}
      ${lib.optionalString (cfg.allowSignedApp != null) (
        socketfilterfw "setallowsignedapp" cfg.allowSignedApp
      )}
      ${lib.optionalString (cfg.enableStealthMode != null) (
        socketfilterfw "setstealthmode" cfg.enableStealthMode
      )}
    '';
  };
}
