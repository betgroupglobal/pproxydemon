# Edge Gateway Dashboard — Usage Guide

A mobile command center for managing reverse-proxy targets, capturing live HTTP traffic, generating AI-powered phishlet configurations, and orchestrating self-hosted tunnel servers — all from your phone.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Dashboard](#dashboard)
3. [Proxies](#proxies)
4. [Intercepts](#intercepts)
5. [Recon](#recon)
6. [Settings](#settings)
7. [Common Workflows](#common-workflows)
8. [Troubleshooting](#troubleshooting)

---

## Getting Started

### 1. Connect to your gateway

Open the app and go to the **Settings** tab. At minimum you need:

- **Gateway URL** — the address of your backend server (e.g. `https://leproxy-production.up.railway.app`)
- **API Key** — the bearer token for write operations and accessing intercepts (same key you set as `API_KEY` on the server)

Tap **Save app settings** after entering them. Then tap **Test Connection** — you should see a green "Gateway healthy" badge.

> If the banner at the top of Settings says "Gateway URL required", the app is not connected. Fill in the URL first.

### 2. Set proxy host (optional)

The **Proxy Host** field in Settings lets you specify a domain that maps to your gateway for proxied traffic. This is used by the Recon tab to build proxy URLs for scanning.

### 3. Configure runtime overrides

Below App Settings, the **Runtime Config** section lets you toggle server-side behaviour without redeploying:

| Setting | What it does |
|---|---|
| `PROXY_TARGET` | Default upstream target for all proxy traffic |
| `INTERCEPT_LAB_MODE` | Enable/disable payload capture on proxied requests |
| `INTERCEPT_TTL_SECONDS` | How long to retain captures (default 600s) |
| `ALLOWED_ORIGINS` | CORS origins for the gateway API |

---

## Dashboard

**Tab icon:** Pulse dot with live status indicator.

The Dashboard is your real-time overview of the entire gateway.

### What you see

- **Gateway health card** — green `OPERATIONAL`, yellow `CONNECTING`, or red `UNREACHABLE`. Shows item count and a quick link to manage stored items. Pull down to refresh.
- **Latency, Edge, Uptime, Rate** — four stat cards showing gateway metrics.
- **Traffic stats** — total requests, average latency, cache hits, and error count.
- **Live feed** — a real-time scrolling list of recent HTTP requests through the gateway. Each row shows method (color-coded), path, status code, latency, and cache status.

### When to check it

- After deploying to confirm the gateway is up
- When traffic seems slow — check latency and error spikes
- To verify proxy traffic is flowing after creating a target

---

## Proxies

**Tab icon:** Network node.

This is where you create and manage reverse-proxy targets. Each proxy represents a domain you want to route through the gateway.

### Creating a proxy

1. Enter a **target URL** (e.g. `https://api.example.com` or just `api.example.com`)
2. Optionally give it a **name** (auto-generated from the hostname if blank)
3. Tap **Deploy proxy**

The proxy appears in the targets list immediately. A slug is auto-generated (e.g. `api-example-com-4`).

### Managing a proxy

Each proxy card shows:
- Name and slug
- Target URL
- Enabled/disabled toggle
- Hit counter
- Intercept toggle (enable to start capturing credentials and form data from proxied traffic)

Tap a card to reveal more options:
- Toggle **Intercept** to start/stop payload capture
- Edit **Inject JS** to add custom JavaScript to proxied pages
- View the generated **phishlet** YAML if recon has been run

### Launching tunnel servers

Below the proxy list, the **Proxy Servers** section lets you spin up dedicated tunnel hosts:

1. Enter a **target host** (e.g. `api.example.com`)
2. Set a **name** and **port** (default 12000)
3. Optionally tap **Grok config** to have Grok Build 0.1 AI generate an optimal TOML config
4. Tap **Launch server**

The server appears in the Instances list with:
- Status dot (green = running, yellow = launching, gray = stopped)
- PID, port, tunnel count
- Uptime and health status
- **Logs** button to tail recent output
- **Stop** button to gracefully shut down

---

## Intercepts

**Tab icon:** Shield with warning accent.

Every proxied request with "Intercept" enabled on its proxy target gets captured here.

### Viewing captures

Captures are grouped by proxy slug. Each group shows:
- Slug name and capture count
- Individual captures with method, path, status, timestamp
- Expand to see full request/response headers and bodies

### Actions

- **Export HAR** — downloads all captures as an HTTP Archive (HAR 1.2) JSON file. On mobile, opens the share sheet; on web, triggers a browser download.
- **Replay** — opens a modal where you paste a HAR JSON blob and specify a proxy slug. The engine replays every request sequentially, extracts session tokens, and produces a detailed report with per-request latency, cookies, and redirects.
- **Clear** — wipes all intercept captures (with confirmation dialog on mobile).

### HAR Replay

The replay engine is useful for:
- Replaying a captured login flow against a target
- Extracting session tokens and CSRF tokens from the response chain
- Validating that a proxy configuration correctly handles auth redirects

Paste the HAR, enter the proxy slug, and tap **Run Replay**. The report shows:
- Succeeded / failed / total counts
- Extracted tokens (tappable to copy)
- Flow summary
- Per-request log with method, status, latency, cookies, and redirects

---

## Recon

**Tab icon:** Radar dish.

The reconnaissance pipeline automates phishlet generation — you browse a target's login page, the app captures form fields and auth links, then Kimi K2.7 AI generates and refines a phishlet YAML configuration.

### Running a scan

1. Select a **target** from the proxy chips at the top
2. Tap **Run scan**
3. An in-app browser opens the target. Navigate to the login page and interact with the form.
4. The pipeline auto-progresses through four stages:
   - **Capture** — the page is scanned for form fields, hidden inputs, CSRF tokens, auth links, and API endpoints
   - **Generate** — Kimi K2.7 creates a first-pass phishlet YAML
   - **Refine** — the AI critiques its own output (multi-pass) and produces an improved version with a score
   - **Done** — final YAML is ready to copy

### What gets captured

The **Captured intelligence** card shows real-time metrics:
- Page title, form action, HTTP method
- Number of form fields, hidden inputs, cookies, domains
- CSRF fields, auth links, and API endpoints discovered

### Login Phishlet Automator

Instead of browsing manually, you can paste a specific login URL and tap **Generate**. The app navigates to that URL, probes the login form structure, and produces a phishlet directly — no interaction needed.

### Headless Agent

For advanced use, the **Headless Agent** section provides a copy-paste terminal command to run the Puppeteer-based agent locally on your machine. The agent navigates the target, extracts the form structure, and uploads the result back to the gateway.

### Output

Both the initial and refined YAML are displayed with **Copy** buttons. The refined result includes:
- Score out of 100
- Number of critique passes
- List of findings with severity (critical / warning / info) and suggested fixes
- List of improvements applied

---

## Settings

**Tab icon:** Gear.

The central configuration hub for the entire gateway.

### App Settings (device-local)

| Field | Purpose |
|---|---|
| **Gateway URL** | Backend server address |
| **Proxy Host** | Domain mapped to your gateway for proxy traffic |
| **Allowed Origins** | CORS origins (use `*` for open access) |

These are persisted on your device using AsyncStorage. Tap **Save app settings** after changes.

### API Key

Enter the bearer token that matches the `API_KEY` set on your server. Toggle visibility with the eye icon. Write operations (create/update/delete proxies, clear intercepts, save config) require this key.

### Runtime Config

Server-side overrides organised into groups:

- **Security** — `API_KEY` (can be changed at runtime)
- **Edge Proxy** — `PROXY_TARGET`, `BASE_DOMAIN`, `ALLOWED_ORIGINS`
- **Intercept Lab** — `INTERCEPT_LAB_MODE`, allowlist/blocklist, TTL
- **AI Phishlet Engine** — toolkit URL and secret for Kimi K2.7 and Grok Build 0.1

Changes take effect immediately. Tap **Save runtime config** to persist, or **Revert to defaults** to clear all overrides.

### Proxy Tunnels

Shows all self-hosted tunnels created via the Proxy Manager:
- Running / stopped counts and connection stats
- Per-tunnel row with type, local/remote port mapping, status
- Tunnel actions: start, stop, delete (requires API key)

### Gateway URLs & APIs

Quick-reference list of all API endpoints with copy buttons — useful for curl testing or integrating with external tools.

### Architecture & Capabilities

Reference cards showing the system architecture (Expo App → Edge Gateway → In-Memory Store) and all six core capabilities.

---

## Common Workflows

### Workflow 1: Set up a new proxy target

1. **Settings** → enter Gateway URL and API Key → Save → Test Connection
2. **Proxies** → enter target URL → Deploy proxy
3. **Dashboard** → confirm gateway is operational and traffic is flowing

### Workflow 2: Capture login traffic

1. **Proxies** → toggle **Intercept** on the target proxy
2. Traffic flows through the gateway — credentials, cookies, and form data are captured
3. **Intercepts** → view captures grouped by slug → expand to inspect headers/bodies
4. **Intercepts** → Export HAR for offline analysis or Replay against another target

### Workflow 3: Generate a phishlet for a login page

1. **Proxies** → create a proxy for the target domain
2. **Recon** → select the proxy → Run scan
3. Browse the login page in the in-app browser — the capture happens automatically
4. Wait for the pipeline to finish (Capture → Generate → Refine → Done)
5. Copy the refined YAML — it's automatically applied to the proxy

### Workflow 4: Launch a tunnel server (Grok Build 0.1)

1. **Proxies** → scroll to Proxy Servers section
2. Enter target host → tap **Grok config** for AI-generated TOML
3. Review the generated config → tap **Launch server**
4. Monitor the instance — check logs, uptime, and health
5. Stop when done

### Workflow 5: Replay a HAR session

1. **Intercepts** → Export HAR (or use any HAR file)
2. **Intercepts** → tap Replay → paste the HAR JSON
3. Enter the proxy slug to replay against
4. Tap Run Replay → review extracted tokens and request log

---

## Troubleshooting

### "Gateway URL required" banner

Go to **Settings** → enter your backend URL in the **Gateway URL** field → Save. The banner disappears once the app is connected.

### Health check shows UNREACHABLE

1. Verify the gateway URL is correct in Settings
2. Check that the server process is running (`curl <gateway-url>/health`)
3. If using Docker, check container logs
4. Ensure no firewall is blocking the port

### AI features return stub/fallback results

The gateway falls back to deterministic stubs when AI is unavailable. For live AI:
1. Set `TOOLKIT_URL` and `TOOLKIT_SECRET` in Runtime Config (Settings tab)
2. Verify the toolkit credentials are valid
3. Check server logs for `[kimi]` or `[grok-build]` error messages

### Proxies list is empty

1. Check that the gateway URL is correct in Settings
2. Verify the server is running
3. Create a proxy from the Proxies tab (enter a target URL and tap Deploy)

### Intercepts don't show any captures

1. Enable **Intercept** on the proxy target (toggle in the proxy card)
2. Send traffic through the proxy
3. Pull to refresh on the Intercepts tab
4. Check that `INTERCEPT_LAB_MODE` is not disabled in Runtime Config

### Tunnels won't start

1. Verify the proxy-manager process is running (port 7001)
2. Check port ranges don't collide (remote ports use 10000–50000)
3. Review the proxy-build config at `proxy-build/config/config.toml`
4. Check proxy-manager logs via the server instance logs button

### HAR export or replay fails

- Export requires the API key to be set (intercepts are auth-protected)
- Replay requires both a valid HAR JSON and an existing proxy slug
- Large HAR files may take time — the engine runs requests sequentially

---

## Keyboard Shortcuts (web)

When running the app in a browser:

| Key | Action |
|---|---|
| `Enter` in proxy target field | Submit (deploy proxy) |
| `Enter` in settings fields | Triggers form submission where applicable |

---

## Environment Variables (server-side)

| Variable | Required | Purpose |
|---|---|---|
| `PORT` | No (default 8787) | Gateway API port |
| `API_KEY` | No | Bearer token for write auth |
| `ALLOWED_ORIGINS` | No | Comma-separated CORS origins |
| `TOOLKIT_URL` | For AI | Rork Toolkit base URL |
| `TOOLKIT_SECRET_KEY` | For AI | Rork Toolkit secret |
| `PROXY_PORT` | No (default 7000) | Proxy tunnel entry port |
| `PROXY_API_PORT` | No (default 7001) | Proxy manager API port |

---

Built with Rork · Edge Gateway Dashboard
