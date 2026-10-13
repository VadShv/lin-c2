$ErrorActionPreference='Stop'
if (Get-NetTCPConnection -State Established | Where-Object { $_.LocalPort -eq 7777 }) {
    throw 'Active game connection; maintenance refused.'
}
$f='C:\L2Server\L2Server\l2server.ini'
Copy-Item $f "$f.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
$text=[IO.File]::ReadAllText($f)
$text=[regex]::Replace($text,'(?im)^reconnectauth\s*=[^\r\n]*','reconnectauth=1')
[IO.File]::WriteAllText($f,$text,[Text.Encoding]::ASCII)
$sql='C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE'
& $sql -S 'localhost\SQLEXPRESS' -E -b -l 8 -W -Q "SET NOCOUNT ON; IF NOT EXISTS (SELECT 1 FROM lin2db.dbo.worldstatus WHERE idx=1) INSERT INTO lin2db.dbo.worldstatus(idx,server,status) VALUES(1,'Bartz',0);"
if($LASTEXITCODE -ne 0) {throw 'SQL failed'}
Get-Process L2NPC,L2Server -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 4
& C:\l2work\start_l2.ps1 -Only L2Server,L2NPC
Start-Sleep 10
& $sql -S 'localhost\SQLEXPRESS' -E -l 8 -W -Q 'SET NOCOUNT ON; SELECT * FROM lin2db.dbo.worldstatus;'
Get-ChildItem C:\L2Server\L2Server\log\system -File | Sort LastWriteTime -Descending | Select -First 1 | ForEach-Object {Get-Content $_.FullName -Tail 14}
