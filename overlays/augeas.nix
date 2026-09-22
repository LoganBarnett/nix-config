################################################################################
# augeas does not build on macOS: `make check` aborts in one of the bundled
# gnulib tests.
#
# augeas runs the bundled GNU portability library (gnulib) test suite as part
# of `make check`.  The failing test is gnulib's multithread-safety test for
# nl_langinfo() (gnulib/tests/test-nl_langinfo-mt), which aborts under the
# nixos-25.11 toolchain on macOS.  It exercises Apple's libc, not augeas, so
# its verdict says nothing about whether augtool works.
#
# nixpkgs master already passes --disable-gnulib-tests on Darwin
# (NixOS/nixpkgs#492596), which drops only the gnulib/tests directory from
# `make check` and leaves augeas' own tests running.  The backport to
# release-25.11 (NixOS/nixpkgs#495405) was closed as not reproducing on stable
# at the time, so the pinned nixpkgs lacks it.  Delete this overlay once the
# pinned nixpkgs carries the flag.
################################################################################
final: prev:
if !prev.stdenv.hostPlatform.isDarwin then
  { }
else
  {
    augeas = prev.augeas.overrideAttrs (old: {
      configureFlags = (old.configureFlags or [ ]) ++ [ "--disable-gnulib-tests" ];
    });
  }
