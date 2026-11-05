# Registers (or removes) the logon task that keeps the Saqr Print Agent running.
# Called by the installer; safe to run by hand from an elevated PowerShell.
param(
  [Parameter(Mandatory = $true)][ValidateSet("install", "remove")][string]$Action,
  [string]$InstallDir = $PSScriptRoot
)

$TaskName = "SaqrPrintAgent"
$ErrorActionPreference = "Stop"

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Get-Process -Name "SaqrPrintAgent" -ErrorAction SilentlyContinue | Stop-Process -Force

if ($Action -eq "remove") { exit 0 }

$action    = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$InstallDir\run-hidden.vbs`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn
# Run for whichever user logs in (the POS machine's cashier account), not as SYSTEM,
# so USB printer ports behave the same as in a normal desktop session.
$principal = New-ScheduledTaskPrincipal -GroupId "S-1-5-32-545" -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
  -Principal $principal -Settings $settings -Description "Saqr POS print bridge" | Out-Null
Start-ScheduledTask -TaskName $TaskName
