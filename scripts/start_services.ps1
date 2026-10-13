# Compatibility entry point: queue startup rather than launching via PsExec/SSH.
$ErrorActionPreference = 'Stop'
$queue = 'C:\l2work\cmd'
if (-not (Test-Path $queue)) { throw 'Supervisor queue is missing; follow docs/RUNBOOK.md.' }
$name = 'start-' + [Guid]::NewGuid().ToString('N')
Set-Content "$queue\$name.tmp" '& C:\l2work\start_l2.ps1' -Encoding UTF8
Move-Item "$queue\$name.tmp" "$queue\$name.ps1"
"Queued $name; inspect C:\l2work\out\$name.txt. No PsExec/session-1 startup is used."
