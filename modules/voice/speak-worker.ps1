# Worker unico della coda di lettura (%TEMP%\claude-voice-reader-queue): legge i file *.txt in ordine di nome
# (cioe di arrivo), uno alla volta, poi esce quando la coda e vuota. Un mutex con nome garantisce un solo worker.
# Voce: Paola (sherpa-onnx, in %USERPROFILE%\.claude\work-assistant\voice-data), altrimenti la voce italiana di Windows.
# CLAUDE_WORK_ASSISTANT_DRYRUN=1 (o il vecchio CLAUDE_VOICE_READER_DRYRUN=1): sintetizza ma non riproduce (attende 1 s).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'voice-queue.ps1')

$root = $script:VoiceData
$bin = Get-ChildItem (Join-Path $root 'sherpa') -Recurse -Filter 'sherpa-onnx-offline-tts.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$m = Join-Path $root 'sherpa\vits-piper-it_IT-paola-medium'
$wav = Join-Path $env:TEMP 'claude-voice-reader.wav'
$dry = $script:VoiceDryRun

function Invoke-Speak([string]$text, [string]$name) {
  Write-VoiceLog "sintesi ${name}: $($text.Substring(0, [Math]::Min(80, $text.Length)))"
  Remove-Item $wav -ErrorAction SilentlyContinue
  if ($bin -and (Test-Path "$m\it_IT-paola-medium.onnx")) {
    # L'eseguibile legge gli argomenti come UTF-8, ma PowerShell 5.1 li codifica con la codepage ANSI:
    # passo i byte UTF-8 riletti come ANSI, cosi arrivano intatti (accenti compresi).
    $arg = [Text.Encoding]::Default.GetString([Text.Encoding]::UTF8.GetBytes($text.Replace('"', ' ')))
    & $bin.FullName "--vits-model=$m\it_IT-paola-medium.onnx" "--vits-tokens=$m\tokens.txt" "--vits-data-dir=$m\espeak-ng-data" "--output-filename=$wav" $arg *> $null
  }
  if (Test-Path $wav) {
    Write-VoiceLog "inizio lettura $name (Paola, wav $((Get-Item $wav).Length) byte)"
    if ($dry) { Start-Sleep -Seconds 1 } else { (New-Object Media.SoundPlayer $wav).PlaySync() }
  } else {
    Write-VoiceLog "inizio lettura $name (voce di Windows)"
    if ($dry) { Start-Sleep -Seconds 1 } else {
      Add-Type -AssemblyName System.Speech
      $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
      $v = $s.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -like 'it*' } | Select-Object -First 1
      if ($v) { $s.SelectVoice($v.VoiceInfo.Name) }
      $s.Speak($text)
      $s.Dispose()
    }
  }
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
      if ($text.Trim()) { Invoke-Speak $text $item.Name }
    }
  } finally {
    if ((Get-Content $script:VoicePid -TotalCount 1 -ErrorAction SilentlyContinue) -eq "$PID") { Remove-Item $script:VoicePid -Force -ErrorAction SilentlyContinue }
    $mutex.ReleaseMutex()
  }
  # Un hook puo aver accodato un testo tra l'ultimo controllo e il rilascio del mutex: in quel caso ricomincio.
  if ((Test-VoiceOff) -or -not (Get-NextItem)) { Write-VoiceLog 'coda vuota, worker termina'; exit 0 }
}
