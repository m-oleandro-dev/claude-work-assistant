# Modulo voce, "on_change": chiamato da /assistente dopo on/off/reset.
# Spento: svuota la coda e ferma subito la lettura in corso.
# Acceso: se manca la voce neurale (o espeak-ng.dll) la scarica subito, cosi basta un solo comando.
param([string]$State = '')
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'voice-queue.ps1')
if ($State -eq 'off') {
  Stop-VoiceReader
  'Coda di lettura svuotata.'
} elseif ($State -eq 'on') {
  $bin = Get-ChildItem (Join-Path $script:VoiceData 'sherpa') -Recurse -Filter 'sherpa-onnx-offline-tts.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  $dll = Join-Path $script:VoiceData 'espeak-ng.dll'
  if (-not $bin -or -not (Test-Path $dll)) {
    'Mancano componenti della voce neurale Paola: li scarico ora (circa 100 MB, solo la prima volta).'
    try { & (Join-Path $PSScriptRoot 'install-voice.ps1') }
    catch { "Installazione non riuscita: $($_.Exception.Message). Uso la voce italiana di Windows; riprova con /assistente voce install." }
  }
}
