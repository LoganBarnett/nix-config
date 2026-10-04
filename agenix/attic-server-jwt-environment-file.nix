################################################################################
# Generator for atticd's JWT signing secret in systemd EnvironmentFile form.
#
# atticd and atticadm read ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64, the base64 of
# a PKCS#1 RSA private key in PEM form.  Units that read this file should list
# the secret in restartTriggers.
################################################################################
{ ... }:
{
  age.generators.attic-server-jwt-environment-file =
    { pkgs, ... }:
    ''
      set -euo pipefail
      printf 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=%s' \
        "$(${pkgs.openssl}/bin/openssl genrsa -traditional 4096 \
          | ${pkgs.coreutils}/bin/base64 --wrap 0)"
    '';
}
