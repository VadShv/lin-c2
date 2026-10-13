param([string]$Variant='L2AuthD483.exe')
$ErrorActionPreference='Stop'
if (Get-NetTCPConnection -State Established | Where-Object { $_.LocalPort -eq 7777 }) {
    throw 'Active game connection; maintenance refused.'
}
$dir='C:\L2Server\NewAuth'
$source=Join-Path $dir $Variant
$target=Join-Path $dir 'L2AuthD.exe'
if(-not(Test-Path $source)) {throw "Missing $Variant"}
$backup="$target.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $target $backup
Get-Process L2NPC,L2Server,L2AuthD -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 4
try {
    Copy-Item $source $target -Force
    "Switched to $Variant; backup $backup"
    Get-FileHash $target -Algorithm SHA256 | Format-List | Out-String
    & C:\l2work\start_l2.ps1 -Only L2AuthD
    if(-not(Get-NetTCPConnection -State Listen -LocalPort 2106 -ErrorAction SilentlyContinue)) {
        Show-ProcWindows L2AuthD
        throw 'Replacement AuthD did not open 2106'
    }
} catch {
    "Rolling back AuthD: $($_.Exception.Message)"
    Get-Process L2AuthD -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 2
    Copy-Item $backup $target -Force
    & C:\l2work\start_l2.ps1 -Only L2AuthD
}
& C:\l2work\start_l2.ps1 -Only L2Server,L2NPC
Start-Sleep 8
Show-ProcWindows L2AuthD
& 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE' -S 'localhost\SQLEXPRESS' -E -l 8 -W -Q 'SET NOCOUNT ON; SELECT * FROM lin2db.dbo.worldstatus;'
