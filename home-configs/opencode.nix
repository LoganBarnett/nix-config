################################################################################
# Manage opencode, an AI coding agent TUI.  Configuration here is intentionally
# minimal: no provider/model is wired up yet because no API credentials exist.
# When credentials arrive, fill in the `provider` / `model` scaffold below.
#
# A note on vim bindings, since that was a goal: opencode's prompt input is
# readline/emacs-style and has no full vim insert mode yet (upstream feature
# requests anomalyco/opencode#6537 and #4092).  What ships by default is
# vim-style *navigation* of the message area (b, f, ctrl-u, ctrl-d, and `i` to
# focus the editor like vim insert), so most muscle memory already works.  For
# real vim editing of longer prompts, press ctrl-e in the TUI to compose in
# $EDITOR — set EDITOR to your vim of choice and that buffer is fully vim.
#
# UI concerns (theme, keybind remaps) live in ~/.config/opencode/tui.json in
# opencode 1.x, which this home-manager module does NOT manage — the `settings`
# option below only writes opencode.json, and the opencode.json schema rejects
# `theme`/`keybinds` keys.  Manage tui.json via xdg.configFile if remaps are
# ever wanted; the defaults already cover the vim navigation above.
################################################################################
{ pkgs, ... }:
{
  programs.opencode = {
    enable = true;
    package = pkgs.opencode;
    settings = {
      "$schema" = "https://opencode.ai/config.json";

      # NOTE: the self-updater is already hard-disabled at the binary level —
      # the vendored derivation's wrapper sets OPENCODE_DISABLE_AUTOUPDATE=true
      # (see ../derivations/opencode/default.nix), which cannot be undone by
      # config — so no `autoupdate` key is needed here.

      # No provider/model yet — opencode runs but has nothing to talk to until
      # an API is configured.  When that day comes, set `model` to a
      # "<provider>/<model>" string and add the matching `provider` block.  Two
      # likely shapes, mirroring how aider-chat.nix points at self-hosted
      # ollama:
      #
      #   model = "anthropic/claude-opus-4-8";
      #
      # or an OpenAI-compatible local endpoint (ollama, llama.cpp, etc.):
      #
      #   provider.ollama = {
      #     npm = "@ai-sdk/openai-compatible";
      #     options.baseURL = "https://ollama.${facts.network.domain}/v1";
      #     models."deepseek-coder:1.3b" = { };
      #   };
      #   model = "ollama/deepseek-coder:1.3b";
    };
  };
}
