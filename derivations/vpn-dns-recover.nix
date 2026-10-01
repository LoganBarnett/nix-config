{
  coreutils,
  gawk,
  gnugrep,
  nettools,
  writeShellApplicationWithLibs,
}:
writeShellApplicationWithLibs {
  name = "vpn-dns-recover";
  libs.BASH_LOGGING = ../bash-logging;
  runtimeInputs = [
    coreutils
    gawk
    gnugrep
    nettools
  ];
  text = builtins.readFile ../scripts/vpn-dns-recover;
}
