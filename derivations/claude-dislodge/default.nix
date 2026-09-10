{
  claude-code,
  coreutils,
  gawk,
  gnugrep,
  jq,
  lib,
  lsof,
  procps,
  stdenv,
  writeShellApplication,
}:
writeShellApplication {
  name = "claude-dislodge";
  runtimeInputs = [
    # ps, memory_pressure, and sysctl on macOS are system binaries at fixed
    # paths and necessarily come from outside Nix: the procps ps cannot read
    # rss there.
    claude-code
    coreutils
    gawk
    gnugrep
    jq
  ]
  ++ lib.optionals stdenv.isDarwin [ lsof ]
  ++ lib.optionals stdenv.isLinux [ procps ];
  text = builtins.readFile ./claude-dislodge;
}
