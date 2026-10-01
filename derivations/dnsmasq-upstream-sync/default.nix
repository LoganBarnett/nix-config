{
  coreutils,
  gawk,
  gnused,
  writeShellApplication,
}:
writeShellApplication {
  name = "dnsmasq-upstream-sync";
  runtimeInputs = [
    coreutils
    gawk
    gnused
  ];
  text = builtins.readFile ./dnsmasq-upstream-sync;
}
