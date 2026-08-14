#!/usr/bin/env node
"use strict"

/**
 * Removes the SaqrPrintAgent Windows Service.
 * Must be run from an elevated (Administrator) PowerShell/CMD.
 *
 *   node uninstall-service.js
 */

if (process.platform !== "win32") {
  console.error("This script is for Windows only.")
  process.exit(1)
}

const { Service } = require("node-windows")
const path = require("path")

const svc = new Service({
  name:   "SaqrPrintAgent",
  script: path.join(__dirname, "index.js"),
})

svc.on("uninstall", () => {
  console.log("✔ Service uninstalled successfully.")
})

svc.on("error", (err) => {
  console.error("✖ Service error:", err)
})

console.log("Uninstalling SaqrPrintAgent Windows service…")
svc.uninstall()
