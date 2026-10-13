$ErrorActionPreference='Stop'
if (Get-NetTCPConnection -State Established | Where-Object { $_.LocalPort -eq 7777 }) {
    throw 'Active game connection; maintenance refused.'
}
$dir='C:\L2Server\L2Server'
$source=Join-Path $dir 'L2Server483.exe'
$target=Join-Path $dir 'L2Server.exe'
if(-not(Test-Path $source)) {throw 'C2 binary is missing'}
Get-Process L2NPC,L2Server -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 4
Copy-Item $target "$target.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $source $target -Force
Get-FileHash $target -Algorithm SHA256 | Format-List | Out-String
& C:\l2work\start_l2.ps1 -Only L2Server,L2NPC
Start-Sleep 8
Show-ProcWindows L2Server
& 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE' -S 'localhost\SQLEXPRESS' -E -l 8 -W -Q 'SET NOCOUNT ON; SELECT * FROM lin2db.dbo.worldstatus;'
