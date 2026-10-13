# Provision on a restored/stopped VM only. Never run against an active game session.
param(
    [PSCredential]$Credential,
    [string]$Base = 'C:\l2work'
)
$ErrorActionPreference = 'Stop'
if (Get-Process L2LogD,L2AuthD,Cached,L2Server,L2NPC -ErrorAction SilentlyContinue) {
    throw 'Stop game processes before installing/updating the supervisor.'
}
if ($Base -ne 'C:\l2work') { throw 'Current supervisor scripts require C:\l2work.' }
if (Get-ScheduledTask -TaskName L2Supervisor -ErrorAction SilentlyContinue) {
    throw 'Task already exists; review existing task/config manually before updating.'
}
if (-not $Credential) { $Credential = Get-Credential -Message 'Windows account for L2Supervisor (not SQL)' }
New-Item -ItemType Directory -Path $Base -Force | Out-Null
& icacls.exe $Base /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to restrict supervisor directory ACLs.' }
Copy-Item "$PSScriptRoot\supervisor\*.ps1" $Base -Force
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\l2work\supervisor.ps1'
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -MultipleInstances IgnoreNew
# Task Scheduler requires the account password at registration; it is never written to a script.
Register-ScheduledTask -TaskName L2Supervisor -Action $action -Trigger $trigger -Settings $settings `
    -User $Credential.UserName -Password $Credential.GetNetworkCredential().Password -RunLevel Highest | Out-Null
'Task registered, NOT started. Provision private DB credentials and review docs/RUNBOOK.md first.'
