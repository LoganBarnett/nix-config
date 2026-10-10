################################################################################
# Credentials for the MCP servers registered in home-configs/mcp.nix, and the
# only place that imports that registry: a host gets the servers and their
# tokens together or not at all.
#
# Each token is a read-only credential the service issued to one host, hence
# the host-id in the file name: revoking one host's token must not touch any
# other host's.  Store a freshly issued token with
# `agenix edit secrets/issued/<service>-<host-id>-mcp-token.age`, then rekey.
################################################################################
{ host-id, ... }:
let
  issuedToken = service: {
    rekeyFile = ../secrets/issued/${service}-${host-id}-mcp-token.age;
    # The wrappers run as the login user, not as root.
    mode = "0400";
    owner = "logan";
  };
in
{
  age.secrets.gitea-mcp-token = issuedToken "gitea";
  age.secrets.github-mcp-token = issuedToken "github";
  home-manager.users.logan.imports = [ ../home-configs/mcp.nix ];
}
