{
  config,
  facts,
  host-id,
  ...
}:
{
  services.garage-queue-worker.workers.ollama = {
    enable = true;
    integrations.ollama.enable = true;
    # TCP loopback instead of the default unix socket: the worker is a launchd
    # user agent whose socket cannot be opened by nginx's unprivileged
    # workers, and macOS has no systemd-style group/umask plumbing to fix
    # that.
    observe.socket = null;
    settings = {
      worker = {
        id = host-id;
        server_url = "https://ollama.${facts.network.domain}";
        poll_interval_ms = 1000;
      };
    };
  };

  services.https.fqdns."${host-id}-ollama-worker.${facts.network.domain}" = {
    internalPort = config.services.garage-queue-worker.workers.ollama.observe.port;
  };

  networking.dnsAliases = [ "${host-id}-ollama-worker" ];
  networking.monitors = [ "garage-queue-worker" ];
}
