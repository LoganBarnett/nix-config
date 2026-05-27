################################################################################
# gpclient derivation vendored from nixpkgs-unstable.  Inherits version, src,
# and cargoHash from gpauth so the rapid-updater bumps both simultaneously.
#
# v2.5.x packaging notes (these are what made the in-place overrideAttrs
# approach impractical and motivated full vendoring):
#   - OpenConnect is statically linked from crates/openconnect/deps/openconnect
#     and built inside the Rust derivation, so we need autotools and the
#     full C toolchain it depends on (gnutls, libxml2, lz4, p11-kit).
#   - Several hardcoded paths moved out of crates/gpapi/src/lib.rs and
#     crates/common/src/vpn_utils.rs into crates/common/src/constants.rs
#     and crates/openconnect/src/vpn_utils.rs respectively.  Substitutions
#     in postPatch reflect the new layout.
#   - constants.rs has both Linux (/usr/bin/*) and macOS (/opt/homebrew/bin/*)
#     paths gated by cfg attributes.  The blanket /opt/homebrew/ -> $out/
#     rewrite redirects gpclient/gpservice/gpgui-helper into our own out
#     correctly, but the same rewrite would point gpauth at $out/bin/gpauth
#     (which does not exist — gpauth is a separate derivation).  The
#     explicit /opt/homebrew/bin/gpauth substitution must come first.
#
# See README.org §Rapid Package Updates and scripts/gpclient-update.
################################################################################
{
  lib,
  rustPlatform,
  stdenv,
  atk,
  autoconf,
  automake,
  cairo,
  glib,
  glib-networking,
  gnutls,
  gpauth,
  gtk3,
  libtool,
  libxml2,
  lz4,
  makeBinaryWrapper,
  openssl,
  p11-kit,
  pango,
  perl,
  pkg-config,
  vpnc-scripts,
}:

rustPlatform.buildRustPackage {
  pname = "gpclient";

  inherit (gpauth)
    cargoHash
    src
    version
    ;

  buildAndTestSubdir = "apps/gpclient";

  nativeBuildInputs = [
    makeBinaryWrapper
    perl
    pkg-config

    # used to build vendored openconnect
    autoconf
    automake
    libtool
  ];
  buildInputs = [
    glib
    glib-networking
    gpauth
    openssl

    # used for vendored openconnect
    gnutls
    libxml2
    lz4
    p11-kit
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    atk
    cairo
    gtk3
    pango
  ];

  postPatch = ''
    substituteInPlace crates/openconnect/src/vpn_utils.rs \
      --replace-fail /etc/vpnc/vpnc-script ${vpnc-scripts}/bin/vpnc-script \
      --replace-fail /usr/libexec/gpclient/hipreport.sh $out/libexec/gpclient/hipreport.sh

    substituteInPlace crates/common/src/constants.rs \
      --replace-fail /usr/bin/gpclient $out/bin/gpclient \
      --replace-fail /usr/bin/gpservice $out/bin/gpservice \
      --replace-fail /usr/bin/gpauth ${gpauth}/bin/gpauth \
      --replace-fail /opt/homebrew/bin/gpauth ${gpauth}/bin/gpauth \
      --replace-fail /opt/homebrew/ $out/
  '';

  postInstall = ''
    cp -r packaging/files/usr/libexec $out/libexec

    substituteInPlace $out/libexec/gpclient/hipreport.sh \
      --replace-fail /usr/bin/gpclient $out/bin/gpclient
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    cp -r packaging/files/usr/lib $out/lib
    substituteInPlace $out/lib/NetworkManager/dispatcher.d/pre-down.d/gpclient.down \
      --replace-fail /usr/bin/gpclient $out/bin/gpclient
  '';

  postFixup = ''
    wrapProgram "$out/bin/gpclient" \
      --prefix GIO_EXTRA_MODULES : ${glib-networking}/lib/gio/modules
  '';
}
