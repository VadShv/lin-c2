"=== L2 C2 status $(Get-Date) ==="
$procs = Get-Process L2LogD,L2AuthD,Cached,L2Server,L2NPC -ErrorAction SilentlyContinue
foreach ($n in 'L2LogD','L2AuthD','Cached','L2Server','L2NPC') { $p = $procs | Where-Object Name -eq $n; if ($p) { "{0,-9} PID={1,-6} {2,5} MB  up since {3}" -f $n,$p.Id,[math]::Round($p.WorkingSet64/1MB),$p.StartTime.ToString('HH:mm:ss') } else { "{0,-9} NOT RUNNING" -f $n } }
$ports = @{3999='LogD';2106='Auth(client)';2104='Auth(world)';2006='CacheD';2008='CacheD(npc)';7777='Game';2002='L2Server(npc)'}
"ports: " + (($ports.Keys | Sort-Object | ForEach-Object { "$_=" + $(if (Get-NetTCPConnection -LocalPort $_ -State Listen -ErrorAction SilentlyContinue) {'up'} else {'DOWN'}) }) -join '  ')
$os = Get-CimInstance Win32_OperatingSystem; "RAM free: $([math]::Round($os.FreePhysicalMemory/1KB)) / $([math]::Round($os.TotalVisibleMemorySize/1KB)) MB   disk C: free $([math]::Round((Get-PSDrive C).Free/1GB,1)) GB"
