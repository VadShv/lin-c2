param([string]$Output='C:\l2work\game-debug.etl')
$ErrorActionPreference='Stop'
& pktmon filter list
& pktmon filter add L2GameDebug -t TCP -p 7777
if($LASTEXITCODE -ne 0) {throw 'Unable to add game filter'}
& pktmon start --capture --pkt-size 0 `
    --file-name $Output --file-size 16 --log-mode circular
if($LASTEXITCODE -ne 0) {throw 'Unable to start game capture'}
"Capture is active; filter added for TCP 7777, 16 MB circular file."
"Review pre-existing filters; stop with pktmon stop. Captures must remain private."
