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

function printToNetwork(host, port, data) {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host, port, timeout: CONNECT_TIMEOUT_MS }, () => {
      socket.write(data, (err) => {
        if (err) {
          socket.destroy()
          reject(err)
          return
        }
        socket.end()
      })
    })

    socket.on("error", reject)
    socket.on("timeout", () => {
      socket.destroy()
      reject(new Error(`Connection timed out after ${CONNECT_TIMEOUT_MS}ms`))
    })
    socket.on("close", () => resolve())
  })
}

async function discoverDarwin() {
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
      proc.kill("SIGTERM")
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
  if (process.platform === "darwin") {
    return discoverDarwin()
  }
  if (process.platform === "linux") {
    return discoverLinux()
  }
  return []
}

async function readBody(req) {
  const chunks = []
  for await (const chunk of req) chunks.push(chunk)
  const raw = Buffer.concat(chunks).toString("utf8")
  if (!raw) return {}
  return JSON.parse(raw)
}

const server = http.createServer(async (req, res) => {
  const origin = req.headers.origin || ""

  if (req.method === "OPTIONS") {
    res.writeHead(204, corsHeaders(origin))
    res.end()
    return
  }

  if (!authorized(req)) {
    sendJson(res, 401, { error: "Unauthorized" }, origin)
    return
  }

  try {
    if (req.method === "GET" && req.url === "/health") {
      sendJson(res, 200, { ok: true, version: "1.0.0", port: PORT }, origin)
      return
    }

    if (req.method === "GET" && req.url === "/discover") {
      const printers = await discoverPrinters()
      sendJson(res, 200, { printers }, origin)
      return
    }

    if (req.method === "POST" && req.url === "/print") {
      const body = await readBody(req)
      const host = (body.host || "").toString().trim()
      const port = parseInt(body.port || "9100", 10)
      const dataBase64 = body.data_base64 || ""

      if (!host || !dataBase64) {
        sendJson(res, 422, { error: "host and data_base64 are required" }, origin)
        return
      }

      const data = Buffer.from(dataBase64, "base64")
      await printToNetwork(host, port, data)
      sendJson(res, 200, { ok: true, bytes: data.length }, origin)
      return
    }

    sendJson(res, 404, { error: "Not found" }, origin)
  } catch (err) {
    sendJson(res, 500, { ok: false, error: err.message }, origin)
  }
})

server.listen(PORT, HOST, () => {
  console.log(`Saqr print agent listening on http://${HOST}:${PORT}`)
  if (TOKEN) console.log("Token authentication enabled")
})
