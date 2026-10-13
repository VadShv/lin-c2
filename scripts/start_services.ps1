# L2 C2 Server — Service Start/Stop/Check Scripts
# Usage: powershell -ExecutionPolicy Bypass -File start_services.ps1

$L2ServerDir = "C:\L2Server"
$PsExec = "C:\pstools\PsExec.exe"

# Service definitions: name, directory, executable, expected port
$services = @(
    @{Name="L2AuthD";   Dir="NewAuth";    Exe="L2AuthD.exe";  Port=2106},
    @{Name="CacheD";     Dir="CacheD";    Exe="CacheD.exe";   Port=2006},
    @{Name="L2LogD";     Dir="L2LogD";    Exe="L2LogD.exe";   Port=3999},
    @{Name="L2Server";   Dir="L2Server";  Exe="L2Server.exe"; Port=7777},
    @{Name="L2NPC";      Dir="L2NPC";     Exe="L2NPC.exe";    Port=0},
    @{Name="PetitionD";  Dir="Petition\PetitionD"; Exe="PetitionD.exe"; Port=0}
)

function Start-L2Service {
    param($svc)
    $exePath = Join-Path $L2ServerDir $svc.Dir
    $exe = Join-Path $exePath $svc.Exe
    
    if (-not (Test-Path $exe)) {
        Write-Output "  SKIP: $exe not found"
        return $false
    }
    
    # Check if already running
    $proc = Get-Process -Name $svc.Name -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Output "  Already running (PID=$($proc.Id))"
        return $true
    }
    
    Write-Output "  Starting $($svc.Name)..."
    & $PsExec -i 1 -accepteula -d -w $exePath $exe 2>&1 | Out-Null
    Start-Sleep -Seconds 5
    
    $proc = Get-Process -Name $svc.Name -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Output "  Started (PID=$($proc.Id), Threads=$($proc.Threads.Count))"
        if ($svc.Port -gt 0) {
            Start-Sleep -Seconds 3
            $port = Test-NetConnection -ComputerName localhost -Port $svc.Port -WarningAction SilentlyContinue
            Write-Output "  Port $($svc.Port): $($port.TcpTestSucceeded)"
        }
        return $true
    } else {
        Write-Output "  FAILED to start"
        return $false
    }
}

function Stop-L2Service {
    param($svc)
    $proc = Get-Process -Name $svc.Name -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-Process -Name $svc.Name -Force
        Write-Output "  Stopped $($svc.Name) (PID=$($proc.Id))"
    } else {
        Write-Output "  $($svc.Name) not running"
    }
}

function Check-L2Service {
    param($svc)
    $proc = Get-Process -Name $svc.Name -ErrorAction SilentlyContinue
    if ($proc) {
        $portStatus = ""
        if ($svc.Port -gt 0) {
            $port = Test-NetConnection -ComputerName localhost -Port $svc.Port -WarningAction SilentlyContinue
            $portStatus = " Port=$($svc.Port):$($port.TcpTestSucceeded)"
        }
        Write-Output "  $($svc.Name): RUNNING (PID=$($proc.Id), Threads=$($proc.Threads.Count)$portStatus)"
        return $true
    } else {
        Write-Output "  $($svc.Name): NOT RUNNING"
        return $false
    }
}

# Start all services in order
Write-Output "=== Starting L2 Services ==="
foreach ($svc in $services) {
    Start-L2Service $svc
    Start-Sleep -Seconds 2
}

# Check all services
Write-Output ""
Write-Output "=== Service Status ==="
foreach ($svc in $services) {
    Check-L2Service $svc
}
