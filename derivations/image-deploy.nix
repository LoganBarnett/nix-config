{
  coreutils,
  disk-detachable,
  firmware-host-key-add,
  image-create,
  zstd,
  writeShellApplication,
  ...
}:
writeShellApplication {
  name = "image-deploy";
  runtimeInputs = [
    # The script uses sync --file-system, which is a GNU coreutils flag that
    # macOS' /bin/sync lacks, so pin GNU coreutils rather than relying on
    # whatever the ambient PATH provides.
    coreutils
    disk-detachable
    firmware-host-key-add
    image-create
    zstd
  ];
  text = builtins.readFile ../scripts/image-deploy;
}
