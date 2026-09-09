################################################################################
# VENDORED, UNALTERED COPY of nixpkgs master's claude-code derivation:
#   pkgs/by-name/cl/claude-code/package.nix
#   @ nixpkgs commit a96171f71f0a (2026-08-31, "claude-code: fetch
#   zstd-compressed distribution")
#
# Everything below this banner is byte-for-byte upstream — do NOT edit it.  Only
# this header was added.  manifest.zst.json and update.sh alongside are that
# commit's copies too, kept so the directory mirrors upstream and the
# derivation's defaults stay valid.  Re-sync by re-copying the directory from a
# newer nixpkgs master and updating the commit reference above.
#
# Why we vendor it instead of using pkgs.claude-code directly:
#   Claude Code ships as a native binary, which master's derivation installs
#   from Anthropic's release manifest.  Our pinned nixpkgs (25.11) still builds
#   an old release as a Node.js bundle.  Master reads the version and
#   per-platform checksums through the `manifest` argument, and
#   overlays/claude-code.nix fills that from static.nix, so the pin lives in
#   static.nix (bumped by scripts/claude-code-update) while the derivation
#   itself tracks master.  That argument is the only point of deviation.
################################################################################
# NOTE: Use the following command to update the package
# ```sh
# nix-shell maintainers/scripts/update.nix --arg commit true --arg predicate '(path: pkg: builtins.elem path [["claude-code"] ["vscode-extensions" "anthropic" "claude-code"]])'
# ```
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  autoPatchelfHook,
  alsa-lib,
  procps,
  ripgrep,
  bubblewrap,
  socat,
  zstd,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  manifest ? lib.importJSON ./manifest.zst.json,
}:
let
  stdenv = stdenvNoCC;
  baseUrl = "https://downloads.claude.ai/claude-code-releases";
  platformKey = "${stdenv.hostPlatform.node.platform}-${stdenv.hostPlatform.node.arch}";
  platformManifestEntry = manifest.platforms.${platformKey};
in
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-code";
  inherit (manifest) version;

  src = fetchurl {
    url = "${baseUrl}/${finalAttrs.version}/${platformKey}/${platformManifestEntry.binary}";
    sha256 = platformManifestEntry.checksum;
  };

  dontUnpack = true;
  dontBuild = true;
  __noChroot = stdenv.hostPlatform.isDarwin;
  # otherwise the bun runtime is executed instead of the binary
  dontStrip = true;

  nativeBuildInputs = [
    makeBinaryWrapper
    zstd
  ]
  ++ lib.optionals stdenv.hostPlatform.isElf [ autoPatchelfHook ];

  strictDeps = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    unzstd -q $src -o $out/bin/claude
    chmod 755 $out/bin/claude

    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      ${lib.optionalString stdenv.hostPlatform.isLinux ''
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ alsa-lib ]} \
      ''}--prefix PATH : ${
        lib.makeBinPath (
          [
            # claude-code uses [node-tree-kill](https://github.com/pkrumins/node-tree-kill) which requires procps's pgrep(darwin) or ps(linux)
            procps
            # https://code.claude.com/docs/en/troubleshooting#search-and-discovery-issues
            ripgrep
          ]
          # the following packages are required for the sandbox to work (Linux only)
          ++ lib.optionals stdenv.hostPlatform.isLinux [
            bubblewrap
            socat
          ]
        )
      }

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    writableTmpDirAsHomeHook
    versionCheckHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  versionCheckProgramArg = "--version";

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://github.com/anthropics/claude-code";
    downloadPage = "https://claude.com/product/claude-code";
    changelog = "https://github.com/anthropics/claude-code/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    maintainers = with lib.maintainers; [
      adeci
      malo
      markus1189
      mirkolenz
      omarjatoi
      oskarwires
      xiaoxiangmoe
    ];
    mainProgram = "claude";
  };
})
