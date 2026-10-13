$ErrorActionPreference='Stop'
$target='C:\L2Server\L2Server\L2Server.exe'
$source='C:\l2work\L2Server_C2_485_packetfix.exe'
$old=@('F813E4FD9498940147AB1C4F23B4FF37E12A7E9B029E872DB607AB7A33B4F6AC',
       '46BDA8BEEE36F99B25D8EA5EFB315323A92CE1A0A134F06CB4C9B1C38027C1F1')
$new='46BDA8BEEE36F99B25D8EA5EFB315323A92CE1A0A134F06CB4C9B1C38027C1F1'
$current=(Get-FileHash $target -Algorithm SHA256).Hash
if($current -eq $new) {
    'Confirmed baseline is already installed; no restart or replacement performed'
    return
}
if($current -notin $old) {throw 'Unexpected live binary; refusing replacement'}
if((Get-FileHash $source -Algorithm SHA256).Hash -ne $new) {throw 'Unexpected staged binary; refusing replacement'}
if(Get-NetTCPConnection -State Established | Where-Object { $_.LocalPort -eq 7777 }) {
    throw 'Client connection is active; close game before replacement'
}
$backup="$target.bak-packet485-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $target $backup
Get-Process L2NPC,L2Server -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 4
Copy-Item $source $target -Force
"Installed packet compatibility fix; original saved as $backup"
& C:\l2work\start_l2.ps1 -Only L2Server,L2NPC
Start-Sleep 8
Show-ProcWindows L2Server
& 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE' -S 'localhost\SQLEXPRESS' -E -l 8 -W -Q 'SET NOCOUNT ON; SELECT * FROM lin2db.dbo.worldstatus;'
Get-FileHash $target -Algorithm SHA256 | Format-List | Out-String
