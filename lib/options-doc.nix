################################################################################
# Renders an option set as a list of option documents, for docs/nix-options.org.
#
# `host` names a configuration that declares the option set and `prefix` is the
# dotted option path.  The result is what lib.optionAttrSetToDocList yields,
# minus internal and hidden options, sorted by name, with declaration paths
# made relative to the repository root so documents can link to them.
################################################################################
{ lib, configurations }:
host: prefix:
let
  cfg = configurations.${host} or (throw "No host named ${host}.");
  opts = lib.attrByPath (lib.splitString "." prefix) (throw
    "No option set ${prefix} on ${host}."
  ) cfg.options;
  public = o: o.visible && !o.internal;
  # Declarations arrive as /nix/store/<hash>-source/<path>.  Only <path> is
  # useful to a reader.
  relative =
    p:
    let
      s = toString p;
      m = builtins.match "/nix/store/[^/]+/(.*)" s;
    in
    if m == null then s else builtins.head m;
in
lib.sort (a: b: a.name < b.name) (
  map (o: o // { declarations = map relative o.declarations; }) (
    lib.filter public (lib.optionAttrSetToDocList opts)
  )
)
