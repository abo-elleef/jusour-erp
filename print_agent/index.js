#!/usr/bin/env node
"use strict"

const http = require("http")
const net = require("net")
const { execFile, spawn } = require("child_process")
const { promisify } = require("util")

const execFileAsync = promisify(execFile)

const HOST = process.env.SAQR_PRINT_AGENT_HOST || "127.0.0.1"
const PORT = parseInt(process.env.SAQR_PRINT_AGENT_PORT || "9310", 10)
const TOKEN = process.env.SAQR_PRINT_AGENT_TOKEN || ""
const ALLOWED_ORIGINS = (process.env.SAQR_PRINT_AGENT_ORIGINS || "*")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean)
const CONNECT_TIMEOUT_MS = parseInt(process.env.SAQR_PRINT_CONNECT_TIMEOUT_MS || "5000", 10)
const DISCOVER_TIMEOUT_MS = parseInt(process.env.SAQR_PRINT_DISCOVER_TIMEOUT_MS || "4000", 10)

// ─── Logging ──────────────────────────────────────────────────────────────────

function ts() {
  return new Date().toISOString().replace("T", " ").replace("Z", "")
}

function log(level, message) {
  const prefix = `[${ts()}] [${level.padEnd(5)}]`
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

// ─── HTTP server ──────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const origin = req.headers.origin || ""

  if (req.method === "OPTIONS") {
    res.writeHead(204, corsHeaders(origin))
    res.end()
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
      sendJson(res, 200, { ok: true, version: "1.0.0", port: PORT }, origin)
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
      const host = (body.host || "").toString().trim()
      const port = parseInt(body.port || "9100", 10)
      const dataBase64 = body.data_base64 || ""

      if (!host || !dataBase64) {
        logWarn("Print request rejected — missing host or data_base64")
        sendJson(res, 422, { error: "host and data_base64 are required" }, origin)
        return
      }

      const data = Buffer.from(dataBase64, "base64")
      logInfo(`Sending ${data.length} bytes to printer ${host}:${port} …`)

      try {
        await printToNetwork(host, port, data)
        logOk(`Print SUCCESS — ${data.length} bytes sent to ${host}:${port}`)
        sendJson(res, 200, { ok: true, bytes: data.length }, origin)
      } catch (printErr) {
        logError(`Print FAILED — ${host}:${port} — ${printErr.message}`)
        sendJson(res, 500, { ok: false, error: printErr.message }, origin)
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
  if (process.platform === "win32") {
    console.log("  Discovery    : Bonjour/dns-sd (install Bonjour for Windows if needed)")
  }
  console.log(divider)
  console.log("  Endpoints:")
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
