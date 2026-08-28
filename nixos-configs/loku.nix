################################################################################
# Loku is a local video browser and player.  It serves two libraries: the yt-dlp
# download tree Metube populates, and the MakeMKV disc rips that krypton's Kodi
# also reads over NFS.  Loku writes derived .compat.mp4 copies and .jpg
# thumbnails beside the master files, so library paths must be writable by the
# service.
################################################################################
{ facts, ... }:
{
  networking.dnsAliases = [ "loku" ];
  services.loku-server = {
    enable = true;
    # Attribute names become URL segments (/browse/<name>), and the first in
    # lexicographic order is the default landing library — "downloads" sorts
    # before "movies", keeping the yt-dlp tree as the landing page.
    libraries = {
      downloads = {
        path = "/tank/data/media";
        kind = "downloads";
      };
      movies = {
        path = "/tank/data/kodi-media";
        kind = "discs";
      };
    };
  };

  # Compat copies are derived and reproducible from the masters, and for
  # Blu-rays they are near master-size (the video stream is remuxed, not
  # re-encoded) — backing them up would roughly double the disc library's backup
  # footprint for zero recovery value.  Thumbnails stay backed up: they are
  # small, and restoring them avoids a regeneration pass.
  services.restic.backups.nfsProvider.exclude = [ "*.compat.mp4" ];

  services.https.fqdns."loku.${facts.network.domain}" = {
    enable = true;
    # loku-server uses systemd socket activation; the socket lives at
    # /run/loku-server/loku-server.sock, which matches the serviceNameForSocket
    # convention.  https.nix adds nginx to the loku-server group so it can
    # connect to the group-readable socket.
    serviceNameForSocket = "loku-server";
  };

  # Ensure the library directories are mounted and initialised before the
  # service starts.  setup-media-dir.service creates /tank/data/media, and
  # setup-shared-media-acls.service applies the media-shared ACLs to
  # /tank/data/kodi-media.
  systemd.services.loku-server = {
    after = [
      "tank-data.mount"
      "setup-media-dir.service"
      "setup-shared-media-acls.service"
    ];
    requires = [ "tank-data.mount" ];
  };

  # Grant loku-server access to files created under the media-shared group ACL.
  # Without this the service user cannot read downloads that were written by
  # other members of media-shared (e.g. metube), nor write sidecars beside them.
  users.users.loku-server.extraGroups = [ "media-shared" ];
}
