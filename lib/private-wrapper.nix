################################################################################
# mkPrivateWrapper — build flake outputs for a private wrapper around the
# public `nix-config` flake.
#
# A private wrapper exists to layer host-specific configuration that is unsafe
# to publish (org-internal hostnames, gateways, certs, identifiers, etc.) onto
# a host whose generic shape is declared in `nix-config`.  This helper handles
# the wiring so each wrapper only has to drop `./hosts/<hostname>.nix` files in
# its repo; the helper:
#
# - Reads `hostsDir` for `<hostname>.nix` files.
# - Looks each one up in `nix-config.darwinConfigurations` and
#   `nix-config.nixosConfigurations` and calls `extendModules` with the
#   private file as an extra module.
# - Augments `specialArgs.flake-inputs` with `nix-config` itself (the public
#   flake doesn't carry itself as an input, so without this the extension
#   modules can't refer back into the public tree).
# - Re-derives `home-manager.extraSpecialArgs` inside each extended host so
#   the augmented `flake-inputs` reaches home-manager modules too; without
#   this they evaluate against the unmodified specialArgs that public's
#   `darwin-host` / `nix-host` captured at let-binding time.
# - Throws if any `<hostname>.nix` doesn't name a host that exists in
#   nix-config — typos otherwise drop silently and leave the host
#   unconfigured.
#
# Returns the full flake-outputs shape (`nix-config // overrides`), so the
# typical call site is just:
#
#   outputs = { self, nix-config, ... }:
#     nix-config.lib.mkPrivateWrapper {
#       inherit nix-config;
#       hostsDir = ./hosts;
#     };
################################################################################
{
  nix-config,
  hostsDir,
}:
let
  inherit (nix-config.inputs.nixpkgs) lib;

  hostExtensions =
    let
      entries = builtins.readDir hostsDir;
      nixFiles = lib.filterAttrs (
        name: type: type == "regular" && lib.hasSuffix ".nix" name
      ) entries;
    in
    lib.mapAttrs' (
      fname: _:
      lib.nameValuePair (lib.removeSuffix ".nix" fname) (hostsDir + "/${fname}")
    ) nixFiles;

  specialArgs = {
    flake-inputs = nix-config.inputs // {
      inherit nix-config;
    };
  };

  extendOne =
    base: name: module:
    base.${name}.extendModules {
      inherit specialArgs;
      modules = [
        # Public's `darwin-host` / `nix-host` sets
        # `home-manager.extraSpecialArgs` from a closure-captured
        # `flake-inputs`, so the specialArgs override above does not reach
        # home-manager modules.  Re-derive extraSpecialArgs from our
        # (overridden) specialArgs here so that the augmented flake-inputs
        # is visible to user-level configs too — without this, home-manager
        # modules that reach back into nix-config fail with `attribute
        # 'nix-config' missing`.
        (
          {
            facts,
            flake-inputs,
            host-id,
            lib,
            system,
            ...
          }:
          {
            home-manager.extraSpecialArgs = lib.mkForce {
              inherit
                facts
                flake-inputs
                host-id
                system
                ;
            };
          }
        )
        module
      ];
    };

  overlayFor =
    base:
    lib.mapAttrs (name: module: extendOne base name module) (
      lib.filterAttrs (name: _: base ? ${name}) hostExtensions
    );

  finalDarwin =
    nix-config.darwinConfigurations // overlayFor nix-config.darwinConfigurations;
  finalNixos =
    nix-config.nixosConfigurations // overlayFor nix-config.nixosConfigurations;

  unmatched = lib.filterAttrs (
    name: _:
    !(nix-config.darwinConfigurations ? ${name})
    && !(nix-config.nixosConfigurations ? ${name})
  ) hostExtensions;
in
if unmatched != { } then
  throw "host extensions in ${toString hostsDir} with no matching nix-config host: ${lib.concatStringsSep ", " (lib.attrNames unmatched)}"
else
  nix-config
  // {
    darwinConfigurations = finalDarwin;
    nixosConfigurations = finalNixos;
    # proton-deploy resolves the deploy strategy from `.#hostSystems."<host>"'
    # -- a cheap host -> "darwin"/"nixos" map that avoids evaluating a full
    # system config.  Public nix-config exposes the *Configurations sets but
    # not this map, and it must also cover the private host extensions, so
    # synthesise it here over the extended sets (mirroring the hand-written
    # producer in the non-wrapper lenses).
    hostSystems =
      lib.mapAttrs (_: _: "darwin") finalDarwin
      // lib.mapAttrs (_: _: "nixos") finalNixos;
  }
