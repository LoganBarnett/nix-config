################################################################################
# Generic MCP (Model Context Protocol) server registry.  This file is
# deliberately client-neutral: `programs.mcp.servers` writes the tool-agnostic
# ~/.config/mcp/mcp.json.
#
# Secret handling: the generated config lands in the world-readable Nix store,
# so no token may be inlined here.  Each credentialed server's `command` is a
# wrapper that reads its token at run time from the agenix secret declared in
# agnostic-configs/mcp-credentials.nix, which is also what imports this file.
# The paths resolve through `osConfig`, so a host that imports this file
# without declaring the secrets fails at evaluation instead of shipping a
# server that dies at spawn.
#
# The default posture is read-only.  Write access and session elevation are
# intentionally out of scope for this file.
################################################################################
{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  secrets = osConfig.age.secrets;

  # Emits the preamble that loads a credential file into `token`, failing
  # loudly rather than proceeding with an empty value.
  #
  # The readability test comes before the read on purpose: under `set -e` a
  # failed command substitution in a plain assignment aborts the script, so a
  # check placed after the assignment would never run.
  fileToken = path: ''
    if [ ! -r ${lib.escapeShellArg path} ]; then
      printf 'FATAL: credential file %s is missing or unreadable.\n' \
        ${lib.escapeShellArg path} >&2
      exit 1
    fi
    token="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg path})"
    if [ -z "$token" ]; then
      printf 'FATAL: credential file %s is empty.\n' \
        ${lib.escapeShellArg path} >&2
      exit 1
    fi
  '';

  # gitea-mcp exposes only single-dash flags (it uses Go's `flag` package), so
  # they are documented here: `-t stdio` selects the stdio transport, `-host`
  # is the Gitea base URL, and `-read-only` blocks every mutating tool.  The
  # token is passed via GITEA_ACCESS_TOKEN rather than the `-token` flag so it
  # never appears in the process argument list.  gitea-mcp also speaks to
  # Forgejo, which is API-compatible; swap to a forgejo-mcp package after the
  # migration if one lands in nixpkgs.
  gitea-mcp = pkgs.writeShellScript "gitea-mcp-wrapped" ''
    set -euo pipefail
    ${fileToken secrets.gitea-mcp-token.path}
    export GITEA_ACCESS_TOKEN="$token"
    exec ${pkgs.gitea-mcp-server}/bin/gitea-mcp \
      -t stdio \
      -host ${lib.escapeShellArg "https://gitea.proton"} \
      -read-only
  '';

  # github-mcp-server reads GITHUB_PERSONAL_ACCESS_TOKEN from the environment;
  # `--read-only` restricts it to non-mutating tools, and the default toolset
  # (context, repos, issues, pull_requests, users) is left in place.
  github-mcp = pkgs.writeShellScript "github-mcp-wrapped" ''
    set -euo pipefail
    ${fileToken secrets.github-mcp-token.path}
    export GITHUB_PERSONAL_ACCESS_TOKEN="$token"
    exec ${pkgs.github-mcp-server}/bin/github-mcp-server stdio --read-only
  '';

  # mcp-grafana covers the Prometheus need through Grafana's datasource tools
  # (and additionally exposes dashboards, Loki, and search).  `-disable-write`
  # and `-disable-admin` keep it read-only; narrow further with `-enabled-tools`
  # if the surface is too broad.  Only single-dash flags exist (Go `flag`
  # package): `-t stdio` selects the stdio transport.  The URL is public; the
  # service-account token is exported under both env names mcp-grafana has
  # accepted across versions so it works regardless of which this build
  # honors.  The token should belong to a Viewer-role service account so the
  # credential itself is read-only, not just the tool flags.
  grafana-mcp = pkgs.writeShellScript "grafana-mcp-wrapped" ''
    set -euo pipefail
    ${fileToken secrets.grafana-mcp-token.path}
    export GRAFANA_URL=${lib.escapeShellArg "https://grafana.proton"}
    export GRAFANA_API_KEY="$token"
    export GRAFANA_SERVICE_ACCOUNT_TOKEN="$token"
    exec ${pkgs.mcp-grafana}/bin/mcp-grafana \
      -t stdio \
      -disable-write \
      -disable-admin
  '';
in
{
  programs.claude-code.enableMcpIntegration = true;
  programs.mcp = {
    enable = true;
    servers = {
      # The one server that needs no credential, and so no wrapper: it shells
      # out to git against whatever repository a tool call names.
      #
      # The mutation tools are permitted by default, but that's okay because we
      # want to allow that mutation.
      git = {
        type = "stdio";
        command = "${pkgs.mcp-server-git}/bin/mcp-server-git";
      };
      gitea = {
        type = "stdio";
        command = "${gitea-mcp}";
      };
      github = {
        type = "stdio";
        command = "${github-mcp}";
      };
      grafana = {
        type = "stdio";
        command = "${grafana-mcp}";
      };

      # Pending:
      #
      #   postgres  Deferred by choice — worth doing deliberately with the
      #             read-only role + structured-ops + session-elevation design
      #             rather than a quick read-only entry.  Also needs a
      #             reachability decision, since silicon serves PostgreSQL over
      #             a local Unix socket only (tunnel / run-on-silicon / TCP).
      #
      #   ntfy      No packaged server; needs a small stdio MCP over the publish
      #             API at https://ntfy.proton (token as an issued secret next
      #             to the others in agnostic-configs/mcp-credentials.nix).
      #             This is the one write-capable server.
    };
  };
}
