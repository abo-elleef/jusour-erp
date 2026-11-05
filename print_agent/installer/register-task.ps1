# Stops the agent (and its restart loop) and removes the old logon task from
# versions before 1.2.1. Called by the installer and uninstaller.
$ErrorActionPreference = "SilentlyContinue"

Unregister-ScheduledTask -TaskName "SaqrPrintAgent" -Confirm:$false

# Stop the restart loop first, otherwise it relaunches the agent.
Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" |
  Where-Object { $_.CommandLine -like "*run-hidden.vbs*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like "*SaqrPrintAgent*tray.ps1*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-Process -Name "SaqrPrintAgent" | Stop-Process -Force
exit 0
