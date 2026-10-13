# Stop all L2 services in reverse order
$ErrorActionPreference = 'Stop'
if (Get-NetTCPConnection -State Established | Where-Object { $_.LocalPort -eq 7777 }) {
    throw 'Active game connection; close clients before stopping.'
}
$services = @("PetitionD", "L2NPC", "L2Server", "L2LogD", "CacheD", "L2AuthD")

Write-Output "=== Stopping L2 Services ==="
foreach ($name in $services) {
    $proc = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-Process -Name $name -Force
        Write-Output "  Stopped $name (PID=$($proc.Id))"
    } else {
        Write-Output "  $name not running"
    }
    Start-Sleep -Seconds 1
}
Write-Output "All services stopped"
