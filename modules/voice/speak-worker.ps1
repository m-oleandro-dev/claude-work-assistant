# Worker unico della coda di lettura (%TEMP%\claude-voice-reader-queue): legge i file *.txt in ordine di nome
# (cioe di arrivo), uno alla volta, poi esce quando la coda e vuota. Un mutex con nome garantisce un solo worker.
# Voce: Paola (sherpa-onnx, in %USERPROFILE%\.claude\work-assistant\voice-data), altrimenti la voce italiana di Windows.
# CLAUDE_WORK_ASSISTANT_DRYRUN=1 (o il vecchio CLAUDE_VOICE_READER_DRYRUN=1): sintetizza ma non riproduce (attende 1 s).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'voice-queue.ps1')
. (Join-Path $PSScriptRoot 'phonemize.ps1')

$root = $script:VoiceData
$bin = Get-ChildItem (Join-Path $root 'sherpa') -Recurse -Filter 'sherpa-onnx-offline-tts.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$m = Join-Path $root 'sherpa\vits-piper-it_IT-paola-medium'
$dry = $script:VoiceDryRun
$SynthTimeoutMs = 45000

# Registro: oltre 1 MB riparte da zero.
try { if ((Test-Path $script:VoiceLog) -and (Get-Item $script:VoiceLog).Length -gt 1MB) { Remove-Item $script:VoiceLog -Force } } catch { }

# L'eseguibile legge gli argomenti come UTF-8, ma PowerShell 5.1 li passa con la codepage ANSI: ripasso i byte UTF-8
# riletti come ANSI, cosi arrivano intatti. I caratteri che non sopravvivono al giro (es. byte 0x81, 0x8D, 0x9D)
# diventano spazi; le barre rovesciate finali vengono tolte (diventerebbero una virgoletta in piu).
$script:CharOk = @{}
function ConvertTo-SherpaArg([string]$text) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $text.ToCharArray()) {
    $k = [string]$c
    if (-not $script:CharOk.ContainsKey($k)) {
      $mang = [Text.Encoding]::Default.GetString([Text.Encoding]::UTF8.GetBytes($k))
      $script:CharOk[$k] = ([Text.Encoding]::UTF8.GetString([Text.Encoding]::Default.GetBytes($mang)) -ceq $k)
    }
    if ($script:CharOk[$k] -and $c -ne '"') { [void]$sb.Append($c) } else { [void]$sb.Append(' ') }
  }
  $s = $sb.ToString().TrimEnd('\', ' ')
  return [Text.Encoding]::Default.GetString([Text.Encoding]::UTF8.GetBytes($s))
}

# Lancia sherpa con un tempo massimo; $true solo se termina bene e produce un wav plausibile.
function Invoke-Sherpa([string[]]$options, [string]$arg, [string]$wavPath) {
  Remove-Item $wavPath -Force -ErrorAction SilentlyContinue
  $all = @($options) + "--output-filename=$wavPath"
  $cmd = (($all | ForEach-Object { '"' + $_ + '"' }) -join ' ') + ' "' + $arg + '"'
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $bin.FullName
  $psi.Arguments = $cmd
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [Diagnostics.Process]::Start($psi)
  $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()  # svuota i tubi: niente blocchi
  if (-not $p.WaitForExit($SynthTimeoutMs)) {
    try { $p.Kill() } catch { }
    Write-VoiceLog "sherpa bloccato oltre $($SynthTimeoutMs / 1000) s: terminato"
    return $false
  }
  if ($p.ExitCode -ne 0) { Write-VoiceLog "sherpa uscito con codice $($p.ExitCode)"; return $false }
  return ((Test-Path $wavPath) -and (Get-Item $wavPath).Length -gt 1000)
}

function Invoke-Speak([string]$text, [string]$name) {
  Write-VoiceLog "sintesi ${name}: $($text.Substring(0, [Math]::Min(80, $text.Length)))"
  $wav = Join-Path $env:TEMP "claude-voice-reader-$PID.wav"  # un wav per worker: mai quello di una lettura precedente
  Remove-Item $wav -Force -ErrorAction SilentlyContinue
  $ok = $false
  if ($bin -and (Test-Path "$m\it_IT-paola-medium.onnx")) {
    $model = @("--vits-model=$m\it_IT-paola-medium.onnx", "--vits-tokens=$m\tokens.txt")
    # Pronuncia inglese dei termini tecnici: lessico generato con espeak-ng.dll; se manca o fallisce, modalita normale.
    $lex = $null
    try { $lex = New-VoiceLexicon $text $root $m "$m\tokens.txt" } catch { Write-VoiceLog "lessico non creato: $($_.Exception.Message)" }
    if ($lex) {
      $lexFile = Join-Path $env:TEMP "claude-voice-reader-lexicon-$PID.txt"
      [IO.File]::WriteAllText($lexFile, $lex.Lexicon, (New-Object Text.UTF8Encoding($false)))
      $ok = Invoke-Sherpa ($model + "--vits-lexicon=$lexFile") (ConvertTo-SherpaArg $lex.Text) $wav
      Remove-Item $lexFile -Force -ErrorAction SilentlyContinue
      if (-not $ok) { Write-VoiceLog 'sintesi con lessico non riuscita, riprovo in modalita normale' }
    }
    if (-not $ok) {
      $ok = Invoke-Sherpa ($model + "--vits-data-dir=$m\espeak-ng-data") (ConvertTo-SherpaArg $text) $wav
    }
  }
  if ($ok) {
    Write-VoiceLog "inizio lettura $name (Paola, wav $((Get-Item $wav).Length) byte)"
    if ($dry) { Start-Sleep -Seconds 1 } else { (New-Object Media.SoundPlayer $wav).PlaySync() }
  } else {
    Write-VoiceLog "inizio lettura $name (voce di Windows)"
    if ($dry) { Start-Sleep -Seconds 1 } else {
      Add-Type -AssemblyName System.Speech
      $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
      try {
        $v = $s.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -like 'it*' } | Select-Object -First 1
        if ($v) { $s.SelectVoice($v.VoiceInfo.Name) }
        $s.Speak($text)
      } finally { $s.Dispose() }
    }
  }
  Remove-Item $wav -Force -ErrorAction SilentlyContinue
  Write-VoiceLog "fine lettura $name"
}

function Get-NextItem {
  if (-not (Test-Path $script:VoiceQueue)) { return $null }
  Get-ChildItem $script:VoiceQueue -File -Filter '*.txt' | Where-Object { $_.Extension -eq '.txt' } | Sort-Object Name | Select-Object -First 1
}

$mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeVoiceReaderWorker')
while ($true) {
  $owned = $false
  try { $owned = $mutex.WaitOne(0) } catch { $owned = $true }  # mutex abbandonato (worker terminato a forza): ora e nostro
  if (-not $owned) { Write-VoiceLog 'worker gia attivo, esco'; exit 0 }
  Set-Content -Path $script:VoicePid -Value $PID
  Write-VoiceLog 'worker attivo'
  try {
    while ($true) {
      if (Test-VoiceOff) { Clear-VoiceQueue; Write-VoiceLog 'voce disattivata: coda svuotata'; break }
      $item = Get-NextItem
      if (-not $item) { break }
      $text = ''
      try { $text = [IO.File]::ReadAllText($item.FullName, [Text.Encoding]::UTF8) } catch { }
      Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
      # Un errore su un messaggio non deve fermare gli altri.
      if ($text.Trim()) {
        try { Invoke-Speak $text $item.Name } catch { Write-VoiceLog "errore nella lettura di $($item.Name): $($_.Exception.Message)" }
      }
    }
  } finally {
    if ((Get-Content $script:VoicePid -TotalCount 1 -ErrorAction SilentlyContinue) -eq "$PID") { Remove-Item $script:VoicePid -Force -ErrorAction SilentlyContinue }
    $mutex.ReleaseMutex()
  }
  # Un hook puo aver accodato un testo tra l'ultimo controllo e il rilascio del mutex: in quel caso ricomincio.
  if ((Test-VoiceOff) -or -not (Get-NextItem)) { Write-VoiceLog 'coda vuota, worker termina'; exit 0 }
}
