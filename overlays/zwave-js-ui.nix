# zwave-js-ui hardcodes the zwave-js driver's forceConsole log setting to
# false outside of Docker (api/lib/utils.ts buildLogConfig), so under systemd —
# where stdout is not a TTY — driver logs never reach journald.  The only stock
# way to force console logging is zwave.options.logConfig in settings.json, but
# anything under zwave.options is handed to the driver by reference, and
# zwave-js-ui later attaches live winston transports to that very object
# (api/lib/ZwaveClient.ts: `zwaveOptions.logConfig.transports =
# [logTransport]`).  The transports make the in-memory settings circular, so
# GET /api/settings crashes in res.json() with "Converting circular structure
# to JSON" — an unhandled rejection that never answers the request.  The
# reverse proxy 504s after 60 seconds and the UI hangs forever on its loading
# screen.
#
# This patch adds a root-level `zwave.forceConsole` setting that buildLogConfig
# honors, so console logging can be forced declaratively without ever touching
# zwave.options.  Candidate for upstreaming to zwave-js/zwave-js-ui.
final: prev: {
  zwave-js-ui = prev.zwave-js-ui.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./zwave-js-ui-force-console.patch ];
  });
}
