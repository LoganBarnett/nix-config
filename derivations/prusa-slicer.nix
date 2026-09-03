{
  stdenv,
  lib,
  binutils,
  fetchFromGitHub,
  fetchpatch,
  cmake,
  pkg-config,
  wrapGAppsHook3,
  # Pinned: 2.8.0 (and through 2.9.x) does not build with boost 1.87+, which
  # removed the deprecated boost::asio::io_service alias.  See upstream issue:
  # https://github.com/prusa3d/PrusaSlicer/issues/13799
  boost186,
  cereal,
  cgal_5,
  curl,
  darwin,
  dbus,
  eigen,
  expat,
  glew,
  glib,
  glib-networking,
  gmp,
  gtk3,
  hicolor-icon-theme,
  ilmbase,
  libpng,
  mpfr,
  nanosvg,
  nlopt,
  opencascade-occt_7_6,
  openvdb,
  pcre,
  qhull,
  rcodesign,
  tbb_2022,
  wxGTK32,
  xmlstarlet,
  xorg,
  libbgcode,
  heatshrink,
  catch2,
  withSystemd ? lib.meta.availableOn stdenv.hostPlatform systemd,
  systemd,
  wxGTK-override ? null,
}:
let
  opencascade-occt = opencascade-occt_7_6;
  wxGTK-prusa = wxGTK32.overrideAttrs (old: rec {
    pname = "wxwidgets-prusa3d-patched";
    version = "3.2.0";
    configureFlags = old.configureFlags ++ [ "--disable-glcanvasegl" ];
    patches = [ ./wxWidgets-Makefile.in-fix.patch ];
    src = fetchFromGitHub {
      owner = "prusa3d";
      repo = "wxWidgets";
      rev = "78aa2dc0ea7ce99dc19adc1140f74c3e2e3f3a26";
      hash = "sha256-rYvmNmvv48JSKVT4ph9AS+JdstnLSRmcpWz1IdgBzQo=";
      fetchSubmodules = true;
    };
  });
  nanosvg-fltk = nanosvg.overrideAttrs (old: rec {
    pname = "nanosvg-fltk";
    version = "unstable-2022-12-22";

    src = fetchFromGitHub {
      owner = "fltk";
      repo = "nanosvg";
      rev = "abcd277ea45e9098bed752cf9c6875b533c0892f";
      hash = "sha256-WNdAYu66ggpSYJ8Kt57yEA4mSTv+Rvzj9Rm1q765HpY=";
    };
  });
  openvdb_tbb_2022 = openvdb;
  wxGTK-override' =
    if wxGTK-override == null then wxGTK-prusa else wxGTK-override;

  patches = [
    (fetchpatch {
      url = "https://raw.githubusercontent.com/gentoo/gentoo/master/media-gfx/prusaslicer/files/prusaslicer-2.8.0-missing-includes.patch";
      hash = "sha256-/R9jv9zSP1lDW6IltZ8V06xyLdxfaYrk3zD6JRFUxHg=";
    })
    (fetchpatch {
      url = "https://raw.githubusercontent.com/gentoo/gentoo/master/media-gfx/prusaslicer/files/prusaslicer-2.8.0-fixed-linking.patch";
      hash = "sha256-G1JNdVH+goBelag9aX0NctHFVqtoYFnqjwK/43FVgvM=";
    })
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "prusa-slicer";
  version = "2.8.0";
  inherit patches;

  src = fetchFromGitHub {
    owner = "prusa3d";
    repo = "PrusaSlicer";
    hash = "sha256-A/uxNIEXCchLw3t5erWdhqFAeh6nudcMfASi+RoJkFg=";
    rev = "version_${finalAttrs.version}";
  };

  # required for GCC 14
  postPatch = ''
    substituteInPlace src/libslic3r/Arrange/Core/DataStoreTraits.hpp \
      --replace-fail \
      "WritableDataStoreTraits<ArrItem>::template set" \
      "WritableDataStoreTraits<ArrItem>::set"
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    wrapGAppsHook3
    wxGTK-override'
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    rcodesign
    xmlstarlet
  ];

  buildInputs = [
    binutils
    boost186
    cereal
    cgal_5
    curl
    dbus
    eigen
    expat
    glew
    glib
    glib-networking
    gmp
    gtk3
    hicolor-icon-theme
    ilmbase
    libpng
    mpfr
    nanosvg-fltk
    nlopt
    opencascade-occt
    openvdb_tbb_2022
    pcre
    qhull
    tbb_2022
    wxGTK-override'
    xorg.libX11
    libbgcode
    heatshrink
    catch2
  ]
  ++ lib.optionals withSystemd [
    systemd
  ];

  strictDeps = true;

  separateDebugInfo = true;

  # The build system uses custom logic - defined in
  # cmake/modules/FindNLopt.cmake in the package source - for finding the nlopt
  # library, which doesn't pick up the package in the nix store.  We
  # additionally need to set the path via the NLOPT environment variable.
  NLOPT = nlopt;

  # prusa-slicer uses dlopen on `libudev.so` at runtime
  NIX_LDFLAGS = lib.optionalString withSystemd "-ludev";

  prePatch = ''
    # Since version 2.5.0 of nlopt we need to link to libnlopt, as libnlopt_cxx
    # now seems to be integrated into the main lib.
    sed -i 's|nlopt_cxx|nlopt|g' cmake/modules/FindNLopt.cmake

    # Disable slic3r_jobs_tests.cpp as the test fails sometimes
    sed -i 's|slic3r_jobs_tests.cpp||g' tests/slic3rutils/CMakeLists.txt

    # prusa-slicer expects the OCCTWrapper shared library in the same folder as
    # the executable when loading STEP files. We force the loader to find it in
    # the usual locations (i.e. LD_LIBRARY_PATH) instead. See the manpage
    # dlopen(3) for context.
    if [ -f "src/libslic3r/Format/STEP.cpp" ]; then
      substituteInPlace src/libslic3r/Format/STEP.cpp \
        --replace 'libpath /= "OCCTWrapper.so";' 'libpath = "OCCTWrapper.so";'
    fi
    # https://github.com/prusa3d/PrusaSlicer/issues/9581
    if [ -f "cmake/modules/FindEXPAT.cmake" ]; then
      rm cmake/modules/FindEXPAT.cmake
    fi

    # Fix resources folder location on macOS
    substituteInPlace src/PrusaSlicer.cpp \
      --replace "#ifdef __APPLE__" "#if 0"

    # Stash the upstream macOS Info.plist template and entitlements for the
    # darwin bundle steps.  cmake switches into a build subdir, so capturing
    # them here (at source root) avoids relying on phase-specific cwd later.
    cp src/platform/osx/Info.plist.in "$TMPDIR/Info.plist.in"
    cp src/platform/osx/entitlements.plist "$TMPDIR/entitlements.plist"
  '';

  cmakeFlags = [
    "-DSLIC3R_STATIC=0"
    "-DSLIC3R_FHS=1"
    "-DSLIC3R_GTK=3"
    "-Wno-dev"
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];

  postInstall = ''
    ln -s "$out/bin/PrusaSlicer" "$out/bin/prusa-gcodeviewer"

    mkdir -p "$out/lib"
    mv -v $out/bin/*.* $out/lib/

    mkdir -p "$out/share/pixmaps/"
    ln -s "$out/share/PrusaSlicer/icons/PrusaSlicer.png" "$out/share/pixmaps/PrusaSlicer.png"
    ln -s "$out/share/PrusaSlicer/icons/PrusaSlicer-gcodeviewer_192px.png" "$out/share/pixmaps/PrusaSlicer-gcodeviewer.png"
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    # Lay down a macOS .app bundle so PrusaSlicer can be launched from Finder
    # and Launchpad once nix-darwin or Home Manager installs it into an
    # Applications folder.
    app="$out/Applications/PrusaSlicer.app"
    plist="$app/Contents/Info.plist"
    mkdir --parents "$app/Contents/MacOS" "$app/Contents/Resources"

    # The binary lives in the bundle so that the process macOS sees at runtime
    # is the bundle's own.  Privacy grants (TCC) and the running application's
    # identity, name and icon are derived from the executable that is actually
    # running; a bundle whose launcher execs a binary outside itself shows up as
    # that outside binary.  bin/ points back into the bundle so the CLI is the
    # same executable.
    mv "$out/bin/PrusaSlicer" "$app/Contents/MacOS/PrusaSlicer"
    ln --symbolic "$app/Contents/MacOS/PrusaSlicer" "$out/bin/PrusaSlicer"

    # Use upstream's Info.plist template so file associations (.stl, .3mf,
    # .gcode, etc.) and the prusaslicer:// URL handler match Prusa's
    # official builds.
    install --mode=644 "$TMPDIR/Info.plist.in" "$plist"
    substituteInPlace "$plist" \
      --replace-fail "@SLIC3R_APP_KEY@"  "PrusaSlicer" \
      --replace-fail "@SLIC3R_APP_NAME@" "PrusaSlicer" \
      --replace-fail "@SLIC3R_BUILD_ID@" "${finalAttrs.version}"

    # Upstream's template sets LSEnvironment (an ASAN knob, meaningless in a
    # non-sanitizer build).  Any LSEnvironment entry makes LaunchServices
    # demand a "secure launch", which requires a code signature carrying spawn
    # constraints.  Without one the launch fails with permErr (-54):
    # CoreServicesUIAgent logs "Launch requires secure launch with spawn
    # constraints, but none are present or valid", and Finder reports that it
    # does not have permission to open "(null)".  Seen on macOS 15.
    #
    # The template's CFBundleIdentifier also carries a trailing slash, which
    # Apple disallows in bundle identifiers and which would otherwise become the
    # signed identity established in postFixup.
    #
    # Edits apply in order: the LSEnvironment value dict goes first, while the
    # key still anchors the following-sibling axis.
    ls_env_key='/plist/dict/key[text()="LSEnvironment"]'
    bundle_id_key='/plist/dict/key[text()="CFBundleIdentifier"]'
    xmlstarlet edit --inplace \
      --delete "$ls_env_key/following-sibling::*[1]" \
      --delete "$ls_env_key" \
      --update "$bundle_id_key/following-sibling::string[1]" \
        --value 'com.prusa3d.slic3r' \
      "$plist"
    # --delete is a silent no-op when nothing matches.
    remaining=$(
      xmlstarlet select --template --value-of "count($ls_env_key)" "$plist"
    )
    if [ "$remaining" != 0 ]; then
      echo "LSEnvironment survived removal from Info.plist" >&2
      exit 1
    fi

    # Copies rather than symlinks into share/: the bundle is sealed in
    # postFixup and the seal records a symlink as a symlink.  nix-darwin
    # installs bundles into /Applications with rsync --copy-unsafe-links, which
    # turns links pointing outside the bundle into regular files, so a symlinked
    # icon would fail seal verification once installed.
    for icns in PrusaSlicer.icns stl.icns gcode.icns bgcode.icns; do
      icns_src="$out/share/PrusaSlicer/icons/$icns"
      if [ -f "$icns_src" ]; then
        install --mode=644 "$icns_src" "$app/Contents/Resources/$icns"
      fi
    done
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "$out/lib"
    )
  '';

  # On darwin the only executable is wrapped by hand inside the bundle (see
  # postFixup).  Left on, wrapGAppsHook would also wrap the bin/ symlink that
  # points into the bundle, stacking a second wrapper on top.
  dontWrapGApps = stdenv.hostPlatform.isDarwin;

  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    app="$out/Applications/PrusaSlicer.app"

    # makeBinaryWrapper leaves a Mach-O at the bundle's advertised executable
    # path.  A shell script there cannot carry a code signature at all, so the
    # bundle could neither be sealed below nor pass a LaunchServices secure
    # launch.
    wrapGApp "$app/Contents/MacOS/PrusaSlicer"

    # Sign the bundle so macOS has a code identity for it.  Up to this point the
    # binaries carry only the ad-hoc signature the linker emits: an identifier
    # equal to the file name, no entitlements, Info.plist not bound, no sealed
    # resources.  With no identity to attach a privacy (TCC) grant to, macOS
    # keys grants by the executable's absolute path, which is a store path that
    # changes on every rebuild.  Each rebuild then leaves a dead row behind in
    # System Settings, and a grant added there by hand is inert, because it is
    # keyed by bundle identifier while the binary identifies itself by file
    # name.  PrusaSlicer hits this for Local Network access when talking to
    # PrusaLink or OctoPrint printers.
    #
    # Sign the .app directory, not the binaries inside it.  Signing a Mach-O
    # file cannot seal the bundle, and an unsealed Info.plist means macOS cannot
    # trust CFBundleIdentifier, which is the identity this exists to establish.
    # Signing the directory binds Info.plist and generates CodeResources, and
    # rcodesign signs the nested Mach-O behind the wrapper as part of the same
    # pass.
    #
    # rcodesign rather than the host /usr/bin/codesign or sigtool: the host
    # codesign is an impure path gated behind allowed-impure-host-deps and fails
    # outright under the sandbox, and sigtool has no concept of a bundle.  The
    # result passes Apple's `codesign --verify --deep --strict`.
    #
    # Upstream's entitlements only disable library validation, which upstream
    # needs for 3Dconnexion drivers and which also covers the store dylibs, each
    # carrying its own ad-hoc signature.
    #
    # This is the last step of fixupPhase: after stripping, which would
    # invalidate an earlier signature, and after wrapGApp, so the wrapper is
    # covered.
    #
    # This does not make grants survive rebuilds.  TCC stores the designated
    # requirement presented when a grant is made, and an ad-hoc signature's
    # designated requirement is its cdhash, so any rebuild forces re-approval.
    # Only a certificate-anchored requirement survives content changes, and no
    # derivation can carry a private key without publishing it in the store.
    rcodesign sign \
      --binary-identifier com.prusa3d.slic3r \
      --entitlements-xml-file "$TMPDIR/entitlements.plist" \
      "$app"
  '';

  doCheck = true;

  checkPhase = ''
    runHook preCheck

    ctest \
      --force-new-ctest-process \
      -E 'libslic3r_tests|sla_print_tests'

    runHook postCheck
  '';

  meta =
    with lib;
    {
      description = "G-code generator for 3D printer";
      homepage = "https://github.com/prusa3d/PrusaSlicer";
      license = licenses.agpl3Plus;
      maintainers = with maintainers; [
        tweber
        tmarkus
      ];
      platforms = platforms.unix;
    }
    // lib.optionalAttrs (stdenv.hostPlatform.isDarwin) {
      mainProgram = "PrusaSlicer";
    };
})
