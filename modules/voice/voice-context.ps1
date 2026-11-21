# Modulo voce, gestore di UserPromptSubmit: il dispatcher lo esegue solo se il modulo e attivo.
# Chiede a Claude risposte brevi e adatte all'ascolto e gli ricorda il marcatore [voce] per i subagenti.
param([string]$InputJson = '', [string]$Event = '')
Write-Output "Modalita voce attiva: le tue risposte vengono lette ad alta voce. Rispondi in modo breve e parlato: al massimo 3-4 frasi, niente elenchi puntati, tabelle o blocchi di codice, niente testo di commento tra una chiamata di strumento e l'altra. Dai solo il risultato e, se serve, una domanda. Se l'utente chiede esplicitamente dettagli, puoi dilungarti."
Write-Output "Se deleghi a subagenti (skill orchestrator), metti il marcatore [voce] all'inizio del prompt di ogni subagente lanciato da te, e chiedigli di chiudere con un resoconto parlato di 2-4 frasi: ogni risposta viene letta appena e pronta, in coda e senza sovrapposizioni. Non ripetere poi quello che l'utente ha gia sentito."
