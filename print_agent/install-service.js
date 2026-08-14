#!/usr/bin/env node
"use strict"

/**
 * Registers the Saqr Print Agent as a Windows Service.
 * Must be run once from an elevated (Administrator) PowerShell/CMD.
 *
 *   node install-service.js
 *
 * The service will:
 *   - Start automatically on Windows boot
 *   - Restart automatically if it crashes
 *   - Log stdout/stderr to  %PROGRAMDATA%\saqr-print-agent\
 */

if (process.platform !== "win32") {
  console.error("This script is for Windows only.")
  process.exit(1)
}

const { Service } = require("node-windows")
const path = require("path")

const svc = new Service({
  name:        "SaqrPrintAgent",
  description: "Saqr POS – local ESC/POS print bridge (network & USB printers)",
  script:      path.join(__dirname, "index.js"),
  nodeOptions: [],
  env: [
    // Override these by editing the service environment in Services.msc
    // or by setting them before running this installer.
    { name: "SAQR_PRINT_AGENT_HOST",  value: process.env.SAQR_PRINT_AGENT_HOST  || "127.0.0.1" },
    { name: "SAQR_PRINT_AGENT_PORT",  value: process.env.SAQR_PRINT_AGENT_PORT  || "9310" },
    { name: "SAQR_PRINT_AGENT_TOKEN", value: process.env.SAQR_PRINT_AGENT_TOKEN || "" },
    { name: "SAQR_PRINT_AGENT_ORIGINS", value: process.env.SAQR_PRINT_AGENT_ORIGINS || "*" },
  ],
})

svc.on("install", () => {
  console.log("✔ Service installed.")
  svc.start()
  console.log("✔ Service started — SaqrPrintAgent is now running.")
  console.log("")
  console.log("  Health check:  http://127.0.0.1:9310/health")
  console.log("  To stop:       net stop SaqrPrintAgent")
  console.log("  To uninstall:  node uninstall-service.js")
})

svc.on("alreadyinstalled", () => {
  console.log("ℹ Service is already installed. To reinstall, run uninstall-service.js first.")
})

svc.on("error", (err) => {
  console.error("✖ Service error:", err)
})

console.log("Installing SaqrPrintAgent Windows service…")
svc.install()
