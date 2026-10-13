foreach ($n in 'L2NPC','L2Server','Cached','L2AuthD','L2LogD') { $p = Get-Process -Name $n -ErrorAction SilentlyContinue; if ($p) { $p | Stop-Process -Force; "$n stopped" }; Start-Sleep 1 }
