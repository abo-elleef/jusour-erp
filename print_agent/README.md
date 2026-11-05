# Saqr Print Agent

Bridges the cloud-hosted POS to local ESC/POS receipt printers — both **network (IP)** and **USB** printers on Windows.

The agent forwards raw ESC/POS bytes as-is. Character encoding, Arabic reshaping, and code-page selection are all handled by the Rails app before data reaches the agent.

---

## Installation on the restaurant Windows machine

### For restaurant staff — the installer (recommended)

1. Download **`SaqrPrintAgent-Setup.exe`** (from the GitHub release / Actions artifact).
2. Double-click it and click **Next**.
3. Paste the **agent token** from Saqr → Admin → Settings → Printing. Leave the port as `9310`.
4. Click **Install**. When it finishes, a status page opens showing **Running**.

That's all — no terminal. The agent runs hidden in the background, starts automatically
every time Windows starts (even before anyone logs in), and restarts itself if it crashes (a small hidden loop restarts it).

- **Status page:** Start menu → *Saqr Print Agent Status* (or <http://127.0.0.1:9310/>)
- **Config:** `C:\ProgramData\SaqrPrintAgent\config.json` (edit, then log out/in or reboot)
- **Log:** `C:\ProgramData\SaqrPrintAgent\agent.log`
- **Upgrade:** run the new installer over the old one; the existing config is kept.
- **Uninstall:** Settings → Apps → Saqr Print Agent.

`config.json`:

```json
{ "port": 9310, "token": "your-secret-token" }
```

Optional keys: `host`, `origins`, `connect_timeout_ms`, `discover_timeout_ms`.
Environment variables (below) still override the file.

### For IT / development — Node.js

Requires [Node.js 18+](https://nodejs.org/en/download).

```powershell
cd print_agent
npm install
node index.js          # foreground, for testing
```

`npm run install-service` / `uninstall-service` register a classic Windows Service
via `node-windows` (needs Node installed and an Administrator shell). The installer
above does not use it.

---

## Configuring printers in Saqr

Go to **Admin → Printers** and set each printer's connection:

- **Network printer** — set Connection to `Network (IP)`, enter the printer's IP address and port (default 9100)
- **USB printer** — set Connection to `USB`, enter the Windows port name (e.g. `USB001`)

To find the USB port name: open **Devices & Printers** → right-click the printer → **Printer properties** → **Ports** tab.

---

## Building the installer (for release)

Easiest: GitHub → Actions → **Print agent Windows installer** → Run workflow
(or push a tag like `print-agent-v1.2.2` to attach it to a release). The job
builds `SaqrPrintAgent.exe` with `pkg`, then wraps it with
[Inno Setup](https://jrsoftware.org/isinfo.php) into `SaqrPrintAgent-Setup.exe`.

Locally on Windows (needs Node.js and Inno Setup 6 on PATH):

```powershell
npm install
npm run installer      # → dist\SaqrPrintAgent-Setup.exe
```

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

With the installer, prefer `config.json` (see above). With the legacy `install-service`, variables are baked in at install time.

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
| Status page does not open | Agent not running — open Task Scheduler → `SaqrPrintAgent` → Run; check `agent.log` |
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
