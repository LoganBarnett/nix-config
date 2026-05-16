################################################################################
# Stalwart-mail module extensions.
#
# Configuration of services.stalwart-mail itself happens directly in the
# nixos-configs/ consumer files (stalwart.nix for invariant pieces,
# stalwart-facts.nix for facts-derived pieces).
#
# This module exists only to add a small extension to the upstream
# `services.stalwart-mail` namespace: a way to contribute custom
# spam-filter rules that actually fire.  See the option descriptions for
# the architectural reason that requires its own machinery.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.stalwart-mail;

  hasExtras = cfg.extraSpamFilterRules != { } || cfg.extraSpamFilterScores != { };

  # The merge implementation is parked until we have a working approach.
  # The naive `builtins.fromTOML` path fails because the bundled
  # spam-filter.toml uses curly-brace inline-set syntax that no strict
  # TOML parser accepts — see
  # https://github.com/LoganBarnett/stalwart-spam-filter-toml-bug for
  # the reproducer.  The replacement will use a runCommand-based
  # text-merge (sed-fix the broken syntax, then cat the bundled file
  # with our additions appended) — to be wired up once landed.
in
{
  options.services.stalwart-mail = {
    extraSpamFilterRules = mkOption {
      type = types.attrsOf (types.attrsOf types.anything);
      default = { };
      example = lib.literalExpression ''
        {
          STWT_MY_CUSTOM_RULE = {
            enable = true;
            scope = "any";
            priority = 2000;
            condition = [
              { "if" = "from.domain == 'example.com'"; "then" = "'FROM_EXAMPLE'"; }
              { "else" = false; }
            ];
          };
        }
      '';
      description = ''
        Custom spam-filter rules merged into Stalwart's bundled rule set
        at evaluation time.

        Stalwart 0.14 loads its working rule set from the URL given by
        `services.stalwart-mail.settings.spam-filter.resource` (by
        default the bundled file in
        `pkgs.stalwart-mail.spam-filter`).  Rules declared in local TOML
        under `services.stalwart-mail.settings.spam-filter.rule.<id>`
        do appear in the running configuration but are silently NOT
        evaluated — the rule engine consults only the resource.  This
        is a documented gap; the upstream maintainer's note at
        <https://github.com/stalwartlabs/stalwart/discussions/789>
        recommends "creat[ing] a local copy of the spam rules and
        modify[ing] them" until the API for additive rules ships.

        This option implements that workaround declaratively: at eval
        time we read the bundled `spam-filter.toml`, deep-merge entries
        from this option into its `[spam-filter.rule.<id>]` section,
        write the result to a derivation in the Nix store, and point
        `spam-filter.resource` at that file.  Rules contributed here
        therefore actually fire.

        Each value follows the bundled file's per-rule schema:
        `{ enable = true; scope = "any"; priority = <int>; condition =
        [ { "if" = "<expr>"; "then" = "'TAG_NAME'"; } { "else" =
        false; } ]; }`.  When a rule emits a new `TAG_NAME`, declare
        its score in `extraSpamFilterScores` so the classifier weights
        it correctly.

        Removable once upstream lands additive-rule support.
      '';
    };

    extraSpamFilterScores = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = lib.literalExpression ''
        {
          "FROM_EXAMPLE" = "-1.0";
          "SUSPICIOUS_TAG" = "2.5";
        }
      '';
      description = ''
        Score (numeric string, matching the bundled format) for each
        tag emitted by rules in `extraSpamFilterRules`.  Merged
        per-key into the bundled spam-filter's score table at the same
        eval-time step that merges the rules.

        Stalwart's classifier sums all matching tag scores for a
        message; the result in `X-Spam-Status` decides whether the
        message is filed into Junk Mail.  Typical weights: `-1.5` to
        `-0.5` for confidence boosts, `0.5` to `2.0` for suspicion
        bumps, `5.0` and above for near-certain spam markers.

        See the description of `extraSpamFilterRules` for why
        custom-tag scores need to be merged at this layer rather
        than declared in local TOML.
      '';
    };
  };

  # Warn loudly if any consumer sets the extras options before the merge
  # is wired up, so we don't pretend to honor them.
  config.warnings = lib.optional (cfg.enable && hasExtras) ''
    services.stalwart-mail.extraSpamFilterRules / extraSpamFilterScores are
    set but the underlying merge into the bundled spam-filter resource is
    not yet implemented (the bundled file is invalid TOML; see
    https://github.com/LoganBarnett/stalwart-spam-filter-toml-bug).  Those
    options are inert until that's resolved.
  '';
}
