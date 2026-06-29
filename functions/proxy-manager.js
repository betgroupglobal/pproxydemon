// =============================================================================
// Edge Gateway self-hosted proxy manager — Pangolin / frp / direct tunnel backends
// Manages proxy tunnels, routing, and health without Cloudflare dependencies.
//
// Backends:
//   - direct   — built-in TCP/HTTP reverse proxy (zero deps, always available)
//   - pangolin — WireGuard-based, self-hosted control plane
//   - frp      — Fast Reverse Proxy, lightweight TCP/HTTP/UDP
// =============================================================================

import http from "node:http";
import net from "node:net";
import fs from "node:fs";
import { spawn } from "node:child_process";
import { EventEmitter } from "node:events";

// ── Configuration ────────────────────────────────────────────────────────────

const CONFIG_PATH = process.env.CONFIG_PATH || "/app/config.toml";
const PROXY_PORT = parseInt(process.env.PROXY_PORT || "7000", 10);
const API_PORT = parseInt(process.env.PROXY_API_PORT || "7001", 10);

// Pangolin config (WireGuard-based self-hosted control plane)
const PANGOLIN_CONTROL_PLANE = process.env.PANGOLIN_CONTROL_PLANE || "";
const PANGOLIN_AUTH_TOKEN = process.env.PANGOLIN_AUTH_TOKEN || "";
const PANGOLIN_ENABLED = !!(PANGOLIN_CONTROL_PLANE && PANGOLIN_AUTH_TOKEN);

// frp config (Fast Reverse Proxy)
const FRPS_ADDR = process.env.FRPS_ADDR || "";
const FRPS_PORT = parseInt(process.env.FRPS_PORT || "7000", 10);
const FRP_AUTH_TOKEN = process.env.FRP_AUTH_TOKEN || "";
const FRP_ENABLED = !!(FRPS_ADDR && FRP_AUTH_TOKEN);

let config = {};

function loadConfig() {
  try {
    const raw = fs.readFileSync(CONFIG_PATH, "utf-8");
    config = parseToml(raw);
    console.log(`[proxy-manager] config loaded from ${CONFIG_PATH}`);
  } catch (err) {
    console.warn(`[proxy-manager] config load failed (${err.message}), using defaults`);
    config = getDefaultConfig();
  }
}

function getDefaultConfig() {
  return {
    server: { bindAddr: "0.0.0.0", bindPort: 7000 },
    health: { path: "/health", intervalSeconds: 30, timeoutSeconds: 5 },
    gateway: { apiPort: 8787, healthPath: "/health", corsOrigins: ["*"] },
    auth: { apiKey: "", token: "" },
    proxies: [],
  };
}

// ── Backend availability check during startup ───────────────────────────────

console.log(`[proxy-manager] backends: direct=available pangolin=${PANGOLIN_ENABLED ? "configured" : "unavailable"} frp=${FRP_ENABLED ? "configured" : "unavailable"}`);

// Minimal TOML parser (handles the subset used in config.toml)
function parseToml(raw) {
  const out = { proxies: [] };
  let section = null;
  let currentProxy = null;

  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    // Section headers
    const sectionMatch = trimmed.match(/^\[([^\]]+)\]$/);
    if (sectionMatch) {
      section = sectionMatch[1];
      if (section === "server" || section === "health" || section === "gateway" || section === "auth" || section === "tunnel") {
        out[section] = out[section] || {};
      }
      if (section === "proxies") {
        currentProxy = {};
        out.proxies.push(currentProxy);
      }
      continue;
    }

    // Key-value pairs
    const kvMatch = trimmed.match(/^(\w+)\s*=\s*(.+)$/);
    if (kvMatch) {
      const key = kvMatch[1];
      let value = kvMatch[2].trim();
      // Strip quotes, resolve env vars
      value = value.replace(/^["']|["']$/g, "");
      value = value.replace(/\$\{(\w+):-\}/g, (_, env) => process.env[env] || "");
      value = value.replace(/\$\{(\w+)\}/g, (_, env) => process.env[env] || "");

      // Parse typed values
      if (value === "true" || value === "false") value = value === "true";
      else if (/^\d+$/.test(value)) value = parseInt(value, 10);

      if (currentProxy && section === "proxies") {
        currentProxy[key] = value;
      } else if (section) {
        out[section][key] = value;
      } else {
        out[key] = value;
      }
    }
  }

  return out;
}

// ── Proxy tunnel state ──────────────────────────────────────────────────────

const tunnels = new Map(); // id → { id, name, type, localHost, localPort, remotePort, status, startedAt, bytesIn, bytesOut, conns }
let nextTunnelId = 1;

const events = new EventEmitter();

/** Supported tunneling backends. */
const TUNNEL_BACKENDS = ["direct", "pangolin", "frp"];

function createTunnel(def) {
  const backend = TUNNEL_BACKENDS.includes(def.backend) ? def.backend : "direct";
  const tunnel = {
    id: nextTunnelId++,
    name: def.name || `tunnel-${nextTunnelId}`,
    backend,                       // "direct" | "pangolin" | "frp"
    type: def.type || "tcp",       // "tcp" | "http" | "udp"
    localHost: def.localIP || "127.0.0.1",
    localPort: def.localPort || 0,
    remotePort: def.remotePort || 0,
    status: "stopped",
    startedAt: null,
    bytesIn: 0,
    bytesOut: 0,
    conns: 0,
    server: null,      // net.Server for direct backend
    child: null,       // child_process for pangolin/frp backends
    logPath: null,     // log file path for external backends
    configPath: null,  // generated config path for external backends
  };

  tunnels.set(tunnel.id, tunnel);
  return tunnel;
}

/** Generate a Pangolin WireGuard client config (INI format) for this tunnel. */
function generatePangolinConfig(tunnel) {
  return [
    "[Interface]",
    `PrivateKey = AUTO_GENERATE_ON_CONTROL_PLANE`,
    `Address = 10.100.${(tunnel.id % 254) + 1}.2/32`,
    `DNS = 1.1.1.1`,
    "",
    "[Peer]",
    `PublicKey = SERVER_PUBKEY_FROM_CONTROL_PLANE`,
    `Endpoint = ${PANGOLIN_CONTROL_PLANE.replace(/^https?:\/\//, "")}:51820`,
    `AllowedIPs = 0.0.0.0/0`,
    `PersistentKeepalive = 25`,
  ].join("\n");
}

/** Generate an frp client config (TOML format) for this tunnel. */
function generateFrpConfig(tunnel) {
  return [
    "# frp client config — auto-generated by proxy-manager",
    `# Tunnel: ${tunnel.name} (${tunnel.type})`,
    "",
    "[common]",
    `server_addr = "${FRPS_ADDR}"`,
    `server_port = ${FRPS_PORT}`,
    `token = "${FRP_AUTH_TOKEN}"`,
    "",
    `[${tunnel.name}]`,
    `type = "${tunnel.type}"`,
    `local_ip = "${tunnel.localHost}"`,
    `local_port = ${tunnel.localPort}`,
    `remote_port = ${tunnel.remotePort}`,
    "use_encryption = true",
    "use_compression = true",
  ].join("\n");
}

/** Start a tunnel via Pangolin (WireGuard-based). Spawns wg-quick or equivalent. */
function startPangolinTunnel(tunnel) {
  if (!PANGOLIN_ENABLED) return { ok: false, error: "Pangolin control plane not configured" };

  // Write WireGuard config
  const configPath = `/tmp/pangolin-tunnel-${tunnel.id}.conf`;
  const configContent = generatePangolinConfig(tunnel);
  try {
    fs.writeFileSync(configPath, configContent, "utf-8");
    tunnel.configPath = configPath;
  } catch (err) {
    return { ok: false, error: `Failed to write Pangolin config: ${err.message}` };
  }

  // Register with Pangolin control plane first
  const baseUrl = PANGOLIN_CONTROL_PLANE.replace(/\/+$/, "");
  const body = JSON.stringify({
    name: tunnel.name,
    localPort: tunnel.localPort,
    remotePort: tunnel.remotePort,
    type: tunnel.type,
  });

  // Fire-and-forget the control-plane registration + wg-quick up
  const logPath = `/tmp/pangolin-tunnel-${tunnel.id}.log`;
  const logStream = fs.openSync(logPath, "w");
  tunnel.logPath = logPath;

  try {
    const child = spawn("bash", ["-c", [
      `# Register with Pangolin control plane`,
      `curl -s -X POST "${baseUrl}/api/v1/tunnels" \\`,
      `  -H "Authorization: Bearer ${PANGOLIN_AUTH_TOKEN}" \\`,
      `  -H "Content-Type: application/json" \\`,
      `  -d '${body}' > /dev/null 2>&1 || true`,
      ``,
      `# Bring up WireGuard interface`,
      `wg-quick up "${configPath}" 2>&1 || echo "[pangolin] wg-quick failed (may need root)"`,
    ].join("\n")], {
      stdio: ["ignore", logStream, logStream],
      detached: false,
    });

    tunnel.child = child;
    child.on("exit", (code) => {
      console.log(`[pangolin] tunnel "${tunnel.name}" exited with code ${code}`);
      if (tunnel.status === "running") tunnel.status = "degraded";
    });
  } catch (err) {
    fs.closeSync(logStream);
    tunnel.logPath = null;
    return { ok: false, error: `Failed to spawn Pangolin: ${err.message}` };
  }

  tunnel.status = "running";
  tunnel.startedAt = Date.now();
  console.log(`[pangolin] tunnel "${tunnel.name}" started on WireGuard`);
  events.emit("tunnel:started", tunnel);
  return { ok: true };
}

/** Start a tunnel via frp (Fast Reverse Proxy). Spawns frpc with generated config. */
function startFrpTunnel(tunnel) {
  if (!FRP_ENABLED) return { ok: false, error: "frp server not configured" };

  // Write frp client config
  const configPath = `/tmp/frpc-tunnel-${tunnel.id}.toml`;
  const configContent = generateFrpConfig(tunnel);
  try {
    fs.writeFileSync(configPath, configContent, "utf-8");
    tunnel.configPath = configPath;
  } catch (err) {
    return { ok: false, error: `Failed to write frp config: ${err.message}` };
  }

  const logPath = `/tmp/frpc-tunnel-${tunnel.id}.log`;
  const logStream = fs.openSync(logPath, "w");
  tunnel.logPath = logPath;

  try {
    // Spawn frpc with the generated config
    // frpc reads TOML config: frpc -c /tmp/frpc-tunnel-N.toml
    const child = spawn("frpc", ["-c", configPath], {
      stdio: ["ignore", logStream, logStream],
      detached: false,
    });

    tunnel.child = child;
    child.on("exit", (code) => {
      console.log(`[frp] tunnel "${tunnel.name}" frpc exited with code ${code}`);
      if (tunnel.status === "running") tunnel.status = "degraded";
    });
    child.on("error", (err) => {
      console.error(`[frp] tunnel "${tunnel.name}" frpc error: ${err.message}`);
      // frp binary not found — fall back to direct backend
      if (err.code === "ENOENT") {
        console.warn(`[frp] frpc binary not found, falling back to direct tunnel`);
        tunnel.backend = "direct";
        fs.closeSync(logStream);
        return startDirectTunnel(tunnel);
      }
    });
  } catch (err) {
    fs.closeSync(logStream);
    tunnel.logPath = null;
    return { ok: false, error: `Failed to spawn frpc: ${err.message}` };
  }

  tunnel.status = "running";
  tunnel.startedAt = Date.now();
  console.log(`[frp] tunnel "${tunnel.name}" started via frpc → ${FRPS_ADDR}:${FRPS_PORT}`);
  events.emit("tunnel:started", tunnel);
  return { ok: true };
}

/** Start a direct TCP tunnel (built-in). */
function startDirectTcpTunnel(tunnel) {
  tunnel.server = net.createServer((clientSocket) => {
    tunnel.conns++;
    const backendSocket = net.createConnection({ host: tunnel.localHost, port: tunnel.localPort }, () => {
      clientSocket.pipe(backendSocket);
      backendSocket.pipe(clientSocket);
    });

    clientSocket.on("data", (chunk) => (tunnel.bytesIn += chunk.length));
    backendSocket.on("data", (chunk) => (tunnel.bytesOut += chunk.length));

    backendSocket.on("error", () => { clientSocket.destroy(); });
    clientSocket.on("error", () => { backendSocket.destroy(); });
    clientSocket.on("close", () => { if (tunnel.conns > 0) tunnel.conns--; });
  });

  tunnel.server.listen(tunnel.remotePort, config.server?.bindAddr || "0.0.0.0", () => {
    tunnel.status = "running";
    tunnel.startedAt = Date.now();
    console.log(`[direct] tunnel "${tunnel.name}" started — tcp:${tunnel.remotePort} → ${tunnel.localHost}:${tunnel.localPort}`);
    events.emit("tunnel:started", tunnel);
  });

  tunnel.server.on("error", (err) => {
    tunnel.status = "error";
    console.error(`[direct] tunnel "${tunnel.name}" error: ${err.message}`);
  });
}

/** Start a direct HTTP tunnel (built-in). */
function startDirectHttpTunnel(tunnel) {
  tunnel.server = http.createServer((req, res) => {
    tunnel.conns++;
    const options = {
      hostname: tunnel.localHost,
      port: tunnel.localPort,
      path: req.url,
      method: req.method,
      headers: { ...req.headers, host: `${tunnel.localHost}:${tunnel.localPort}` },
    };

    const proxyReq = http.request(options, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
      proxyRes.on("data", (chunk) => (tunnel.bytesOut += chunk.length));
    });

    req.on("data", (chunk) => (tunnel.bytesIn += chunk.length));
    req.pipe(proxyReq);

    proxyReq.on("error", () => {
      res.writeHead(502);
      res.end("Bad Gateway");
    });
    req.on("close", () => { if (tunnel.conns > 0) tunnel.conns--; });
  });

  tunnel.server.listen(tunnel.remotePort, config.server?.bindAddr || "0.0.0.0", () => {
    tunnel.status = "running";
    tunnel.startedAt = Date.now();
    console.log(`[direct] tunnel "${tunnel.name}" started — http:${tunnel.remotePort} → ${tunnel.localHost}:${tunnel.localPort}`);
    events.emit("tunnel:started", tunnel);
  });
}

/** Start a direct tunnel (TCP or HTTP) — the built-in backend. */
function startDirectTunnel(tunnel) {
  try {
    if (tunnel.type === "http") {
      startDirectHttpTunnel(tunnel);
    } else {
      startDirectTcpTunnel(tunnel);
    }
    return { ok: true };
  } catch (err) {
    tunnel.status = "error";
    return { ok: false, error: err.message };
  }
}

function startTunnel(tunnel) {
  if (tunnel.status === "running") return { ok: false, error: "already running" };

  switch (tunnel.backend) {
    case "pangolin":
      return startPangolinTunnel(tunnel);
    case "frp":
      return startFrpTunnel(tunnel);
    case "direct":
    default:
      return startDirectTunnel(tunnel);
  }
}

function stopTunnel(tunnel) {
  // Stop direct backend server
  if (tunnel.server) {
    tunnel.server.close();
    tunnel.server = null;
  }

  // Stop external backend child process
  if (tunnel.child) {
    try {
      if (!tunnel.child.killed) {
        tunnel.child.kill("SIGTERM");
        setTimeout(() => {
          try { if (tunnel.child && !tunnel.child.killed) tunnel.child.kill("SIGKILL"); } catch { /* dead */ }
        }, 3000);
      }
    } catch { /* already dead */ }
    tunnel.child = null;
  }

  // Close log stream
  if (tunnel.logPath) {
    try { fs.unlinkSync(tunnel.logPath); } catch { /* already deleted */ }
    tunnel.logPath = null;
  }

  // Clean up config file
  if (tunnel.configPath) {
    try { fs.unlinkSync(tunnel.configPath); } catch { /* already deleted */ }
    tunnel.configPath = null;
  }

  tunnel.status = "stopped";
  tunnel.startedAt = null;
  events.emit("tunnel:stopped", tunnel);
  return { ok: true };
}

function getTunnelStats(tunnel) {
  const uptime = tunnel.startedAt ? Math.round((Date.now() - tunnel.startedAt) / 1000) : 0;
  return {
    id: tunnel.id,
    name: tunnel.name,
    backend: tunnel.backend,
    type: tunnel.type,
    remotePort: tunnel.remotePort,
    localHost: tunnel.localHost,
    localPort: tunnel.localPort,
    status: tunnel.status,
    uptime,
    bytesIn: tunnel.bytesIn,
    bytesOut: tunnel.bytesOut,
    activeConns: tunnel.conns,
    hasChildProcess: !!tunnel.child,
    configPath: tunnel.configPath || null,
    logPath: tunnel.logPath || null,
  };
}

// ── Proxy server instance management (launch/stop/list child processes) ──────

const proxyServers = new Map(); // id → { id, name, config, port, pid, status, startedAt, health, logs }
let nextServerId = 1;

/**
 * Launch a new proxy tunnel server instance as a child process.
 * Spawns `node proxy-manager.js` with a custom config TOML on a dedicated port.
 */
function launchProxyServer(def) {
  const id = nextServerId++;
  const port = def.port || (12000 + id);
  const name = def.name || `proxy-server-${id}`;

  // Write a temporary config file for this instance
  const configPath = `/tmp/proxy-server-${id}.toml`;
  const configContent = def.config || generateServerConfig(name, port, def.tunnels || []);

  try {
    fs.writeFileSync(configPath, configContent, "utf-8");
  } catch (err) {
    return { ok: false, error: `Failed to write config: ${err.message}` };
  }

  const logPath = `/tmp/proxy-server-${id}.log`;
  const logStream = fs.openSync(logPath, "w");

  let child;
  try {
    // Spawn a dedicated proxy-manager process with the instance config.
    // Use the file path directly (ESM-compatible — no require()).
    child = spawn(
      process.execPath,
      [new URL(import.meta.url).pathname],
      {
        cwd: process.cwd(),
        stdio: ["ignore", logStream, logStream],
        detached: false,
        env: {
          ...process.env,
          CONFIG_PATH: configPath,
          PROXY_PORT: String(port),
          PROXY_API_PORT: String(port + 1),
        },
      },
    );
  } catch (err) {
    fs.closeSync(logStream);
    return { ok: false, error: `Failed to spawn process: ${err.message}` };
  }

  const instance = {
    id,
    name,
    port,
    apiPort: port + 1,
    pid: child.pid,
    status: "launching",
    startedAt: Date.now(),
    configPath,
    logPath,
    child,
    logStream,
    health: null,
    tunnelCount: def.tunnels?.length || 0,
  };

  child.on("exit", (code) => {
    instance.status = code === 0 ? "stopped" : "crashed";
    instance.health = null;
    console.log(`[proxy-manager] server "${name}" (pid ${instance.pid}) exited with code ${code}`);
    events.emit("server:stopped", instance);
  });

  child.on("error", (err) => {
    instance.status = "crashed";
    instance.health = null;
    console.error(`[proxy-manager] server "${name}" error: ${err.message}`);
  });

  // Mark as running after a short startup window
  setTimeout(() => {
    if (instance.status === "launching") {
      instance.status = "running";
      // Quick health probe
      checkServerHealth(instance);
      events.emit("server:started", instance);
    }
  }, 2000);

  proxyServers.set(id, instance);

  // Periodic health checks
  const healthInterval = setInterval(() => checkServerHealth(instance), 15000);
  instance._healthInterval = healthInterval;

  return { ok: true, data: getServerStats(instance) };
}

function checkServerHealth(instance) {
  if (instance.status !== "running") return;
  const url = `http://127.0.0.1:${instance.apiPort}/health`;
  const req = http.get(url, { timeout: 3000 }, (res) => {
    let data = "";
    res.on("data", (chunk) => (data += chunk));
    res.on("end", () => {
      try {
        instance.health = JSON.parse(data);
        instance.status = "running";
      } catch {
        instance.health = { status: "degraded", raw: data.slice(0, 200) };
      }
    });
  });
  req.on("error", () => {
    if (instance.status === "running") {
      instance.status = "degraded";
      instance.health = null;
    }
  });
  req.on("timeout", () => {
    req.destroy();
    instance.status = "degraded";
  });
}

function stopProxyServer(id) {
  const instance = proxyServers.get(id);
  if (!instance) return { ok: false, error: "server not found" };
  if (instance.status === "stopped") return { ok: false, error: "already stopped" };

  // Clear health check interval
  if (instance._healthInterval) {
    clearInterval(instance._healthInterval);
  }

  // Kill the child process
  try {
    if (instance.child && !instance.child.killed) {
      instance.child.kill("SIGTERM");
      // Force kill after 5s if still alive
      setTimeout(() => {
        try { if (instance.child && !instance.child.killed) instance.child.kill("SIGKILL"); } catch { /* already dead */ }
      }, 5000);
    }
  } catch (err) {
    // Process may already be dead
  }

  instance.status = "stopped";
  instance.health = null;

  // Close log stream
  try { if (instance.logStream) fs.closeSync(instance.logStream); } catch { /* already closed */ }

  // Clean up temp config
  try { fs.unlinkSync(instance.configPath); } catch { /* already deleted */ }

  events.emit("server:stopped", instance);
  return { ok: true };
}

function getServerStats(instance) {
  return {
    id: instance.id,
    name: instance.name,
    port: instance.port,
    apiPort: instance.apiPort,
    pid: instance.pid,
    status: instance.status,
    uptime: instance.startedAt ? Math.round((Date.now() - instance.startedAt) / 1000) : 0,
    health: instance.health,
    tunnelCount: instance.tunnelCount,
    startedAt: instance.startedAt,
  };
}

function generateServerConfig(name, port, tunnels) {
  const lines = [
    "# Auto-generated by proxy-manager (Grok Build 0.1)",
    `# Server: ${name}`,
    "",
    "[server]",
    `bindAddr = "0.0.0.0"`,
    `bindPort = ${port}`,
    "",
    "[health]",
    `path = "/health"`,
    `intervalSeconds = 30`,
    `timeoutSeconds = 5`,
    "",
    "[gateway]",
    `apiPort = ${port + 1}`,
    `healthPath = "/health"`,
    `corsOrigins = ["*"]`,
    "",
    "[auth]",
    `apiKey = "${process.env.API_KEY || ""}"`,
    `token = "${process.env.PROXY_TOKEN || ""}"`,
    "",
  ];

  for (const t of tunnels) {
    lines.push("[[proxies]]");
    lines.push(`name = "${t.name || `tunnel-${Math.random().toString(36).slice(2, 8)}`}"`);
    lines.push(`type = "${t.type || "tcp"}"`);
    lines.push(`localIP = "${t.localIP || "127.0.0.1"}"`);
    lines.push(`localPort = ${t.localPort || 3000}`);
    lines.push(`remotePort = ${t.remotePort || (port + 100 + tunnels.indexOf(t))}`);
    lines.push(`autoStart = ${t.autoStart !== false ? "true" : "false"}`);
    lines.push("");
  }

  return lines.join("\n");
}

// ── Proxy API server (internal, for gateway queries) ─────────────────────────

function json(res, status, body) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (chunk) => (data += chunk));
    req.on("end", () => {
      try { resolve(JSON.parse(data)); } catch { resolve(null); }
    });
  });
}

const apiServer = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${API_PORT}`);
  const method = req.method.toUpperCase();

  // GET /api/proxy/tunnels — list all tunnels with stats
  if (url.pathname === "/api/proxy/tunnels" && method === "GET") {
    const list = [];
    for (const t of tunnels.values()) list.push(getTunnelStats(t));
    return json(res, 200, { success: true, data: list, count: list.length });
  }

  // POST /api/proxy/tunnels — create a new tunnel
  if (url.pathname === "/api/proxy/tunnels" && method === "POST") {
    const body = await readBody(req);
    if (!body?.localPort) return json(res, 400, { success: false, error: "localPort is required" });
    const tunnel = createTunnel(body);
    if (body.autoStart !== false) {
      const result = startTunnel(tunnel);
      if (!result.ok) {
        tunnels.delete(tunnel.id);
        return json(res, 500, { success: false, error: result.error });
      }
    }
    return json(res, 201, { success: true, data: getTunnelStats(tunnel) });
  }

  // GET /api/proxy/tunnels/:id — single tunnel status
  const tunnelIdMatch = url.pathname.match(/^\/api\/proxy\/tunnels\/(\d+)$/);
  if (tunnelIdMatch && method === "GET") {
    const id = parseInt(tunnelIdMatch[1], 10);
    const tunnel = tunnels.get(id);
    if (!tunnel) return json(res, 404, { success: false, error: "tunnel not found" });
    return json(res, 200, { success: true, data: getTunnelStats(tunnel) });
  }

  // POST /api/proxy/tunnels/:id/start — start a tunnel
  const startMatch = url.pathname.match(/^\/api\/proxy\/tunnels\/(\d+)\/start$/);
  if (startMatch && method === "POST") {
    const id = parseInt(startMatch[1], 10);
    const tunnel = tunnels.get(id);
    if (!tunnel) return json(res, 404, { success: false, error: "tunnel not found" });
    const result = startTunnel(tunnel);
    return json(res, result.ok ? 200 : 400, result);
  }

  // POST /api/proxy/tunnels/:id/stop — stop a tunnel
  const stopMatch = url.pathname.match(/^\/api\/proxy\/tunnels\/(\d+)\/stop$/);
  if (stopMatch && method === "POST") {
    const id = parseInt(stopMatch[1], 10);
    const tunnel = tunnels.get(id);
    if (!tunnel) return json(res, 404, { success: false, error: "tunnel not found" });
    const result = stopTunnel(tunnel);
    return json(res, 200, result);
  }

  // DELETE /api/proxy/tunnels/:id — remove a tunnel
  if (tunnelIdMatch && method === "DELETE") {
    const id = parseInt(tunnelIdMatch[1], 10);
    const tunnel = tunnels.get(id);
    if (!tunnel) return json(res, 404, { success: false, error: "tunnel not found" });
    stopTunnel(tunnel);
    tunnels.delete(id);
    return json(res, 200, { success: true, data: null });
  }

  // GET /api/proxy/backends — list available tunneling backends and their readiness
  if (url.pathname === "/api/proxy/backends" && method === "GET") {
    return json(res, 200, {
      success: true,
      data: {
        backends: [
          {
            id: "direct",
            label: "Direct TCP/HTTP",
            description: "Built-in reverse proxy — zero dependencies, always available",
            available: true,
            features: ["tcp", "http", "websocket"],
          },
          {
            id: "pangolin",
            label: "Pangolin",
            description: "WireGuard-based self-hosted control plane — low detection surface",
            available: PANGOLIN_ENABLED,
            features: ["tcp", "http", "udp", "wireguard-mesh"],
            configRequired: !PANGOLIN_ENABLED ? ["PANGOLIN_CONTROL_PLANE", "PANGOLIN_AUTH_TOKEN"] : [],
          },
          {
            id: "frp",
            label: "frp (Fast Reverse Proxy)",
            description: "Lightweight single-binary TCP/HTTP/UDP — quick pivots",
            available: FRP_ENABLED,
            features: ["tcp", "http", "udp", "encryption", "compression"],
            configRequired: !FRP_ENABLED ? ["FRPS_ADDR", "FRPS_PORT", "FRP_AUTH_TOKEN"] : [],
          },
        ],
        activeBackend: config.tunnel?.backend || "direct",
      },
    });
  }

  // GET /api/proxy/status — overall proxy health
  if (url.pathname === "/api/proxy/status" && method === "GET") {
    const running = [...tunnels.values()].filter((t) => t.status === "running").length;
    const total = tunnels.size;
    const totalBytes = [...tunnels.values()].reduce((s, t) => s + t.bytesIn + t.bytesOut, 0);
    const totalConns = [...tunnels.values()].reduce((s, t) => s + t.conns, 0);
    return json(res, 200, {
      success: true,
      data: {
        status: "ok",
        tunnelCount: total,
        tunnelsRunning: running,
        tunnelsStopped: total - running,
        totalBytesTransferred: totalBytes,
        totalActiveConns: totalConns,
        config: {
          bindAddr: config.server?.bindAddr || "0.0.0.0",
          bindPort: config.server?.bindPort || PROXY_PORT,
        },
      },
    });
  }

  // ── Proxy Server Instance Management (launch/stop/list child processes) ──

  // GET /api/proxy/servers — list all launched proxy server instances
  if (url.pathname === "/api/proxy/servers" && method === "GET") {
    const list = [];
    for (const s of proxyServers.values()) list.push(getServerStats(s));
    return json(res, 200, { success: true, data: list, count: list.length });
  }

  // POST /api/proxy/servers/launch — launch a new proxy server instance
  if (url.pathname === "/api/proxy/servers/launch" && method === "POST") {
    const body = await readBody(req);
    if (!body?.port) return json(res, 400, { success: false, error: "port is required" });
    const result = launchProxyServer(body);
    if (!result.ok) return json(res, 500, { success: false, error: result.error });
    return json(res, 201, { success: true, data: result.data });
  }

  // GET /api/proxy/servers/:id — single server instance
  const serverIdMatch = url.pathname.match(/^\/api\/proxy\/servers\/(\d+)$/);
  if (serverIdMatch && method === "GET") {
    const id = parseInt(serverIdMatch[1], 10);
    const instance = proxyServers.get(id);
    if (!instance) return json(res, 404, { success: false, error: "server not found" });
    return json(res, 200, { success: true, data: getServerStats(instance) });
  }

  // POST /api/proxy/servers/:id/stop — stop a server instance
  const serverStopMatch = url.pathname.match(/^\/api\/proxy\/servers\/(\d+)\/stop$/);
  if (serverStopMatch && method === "POST") {
    const id = parseInt(serverStopMatch[1], 10);
    const result = stopProxyServer(id);
    return json(res, result.ok ? 200 : 400, result);
  }

  // GET /api/proxy/servers/:id/logs — tail recent logs from a server instance
  const serverLogsMatch = url.pathname.match(/^\/api\/proxy\/servers\/(\d+)\/logs$/);
  if (serverLogsMatch && method === "GET") {
    const id = parseInt(serverLogsMatch[1], 10);
    const instance = proxyServers.get(id);
    if (!instance) return json(res, 404, { success: false, error: "server not found" });
    let logs = "";
    try {
      logs = fs.readFileSync(instance.logPath, "utf-8").slice(-10000); // last 10KB
    } catch {
      logs = "(no logs yet)";
    }
    return json(res, 200, { success: true, data: { logs } });
  }

  // GET /health — health check
  if ((url.pathname === "/health" || url.pathname === "/") && method === "GET") {
    const runningServers = [...proxyServers.values()].filter((s) => s.status === "running").length;
    return json(res, 200, {
      status: "ok",
      uptime: Math.round((Date.now() - startedAt) / 1000),
      childServers: runningServers,
      totalServers: proxyServers.size,
    });
  }

  json(res, 404, { success: false, error: "not found" });
});

// ── Main proxy server (TCP/HTTP multiplexer) ─────────────────────────────────

const mainServer = net.createServer((socket) => {
  // Peek detection: check if this is HTTP traffic
  let firstChunk = true;
  socket.on("data", (chunk) => {
    if (firstChunk) {
      firstChunk = false;
      const str = chunk.toString("utf-8", 0, Math.min(chunk.length, 16));
      // If it looks like HTTP, let the API server handle it
      if (/^(GET|POST|PUT|DELETE|HEAD|OPTIONS|PATCH) /.test(str)) {
        apiServer.emit("connection", socket);
        socket.unshift(chunk); // Re-queue for the HTTP parser
        return;
      }
    }
    // Forward to a matching tunnel based on destination port
    // (tunnel matching happens via the tunnel servers themselves)
    socket.destroy();
  });
});

// ── Startup ──────────────────────────────────────────────────────────────────

const startedAt = Date.now();

function start() {
  loadConfig();

  // Start the API server
  apiServer.on("error", (err) => {
    if (err.code === "EADDRINUSE") {
      console.warn(`[proxy-manager] API server port ${API_PORT} already in use — skipping bind`);
    } else {
      console.error(`[proxy-manager] API server error: ${err.message}`);
    }
  });

  apiServer.listen(API_PORT, "127.0.0.1", () => {
    console.log(`[proxy-manager] API server listening on http://127.0.0.1:${API_PORT}`);
    console.log(`[proxy-manager] auth: ${config.auth?.apiKey ? "configured" : "open"}`);
  });

  // Start the main proxy server for TCP/UDP forwarding
  const bindAddr = config.server?.bindAddr || "0.0.0.0";
  const bindPort = config.server?.bindPort || PROXY_PORT;

  mainServer.on("error", (err) => {
    if (err.code === "EADDRINUSE") {
      console.warn(`[proxy-manager] proxy server port ${bindPort} already in use — skipping bind`);
    } else {
      console.error(`[proxy-manager] proxy server error: ${err.message}`);
    }
  });

  mainServer.listen(bindPort, bindAddr, () => {
    console.log(`[proxy-manager] proxy server listening on ${bindAddr}:${bindPort}`);
  });

  // Auto-start tunnels from config
  if (Array.isArray(config.proxies)) {
    for (const proxyDef of config.proxies) {
      if (!proxyDef.name || !proxyDef.localPort) continue;
      const tunnel = createTunnel(proxyDef);
      if (proxyDef.autoStart !== false) {
        startTunnel(tunnel);
      }
    }
  }

  // Periodic stats dump
  setInterval(() => {
    const running = [...tunnels.values()].filter((t) => t.status === "running").length;
    if (running > 0) {
      console.log(`[proxy-manager] stats: ${running}/${tunnels.size} tunnels running`);
    }
  }, 60000);
}

start();
