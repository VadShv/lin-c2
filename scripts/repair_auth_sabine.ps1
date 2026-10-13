$ErrorActionPreference = 'Stop'
if (Get-NetTCPConnection -State Established | Where-Object { $_.LocalPort -eq 7777 }) {
    throw 'Active game connection; maintenance refused.'
}
$file = 'C:\L2Server\NewAuth\etc\config.txt'
$backup = "$file.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $file $backup
$text = [IO.File]::ReadAllText($file)
$text = [regex]::Replace($text, '(?im)^serverExPort\s*=[^\r\n]*', 'serverExPort=2106')
$text = [regex]::Replace($text, '(?im)^logdip\s*=[^\r\n]*', 'logdip="127.0.0.1"')
[IO.File]::WriteAllText($file, $text, [Text.Encoding]::ASCII)
"Backup: $backup"
Select-String -Path $file -Pattern '^serverPort|^serverExPort|^serverIntPort|^DevServerIP|^ProtocolVersion'
Get-Process L2AuthD -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
& C:\l2work\start_l2.ps1 -Only L2AuthD
Start-Sleep -Seconds 15
Show-ProcWindows L2AuthD
Get-NetTCPConnection | Where-Object {$_.LocalPort -in 2104,2106,2108 -or $_.RemotePort -eq 2104} |
    Select LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess | Format-Table | Out-String
foreach ($ip in '127.0.0.1','192.168.0.3') {
    $c = New-Object Net.Sockets.TcpClient
    try {
        $c.Connect($ip,2106)
        $s=$c.GetStream(); $s.ReadTimeout=5000; $buf=New-Object byte[] 32
        $n=$s.Read($buf,0,$buf.Length)
        if ($n -gt 0) { "$ip`:2106 $n bytes: " + [BitConverter]::ToString($buf,0,$n) }
        else { "$ip`:2106 EOF" }
    } catch { "$ip`:2106 ERROR: $($_.Exception.Message)" }
    finally { $c.Close() }
}
& 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE' `
    -S 'localhost\SQLEXPRESS' -E -l 8 -W `
    -Q 'SET NOCOUNT ON; SELECT id,name,ip,inner_ip,port FROM lin2db.dbo.server; SELECT * FROM lin2db.dbo.worldstatus;'
