# L2 supervisor: long-lived process started by the 'L2Supervisor' scheduled task (Administrator, session 0).
# - On boot: if C:\l2work\autostart.enabled exists, waits for SQL Server and starts the whole L2 chain.
# - Executes command scripts dropped into C:\l2work\cmd\*.ps1 (output -> C:\l2work\out\<name>.txt).
$ErrorActionPreference = 'Continue'; $ProgressPreference = 'SilentlyContinue'
$base = 'C:\l2work'; $cmd = "$base\cmd"; $out = "$base\out"; $done = "$base\done"
foreach ($d in $cmd,$out,$done) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
. "$base\win32.ps1"
function Log($m) { Add-Content "$base\supervisor.log" "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" }
Log "supervisor started PID=$PID session=$((Get-Process -Id $PID).SessionId) station=$([W]::Station())"
if (Test-Path "$base\autostart.enabled") {
  $up = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
  if ($up.TotalMinutes -lt 10 -and -not (Get-Process L2Server -ErrorAction SilentlyContinue)) {
    Log "boot detected (uptime $([int]$up.TotalSeconds)s): waiting for SQL Server"
    $t0 = Get-Date
    while (((Get-Service 'MSSQL$SQLEXPRESS').Status -ne 'Running') -and ((Get-Date) - $t0).TotalMinutes -lt 5) { Start-Sleep 5 }
    Start-Sleep 20
    Log "autostart: running start_l2.ps1"
    $r = & "$base\start_l2.ps1" 2>&1 | Out-String
    Log "autostart result:`n$r"
  }
}
while ($true) {
  foreach ($f in (Get-ChildItem $cmd -Filter *.ps1 | Sort-Object Name)) {
    $name = $f.BaseName
    $res = try { & $f.FullName 2>&1 | Out-String } catch { "EXCEPTION: $($_ | Out-String)" }
    Set-Content -Path "$out\$name.tmp" -Value $res -Encoding UTF8
    Move-Item "$out\$name.tmp" "$out\$name.txt" -Force
    Move-Item $f.FullName "$done\$($f.Name)" -Force
    Log "ran $name"
  }
  Start-Sleep -Milliseconds 1500
}
