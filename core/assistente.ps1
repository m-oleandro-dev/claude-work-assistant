# Comando /assistente del plugin work-assistant.
#   assistente.ps1 [status]              elenca i moduli con stato on/off
#   assistente.ps1 <modulo> on|off       attiva / disattiva un modulo (override per utente)
#   assistente.ps1 <modulo> reset        torna al valore predefinito del modulo
#   assistente.ps1 <modulo> [status]     stato del modulo e sottocomandi disponibili
#   assistente.ps1 <modulo> <comando>    sottocomando del modulo (es. voce install)
# <modulo> accetta il nome o un alias (voice / voce, orchestrator / orchestratore).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common.ps1')
$a = @($args | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() })

function Get-StateLabel($m) {
  $s = Get-WAModuleState $m
  $lbl = if ($s -eq 'on') { 'ATTIVO' } else { 'DISATTIVATO' }
  $src = if ((Get-WAState).ContainsKey($m.Name)) { "impostato; predefinito: $($m.Default)" } else { 'predefinito' }
  return "$lbl ($src)"
}

function Show-Status {
  $mods = Get-WAModules
  'Moduli di work-assistant:'
  foreach ($m in $mods) {
    $al = if ($m.Aliases.Count) { " ($($m.Aliases -join ', '))" } else { '' }
    "- $($m.Name)${al}: $(Get-StateLabel $m) - $($m.Description)"
  }
  "Uso: /assistente <modulo> on|off|reset, /assistente <modulo> <comando>"
}

function Invoke-OnChange($m, [string]$state) {
  if (-not $m.OnChange) { return }
  try { Invoke-WAModuleScript $m $m.OnChange @{ State = $state } }
  catch { Write-WALog "on_change di $($m.Name): $($_.Exception.Message)"; "Avviso: $($_.Exception.Message)" }
}

if ($a.Count -eq 0 -or $a[0].ToLowerInvariant() -eq 'status' -or $a[0].ToLowerInvariant() -eq 'stato') { Show-Status; exit 0 }

$m = Resolve-WAModule $a[0]
if (-not $m) {
  "Modulo sconosciuto: $($a[0])."
  Show-Status
  exit 0
}
$cmd = if ($a.Count -ge 2) { $a[1].ToLowerInvariant() } else { 'status' }
$rest = @()
if ($a.Count -gt 2) { $rest = $a[2..($a.Count - 1)] }

switch ($cmd) {
  { $_ -in 'on', 'attiva' } {
    Set-WAState $m.Name 'on'
    Write-WALog "assistente: $($m.Name) on"
    Invoke-OnChange $m 'on'
    "Modulo $($m.Name): ATTIVO"
  }
  { $_ -in 'off', 'disattiva' } {
    Set-WAState $m.Name 'off'
    Write-WALog "assistente: $($m.Name) off"
    Invoke-OnChange $m 'off'
    "Modulo $($m.Name): DISATTIVATO"
  }
  'reset' {
    Set-WAState $m.Name ''
    $s = Get-WAModuleState $m
    Invoke-OnChange $m $s
    "Modulo $($m.Name): torna al predefinito ($s)"
  }
  { $_ -in 'status', 'stato' } {
    "Modulo $($m.Name): $(Get-StateLabel $m) - $($m.Description)"
    if ($m.Commands.Count) { "Comandi: $(($m.Commands.Keys | Sort-Object) -join ', ')" }
  }
  default {
    if ($m.Commands.ContainsKey($cmd)) {
      try { Invoke-WAModuleScript $m $m.Commands[$cmd] @{ Arguments = $rest } }
      catch { "Errore nel comando $cmd del modulo $($m.Name): $($_.Exception.Message)" }
    } else {
      "Comando sconosciuto per il modulo $($m.Name): $cmd. Disponibili: on, off, reset, status$(if ($m.Commands.Count) { ', ' + (($m.Commands.Keys | Sort-Object) -join ', ') })"
    }
  }
}
exit 0
