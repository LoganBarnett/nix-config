################################################################################
# Shell preamble that loads a credential file into `token`, failing loudly
# rather than proceeding with an empty value.  Shared by the MCP wrapper
# scripts, which read their agenix secrets at run time so that nothing secret
# lands in the Nix store.
################################################################################
{ coreutils, lib }:
{
  # The readability test comes before the read on purpose: under `set -e` a
  # failed command substitution in a plain assignment aborts the script, so a
  # check placed after the assignment would never run.
  fileToken = path: ''
    if [ ! -r ${lib.escapeShellArg path} ]; then
      printf 'FATAL: credential file %s is missing or unreadable.\n' \
        ${lib.escapeShellArg path} >&2
      exit 1
    fi
    token="$(${coreutils}/bin/cat ${lib.escapeShellArg path})"
    if [ -z "$token" ]; then
      printf 'FATAL: credential file %s is empty.\n' \
        ${lib.escapeShellArg path} >&2
      exit 1
    fi
  '';
}
