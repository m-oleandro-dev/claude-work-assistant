# Modulo voce, "on_change": chiamato da /assistente dopo on/off/reset.
# Spento: svuota la coda e ferma subito la lettura in corso. Acceso: segnala se manca la voce neurale.
param([string]$State = '')
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'voice-queue.ps1')
if ($State -eq 'off') {
  Stop-VoiceReader
  'Coda di lettura svuotata.'
} elseif ($State -eq 'on') {
  $bin = Get-ChildItem (Join-Path $script:VoiceData 'sherpa') -Recurse -Filter 'sherpa-onnx-offline-tts.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $bin) { 'Voce neurale Paola non installata: uso la voce italiana di Windows. Per installarla: /assistente voce install' }
}
