// Collect Z-Wave node health from zwave-js-server and write Prometheus
// textfile metrics.  See zwave-metrics.nix for the systemd wiring and
// zwave-alertmanager-alerts.nix for the alerts that consume these.
//
// The zwave-js-server websocket (zwave.serverEnabled in zwave-js-ui's
// settings) is the same interface OpenHAB consumes, and it is the driver's
// own view of the network — no MQTT gateway or REST scraping involved.  One
// full state dump per run, no subscription kept open.
//
// Environment:
//   ZWAVE_WS_URL  websocket URL (default ws://127.0.0.1:3004)
//   OUTPUT_PATH   final path of the .prom file (written atomically via a
//                 .tmp sibling)
//
// On any failure the script still writes the file, with
// zwave_metrics_success 0 and no node metrics, then exits non-zero.  A
// missing or frozen file is covered by the absent() and mtime alerts.
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const wsUrl = process.env.ZWAVE_WS_URL ?? 'ws://127.0.0.1:3004';
const outputPath = process.env.OUTPUT_PATH;
if (!outputPath) {
  console.error('OUTPUT_PATH is required');
  process.exit(2);
}

// Prometheus exposition format label escaping: backslash, quote, newline.
function escapeLabel(value) {
  return String(value)
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n');
}

function labelSet(node) {
  const label = node.deviceConfig?.label ?? '';
  const name = node.name ?? '';
  return (
    `node="${node.nodeId}"` +
    `,label="${escapeLabel(label)}"` +
    `,name="${escapeLabel(name)}"`
  );
}

function writeMetrics(lines) {
  const tmpPath = path.join(
    path.dirname(outputPath),
    path.basename(outputPath) + '.tmp',
  );
  fs.writeFileSync(tmpPath, lines.join('\n') + '\n');
  // Atomic replacement prevents node_exporter reading a partial file.
  fs.renameSync(tmpPath, outputPath);
}

function writeFailure(error) {
  console.error('zwave metrics collection failed:', error.message ?? error);
  writeMetrics([
    '# HELP zwave_metrics_success Whether the last zwave metrics collection succeeded.',
    '# TYPE zwave_metrics_success gauge',
    'zwave_metrics_success 0',
  ]);
  process.exit(1);
}

const timeout = setTimeout(
  () => writeFailure(new Error('timed out after 20s')),
  20000,
);

let msgId = 0;
const pending = new Map();
const ws = new WebSocket(wsUrl);
function send(cmd) {
  return new Promise((resolve, reject) => {
    const messageId = String(++msgId);
    pending.set(messageId, { resolve, reject });
    ws.send(JSON.stringify({ messageId, ...cmd }));
  });
}
ws.onerror = (event) => writeFailure(new Error(event.message ?? 'websocket error'));
ws.onmessage = async (event) => {
  const msg = JSON.parse(event.data);
  if (msg.type === 'version') {
    try {
      await send({
        command: 'set_api_schema',
        schemaVersion: msg.maxSchemaVersion,
      });
      const result = await send({ command: 'start_listening' });
      const lines = [
        '# HELP zwave_metrics_success Whether the last zwave metrics collection succeeded.',
        '# TYPE zwave_metrics_success gauge',
        'zwave_metrics_success 1',
        '# HELP zwave_node_dead Node is marked Dead by the controller.',
        '# TYPE zwave_node_dead gauge',
      ];
      const nodes = result.state.nodes;
      for (const node of nodes) {
        // Node status enum: 0 Unknown, 1 Asleep, 2 Awake, 3 Dead, 4 Alive.
        // Asleep is the healthy resting state for battery devices, so only
        // Dead counts against a node.
        lines.push(`zwave_node_dead{${labelSet(node)}} ${node.status === 3 ? 1 : 0}`);
      }
      lines.push(
        '# HELP zwave_node_battery_percent Battery level reported by the node.',
        '# TYPE zwave_node_battery_percent gauge',
      );
      for (const node of nodes) {
        const battery = node.values?.find(
          (v) =>
            v.commandClass === 128 &&
            v.property === 'level' &&
            v.endpoint === 0 &&
            typeof v.value === 'number',
        );
        if (battery) {
          lines.push(`zwave_node_battery_percent{${labelSet(node)}} ${battery.value}`);
        }
      }
      lines.push(
        '# HELP zwave_node_water_leak Water alarm sensor status is anything other than idle.',
        '# TYPE zwave_node_water_leak gauge',
      );
      for (const node of nodes) {
        // Notification CC (113) "Water Alarm" / "Sensor status": 0 is idle,
        // 2 is "Water leak detected".  Any non-idle state counts as a leak.
        const leak = node.values?.find(
          (v) =>
            v.commandClass === 113 &&
            v.property === 'Water Alarm' &&
            v.propertyKey === 'Sensor status' &&
            typeof v.value === 'number',
        );
        if (leak) {
          lines.push(`zwave_node_water_leak{${labelSet(node)}} ${leak.value !== 0 ? 1 : 0}`);
        }
      }
      clearTimeout(timeout);
      writeMetrics(lines);
      process.exit(0);
    } catch (error) {
      writeFailure(error);
    }
  } else if (msg.type === 'result') {
    const p = pending.get(msg.messageId);
    if (!p) return;
    pending.delete(msg.messageId);
    if (msg.success) {
      p.resolve(msg.result);
    } else {
      p.reject(new Error(JSON.stringify(msg)));
    }
  }
};
