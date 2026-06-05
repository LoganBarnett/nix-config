# Enable nix-remote-builder-doctor on Darwin hosts.
{
  config,
  facts,
  flake-inputs,
  pkgs,
  ...
}:

{
  services.nix-remote-builder-doctor = {
    enable = true;
    # Reference the package through the overridable `flake-inputs` module arg
    # rather than a nixpkgs overlay.  An overlay lexically captures nix-config's
    # own flake-inputs, so a private-lens `specialArgs.flake-inputs` override
    # can't reach it; this path can (it's how the gitea-patched build lands).
    package =
      flake-inputs.nix-remote-builder-doctor.packages.${pkgs.system}.default;
    builders = [
      {
        name = "silicon";
        hostName = "silicon.${facts.network.domain}";
      }
      {
        name = "rpi-build";
        hostName = "rpi-build.${facts.network.domain}";
      }
    ];
  };
}
