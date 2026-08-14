# Saqr Print Agent

Bridges the cloud-hosted POS to local ESC/POS receipt printers — both **network (IP)** and **USB** printers on Windows.

The agent forwards raw ESC/POS bytes as-is. Character encoding, Arabic reshaping, and code-page selection are all handled by the Rails app before data reaches the agent.

---

## Installation on the restaurant Windows machine

### Option A — Single EXE (recommended, no Node.js needed)

Download `SaqrPrintAgent.exe` from the latest release and place it anywhere (e.g. `C:\Saqr\`).

**One-time setup — run as Administrator:**

```powershell
# 1. Set your configuration (edit these values first)
$env:SAQR_PRINT_AGENT_TOKEN = "your-secret-token"   # must match Admin → Settings → Printing
$env:SAQR_PRINT_AGENT_PORT  = "9310"                 # default is fine for most installs

# 2. Install as a Windows Service (auto-starts on boot)
C:\Saqr\SaqrPrintAgent.exe install-service
```

The service starts immediately and survives reboots and crashes automatically.

**Verify it's running:**

```powershell
curl http://127.0.0.1:9310/health
```

---

### Option B — Node.js (for development / IT teams)

Requires [Node.js 18+](https://nodejs.org/en/download).

```powershell
cd C:\path\to\saqr-pos\print_agent
npm install
```

**Run manually (foreground, for testing):**

```powershell
node index.js
```

**Install as a Windows Service (run as Administrator):**

```powershell
# Set env vars first if needed
$env:SAQR_PRINT_AGENT_TOKEN = "your-secret-token"

npm run install-service
```

**Uninstall the service:**

```powershell
npm run uninstall-service
```

---

## Configuring printers in Saqr

Go to **Admin → Printers** and set each printer's connection:

- **Network printer** — set Connection to `Network (IP)`, enter the printer's IP address and port (default 9100)
- **USB printer** — set Connection to `USB`, enter the Windows port name (e.g. `USB001`)

To find the USB port name: open **Devices & Printers** → right-click the printer → **Printer properties** → **Ports** tab.

---

## Building the EXE (for release)

Requires Node.js and `pkg`:

```powershell
npm install
npm run build
# Output: dist/SaqrPrintAgent.exe
```

The EXE is self-contained — no Node.js installation needed on the restaurant machine.

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SAQR_PRINT_AGENT_HOST` | `127.0.0.1` | Bind address (keep localhost for security) |
| `SAQR_PRINT_AGENT_PORT` | `9310` | HTTP port |
| `SAQR_PRINT_AGENT_TOKEN` | *(empty)* | Shared secret; must match Admin → Settings → Printing → Agent token |
| `SAQR_PRINT_AGENT_ORIGINS` | `*` | Comma-separated allowed CORS origins |
| `SAQR_PRINT_CONNECT_TIMEOUT_MS` | `5000` | TCP connect timeout to network printer (ms) |
| `SAQR_PRINT_DISCOVER_TIMEOUT_MS` | `4000` | mDNS browse timeout (ms) |

When running as a Windows Service, set these before running `install-service` — they are baked into the service registration. To change them later, uninstall and reinstall the service.

---

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Agent status and version |
| `GET` | `/discover` | Browse mDNS/Bonjour for network printers |
| `POST` | `/print` | Send ESC/POS bytes to a printer |

### POST /print — network printer

```json
{
  "connection": "network",
  "host": "192.168.1.50",
  "port": 9100,
  "data_base64": "<base64-encoded ESC/POS bytes>"
}
```

### POST /print — USB printer

```json
{
  "connection": "usb",
  "device": "USB001",
  "data_base64": "<base64-encoded ESC/POS bytes>"
}
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `curl http://127.0.0.1:9310/health` fails | Service not running — check `Services.msc` → SaqrPrintAgent |
| `401 Unauthorized` | Token mismatch — check `SAQR_PRINT_AGENT_TOKEN` vs Admin → Settings |
| Network printer times out | Verify IP with `Test-NetConnection -ComputerName PRINTER_IP -Port 9100` |
| USB printer fails to open | Wrong port name — check Devices & Printers → Ports tab |
| Port 9310 in use | `netstat -ano \| findstr 9310` — kill or change `SAQR_PRINT_AGENT_PORT` |
| Garbled Arabic characters | In Rails console: `Setting.set("print_code_page", 47)` (or 22 for some Epson models) |

---

## macOS / Linux (development only)

```bash
cd print_agent
node index.js
```

USB printing is Windows-only (`\\.\USB001` device paths). On macOS/Linux, use network printers only.
