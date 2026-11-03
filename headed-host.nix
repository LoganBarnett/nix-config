{
  config,
  flake-inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    flake-inputs.emacs-config.darwinModules.default
    flake-inputs.emacs-config.darwinModules.org-agenda-ics-calendars
    ({ pkgs, ... }: {
      environment.systemPackages = pkgs.callPackage ./general-packages.nix { };
    })
  ];
}
