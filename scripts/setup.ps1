# L2 C2 Server Setup Script
# Run on Windows Server 2019 with SQL Server 2019 Express already installed
# Usage: powershell -ExecutionPolicy Bypass -File setup.ps1

# =============================================================================
# CONFIGURATION - Adjust these values for your environment
# =============================================================================
$L2ServerDir = "C:\L2Server"
$PublicIP = "136.234.76.201"  # Change to your VM's public IP
$SQLInstance = "localhost\SQLEXPRESS"
$DBUser = "gamma"
# $DBPassword = "lineage2pwd"  # Set this securely, do not hardcode

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
if (Test-Path $l2logIni -and -not (Test-Path $l2logIni2)) {
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
    "CacheD\l2cache.dsn"   = "lin2world"
    "CacheD\lin2comm.dsn"  = "lin2comm"
    "CacheD\lin2user.dsn"  = "lin2user"
    "NewAuth\L2Conn.dsn"   = "lin2db"
    "NewAuth\sldb.dsn"     = "lin2db"
}

foreach ($path in $dsnFiles.Keys) {
    $fullPath = Join-Path $L2ServerDir $path
    $db = $dsnFiles[$path]
    $content = $dsnTemplate -replace "{DB}", $db -replace "{USER}", $DBUser -replace "{PWD}", $DBPassword
    Set-Content $fullPath -Value $content -Force
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
Set-ItemProperty -Path $regPath -Name "World" -Value "3" -Type String
Set-ItemProperty -Path $regPath -Name "worldid" -Value "3" -Type String
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

$configFile = "$L2ServerDir\NewAuth\etc\config.txt"
if (Test-Path $configFile) {
    $content = Get-Content $configFile -Raw
    $content = $content -replace "encrypt\s*=\s*true", "encrypt = false"
    $content = $content -replace "DevServerIP\s*=\s*true", "DevServerIP = false"
    $content = $content -replace "serverexport\s*=\s*[\d\.]+", "serverexport = $PublicIP"
    Set-Content $configFile -Value $content -NoNewline
    Write-Output "  config.txt updated"
}

# =============================================================================
# STEP 6: Windows Firewall
# =============================================================================
Write-Output "=== Step 6: Firewall rules ==="

$ports = @(2104, 7777, 2106, 3999, 2006, 2008)
foreach ($port in $ports) {
    $ruleName = "L2 Server Port $port"
    if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
        Write-Output "  Added firewall rule for port $port"
    }
}

# =============================================================================
# STEP 7: Disable DEP
# =============================================================================
Write-Output "=== Step 7: DEP ==="
Write-Output "  DEP should be disabled via: bcdedit /set nx AlwaysOff"
Write-Output "  A reboot is required after changing DEP settings."

# =============================================================================
# Complete
# =============================================================================
Write-Output ""
Write-Output "=== Setup Complete ==="
Write-Output "Next: Start services in order: L2AuthD -> CacheD -> L2LogD -> L2Server -> L2NPC -> PetitionD"
Write-Output "Note: L2LogD shows a login dialog that must be filled manually (see docs/STATUS.md)"
