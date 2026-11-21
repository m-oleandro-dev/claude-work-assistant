---
description: Moduli dell'assistente di lavoro (status, <modulo> on|off|reset, voce install)
argument-hint: [status | <modulo> on|off|reset|status | voce install]
allowed-tools: Bash(powershell:*)
---
Risultato del comando:

!`powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/core/assistente.ps1" $ARGUMENTS`

Riporta all'utente solo il risultato qui sopra, in modo brevissimo (per lo stato dei moduli va bene un elenco corto), senza altro.
