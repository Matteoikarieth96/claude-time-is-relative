# Prossimo push: la traccia

Lista viva di tutto quello che entra nel prossimo push, aggiornata man mano.

**Dove siamo:** branch `starcks`, v2.7 committata col tag `yako-v2.7` (24 ottobre, sera). Sul repo privato `yako` (il remote del fork) ci sono v2.6, v2.7, la pulizia e i documenti dopo (`yako/starcks` a `5d0e0ef`, 25/10). La v2.8 (la miniera) non è ancora committata.

**Regola:** il push va solo su `yako`, mai su `origin`, che è il repo originale di Dino.

## Per ripartire (sessione "Widget tempo del prompt", 24/10 18:50)

Chi riprende da qui trova tutto in questo file e nella memoria `task-eta-widget-fork.md`.

- **Stato:** la v2.7 è committata (tag `yako-v2.7`). L'app installata in `~/Applications` è la build delle 19:15, con gli stessi sorgenti del commit (selftest ok, 155 test ok). Lo script del widget iPhone è in iCloud.
- **Chi aspetta cosa:**
  - Nick deve ancora provare a mano le cose della colonna "Da provare a mano" e della sezione del gioco: quello che non va si sistema in un commit dopo la v2.7.
  - Pulizia profonda fatta (sezioni A, B, C, E di `docs/pulizia.md`, non la D) in un commit a parte dopo la v2.7, installata. Cosa è stato tolto e cosa saltato: in cima a `docs/pulizia.md`.
  - Il push di v2.6 e v2.7 è fatto (25/10, con l'ok di Nick). Il prossimo push porterà la v2.8, sempre solo con il suo ok.
- **Decisioni aperte di Nick:**
  1. Live Activity come DAZN (blocco schermo e Dynamic Island mentre un prompt è live): serve un'app iPhone vera, Xcode e l'Apple Developer Program a 99 € l'anno. Proposta: una sessione dedicata. In alternativa, subito e gratis: una notifica a fine prompt (iMessage a se stesso o ntfy).
  2. Routine del gioco: aggiungere il "giro del campo" al task del lunedì `tasketa-analisi-settimana` (aggiorna la mappa e una riga sul gioco nell'analisi) invece di una routine nuova.
  3. Le tre scelte del gioco nella sezione "Dopo la v2.7" (regole degli stili, punteggio di Claude nella mappa, mazza forte).
- **Come si è chiusa la v2.7:** compilazione unica con `widget/build.sh`, `--selftest`, 155 test, `YAKO.md` aggiornato, commit con i percorsi espliciti e tag `yako-v2.7`, pulizia avvisata. Il push è fatto (25/10).
- **Attenzioni:**
  - per copiare negli appunti serve `LANG=en_US.UTF-8` prima di `pbcopy`;
  - due compilazioni insieme in `widget/build/` si scontrano: se c'è un'altra sessione, compilare in una cartella della scratchpad;
  - l'immagine di prova della dashboard legge le preferenze vere solo se il programma sta dentro un `.app` con l'`Info.plist` dell'app.

## Nella v2.6 (caricata)

- Widget iPhone:
  - niente copia e incolla, perché l'app tiene lo script in iCloud;
  - non si blocca mai: prova IP e nome insieme, massimo 4 secondi;
  - nel blocco schermo il tempo viene prima di tutto;
  - chiaro o scuro, più 3 stili da vincere.
- Analisi della settimana: lunedì alle 9 un agente esterno legge solo i numeri (`widget/insights/`).
- Touch Bar: pulsante nella Control Strip e barra piena con le sessioni (`TouchBar.swift`).
- Clic restando sopra con il puntatore (`Hover.swift`), ⌘R e ⌘1-3 nella dashboard; la riga del minigolf si accende solo passandoci sopra.
- Progetto del gioco: `docs/gioco-progressione.md`.

## Nella v2.7 (caricata)

| Cosa | File | Chi | Verificato | Da provare a mano (Nick) |
|---|---|---|---|---|
| Dashboard a widget modificabili. Griglia a 4 colonne, misure da 1×1 a 4×4, «Modifica» o ⌘E, «Aggiungi», «Ripristina». Disposizione salvata in `dashboardLayout` | `DashboardGrid.swift`, `Dashboard.swift` | agente dashboard | immagini in chiaro e scuro, selftest, 144 test | trascinare, menu della misura, il «−», Ripristina, scorrimento dello Storico |
| Prima i dati. Confronti col periodo prima, «Dove sbagliano le stime» per tipo, modello e progetto, Adesso dal vivo. Il periodo parte da 7 giorni ed è ricordato (`dashboardRange`); 7 e 30 giorni sono giorni interi | `Dashboard.swift` | agente dashboard | immagini | — |
| Esiti in parole semplici (Stima centrata, Più veloce, Nella forchetta, Sforata), meme come nota piccola | `Dashboard.swift` | io (revisione) | immagine | — |
| Statistiche inutili, la prima è «Doomscrolling evitato» (minuti di minigolf mentre Claude lavora). Si personalizzano (`dashboardFunStats`) | `FunStats.swift` | agente dashboard + io | immagine coi dati veri (10 min, 32 partite) | «Personalizza» |
| Sigle colorate dei progetti, loghi scelti da Nick (`~/.claude/task-eta/logos/`), simboli inventati per i modelli | `Marks.swift` | agente dashboard | immagine con un logo di prova | «Loghi» con un'immagine vera |
| Apertura animata: numeri e barre una volta sola; niente se c'è Riduci movimento | `Dashboard.swift` e altri | agente dashboard | fotogramma a metà | dal vivo |
| Analisi della settimana come widget; si apre passando sull'icona | `Insights.swift` | agente dashboard + io | immagine | il passaggio sull'icona |
| Gemme: riassunto 2×1. Gemme, minigolf e serie sono nascosti di partenza | `Gems.swift` | agente dashboard | immagine | — |
| Touch Bar: pulsante disegnato (capsula col gradiente, sessioni impilate dietro), approvato da Nick sulla Touch Bar vera. Le sessioni oltre 4 si scorrono | `TouchBar.swift`, `main.swift` (immagine di prova) | sessione Touch Bar | immagine; approvato dal vero | lo scorrimento |
| Widget iPhone come vista a distanza delle sessioni (nuova richiesta di Nick): tante barre come nel pannello del Mac, ottimizzate, prima chi ti aspetta; niente analisi (niente percentuali, ore, statistiche, gemme, analisi della settimana). Serve per restare collegato al Mac dal telefono | `widget/iphone/TaskETA.js`, `PhoneServer.swift` | agente iPhone | 336 prove nel simulatore, controllo della sintassi Swift e JavaScript. Script in iCloud e server ridotto (2,1 KB) installati con la build delle 18:17 | tutte le misure sull'iPhone |
| Il campo dentro Analytics: la mappa del gioco come widget «Il campo» (4×5). La pagina web esiste solo con Analytics aperta, prende i numeri dall'app (`window.CAMPO_DATA`) e usa i font Barlow (OFL) in Resources. Minigolf e gemme rifatti nello stile della mappa | nuovi: `widget/campo/` (il-campo.html, font), `Campo.swift`, `CampoStyle.swift`. Cambiati: `build.sh` (1 riga), `DashboardGrid.swift` (misura 4×5, widget del campo), `Dashboard.swift` (`PastTask` con segments e tools, minigolf), `Gems.swift` (la parte della dashboard), `main.swift` (selftest del campo, mappa nell'immagine di prova) | sessione "Il campo dentro Analytics" | finito e installato (build delle 18:17): selftest, 144 test | aprire Analytics e passare il mouse sulle buche (la scheda si apre accanto); cliccare @yakonft (si apre il browser); scorrere con la rotella sopra la mappa; trascinare il widget in «Modifica»; chiaro e scuro |
| Gioco: documento aggiornato (nomi del campo, monopattino, Urbe Hub, gioco utile: attese brevi, prompt migliori, risultati spiegati; le gemme come gioco anche per Claude; il progetto "La mappa dentro Analytics", cioè un widget della dashboard con la mappa e i numeri dell'app, ancora da costruire). La mappa è un artifact: [Il campo di TaskETA](`<link dell'artifact privato, nella skill installata>`) | `docs/gioco-progressione.md` | sessione gioco | solo documento, il codice del gioco non c'è | — |
| Mood del gioco, scelto da Nick («che uno può modificare il mood in quello che preferisce; ora sono due ma in futuro possono essere altri»). Minigolf, di partenza: lo scorecard con i segni del golf (hole in one disco pieno nell'anello, birdie cerchio, par punto, bogey quadrato), «buche buone» e bogey. Gemme: diamanti, zaffiri, smeraldi e sassi. Le regole non cambiano. Salvato in `gameMood`. Seguono il mood la card (titolo «Lo scorecard» o «Gemme delle stime»), i testi del campo, la mappa di «Il campo» (`DATA.mood`) e la Touch Bar (nome della buca). Per un mood nuovo basta un `case` in più | nuovo: `GameMood.swift`. Cambiati: `Gems.swift`, `Campo.swift`, `CampoEngine.swift`, `Dashboard.swift` (Impostazioni > Gioco), `DashboardGrid.swift` (titolo), `TouchBar.swift`, `PhoneServer.swift` (una chiamata), `main.swift` (selftest), `widget/campo/il-campo.html` | sessione gioco | build delle 19:04 installata: selftest ok, 155 test ok, immagini della dashboard nei due mood | Impostazioni > Gioco, o il selettore in fondo alla card: passare a Gemme e tornare a Minigolf; guardare lo scorecard di oggi, la collezione, il grafico, la mappa in «Il campo» (club house, segnapunti di Claude) e la Touch Bar dopo una buca |
| Card del gioco corta (Nick: «troppo lunga: metti molte cose che nascono ed escono se ci passi sopra o le clicchi; istantaneo»). A riposo: la buca in corso e il fairway verso il green, lo scorecard di oggi con il punteggio sul par, il prossimo potere. Il resto dietro 8 chip (Prove, Oggi, Collezione, Minigolf, Claude, A cosa serve, Stili iPhone, Mood): si apre appena il puntatore è sopra, resta finché il puntatore è sui chip o sul riquadro, sparisce quando esci; un clic lo tiene aperto (bordo rosso), un altro clic lo chiude. Nessuna animazione. Aiuto di «Clic restando sopra con il puntatore» aggiornato (si apre appena ci passi sopra; `Hover.swift` con ritardo 0) | `Gems.swift` (GemsCard, GemsDetail), `Dashboard.swift` (testo dell'aiuto), `Hover.swift` (della sessione principale, compilato) | sessione gioco | build delle 19:15 installata: selftest ok, 155 test ok, immagini a riposo e con «Stili iPhone» aperto (chiaro e scuro) | passare sui chip uno per uno (si aprono subito), scendere nel riquadro (resta), uscire (sparisce); clic per tenerlo aperto |
| Stili del widget iPhone spiegati e con un pulsante (Nick: «spiega bene sti 3 e se si può mettere un bottone che li applica»). Nel chip «Stili iPhone»: anteprima di ognuno (Automatico chiaro/scuro, Fairway prato verde con «in corso» giallo, Golf di notte blu notte, Trofeo oro con testo marrone), una riga su com'è, «Usa sull'iPhone» per quelli vinti, il lucchetto con come vincerli per gli altri. La scelta va in `phoneTheme`, il server la manda in `/status` come `theme` (solo se vinto, se no `auto`), lo script la usa quando il Parameter è vuoto; il Parameter vince ancora. Il widget cambia da solo al prossimo aggiornamento | `Gems.swift` (PhoneTheme, PhoneThemeTiles, anteprime), `PhoneServer.swift` (`theme`), `widget/iphone/TaskETA.js` (applyTheme, testo della finestra) | sessione gioco | 48 prove nel banco di prova (6 misure, online e offline, con e senza `theme`, `auto`, il Parameter che vince); `/status` risponde `theme: auto`; script in iCloud riscritto alle 19:15 | cliccare «Usa sull'iPhone» su Fairway o Golf di notte e aspettare il prossimo aggiornamento del widget (Parameter vuoto); tornare ad Automatico |

Fuori dal repo, da non committare qui: le skill `tasketa-gioco` e `yako-touch` in `~/.claude/skills`, e il task programmato `tasketa-analisi-settimana`. La skill `yako-touch` ora mette, dove c'è un easter egg, "Per gli easter egg scrivi su Telegram a @yakonft". I suoi pacchetti per claude.ai vanno caricati a mano: `~/.claude/skills/_pacchetti-claude-ai/yako-touch.skill`.

## La 2.8.1 (25/10, unita in `starcks` e installata)

Sopra `yako-v2.8`: piccone come livello, con Claude che si valuta e chiede l'upgrade (riga ⏱ e blocco del prompt, `task_eta.py piccone`); insegne; «Come si fa un diamante»; il perché del colpo; tocco di velluto; filone; Herobrine. Dettaglio in `YAKO.md`. Unita in `starcks` la mattina del 25/10 (Nick: «usciamo tutti alla 2.8.1»), con in più la ✕ sugli avvisi e un avviso solo per sessione. Da caricare su `yako`: 07327f2, 778e316, v2.8, v2.8.1, solo con l'ok di Nick.

## La v2.8 (25/10 notte)

Nick, prima di dormire: «manda un agente che fa il resto e controlla tutto … fai fare test e controllo … fai un branch e fai gli upgrade e le idee che ti vengono insieme ai sub agenti». Quindi:
- la v2.8 si chiude sul branch `starcks` con il tag `yako-v2.8`, dopo la revisione di un agente senior e le prove di un agente tester;
- le idee della notte vanno sul branch `notte-2.8.1` (tag `yako-v2.8.1`), da guardare al mattino prima di unirle;
- nessun push: è tutto in locale finché Nick non dice ok.

Cosa c'è dentro, oltre alla tabella qui sotto:
- miniera con 10 oggetti e diamante entro il 5%;
- Faro di Surry acceso da una settimana all'80% di stime buone (con almeno 20 colpi), più fari possibili;
- cifre in VT323;
- schema in «A cosa serve»;
- minigolf: ostacoli, giro del giorno, tiri leggeri, palla ripresa, menu della striscia (sessione «ostacoli», note in `side-session-notes/…/ostacoli-e-giro-del-giorno.md`);
- card del minigolf nuova (sessione «card»);
- pallino con le raffiche.

### Il dettaglio (com'era prima del commit)

| Cosa | File | Verificato | Da provare a mano (Nick) |
|---|---|---|---|
| La miniera in stile Minecraft, mood di partenza: 6 minerali, blocchi da 9 diamanti, ultimi 16 colpi, consiglio sulla direzione dell'errore, stili iPhone a 1, 5 e 10 blocchi. Minigolf resta extra, «Gemme» diventa Miniera | nuovi: `widget/Sources/Miniera.swift`, `widget/miniera/fonts/` (Pixelify Sans, OFL). Cambiati: `GameMood.swift`, `Gems.swift`, `DashboardGrid.swift`, `PhoneServer.swift`, `Campo.swift`, `build.sh`, `main.swift` | build del 25/10 01:16 installata, selftest ok (con `MineTest`), immagini della dashboard e dell'inventario | la card in Analytics, passare sui tre pulsanti; salvare le icone in `~/.claude/task-eta/minerali` e riaprire Analytics |
| Il minerale a fine task: nella riga, nel box della barra dei menu, nella Touch Bar (solo nome); «N blocchi di diamante, k/9» nella barra piena | `Celebration.swift`, `StatusItem.swift`, `TouchBar.swift`, `TaskStore.swift` | immagini del pannello e della Touch Bar | finire un task e guardare riga, barra dei menu e Touch Bar |
| Stima centrata = entro l'8%, senza il minimo di 10 secondi (il punteggio di Claude nell'hook lo tiene) | `Celebration.swift`, `CampoEngine.swift` | selftest | — |
| Card del minigolf rifatta nello stile del campo | sessione «Card del minigolf nello stile del campo», `Dashboard.swift` o un file nuovo | in corso | — |

Il test della privacy falliva per il percorso della tua home in `extras/scheduled/tasketa-analisi-settimana.md` (commit `c58c08b`, già su `yako`): corretto dalla sessione fork in `07327f2`, non ancora caricato. Su `yako` il percorso resta nella storia di `c58c08b`: il repo è privato.

## Dopo la v2.7

- **Il gioco a livelli, prima versione** (agente del gioco; entrato nella v2.7):
  - `CampoEngine.swift`: a che buca sei, le prove e i poteri, ognuno col suo perché e con «Cosa fare». Riusa le regole di `Campo.swift`.
  - `GolfRules.swift` e `Golf.swift`: mazza forte (buca 4), ghiaccio a 200 buche fatte, biliardo a 888, solo parametri. In fondo al minigolf c'è il campo («Prato · mazza forte»); un clic sceglie quello della prossima partita.
  - `Gems.swift`: il blocco «IL CAMPO» nella card delle gemme. `CampoStyle.swift`: i campi del minigolf risultano costruiti (`built`).
  - `main.swift`: `--course-report`.
  - **Anche Claude gioca**, già attivo in `task_eta.py`: una riga nel blocco `[task-eta]` con il punteggio di Claude, contro la forchetta dell'hook (circa 55 token, +4 ms). Si spegne con `task_eta.py score off`. Nuovo `tests/test_score.py` (11 test).
  - Da provare: il blocco «IL CAMPO» in Analytics, `--course-report`, il minigolf (tiri più lunghi, nome del campo in fondo), ghiaccio e biliardo con `open -a TaskETA --env TASKETA_DEBUG_FIELD=ghiaccio` (oppure `biliardo`), `task_eta.py score`.
  - Scelte che toccano a Nick:
    - gli stili del widget (`WidgetTheme`) usano ancora le regole vecchie (notte a 10 di fila, oro a 40.000 punti), il campo li dà con le buche 5 e 7;
    - la mappa misura Claude sulla forchetta scritta da Claude: conviene farle usare lo stesso punteggio dell'hook;
    - «mazza forte dopo 10 di fila» è stata fatta come potere della buca 4: se intendevi 10 buche di fila al minigolf, è una riga.
  - Per dopo: Mulligan, Buca doppia, Eagle, il consiglio del caddie; il campo salvato nelle partite; la riga dell'attesa nel pannello; il punteggio di Claude nell'analisi del lunedì; aggiornare documento, `YAKO.md` e la skill.
- Pulizia profonda del codice: fatta in un commit a parte dopo la v2.7 (sezioni A, B, C, E di `docs/pulizia.md`; la D aspetta Nick). Entra nel push insieme alla v2.7.

## Prima del push

1. ~~Compilazione unica, selftest, 155 test~~ (fatto, 24/10 sera).
2. ~~`YAKO.md`: riga v2.7 e sezioni per area~~ (fatto).
3. ~~Commit e tag `yako-v2.7`~~ (fatto).
4. Nick prova le voci della colonna "Da provare a mano"; si sistema quello che non va, in commit dopo la v2.7.
5. ~~Push su `yako`: branch `starcks` e tag `yako-v2.6` e `yako-v2.7`~~ (fatto, 25/10). Mai su `origin`.
