$ErrorActionPreference='Stop'
if (Get-NetTCPConnection -State Established | Where-Object { $_.LocalPort -eq 7777 }) {
    throw 'Active game connection; maintenance refused.'
}
$f='C:\L2Server\L2Server\L2Server.exe'
$bytes=[IO.File]::ReadAllBytes($f)
# PE-verified GetProtocolVersion: mov eax, 481; add esp, 0x64; ret.
# The offset and adjacent bytes are guarded; this is not a broad binary search.
$offset=0x10105C
$expected=[byte[]](0xB8,0xE1,0x01,0x00,0x00,0x83,0xC4,0x64,0xC3)
for($i=0;$i -lt $expected.Length;$i++) {
    if($bytes[$offset+$i] -ne $expected[$i]) {throw "Unexpected binary at $($offset+$i); no changes applied"}
}
Get-Process L2NPC,L2Server -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 4
$backup="$f.bak-protocol481-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $f $backup
$bytes[$offset+1]=0xE5
[IO.File]::WriteAllBytes($f,$bytes)
$original=[IO.File]::ReadAllBytes($backup)
$changes=0
for($i=0;$i -lt $bytes.Length;$i++) {if($bytes[$i] -ne $original[$i]) {$changes++}}
if($changes -ne 1) {throw "Unexpected number of changed bytes: $changes"}
"Changed exactly $changes byte; protocol 481 -> 485; backup $backup"
Get-FileHash $f -Algorithm SHA256 | Format-List | Out-String
& C:\l2work\start_l2.ps1 -Only L2Server,L2NPC
Start-Sleep 8
& 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE' -S 'localhost\SQLEXPRESS' -E -l 8 -W -Q 'SET NOCOUNT ON; SELECT * FROM lin2db.dbo.worldstatus;'
