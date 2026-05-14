################################################################################
# Ensure this host has a TLS certificate available which is tied to the internal
# CA.
################################################################################
{
  config,
  host-id,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tls;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;
in
{
  # TODO: Make this `security.tls`.
  options.tls = {
    enable = mkEnableOption "Manage TLS certificates." // {
      default = true;
    };
    expiry-warning-days = mkOption {
      type = types.int;
      default = 30;
      description = ''
        Number of days before certificate expiration at which the goss
        expiry check begins reporting failure.  Applies globally to every
        managed leaf.
      '';
    };
    tls-leafs = mkOption (
      let
        tls-leaf-type = types.submodule {
          options = {
            enable = mkEnableOption "Manage a TLS leaf certificate." // {
              default = true;
            };
            fqdn = mkOption {
              type = types.str;
            };
            ca = mkOption {
              # Not sure how to type this correctly.  Come back to it later.
              type = types.anything;
            };
          };
        };
      in
      {
        type = types.attrsOf tls-leaf-type;
        default = { };
      }
    );
  };

  config = mkIf cfg.enable (
    let
      tls-leafs = lib.filter (leaf: leaf.enable) (
        lib.attrsets.attrValues cfg.tls-leafs
      );
      expiry-warning-seconds = cfg.expiry-warning-days * 24 * 60 * 60;
    in
    {
      users.groups = {
        tls-leaf = { };
      };
      age.secrets = mkMerge (
        map (leaf-config: {
          "tls-${leaf-config.fqdn}.key" = {
            generator = {
              dependencies = [ leaf-config.ca ];
              script = "tls-signed-certificate";
            };
            group = "tls-leaf";
            mode = "0440";
            settings = {
              root-certificate = leaf-config.ca;
              inherit (leaf-config) fqdn;
            };
            rekeyFile = ../secrets/tls-${leaf-config.fqdn}.key.age;
          };
        }) tls-leafs
      );
      # Contribute per-leaf expiry checks unconditionally.  goss only runs
      # when "goss" is in networking.monitors (see nixos-modules/goss.nix),
      # so leaving these laid down on non-monitored hosts is inert.
      services.goss.checks.command = lib.listToAttrs (
        map (leaf-config: {
          name = "tls-cert-expiry-${leaf-config.fqdn}";
          value = {
            #   -checkend N  exit 0 if cert valid past N seconds, 1 otherwise.
            #   -noout       suppress printing the cert body.
            #   -in PATH     read certificate from PATH.
            exec = ''
              ${pkgs.openssl}/bin/openssl x509 \
                -checkend ${toString expiry-warning-seconds} \
                -noout \
                -in ${../secrets/tls-${leaf-config.fqdn}.crt}
            '';
            "exit-status" = 0;
          };
        }) tls-leafs
      );
    }
  );

}
