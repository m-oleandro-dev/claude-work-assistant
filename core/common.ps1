# Funzioni comuni del plugin work-assistant (dot-source): log, elenco dei moduli, stato on/off.
# File solo ASCII: PowerShell 5.1 legge come ANSI gli script senza BOM.
#
# Stato dei moduli: %USERPROFILE%\.claude\work-assistant\state.json  ->  { "modules": { "voice": "on" } }
# Un modulo senza voce nello stato usa il "default" del suo module.json.
# CLAUDE_WORK_ASSISTANT_HOME sposta la cartella dei dati utente (utile per i test).

$script:WARoot = Split-Path -Parent $PSScriptRoot
$script:WAHome = if ($env:CLAUDE_WORK_ASSISTANT_HOME) { $env:CLAUDE_WORK_ASSISTANT_HOME } else { Join-Path $env:USERPROFILE '.claude\work-assistant' }
$script:WAState = Join-Path $script:WAHome 'state.json'
$script:WALog = Join-Path $env:TEMP 'claude-work-assistant.log'

function Write-WALog([string]$msg) {
  try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') [$PID] $msg" | Add-Content -Path $script:WALog -Encoding UTF8 } catch { }
}

# Converte un PSCustomObject (da ConvertFrom-Json) in hashtable, solo il primo livello.
function ConvertTo-WAHashtable($obj) {
  $h = @{}
  if ($null -eq $obj) { return $h }
  foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
  return $h
}

# Moduli installati: ogni cartella modules\<nome>\ con un module.json valido, ordinati per "order" e nome.
function Get-WAModules {
  $dir = Join-Path $script:WARoot 'modules'
  $list = @()
  foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)) {
    $mf = Join-Path $d.FullName 'module.json'
    if (-not (Test-Path -LiteralPath $mf)) { continue }
    try {
      $j = [IO.File]::ReadAllText($mf, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch { Write-WALog "module.json non valido in $($d.Name): $($_.Exception.Message)"; continue }
    $name = if ($j.name) { [string]$j.name } else { $d.Name }
    $def = if ([string]$j.default -eq 'on') { 'on' } else { 'off' }
    $order = 100
    if ($null -ne $j.order) { $order = [int]$j.order }
    $list += [pscustomobject]@{
      Name        = $name
      Aliases     = @($j.aliases | Where-Object { $_ })
      Description = [string]$j.description
      Default     = $def
      Order       = $order
      Dir         = $d.FullName
      Hooks       = ConvertTo-WAHashtable $j.hooks
      Commands    = ConvertTo-WAHashtable $j.commands
      OnChange    = [string]$j.on_change
    }
  }
  return @($list | Sort-Object Order, Name)
}

# Trova un modulo per nome o alias (senza distinzione tra maiuscole e minuscole).
function Resolve-WAModule([string]$nameOrAlias) {
  if (-not $nameOrAlias) { return $null }
  $k = $nameOrAlias.ToLowerInvariant()
  foreach ($m in (Get-WAModules)) {
    if ($m.Name.ToLowerInvariant() -eq $k) { return $m }
    foreach ($a in $m.Aliases) { if ([string]$a -and ([string]$a).ToLowerInvariant() -eq $k) { return $m } }
  }
  return $null
}

# Override per utente: hashtable nome -> 'on' | 'off'.
function Get-WAState {
  $h = @{}
  if (-not (Test-Path -LiteralPath $script:WAState)) { return $h }
  try {
    $j = [IO.File]::ReadAllText($script:WAState, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($j.modules) {
      foreach ($p in $j.modules.PSObject.Properties) {
        $v = ([string]$p.Value).ToLowerInvariant()
        if ($v -eq 'on' -or $v -eq 'off') { $h[$p.Name] = $v }
      }
    }
  } catch { Write-WALog "state.json non valido: $($_.Exception.Message)" }
  return $h
}

# Imposta l'override di un modulo; $value vuoto rimuove l'override (torna al default).
function Set-WAState([string]$name, [string]$value) {
  $h = Get-WAState
  if ($value) { $h[$name] = $value } else { $h.Remove($name) }
  New-Item -ItemType Directory -Force $script:WAHome | Out-Null
  $mods = [ordered]@{}
  foreach ($k in ($h.Keys | Sort-Object)) { $mods[$k] = $h[$k] }
  $json = (New-Object PSObject -Property @{ modules = (New-Object PSObject -Property $mods) }) | ConvertTo-Json -Depth 4
  $tmp = "$($script:WAState).tmp"
  [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
  # Sostituzione atomica quando il file esiste: chi legge non trova mai uno stato mancante.
  if (Test-Path -LiteralPath $script:WAState) { [IO.File]::Replace($tmp, $script:WAState, [NullString]::Value) }
  else { Move-Item -LiteralPath $tmp -Destination $script:WAState -Force }
}

# 'on' o 'off' per un modulo (oggetto da Get-WAModules o nome).
function Get-WAModuleState($module) {
  if ($module -is [string]) { $module = Resolve-WAModule $module }
  if (-not $module) { return 'off' }
  $s = Get-WAState
  if ($s.ContainsKey($module.Name)) { return $s[$module.Name] }
  return $module.Default
}

function Test-WAModuleEnabled($module) { return ((Get-WAModuleState $module) -eq 'on') }

# Esegue uno script di un modulo nello stesso processo, passando solo i parametri che lo script dichiara.
# $spec: "file.ps1" oppure { "script": "file.ps1", "args": { "Nome": "valore" } }
function Invoke-WAModuleScript($module, $spec, [hashtable]$extra) {
  $scriptName = $null
  $args2 = @{}
  if ($spec -is [string]) { $scriptName = $spec }
  else {
    $scriptName = [string]$spec.script
    $args2 = ConvertTo-WAHashtable $spec.args
  }
  if (-not $scriptName) { throw "script non indicato" }
  $path = Join-Path $module.Dir $scriptName
  if (-not (Test-Path -LiteralPath $path)) { throw "script non trovato: $path" }
  $declared = @((Get-Command -Name $path -ErrorAction Stop).Parameters.Keys)
  if ($extra) { foreach ($k in $extra.Keys) { if ($declared -contains $k) { $args2[$k] = $extra[$k] } } }
  return (& $path @args2)
}
