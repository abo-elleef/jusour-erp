#!/usr/bin/env node
"use strict"

const http = require("http")
const net = require("net")
const fs = require("fs")
const { execFile, spawn } = require("child_process")
const { promisify } = require("util")

const path = require("path")
const os = require("os")

const execFileAsync = promisify(execFile)
const VERSION = "1.2.2"

// ─── Config ───────────────────────────────────────────────────────────────────
// Precedence: environment variable > config.json > default.
// config.json lives in %ProgramData%\SaqrPrintAgent on Windows (written by the
// installer), or next to the agent for dev use. Override with SAQR_PRINT_AGENT_CONFIG.

const DATA_DIR =
  process.env.SAQR_PRINT_AGENT_DIR ||
  (process.platform === "win32"
    ? path.join(process.env.PROGRAMDATA || "C:\\ProgramData", "SaqrPrintAgent")
    : path.join(os.homedir(), ".saqr-print-agent"))

const CONFIG_PATH = process.env.SAQR_PRINT_AGENT_CONFIG || path.join(DATA_DIR, "config.json")

function loadConfig() {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"))
  } catch (err) {
    if (err.code !== "ENOENT") console.error(`Could not read ${CONFIG_PATH}: ${err.message}`)
    return {}
  }
}

const FILE_CONFIG = loadConfig()

function setting(envName, key, fallback) {
  const fromEnv = process.env[envName]
  if (fromEnv !== undefined && fromEnv !== "") return fromEnv
  if (FILE_CONFIG[key] !== undefined && FILE_CONFIG[key] !== "") return String(FILE_CONFIG[key])
  return fallback
}

const HOST = setting("SAQR_PRINT_AGENT_HOST", "host", "127.0.0.1")
const PORT = parseInt(setting("SAQR_PRINT_AGENT_PORT", "port", "9310"), 10)
const TOKEN = setting("SAQR_PRINT_AGENT_TOKEN", "token", "")
const ALLOWED_ORIGINS = setting("SAQR_PRINT_AGENT_ORIGINS", "origins", "*")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean)
const CONNECT_TIMEOUT_MS = parseInt(setting("SAQR_PRINT_CONNECT_TIMEOUT_MS", "connect_timeout_ms", "5000"), 10)
const DISCOVER_TIMEOUT_MS = parseInt(setting("SAQR_PRINT_DISCOVER_TIMEOUT_MS", "discover_timeout_ms", "4000"), 10)

// ─── File logging (the installed agent has no console window) ─────────────────

const LOG_PATH = path.join(DATA_DIR, "agent.log")
const MAX_LOG_BYTES = 1024 * 1024
const recentLines = []

function appendLogFile(line) {
  recentLines.push(line)
  if (recentLines.length > 50) recentLines.shift()
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true })
    try {
      if (fs.statSync(LOG_PATH).size > MAX_LOG_BYTES) fs.renameSync(LOG_PATH, LOG_PATH + ".1")
    } catch {}
    fs.appendFileSync(LOG_PATH, line + "\n")
  } catch {
    // Logging must never crash the agent.
  }
}

// ─── Logging ──────────────────────────────────────────────────────────────────

function ts() {
  return new Date().toISOString().replace("T", " ").replace("Z", "")
}

function log(level, message) {
  const prefix = `[${ts()}] [${level.padEnd(5)}]`
  appendLogFile(`${prefix} ${message}`)
  if (level === "ERROR") {
    console.error(`${prefix} ${message}`)
  } else {
    console.log(`${prefix} ${message}`)
  }
}

function logInfo(message)  { log("INFO",  message) }
function logOk(message)    { log("OK",    message) }
function logWarn(message)  { log("WARN",  message) }
function logError(message) { log("ERROR", message) }

// ─── CORS ─────────────────────────────────────────────────────────────────────

function corsHeaders(origin) {
  const allowed =
    ALLOWED_ORIGINS.includes("*") ||
    (origin && ALLOWED_ORIGINS.some((o) => origin === o || origin.endsWith(o.replace(/^\*/, ""))))

  return {
    "Access-Control-Allow-Origin": allowed ? origin || "*" : "null",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, X-Print-Agent-Token",
    "Access-Control-Max-Age": "86400"
  }
}

function sendJson(res, status, body, origin) {
  const payload = JSON.stringify(body)
  res.writeHead(status, {
    "Content-Type": "application/json",
    ...corsHeaders(origin)
  })
  res.end(payload)
}

function authorized(req) {
  if (!TOKEN) return true
  return req.headers["x-print-agent-token"] === TOKEN
}

// ─── USB print (Windows) ──────────────────────────────────────────────────────

function printToUsb(device, data) {
  return new Promise((resolve, reject) => {
    // Windows exposes USB printer ports as \\.\USB001, USB002, etc.
    // Normalise: accept "USB001" or "\\\\.\\USB001"
    const devicePath = device.startsWith("\\\\.\\") ? device : `\\\\.\\${device}`
    fs.open(devicePath, "w", (openErr, fd) => {
      if (openErr) {
        return reject(new Error(`Cannot open USB device ${devicePath}: ${openErr.message}`))
      }
      fs.write(fd, data, 0, data.length, null, (writeErr) => {
        fs.close(fd, () => {})
        if (writeErr) {
          reject(new Error(`Write to ${devicePath} failed: ${writeErr.message}`))
        } else {
          resolve()
        }
      })
    })
  })
}

// ─── Network print ────────────────────────────────────────────────────────────

function printToNetwork(host, port, data) {
  return new Promise((resolve, reject) => {
    let settled = false

    function settle(fn, value) {
      if (settled) return
      settled = true
      fn(value)
    }

    const socket = net.connect({ host, port, timeout: CONNECT_TIMEOUT_MS }, () => {
      socket.write(data, (err) => {
        if (err) {
          socket.destroy()
          settle(reject, err)
          return
        }
        socket.end()
      })
    })

    socket.on("error", (err) => {
      socket.destroy()
      settle(reject, err)
    })

    socket.on("timeout", () => {
      socket.destroy()
      settle(reject, new Error(`Connection timed out after ${CONNECT_TIMEOUT_MS}ms`))
    })

    socket.on("close", () => settle(resolve, undefined))
  })
}

// ─── Printer discovery ────────────────────────────────────────────────────────

// Shared dns-sd discovery logic (macOS and Windows both ship dns-sd via Bonjour)
function discoverViaDnsSd() {
  return new Promise((resolve) => {
    const found = new Map()
    const proc = spawn("dns-sd", ["-B", "_pdl-datastream._tcp", "local"], { stdio: ["ignore", "pipe", "pipe"] })

    const handleLine = (line) => {
      const match = line.match(/Add\s+\d+\s+\d+\s+(.+?)\._pdl-datastream\._tcp\./)
      if (!match) return
      const name = match[1].replace(/\\032/g, " ").trim()
      if (!found.has(name)) {
        found.set(name, { name, host: null, port: 9100, service_type: "_pdl-datastream._tcp" })
      }
    }

    proc.stdout.on("data", (chunk) => {
      chunk.toString().split("\n").forEach(handleLine)
    })

    setTimeout(() => {
      proc.kill(process.platform === "win32" ? undefined : "SIGTERM")
      resolve([...found.values()])
    }, DISCOVER_TIMEOUT_MS)

    proc.on("error", () => resolve([]))
  })
}

async function discoverLinux() {
  try {
    const { stdout } = await execFileAsync("avahi-browse", [
      "-t", "-r", "_pdl-datastream._tcp"
    ], { timeout: DISCOVER_TIMEOUT_MS + 1000 })

    const found = new Map()
    stdout.split("\n").forEach((line) => {
      const serviceMatch = line.match(/=.*_pdl-datastream\._tcp.*\s+(.+)$/)
      if (serviceMatch) {
        const name = serviceMatch[1].trim()
        found.set(name, { name, host: null, port: 9100, service_type: "_pdl-datastream._tcp" })
      }
      const addrMatch = line.match(/=\s*IPv4.*\s+(\d+\.\d+\.\d+\.\d+)\s+(\d+)/)
      if (addrMatch && found.size > 0) {
        const last = [...found.values()].pop()
        last.host = addrMatch[1]
        last.port = parseInt(addrMatch[2], 10) || 9100
      }
    })
    return [...found.values()].filter((p) => p.host)
  } catch {
    return []
  }
}

async function discoverPrinters() {
  const platform = process.platform
  if (platform === "darwin" || platform === "win32") {
    return discoverViaDnsSd()
  }
  if (platform === "linux") {
    return discoverLinux()
  }
  return []
}

// ─── Body parsing ─────────────────────────────────────────────────────────────

async function readBody(req) {
  const chunks = []
  for await (const chunk of req) chunks.push(chunk)
  const raw = Buffer.concat(chunks).toString("utf8")
  if (!raw) return {}
  return JSON.parse(raw)
}

// ─── Status page ──────────────────────────────────────────────────────────────

function escapeHtml(str) {
  return String(str).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))
}

function statusPage() {
  const lines = escapeHtml(recentLines.slice(-30).join("\n") || "No activity yet.")
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="5">
<title>Saqr Print Agent</title>
<style>
body{font-family:system-ui,Segoe UI,sans-serif;max-width:760px;margin:40px auto;padding:0 16px;color:#1f2937}
.ok{display:inline-block;background:#16a34a;color:#fff;padding:4px 12px;border-radius:999px;font-weight:600}
dl{display:grid;grid-template-columns:140px 1fr;gap:6px 12px}dt{color:#6b7280}
pre{background:#111827;color:#d1d5db;padding:12px;border-radius:8px;overflow:auto;font-size:12px;max-height:340px}
</style></head><body>
<h1>Saqr Print Agent</h1>
<p><span class="ok">&#9679; Running</span></p>
<dl>
<dt>Version</dt><dd>${VERSION}</dd>
<dt>Address</dt><dd>http://${escapeHtml(HOST)}:${PORT}</dd>
<dt>Token</dt><dd>${TOKEN ? "set" : "not set (open)"}</dd>
<dt>Platform</dt><dd>${escapeHtml(process.platform)}</dd>
<dt>Config file</dt><dd>${escapeHtml(CONFIG_PATH)}</dd>
<dt>Log file</dt><dd>${escapeHtml(LOG_PATH)}</dd>
</dl>
<h3>Recent activity</h3><pre>${lines}</pre>
<p style="color:#6b7280">This page refreshes every 5 seconds. Printers are configured in Saqr under Admin &rarr; Printers.</p>
</body></html>`
}

// ─── HTTP server ──────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const origin = req.headers.origin || ""

  if (req.method === "OPTIONS") {
    res.writeHead(204, corsHeaders(origin))
    res.end()
    return
  }

  // Human-friendly status page — no secrets, no auth, safe on localhost.
  if (req.method === "GET" && (req.url === "/" || req.url === "/status")) {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" })
    res.end(statusPage())
    return
  }

  if (!authorized(req)) {
    logWarn(`Unauthorized request: ${req.method} ${req.url} from ${req.socket.remoteAddress}`)
    sendJson(res, 401, { error: "Unauthorized" }, origin)
    return
  }

  try {
    // ── GET /health ──────────────────────────────────────────────────────────
    if (req.method === "GET" && req.url === "/health") {
      logInfo("Health check — OK")
      sendJson(res, 200, { ok: true, version: VERSION, port: PORT }, origin)
      return
    }

    // ── GET /discover ────────────────────────────────────────────────────────
    if (req.method === "GET" && req.url === "/discover") {
      logInfo("Discovering printers on the network…")
      const printers = await discoverPrinters()
      logInfo(`Discovery complete — found ${printers.length} printer(s)`)
      sendJson(res, 200, { printers }, origin)
      return
    }

    // ── POST /print ──────────────────────────────────────────────────────────
    if (req.method === "POST" && req.url === "/print") {
      const body = await readBody(req)
      const connection = (body.connection || "network").toString().trim()
      const dataBase64 = body.data_base64 || ""

      if (!dataBase64) {
        logWarn("Print request rejected — missing data_base64")
        sendJson(res, 422, { error: "data_base64 is required" }, origin)
        return
      }

      const data = Buffer.from(dataBase64, "base64")

      if (connection === "usb") {
        const device = (body.device || "").toString().trim()
        if (!device) {
          logWarn("Print request rejected — missing device for USB connection")
          sendJson(res, 422, { error: "device is required for USB connection (e.g. USB001)" }, origin)
          return
        }
        logInfo(`Sending ${data.length} bytes to USB device ${device} …`)
        try {
          await printToUsb(device, data)
          logOk(`Print SUCCESS — ${data.length} bytes sent to USB ${device}`)
          sendJson(res, 200, { ok: true, bytes: data.length }, origin)
        } catch (printErr) {
          logError(`Print FAILED — USB ${device} — ${printErr.message}`)
          sendJson(res, 500, { ok: false, error: printErr.message }, origin)
        }
      } else {
        const host = (body.host || "").toString().trim()
        const port = parseInt(body.port || "9100", 10)
        if (!host) {
          logWarn("Print request rejected — missing host for network connection")
          sendJson(res, 422, { error: "host is required for network connection" }, origin)
          return
        }
        logInfo(`Sending ${data.length} bytes to printer ${host}:${port} …`)
        try {
          await printToNetwork(host, port, data)
          logOk(`Print SUCCESS — ${data.length} bytes sent to ${host}:${port}`)
          sendJson(res, 200, { ok: true, bytes: data.length }, origin)
        } catch (printErr) {
          logError(`Print FAILED — ${host}:${port} — ${printErr.message}`)
          sendJson(res, 500, { ok: false, error: printErr.message }, origin)
        }
      }
      return
    }

    logWarn(`Not found: ${req.method} ${req.url}`)
    sendJson(res, 404, { error: "Not found" }, origin)
  } catch (err) {
    logError(`Unhandled error on ${req.method} ${req.url} — ${err.message}`)
    sendJson(res, 500, { ok: false, error: err.message }, origin)
  }
})

// ─── Startup ──────────────────────────────────────────────────────────────────

server.listen(PORT, HOST, () => {
  const divider = "─".repeat(60)
  console.log(divider)
  console.log("  Saqr Print Agent")
  console.log(`  Listening on : http://${HOST}:${PORT}`)
  console.log(`  Platform     : ${process.platform} (Node ${process.version})`)
  console.log(`  Auth token   : ${TOKEN ? "enabled" : "disabled (open)"}`)
  console.log(`  Config file  : ${CONFIG_PATH}`)
  console.log(`  Log file     : ${LOG_PATH}`)
  if (process.platform === "win32") {
    console.log("  Discovery    : Bonjour/dns-sd (install Bonjour for Windows if needed)")
  }
  console.log(divider)
  console.log("  Endpoints:")
  console.log(`    GET  http://${HOST}:${PORT}/         — status page`)
  console.log(`    GET  http://${HOST}:${PORT}/health   — status check`)
  console.log(`    GET  http://${HOST}:${PORT}/discover — browse network printers`)
  console.log(`    POST http://${HOST}:${PORT}/print    — send ESC/POS bytes to printer`)
  console.log(divider)
  console.log("  Press Ctrl+C to stop.")
  console.log(divider)
  logInfo("Agent ready — waiting for print jobs.")
})

server.on("error", (err) => {
  logError(`Server error: ${err.message}`)
  if (err.code === "EADDRINUSE") {
    logError(`Port ${PORT} is already in use. Is another instance running?`)
    logError(`Set a different port: $env:SAQR_PRINT_AGENT_PORT=9311  (PowerShell)`)
  }
  process.exit(1)
})

process.on("SIGINT", () => {
  logInfo("Shutting down — goodbye.")
  process.exit(0)
})

// Windows does not send SIGTERM from Task Manager; handle SIGHUP as a courtesy
process.on("SIGHUP", () => {
  logInfo("SIGHUP received — shutting down.")
  process.exit(0)
})
