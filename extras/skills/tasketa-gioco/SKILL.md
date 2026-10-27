---
name: tasketa-gioco
description: Il gioco delle stime di TaskETA (Yako) — "Il campo", un minigolf da 9 buche dove ogni buca è un livello con le sue prove e il suo potere, più i campi del minigolf (ghiaccio, biliardo) aperti dalle buche fatte. Ricorda il progetto, dice a che buca è Nick con i numeri veri dell'indice, aggiorna la mappa pubblicata e guida la costruzione un pezzo alla volta. ATTIVARE SEMPRE quando Nick parla del gioco di TaskETA o del widget — "il gioco", "il campo", "la mappa del minigolf", "a che buca sono", "dove sono nel gioco", "a che livello sono", "i poteri", "sbloccare", "le gemme", "le prove", "mazza forte", "campo ghiacciato", "ghiaccio", "biliardo", "buche fatte", "aggiorna la mappa", "costruiamo il gioco", "prossimo passo del gioco", "livelli e obiettivi", "Mulligan", "buca doppia", "Eagle", "stili del widget", "Urbe Hub", "Pratone dei Gardens", "Trump Lake", "Monte Donato". Versione 1 del 24/10/2026 (repo ~/Downloads/claude-time-is-relative, branch starcks); la mappa è anche nell'app, nella finestra Analytics.
---

# Il gioco delle stime di TaskETA

## Obiettivo di Nick

Un gioco vero, semplice e progressivo dentro TaskETA, l'app della barra dei menu che cronometra i suoi task di Claude Code:
- le gemme e i punti di oggi restano la cosa con cui continuare a giocare;
- livelli con pochi obiettivi semplici, a gradini di difficoltà;
- poteri che si sbloccano e rendono il gioco più divertente e diverso, anche nel minigolf;
- spiegato con una mappa da minigolf.

Tutto deve essere leggerissimo, perché l'app gira sempre in background.

## Dove stanno le cose

| Cosa | Dove |
|---|---|
| Il progetto completo (regole, poteri, equilibrio, primi passi) | `~/Downloads/claude-time-is-relative/docs/gioco-progressione.md` |
| La mappa pubblicata (artifact privato) | `<link dell'artifact privato, nella skill installata>` |
| Il sorgente della mappa, con i punti da aggiornare segnati `←` | `templates/il-campo.html` |
| La mappa dentro l'app (finestra Analytics, un WKWebView), uguale byte per byte al template | `widget/campo/il-campo.html` nella repo, con i font in `widget/campo/fonts/`; `build.sh` la copia nelle Resources |
| I numeri della mappa nell'app | `window.CAMPO_DATA`, fatto da `CampoData` in `widget/Sources/Campo.swift` (stessa forma di `DATA`, più `atShort`, `eta`, `embed`, `still`) |
| Il monitor: dove sei, con le regole del campo | `references/dove-sono.py` |
| Il gioco di oggi nell'app | `widget/Sources/Gems.swift` (gemme, livelli, sfida, stili), `Golf.swift` e `GolfStats.swift` (minigolf), `TouchBar.swift`, `widget/iphone/TaskETA.js` |
| Il changelog dell'app | `YAKO.md` (tenere la sua forma: tabella delle versioni + funzioni per area) |
| La memoria del fork | `task-eta-widget-fork.md` nella memoria di Claude del progetto |

## Le regole in breve

- Ogni task con la stima è una buca, la stima è il par. Diamante 300, zaffiro 150, smeraldo 100, sasso 0; +25 per gemma di fila prima, fino a +250. Giri da 18.
- **Il campo**: 9 buche = i 9 livelli di oggi, con le stesse soglie di punti. I punti portano al green, le prove mettono in buca, la buca chiusa accende un potere.
  - Il Pratone dei Gardens (1 prova): 1 Principiante, 2 Caddie, 3 Dilettante.
  - Trump Lake (2 prove): 4 Handicap 18, 5 Handicap 9, 6 Scratch.
  - Monte Donato (3 prove): 7 Pro, 8 Campione, 9 Leggenda del green.
- **Poteri**: Fairway (1), Il consiglio del caddie (2), Mulligan (3), Mazza forte (4, minigolf), Golf di notte (5), Buca doppia (6), Trofeo (7), Eagle (8), Giacca verde e Stagione 2 (9).
- **A cosa serve** (Nick, 24/10): prompt migliori, restare al Mac mentre Claude lavora, ogni risultato con il suo perché.
  - Attesa: una riga nel pannello scelta dalla stima: meno di 1 min niente; 1–5 min una buca o il consiglio da 30 s; 5–15 min prepara il prossimo prompt; oltre 15 min il giro lungo. Le attese lunghe sono un terzo delle buche ma l'82% del tempo d'attesa.
  - Colpo pulito (+25): un turno solo (`segments` = 1) e rimasto del suo tipo (quick ≤ 3 strumenti, medium ≤ 15). Nei dati: 63% delle buche, bogey 10% contro 54%. Prompt da una parola, contesto nel prompt e notte non cambiano le stime: non premiarli.
  - Ogni risultato porta perché + cosa fare, con regole fisse (tabella nel documento), niente AI mentre l'app gira.
- **Anche Claude gioca** (Nick, 24/10; costruito in v2.7): le gemme danno un voto alle stime di Claude.
  - **Come si vede:** nel blocco `[task-eta]` che l'hook scrive a ogni prompt c'è una riga in più, di circa 50 token: «Your score, last 18 estimates against this hook's range…: N inside (N hit), N too short, N too long; streak N, best N/18», più l'avviso che conta la stima e mai il lavoro.
  - **Accesa di base.** La spegni con `python3 task_eta.py score off` (o `TASK_ETA_SCORE=0`) e la riaccendi con `score on`. `python3 task_eta.py score` (anche `--json`) mostra il punteggio attuale: i numeri cambiano a ogni task, quindi leggili da lì e non scriverli qui.
  - **Regole contro i trucchi** (`claude_score` in `task_eta.py`):
    - la stima si confronta con la forchetta che l'hook ha offerto per il tipo dichiarato (`suggestions.jsonl`), mai con quella scritta da Claude;
    - centrata solo entro l'8% (o 10 s);
    - finire sotto la forchetta è un errore anche quello («too long»): per Claude lo zaffiro non è un premio;
    - non contano i task fermati, le prove automatiche e le stime senza offerta nel log.
  - **Nell'app** il punteggio si calcola allo stesso modo: `ClaudeScore` in `CampoEngine.swift`. Se cambi una regola, cambiala in tutti e due.
- **Mood del gioco** (costruito in v2.7, `GameMood.swift`): Minigolf, di partenza (scorecard: hole in one disco pieno nell'anello, birdie cerchio, par punto, bogey quadrato; «buche buone», «bogey», card «Lo scorecard») o Gemme (diamanti, zaffiri, smeraldi, sassi). Le regole non cambiano. Si sceglie in Impostazioni > Gioco o in fondo alla card (`gameMood` in UserDefaults). Nei testi nuovi non scrivere «gemme» o «sassi» fissi: usa `GameMood.current.goods` / `.bads` / `.name(gem)`, e nella mappa `M.good`, `M.goods`, `M.bad` (da `DATA.mood`). Per un mood nuovo: un `case` in più.
- **Card corta** (v2.7, Nick: «troppo lunga… istantaneo»): a riposo solo buca e green, scorecard di oggi, prossimo potere; il resto dietro chip che si aprono subito al passaggio e spariscono uscendo, un clic li tiene aperti. Niente animazioni sui dettagli, niente ritardi al passaggio (anche `dwellClick` ha ritardo 0). Non riallungare la card.
- **Stili iPhone con un pulsante**: «Usa sull'iPhone» salva `phoneTheme`, il server manda `theme` in `/status` (solo se vinto), lo script lo usa con il Parameter vuoto. Da decidere con Nick: stili legati alle buche 1/5/7 invece che a punti e serie.
- **Minigolf**: prato subito, Campo ghiacciato a 200 buche fatte, Biliardo a 888. "Buche fatte" = tutti i task con la stima, anche i bogey.
- Le prove esatte e le definizioni (disastro = oltre 5 volte la stima; al 70% = giornata con almeno il 70% di gemme, contando i giorni con almeno 10 buche) sono nel documento e in `COURSE` dentro `dove-sono.py`. Se cambi una regola, cambiala in tutti e due.

## Procedura

**A. "A che buca sono?"**
1. `python3 -I ~/.claude/skills/tasketa-gioco/references/dove-sono.py` (o `--json`).
2. Rispondi in italiano semplice: buca e titolo, punti al green, le prove con l'avanzamento, il prossimo potere, quante buche mancano al prossimo campo del minigolf.

**B. Aggiornare la mappa**
La mappa è un parco di minigolf visto dall'alto (come le mappe vere dei parchi, ma nello stile sobrio di TaskETA). Ogni buca ed edificio apre una scheda al passaggio del mouse, al focus o al tocco (su telefono è un foglio dal basso):
- Urbe Hub, dentro la U della buca 6, disegnato come un pollaio tech (tetto di pannelli solari, antenna con la luce, un pollo e un dino) = il motore: task-eta di Dino (Urbe.eth) e l'analisi del lunedì;
- club house = come si gioca;
- bacheca = i poteri;
- tabellone all'ingresso = dove sei;
- chiosco = cosa fare mentre Claude lavora, secondo quanto dura l'attesa (Doomscrolling evitato, ripartenza pronta);
- segnapunti di Claude, in cima a Monte Donato = anche Claude gioca: il suo punteggio sulle stime (DATA.ai);
- totem del widget iPhone = cosa mostra il widget oggi e con il campo, e quando si è aggiornato (DATA.phone);
- prato, ghiaccio, biliardo = i campi del minigolf;
- lavori in corso = cosa resta da costruire.

Un monopattino percorre le buche chiuse e si ferma sulla buca in corso, tanto avanti quanto i punti verso il green (Nick, 25/10: «sono a 2/3, quindi dovrei essere a 2/3 del percorso 5»); con il green raggiunto aspetta in buca le prove. Ghiaccio e biliardo ancora chiusi mostrano le buche fatte contate dall'inizio («Biliardo · 219/888») con una barra. Easter egg chiesti da Nick:
- cliccare il monopattino fa un trick: 1 clic saltello, 2 un 360, 3 o 4 un backflip, 5 il turbo, cioè 300 km/h per 2,4 secondi fino in fondo al campo e ritorno;
- un clic su Trump Lake fa galleggiare un cappellino rosso dove clicchi (restano gli ultimi 6);
- ognuno dei 12 cespugli nasconde un segreto (Nick, 25/10): un clic lo scuote, l'oggetto salta fuori e si apre la sua scheda; «Segreti nei cespugli: N di 12» sotto la mappa, salvato nel browser (`localStorage`, chiave `campo-cespugli`). I segreti stanno in `SECRETS` nello script (segnato `←`), i disegni in `LOOT`: pallina persa di Dino, John Cena («You can't see me», non esce niente), il pollo evaso dall'Urbe Hub, il cappellino asciutto, il dino che fa capolino, il piccone della miniera, la scorecard sospetta, il riccio, il buono caffè del chiosco, il foglietto di Claude («ci metto 2 minuti» → «9»), l'aereo di carta per @yakonft, il tee d'oro;
- sotto la mappa: «Per gli easter egg scrivi su Telegram a @yakonft» (link https://t.me/yakonft), voluto da Nick.
1. Lancia `dove-sono.py --json`.
2. Copia `templates/il-campo.html` nella scratchpad e cambia solo l'oggetto dopo `DATA = window.CAMPO_DATA ||` in cima allo script (segnato `←`): ora, punti, buche fatte, titolo, serie, giro di oggi, `nowHole`, `prevGreen` (green dell'ultima buca chiusa) e per ogni buca stato (`done` / `now` / `todo`) e prove (`ok` / `part` / `no` con l'avanzamento). `phone.synced` porta già la preposizione («alle 17:13») o è `null`. Stato delle buche, bandiera che sventola, lucchetti del minigolf, intestazione e monopattino si sistemano da soli. Sul web `atShort`, `eta`, `embed` e `still` non servono: senza `CAMPO_DATA` i font arrivano da Google Fonts.
3. In una conversazione nuova: prima `Artifact` con `action: "read"` sull'URL, poi publish con `url` uguale, così il link resta lo stesso.
4. Nell'app la mappa si aggiorna da sola: i numeri li dà `Campo.swift` a ogni apertura della dashboard.
5. Se cambi il disegno (tracciati in `<defs>`: `h1`–`h9` le buche, `w0`–`w8` i vialetti) o lo script, metti la versione nuova sia in `templates/il-campo.html` sia in `widget/campo/il-campo.html` della repo, e controlla con `cmp` che siano uguali. Nella repo non committare se non te lo chiede Nick.

**C. Costruire un pezzo**
1. Segui i "Primi passi" del documento, in ordine: `kind_declared` in `PastTask` → `Course.swift` → `--course-report` con i selftest → "Il campo" nella dashboard → `GolfRules` con mazza forte, ghiaccio, biliardo → poteri delle stime → sfida del giro → widget e Touch Bar.
2. Lavora nella repo sul branch `starcks`. Compila con `widget/build.sh`, prova con `--selftest`, `python3 -m unittest discover -s tests`, poi installa come dice la memoria del fork.
3. Se un'altra sessione lavora nella repo, committa solo i tuoi file con i percorsi espliciti.
4. Aggiorna `YAKO.md`, il documento (sposta da [nuovo] a [c'è già]) e questa skill.

## Regole di Nick, non negoziabili

- Leggero, sempre: ogni potere è un numero letto quando parte una partita o si apre la dashboard. Nessun timer, nessuna animazione a riposo, nessuna immagine o suono nuovo. Il timer del minigolf gira solo mentre la pallina si muove.
- Si avanza a buche fatte e a buche fatte bene. Niente valute da spendere: Nick ha corretto il 24/10 i "gettoni spesi" in "buche fatte".
- Gli sblocchi devono essere evidenti: un potere vinto funziona da solo, uno da vincere dice quale buca lo dà. Niente da scrivere nel Parameter di Scriptable per gli stili: Nick non capiva il riquadro "Stili del widget iPhone".
- Grafica sobria. Nella Touch Bar solo testo, niente icone di gemme o diamanti (Nick le trova cringe).
- Italiano semplice, frasi corte. Spiegazioni visive.
- Revisioni e analisi da agenti esterni senza il contesto della chat, quando servono.

## Gotcha pagati

- `PastTask` (Dashboard.swift) non legge `kind_declared`: serve per Eagle, per le prove sui quick e sui medium e per la sfida "un birdie su un medium".
- `GolfStats.save` tiene solo le ultime 500 partite: non contarci per totali storici.
- `segments` nell'indice conta le volte che il task si ferma e riparte (messaggi aggiunti a metà, domande di ritorno, job in background), non solo i messaggi aggiunti: nel perché scrivi «si è fermato e ripartito».
- La Touch Bar ha già una cache delle gemme (`gemStats()`, ricaricata solo quando l'indice cambia): riusala, non rileggere le 800 KB dell'indice a ogni partita.
- I punti nell'indice si muovono mentre Nick lavora: nella mappa scrivi l'ora dei numeri.
- Anteprima della mappa: usa una porta libera e chiudi solo il tuo processo, per PID. Il 24/10 un `pkill -f "http.server 879"` ha chiuso i server di altre sessioni (8791, 8793).
- La prima mappa (lista di 9 schede in fila) a Nick non piaceva: la voleva più dinamica, più corta, con il popup al passaggio del cursore e fatta come la mappa vera di un parco di minigolf (24/10). Non tornare alla lista. Le spiegazioni lunghe stanno nel documento, non nella pagina.
- Nello script della mappa le funzioni stanno tutte nello stesso blocco: una seconda `function place(...)` (quella del monopattino) copriva quella delle schede, che si aprivano lontano dalla buca. Ora le schede usano `placePop`: non riusare un nome già presente. E `.pop` ha un suo `display`, quindi serve `.pop[hidden] { display: none; }` (24/10).
- Su telefono la mappa scorre di lato (larga almeno 820 px) e le schede diventano un foglio dal basso. Se aggiungi un edificio, mettigli `data-k`, `tabindex="0"`, `role="button"`, un `aria-label` e una scheda in `CARDS`.

## Output atteso

- "A che buca sono": 5–8 righe come quelle di `dove-sono.py`, in italiano.
- Mappa aggiornata: il link (sempre lo stesso) e una riga su cosa è cambiato.
- Costruzione: cosa hai fatto, i test con il loro esito, cosa resta.

## Non ancora fatto

- Nell'app c'è la mappa (finestra Analytics); cosa c'è già del resto del gioco lo dicono `YAKO.md` e i «Primi passi» del documento.
- Idee per dopo: Vento a favore (bonus serie fino a +500), campo di sabbia nel minigolf, una palla da colpire nel biliardo, Stagione 2.
