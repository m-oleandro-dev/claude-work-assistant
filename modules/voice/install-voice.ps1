# Modulo voce, comando "install" (/assistente voce install, lanciato anche da /assistente voce on se manca qualcosa):
# scarica il motore sherpa-onnx, la voce italiana Paola e espeak-ng.dll (per la pronuncia inglese)
# in %USERPROFILE%\.claude\work-assistant\voice-data. Salta cio che e gia presente.
param([string[]]$Arguments = @())
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # la barra di avanzamento rallenta molto i download in PowerShell 5.1
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'core\common.ps1')
$data = Join-Path $script:WAHome 'voice-data'
$sherpa = Join-Path $data 'sherpa'
New-Item -ItemType Directory -Force $sherpa | Out-Null

$haveEngine = [bool](Get-ChildItem $sherpa -Recurse -Filter 'sherpa-onnx-offline-tts.exe' -ErrorAction SilentlyContinue | Select-Object -First 1)
$haveVoice = Test-Path (Join-Path $sherpa 'vits-piper-it_IT-paola-medium\it_IT-paola-medium.onnx')
$haveEspeak = Test-Path (Join-Path $data 'espeak-ng.dll')
if ($haveEngine -and $haveVoice -and $haveEspeak) { Write-Output 'Voce gia installata, niente da scaricare.'; return }

# Il tar di Windows (bsdtar) non apre i .bz2 da solo: decomprimo con il bzip2 di Git for Windows,
# che Claude Code su Windows richiede comunque.
$bz = @(
  (Get-Command bzip2 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
  "$env:ProgramFiles\Git\usr\bin\bzip2.exe",
  "$env:ProgramFiles\Git\mingw64\bin\bzip2.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $bz) { throw 'bzip2 non trovato: installa Git for Windows.' }
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'

$urls = [ordered]@{}
if (-not $haveEngine) { $urls['engine'] = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.40/sherpa-onnx-v1.12.40-win-x64-shared-MD-MinSizeRel.tar.bz2' }
if (-not $haveVoice) { $urls['voice'] = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-it_IT-paola-medium.tar.bz2' }
foreach ($k in $urls.Keys) {
  $f = Join-Path $env:TEMP "voice-reader-$k.tar.bz2"
  $t = Join-Path $env:TEMP "voice-reader-$k.tar"
  Write-Output "Scarico $k ..."
  Invoke-WebRequest $urls[$k] -OutFile $f -UseBasicParsing
  Remove-Item $t -Force -ErrorAction SilentlyContinue
  $p = Start-Process $bz -ArgumentList '-d', '-f', "`"$f`"" -PassThru -NoNewWindow -Wait
  if (-not (Test-Path $t)) { throw "Decompressione di $k non riuscita." }
  & $tar -xf $t -C $sherpa
  if ($LASTEXITCODE -ne 0) { throw "Estrazione di $k non riuscita." }
  Remove-Item $t -Force
}

# espeak-ng.dll (GPL-3.0) dal pacchetto Piper per Windows: se manca, la voce funziona ma senza pronuncia inglese.
if (-not $haveEspeak) {
  Write-Output 'Scarico espeak-ng.dll (pronuncia inglese) ...'
  $zip = Join-Path $env:TEMP 'voice-reader-piper.zip'
  try {
    Invoke-WebRequest 'https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip' -OutFile $zip -UseBasicParsing
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
      $e = $z.Entries | Where-Object { $_.FullName -eq 'piper/espeak-ng.dll' } | Select-Object -First 1
      if (-not $e) { throw 'espeak-ng.dll non presente nel pacchetto.' }
      [IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $data 'espeak-ng.dll'), $true)
    } finally { $z.Dispose() }
  } catch { Write-Output "Avviso: espeak-ng.dll non installata ($($_.Exception.Message)); la pronuncia inglese resta disattivata." }
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
}
Write-Output "Installazione completata in $data"
