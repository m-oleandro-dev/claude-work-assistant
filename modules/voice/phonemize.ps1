# Modulo voce - pronuncia inglese con la voce italiana Paola (dot-source). File solo ASCII.
# Idea: espeak-ng.dll (via P/Invoke) trascrive ogni parola in IPA, in inglese per i termini tecnici e in
# italiano per il resto; sherpa-onnx legge poi il testo con --vits-lexicon (parola -> fonemi separati da "_").
# In modalita lessico le parole senza voce nel lessico vengono saltate: per questo si trascrivono tutte.
# Ogni funzione restituisce $null se qualcosa manca: il chiamante torna alla modalita normale (--vits-data-dir).

$script:EspeakReady = $false
$script:EspeakFailed = $false
$script:TokenSet = $null

# Termini inglesi frequenti nei testi tecnici che finiscono in vocale (le altre parole inglesi si riconoscono
# dalle euristiche in Test-EnglishWord).
$script:EnglishWords = @(
  'file','files','code','make','page','image','release','service','feature','update','cache','queue','type',
  'source','hook','hooks','plugin','plugins','debug','bug','bugs','frontend','backend','api','json','yaml','repo',
  'deploy','pull','request','merge','push','token','prompt','script','shell','terminal','server','client','build',
  'test','tests','log','logs','config','default','mode','model','agent','agents','session','claude','github','git',
  'markdown','readme','setup','install','settings','skill','skills','stack','commit','commits','branch','main',
  'master','default','online','offline','email','mail','link','web','site','app','apps','software','hardware',
  'cloud','docker','python','node','module','modules','package','packages','dashboard','widget','browser','tab',
  'popup','login','logout','password','username','user','users','database','query','schema','table','index',
  'framework','library','function','class','object','string','array','boolean','null','undefined','true','false',
  'error','warning','status','store','pipeline','workflow','review','fork','clone','tag','tags','issue',
  'issues','ticket','sprint','backlog','roadmap','feedback','team','manager','owner','admin','root','home',
  'path','folder','directory','download','upload','backup','restore','reset','refresh','reload','restart','start',
  'stop','run','running','runtime','timeout','retry','fallback','format','lint','linter','parser','render',
  'template','theme','style','styles','layout','design','prototype','mockup','release','version','major','minor',
  'patch','hotfix','rollback','staging','production','live','beta','alpha','demo','preview','snippet','gist',
  'pipeline','job','jobs','worker','thread','async','await','callback','promise','event','events','handler',
  'listener','trigger','webhook','endpoint','route','router','proxy','gateway','cluster','node','container',
  'sandbox','permission','permissions','allow','deny','whitelist','blacklist','default','override','toggle',
  'switch','flag','flags','option','options','param','params','argument','arguments','input','output','stdin',
  'stdout','stderr','pipe','regex','wildcard','glob','sync','async','merge','rebase','stash','diff','blame',
  'wrapper','helper','utility','utils','core','engine','kernel','driver','plugin','extension','addon','mod',
  'voice','reader','assistant','orchestrator','subagent','subagents','workspace','project','projects','prompt'
)
$script:EnglishSet = @{}
foreach ($w in $script:EnglishWords) { $script:EnglishSet[$w] = $true }

# Parole italiane (o prestiti letti all'italiana) che le euristiche prenderebbero per inglesi.
$script:ItalianOverride = @{}
foreach ($w in @('il','in','un','per','con','non','del','al','dal','nel','sul','ed','ad','od','gran','tram','film','gas','bus','bar','sport',
  'quel','buon','qual','nessun','alcun','ognun','qualcun','nord','ovest','amor','signor','poter','virus','bonus','focus','forum','album',
  'tennis','autobus','club','hotel','chef','super','inter','extra','taxi','kiwi','karate','yoga','yogurt','jazz','jeans','judo','whisky',
  'kimono','bikini','state','base','cosi','piu','mister')) { $script:ItalianOverride[$w] = $true }

# Sigle tecniche lette con le lettere inglesi; le altre sigle (INPS, RAI, IVA) restano italiane.
$script:EnglishAcronyms = @{}
foreach ($w in @('API','CLI','JSON','URL','HTTP','HTTPS','SQL','CSS','HTML','JS','PR','CI','UI','UX','SDK','IDE','CPU','GPU','RAM','SSH','TTS','MCP','LLM','AI','OK','ID','YAML','XML','CSV','PDF','AWS','GPT')) { $script:EnglishAcronyms[$w] = $true }

function Test-EnglishWord([string]$w) {
  $l = $w.ToLowerInvariant()
  if ($script:ItalianOverride.ContainsKey($l)) { return $false }
  if ($script:EnglishSet.ContainsKey($l)) { return $true }
  if ($w.Length -ge 2 -and $w -cmatch '^[A-Z]+$') { return $script:EnglishAcronyms.ContainsKey($w) }
  if ($w.Contains("'")) {
    # elisioni italiane (l'utente, dell'ora, quest'anno): italiano; contrazioni inglesi (don't, it's): inglese
    return ($l -notmatch "^(l|un|dell|all|nell|sull|dall|coll|c|d|m|t|s|n|v|ch|quest|quell|anch|com|cos|sant|bell|nient|senz|quant|tutt|mezz|dov)'")
  }
  if ($l -match "[^a-z]") { return $false }  # accenti, cifre: italiano
  if ($l.Length -le 3) { return $false }
  if ($l -match '[kwxyj]') { return $true }
  if ($l -match 'th|sh|ck|wh|ough|ing$|tion$|ness$|ment$|ly$') { return $true }
  if ($l -match '[^aeiou]$') { return $true }  # l'italiano finisce quasi sempre in vocale
  return $false
}
function Initialize-Espeak([string]$voiceData, [string]$espeakDataParent) {
  if ($script:EspeakReady) { return $true }
  if ($script:EspeakFailed) { return $false }
  $script:EspeakFailed = $true
  try {
    $dll = Join-Path $voiceData 'espeak-ng.dll'
    if (-not (Test-Path -LiteralPath $dll)) { return $false }
    $src = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WAEsp {
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern int espeak_Initialize(int output, int buflength, byte[] path, int options);
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern int espeak_SetVoiceByName(byte[] name);
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern IntPtr espeak_TextToPhonemes(ref IntPtr textptr, int textmode, int phonememode);
  public static string Utf8(IntPtr p) {
    if (p == IntPtr.Zero) return null;
    int n = 0; while (Marshal.ReadByte(p, n) != 0) n++;
    byte[] b = new byte[n]; Marshal.Copy(p, b, 0, n); return Encoding.UTF8.GetString(b);
  }
  public static byte[] Z(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }
  public static int Init(string path) { return espeak_Initialize(2, 0, Z(path), 0); }
  public static int Voice(string name) { return espeak_SetVoiceByName(Z(name)); }
  public static string Phon(string text) {
    byte[] b = Z(text);
    IntPtr mem = Marshal.AllocHGlobal(b.Length); Marshal.Copy(b, 0, mem, b.Length);
    IntPtr p = mem; StringBuilder sb = new StringBuilder();
    int guard = 0;
    while (p != IntPtr.Zero && guard++ < 50) { string r = Utf8(espeak_TextToPhonemes(ref p, 1, 2)); if (r != null) sb.Append(r).Append(' '); }
    Marshal.FreeHGlobal(mem); return sb.ToString().Trim();
  }
}
"@
    if (-not ('WAEsp' -as [type])) { Add-Type -TypeDefinition $src }
    if ([WAEsp]::Init($espeakDataParent) -le 0) { return $false }
    $script:EspeakReady = $true
    $script:EspeakFailed = $false
    return $true
  } catch { return $false }
}

function Get-TokenSet([string]$tokensFile) {
  if ($script:TokenSet) { return $script:TokenSet }
  $set = @{}
  foreach ($line in [IO.File]::ReadAllLines($tokensFile, [Text.Encoding]::UTF8)) {
    if ($line.Length -ge 1) {
      # formato "<simbolo> <id>"; la riga dello spazio ha il simbolo vuoto
      $sym = $line.Substring(0, [Math]::Max(0, $line.LastIndexOf(' ')))
      if ($sym.Length -eq 1) { $set[$sym] = $true }
    }
  }
  $script:TokenSet = $set
  return $set
}

# Costruisce il lessico per il testo: restituisce @{ Text = <testo per sherpa>; Lexicon = <righe> } oppure $null.
function New-VoiceLexicon([string]$text, [string]$voiceData, [string]$espeakDataParent, [string]$tokensFile) {
  # Interruttore persistente: un crash nativo di espeak non si intercetta e uccide il worker prima di poter
  # scrivere un log. Il file "espeak.probing" resta se il lavoro non e finito: al giro dopo il lessico si salta
  # (per un giorno), cosi un crash costa al massimo un messaggio invece di ripetersi a ogni avvio.
  $probe = Join-Path $voiceData 'espeak.probing'
  if (Test-Path -LiteralPath $probe) {
    if (((Get-Date) - (Get-Item -LiteralPath $probe).LastWriteTime).TotalHours -lt 24) {
      Write-VoiceLog 'pronuncia inglese sospesa: il giro precedente con espeak non e finito (cancella espeak.probing per riprovare)'
      return $null
    }
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
  }
  Set-Content -LiteralPath $probe -Value 'probing' -Encoding ASCII
  $res = New-VoiceLexiconCore $text $voiceData $espeakDataParent $tokensFile
  Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
  return $res
}

function New-VoiceLexiconCore([string]$text, [string]$voiceData, [string]$espeakDataParent, [string]$tokensFile) {
  if (-not (Initialize-Espeak $voiceData $espeakDataParent)) { return $null }
  $tokens = Get-TokenSet $tokensFile
  $lex = New-Object 'System.Collections.Generic.Dictionary[string,string]'
  $outText = New-Object System.Text.StringBuilder
  $pos = 0
  foreach ($mt in [regex]::Matches($text, "[\p{L}\p{N}]+(?:'[\p{L}\p{N}]+)*")) {
    [void]$outText.Append($text.Substring($pos, $mt.Index - $pos))
    $pos = $mt.Index + $mt.Length
    $word = $mt.Value
    $key = $word.ToLowerInvariant().Replace("'", '')
    if (-not $lex.ContainsKey($key)) {
      $voice = if (Test-EnglishWord $word) { 'en-us' } else { 'it' }
      [void][WAEsp]::Voice($voice)
      $ipa = ([WAEsp]::Phon($word)).Replace(' ', '')
      $ph = New-Object System.Text.StringBuilder
      foreach ($ch in $ipa.ToCharArray()) {
        if ($tokens.ContainsKey([string]$ch) -and $ch -ne '_') { [void]$ph.Append(' ').Append($ch).Append(' _') }
      }
      if ($ph.Length -eq 0) { $lex[$key] = $null; continue }
      $lex[$key] = $ph.ToString()
    }
    if ($null -ne $lex[$key]) { [void]$outText.Append($key) }
  }
  [void]$outText.Append($text.Substring($pos))
  $lines = @(foreach ($k in $lex.Keys) { if ($null -ne $lex[$k]) { "$k _$($lex[$k])" } })
  if ($lines.Count -eq 0) { return $null }
  return @{ Text = $outText.ToString(); Lexicon = ($lines -join "`r`n") + "`r`n" }
}
