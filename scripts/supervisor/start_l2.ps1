# Start L2 daemons as children of the supervisor (same window station => dialogs can be auto-filled).
# Usage: start_l2.ps1 [-Only L2LogD,L2AuthD,...]  (default: all, in dependency order)
param([string[]]$Only)
$L2 = 'C:\L2Server'
$only = $Only
$DBUSER = 'gamma'; $DBPWD = $env:L2_DB_PASSWORD
# Private local config is excluded from Git. Provision it with restrictive ACLs.
if (Test-Path 'C:\l2work\local.ps1') { . 'C:\l2work\local.ps1' }
if (-not $DBPWD) { throw 'Set L2_DB_PASSWORD or private C:\l2work\local.ps1 ($DBPWD) before starting.' }
$svcs = @(
  @{N='L2LogD';  D="$L2\L2logD";  E='L2LogD.exe';  Port=3999; Wait=20;  Dlg=@{'LogDB Login'='linworld'; 'BBS Login'='lin2report'}},
  @{N='L2AuthD'; D="$L2\NewAuth"; E='L2AuthD.exe'; Port=2106; Wait=20;  Dlg=@{'L2 ODBC Connection Info'='L2Conn'}},
  @{N='Cached';  D="$L2\CacheD";  E='Cached.exe';  Port=2006; Wait=30;  Dlg=@{}},
  @{N='L2Server';D="$L2\L2Server";E='L2Server.exe';Port=7777; Wait=180; Dlg=@{}},
  @{N='L2NPC';   D="$L2\L2NPC";   E='L2NPC.exe';   Port=0;    Wait=40;  Dlg=@{}}
)
function Fill-OdbcDialog($dlg, $dsn) {
  [void][W]::SendMessage([W]::GetDlgItem($dlg,1000), 0x000C, [IntPtr]::Zero, $dsn)
  [void][W]::SendMessage([W]::GetDlgItem($dlg,1001), 0x000C, [IntPtr]::Zero, $DBUSER)
  [void][W]::SendMessage([W]::GetDlgItem($dlg,1002), 0x000C, [IntPtr]::Zero, $DBPWD)
  [void][W]::PostMessage($dlg, 0x0111, [IntPtr]1, [W]::GetDlgItem($dlg,1))
}
foreach ($s in $svcs) {
  if ($only -and $only -notcontains $s.N) { continue }
  if (Get-Process -Name $s.N -ErrorAction SilentlyContinue) { "$($s.N): already running"; continue }
  $p = Start-Process -FilePath "$($s.D)\$($s.E)" -WorkingDirectory $s.D -PassThru
  $deadline = (Get-Date).AddSeconds($s.Wait); $ok = $false; $notes = @()
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 1500
    if ($p.HasExited) { break }
    foreach ($d in ([W]::Tops([uint32]$p.Id) | Where-Object { [W]::Cls($_) -eq '#32770' })) {
      $title = [W]::Txt($d)
      if ($s.Dlg.ContainsKey($title)) { Fill-OdbcDialog $d $s.Dlg[$title]; $notes += "auto-filled '$title' with DSN $($s.Dlg[$title])" }
      else { $notes += "DIALOG '$title': " + (([W]::Children($d) | ForEach-Object {
        if ([W]::GetDlgCtrlID($_) -eq 1002) { '[credential field redacted]' } else { [W]::Txt($_) }
      } | Where-Object { $_ }) -join ' | ') }
    }
    if ($s.Port -ne 0 -and (Get-NetTCPConnection -LocalPort $s.Port -State Listen -ErrorAction SilentlyContinue)) { $ok = $true; break }
    if ($s.Port -eq 0 -and $s.N -eq 'L2NPC' -and (Get-NetTCPConnection -OwningProcess $p.Id -RemotePort 2002 -State Established -ErrorAction SilentlyContinue)) { $ok = $true; break }
  }
  if ($p.HasExited) { "$($s.N): EXITED code=$($p.ExitCode)" } else { $p.Refresh(); "$($s.N): PID=$($p.Id) mem=$([math]::Round($p.WorkingSet64/1MB))MB ready=$ok" }
  $notes | Select -Unique | ForEach-Object { "   $_" }
  if (-not $ok -and -not $p.HasExited) { "   WARNING: $($s.N) not ready within $($s.Wait)s" }
}
