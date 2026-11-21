# claude-work-assistant

Plugin **work-assistant** per **Claude Code**: un assistente di lavoro modulare.
La sessione principale fa da **orchestratore** (divide le richieste, delega le parti indipendenti a subagenti in
parallelo e sceglie per ognuno il modello adatto); la **lettura vocale** delle risposte e un modulo opzionale.
Altri moduli arriveranno: ognuno e una cartella in `modules/` e si attiva o disattiva con `/assistente`.

> Stato: sperimentale. Gli script sono per **Windows 10/11** (PowerShell 5.1). Contributi e segnalazioni sono benvenuti.

## Moduli

| Modulo | Alias | Predefinito | Cosa fa |
| --- | --- | --- | --- |
| `orchestrator` | `orchestratore` | **on** | Skill `orchestrator` + promemoria a ogni messaggio + nota sul modello consigliato a inizio sessione |
| `voice` | `voce` | **off** | Legge ad alta voce le risposte (voce italiana neurale Paola in locale, ripiego sulla voce di Windows) |

### Orchestratore

- **SessionStart**: aggiunge al contesto una nota sul modello consigliato per la sessione principale, **Sonnet**
  (veloce ma affidabile nel dividere le richieste e giudicarne la complessita; Haiku e troppo debole come
  pianificatore). Se il hook riceve il campo `model` e non e Sonnet, Claude te lo dice nella prima risposta e
  suggerisce `/model sonnet`. Il campo `model` e facoltativo (puo mancare dopo `/clear`): in quel caso il consiglio
  e generico. Dopo una compattazione la nota non viene ripetuta.
- **UserPromptSubmit**: una riga che ricorda di usare la skill quando il messaggio contiene piu richieste o un
  compito delegabile.
- **Skill `orchestrator`** (`skills/orchestrator/SKILL.md`): come dividere il lavoro e quale modello passare al
  parametro `model` dello strumento Agent:

  | Compito | Modello |
  | --- | --- |
  | banale / consultazione (trovare un file, leggere un valore) | `haiku` |
  | normale, risposta rapida (spiegazione, piccola modifica) | `sonnet` |
  | complesso, in piu passi, articolato (piu file, debug, analisi) | `opus` |
  | solo se davvero indispensabile (ragionamento o progettazione piu difficile) | `fable` |

- **Subagenti orchestratori**: ogni prompt delegato contiene le stesse regole, cosi un subagente il cui lavoro si
  divide in parti indipendenti le delega a sua volta ad altri subagenti. Claude Code lo permette: per la
  [documentazione](https://code.claude.com/docs/en/sub-agents) un subagente puo lanciare subagenti fino a tre
  livelli sotto la conversazione principale (variabile `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `1` disattiva
  l'annidamento); al limite lo strumento Agent non viene fornito e il subagente lavora da solo, o propone
  all'orchestratore una suddivisione. Un subagente annidato senza `model` usa il modello di chi lo lancia.
- Ogni prompt delegato termina chiedendo un breve resoconto finale.

### Voce

- **Stop**: a fine risposta legge l'ultimo messaggio di Claude (markdown, codice e URL vengono ripuliti).
- **SubagentStop** e **PostToolUse** su `SubagentHandback`: legge il resoconto finale dei subagenti avviati con il
  marcatore `[voce]` nel prompt (l'orchestratore lo mette solo nei subagenti lanciati dalla sessione principale).
- **UserPromptSubmit**: chiede a Claude risposte brevi e adatte all'ascolto e gli ricorda il marcatore `[voce]`.
- **Coda di lettura**: ogni testo entra in una coda FIFO (`%TEMP%\claude-voice-reader-queue\`) con un solo lettore
  alla volta (mutex con nome `Local\ClaudeVoiceReaderWorker`): le letture non si sovrappongono. I doppioni
  identici vengono scartati (impronte SHA1 in `spoken.hashes`). Spegnere il modulo svuota la coda e ferma la lettura.
- Registro: `%TEMP%\claude-voice-reader.log`. Prove senza audio: `CLAUDE_WORK_ASSISTANT_DRYRUN=1`
  (vale anche il vecchio `CLAUDE_VOICE_READER_DRYRUN=1`).
- **Pronuncia inglese**: i termini tecnici inglesi (file, commit, branch, settings, sigle come API) vengono letti
  con pronuncia inglese anche dalla voce italiana: `espeak-ng.dll` trascrive ogni parola in IPA (inglese per i
  termini riconosciuti da un dizionario e da alcune euristiche, italiano per il resto) e sherpa-onnx legge il testo
  con quel lessico. Se la DLL manca o qualcosa fallisce, si torna alla lettura normale tutta italiana.
- Dati della voce: `%USERPROFILE%\.claude\work-assistant\voice-data`. La vecchia cartella
  `%USERPROFILE%\.claude\voice-reader-data` e il file `%USERPROFILE%\.claude\voice-off` della versione 0.1
  **non sono piu usati**: puoi cancellarli, oppure spostare `voice-reader-data` in `work-assistant\voice-data`
  per evitare un nuovo download.

## Comando `/assistente`

| Comando | Effetto |
| --- | --- |
| `/assistente` o `/assistente status` | elenca i moduli con lo stato (on/off, impostato o predefinito) |
| `/assistente <modulo> on` / `off` | attiva / disattiva un modulo (per esempio `/assistente voce on`) |
| `/assistente <modulo> reset` | torna al valore predefinito del modulo |
| `/assistente <modulo>` | stato del modulo e suoi sottocomandi |
| `/assistente voce install` | scarica motore, voce Paola ed espeak-ng.dll (circa 100 MB); `voce on` lo fa gia da solo se manca qualcosa |

`/voce` resta come scorciatoia di `/assistente voce` (`/voce on`, `/voce off`, `/voce install`; senza argomenti
mostra lo stato, non inverte piu).

Lo stato e per utente, in `%USERPROFILE%\.claude\work-assistant\state.json`, per esempio
`{ "modules": { "voice": "on" } }`. Un modulo assente dal file usa il `default` del suo `module.json`.

## Come funziona

`hooks/hooks.json` registra **un solo** comando per evento (SessionStart, UserPromptSubmit, Stop, SubagentStop,
PostToolUse con matcher `SubagentHandback`): `core/dispatch.ps1 -Event <evento>`. Il dispatcher:

1. legge lo stdin del hook una sola volta (UTF-8);
2. per ogni modulo attivo che gestisce l'evento (in ordine di `order`, poi nome) esegue il suo gestore passandogli
   lo stesso JSON (`-InputJson`) e il nome dell'evento (`-Event`);
3. per SessionStart e UserPromptSubmit concatena su stdout l'output dei moduli (diventa contesto per Claude);
   per gli altri eventi l'output finisce solo nel registro;
4. non fa mai fallire il hook: un errore di un modulo viene scritto in `%TEMP%\claude-work-assistant.log` ed esce
   comunque con codice 0.

## Aggiungere un modulo

1. Crea `modules/<nome>/module.json`:

   ```json
   {
     "name": "promemoria",
     "aliases": ["memo"],
     "description": "Breve descrizione in italiano",
     "default": "off",
     "order": 60,
     "hooks": {
       "UserPromptSubmit": "contesto.ps1",
       "Stop": { "script": "fine.ps1", "args": { "Modo": "breve" } }
     },
     "commands": { "pulisci": "pulisci.ps1" },
     "on_change": "cambio-stato.ps1"
   }
   ```

2. Scrivi i gestori in `modules/<nome>/`. Ogni gestore e uno script PowerShell 5.1 (solo ASCII) che dichiara i
   parametri che gli servono tra `-InputJson` (JSON del hook), `-Event` e quelli in `args`; per i comandi
   `-Arguments` (argomenti dopo il sottocomando), per `on_change` `-State` (`on`/`off`). Quello che scrive su stdout
   diventa contesto solo per SessionStart e UserPromptSubmit. Non usare `Write-Host` ne `[Environment]::Exit`:
   i gestori girano nello stesso processo del dispatcher.
3. Se serve un evento nuovo, aggiungilo a `hooks/hooks.json` con lo stesso comando del dispatcher.
4. Prova con `/assistente <nome> on` e controlla il registro.

## Installazione

Dentro Claude Code:

```
/plugin marketplace add m-oleandro-dev/claude-work-assistant
/plugin install work-assistant@work-assistant-marketplace
```

L'orchestratore e attivo subito. Per la voce basta un comando: la prima volta scarica da solo motore, voce Paola
e pronuncia inglese (circa 100 MB):

```
/assistente voce on
```

I due comandi del plugin sono richiesti da Claude Code (prima si aggiunge il marketplace, poi si installa): non
si possono fondere, ma si incollano di seguito.

Se avevi installato la versione precedente (`voice-reader`), disinstallala, altrimenti le risposte vengono lette due volte.

In alternativa, senza marketplace: clona il repository e avvia con

```powershell
claude --plugin-dir "C:\percorso\claude-work-assistant"
```

## Licenze

Codice del plugin sotto licenza MIT (vedi `LICENSE`). `/assistente voce install` scarica al momento
dell'installazione componenti di terze parti, che **non sono ridistribuiti** in questo repository:

- motore [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) v1.12.40: Apache-2.0 (le versioni 2.x non includono
  piu il convertitore di fonemi per l'italiano);
- dati di fonemizzazione espeak-ng (inclusi nel pacchetto della voce) ed `espeak-ng.dll` (estratta dal pacchetto
  Piper per Windows, rhasspy/piper 2023.11.14-2): GPL-3.0;
- voce `vits-piper-it_IT-paola-medium` (rhasspy/piper-voices): MIT; dataset della voce Paola: CC0; modello di base
  da cui e stata addestrata (hifi_tts): CC BY 4.0.

## Limiti noti

- Solo Windows (PowerShell 5.1, `System.Speech`, `Media.SoundPlayer`).
- La scelta del modello dei subagenti e affidata a Claude tramite la skill: e un'indicazione, non un vincolo.
- Il campo `model` di SessionStart non arriva sempre: in quel caso il consiglio su Sonnet e generico.
- I subagenti potrebbero non vedere la skill: per questo le regole vanno copiate nel prompt delegato.
- Voce: si legge solo l'ultimo messaggio di ogni turno; tra una lettura e l'altra passano alcuni secondi; un doppione
  viene riconosciuto solo se il testo e identico; i termini inglesi hanno accento italiano.

## Idee

- Altri moduli (promemoria, riepilogo di fine giornata, integrazioni).
- Supporto macOS/Linux per la voce (`say`, `espeak-ng`, Piper); scelta di voce e velocita; lettura a frasi.
