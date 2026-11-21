# Dispatcher unico degli hook del plugin work-assistant.
# Uso (da hooks/hooks.json): dispatch.ps1 -Event <SessionStart|UserPromptSubmit|Stop|SubagentStop|PostToolUse>
# Legge lo stdin del hook una sola volta, poi esegue, in ordine, il gestore di ogni modulo attivo per quell'evento,
# passandogli lo stesso JSON (-InputJson) e il nome dell'evento (-Event).
# Per gli eventi che aggiungono contesto (SessionStart, UserPromptSubmit) concatena l'output dei moduli su stdout;
# per gli altri lo scrive solo nel registro. Un errore di un modulo non fa mai fallire il hook: esce sempre con 0.
# Registro: %TEMP%\claude-work-assistant.log
param([string]$Event = '')
$ErrorActionPreference = 'Continue'
$contextEvents = @('SessionStart', 'UserPromptSubmit')
try {
  . (Join-Path $PSScriptRoot 'common.ps1')

  # Stdin come UTF-8 (con [Console]::In PowerShell 5.1 userebbe la codepage OEM e rovinerebbe gli accenti).
  $raw = ''
  try {
    $reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
  } catch { Write-WALog "dispatch ${Event}: stdin non leggibile: $($_.Exception.Message)" }
  if (-not $Event -and $raw.Trim()) {
    try { $Event = [string]($raw | ConvertFrom-Json).hook_event_name } catch { }
  }
  if (-not $Event) { Write-WALog 'dispatch: evento non indicato'; exit 0 }

  $out = New-Object System.Collections.ArrayList
  foreach ($m in (Get-WAModules)) {
    if (-not $m.Hooks.ContainsKey($Event)) { continue }
    if (-not (Test-WAModuleEnabled $m)) { continue }
    $t0 = Get-Date
    try {
      $res = Invoke-WAModuleScript $m $m.Hooks[$Event] @{ InputJson = $raw; Event = $Event }
      $text = (@($res) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) -join "`n"
      $ms = [int]((Get-Date) - $t0).TotalMilliseconds
      Write-WALog "dispatch ${Event}: modulo $($m.Name) ok (${ms} ms, $($text.Length) caratteri di output)"
      if ($text.Trim()) {
        if ($contextEvents -contains $Event) { [void]$out.Add($text.Trim()) }
        else { Write-WALog "dispatch ${Event}: output di $($m.Name) ignorato: $($text.Substring(0, [Math]::Min(200, $text.Length)))" }
      }
    } catch {
      Write-WALog "dispatch ${Event}: ERRORE nel modulo $($m.Name): $($_.Exception.Message)"
    }
  }
  if ($out.Count -gt 0) { Write-Output ($out -join "`n") }
} catch {
  try { Write-WALog "dispatch ${Event}: ERRORE: $($_.Exception.Message)" } catch { }
}
exit 0
