# Modulo voce - funzioni comuni (dot-source): log, pulizia del testo, coda FIFO di lettura, avvio del worker.
# File solo ASCII: PowerShell 5.1 legge come ANSI gli script senza BOM.
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'core\common.ps1')

$script:VoiceData   = Join-Path $script:WAHome 'voice-data'
$script:VoiceQueue  = Join-Path $env:TEMP 'claude-voice-reader-queue'
$script:VoiceLog    = Join-Path $env:TEMP 'claude-voice-reader.log'
$script:VoicePid    = Join-Path $env:TEMP 'claude-voice-reader.pid'
$script:VoiceHashes = Join-Path $script:VoiceQueue 'spoken.hashes'
$script:VoiceMarker = '[voce]'
$script:VoiceDryRun = ($env:CLAUDE_WORK_ASSISTANT_DRYRUN -eq '1' -or $env:CLAUDE_VOICE_READER_DRYRUN -eq '1')

# Lo stato del modulo e in state.json (vedi core/common.ps1); il vecchio file voice-off non e piu usato.
function Test-VoiceOff { -not (Test-WAModuleEnabled 'voice') }

function Write-VoiceLog([string]$msg) {
  try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') [$PID] $msg" | Add-Content -Path $script:VoiceLog -Encoding UTF8 } catch { }
}

# JSON del hook: quello passato dal dispatcher (-InputJson), altrimenti lo stdin letto come UTF-8
# (con [Console]::In PowerShell 5.1 userebbe la codepage OEM e rovinerebbe gli accenti).
function Read-HookInput([string]$raw) {
  if (-not $raw) {
    $reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
  }
  if (-not $raw -or -not $raw.Trim()) { return $null }
  try { return ($raw | ConvertFrom-Json) } catch { Write-VoiceLog "JSON non valido: $($_.Exception.Message)"; return $null }
}

# Righe del transcript JSONL gia convertite, dall'ultima alla prima.
function Get-TranscriptEntriesReversed([string]$path) {
  if (-not $path -or -not (Test-Path -LiteralPath $path)) { return @() }
  $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
  $out = New-Object System.Collections.ArrayList
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if (-not $lines[$i].Trim()) { continue }
    try { [void]$out.Add(($lines[$i] | ConvertFrom-Json)) } catch { }
  }
  return $out.ToArray()
}

function Test-RealUserEntry($e) {
  if ($e.type -ne 'user') { return $false }
  $c = $e.message.content
  if ($c -is [array]) { return (@($c | Where-Object { $_.type -eq 'tool_result' }).Count -eq 0) }
  return $true
}

# Testo dell'ultimo messaggio assistant dell'ultimo turno. Se l'agente ha consegnato il resoconto
# con lo strumento SubagentHandback, restituisce il campo message di quella chiamata.
function Get-LastAssistantText([string]$path) {
  foreach ($e in (Get-TranscriptEntriesReversed $path)) {
    if (Test-RealUserEntry $e) { break }
    if ($e.type -ne 'assistant') { continue }
    $content = @($e.message.content)
    $hb = $content | Where-Object { $_.type -eq 'tool_use' -and $_.name -eq 'SubagentHandback' } | Select-Object -First 1
    if ($hb -and $hb.input.message) { return [string]$hb.input.message }
    $t = ($content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
    if ($t.Trim()) { return $t }
  }
  return ''
}

# Messaggio di consegna (SubagentHandback) presente nel transcript, se c'e.
function Get-HandbackText([string]$path) {
  foreach ($e in (Get-TranscriptEntriesReversed $path)) {
    if ($e.type -ne 'assistant') { continue }
    $hb = @($e.message.content) | Where-Object { $_.type -eq 'tool_use' -and $_.name -eq 'SubagentHandback' } | Select-Object -First 1
    if ($hb -and $hb.input.message) { return [string]$hb.input.message }
  }
  return ''
}

# Transcript del subagente: campo esplicito, altrimenti <transcript principale senza .jsonl>\subagents\agent-<id>.jsonl
function Get-SubagentTranscript($inp) {
  if ($inp.agent_transcript_path) { return [string]$inp.agent_transcript_path }
  $tp = [string]$inp.transcript_path
  if ($tp -match '[\\/]subagents[\\/]') { return $tp }
  if ($tp -and $inp.agent_id) {
    $dir = $tp -replace '\.jsonl$', ''
    return (Join-Path (Join-Path $dir 'subagents') "agent-$($inp.agent_id).jsonl")
  }
  return ''
}

# $true se il prompt del subagente contiene il marcatore [voce]; $null se il transcript non e leggibile.
function Test-SubagentMarked([string]$path) {
  if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
  $head = (Get-Content -LiteralPath $path -Encoding UTF8 -TotalCount 3) -join "`n"
  return $head.Contains($script:VoiceMarker)
}

function ConvertTo-SpokenText([string]$text) {
  if (-not $text) { return '' }
  $text = $text.Replace($script:VoiceMarker, ' ')
  $text = [regex]::Replace($text, '(?s)```.*?```', ' (blocco di codice omesso). ')
  $text = [regex]::Replace($text, '`([^`]*)`', '$1')
  $text = [regex]::Replace($text, '\[([^\]]*)\]\([^)]*\)', '$1')
  $text = [regex]::Replace($text, 'https?://\S+', ' link ')
  $text = [regex]::Replace($text, '(?m)^\s*#+\s*', '')
  $text = [regex]::Replace($text, '(?m)^\s*[-*]\s+', '')
  $text = [regex]::Replace($text, '[*_|>~]', '')
  # Virgolette e trattini tipografici: alcuni byte UTF-8 (es. 0x9D) non sopravvivono al passaggio ANSI verso sherpa-onnx
  $text = $text.Replace([string][char]0x2018, "'").Replace([string][char]0x2019, "'")
  $text = $text.Replace([string][char]0x201C, ' ').Replace([string][char]0x201D, ' ')
  $text = $text.Replace([string][char]0x2013, ', ').Replace([string][char]0x2014, ', ').Replace([string][char]0x2026, '...')
  $text = [regex]::Replace($text, '\s+', ' ').Trim()
  if ($text.Length -gt 1500) { $text = $text.Substring(0, 1500) + '... risposta troncata.' }
  return $text
}

function Get-TextHash([string]$text) {
  $norm = [regex]::Replace($text.ToLowerInvariant(), '\s+', ' ').Trim()
  $sha = [Security.Cryptography.SHA1]::Create()
  return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($norm)))).Replace('-', '')
}

# Accoda un testo (gia pulito) e avvia il worker. Restituisce $false se e un doppione.
function Add-VoiceQueueItem([string]$text, [string]$source) {
  if (-not $text.Trim()) { return $false }
  New-Item -ItemType Directory -Force $script:VoiceQueue | Out-Null
  $hash = Get-TextHash $text
  $m = New-Object System.Threading.Mutex($false, 'Local\ClaudeVoiceReaderEnqueue')
  $owned = $false
  try {
    try { $owned = $m.WaitOne(3000) } catch { $owned = $true }  # mutex abbandonato: ora e nostro
    $known = @()
    if (Test-Path $script:VoiceHashes) { $known = @(Get-Content $script:VoiceHashes) }
    if ($known -contains $hash) { Write-VoiceLog "doppione ignorato ($source, $hash)"; return $false }
    $known = @($known + $hash) | Select-Object -Last 200
    Set-Content -Path $script:VoiceHashes -Value $known -Encoding ASCII
    # Nome ordinabile: tick UTC a 19 cifre + pid; scrittura in .tmp e rinomina, cosi il worker non legge file a meta
    $name = '{0:D19}-{1}-{2}' -f [DateTime]::UtcNow.Ticks, $PID, $source
    $tmp = Join-Path $script:VoiceQueue "$name.tmp"
    [IO.File]::WriteAllText($tmp, $text, [Text.Encoding]::UTF8)
    Move-Item -LiteralPath $tmp -Destination (Join-Path $script:VoiceQueue "$name.txt")
    Write-VoiceLog "accodato $name.txt ($($text.Length) caratteri)"
  } finally {
    if ($owned) { try { $m.ReleaseMutex() } catch { } }
    $m.Dispose()
  }
  Start-VoiceWorker
  return $true
}

# Avvia sempre un worker nascosto: se ne gira gia uno (mutex occupato) il nuovo esce subito.
function Start-VoiceWorker {
  $worker = Join-Path $PSScriptRoot 'speak-worker.ps1'
  $p = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$worker`""
  Write-VoiceLog "worker lanciato (pid $($p.Id))"
}

# Svuota la coda e ferma la lettura in corso (worker e sintetizzatore figlio).
function Clear-VoiceQueue {
  if (Test-Path $script:VoiceQueue) {
    Get-ChildItem $script:VoiceQueue -File | Where-Object { $_.Extension -eq '.txt' -or $_.Extension -eq '.tmp' } | Remove-Item -Force -ErrorAction SilentlyContinue
  }
}

function Stop-VoiceReader {
  Clear-VoiceQueue
  if (Test-Path $script:VoicePid) {
    $wp = 0
    [void][int]::TryParse(((Get-Content $script:VoicePid -TotalCount 1) -as [string]), [ref]$wp)
    $proc = $null
    if ($wp -gt 0) { $proc = Get-Process -Id $wp -ErrorAction SilentlyContinue }
    if ($proc -and $proc.ProcessName -eq 'powershell') {  # pid riciclato: non toccare altri programmi
      Get-CimInstance Win32_Process -Filter "ParentProcessId=$wp" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
      Stop-Process -Id $wp -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $script:VoicePid -Force -ErrorAction SilentlyContinue
  }
  Write-VoiceLog 'coda svuotata e lettura fermata'
}
