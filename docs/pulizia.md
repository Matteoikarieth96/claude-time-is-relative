# Pulizia profonda di TaskETA: l'inventario

## Com'è andata (fase 2, 24 ottobre sera, dopo il commit della v2.7)

Fatte le sezioni A, B, C ed E; la D aspetta Nick. Nel codice: 241 righe tolte e 108 riscritte, 133 in meno. Controlli: build, `--selftest`, 155 test, sintassi dello script dell'iPhone, e le foto prima e dopo di pannello, Touch Bar e dashboard (anche con tutti i widget e le schede del gioco): identiche, a parte l'ora scritta sotto la mappa.

- **A, tolto tutto:** `PhoneGame`, `GemStats.fresh` e il parametro `today:`, `PhoneInsights`, `isRecent` e `generatedDate`, `WidgetTheme.emoji`, `DashCard`, `doneRecentlyCount` e `doneRecentlyWindow`, `parseDeclaredEstimate`, `menuColor`, `notifyNote`. Nello script dell'iPhone, i rami per l'app v2.6 (`game`, i pezzi della nota).
- **B, fatto:**
  - B1: livelli da `CampoCourse.rules`; giro da 18 e 70% da `CampoCourse`, anche nella Touch Bar; punteggio sul par della Touch Bar da `CampoHole.toPar` e `CampoData.signed`; serie con `CampoGame.bestRun`; `ClaudeScore.mark` usa `outcomeOf`; nomi vecchi dei tipi in un solo `legacyKinds`.
  - B2: `GemStats.current` è l'unica cache delle gemme per Touch Bar e server dell'iPhone, che ora la legge sul thread principale come la Touch Bar. `TaskStore.indexURL` in tutti e quattro i posti.
  - B3: `store.doneCount` e `store.runningCount` per barra dei menu, pannello corto e iPhone.
  - B4: `GolfStats.forDashboard()`, letto una volta per widget; `DashDebug.golf` e `DashDebug.gems`.
  - B5: `TaskStore.golfClicks` (101). Il `grouped` privato resta: è solo una scorciatoia locale.
- **B6, saltato:** `--phone-script` scrive sempre, mentre il sync dell'app scrive solo se lo script è cambiato. Non è un doppione vero, resta com'è.
- **C, fatto tutto** (anche `unlockedBySlide` diventato `unlockedByKeys`; l'id del traguardo resta "slide").
- **E:** `CampoStyle.walk` tolto. I due "voti di Claude" restano: la mappa conta sulla forchetta che scrive Claude, il motore su quella dell'hook, quindi non sono la stessa cosa.
- **Trovato nella v2.7, non toccato:** `CampoGameCard` (`CampoEngine.swift`), una scheda del campo che nessuno mostra. Può essere un pezzo ancora da collegare: va chiesto a chi l'ha scritta prima di toglierla.

Fase 1, solo lettura (24 ottobre, 18:10). Qui c'è cosa togliere, perché, quanto rischia e in che ordine. Non è stato tolto niente: la pulizia vera si fa in un colpo solo dopo il commit della v2.7, con l'ok di Nick.

**Da sapere prima di leggere**

- I numeri di riga sono quelli delle 18:08, sulla v2.6 più il lavoro della v2.7 non ancora committato. Altre sessioni stanno lavorando su `Campo.swift`, `CampoStyle.swift`, `CampoEngine.swift`, `Dashboard.swift`, `Gems.swift`, `Golf.swift` e `GolfStats.swift`, quindi le righe si sposteranno. Prima di togliere qualcosa si ricontrolla ogni voce cercandola per nome.
- La regola: dopo la pulizia l'app fa esattamente le stesse cose. Le voci che cambierebbero quello che vedi stanno nella sezione D, e si fanno solo se dici sì.
- **Cosa non tocco.** `task_eta.py`, `install.py`, `tests/` e `docs/src/` sono il codice di Dino, quasi intatto: rispetto al suo ci sono 19 righe diverse. Lì non ho trovato niente di morto, e toccarli renderebbe più difficile prendere i suoi aggiornamenti.
- **Restano anche le opzioni di prova** (`TASKETA_DEBUG_*`, `--snapshot`, `--dashboard-snapshot`, `--touchbar-snapshot`, `--cheer`…). A riposo non costano niente: si leggono una volta all'avvio. Servono agli agenti per fotografare l'app, perché la shell qui non può fare screenshot.
- Come le ho cercate: una copia ferma del codice e una scansione di ogni nome dichiarato e mai usato, seguendo anche le catene (quello che resta inutile una volta tolto un pezzo morto). Poi ho controllato a mano ogni candidato, e confrontato con la v2.6 committata e con il codice di Dino.

## A. Codice morto: si toglie, e l'app resta identica

| # | Cosa | Dove | Perché è morto | Rischio |
|---|---|---|---|---|
| A1 | `PhoneGame`: le gemme per l'iPhone | `Gems.swift:268-311` | Dalla v2.3 alla v2.6 il server la mandava all'iPhone dentro `/status` (`body.game`). Nella v2.7 l'iPhone mostra solo le sessioni e il server non la crea più. Si porta dietro `GemStats.fresh` (`Gems.swift:193-197`) e il parametro `today:` di `GemStats.count` (`Gems.swift:180`), usati solo da lei | nullo |
| A2 | `PhoneInsights`: l'analisi della settimana per l'iPhone | `Insights.swift:148-161` | Stessa storia: la v2.6 la mandava (`body.insights`), la v2.7 no. Si porta dietro `isRecent` e `generatedDate` (`Insights.swift:41-44`), che servivano solo a lei. Il campo `generated` resta, perché fa parte del formato di `insights.json` | nullo |
| A3 | `WidgetTheme.emoji` | `Gems.swift:244-250` | Nessuno lo legge: la dashboard disegna gli stili come pallini colorati e lo script dell'iPhone ha i nomi suoi | nullo |
| A4 | `DashCard` e la sua chiave `dashCardBare` | `Dashboard.swift:396-428` | La vecchia scheda della dashboard, quella di prima della griglia di widget. L'hanno sostituita `WidgetChrome` (`DashboardGrid.swift`) e `CampoPlate`, e nessuno la usa più | basso. `Dashboard.swift` è in lavorazione: ricontrollo dopo il commit |
| A5 | `TaskStore.doneRecentlyCount` e `doneRecentlyWindow` | `TaskStore.swift:110-111`, `661-667` | Viene dalla versione di Dino: la barra dei menu contava i task finiti negli ultimi 30 minuti. In Yako la barra conta i task finiti visibili, cioè quelli dell'ultima ora (`StatusItem.swift:146`), e questa funzione non la chiama nessuno. Anche il commento che dice che la usa la barra dei menu è sbagliato | nullo |
| A6 | `parseDeclaredEstimate` | `TaskStore.swift:736-737` | Una scorciatoia sopra `parseDeclaredLine` che non chiama nessuno, già nel codice di Dino | nullo |
| A7 | `Pace.menuColor` | `Views.swift:36-37` | Il colore per la barra dei menu, che oggi si disegna con altri colori. Nessuno lo usa | nullo |
| A8 | `Prefs.notifyNote` | `Prefs.swift:88-89`, letto in `Views.swift:670` e `Dashboard.swift:1352` | Doveva dire "macOS blocca le notifiche", ma nessuno lo imposta mai: è sempre vuoto. Quando macOS le rifiuta, l'app mostra i suoi avvisi | nullo |
| A9 | Script dell'iPhone, i pezzi per la vecchia app del Mac | `widget/iphone/TaskETA.js:56-60` e `727-728` (`d.game.themes`), `174-185` (il ripiego di `noteOf` su `overText`, `waiting`, `end`) | Servivano a far funzionare lo script nuovo con l'app v2.6, che mandava `game` e i pezzi separati invece di `note`. È l'app stessa a scrivere lo script in iCloud prendendolo dal suo pacchetto, quindi script e server arrivano sempre insieme. L'app installata (build delle 17:57) manda già `note` | basso: controllo della sintassi con `node --check` e un'occhiata al widget sull'iPhone |

Sono circa 130 righe in tutto.

## B. Doppioni: una versione sola, stesso risultato

**B1. Le regole del gioco ripetute dentro l'app.** I numeri restano gli stessi. Il selftest controlla già punti, livelli, gemme e buche del campo.

- **Livelli e soglie** (Principiante 0 … Leggenda del green 300.000): sono sia in `GemLevel.steps` (`Gems.swift:86-90`) sia in `CampoCourse.rules` (`Campo.swift:77-107`). `GemLevel` può leggerli da `CampoCourse`.
- **Il giro da 18 buche**: c'è `GemStats.roundHoles` (`Gems.swift:144`), c'è `CampoCourse.round` (`Campo.swift:72`), e il "/18" è scritto a mano nella Touch Bar (`TouchBar.swift:219`, `502-503`). Basta una costante.
- **L'obiettivo del 70%**: è sia in `GemsGuide.goal` (`Gems.swift:580`) sia in `CampoCourse.goal` (`Campo.swift:69`).
- **Il punteggio sul par** (−2, −1, 0, +1): c'è `CampoHole.toPar` (`Campo.swift:26-33`), e la Touch Bar ha una tabella sua con un suo modo di scrivere il segno (`TouchBar.swift:215-218`), uguale a `CampoData.signed(par:)`.
- **La serie migliore**: è calcolata tre volte, in `GemStats.bestStreak` (`Gems.swift:173-177`), `GemChallenge.threeInARow` (`Gems.swift:132-135`) e `CampoGame.bestRun` (`Campo.swift:261-268`). Ne basta una, `bestRun`.
- **La regola dell'esito** (centrata entro l'8% o 10 secondi, forchetta di riserva da 0,7 a 1,5 volte la stima): c'è `outcomeOf` (`Celebration.swift:42`) e la riscrive `ClaudeScore.mark` (`CampoEngine.swift:100-104`, nel motore in costruzione).
- **I nomi vecchi dei tipi di task** (veloce, medio, lungo): sono sia in `TaskStore.swift:728` sia in `CampoEngine.swift:82`.

Rischio basso. Questi file però sono in lavorazione, quindi questa parte va per ultima.

**B2. L'indice letto e ricalcolato due volte mentre l'app gira in background.** La Touch Bar (`TouchBar.swift:229-237`) e il server dell'iPhone (`PhoneServer.swift:200-210`), ognuno con la sua cache, rileggono `index.json` (893 KB oggi) e rifanno i conti delle gemme ogni volta che cambia. Con una cache sola, a ogni task finito l'indice si legge una volta invece di due: più leggero, con Touch Bar e iPhone accesi. Il percorso di `index.json` è anche costruito in quattro posti (`PhoneServer.swift:201`, `TouchBar.swift:230`, `Dashboard.swift:1276`, `main.swift:551`): ne basta uno, `TaskStore.indexURL`.

**B3. I conteggi delle sessioni.** "Fatti" è contato a mano in tre posti (`StatusItem.swift:146`, `Views.swift:636`, `PhoneServer.swift:227`). "In corso", in `PhoneServer.swift:226`, rifà `store.runningCount`. Basta un `store.doneCount`, che prende il posto di A5.

**B4. Il minigolf nella dashboard.** `MinigolfCard` e `MinigolfWidget` (`Dashboard.swift:1447-1448` e `1599-1600`) leggono ognuno le partite salvate (fino a 500) a ogni ridisegno: basta una funzione sola. Anche i flag di prova sono sparsi: `TASKETA_DEBUG_GOLF` si legge in tre punti (`TaskStore.swift:328`, `Dashboard.swift:1447`, `1599`) e `TASKETA_DEBUG_GEMS` in `DashboardGrid.swift:687`. Possono stare tutti in `DashDebug`, letti una volta sola.

**B5. Cose piccole.**

- `grouped`, privato, è ripetuto in `GemsCard` (`Gems.swift:540`) e in `MinigolfCard` (`Dashboard.swift:1589`), e chiama solo `CampoData.grouped`.
- La soglia dei 101 clic del minigolf è scritta in `TaskStore.swift:569` e in tre testi (`Dashboard.swift:1459-1460`, `1613`). Diventa una costante.

**B6. Lo script dell'iPhone in iCloud.** `TaskETA --phone-script` (`main.swift:469-483`) ricopia a mano quello che fa `PhoneServer.syncScript` e legge il codice direttamente dalle preferenze. Può chiamare lo stesso codice dell'app. L'opzione resta.

**Doppioni che per ora restano, e perché.**

- **Le regole del gioco fuori dall'app**: lo script della skill `~/.claude/skills/tasketa-gioco/references/dove-sono.py`, l'analisi del lunedì `widget/insights/export.py` (esito, punti, livelli), la mappa `widget/campo/il-campo.html` (numeri di esempio e tabella dei punti) e la sua sorgente nella skill (`templates/il-campo.html`, 63 righe diverse). Girano senza l'app, perché leggono solo l'indice, e quindi non si possono semplicemente togliere. Proposta per dopo, finito il motore: `TaskETA --campo-json` stampa i numeri, e `dove-sono.py` li chiede all'app tenendo le sue regole solo come riserva. Per `export.py`, un test che confronta i suoi punti con quelli dell'app su un indice di prova.
- **Le notifiche di macOS** (`Notifier.swift`): con l'app firmata "ad hoc" macOS le rifiuta sempre e si vedono gli avvisi dell'app. Il codice resta per il giorno in cui l'app sarà firmata davvero (vedi D4).

## C. Commenti e documenti vecchi

- **C1** `main.swift:9-22`, l'elenco delle opzioni: dice che `--login` lo usa `build.sh`, invece lo usa `install.py`. Mancano `--dashboard-snapshot`, `--celebrate`, `--compact`, `--burst`, `TASKETA_DEBUG_DASH`, `_GEMS`, `_CLICK` e `_POPOVER`.
- **C2** `FunStats.swift:3-4`: "(the iPhone gets none of this)". Ora l'iPhone riceve solo le sessioni: basta dire che i prompt non lasciano mai il Mac.
- **C3** `Insights.swift:4-6`: "a tap away, on the iPhone". Non è più così.
- **C4** `Gems.swift:4-8`: "for the dashboard and the iPhone widget". E `Gems.swift:63`: "the same on the Mac and on the iPhone". L'iPhone non disegna più le gemme.
- **C5** `widget/insights/export.py:9-11` e `widget/insights/README.md` (punto 3): "lo manda all'iPhone… un tocco sul widget apre l'analisi intera". Non succede più.
- **C6** `widget/README.md`: nella tabella dei file ne mancano 10 (`PhoneServer`, `Insights`, `TouchBar`, `Hover`, `DashboardGrid`, `FunStats`, `Marks`, `Campo`, `CampoStyle`, `CampoEngine`). `Gems` dice ancora "dashboard and iPhone". `DotFeedback` dice "the slide to unlock", che non c'è più dalla v2.5: ora si sblocca trascinando il pallino con ⌘ M G.
- **C7** Un nome rimasto vecchio: il parametro `unlockedBySlide` (`GolfStats.swift:211-216`, `Dashboard.swift:1451-1452`, `main.swift:309`) parla dello sblocco a scorrimento, che non c'è più dalla v2.5; ora vuol dire "con i tasti". Diventa `unlockedByKeys`. Il valore salvato "scorrimento" resta leggibile, così il tuo vecchio sblocco conta ancora.
- **C8** `YAKO.md:87` e `:132`, nelle sezioni per area, dicono ancora che le gemme sono sull'iPhone. Va sistemato insieme alla riga della v2.7, nella sessione che prepara il push.

## D. Da decidere: cambiano qualcosa che vedi, quindi non sono nella pulizia

- **D1** Ci sono due sfide per la stessa cosa. La «Sfida di oggi» delle gemme (`GemChallenge`, `Gems.swift:100-139`, mostrata nella scheda delle gemme) e la «sfida del giro» del campo (`Campo.swift:246-257`). Il progetto del gioco dice che la sfida del giorno diventa una sfida per giro.
- **D2** Gli stili del widget dell'iPhone si vincono con regole diverse da quelle del campo. Nell'app: Fairway a 10.000 punti, Golf di notte con 10 gemme di fila, Trofeo a 40.000 (`Gems.swift:260-266`). Nel campo sono i poteri delle buche 1, 5 e 7. Quando il motore accende i poteri, deve restarne una sola.
- **D3** Nelle impostazioni ci sono «Copia lo script» e «Mettilo in Scriptable» (`Dashboard.swift:1341-1344`), ma lo script arriva da solo ogni minuto. Proposta: togliere «Mettilo in Scriptable» e tenere «Copia» per chi non ha iCloud.
- **D4** Il codice delle notifiche di macOS: lo tengo, a meno che tu non sappia già che l'app non sarà mai firmata.

## E. Da ricontrollare dopo il commit della v2.7

Sono file in lavorazione adesso: queste voci si guardano quando sono fermi.

- `CampoStyle.walk` (`CampoStyle.swift:27`): un colore che oggi non usa nessuno.
- Il "voto di Claude sulle sue stime" sembra calcolato due volte: in `CampoData.claude` (`Campo.swift:359-380`, sulla forchetta che scrive Claude) e in `ClaudeScore` (`CampoEngine.swift:74-137`, sulla forchetta dell'hook). Se la mappa passa al motore, il primo si toglie.
- Le schede delle gemme e del minigolf, che la sessione «Il campo dentro Analytics» sta ridisegnando: si rifà la scansione quando ha finito.

## L'ordine

1. Aspettare il commit della v2.7, con il motore del campo finito: lo chiedo alla sessione che tiene traccia del push.
2. **A**, il codice morto: prima lo Swift (A1-A8), poi lo script dell'iPhone (A9). Build e selftest.
3. **C**, commenti e documenti.
4. **B**, i doppioni: prima nei file fermi (B2-B6), poi le regole del gioco (B1), che toccano i file nuovi del campo.
5. **E**: una nuova scansione dei file appena committati, e quello che risulta morto si toglie nello stesso giro.
6. Le verifiche: `widget/build.sh`, `--selftest`, `python3 -m unittest discover -s tests`, `node --check` sullo script dell'iPhone, e le foto di pannello e dashboard (`--snapshot`, `--dashboard-snapshot`) prima e dopo, che devono venire uguali. Poi installazione, una riga in `YAKO.md` e un commit a parte con solo i file toccati. Niente push.

Non entrano: i doppioni che restano (sezione B), la sezione D senza il tuo sì, e il codice di Dino.
