---
name: orchestrator
description: Use when the user's message contains two or more distinct requests, or a task that can be delegated (broad search, multi-step change, independent subtasks), and also when you are a subagent whose work splits into independent parts. Splits the work, runs independent parts in parallel subagents, and picks each subagent's model by complexity (haiku, sonnet, opus, fable).
---

# Orchestratore (work-assistant)

La sessione principale fa da **orchestratore**: capisce cosa chiede l'utente, divide il lavoro, delega a subagenti
le parti indipendenti scegliendo per ognuna il modello giusto, e alla fine restituisce un risultato pulito.
Modello consigliato per la sessione principale: **Sonnet** (veloce, ma affidabile nel dividere le richieste e nel
giudicarne la complessita; Haiku e troppo debole come pianificatore).

## 1. Analizza e dividi

- Individua le richieste distinte nel messaggio.
- Separa quelle **indipendenti** (si fanno in parallelo, senza il risultato delle altre), quelle **dipendenti**
  (servono i risultati di un'altra) e quelle **banali** (una frase, nessuno strumento).
- Una sola richiesta semplice, o solo richieste banali: **non orchestrare**, rispondi direttamente.
- Due parti che scrivono sugli stessi file non vanno in parallelo: falle in sequenza (anche in un solo subagente).

## 2. Scegli il modello di ogni subagente

Passa sempre il parametro `model` dello strumento Agent (un alias: `haiku`, `sonnet`, `opus`, `fable`).

| Complessita del compito | Esempi | `model` |
| --- | --- | --- |
| Banale / consultazione | trovare un file, leggere un valore, elencare, grep, una domanda fattuale | `haiku` |
| Normale, risposta rapida | spiegare un pezzo di codice, piccola modifica a un file, riassunto, una ricerca mirata | `sonnet` |
| Complessa, in piu passi, articolata | modifica su piu file, debug non ovvio, analisi con confronto di alternative, refactoring | `opus` |
| Solo se davvero indispensabile | il ragionamento o la progettazione piu difficile: architettura delicata, bug che opus non ha risolto, prove/algoritmi complessi | `fable` |

Regole: nel dubbio tra due livelli scegli il piu basso e, se il risultato non basta, rilancia al livello superiore.
`fable` e l'eccezione, non la norma: motivane l'uso in una riga nel tuo ragionamento.

## 3. Lancia i subagenti

Per ogni parte indipendente chiama lo strumento Agent **nello stesso messaggio** (cosi partono in parallelo), con
`run_in_background: true` quando nel frattempo hai altro da fare. Scegli il tipo di agente adatto (per esempio
`Explore` per ricerche in sola lettura, `general-purpose` per modifiche).

Ogni prompt delegato deve:

1. contenere tutto il contesto necessario (il subagente non vede la conversazione): percorsi, vincoli, cosa produrre;
2. includere il blocco **Regole per il subagente** qui sotto (i subagenti potrebbero non avere questa skill);
3. terminare chiedendo un **breve resoconto finale** (solo il risultato, i percorsi utili, cosa resta in sospeso).

### Regole per il subagente (da copiare nel prompt)

> Sei anche tu un orchestratore. Se il tuo lavoro si divide in parti indipendenti che in parallelo andrebbero
> piu veloci, delegale ad altri subagenti con lo strumento Agent, nello stesso messaggio, scegliendo il parametro
> `model` per complessita: haiku per consultazioni banali, sonnet per compiti normali e rapidi, opus per compiti
> complessi e in piu passi, fable solo se davvero indispensabile. Non delegare parti piccole o sequenziali: fai da te.
> Se lo strumento Agent non e disponibile (limite di profondita raggiunto), fai il lavoro da solo; se il lavoro e
> troppo grande, restituisci all'orchestratore una proposta di suddivisione (parti, modello consigliato per ognuna).
> Concludi con un breve resoconto finale.

### Subagenti annidati

Nella versione attuale di Claude Code un subagente puo lanciare a sua volta subagenti, **fino a tre livelli sotto
la conversazione principale** (impostabile con `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; `1` disattiva l'annidamento).
Al limite di profondita lo strumento Agent non viene dato al subagente, che quindi lavora da solo.
Il modello di un subagente annidato, se non indicato, e quello del subagente che lo lancia: per questo il
parametro `model` va passato anche ai livelli inferiori.
Fonte: https://code.claude.com/docs/en/sub-agents

## 4. Tu cosa fai nel frattempo

- Le richieste banali o dipendenti le gestisci tu; per le dipendenti aspetta la notifica del subagente da cui dipendono.
- Non ripetere per intero i risultati dei subagenti: integra, confronta, segnala conflitti e cosa manca.

## 5. Se il modulo voce e attivo

Se nel contesto compare "Modalita voce attiva":

- il prompt di ogni subagente lanciato **dalla sessione principale** inizia con il marcatore `[voce]` (solo i
  subagenti con il marcatore vengono letti ad alta voce, in coda e senza sovrapposizioni);
- il prompt termina con questa istruzione, testuale:

  > Il tuo messaggio finale verra letto ad alta voce all'utente. Concludi con un resoconto parlato in italiano di 2-4
  > frasi: solo il risultato, niente markdown, elenchi, tabelle, codice, percorsi lunghi o URL.

- i subagenti annidati (lanciati da un subagente) **non** usano `[voce]`: il loro risultato arriva gia nel
  resoconto del subagente che li ha lanciati e verrebbe letto due volte;
- dopo aver lanciato i subagenti scrivi al massimo una frase brevissima ("Ci lavoro, ti leggo le risposte man mano");
  quando arriva un risultato **non ripeterlo** (l'utente lo ha gia sentito) e alla fine dai solo un congedo di una frase.
