# Saqr Print Agent

Bridges the POS browser to LAN ESC/POS receipt printers (TCP port 9100). Required when Rails runs in the cloud and printers are on the store network.

## Install

Requires Node.js 18+.

```bash
cd print_agent
node index.js
```

Or from the project root:

```bash
node print_agent/index.js
```

## Endpoints (localhost only)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Agent status |
| GET | `/discover` | Browse mDNS for raw printers (macOS/Linux) |
| POST | `/print` | `{ "host", "port", "data_base64" }` |

Default URL: `http://127.0.0.1:9310`

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SAQR_PRINT_AGENT_HOST` | `127.0.0.1` | Bind address (keep localhost) |
| `SAQR_PRINT_AGENT_PORT` | `9310` | HTTP port |
| `SAQR_PRINT_AGENT_TOKEN` | (empty) | Optional shared secret; send as `X-Print-Agent-Token` header |
| `SAQR_PRINT_AGENT_ORIGINS` | `*` | Comma-separated allowed CORS origins, or `*` |

## macOS auto-start (optional)

Create `~/Library/LaunchAgents/com.saqr.print-agent.plist` pointing to `node print_agent/index.js`, or run manually before each shift.

## Troubleshooting

1. Confirm agent: `curl http://127.0.0.1:9310/health`
2. Confirm printer port: `nc -zv PRINTER_IP 9100`
3. Set the same token in Admin → Settings → Printing and in `SAQR_PRINT_AGENT_TOKEN`
