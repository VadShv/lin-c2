# Run inside the supervisor before disruptive maintenance.
$ErrorActionPreference = 'Stop'
$connections = Get-NetTCPConnection -State Established -ErrorAction Stop
if ($connections | Where-Object { $_.LocalPort -eq 7777 }) {
    throw 'An active game connection exists; close clients before maintenance.'
}
