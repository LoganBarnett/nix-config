################################################################################
# Hands Emacs a list of extra org-agenda files from Nix.
#
# emacs-config reads ~/.config/emacs/nix-org-agenda.json at startup, in
# lisp/nix-org-agenda-config.el, and appends the paths under its
# `org-agenda-files` key to `org-agenda-files`.  This module writes that file
# from `programs.emacs.org-agenda.files`.  Producers of generated agenda files,
# such as darwin-modules/emacs-org-agenda-outlook-calendars.nix, append to that
# option rather than touching the file themselves.
#
# The contract is one top-level key, `org-agenda-files`, holding a JSON array
# of absolute paths.  Nothing is written when the list is empty, so a host that
# declares nothing looks the same to Emacs as one without this module, and
# Emacs warns about the missing file.  See docs/emacs-org-agenda.org.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    literalExpression
    mkIf
    mkOption
    types
    ;
  cfg = config.programs.emacs.org-agenda;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.emacs.org-agenda = {
    user = mkOption {
      type = types.str;
      default = config.system.primaryUser;
      defaultText = literalExpression "config.system.primaryUser";
      description = ''
        Login user whose Emacs reads the agenda file list.  Producer modules
        also use this as the owner of their secrets and agents.  NixOS has no
        `system.primaryUser`, so NixOS hosts must set this explicitly.
      '';
    };
    files = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example =
        literalExpression
          ''[ "/Users/me/notes/agenda/generated/work.org" ]'';
      description = ''
        Absolute paths Emacs appends to `org-agenda-files`.  Written to
        `~/.config/emacs/nix-org-agenda.json` under the key `org-agenda-files`.
      '';
    };
  };

  config = mkIf (cfg.files != [ ]) {
    home-manager.users.${cfg.user}.home.file.".config/emacs/nix-org-agenda.json".source =
      jsonFormat.generate "nix-org-agenda.json" {
        org-agenda-files = cfg.files;
      };
  };
}
