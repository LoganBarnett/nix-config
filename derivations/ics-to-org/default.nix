{
  cacert,
  coreutils,
  curl,
  ical2orgpy,
  writeShellApplicationWithLibs,
}:
writeShellApplicationWithLibs {
  name = "ics-to-org";
  libs.BASH_LOGGING = ../../bash-logging;
  runtimeInputs = [
    coreutils
    curl
    ical2orgpy
  ];
  # nixpkgs' Darwin curl ships no CA bundle and launchd sets no SSL_CERT_FILE,
  # so the script is told where one lives.
  runtimeEnv.CURL_CA_BUNDLE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  text = builtins.readFile ./ics-to-org;
}
