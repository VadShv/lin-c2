# L2 C2 Server Setup Script
# Run on Windows Server 2019 with SQL Server 2019 Express already installed
# Configuration helper, NOT a complete installer. Run only during maintenance.
param(
    [string]$L2ServerDir = 'C:\L2Server',
    [string]$PublicIP = '176.53.225.183',
    [string]$DBUser = 'gamma',
    [string]$DBPassword = $env:L2_DB_PASSWORD
)
$ErrorActionPreference = 'Stop'
if (-not $DBPassword) { throw 'Set L2_DB_PASSWORD securely before setup; no default password is supplied.' }
if (Get-Process L2LogD,L2AuthD,Cached,L2Server,L2NPC -ErrorAction SilentlyContinue) {
    throw 'Stop the game chain during a maintenance window before running setup.'
}

# =============================================================================
# CONFIGURATION - Adjust these values for your environment
# =============================================================================
$SQLInstance = "localhost\SQLEXPRESS"

# =============================================================================
# STEP 1: Verify prerequisites
# =============================================================================
Write-Output "=== Step 1: Prerequisites ==="

if (-not (Test-Path $L2ServerDir)) {
    Write-Error "L2Server directory not found at $L2ServerDir"
    exit 1
}

$sql = Get-Service -Name "MSSQL`$SQLEXPRESS" -ErrorAction SilentlyContinue
if (-not $sql -or $sql.Status -ne "Running") {
    Write-Error "SQL Server Express must be installed and running"
    exit 1
}
Write-Output "Prerequisites OK"

# =============================================================================
# STEP 2: Configure INI files
# =============================================================================
Write-Output "=== Step 2: Configure INI files ==="

# Set all IPs to 127.0.0.1 in all INI files
Get-ChildItem $L2ServerDir -Recurse -Filter "*.ini" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $modified = $false
    
    # Replace IP addresses
    if ($content -match "address=\d+\.\d+\.\d+\.\d+") {
        $content = $content -replace "address=\d+\.\d+\.\d+\.\d+", "address=127.0.0.1"
        $modified = $true
    }
    
    if ($modified) {
        Set-Content $_.FullName -Value $content -NoNewline
        Write-Output "  Modified: $($_.FullName)"
    }
}

# Copy l2logd.ini to L2LOG.INI if needed
$l2logIni = Join-Path $L2ServerDir "L2LogD\l2logd.ini"
$l2logIni2 = Join-Path $L2ServerDir "L2LogD\L2LOG.INI"
if ((Test-Path $l2logIni) -and -not (Test-Path $l2logIni2)) {
    Copy-Item $l2logIni $l2logIni2
    Write-Output "  Created L2LOG.INI"
}

# =============================================================================
# STEP 3: Create File DSNs
# =============================================================================
Write-Output "=== Step 3: Create File DSNs ==="

$dsnTemplate = @"
[ODBC]
DRIVER=SQL Server
SERVER=localhost,1433
DATABASE={DB}
UID={USER}
PWD={PWD}
"@

# Define DSN files to create
$dsnFiles = @{
    "L2LogD\l2logd.dsn"    = "lin2log"
    "L2LogD\lin2report.dsn" = "lin2report"
    "L2LogD\linworld.dsn"   = "lin2log"
    "CacheD\l2cache.dsn"   = "lin2world"
    "CacheD\lin2comm.dsn"  = "lin2comm"
    "CacheD\lin2user.dsn"  = "lin2user"
    "NewAuth\L2Conn.dsn"   = "lin2db"
    "NewAuth\sldb.dsn"     = "lin2db"
}

foreach ($path in $dsnFiles.Keys) {
    $fullPath = Join-Path $L2ServerDir $path
    $db = $dsnFiles[$path]
    $content = $dsnTemplate.Replace('{DB}', $db).Replace('{USER}', $DBUser).Replace('{PWD}', $DBPassword)
    Set-Content $fullPath -Value $content -Force -Encoding ASCII
    Write-Output "  Created: $path -> $db"
}

# =============================================================================
# STEP 4: Configure registry
# =============================================================================
Write-Output "=== Step 4: Configure registry ==="

# L2LogD
$regPath = "HKLM:\SOFTWARE\WOW6432Node\PROJECT_L2\L2LOGD"
New-Item -Path $regPath -Force | Out-Null
Set-ItemProperty -Path $regPath -Name "DSN" -Value "$L2ServerDir\L2LogD\l2logd.dsn" -Type String
Set-ItemProperty -Path $regPath -Name "UID" -Value $DBUser -Type String
Set-ItemProperty -Path $regPath -Name "PWD" -Value $DBPassword -Type String
Set-ItemProperty -Path $regPath -Name "FILEDSN" -Value "$L2ServerDir\L2LogD\l2logd.dsn" -Type String
Set-ItemProperty -Path $regPath -Name "Server" -Value "127.0.0.1" -Type String
Set-ItemProperty -Path $regPath -Name "Port" -Value "3999" -Type String
Set-ItemProperty -Path $regPath -Name "World" -Value "1" -Type String
Set-ItemProperty -Path $regPath -Name "worldid" -Value "1" -Type String
Write-Output "  L2LOGD registry configured"

# CacheD
$regPath = "HKLM:\SOFTWARE\WOW6432Node\PROJECT_L2\L2CACHED"
New-Item -Path $regPath -Force | Out-Null
Set-ItemProperty -Path $regPath -Name "DSN" -Value "$L2ServerDir\CacheD\l2cache.dsn" -Type String
Set-ItemProperty -Path $regPath -Name "UID" -Value $DBUser -Type String
Set-ItemProperty -Path $regPath -Name "PWD" -Value $DBPassword -Type String
Set-ItemProperty -Path $regPath -Name "FILEDSN" -Value "$L2ServerDir\CacheD\l2cache.dsn" -Type String
Write-Output "  L2CACHED registry configured"

# L2Server
$regPath = "HKLM:\SOFTWARE\WOW6432Node\PROJECT_L2\L2SERVER"
New-Item -Path $regPath -Force | Out-Null
Set-ItemProperty -Path $regPath -Name "DSN" -Value "lin2world" -Type String
Set-ItemProperty -Path $regPath -Name "UID" -Value $DBUser -Type String
Set-ItemProperty -Path $regPath -Name "PWD" -Value $DBPassword -Type String
Write-Output "  L2SERVER registry configured"

# L2NPC
$regPath = "HKLM:\SOFTWARE\WOW6432Node\PROJECT_L2\L2NPC"
New-Item -Path $regPath -Force | Out-Null
Set-ItemProperty -Path $regPath -Name "DSN" -Value "lin2world" -Type String
Set-ItemProperty -Path $regPath -Name "UID" -Value $DBUser -Type String
Set-ItemProperty -Path $regPath -Name "PWD" -Value $DBPassword -Type String
Write-Output "  L2NPC registry configured"

# =============================================================================
# STEP 5: Configure L2AuthD
# =============================================================================
Write-Output "=== Step 5: Configure L2AuthD ==="

# The stock L2AuthD.exe / L2AuthD311.exe rejects the C2 client's
# RequestServerList format 4 after Agree. Keep the supplied C2 variant.
$c2AuthFile = "$L2ServerDir\NewAuth\L2AuthD483.exe"
$authFile = "$L2ServerDir\NewAuth\L2AuthD.exe"
if (Test-Path $c2AuthFile) {
    if (Get-Process L2AuthD -ErrorAction SilentlyContinue) {
        Write-Warning "AuthD is running; use scripts/switch_auth_c2.ps1 via L2Supervisor to switch safely."
    } else {
        if ((Test-Path $authFile) -and -not (Test-Path "$authFile.pre-c2")) {
            Copy-Item $authFile "$authFile.pre-c2"
        }
        Copy-Item $c2AuthFile $authFile -Force
        Write-Output "  C2-compatible L2AuthD483 selected"
    }
}
$configFile = "$L2ServerDir\NewAuth\etc\config.txt"
if (Test-Path $configFile) {
    $content = Get-Content $configFile -Raw
    # serverExPort is a TCP port, not the advertised server IP.
    # Anchor every key: unanchored "encrypt" also matches "NewEncrypt".
    $content = $content -replace '(?im)^serverExPort\s*=[^\r\n]*', 'serverExPort=2106'
    $content = $content -replace '(?im)^encrypt\s*=[^\r\n]*', 'encrypt=true'
    $content = $content -replace '(?im)^DevConnectOuter\s*=[^\r\n]*', 'DevConnectOuter=true'
    $content = $content -replace '(?im)^DevServerIP\s*=[^\r\n]*', "DevServerIP=$PublicIP"
    Set-Content $configFile -Value $content -NoNewline -Encoding ASCII
    Write-Output "  config.txt updated"
}

# =============================================================================
# STEP 6: Windows Firewall
# =============================================================================
Write-Output "=== Step 6: Firewall rules ==="

$ports = @(7777, 2106)
foreach ($port in $ports) {
    $ruleName = "L2 Server Port $port"
    if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
        Write-Output "  Added firewall rule for port $port"
    }
}

# =============================================================================
# STEP 7: Security review
# =============================================================================
Write-Output "=== Step 7: Security review ==="
Write-Output "  No DEP, antivirus or global security settings are changed."
Write-Output "  Review existing firewall rules separately; this script does not remove old rules."
Write-Output "  Configure 32-bit ODBC and the supervisor as described in docs/RUNBOOK.md."

# =============================================================================
# Complete
# =============================================================================
Write-Output ""
Write-Output "=== Setup Complete ==="
Write-Output "Next: use L2Supervisor: L2LogD -> L2AuthD -> Cached -> L2Server -> L2NPC."
Write-Output "This helper does not restore SQL schemas, install the supervisor or build the packet fix."
