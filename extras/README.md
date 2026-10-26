# Fuori dal repo: le copie e come riattivarle

Alcune parti di Yako non vivono nel repo ma sul Mac di Nick, nelle cartelle di Claude. Qui c'è una copia di ciascuna, così il repo le ricorda tutte. Con le istruzioni qui sotto si rimettono su un Mac nuovo o dopo un reset.

Le copie sono del 25 ottobre 2026. Se cambi l'originale, ricopialo qui (comandi in fondo).

| Cosa | Dove vive sul Mac | Copia qui |
|---|---|---|
| Skill **tasketa-gioco**: il gioco delle stime, "Il campo" (dove sei, mappa, regole) | `~/.claude/skills/tasketa-gioco/` | `skills/tasketa-gioco/` |
| Skill **yako-touch**: il modo di Nick di trasformare una funzione in un gioco leggero | `~/.claude/skills/yako-touch/` | `skills/yako-touch/` |
| Task programmato **TaskETA: analisi della settimana** (lunedì alle 9) | `~/.claude/scheduled-tasks/tasketa-analisi-settimana/SKILL.md` | `scheduled/tasketa-analisi-settimana.md` |
| La skill **task-eta** stessa | `~/.claude/skills/task-eta`, un collegamento a questo repo | è il repo |

## Riattivarle

### Le skill in Claude Code

Copia ogni cartella dentro `~/.claude/skills/`:

```bash
cp -R extras/skills/tasketa-gioco extras/skills/yako-touch ~/.claude/skills/
```

Si attivano da sole quando chiedi le cose della loro descrizione ("a che buca sono", "gamifica"). Puoi anche chiamarle a mano con `/tasketa-gioco` e `/yako-touch`.

### Le skill su claude.ai

Su claude.ai si carica un pacchetto `.skill`, cioè lo zip della cartella. I pacchetti stanno in `~/.claude/skills/_pacchetti-claude-ai/`. Per rifarne uno dopo una modifica:

```bash
cd ~/.claude/skills && rm -f _pacchetti-claude-ai/tasketa-gioco.skill && zip -qr _pacchetti-claude-ai/tasketa-gioco.skill tasketa-gioco -x "*.DS_Store"
```

Lo stesso vale per `yako-touch`. Poi, su claude.ai, si carica dalla sezione delle skill nelle impostazioni. Va fatto a mano: Claude non può caricarlo per te.

### Il task programmato dell'analisi

Gira nell'app Claude, nella sezione "Programmati", ogni lunedì alle 9 (cron `0 9 * * 1`) e in modalità Auto. Le istruzioni complete sono in `scheduled/tasketa-analisi-settimana.md`. Per ricrearlo, chiedi a Claude nell'app:

> Crea il task programmato "TaskETA: analisi della settimana", ogni lunedì alle 9, con le istruzioni di `extras/scheduled/tasketa-analisi-settimana.md`.

Gira solo con l'app aperta: se il lunedì alle 9 è chiusa, parte alla prima apertura. Prepara i numeri `widget/insights/export.py`, il resto è spiegato in `widget/insights/README.md`.

### L'app e gli hook

Li rimette `install.py` (vedi il README del repo): `python3 install.py`, con `--widget yes` per TaskETA.app.

## Ricopiare qui dopo una modifica

```bash
rsync -a --delete --exclude '.DS_Store' ~/.claude/skills/tasketa-gioco/ extras/skills/tasketa-gioco/
rsync -a --delete --exclude '.DS_Store' ~/.claude/skills/yako-touch/ extras/skills/yako-touch/
sed "s|$HOME/|~/|g" ~/.claude/scheduled-tasks/tasketa-analisi-settimana/SKILL.md > extras/scheduled/tasketa-analisi-settimana.md
```

La copia del task usa `~` al posto del percorso completo: `tests/test_no_private_data.py` non vuole il nome utente nel repo, e il comando qui sopra lo toglie. Dopo ogni copia lancia i test.

**Attenzione:** questo repo va solo sul repo privato `yako`, mai su `origin`, cioè il repo originale di Dino. Le skill contengono note personali di Nick.
