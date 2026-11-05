# Saqr Print Agent — system tray status icon.
# Green = agent answering, red = not answering. Double-click opens the status page.
# Runs per user at logon (started by run-tray.vbs); the agent itself runs as a boot-time task.
$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Only one tray icon per user session.
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\SaqrPrintAgentTray", [ref]$createdNew)
if (-not $createdNew) { exit }

$dataDir = Join-Path $env:ProgramData "SaqrPrintAgent"
$port = 9310
try {
  $cfg = Get-Content (Join-Path $dataDir "config.json") -Raw | ConvertFrom-Json
  if ($cfg.port) { $port = [int]$cfg.port }
} catch {}
$url = "http://127.0.0.1:$port/"

function New-DotIcon([System.Drawing.Color]$color) {
  $bmp = New-Object System.Drawing.Bitmap 32, 32
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)
  $brush = New-Object System.Drawing.SolidBrush $color
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2
  $g.FillEllipse($brush, 3, 3, 26, 26)
  $g.DrawEllipse($pen, 3, 3, 26, 26)
  $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
  $g.Dispose(); $brush.Dispose(); $pen.Dispose(); $bmp.Dispose()
  return $icon
}

$iconUp   = New-DotIcon ([System.Drawing.Color]::FromArgb(22, 163, 74))
$iconDown = New-DotIcon ([System.Drawing.Color]::FromArgb(220, 38, 38))

function Test-Agent {
  try {
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Timeout = 1500
    $req.Proxy = $null
    $res = $req.GetResponse()
    $ok = ($res.StatusCode -eq 200)
    $res.Close()
    return $ok
  } catch { return $false }
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = $iconDown
$notify.Text = "Saqr Print Agent - checking..."
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$openStatus = $menu.Items.Add("Open status page")
$openLog    = $menu.Items.Add("Open log folder")
[void]$menu.Items.Add("-")
$exitItem   = $menu.Items.Add("Hide tray icon")
$notify.ContextMenuStrip = $menu

$openStatus.add_Click({ Start-Process $url })
$notify.add_DoubleClick({ Start-Process $url })
$openLog.add_Click({ Start-Process $dataDir })
$exitItem.add_Click({
  $timer.Stop()
  $notify.Visible = $false
  $notify.Dispose()
  [System.Windows.Forms.Application]::Exit()
})

$script:up = $null
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$check = {
  $now = Test-Agent
  if ($now -ne $script:up) {
    $previous = $script:up
    $script:up = $now
    if ($now) {
      $notify.Icon = $iconUp
      $notify.Text = "Saqr Print Agent - running"
      if ($previous -eq $false) { $notify.ShowBalloonTip(3000, "Saqr Print Agent", "Agent is running again.", [System.Windows.Forms.ToolTipIcon]::Info) }
    } else {
      $notify.Icon = $iconDown
      $notify.Text = "Saqr Print Agent - NOT running"
      $notify.ShowBalloonTip(5000, "Saqr Print Agent", "Agent is not running - receipts will not print.", [System.Windows.Forms.ToolTipIcon]::Warning)
    }
  }
}
$timer.add_Tick($check)
& $check
$timer.Start()

[System.Windows.Forms.Application]::Run()
