# Yako

La versione di task-eta usata da Starcks: branch `starcks`, partita dal commit `2fa316e` dell'originale (24 ottobre 2026). Il motore delle stime è quello di Dino, toccato solo per renderlo più veloce (`task_eta.py`, `guess_category`). Tutto il resto riguarda il widget (`widget/`).

Dalla v3 si chiama anche **Yako's Mode**: la panoramica in inglese, per Dino e per chi lo trova pubblico, è in [YAKOS-MODE.md](YAKOS-MODE.md).

## Versioni

| Tag | Cosa porta |
|---|---|
| `yako-v3` | **Yako's Mode.** L'inglese è la lingua di base, l'italiano la seconda: si sceglie in Impostazioni (Language / Lingua: Sistema, English, Italiano) e cambia al volo, senza riavviare. Seguono la lingua la barra dei menu, la lista, il pannello, la dashboard con i suoi widget, le impostazioni, gli avvisi, la Touch Bar, le feste, la miniera, il minigolf, il campo, il widget dell'iPhone e, nell'hook, la fine della riga `elapsed` («· Smeraldo» / «· Emerald») e `task_eta.py piccone`. Le ultime due modifiche di Dino (link nel README, flag del portachiavi nel render dei docs). Il pulsante della Touch Bar torna da solo dopo lo stop, lo sblocco o un cambio utente. Pronto per essere pubblico: niente nomi di clienti o percorsi personali, e un test che li blocca. Panoramica in inglese in `YAKOS-MODE.md` |
| `yako-v2.9` | La miniera: la settimana al posto degli ultimi 16 colpi (e Claude vede la sua), l'oggetto trovato cade nella riga e raccoglierlo chiude la riga, le piramidi del faro crescono sempre e quelle finite vanno sull'orizzonte. Il minigolf: la striscia ha la sua riga, sponde esatte nelle buche 10-18, John Cena si può zittire, una vera mappa di calore dei tiri, un giorno diverso ogni giorno (vento, calamita, portali, Pac-Man, buca timida…) e la mira con i rimbalzi. Il campo: il monopattino si ferma lungo la buca in gioco. La tendina si chiude quando il puntatore se ne va, il doppio clic apre la dashboard |
| `yako-v2.8.1` | Avvisi con una ✕ per chiuderli e uno solo per sessione. La miniera, seconda passata: il livello è il piccone (legno, pietra, ferro, oro, diamante) e Claude si valuta da solo, scrive cosa ha trovato a fine risposta e chiede l'upgrade quando è pronto; un'insegna sotto ogni oggetto; «Come si fa un diamante» con i tuoi numeri; il perché di ogni colpo; il tocco di velluto; il filone; Herobrine |
| `yako-v2.8` | La miniera in stile Minecraft è il mood di partenza: dieci oggetti, cinque buoni dal diamante (stima entro il 5%) al carbone e cinque negativi dalla ragnatela alla carne marcia, blocchi da 9 diamanti al posto dei punti, ultimi 16 colpi e da che parte sbagliano le stime, il Faro di Surry acceso da una settimana all'80% di stime buone. Il minerale trovato compare a fine task nella riga, nella barra dei menu e nella Touch Bar. Minigolf resta come mood extra. Il minigolf: ostacoli, giro del giorno da 18 buche, tiri leggeri, palla ripresa mentre rallenta, striscia da spostare o nascondere, card nuova nello stile del campo. Il pallino: le sorprese tornano a ogni raffica |
| `yako-v2.7` | Dashboard a widget da spostare e ridimensionare, prima i dati, esiti in parole semplici, statistiche inutili («Doomscrolling evitato»), sigle e loghi dei progetti. Il gioco a livelli: «Il campo» in Analytics, poteri, minigolf con mazza forte, ghiaccio e biliardo, e anche Claude gioca (una riga nell'hook). Mood del gioco a scelta (Minigolf o Gemme), card corta con i dettagli al passaggio. Widget iPhone solo con le sessioni in barre, stili applicati con un pulsante. Touch Bar che scorre oltre 4 sessioni. Clic al passaggio istantaneo |
| `yako-v2.6` | Widget iPhone senza copia-incolla (lo script arriva da iCloud) e mai bloccato, col tempo prima di tutto nel blocco schermo, chiaro o scuro, e 3 stili da vincere. Analisi della settimana scritta da un agente esterno. TaskETA nella Touch Bar. Clic restando sopra con il puntatore. La riga del minigolf si accende solo passandoci sopra. Progetto del gioco a livelli in `docs/gioco-progressione.md` |
| `yako-v2.5` | Gemme delle stime, sul Mac e sull'iPhone, con la spiegazione di a cosa servono. Il minigolf si sblocca in due soli modi: il 101° clic, o il pallino trascinato tenendo ⌘ M G |
| `yako-v2.4` | Il dinosauro delle 69 sponde: "Coming soon" |
| `yako-v2.3` | Widget per iPhone. Il pallino conta ogni clic e lo ricorda, sussulta, mostra il numero e suona; tappe a 8, 69 e 101, oppure lo sblocco a scorrimento. Il minigolf diventa un gioco: par, punti, serie, quasi-buche, sfida del giorno, traguardi, e una sezione nella dashboard |
| `yako-v2.2` | Tiri di sponda; esultanza più euforica (fanfara, voci cantate, audio tuo) |
| `yako-v2.1` | Minigolf dietro il pallino di "in corso" |
| `yako-v2` | Dashboard, finestra delle impostazioni, pannello che scorre e pannello corto, festa nella barra dei menu, primo easter egg |
| `yako-v1` | Interfaccia in italiano, barra dei menu, animazioni di fine task, avvisi, prestazioni |

## Pannello e tendina

- In inglese o in italiano (v3, vedi «Lingua»): "running" / "in corso", "needs you" / "ti aspetta", "done" / "fatto", "est." / "stima", "actual" / "reale".
- Una riga per sessione. Le richieste precedenti si aprono con un clic e sono unite da una linea.
- Lo sforamento è scritto chiaro ("+10 min oltre la stima (×6)", su una pillola leggibile) e la parte della barra oltre la stima ha righe diagonali.
- Le barre sono sfumate, con un riflesso in alto. I trattini della stima non tagliano il testo.
- Il pannello sulla scrivania è in Liquid Glass "regular" (macOS 26): luminoso come i widget di sistema (v2; il "clear" della v1 sembrava spento).
- Il pannello scorre con trackpad e rotella e mostra tutte le sessioni dell'ultima ora (v2).
- **Pannello corto** (v2): un clic sull'intestazione lo riduce a "▶ in corso  ✓ fatti", senza tempi, più la manina se un task ti aspetta. Lampeggia di verde quando un task finisce e di arancio quando Claude ti aspetta. Un altro clic lo riapre.
- Il clic sul titolo di una riga apre la chat nell'app Claude (`claude://code/continue?session=local_…`).
- "fatto" toglie dalla lista una sessione finita, con un suono.
- La tendina si apre anche lasciando il puntatore sul simbolo nella barra dei menu e scorre. Comunque si sia aperta, anche con un clic, si richiude un secondo dopo che il puntatore se ne va; non mentre tieni premuto il tasto o è aperto un suo menu. Lascia il posto alla dashboard e alle impostazioni.

## Lingua (v3)

- **Inglese di base, italiano come seconda lingua.** In Impostazioni, in cima: «Language / Lingua» (scritto in tutte e due, così lo trova chiunque) con Sistema, English e Italiano. Sistema segue la prima lingua del Mac, e se non è l'italiano va in inglese. Le installazioni nuove partono da Sistema.
- **Al volo:** cambiando lingua si ridisegnano lista, pannello, dashboard, impostazioni, menu dell'app, barra dei menu, Touch Bar e la mappa del campo; il widget dell'iPhone la prende al giro dopo (lo script in iCloud si riscrive quando cambia, entro un minuto).
- **Condivisa con l'hook:** la scelta sta in `~/.claude/task-eta/language.json` (`{"choice": "it", "language": "it"}`, con la lingua già risolta, così l'hook non chiede niente a macOS). La legge la fine della riga `elapsed` («· Smeraldo» o «· Emerald», e il piccone pronto) e `task_eta.py piccone`. Le righe del blocco `[task-eta]` scritte per Claude restano in inglese; cambia solo la frase da dire («prendi il piccone» / "take the pickaxe"). Da Terminale: `task_eta.py language it` (o `en`, `system`); l'app se ne accorge in pochi secondi.
- **Sul Mac di Nick è impostato l'italiano**: per lui non cambia niente finché non sceglie altro.
- **Come funziona:** ogni testo nel codice è `L("English", "Italiano")` (`Loc.swift`), con plurali e generi decisi nel codice per ciascuna lingua. Per una terza lingua: un `case` in `Lang` e, in `L()`, le sue parole cercate per il testo inglese, che `LText` tiene come modello (`"{1} running"`), per esempio da un file JSON nelle risorse dell'app. Non c'è ancora: oggi le lingue sono due. I nomi di Minecraft in inglese sono quelli ufficiali (Diamond, Emerald, Gold Ingot…, Wooden Pickaxe…), il Faro di Surry è Surry's Beacon.
- `TASKETA_LANG=en` o `it` fa una corsa dell'app (o un'anteprima) in quella lingua senza toccare la scelta.

## Barra dei menu

- Un box colorato con i prompt in corso, quelli finiti nell'ultima ora e il tempo di quello che dura di più: "▶ 3  ✓ 2  ⏱ 12m04s".
- Il colore segue il prompt più lungo: verde in tempo, arancio oltre la stima, rosso oltre la forbice, grigio quando non gira niente. Una manina arancio quando un task ti aspetta.
- Quando un task finisce, per qualche secondo il box diventa il timbro dell'esito, nei suoi colori (v2). È l'unico posto sempre a vista.

## Animazioni di fine task

Durano 3,5 secondi nella riga. Con "Riduci movimento" resta solo il timbro.

| Esito | Animazione | Timbro |
|---|---|---|
| entro l'8% della stima | fuochi d'artificio | 🤌 Dai che ci siamo |
| sotto la forbice | un razzo con scintille | 🦵 C'hai quella gamba lì |
| dentro la forbice | coriandoli | 🎉 GG |
| oltre la forbice | fiamme dal fondo | 🔥 This is fine, con di lato 🦖 Dino Gay |

## Avvisi

- Arrivano quando un task finisce (con l'emoji dell'esito) e quando Claude ti aspetta. Si sceglie se riceverli con il widget a vista (la base), sempre o mai.
- macOS rifiuta le notifiche di sistema a un'app firmata ad hoc, com'è questa quando la compili sul Mac. Per questo l'app mostra le sue: un riquadro di vetro in alto a destra, che con un clic apre la chat. Usa quelle di macOS solo se le sono permesse.
- Passandoci sopra compare una piccola ✕ che chiude l'avviso senza aprire la chat (v2.8.1). Una sessione ha un avviso solo: quello nuovo prende il posto del vecchio, così non se ne impilano cinque uguali.

## Dashboard (v2)

- Una finestra con la storia di tutti i task dell'indice di task-eta:
  - in cima task, ore, stime azzeccate e serie migliore;
  - gli esiti con i timbri;
  - stima contro tempo reale, in scala logaritmica;
  - ore per giorno, tempo per progetto e per modello;
  - la mappa di giorni e orari;
  - lo storico, con la ricerca e il link alla chat;
  - "Il gioco": le gemme delle stime (v2.5) e, accanto, il minigolf (v2.3). Il minigolf, prima dello sblocco c'è solo un indizio, con i clic fatti su 101. Dopo, ci sono partite, buche, serie, record di sponde, punti, tiri per buca, quasi-buche, buca più veloce, la sfida di oggi, le buche per par, le 5 migliori partite e i traguardi.
- Il periodo si sceglie: 7 giorni, 30 giorni o tutto.
- Si apre con il doppio clic sul simbolo nella barra dei menu o sull'intestazione del pannello o della tendina (un doppio clic vero, anche nella tendina aperta passando sopra, dove prima ne servivano tre), dalla rotellina e dal menu TaskETA (⌘D).
- Legge l'indice solo quando la apri e lo libera quando la chiudi.

**A widget** (v2.7)
- Griglia a 4 colonne. Ogni riquadro è un widget da 1×1 a 4×4 (4×5 per «Il campo»). «Modifica» o ⌘E per trascinarli, cambiarne la misura e toglierli; «Aggiungi» e «Ripristina». La disposizione resta nelle preferenze (`dashboardLayout`).
- Prima i dati: il confronto col periodo prima, «Dove sbagliano le stime» per tipo, modello e progetto, «Adesso» dal vivo. Il periodo parte da 7 giorni e resta quello scelto; 7 e 30 giorni sono giorni interi.
- Gli esiti in parole semplici (Stima centrata, Più veloce, Nella forchetta, Sforata), con il timbro come nota piccola.
- **Statistiche inutili**, da scegliere con «Personalizza». La prima è «Doomscrolling evitato»: i minuti passati al minigolf invece che sui social mentre Claude lavora.
- Sigle colorate dei progetti, o il loro logo da `~/.claude/task-eta/logos/` («Loghi»), e un simbolo per ogni modello.
- All'apertura numeri e barre salgono una volta sola; niente con «Riduci movimento».
- L'analisi della settimana è un widget: si apre passando sull'icona.
- Gemme, minigolf e serie sono nascosti di partenza: si aggiungono con «Aggiungi».

## Impostazioni

- Le trovi dietro la rotellina della tendina e in una finestra loro (v2), dal menu TaskETA (⌘,) e dalla dashboard.
- Gruppi: dove vederli, avvisi, privacy, iPhone, sistema.
- Il menu TaskETA ha anche Modifica (copia e incolla) e Finestra.
- **Clic restando sopra con il puntatore** (v2.6, acceso di base): sui comandi che aprono o mostrano qualcosa (un'analisi, la dashboard, una cartella, altre righe) basta passarci sopra. Dalla v2.7 è istantaneo, una volta per passaggio, con la manina. Mai su quelli che tolgono, mandano o cambiano qualcosa.

## Widget per iPhone (v2.3)

- Impostazioni > iPhone accende un piccolo server sul Mac: porta 8765, spento di base. Risponde solo a `GET /status`, solo a chi è su una delle reti del Mac e solo con il codice.
- Il widget è uno script di Scriptable (`widget/iphone/TaskETA.js`) per tutte le misure: Home piccolo, medio e grande; blocco schermo rotondo, rettangolare e in riga.
- Fuori dalla Wi-Fi mostra gli ultimi dati in grigio. Nel blocco schermo c'è la cartella al posto del prompt.
- I pulsanti:
  - "Copia lo script" lo mette negli appunti con indirizzo e codice già dentro;
  - "Mettilo in Scriptable" lo salva in iCloud Drive > Scriptable;
  - "Nuovo codice" chiude fuori gli script vecchi.
- Per vederlo solo mentre programmi: una Full immersione con la sua schermata di blocco e la sua pagina Home.
- Bianco, nello stile della lista del Mac: titolo e stato, la barra a capsula con i tempi dentro, cartella e modello sotto.
- **Niente da copiare** (dopo la v2.5): con il server acceso, l'app tiene iCloud Drive > Scriptable > TaskETA.js uguale al suo script, con nome, IP e codice del Mac dentro. Controlla ogni minuto (nuova build, nuovo codice, nuovo IP) e scrive solo se cambia. `TaskETA --phone-script` fa lo stesso da Terminale.
- **Mai bloccato:** iOS dà al widget pochi secondi. Il widget chiede insieme all'IP e al nome del Mac, tiene la prima risposta e dopo 4 secondi mostra gli ultimi dati in grigio. Se qualcosa si rompe, il widget scrive l'errore e la riga invece di restare vuoto.
- **Blocco schermo, il tempo prima di tutto:** nel rettangolare il tempo grande (quello che scorre, o quello reale dell'ultimo task), poi cartella e stima, poi la barra o lo sforamento. Le gemme restano nel rotondo e nella Home.
- **Chiaro o scuro come l'iPhone:** testi e sfondi seguono l'aspetto del telefono; barre e gemme usano un grigio che si legge su entrambi.
- **Tre stili da vincere** (easter egg): ⛳ Fairway (10.000 punti), 🌙 Golf di notte (10 gemme di fila, le gemme brillano), 🏆 Trofeo (40.000 punti). Nella v2.6 si sceglievano scrivendo `fairway`, `notte` o `oro` nel Parameter del widget. **Dalla v2.7 c'è un pulsante:** nel gioco della dashboard, chip «Stili iPhone», ogni stile ha la sua anteprima, una riga su com'è e «Usa sull'iPhone» se è vinto (il lucchetto e come vincerlo, se no). La scelta (`phoneTheme`) arriva al widget come `theme` in `/status` al prossimo aggiornamento; il Parameter, se scritto, vince ancora.
- **Analisi della settimana:** ogni lunedì alle 9 un task programmato dell'app Claude fa da analista esterno. Legge solo i numeri preparati da `widget/insights/export.py`, niente chat né prompt, e scrive `~/.claude/task-eta/insights.json`. La dashboard la mostra («Leggi l'analisi», dalla v2.7 un widget). Vedi `widget/insights/README.md`.
- **Solo le sessioni** (v2.7, voluto da Nick: «mi serve per restare collegato al PC»): il widget è una vista a distanza del pannello del Mac. Tante barre come nella lista, prima chi ti aspetta, poi chi gira; niente analisi (percentuali, ore, statistiche, gemme e analisi della settimana sono tolte). Piccolo: la sessione più urgente e «Le altre…»; medio: 2 o 3 righe compatte; grande: 5 o 6 righe; il blocco schermo resta col tempo prima di tutto. Il server manda solo quello che serve (circa 2 KB).


## Touch Bar

Progettata da un revisore esterno (un agente senza il contesto della chat) e poi realizzata.

- **Pulsante nella Control Strip**, sempre largo 100 punti, accanto a luminosità e volume: una capsula disegnata a mano col gradiente del ritmo, e le altre sessioni come carte impilate dietro (niente numero da decifrare). Mostra per primo ciò che conta di più:
  1. ✋ e quante sessioni ti aspettano, in arancio;
  2. per 6 secondi il nome golfistico della buca appena finita;
  3. il tempo del task più a rischio, sul colore del ritmo, con quanti ne girano;
  4. ⌛ i job in background;
  5. ✓ i turni finiti negli ultimi 10 minuti che non hai ancora aperto;
  6. ⚑ il giro di oggi ("11/18").
- **Un tocco riempie la Touch Bar** (un altro tocco, la ✕ o 20 secondi senza tocchi la chiudono):
  - ✕;
  - un pulsante per sessione, ordinate per urgenza: chi ti aspetta (con cosa: domanda, piano, permesso…), chi rischia di più, i job in background, i turni appena finiti, i fermi. Un tocco apre la chat di quella sessione;
  - oltre 4 sessioni la fila scorre di lato (v2.7): "+N ›" porta alle altre, "‹" torna all'inizio;
  - il giro contro il par ("Giro 6, buca 2/18, +1"): un tocco apre la dashboard.
- Senza sessioni: "Nessuna sessione nell'ultima ora" e «Apri Claude».
- **Torna sempre** (v3; Nick: «molto spesso la touch bar non si vede»): la Control Strip dimentica i pulsanti delle app quando riparte, dopo lo stop, il blocco dello schermo, la finestra di login o un cambio utente. L'app rimette il pulsante al risveglio del Mac e degli schermi, allo sblocco e al ritorno nella sessione (subito e di nuovo dopo 3 secondi), e ridice alla Control Strip che c'è a ogni cambio di app e ogni 20 secondi. In più, ogni secondo guarda se il pulsante sta ancora in una finestra della Touch Bar: se ne resta fuori per 5 secondi (e il pannello pieno è chiuso) lo rimette, al massimo ogni 30 secondi. Sono controlli da niente, nessun lavoro in più a riposo. Da provare: blocca lo schermo (⌃⌘Q), sblocca e guarda se il pulsante c'è; poi lo stesso dopo uno stop.
- Usa le chiamate private di DFRFoundation (come MTMR e Pock): su un Mac senza Touch Bar non fanno niente. Si spegne in Impostazioni > Dove vederli. `TaskETA --touchbar-snapshot file.png` la disegna con i task di prova.

## Gemme delle stime (v2.5)

- **Le stime diventano un giro di golf.** Ogni task con la stima di Claude è una buca, e la stima è il suo par:

  | Esito della stima | Buca | Gemma | Punti |
  |---|---|---|---|
  | centrata | Hole in one | 💎 diamante | 300 |
  | più veloce della forchetta | Birdie | zaffiro | 150 |
  | dentro la forchetta | Par | smeraldo | 100 |
  | oltre la forchetta | Bogey | sasso | 0 |

- **Sopra le gemme:**
  - ogni gemma vale 25 punti in più per ogni gemma di fila prima, fino a +250;
  - nove livelli, da Principiante a Leggenda del green;
  - giri da 18 buche, la serie e la sfida del giorno.
- **A cosa servono:** misurano quanto puoi fidarti del ⏱ di Claude, non danno un voto a te né a Claude. Nella dashboard ci sono tre parti:
  - "A cosa servono";
  - "Cosa ti dicono adesso": una lettura delle ultime 18 buche con un consiglio pratico (tanti sassi vogliono dire task più grossi di come li chiedi, da spezzare; tanti zaffiri, che puoi chiedere di più in una volta) e il progetto in cui le stime sforano di più;
  - "Il fine": tenere almeno il 70% di gemme nelle ultime 18 buche, con una barra che mostra dove sei.
- **Dove si vedono:**
  - nella dashboard, sotto "Il gioco", accanto al minigolf;
  - sull'iPhone, nel widget, fino alla v2.6: dalla v2.7 il widget mostra solo le sessioni, e delle gemme arrivano solo gli stili vinti.
- **Niente viene salvato:** tutto si ricava dall'indice di task-eta.
- **Il mood del gioco** (v2.7): le regole sono le stesse, il vestito si sceglie in Impostazioni > Gioco o in fondo alla card (`gameMood`).
  - Minigolf, di partenza: «Lo scorecard» con i segni del golf (hole in one disco pieno nell'anello, birdie cerchio, par punto, bogey quadrato).
  - Gemme: diamanti, zaffiri, smeraldi e sassi.
  - Seguono il mood la card, il campo e la Touch Bar. Per un mood nuovo basta un `case` in `GameMood.swift`.
- **Card corta** (v2.7): a riposo la buca in corso, lo scorecard di oggi sul par e il prossimo potere. Il resto sta dietro 8 chip (Prove, Oggi, Collezione, Minigolf, Claude, A cosa serve, Stili iPhone, Mood): si apre appena ci passi sopra, resta finché il puntatore è sui chip o sul riquadro, un clic lo tiene aperto.

## Il gioco a livelli (v2.7)

Il progetto completo è in `docs/gioco-progressione.md`; la mappa anche come artifact privato.

- **Il campo**: 9 buche, una per livello, con le stesse soglie di punti. I punti portano al green, le prove mettono in buca, la buca chiusa accende un potere. Tre zone: il Pratone dei Gardens (buche 1–3, una prova), Trump Lake (4–6, due prove), Monte Donato (7–9, tre prove).
- In Analytics è il widget «Il campo» (4×5): la mappa del parco, con una scheda per ogni buca ed edificio al passaggio del puntatore. La pagina vive solo con Analytics aperta e prende i numeri dall'app; font Barlow (OFL) in `widget/campo/`.
- `CampoEngine.swift` dice a che buca sei, le prove e i poteri, ognuno con il suo perché e «Cosa fare». `TaskETA --course-report` lo stampa.
- **Il minigolf cambia** (`GolfRules.swift`): mazza forte con la buca 4, Campo ghiacciato a 200 buche fatte (la pallina scivola), Biliardo a 888 (6 buche). Solo numeri letti a inizio partita. In fondo al minigolf c'è il campo scelto; un clic sceglie quello della partita dopo.
- **Anche Claude gioca**: l'hook aggiunge al blocco `[task-eta]` una riga con il punteggio delle stime di Claude, misurato sulla forchetta dell'hook (circa 55 token, +4 ms). `task_eta.py score` lo mostra, `score off` e `score on` spengono e accendono la riga; anche `TASK_ETA_SCORE=off`.

## La miniera (v2.8)

Il mood di partenza del gioco, in stile Minecraft (`Miniera.swift`). Minigolf resta come extra in Impostazioni > Gioco; il vecchio mood «Gemme» diventa la miniera.

- **Ogni task con la stima è un colpo di piccone.** Quello che trovi dice quanto era giusta la stima:

  | Oggetto | Quando |
  |---|---|
  | Diamante | tempo esatto, entro il 5% |
  | Smeraldo | entro il 25% |
  | Lingotto d'oro | dentro la forchetta |
  | Lingotto di ferro | fuori dalla forchetta, entro una volta e mezza |
  | Carbone | entro il doppio: l'ultimo dei buoni |
  | Ragnatela | sbagliata fino a 3 volte |
  | Patata velenosa | fino a 5 volte |
  | Polvere da sparo | fino a 7 volte |
  | Occhio di ragno | fino a 10 volte |
  | Carne marcia | oltre 10 volte |

  Cinque buoni e cinque negativi, voluti da Nick. «Volte» vale nei due sensi: il doppio o la metà della stima.

- **Il Faro di Surry** (il beacon di Minecraft), a destra nella card. Si accende con una settimana, da lunedì a domenica, con almeno l'80% di stime buone (dal diamante al carbone) e almeno 20 colpi: ogni settimana riuscita è un faro in più, e la card conta i fari accesi. La piramide, vista di lato con tre livelli da 3, 5 e 7 blocchi, ha un cursore che sceglie di che minerale è fatta (diamante, smeraldo, oro, ferro o carbone), e i suoi blocchi sono i minerali di quel tipo presi finora, col numero scritto sopra: un blocco ogni N minerali, con N uguale per tutti e scelto perché il minerale trovato di più riempia la piramide (Nick: «se avrò 100 carboni e 20 diamanti, nella slide del carbone avrò più blocchi»). 1 minerale è già un blocco, 0 è la piramide vuota. Coi dati del 25/10 (81 lingotti d'oro, 14 diamanti, 14 carboni) N è 6: 14 blocchi d'oro, 3 di diamante, 3 di carbone. Nei dati della prima settimana: dal 57 al 67% al giorno, il tratto migliore 17 su 20, quindi l'80% è un obiettivo vero.
- **Niente punti:** 9 diamanti fanno un blocco di diamante, come sul banco da lavoro, e il fine è fare blocchi. La card mostra il banco con i diamanti verso il prossimo blocco e i blocchi fatti.
- **Ultimi 16 colpi** (16 come il lato di un chunk di Minecraft, non i 18 delle buche), con quelli di oggi col bordo giallo, e sotto da che parte sbagliano le stime: troppo corte (task più grossi di come sembravano: chiedi un pezzo alla volta) o troppo lunghe.
- Dietro i pulsanti: «Inventario» (tutti i minerali di sempre, come pile con il numero), «A cosa serve», «Stili iPhone». Gli stili del widget si vincono con i blocchi: Prato al primo, Notte al quinto, Oro al decimo.
- **A fine task** il minerale trovato compare nella festa della riga (con il tempo sulla stima), nel box della barra dei menu e, solo come nome, nella Touch Bar. Nella barra piena della Touch Bar, al posto del giro: «2 blocchi di diamante, 3/9».
- **Il diamante senza minimo:** il diamante è il tempo esatto, entro il 5% (Nick). «Stima centrata» nelle feste e nella dashboard resta entro l'8%, ma senza più il minimo di 10 secondi, che sui task brevi regalava diamanti (24 su 44). Il punteggio di Claude nell'hook tiene il suo minimo di 10 secondi.
- **Le icone sono quelle vere di Minecraft**, ma sono di Mojang: non stanno nel repo. Si salvano dalla wiki in `~/.claude/task-eta/minerali` con questi nomi: `diamante.png`, `smeraldo.png`, `oro.png`, `ferro.png`, `carbone.png`, `ragnatela.png`, `patata-velenosa.png`, `polvere-da-sparo.png`, `occhio-di-ragno.png`, `carne-marcia.png`, i blocchi `blocco-diamante.png`, `blocco-smeraldo.png`, `blocco-oro.png`, `blocco-ferro.png`, `blocco-carbone.png` e il faro `faro.png`. Nick le ha prese dalla wiki italiana di Minecraft (file .webp, convertiti in PNG). Finché manca un file, al suo posto c'è un quadrato colorato.
- Il carattere è Pixelify Sans, con le cifre in VT323 perché il 5 di Pixelify sembra una S e il 2 una Z; tutti e due con licenza OFL, in `widget/miniera/fonts`. Quello di Minecraft non è libero. Le legature sono spente: la «fi» di Pixelify usciva come una «A».
- In «A cosa serve» c'è lo schema del gioco (task → diamante → 9 diamanti → blocco → faro) e la scala dei dieci oggetti, con le parole chiave in grassetto.

## Easter egg: il pallino e il minigolf

**Il pallino di "in corso"** (v2, rivisto in v2.3)
- Ogni pressione conta, anche i clic velocissimi, e il conteggio resta quando l'app si riavvia.
- Mentre lo premi si schiaccia. A ogni clic sussulta, sempre più forte verso il 101, e mostra sopra il numero del clic.
- Suona a ogni clic: un "plop" breve se lo tocchi, un "boing" se lo tieni premuto. La nota sale di circa due ottave fino al 101.
- All'8° clic un pallino schizza e rimbalza per tutto il box per 8 secondi. Al 69° ne partono 69.
- Al 101° clic, o al primo dopo, se l'hai superato: 101 pallini, "Oh yeah! John Cena!" e il minigolf si sblocca per sempre.
- L'altra strada (v2.5): trascina il pallino tenendo premuti ⌘, M e G insieme, e il minigolf si sblocca con la stessa festa. Il pallino segue il puntatore e, se lasci senza i tasti, torna al suo posto. Quando premi il pallino bloccato TaskETA passa in primo piano, così ⌘M e le lettere non arrivano all'app davanti. (In v2.3 si sbloccava scorrendo lungo "in corso": non più.)

**Il minigolf** (v2.1)
- Tieni premuto il pallino e tira, come una fionda: la linea di tiro è verde, gialla o rossa secondo la potenza.
- Quando lasci, la pallina parte nella direzione opposta, rimbalza sui bordi della lista e rallenta. Dove c'era il pallino resta una buca con la bandierina ⛳.
- Se ci ripassa sopra, è buca. Se no si ferma, e la ritiri da lì. Lasciata ferma per un minuto e mezzo torna a essere il pallino.

**Il gioco** (v2.3)
- Ogni buca ha par 3: al primo tiro è un Ace, poi Birdie, Par, Bogey e Doppio bogey.
- Punti: 100 per una buca, 50 in più per ogni sponda, il doppio con l'Ace, e 25 per ogni buca della serie che la precede.
- La serie conta le buche di fila. Una partita lasciata a metà (la pallina ferma per un minuto e mezzo) la azzera.
- "😱 Uuuh!" e un suono quando la pallina sfiora la buca senza entrarci: sono le quasi-buche.
- La sfida del giorno cambia ogni giorno: almeno 2 sponde, 2 tiri esatti, hole in one, 1 sponda esatta, buca in meno di 10 secondi o 3 buche di fila. Anche le sfide hanno la loro serie di giorni.
- Mentre giochi, in fondo alla lista c'è "🏆 record di sponde  🔥 serie  📅 sfida". Sulla festa della buca compaiono par, punti e serie, più "🏆 Nuovo record di sponde!" e "📅 Sfida del giorno vinta!" quando capita.
- Traguardi: Curioso, Nice, Sbloccato, Scorciatoia, Prima buca, Ace, Di sponda, Biliardo, Serie da 3, Quasi!, Mille, Sfida del giorno, Tre giorni, Coming soon.
- **Il dinosauro** (v2.4): a 69 sponde in tutto, contando tutte le partite, una volta sola, entra un 🦖 con un ruggito e un cartello "Coming soon". Poi lo gira: "Dai tempo al tempo, che nessuno mi sta pagando". Se la quota arriva con una buca, aspetta la fine della festa.
- Tutto resta nelle preferenze dell'app (le ultime 500 partite); niente esce dal Mac.

**Tiri di sponda** (v2.2): ogni rimbalzo in un tiro è una sponda, e più sponde fai, più è grande la festa.

| Sponde | Festa | Esultanza |
|---|---|---|
| 0 | fuochi, "⛳ Hole in one!" (o "Buca in N") | fanfara breve, "Oh yeah! John Cena!" cantato (voce Good News) |
| 1–2 | due ondate di fuochi, 30 pallini, "⛳ Di sponda!" / "⛳ 2 sponde!" | fanfara più lunga, "Oh yeah! Oh yeah!" cantato (Superstar) e "John Cena!" |
| 3+ | tre ondate di fuochi, coriandoli, 101 pallini, "🔥 3 SPONDE! 🔥" che trema | fanfara grande con accordo finale, tre "Oh yeah!" e la risata di Jester |

La fanfara è un arpeggio generico creato dall'app. L'audio vero di John Cena non è incluso perché è protetto da copyright, ma puoi mettere un tuo `john-cena.mp3` (o `.m4a`, `.wav`, `.aiff`, `.caf`) in `~/.claude/task-eta/sounds`: si sente al posto delle voci, due volte con 3 sponde. Nelle impostazioni ci sono "Cartella dei suoni" e "Prova l'esultanza".

## La miniera, seconda passata (v2.8.1)

Fatta di notte su richiesta di Nick, con le idee di un consulente esterno (gioco e marketing), rivista da un revisore senior e unita il 25/10.

- **Il piccone è il livello.** Si parte col piccone di legno; pietra al primo blocco di diamante, ferro al terzo, oro al primo Faro di Surry, diamante al terzo. Non si prende da solo:
  - **Claude si valuta da solo:** a fine risposta la riga ⏱ dice cosa ha trovato la sua stima («⏱ Actual time: ~2 min (likely 1 to 4 min: inside) · Smeraldo»);
  - quando il piccone dopo è pronto, la stessa riga **lo dice** («· ⛏ piccone di pietra pronto: se lo vuoi, di' «prendi il piccone»»), e il blocco `[task-eta]` del prompt dopo dice a Claude di prenderlo (`task_eta.py piccone su`) solo se lo chiedi per nome: un «sì» qualsiasi risponde alle altre domande, non a questa;
  - nella card c'è anche il pulsante «Prendi il piccone di …».
  Lo stato è in `~/.claude/task-eta/miniera.json`, condiviso da app e hook. `task_eta.py piccone` dice a che punto sei; si spegne con `TASK_ETA_MINE=off`. Le icone dei picconi (`piccone-legno.png` … `piccone-diamante.png`) stanno con le altre in `~/.claude/task-eta/minerali`.
- **Un'insegna di legno sotto ogni oggetto**, nell'inventario e nella scala: Esatta, Quasi esatta, Nella forchetta, Un po' fuori, Al limite, Sbagliata, Molto sbagliata, Esplosa, Fuori strada, Da buttare.
- **«Come si fa un diamante»** in «A cosa serve», con i tuoi numeri calcolati dal vivo: scrivi tutto nel primo messaggio (i colpi puliti sono buoni molto più spesso degli altri), un quick è una cosa sola (sopra 3 strumenti di lavoro sbaglia molto di più), un pezzo alla volta (quasi tutte le stime sbagliate sono troppo corte), lascia finire Claude. Gli strumenti contati sono quelli di lavoro: le chiamate della riga ⏱ e di `piccone` non contano.
- **Il perché del colpo:** ogni casella degli ultimi 16, passandoci sopra, dice perché è andata così e cosa fare; sotto la griglia c'è «Ultimo colpo: …» con il suo perché.
- **Tocco di velluto** (il colpo pulito: un turno solo e gli strumenti del suo tipo, un quick fino a 3, un medium fino a 15): bordo viola in alto nella casella, e una riga che li confronta con gli altri.
- **Il filone:** i colpi buoni di fila, ora e il record, sotto il banco da lavoro.
- **Le piramidi del faro crescono sempre** (Nick: «sennò si blocca appena fatta una piramide»): una misura fissa, 9 minerali per blocco come sul banco da lavoro e 15 blocchi per piramide. Una piramide finita va sull'orizzonte, piccola e lontana sopra quella davanti, e davanti ne parte una nuova; oltre tre, un numero. Il faro si accende sempre con la settimana all'80%.
- **La settimana al posto degli ultimi 16 colpi** (Nick: «basta tenere un overview totale; l'obiettivo è fare un beacon in una settimana»): «Questa settimana» mostra tutti i minerali trovati, in pile per tipo, la quota di stime buone e il confronto con la settimana prima; sotto, le settimane passate con la loro quota, il faro se acceso e i minerali più trovati. Un clic su una pila apre lo Storico solo su quei prompt, in quella settimana (con la ✕ per toglierlo).
- **Claude sa come va la settimana:** il blocco `[task-eta]` di ogni prompt ha una riga con la quota di stime buone di questa settimana, quella della settimana scorsa e la migliore, e ricorda l'obiettivo (un faro a settimana: 80% con almeno 20 colpi). I numeri stanno in `miniera.json`, scritti dalla riga ⏱: l'hook del prompt non legge l'indice.
- **L'oggetto cade nella riga** (Nick: «come in Minecraft, quando rompi un blocco e cade»): nella miniera, quando un task finisce, niente adesivo. Il minerale trovato cade nella riga della sua sessione, rimbalza e resta fermo al posto di «fatto»; passandoci sopra si alza un poco e dice cos'è. Un clic lo raccoglie, con il pop di Minecraft, e la riga esce dalla lista come con «fatto». A riposo non si muove niente (`Drops.swift`).
- **Easter egg:** in fondo ad «A cosa serve», «Rimosso Herobrine.», la battuta più vecchia dei changelog di Minecraft, con la riga di Telegram per gli easter egg.

## Minigolf e pallino (v2.8)

- **Il pallino:** ogni clic conta nel totale (che apre il minigolf a 101, una volta per sempre), nella sessione (da quando hai aperto TaskETA) e nella raffica, cioè i clic senza fermarti più di 1,5 secondi. Le sorprese a 8, 69 e 101 contano la raffica, quindi tornano ogni volta. Il numero sopra il pallino e il suono seguono la raffica. Nella card del minigolf, sotto «Record», ci sono i tre numeri e la raffica record.
- **Ostacoli** (muretti di legno e funghi a pois): da 5 hole in one di fila (la combo) ne compare uno, poi uno in più a ogni ace, fino a 4. Un rimbalzo vale come una sponda.
- **Il giro del giorno:** 18 buche, ognuna chiede da 0 a 5 sponde, uguali per tutto il giorno; dalla buca 6 ci sono gli ostacoli e la palla parte da un punto a caso. Dopo 4 tiri a vuoto compare «gioca classico».
- **Tiri leggeri:** la forza cresce col quadrato del trascinamento, la piena arriva a 240 punti.
- **Palla ripresa mentre rallenta:** sotto un quinto della velocità del tiro (e sotto 80 punti al secondo) premerla fa partire un tiro nuovo da lì.
- **La striscia** in fondo al pannello ha un menu ⋯: sposta in alto o in basso, nascondi.
- **Ace finte corrette:** con un tiro forte la palla attraversava la buca al primo passo e valeva hole in one.
- **La card del minigolf** in Analytics è rifatta nello stile del campo, più corta, con i dettagli dietro i chip.
- **I giorni del minigolf** (`GolfDay`): uno al giorno, uguale per tutto il giorno, segnato da un'emoji nella striscia e spiegato nel suo menu ⋯:
  - 🌈 pallina arcobaleno: gira, saltella, lascia la scia e rimbalza di più;
  - 🌬️ vento: una direzione del giorno, curva i tiri;
  - 🧲 buca calamita;
  - 🕳️ buca XXL;
  - 🔄 fionda al contrario;
  - 📐 mira del caddie: mentre tiri vedi la strada della pallina, fino al secondo rimbalzo;
  - 🌀 portali: due, blu e arancione; la pallina entra in uno ed esce dall'altro con la stessa spinta;
  - 🕹️ Pac-Man: i lati sinistro e destro sono aperti, la pallina esce da una parte e rientra dall'altra;
  - 🙈 buca timida: quando la pallina le arriva vicino, la buca si scansa di lato una volta per tiro, con un «Ops!»;
  - ⛳ giorno classico.

  Sono tutti numeri letti a inizio partita: a riposo non gira niente.
- **Mira con i rimbalzi:** nel menu ⋯ della striscia si accende per tutti i giorni (spenta di partenza: rende facili gli hole in one).

## Prestazioni

Misure fatte su un Mac con macOS 26.4:

| | prima | Yako |
|---|---|---|
| CPU del widget, a riposo | 2–7,7% | 0,0–0,2% |
| Memoria del widget | ~27 MB | ~20–30 MB |
| Hook a ogni prompt | 0,17 s | ~0,13 s |

- La tendina chiusa non si ricalcola. Il pannello nascosto o coperto da finestre va in pausa su una copia ferma della lista, e le partite di minigolf restano.
- Il pannello si ridimensiona solo quando cambia davvero il contenuto.
- L'orologio batte ogni secondo solo se un task è in corso, altrimenti ogni 15 secondi.
- I file live e le sessioni dell'app si rileggono solo se sono cambiati. Le icone della barra dei menu si creano una volta sola.
- Animazioni, fisica del minigolf e motore audio girano solo mentre servono.
- Nell'hook, `guess_category` cerca le parole chiave in un insieme di prefissi invece di scorrere ogni parola: 4 volte più veloce, con le stesse categorie su tutti i task dell'indice.
- Pulizia profonda (dopo la v2.7, `docs/pulizia.md`): 130 righe in meno tra codice morto e doppioni, l'app fa le stesse cose (pannello e Touch Bar disegnati identici). Touch Bar e server dell'iPhone ora leggono l'indice una volta sola invece di due, e ogni regola del gioco (livelli, giro da 18, 70%, punteggio sul par, serie, esito) sta in un posto solo.

## Bug corretti

- Una sessione cancellata nell'app restava "in corso" all'infinito e faceva correre il tempo. Ora un task il cui transcript non esiste più sparisce dalla lista dopo due minuti.
- I clic veloci sul pallino andavano persi (macOS li tratta come doppi e tripli clic) e il conteggio ripartiva a ogni riavvio.

## Compilare, installare, provare

```bash
./widget/build.sh
./widget/build/TaskETA.app/Contents/MacOS/TaskETA --selftest
python3 -m unittest discover -s tests
```

Per installarla, chiudi la TaskETA in esecuzione, copia `widget/build/TaskETA.app` in `~/Applications` e aprila.

**Anteprime**, con `TaskETA.app/Contents/MacOS/TaskETA`:
- `--snapshot file.png [--dark]` disegna il pannello. Con `--demo` usa task di esempio; con `--celebrate` mostra le quattro animazioni; con `--burst` i 69 pallini; con `--compact` il pannello corto; con `--holeinone N` la festa di una buca con N sponde; con `--dino S` il dinosauro dopo S secondi (2 per "Coming soon", 4 per il retro del cartello).
- `--dashboard-snapshot file.png [--dark]` disegna la dashboard con l'indice vero.
- Con `TASKETA_LANG=en` o `TASKETA_LANG=it` davanti, le anteprime escono in quella lingua.
- `--cheer N` fa sentire l'esultanza di una buca con N sponde (0–3).
- `--touchbar-snapshot file.png` disegna la Touch Bar; `--touchbar-demo` fa girare gli stati sulla Touch Bar vera dell'app aperta per un minuto.
- `--course-report` dice a che buca sei nel campo, con ogni prova e il suo perché.
- `--phone-script` scrive lo script del widget iPhone in iCloud Drive > Scriptable.

**Interruttori per l'app in esecuzione**:
- `TASKETA_DEBUG_REGULAR=1`: icona nel Dock, così gli strumenti che vedono solo le app normali possono fotografarla.
- `TASKETA_DEBUG_CELEBRATE=1`: le quattro animazioni ogni 5 secondi.
- `TASKETA_DEBUG_TOAST=1`: un avviso di ogni tipo all'avvio.
- `TASKETA_DEBUG_GOLF=1`: minigolf sbloccato senza salvarlo, e partite di esempio nella dashboard.
- `TASKETA_DEBUG_GEMS=1`: una giornata di gemme di esempio nella dashboard.
- `TASKETA_DEBUG_FIELD=ghiaccio` (o `biliardo`): il minigolf su quel campo, senza averlo vinto.
- `TASKETA_DEBUG_COMBO=N`: il gioco libero come con N hole in one di fila (gli ostacoli da 5).
- `TASKETA_DEBUG_HOLE=N`: ogni partita è la buca N del giro del giorno, senza scriverla.
- `TASKETA_DEBUG_DASH=…` (separati da virgole) per `--dashboard-snapshot`: `edit`, `all` (anche i widget nascosti), `min`/`max`, `demo`, `halfway`, `editors`, `cards` (le card del gioco intere sotto la griglia), `faro-oro` (il faro su quel minerale), `faro-x10`.
- `TASKETA_DEBUG_DIR=cartella`: scrive lo stato e le catture lì, 4 volte al secondo.

## Fuori dal repo

Le skill `tasketa-gioco` e `yako-touch` e il task programmato dell'analisi del lunedì vivono nelle cartelle di Claude sul Mac. In `extras/` c'è una copia di ciascuno, con le istruzioni per riattivarli (`extras/README.md`).
