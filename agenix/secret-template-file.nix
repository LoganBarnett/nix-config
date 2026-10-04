################################################################################
# A agenix-rekey generator for using a template to substitute secrets into a
# file that itself is also considered secret.
#
# Secrets generated here should be added to the service's `restartTriggers`.
#
# The settings structure expected is:
# {
#   template: String;
# }
# or
# {
#   templateFile: String;
# }
# The dependencies pulled in will substitute based on their name.
# The template string is in the form of %name% but one day I may make that
# configurable.
#
# `replace-secret` reads the replacement from a file instead of an argument, so
# the decrypted dependency never appears in /proc/<pid>/cmdline.  It also edits
# in place, hence staging the template in a temporary file and writing the
# result to stdout, which is what agenix-rekey captures.  It strips surrounding
# newlines from the secret, matching what command substitution would have done.
################################################################################
{ lib, ... }:
{
  age.generators.template-file =
    {
      decrypt,
      deps,
      file,
      name,
      pkgs,
      secret,
      ...
    }:
    let
      template = (
        secret.settings.template or (builtins.readFile secret.settings.templateFile)
      );
    in
    ''
      staged="$(${pkgs.coreutils}/bin/mktemp)"
      trap '${pkgs.coreutils}/bin/rm --force "$staged"' EXIT
      printf '%s' ${lib.escapeShellArg template} > "$staged"
      ${lib.strings.concatStringsSep "\n" (
        builtins.map (dep: ''
          ${pkgs.replace-secret}/bin/replace-secret \
            ${lib.escapeShellArg "%${dep.name}%"} \
            <(${decrypt} ${lib.escapeShellArg dep.file}) \
            "$staged"
        '') deps
      )}
      ${pkgs.coreutils}/bin/cat "$staged"
    '';
}
