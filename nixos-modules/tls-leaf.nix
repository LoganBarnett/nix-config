################################################################################
# Linux access control for internal-CA TLS leaf keys: the tls-leaf group lets
# unprivileged consumers such as nginx read the generated private keys.  The
# certificates themselves come from agnostic-modules/tls-leaf.nix.
################################################################################
{
  config,
  lib,
  ...
}:
let
  cfg = config.tls;
  inherit (lib)
    mkIf
    mkMerge
    ;
in
{
  imports = [ ../agnostic-modules/tls-leaf.nix ];

  config = mkIf cfg.enable (
    let
      tls-leafs = lib.filter (leaf: leaf.enable) (
        lib.attrsets.attrValues cfg.tls-leafs
      );
    in
    {
      users.groups = {
        tls-leaf = { };
      };
      age.secrets = mkMerge (
        map (leaf-config: {
          "tls-${leaf-config.fqdn}.key" = {
            group = "tls-leaf";
            mode = "0440";
          };
        }) tls-leafs
      );
    }
  );
}
