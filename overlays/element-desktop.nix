################################################################################
# element-desktop needs Darwin fixes on top of the pinned nixpkgs.
#
# 1. Nx socket path.  element-desktop builds with Nx, which talks to its task
# runners over Unix domain sockets placed under os.tmpdir() as
# <tmp>/<20-char hash>/fp<id>.sock.  Nx enforces a 95-character budget on that
# path.  macOS itself caps socket paths at 104 bytes.  Lix keeps build
# directories under /nix/var/nix/builds, so this build's TMPDIR is
# /nix/var/nix/builds/nix-build-element-desktop-1.12.18.drv-0/b and the socket
# path overflows the budget.  The build fails in build:ts with "Attempted to
# open socket that exceeds the maximum socket length".  nixpkgs never sees
# this because Nix's build directories live under /private/tmp, nine
# characters shorter, which leaves just enough room.  Point NX_SOCKET_DIR at a
# short, build-private directory instead.  Newer Nx releases refuse a socket
# directory that is the OS temp directory itself or one shared with other
# users, so this must be a fresh directory the build user owns.
#
# 2. Stripping.  The Darwin fixup phase strips everything under
# $out/Applications.  The Electron bundle is prebuilt release binaries plus asar
# archives, locale packs and a Windows icon.ico that llvm-objcopy misreads as a
# COFF object and segfaults on.  xargs reports the signal and the strip hook
# fails the build.  Nothing in the bundle benefits from stripping, so skip it.
#
# Drop this overlay once the pinned nixpkgs carries all fixes.
################################################################################
final: prev:
if !prev.stdenv.hostPlatform.isDarwin then
  { }
else
  {
    element-desktop = prev.element-desktop.overrideAttrs (old: {
      dontStrip = true;
      preBuild = (old.preBuild or "") + ''
        NX_SOCKET_DIR="$(mktemp -d /tmp/nx.XXXXXX)"
        export NX_SOCKET_DIR
      '';
      postBuild = (old.postBuild or "") + ''
        rm -rf "$NX_SOCKET_DIR"
      '';
    });
  }
