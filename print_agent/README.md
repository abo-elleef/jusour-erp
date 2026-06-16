# Saqr Print Agent

Bridges the POS browser to LAN ESC/POS receipt printers (TCP port 9100). Required when Rails runs in the cloud and printers are on the store network.

The agent forwards raw ESC/POS bytes as-is (including Arabic). Character encoding and code-page selection are handled by the Rails app before data reaches the agent.

## Arabic printing

Receipts and kitchen tickets use **Windows-1256** when the app locale is Arabic (`ar`), with ESC/POS code page **47** (common on Arabic firmware). If characters appear garbled on your printer, set in Rails console:

```ruby
Setting.set("print_code_page", 22)   # try PC864 table on some Epson models
Setting.set("print_encoding", "windows-1256")
```

Default is `print_encoding: auto` (Arabic when locale is `ar`).

## Requirements

- Node.js 18 or later — https://nodejs.org/en/download
- (Windows only, for printer discovery) Bonjour for Windows — https://support.apple.com/kb/DL999

> **Note:** Bonjour is optional. If you already know the printer's IP address you can skip it and type the IP manually in Admin → Printers.

---

## Quick start — Windows PowerShell

```powershell
# 1. Navigate to the print_agent folder
cd C:\path\to\saqr-pos\print_agent

# 2. Start the agent
node index.js
```

You should see output like:

```
────────────────────────────────────────────────────────────
  Saqr Print Agent
  Listening on : http://127.0.0.1:9310
  Platform     : win32 (Node v20.x.x)
  Auth token   : disabled (open)
  Discovery    : Bonjour/dns-sd (install Bonjour for Windows if needed)
────────────────────────────────────────────────────────────
  Endpoints:
    GET  http://127.0.0.1:9310/health   — status check
    GET  http://127.0.0.1:9310/discover — browse network printers
    POST http://127.0.0.1:9310/print    — send ESC/POS bytes to printer
────────────────────────────────────────────────────────────
  Press Ctrl+C to stop.
────────────────────────────────────────────────────────────
[2026-01-01 10:00:00.000] [INFO ] Agent ready — waiting for print jobs.
```

Every print job then logs a line in real time:

```
[2026-01-01 10:05:12.345] [INFO ] Sending 842 bytes to printer 192.168.1.50:9100 …
[2026-01-01 10:05:12.401] [OK   ] Print SUCCESS — 842 bytes sent to 192.168.1.50:9100
```

Or on failure:

```
[2026-01-01 10:05:12.345] [INFO ] Sending 842 bytes to printer 192.168.1.50:9100 …
[2026-01-01 10:05:17.350] [ERROR] Print FAILED — 192.168.1.50:9100 — Connection timed out after 5000ms
```

### Environment variables (PowerShell)

```powershell
# Use a different port
$env:SAQR_PRINT_AGENT_PORT = "9311"

# Require a token (must match Admin → Settings → Printing)
$env:SAQR_PRINT_AGENT_TOKEN = "my-secret-token"

# Restrict CORS to your POS domain
$env:SAQR_PRINT_AGENT_ORIGINS = "https://pos.example.com"

# Then start
node index.js
```

### Run as a background service (optional, Windows)

Use [NSSM](https://nssm.cc/) to run the agent as a Windows service that survives reboots:

```powershell
nssm install SaqrPrintAgent "C:\Program Files\nodejs\node.exe" "C:\path\to\saqr-pos\print_agent\index.js"
nssm set SaqrPrintAgent AppDirectory "C:\path\to\saqr-pos\print_agent"
nssm start SaqrPrintAgent
```

---

## macOS / Linux

```bash
cd print_agent
node index.js
```

**macOS auto-start (optional):** Create `~/Library/LaunchAgents/com.saqr.print-agent.plist` pointing to `node print_agent/index.js`.

---

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Agent status |
| GET | `/discover` | Browse mDNS for raw printers (macOS, Windows with Bonjour, Linux with Avahi) |
| POST | `/print` | `{ "host", "port", "data_base64" }` |

Default URL: `http://127.0.0.1:9310`

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SAQR_PRINT_AGENT_HOST` | `127.0.0.1` | Bind address (keep localhost for security) |
| `SAQR_PRINT_AGENT_PORT` | `9310` | HTTP port |
| `SAQR_PRINT_AGENT_TOKEN` | (empty) | Optional shared secret; send as `X-Print-Agent-Token` header |
| `SAQR_PRINT_AGENT_ORIGINS` | `*` | Comma-separated allowed CORS origins, or `*` |
| `SAQR_PRINT_CONNECT_TIMEOUT_MS` | `5000` | TCP connect timeout to printer |
| `SAQR_PRINT_DISCOVER_TIMEOUT_MS` | `4000` | mDNS browse timeout |

## Troubleshooting

1. **Health check:** `curl http://127.0.0.1:9310/health` (or open in browser)
2. **Printer reachable?** `Test-NetConnection -ComputerName PRINTER_IP -Port 9100` (PowerShell)
3. **Token mismatch?** Make sure `SAQR_PRINT_AGENT_TOKEN` matches Admin → Settings → Printing → Agent token
4. **Port in use?** `netstat -ano | findstr 9310` — check if another process holds the port
