# Il campo: il gioco delle stime a livelli

Proposta di progetto, 24 ottobre 2026. Una parte è costruita nella v2.7 (24 ottobre sera): le sezioni fatte hanno il segno **[costruito, v2.7]**, e cosa c'è nell'app, versione per versione, è in `YAKO.md`. Il resto è la struttura, da fare un pezzo alla volta. La skill `/tasketa-gioco` la ricorda, dice a che buca sei e aggiorna la mappa.

Legenda: **[c'è già]** esisteva già prima del campo · **[cambia]** esiste ma cambia · **[nuovo]** da fare · **[costruito, v2.7]** fatto nella v2.7.

## L'idea in cinque righe

- Ogni task con la stima di Claude è un colpo, come oggi. **[c'è già]**
- I **punti** ti portano fino al green della buca. Le **prove** mettono la palla in buca. **[nuovo]**
- Ogni buca chiusa ti dà un **potere**: qualcosa che cambia come si gioca o come si vede. **[nuovo]**
- Le **buche fatte** aprono campi nuovi nel minigolf: il ghiaccio a 200, il biliardo a 888. **[nuovo]**
- **Serve a qualcosa**: a scrivere prompt migliori, a restare al Mac mentre Claude lavora e a capire ogni risultato. **[nuovo]**

I punti misurano quanto giochi, le prove quanto giochi bene. Così con 50 o 90 buche al giorno non si sale solo di quantità: per andare avanti servono stime più affidabili.

## Cosa resta com'è [c'è già]

| Esito della stima | Buca | Gemma | Punti |
|---|---|---|---|
| entro l'8% della stima | Hole in one | diamante | 300 |
| più veloce della forchetta | Birdie | zaffiro | 150 |
| dentro la forchetta | Par | smeraldo | 100 |
| oltre la forchetta | Bogey | sasso | 0 |

- +25 punti per ogni gemma di fila prima, fino a +250.
- Giri da 18 buche. Il giro contro il par come nella Touch Bar: hole in one −2, birdie −1, par 0, bogey +1.
- I nove nomi dei livelli, da Principiante a Leggenda del green: diventano le nove buche del campo.
- Il minigolf dietro il pallino, con par 3, punti, serie, sfida e traguardi.

## Il campo: 9 buche in 3 zone

Il titolo che hai è il nome dell'ultima buca chiusa. Le prove valgono quando le fai, anche prima di arrivare a quella buca: una prova fatta resta fatta.

Due parole nuove:
- **disastro**: un task che dura più di 5 volte la sua stima (stima 2 min, reale oltre 10);
- **al 70%**: una giornata con almeno il 70% di gemme, il "fine" che la dashboard mostra già.

### Il Pratone dei Gardens: una prova per buca (il primo giorno)

| Buca | Green a | Prova | Potere |
|---|---|---|---|
| 1 · Principiante | 0 | chiudi il primo giro da 18 buche | **Fairway**, stile del widget |
| 2 · Caddie | 4.000 | 5 gemme di fila | **Il consiglio del caddie** |
| 3 · Dilettante | 10.000 | vinci una sfida del giro | **Mulligan** |

### Trump Lake: due prove per buca (qualche giorno)

| Buca | Green a | Prove | Potere |
|---|---|---|---|
| 4 · Handicap 18 | 20.000 | 10 gemme di fila · un giro con 3 bogey o meno | **Mazza forte**, nel minigolf |
| 5 · Handicap 9 | 40.000 | 3 giorni di fila al 70% · un giro senza bogey sui quick | **Golf di notte**, stile del widget |
| 6 · Scratch | 75.000 | 15 gemme di fila · un giro senza disastri | **Buca doppia** |

### Monte Donato: tre prove per buca (settimane, e un'abitudine nuova)

| Buca | Green a | Prove | Potere |
|---|---|---|---|
| 7 · Pro | 125.000 | 20 gemme di fila · 5 giorni di fila al 70% · un giro con 1 bogey o meno | **Trofeo**, stile del widget |
| 8 · Campione | 200.000 | 10 gemme di fila sui medium · un giro a −15 o meglio · 2 giri di fila senza disastri | **Eagle** |
| 9 · Leggenda del green | 300.000 | 25 gemme di fila · un giro senza bogey · 20 giorni al 70% in un mese | **Giacca verde** e **Stagione 2** |

Le soglie dei punti sono quelle dei livelli di oggi **[c'è già]**. Prove e poteri sono **[nuovo]**.

## I poteri del campo

| Potere | Tipo | Cosa fa | Cosa tocca nel codice |
|---|---|---|---|
| Fairway | widget **[cambia]** | Il widget dell'iPhone in verde prato. Oggi si vince a 10.000 punti. | `WidgetTheme.isUnlocked` (Gems.swift); lo stile scelto va in `/status` (PhoneServer.swift) e lo legge `TaskETA.js` |
| Il consiglio del caddie | aiuto **[nuovo]** | A ogni nuovo giro, una riga nel pannello e nel widget: «se servono più di 3 strumenti, chiedi medium». Il testo esiste già nella dashboard ("Cosa ti dicono adesso") e nell'analisi del lunedì: cambia dove si vede. | `GemsGuide.reading` (Gems.swift) riusato; un campo in `PhoneGame`; una riga nel pannello (Views.swift) |
| Mulligan | stime **[nuovo]** | Una volta al giorno il primo bogey non rompe la serie. Si usa da solo, e solo se la serie è almeno di 3. Il sasso resta un sasso (0 punti). | il ciclo della serie in `GemStats.init` (Gems.swift) |
| Mazza forte | minigolf **[nuovo]** | Tiri più lunghi: la pallina parte più forte e fa più sponde, che valgono 50 punti l'una. Vale su tutti i campi del minigolf. | `Golf.maxSpeed` 1500 → 2100 (dalla v2.8 la forza cresce col quadrato del trascinamento, piena a 240 punti); i colori della linea di tiro si misurano sul nuovo massimo (`power` in `draw`) |
| Golf di notte | widget **[cambia]** | Il widget notturno, con le gemme che brillano. Oggi si vince con 10 gemme di fila. | come Fairway |
| Buca doppia | stime **[nuovo]** | In ogni giro una buca vale doppio. Si sa dall'inizio del giro quale («la 7 vale doppio»), uguale su Mac, iPhone e Touch Bar. | i punti in `GemStats.init`; il numero della buca ricavato da giorno e giro, niente di salvato |
| Trofeo | widget **[cambia]** | Il widget oro. Oggi si vince a 40.000 punti. | come Fairway |
| Eagle | stime **[nuovo]** | Un diamante su un task medium o long vale 500 punti invece di 300. È raro: 5 su 149 buche finora. | `Gem` e i punti in `GemStats.init`; serve `kind_declared` in `PastTask` |
| Giacca verde | aspetto **[nuovo]** | Tutta l'app in verde e oro, e la bacheca della stagione nella dashboard. Apre la Stagione 2. | solo colori (`Pace`, `Gem.tones`) e la dashboard |

**Gli stili non si scrivono più nel Parameter.** Nella dashboard si sceglie lo stile con un clic e l'app lo manda al widget insieme ai dati di `/status`. Il Parameter resta solo per chi vuole due widget con stili diversi. È la risposta al riquadro "Stili del widget iPhone" che oggi non si capisce: un potere vinto funziona da solo, uno da vincere dice quale buca lo dà.

## Il minigolf: mazza, ghiaccio e biliardo [costruito, v2.7]

Costruito nella v2.7 in `GolfRules.swift`: cosa fa oggi è in `YAKO.md`, sezione «Il gioco a livelli». Sotto, il progetto com'era.

Il minigolf segreto diventa il premio delle stime: più buche fai con le stime, più campi si aprono nel minigolf, per sempre.

**Buche fatte** vuol dire tutti i task con la stima, anche i bogey: oggi 149. Non si spende niente e non si salva niente: il numero viene dall'indice di task-eta, come le gemme.

| Campo | Si apre | Cosa cambia | Cosa tocca in Golf.swift |
|---|---|---|---|
| Prato **[c'è già]** | subito | il minigolf di oggi | forza col quadrato del trascinamento (piena a 240 punti, v2.8), `maxSpeed` 1500, `friction` 0,55, `restitution` 0,8, stop sotto 12 pt/s, `holeRadius` 14, una buca dove c'era il pallino |
| Campo ghiacciato | 200 buche fatte | la pallina scivola: rallenta pochissimo, rimbalza di più, si ferma tardi. Se passa sulla buca troppo veloce ci salta sopra | `friction` 0,55 → 0,85; `restitution` 0,8 → 0,9; stop 12 → 5 pt/s; nuovo `captureSpeed` 900 (sopra, niente buca); colore della pallina e del fondo |
| Biliardo | 888 buche fatte | sei buche, ai quattro angoli e a metà dei lati lunghi; conta solo di sponda | `restitution` 0,8 → 0,92; `friction` 0,55 → 0,6; `holeRadius` 14 → 11 con 6 buche invece di una; nuovo `cushionsNeeded` 1; colore panno |

La **mazza forte** (buca 4 del campo) si somma a qualsiasi campo. Se "10 buche di fila senza sbagliarne una" vuol dire 10 buche di fila al minigolf invece che 10 gemme di fila, cambia una riga sola.

Il campo si sceglie prima del primo tiro con un clic sul nome del campo, nel riquadro in fondo alla lista che già mostra record, serie e sfida.

**Leggero, sempre** (l'app gira sempre in background):
- Ogni potere è un numero, letto quando parte una partita o quando apri la dashboard: nessun timer, nessuna animazione in più a riposo, nessuna immagine o suono nuovo.
- Il timer a 60 al secondo del minigolf gira solo mentre la pallina si muove, come oggi. Sul ghiaccio la pallina corre più a lungo, quindi il timer resta acceso qualche secondo in più, e basta.
- Il biliardo fa 6 controlli di distanza a passo invece di 1: niente di misurabile.
- Le costanti di `Golf` (oggi `static let`) diventano un piccolo insieme di regole, `GolfRules`, scelto all'inizio della partita e passato a `Golf.advance`.
- Buche fatte e mazza forte vengono dall'indice di task-eta: si leggono con la cache che la Touch Bar usa già (`gemStats()`, ricaricata solo quando l'indice cambia), da spostare in un posto comune.

## A cosa serve davvero [nuovo]

Nick, 24 ottobre: il gioco deve avere un uso funzionale. Deve motivare a migliorare i prompt e a lavorare di più, ma soprattutto a restare concreti al Mac invece di alzarsi mentre Claude lavora, con contenuti brevi. E ogni risultato va spiegato e motivato.

### 1. Mentre Claude lavora: cosa fare, secondo quanto dura

La stima arriva all'inizio di ogni risposta, quindi l'app sa subito quanto durerà l'attesa. Nel pannello, sotto la riga del task, compare **una riga sola** con cosa fare, scelta dalla stima. Nella Touch Bar compare la stessa riga, solo testo.

I numeri veri delle 165 buche fino al 24 ottobre (durate reali; la riga si sceglie dalla stima):

| Attesa | Quante buche | Quanto tempo in tutto | Cosa propone |
|---|---|---|---|
| meno di 1 minuto | 36% | 4% | niente da fare: il risultato arriva prima. Al massimo un tiro al volo nel minigolf |
| 1–5 minuti | 32% | 14% | **una buca**: un tiro di minigolf con la sfida del momento, oppure **il consiglio da 30 secondi** sui tuoi prompt |
| 5–15 minuti | 26% | 47% | **prepara il prossimo prompt**, o avvialo in un'altra sessione; se vuoi staccare, un giro corto da 3 buche |
| oltre 15 minuti | 7% | 35% | **il giro lungo**: il minigolf intero o l'analisi della settimana. L'app ti chiama quando ha finito |

Le attese lunghe sono poche ma fanno l'82% del tempo passato ad aspettare: lì si decide se resti al Mac.

Cosa si conta, con il suo perché:
- **Doomscrolling evitato** **[c'è già nella dashboard]**: i minuti di minigolf giocati mentre Claude lavorava (questa settimana 10 minuti in 32 partite). Il perché: «tempo passato al Mac invece che al telefono».
- **Ripartenza pronta** **[nuovo]**: il prossimo prompt nella stessa sessione entro un minuto dalla fine. Oggi succede nel 36% dei casi, entro 5 minuti nel 75%. Il perché: «eri lì quando Claude ha finito». È solo un numero, senza punti, per non premiare i prompt scritti di corsa.

### 2. Le abitudini di prompt che contano

Prima di premiare un'abitudine ho guardato se nei tuoi dati cambia davvero le stime. Due la cambiano molto, le altre no:

| Abitudine | Nei tuoi dati | Conta? |
|---|---|---|
| **Un turno solo**: il task va dall'inizio alla fine senza fermarsi e ripartire (niente messaggi aggiunti a metà, niente domande di ritorno) | bogey nel 19% dei casi; quando si ferma e riparte, nel 58% (1 task su 5) | sì |
| **Del suo tipo**: un quick resta entro 3 strumenti, un medium entro 15, come dice il ⏱ | quick entro 3 strumenti: bogey nel 9%; quick oltre 3: nel 58% | sì |
| Niente prompt da una parola («ok», «vai») | solo il 4% delle buche, 2 bogey su 7 | no, solo un consiglio |
| Un percorso, un link o un'immagine nel prompt | nessuna differenza (pochi casi) | no |
| Lavorare di notte | 25% di bogey di notte, 27% di giorno | no |

**Colpo pulito** **[nuovo]**: una buca con un turno solo e rimasta del suo tipo. Oggi sono il 63% delle buche. Finiscono in bogey nel 10% dei casi, contro il 54% delle altre.
- Vale **+25 punti**, circa il 9% dei punti di una giornata.
- Entra nella lista delle sfide del giro: «6 colpi puliti».
- Nel pannello, alla fine del task, il timbro dice «colpo pulito» o perché non lo è.

**Il consiglio da 30 secondi** **[nuovo]**: una frase presa dai tuoi ultimi giri, mai generica. Per esempio: «Oggi 3 task si sono fermati e ripartiti: 2 sono finiti in sasso. Se ti viene in mente altro mentre Claude lavora, mandalo dopo come prompt nuovo.»

### 3. Ogni risultato ha il suo perché

Ogni cosa che l'app mostra porta **una riga con il perché e una con cosa fare**. Le scrive una piccola serie di regole, in ordine, con i dati che l'indice ha già: niente intelligenza artificiale mentre giri, niente costo.

| Risultato | Perché | Cosa fare |
|---|---|---|
| sasso, task fermato e ripartito | «Si è fermato e ripartito 3 volte: la stima era per un turno solo.» | «Scrivi tutto all'inizio; il resto mandalo dopo, come prompt nuovo.» |
| sasso, quick con troppi strumenti | «Era un quick, ha usato 25 strumenti: chiedevi più di quanto sembrava.» | «Una cosa per volta, o di' che è un lavoro medio.» |
| sasso da disastro | «22 minuti invece di 30 secondi: 44 volte la stima.» | «Spezza il lavoro in passi più piccoli.» |
| altro sasso | «4 minuti oltre la forchetta. In my-app succede spesso.» | «Lì dai più contesto nel prompt.» |
| diamante | «Stima centrata: 5:10 contro 5:00. Colpo pulito.» | «Così: una richiesta, tutta all'inizio.» |
| zaffiro | «Finito prima: Claude si è tenuto largo.» | «Puoi chiedere di più in una volta.» |
| buca chiusa | «3 giorni di fila al 70% di gemme.» | «Vuol dire che puoi pianificare la giornata con le stime.» |
| potere, sfida, campo del minigolf | cosa l'ha dato | cosa cambia da adesso |

Dove si legge:
- nel timbro di fine task del pannello, sotto l'esito;
- nell'avviso;
- nello storico della dashboard;
- nella riga dell'ultima buca del widget.

Nella Touch Bar resta il solo nome della buca, perché non c'è spazio.

**Leggero**: la riga dell'attesa si sceglie una volta, quando arriva la stima. Il perché si calcola una volta, quando il task finisce. Nessun timer in più, niente che giri a vuoto.

## Anche Claude gioca [costruito, v2.7]

Costruito nella v2.7, con una differenza dal progetto: la riga nell'hook è accesa di base. `task_eta.py score` la mostra, `score off` la spegne e `score on` la riaccende (anche `TASK_ETA_SCORE=off`). Nell'app il punteggio è `ClaudeScore` in `CampoEngine.swift`. Sotto, il progetto com'era.

Nick, 24 ottobre: le gemme sono anche un gioco per l'AI. Le gemme danno un voto alle stime ⏱ di Claude, quindi il giocatore vero è Claude quanto Nick.

### Perché

- **La stima è un'abilità di Claude.** Il numero viene dal modello di task-eta, cioè dai tempi veri delle sessioni di Nick. Ma è Claude a scegliere il tipo di lavoro (quick, medium, long), ed è Claude a fare il lavoro.
- **Oggi Claude riceve già metà del riscontro.** Il blocco `[task-eta]` che l'hook aggiunge a ogni prompt dice se il tipo dichiarato era giusto: «110 volte su 148, 30 volte più piccolo del vero». Manca il risultato, cioè quante stime sono finite dentro la forchetta.
- **Una riga in più chiude il cerchio.** È come un tabellone: Claude vede come sta andando e si tara.

### Il punteggio di Claude è diverso da quello di Nick

Le buche sono le stesse, ma si leggono in due modi:

| Esito | Per Nick | Per Claude |
|---|---|---|
| entro l'8% | diamante, 300 | centrata |
| dentro la forchetta | smeraldo, 100 | dentro |
| più veloce della forchetta | zaffiro, 150: una buona notizia | **troppo lunga**: stima prudente, conta come errore |
| oltre la forchetta | sasso, 0 | **troppo corta**: errore |

Il motivo: se lo zaffiro valesse anche per Claude, gli converrebbe dichiarare sempre un tipo più grande. Così finirebbe sempre prima e non sbaglierebbe mai. Per tararsi, anche essere troppo prudenti è un errore.

I numeri veri, 167 stime fino al 24 ottobre:
- **in tutto**: 62% dentro la forchetta, 26% troppo corte, 12% troppo lunghe. Claude sottostima due volte più spesso di quanto sovrastimi;
- **ultime 18**: 12 dentro, di cui 8 centrate; 5 troppo corte, 1 troppo lunga;
- **record**: 15 su 18; serie di stime dentro: 4, il record è 9;
- **sta migliorando**: nella prima metà delle stime il 55% era dentro, nella seconda il 69%.

### La riga che Claude leggerebbe [cambia nell'hook]

Nel blocco `[task-eta]`, sotto la riga sul tipo dichiarato. In inglese, come il resto del blocco:

> Your score: last 18 estimates 12 inside the range (8 hit), 5 too short, 1 too long; streak 4, best 15 of 18. It scores the estimate, not the work: never change the work to hit it.

### Le regole che lo tengono onesto

Quando un numero diventa un obiettivo, si trova il modo di vincere senza migliorare. Per evitarlo:
- **La forchetta è quella dell'hook**, non quella che Claude scrive: Claude non può allargarla. Oggi è larga in media 3 volte (per esempio da 1 a 3 minuti). Se l'hook la stringe, il record riparte.
- **Troppo lunga è un errore**: dichiarare sempre un tipo più grande non paga.
- **Centrata solo entro l'8%** (o 10 secondi), come oggi.
- **Si misura la stima, non il lavoro**, e la riga lo scrive in chiaro: Claude non rallenta e non taglia per centrare.
- **Contano solo i task con la stima.** Quelli senza interfaccia e i task di prova restano fuori, come oggi.

### Nick e Claude giocano la stessa partita

Nick gioca con prompt più chiari: un turno solo, una cosa per volta, cioè i colpi puliti. Claude gioca con stime più giuste. Il gioco è uno solo e i due punteggi stanno vicini:
- Nick vede quello di Claude nella dashboard e sulla mappa, nel segnapunti di Claude;
- Claude vede il suo nel blocco dell'hook.

### Costo e limiti

- **Costo**: una riga, circa 40 token a prompt, e niente quando il gioco è spento. Un interruttore lo spegne, e resta spento finché Nick non lo accende.
- **Effetto**: non cambia mai il lavoro, solo la stima.
- **Niente in più**: nessuna chiamata e nessun file nuovo, perché i numeri vengono dall'indice che l'hook legge già.

### Cosa dà

- **Il record «Claude contro Claude»**: la serie migliore di 18 stime dentro la forchetta, oggi 15.
- **Una riga nell'analisi del lunedì**, per esempio: «Le stime di Claude sono finite dentro la forchetta nel 69% dei casi, 14 punti più della settimana prima.»
- **Un agente che gioca**, nello spirito Yako Touch, e lo si vede.

### Cosa cambia nel codice, quando si costruirà

- `task_eta.py`: una funzione che calcola il punteggio dalle ultime 18 stime (dentro, centrate, corte, lunghe, serie, record), una riga in più nel blocco `[task-eta]` e un interruttore per spegnerla.
- `tests/`: un test con stime di prova.
- `widget/insights/export.py`: il punteggio della settimana e di quella prima, per l'analista.

### Primi passi

1. La funzione del punteggio in `task_eta.py`, con il suo test, senza toccare il blocco.
2. La riga nel blocco, dietro l'interruttore e spenta di base. Si contano i token e si prova una settimana.
3. Lo stesso punteggio nella dashboard accanto alle gemme, nel segnapunti della mappa e nell'analisi del lunedì.

## La sfida del giro [cambia]

Oggi c'è una sfida al giorno («500 punti», «centra 2 stime»), pensata per poche buche: con 50 buche al giorno la vinci a metà mattina. Diventa **una sfida per ogni giro da 18**, presa a caso da questa lista: 5 diamanti, 8 gemme di fila, 3 bogey o meno, nessun disastro, un birdie su un medium, −6 nel giro, 6 colpi puliti. Vale 500 punti. Sono 3–5 sfide al giorno, ognuna con un esito chiaro alla fine del giro.

## Equilibrio con circa 50 buche al giorno

I numeri veri, dal 23 al 24 ottobre (le stime partono il 23):
- 149 buche, 55 il primo giorno e 94 il secondo;
- 26.375 punti, in media circa 180 punti a buca, quindi circa 9.000 punti con 50 buche;
- 74% di gemme: 34 diamanti, 19 zaffiri, 58 smeraldi, 38 sassi;
- 4–5 bogey in un giro (il migliore: 2), giro contro il par di solito tra −2 e −13;
- in ogni giro completo c'è almeno un disastro (il migliore: 5,4 volte la stima);
- serie migliore 14; sui medium 5;
- i quick finiscono in bogey 27 volte su 100, i medium 32, i long 14.

Cosa ne segue:
- **I punti aprono i green in fretta**: 40.000 in 4 giorni, 75.000 in una settimana, 300.000 in circa 5 settimane. Dopo la buca 5 a fermarti sono le prove, non i punti, ed è voluto.
- **Le prove salgono di un gradino per zona.** Il Pratone dei Gardens si chiude il primo giorno. Trump Lake chiede una giornata buona o qualche giorno di fila. Monte Donato chiede un'abitudine nuova, come spezzare i task o dichiarare medium quando servono più di 3 strumenti. Con il 74% di gemme di oggi, 20 di fila arrivano in qualche settimana; 25 di fila e un giro senza bogey chiedono di salire verso l'85%. Per questo si chiama Leggenda.
- **I poteri delle stime restano piccoli.** Buca doppia vale circa il 4% dei punti di una giornata, Eagle il 3–4%, Mulligan fino al 10% (salva una serie). Tutti insieme meno del 20%: il gioco cambia, la classifica no. Il colpo pulito aggiunge circa il 9%, ma premia proprio l'abitudine che fa le gemme.
- **I campi del minigolf**: con 50 buche al giorno il ghiaccio arriva il quarto giorno e il biliardo dopo circa 18 giorni. Tu sei a 149: il ghiaccio è a 51 buche, circa un giorno.
- **Niente punti dal nulla.** Contano solo i task con la stima, come oggi. Fare tanti task piccoli dà punti, ma non chiude le prove: sono quote, serie e giri, non quantità.
- **Durata**: un campo è una stagione, circa tre mesi se le stime migliorano.

## Dove si vede

**Dashboard** **[cambia]**
- Il riquadro "Stili del widget iPhone" diventa **"Il campo"**: una striscia con le 9 bandierine (chiuse, quella di adesso, quelle da fare).
- Sotto, la buca di adesso: la barra dei punti verso il green e le prove con il loro avanzamento («2 di 3 giorni»).
- Il prossimo potere, con una riga su cosa fa.
- I poteri vinti: gli stili si scelgono con un clic; quelli di gioco dicono cosa hanno fatto oggi («Mulligan usato alle 11:20, serie salvata a 7»).
- Nella parte del minigolf: le buche fatte e quante ne mancano al prossimo campo.
- «Apri la mappa» apre il campo intero, come nella mappa di questa proposta.

**Minigolf** **[cambia]**: nel riquadro in fondo alla lista, durante la partita, il campo su cui giochi («Ghiaccio»); un clic sul nome lo cambia prima del primo tiro.

**Widget iPhone** **[cambia]**
- Piccolo: «Buca 5» e il cerchio della prova più vicina.
- Medio e grande: il giro di gemme (c'è già), la buca di adesso con la prova più vicina, il consiglio del caddie e il ×2 sulla casella della buca doppia.
- Blocco schermo: resta com'è, il tempo prima di tutto.
- Lo stile arriva dalla scelta fatta nella dashboard.

**Touch Bar** **[cambia, sobria]**
- Solo testo, niente gemme né diamanti.
- Il pulsante della Control Strip resta com'è. Quando chiudi una buca del campo, per 6 secondi «Buca 5 chiusa». Quando il Mulligan salva la serie, «Mulligan».
- Nella Touch Bar aperta il giro diventa «Giro 6 · 8/18 · −3 · la 12 vale doppio».

**Avvisi** **[nuovo]**: uno quando chiudi una buca («Buca 5 chiusa: nuovo potere, Golf di notte») e uno quando si apre un campo del minigolf («Campo ghiacciato aperto»). Un clic apre la dashboard.

## La mappa dentro Analytics [costruito, v2.7]

Nick, 24 ottobre: la mappa va messa anche dentro "Analytics dei task", e tutta la parte del minigolf di Analytics va rifatta nello stile della mappa.

### Com'è stato costruito

- **La pagina**: `widget/campo/il-campo.html`, uguale byte per byte a `templates/il-campo.html` della skill. I font Barlow (licenza OFL) sono in `widget/campo/fonts/`, e `build.sh` copia la cartella in `Resources`.
  - Senza `window.CAMPO_DATA` è la mappa pubblicata, con i suoi numeri.
  - Con `CAMPO_DATA` usa i font locali e la modalità `embed`: niente scroll, intestazione corta. A riposo niente si muove: acqua, bandiera e luce del pollaio solo con il puntatore sopra.
  - Corretti due difetti della prima mappa, anche in quella pubblicata: le schede ora si aprono accanto alla buca (`placePop`) e la scheda vuota non si vede più (`.pop[hidden]`).
- **Il widget**: «Il campo», 4×4 o 4×5, in `DashboardGrid.swift`. `Campo.swift` prepara i numeri (`CampoData`, cioè `window.CAMPO_DATA`) e la vista: un `WKWebView` che esiste solo con Analytics aperta. I link vanno nel browser, la rotella passa alla dashboard.
- **Lo stile**: `CampoStyle.swift`, con i colori della tabella qui sotto e Barlow. `MinigolfCard` e `GemsCard` sono rifatte (score card, i tre campi con il lucchetto, targhette di legno, niente emoji); la card del gioco è stata poi accorciata (vedi «La card corta»).
- **Memoria misurata**: a riposo 28–33 MB e nessun processo WebKit. Con la mappa aperta circa 85 MB in più, misurati sul web view fuori schermo. Alla chiusura la pagina si libera in 2 secondi, la parte grafica entro un minuto.
- **Da provare a mano**, perché la sessione non ha potuto aprire l'app: le schede in Analytics, il link @yakonft, la rotella sopra la mappa, il trascinamento del widget in «Modifica», la memoria con Analytics aperta e poi chiusa.

Sotto, il progetto com'era.

### La mappa come widget della griglia

- **Dove**: un widget "Il campo" nella griglia di Analytics (`DashboardGrid.swift`: `DashLayout`, `DashWidgetView`), largo tutta la riga, in proporzione 1200 × 720.
- **Una fonte sola**: lo stesso file della mappa pubblicata. Il sorgente è `templates/il-campo.html` della skill `tasketa-gioco`; nella repo andrebbe copiato, per esempio in `widget/campo/il-campo.html`.
  - `build.sh` lo copia in `Contents/Resources`, come fa già con `TaskETA.js`.
  - L'app lo mostra in un `WKWebView`.
- **I numeri vengono dall'app**: nell'HTML, `DATA` si legge da `window.CAMPO_DATA` quando c'è. L'app lo riempie con i suoi numeri (`GemStats`, poi `Course`) prima di caricare la pagina. Così la mappa in Analytics è sempre aggiornata, senza la skill.
- **Font senza internet**: Barlow ha una licenza libera (OFL). I due file `.ttf` vanno in `Resources` e la pagina li carica con `@font-face`, con percorso relativo, usando `loadFileURL(_:allowingReadAccessTo:)`. Se mancano, resta il font di sistema.
- **Link**: il link a @yakonft si apre nel browser (`WKNavigationDelegate` → `NSWorkspace.open`). Più avanti gli edifici potranno portare ai widget di Analytics, per esempio la bacheca alle gemme, con `window.webkit.messageHandlers`.
- **Leggero**:
  - il `WKWebView` esiste solo mentre Analytics è aperta e il widget si vede, e si libera alla chiusura, come l'indice oggi;
  - le animazioni (acqua, bandiera, luce del pollaio) sono CSS e si fermano quando la finestra è nascosta;
  - il giro del monopattino parte una volta sola;
  - va misurata la memoria con Analytics aperta e chiusa.
- **Alternativa nativa**: ridisegnare il parco in un `Canvas` di SwiftUI, perché i tracciati sono già numeri nei `<defs>`. È più leggera, ma poi i disegni da tenere allineati sono due. Meglio partire dal `WKWebView`.

### Il minigolf di Analytics nello stile della mappa

Da rifare: `MinigolfCard` (`Dashboard.swift`) e `GemsCard` (`Gems.swift`). I colori e i font si mettono in un `CampoStyle` comune, chiaro e scuro, e lo scuro è il golf di notte.

| Elemento | Chiaro | Golf di notte |
|---|---|---|
| prato (fondo) | `#cfe3bd` | `#1c3223` |
| corsia | `#3f8a4f` | `#3f8a4f` |
| bordo corsia | `#f1f6e6` | `#2d4a34` |
| vialetto | `#eadfc4` | `#3d3b2f` |
| lago | `#8cc8dc` | `#1f4d5c` |
| ghiaccio | `#eef7fc` → `#c4e1f0` | uguale |
| feltro, sponda | `#1d6a48`, `#7a5232` | uguali |
| bandiera, accento | `#d1452e` | `#f06a50` |
| fatto | `#2f7140` | `#82d191` |
| testo, secondario | `#16241b`, `#56665b` | `#e4ede5`, `#9bb0a2` |

- **Font**: Barlow Semi Condensed 600–700 per titoli e numeri, Barlow per il testo, con le cifre tabulari.
- **Il minigolf diventa il prato del circolo**:
  - in testa un piccolo green disegnato, con la bandierina;
  - i tre campi (prato, ghiaccio, biliardo) come i riquadri della mappa, con le buche fatte («158 di 200») e il lucchetto;
  - i traguardi come targhette di legno;
  - le 5 migliori partite come uno score card da golf (buca, tiri, sponde, punti).
- **Ogni numero con il suo perché**, come nel resto del gioco.
- **Sobrio**: niente emoji per decorare. La Touch Bar resta com'è.

### Primi passi

1. In `build.sh`, copiare in `Resources` la mappa e i due font Barlow; nell'HTML, leggere `DATA` da `window.CAMPO_DATA`.
2. Il widget "Il campo", con il `WKWebView` che la carica e la riempie dai numeri dell'app. Esiste solo con Analytics aperta; misurare la memoria.
3. `CampoStyle`, poi `MinigolfCard` e `GemsCard` rifatte: lo score card e i tre campi.

## Il mood del gioco [costruito, v2.7]

Nick, 24 ottobre: «qui non si capisce il mood delle gemme… perché diamanti, che c'entrano con le buche?». E poi: «che uno può modificare il mood in quello che preferisce; ora sono due ma in futuro possono essere altri».

Le regole restano le stesse: cambiano solo i nomi e i segni dei risultati.

| | Minigolf (di partenza) | Gemme |
|---|---|---|
| stima centrata | **Hole in one**: disco pieno verde dentro un anello | diamante |
| più veloce della forchetta | **Birdie**: cerchio | zaffiro |
| dentro la forchetta | **Par**: punto | smeraldo |
| oltre la forchetta | **Bogey**: quadrato rosso | sasso |
| un risultato a par o meglio | «buca buona», «buche buone» | «gemma», «gemme» |
| la card | «Lo scorecard» | «Gemme delle stime» |

- **Dove si sceglie**: in Impostazioni > Gioco, oppure con il selettore in fondo alla card. Resta salvato (`gameMood` nelle preferenze dell'app).
- **Cosa segue il mood**:
  - la card, cioè lo scorecard di oggi, la collezione, il grafico per giorno e i testi;
  - i testi del campo, cioè le prove («15 buche buone di fila») e i consigli;
  - la mappa di «Il campo», che riceve `DATA.mood`;
  - la Touch Bar, con il nome della buca appena finita.
  Il widget dell'iPhone non mostra più il gioco.
- **Un mood nuovo**: un `case` in più in `GameMood` (`widget/Sources/GameMood.swift`), con i nomi, i segni, le parole e i colori, più le sue parole in `M` nella mappa.
- **Leggero**: il mood è una stringa letta quando si disegna. Le cache del campo lo mettono nella chiave, così cambiarlo rifà i testi una volta sola.

## La card corta e gli stili con un pulsante [costruito, v2.7]

Nick, 24 ottobre: «la parte delle gemme è troppo lunga: metti molte cose che nascono ed escono se ci passi sopra o le clicchi; e se ci passi sopra deve essere istantaneo». E sugli stili: «spiega bene sti 3 e se si può mettere un bottone che li applica, al posto di fare una cosa manuale».

- **A riposo** la card mostra solo tre cose: la buca in corso con il fairway verso il green, lo scorecard di oggi con il punteggio sul par, il prossimo potere.
- **Il resto sta dietro 8 chip**: Prove, Oggi, Collezione, Minigolf, Claude, A cosa serve, Stili iPhone, Mood.
  - Il riquadro si apre appena il puntatore è sopra, senza animazione.
  - Resta aperto finché il puntatore è sui chip o sul riquadro, e sparisce quando esci.
  - Un clic lo tiene aperto.
- **Stili iPhone**: ogni stile ha un'anteprima e una riga su com'è. Quelli vinti hanno «Usa sull'iPhone», gli altri il lucchetto e cosa serve per vincerli.
  - La scelta va al widget da sola: `phoneTheme`, poi `theme` in `/status`, poi lo script.
  - Il Parameter non serve più. Se è scritto, vince lui.
- **Da decidere**: oggi gli stili si vincono con le regole di prima (Fairway a 10.000 punti, Golf di notte con 10 di fila, Trofeo a 40.000). Nel campo sono invece i poteri delle buche 1, 5 e 7. Se Nick vuole, si allineano alle buche: Golf di notte, già vinto con la serie, tornerebbe da vincere alla buca 5.

## Come può crescere

- **Poteri nuovi**: ognuno è un interruttore a sé, legato a una buca. Se ne aggiungono senza toccare il resto. Un'idea già pronta: Vento a favore, il bonus della serie fino a +500.
- **Campi nuovi del minigolf**: un'altra soglia di buche fatte e un'altra serie di numeri in `GolfRules` (per esempio la sabbia, che frena tantissimo). Il biliardo può avere poi una palla da colpire, se lo vorrai.
- **Prove nuove**: ogni prova è una regola che legge le buche (serie, quota, giro, giorni). Se ne aggiungono quando servono, per esempio sui job in background.
- **Stagione 2**: un campo nuovo con 9 buche più difficili e poteri nuovi. I punti ripartono, i poteri vinti restano.

## Primi passi per costruirlo

Dopo la v2.7 sono fatti i passi 1–5, con `CampoEngine.swift` al posto di `Course.swift`, e il 10. Dei poteri funzionano Fairway, Mazza forte, Golf di notte e Trofeo; gli altri risultano «vinti, ancora da costruire» (`CampoPower.built`). Per il resto vale `YAKO.md`.

1. Leggere `kind_declared` dall'indice in `PastTask` (oggi non c'è) e aggiungere a `GemStats` quello che serve alle prove: bogey e disastri per giro, giro contro il par, serie per tipo, giorni al 70%.
2. `Course.swift`: le 9 buche come dati (titolo, zona, soglia, prove, potere) e lo stato del campo calcolato in un solo passaggio sull'indice, come fa `GemStats`. I poteri valgono dal momento in cui li vinci, non all'indietro. Niente di salvato, tranne lo stile scelto.
3. `TaskETA --course-report`: stampa dove sei e le prove con l'avanzamento, e un selftest per ogni tipo di prova. Con l'indice di oggi deve dire: buche 1–4 chiuse, buca 5 in corso.
4. Dashboard: "Il campo" al posto di "Stili del widget iPhone", con la scelta dello stile mandata a `/status`.
5. Minigolf: `GolfRules` al posto delle costanti di `Golf`, con prato e mazza forte. Poi ghiaccio e biliardo, aperti dalle buche fatte, ognuno con un selftest della fisica.
6. I poteri delle stime, uno alla volta e ognuno con il suo test: Mulligan, Buca doppia, Eagle.
7. Il perché di ogni risultato (le regole in ordine della tabella), il colpo pulito e la riga dell'attesa nel pannello. Servono `segments` e `tools` dall'indice, che ci sono già.
8. La sfida del giro al posto della sfida del giorno.
9. Widget e Touch Bar, poi il consiglio del caddie e quello da 30 secondi, infine Giacca verde e Stagione 2.
10. Anche Claude gioca: i tre passi della sua sezione, con la riga nell'hook spenta di base.

## Dove sei adesso (24 ottobre, ore 16)

- **Buche chiuse: 1, 2, 3, 4.** Titolo: Handicap 18, come oggi nell'app.
- Poteri che avresti: Fairway, il consiglio del caddie, Mulligan, Mazza forte.
- Buche fatte: 149. Il ghiaccio del minigolf a 200 (ne mancano 51, circa un giorno), il biliardo a 888.
- **Buca 5 · Handicap 9**:
  - punti: 26.375 su 40.000, ne mancano 13.625 (circa un giorno e mezzo);
  - 3 giorni di fila al 70%: 2 di 3 (23 ottobre 73%, oggi 76%);
  - un giro senza bogey sui quick: non ancora (il migliore ne ha 1).
- Già vicino alla 6: 15 di fila (il tuo record è 14) e un giro senza disastri (il migliore ne ha uno solo, da 5,4 volte).
