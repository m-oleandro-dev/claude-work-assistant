---
description: Scorciatoia per /assistente voce (on, off, status, install)
argument-hint: [on|off|status|install]
allowed-tools: Bash(powershell:*)
---
Risultato del comando:

!`powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/core/assistente.ps1" voce $ARGUMENTS`

Riporta all'utente solo il risultato qui sopra, in una frase brevissima, senza altro.
