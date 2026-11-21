# Modulo voce, gestore degli eventi Stop, SubagentStop e PostToolUse (chiamato da core/dispatch.ps1).
# Mette in coda il testo da leggere; la lettura vera la fa speak-worker.ps1, uno alla volta.
#   -Source Stop          hook Stop: ultimo messaggio dell'agente principale
#   -Source SubagentStop  hook SubagentStop: resoconto finale di un subagente avviato con il marcatore [voce]
#   -Source Handback      hook PostToolUse su SubagentHandback: resoconto consegnato con quello strumento
param([string]$Source = 'Stop', [string]$InputJson = '', [string]$Event = '')
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'voice-queue.ps1')
if (Test-VoiceOff) { exit 0 }

$inp = Read-HookInput $InputJson
if (-not $inp) { exit 0 }
Write-VoiceLog "hook $Source ($($inp.hook_event_name)) agent_type='$($inp.agent_type)' agent_id='$($inp.agent_id)'"

$text = ''
switch ($Source) {
  'Stop' {
    $text = [string]$inp.last_assistant_message
    if (-not $text.Trim()) { $text = Get-LastAssistantText ([string]$inp.transcript_path) }
  }
  'SubagentStop' {
    # Gli agenti interni di Claude Code (suggerimenti, /btw) hanno agent_type vuoto: non si leggono.
    if (-not $inp.agent_type) { Write-VoiceLog 'agente interno ignorato'; exit 0 }
    $atp = Get-SubagentTranscript $inp
    $marked = Test-SubagentMarked $atp
    if ($marked -eq $false) { Write-VoiceLog "subagente senza marcatore $script:VoiceMarker, non letto"; exit 0 }
    if ($null -eq $marked) { Write-VoiceLog "transcript del subagente non trovato ($atp): leggo comunque" }
    # Se il subagente ha consegnato con SubagentHandback, il resoconto e quel messaggio, non last_assistant_message.
    $text = Get-HandbackText $atp
    if (-not $text.Trim()) { $text = [string]$inp.last_assistant_message }
    if (-not $text.Trim()) { $text = Get-LastAssistantText $atp }
  }
  'Handback' {
    if ($inp.tool_name -and $inp.tool_name -ne 'SubagentHandback') { exit 0 }
    $atp = Get-SubagentTranscript $inp
    $marked = Test-SubagentMarked $atp
    if ($marked -eq $false) { Write-VoiceLog "subagente senza marcatore $script:VoiceMarker, non letto"; exit 0 }
    $text = [string]$inp.tool_input.message
  }
  default { Write-VoiceLog "Source sconosciuta: $Source"; exit 0 }
}

$text = ConvertTo-SpokenText $text
Write-VoiceLog "testo trovato ($Source): $($text.Length) caratteri"
if ($text) { [void](Add-VoiceQueueItem $text $Source) }
exit 0
