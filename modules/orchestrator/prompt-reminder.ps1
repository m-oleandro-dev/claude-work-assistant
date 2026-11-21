# Modulo orchestratore, gestore di UserPromptSubmit: breve promemoria della skill orchestrator.
param([string]$InputJson = '', [string]$Event = '')
$ErrorActionPreference = 'Continue'
$inp = $null
if ($InputJson) { try { $inp = $InputJson | ConvertFrom-Json } catch { } }
$prompt = if ($inp) { [string]$inp.prompt } else { '' }
if ($inp -and -not $prompt.Trim()) { exit 0 }
Write-Output "work-assistant: se il messaggio contiene piu richieste indipendenti o un compito delegabile (ricerca ampia, modifica in piu passi), segui la skill orchestrator: subagenti in parallelo, modello scelto per complessita (haiku banale, sonnet normale, opus complesso, fable solo se indispensabile). Se e una richiesta semplice, rispondi direttamente."
