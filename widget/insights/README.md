# Analisi della settimana

Ogni lunedì alle 9 un task programmato di Claude (app Claude, "TaskETA: analisi della settimana") fa da analista esterno: non ha il contesto dei progetti né delle chat, legge solo i numeri.

1. `export.py` legge l'indice di task-eta e scrive `~/.claude/task-eta/insights-input.json`. Dentro ci sono solo numeri ed etichette (progetti, modelli, tipi di lavoro), con una nota su cosa vuol dire ogni numero. Nessun prompt, percorso o id di sessione.
2. L'analista legge quel file e nient'altro, e scrive `~/.claude/task-eta/insights.json`:

```json
{"v": 1, "generated": "2026-10-26T09:00:00+01:00", "period": "19-26 ottobre",
 "headline": "Una frase", "items": [{"title": "…", "body": "…", "kind": "trend|record|tip|warning"}]}
```

3. TaskETA.app lo mostra nella dashboard ("Analisi della settimana", con «Leggi l'analisi»). Dalla v2.7 il widget dell'iPhone mostra solo le sessioni, quindi l'analisi non ci va più.

Per rifarla a mano: `python3 export.py`, poi "Esegui ora" sul task programmato.
