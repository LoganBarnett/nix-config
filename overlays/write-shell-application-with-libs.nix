################################################################################
# writeShellApplication for scripts that source a shared bash library.
#
# `libs` maps an environment variable name to a library file.  The file is
# copied to the store and exported under that name at runtime, so the script
# sources the exact copy it was checked against rather than whatever is in the
# invoking user's home.  The script keeps a fallback so it still runs directly
# outside Nix:
#
#   # shellcheck source=bash-logging
#   source "${BASH_LOGGING:-$HOME/.bash-logging}"
#
# The directive names the library by basename.  All libraries are collected
# into one directory handed to shellcheck as --source-path, so the sourced
# functions are analysed with the script instead of being skipped as an
# unknown external file.
################################################################################
final: prev: {
  writeShellApplicationWithLibs =
    {
      libs,
      runtimeEnv ? { },
      extraShellCheckFlags ? [ ],
      ...
    }@args:
    let
      inherit (final) lib;
      sourcePath = final.linkFarm "${args.name}-shellcheck-sources" (
        lib.mapAttrsToList (_: file: {
          name = baseNameOf file;
          path = file;
        }) libs
      );
    in
    final.writeShellApplication (
      builtins.removeAttrs args [ "libs" ]
      // {
        runtimeEnv = runtimeEnv // lib.mapAttrs (_: file: "${file}") libs;
        extraShellCheckFlags = extraShellCheckFlags ++ [
          "--external-sources"
          "--source-path=${sourcePath}"
        ];
      }
    );
}
