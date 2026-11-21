# Modulo orchestratore, gestore di SessionStart.
# Aggiunge al contesto una nota sul modello consigliato per la sessione principale (Sonnet).
# Il campo "model" dell'input di SessionStart e facoltativo (puo mancare dopo /clear o un ripristino).
param([string]$InputJson = '', [string]$Event = '')
$ErrorActionPreference = 'Continue'
$inp = $null
if ($InputJson) { try { $inp = $InputJson | ConvertFrom-Json } catch { } }
$source = if ($inp) { [string]$inp.source } else { '' }
if ($source -eq 'compact') { exit 0 }  # dopo una compattazione non serve ripeterlo
$model = if ($inp) { [string]$inp.model } else { '' }

if ($model -and $model -match 'sonnet') {
  Write-Output "work-assistant: la sessione principale fa da orchestratore (skill orchestrator) e usa gia Sonnet, il modello consigliato: non serve dirlo all'utente."
} elseif ($model) {
  Write-Output "work-assistant: la sessione principale fa da orchestratore (skill orchestrator). Modello attuale: $model; per l'orchestratore e consigliato Sonnet (veloce ma affidabile nel dividere le richieste e valutarne la complessita; Haiku e troppo debole per pianificare). Nella tua prima risposta dillo all'utente in una frase e suggerisci /model sonnet, senza insistere."
} else {
  Write-Output "work-assistant: la sessione principale fa da orchestratore (skill orchestrator). Per l'orchestratore e consigliato Sonnet (veloce ma affidabile nel dividere le richieste; Haiku e troppo debole per pianificare). Se non stai gia usando Sonnet, nella tua prima risposta dillo all'utente in una frase e suggerisci /model sonnet, senza insistere."
}
