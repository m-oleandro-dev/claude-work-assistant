# Modulo voce, comando "install" (/assistente voce install):
# scarica il motore sherpa-onnx e la voce italiana Paola in %USERPROFILE%\.claude\work-assistant\voice-data
param([string[]]$Arguments = @())
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # la barra di avanzamento rallenta molto i download in PowerShell 5.1
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'core\common.ps1')
$data = Join-Path $script:WAHome 'voice-data'
$sherpa = Join-Path $data 'sherpa'
New-Item -ItemType Directory -Force $sherpa | Out-Null

# Il tar di Windows (bsdtar) non apre i .bz2 da solo: decomprimo con il bzip2 di Git for Windows,
# che Claude Code su Windows richiede comunque.
$bz = @(
  (Get-Command bzip2 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
  "$env:ProgramFiles\Git\usr\bin\bzip2.exe",
  "$env:ProgramFiles\Git\mingw64\bin\bzip2.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $bz) { throw 'bzip2 non trovato: installa Git for Windows.' }
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'

$urls = [ordered]@{
  engine = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.40/sherpa-onnx-v1.12.40-win-x64-shared-MD-MinSizeRel.tar.bz2'
  voice  = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-it_IT-paola-medium.tar.bz2'
}
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
Write-Output "Installazione completata in $sherpa"
