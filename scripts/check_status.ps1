# Check status of all L2 services and connections
Write-Output "=== L2 Service Status ==="
Write-Output "Date: $(Get-Date)"
Write-Output ""

$services = @(
    @{Name="L2AuthD";   Port=2106;  DB="lin2db"},
    @{Name="CacheD";     Port=2006;  DB="lin2world"},
    @{Name="L2LogD";     Port=3999;  DB="lin2log"},
    @{Name="L2Server";   Port=7777;  DB="lin2world"},
    @{Name="L2NPC";      Port=0;     DB="lin2world"},
    @{Name="PetitionD";  Port=0;     DB="petition"}
)

foreach ($svc in $services) {
    $proc = Get-Process -Name $svc.Name -ErrorAction SilentlyContinue
    if ($proc) {
        $portStr = ""
        if ($svc.Port -gt 0) {
            $port = Test-NetConnection -ComputerName localhost -Port $svc.Port -WarningAction SilentlyContinue
            $portStr = " Port=$($svc.Port):$($port.TcpTestSucceeded)"
        }
        Write-Output "$($svc.Name): RUNNING (PID=$($proc.Id), Threads=$($proc.Threads.Count)$portStr)"
    } else {
        Write-Output "$($svc.Name): NOT RUNNING"
    }
}

Write-Output ""
Write-Output "=== SQL Server ==="
Get-Service -Name "MSSQL`$SQLEXPRESS" | Format-Table Name, Status -AutoSize

Write-Output "=== ODBC Connections ==="
$conns = netstat -an | Select-String "1433" | Select-String "ESTABLISHED"
if ($conns) {
    $conns | ForEach-Object { Write-Output "  $_" }
} else {
    Write-Output "  No ODBC connections"
}

Write-Output "=== Listening Ports ==="
$ports = @(2104, 2106, 3999, 2006, 2008, 7777)
foreach ($p in $ports) {
    $tcp = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($tcp) {
        Write-Output "  Port $p: LISTENING"
    } else {
        Write-Output "  Port $p: not listening"
    }
}
