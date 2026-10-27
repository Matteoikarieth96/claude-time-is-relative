# Il caso di riferimento: "Il campo" di TaskETA (24/10/2026)

TaskETA è l'app della barra dei menu del fork Yako di task-eta: cronometra i task di Claude Code e li confronta con la stima di Claude. Il 24/10 Nick ha chiesto di trasformare le gemme delle stime in un gioco vero, a livelli, spiegato con una mappa da minigolf. Qui le decisioni, nell'ordine della procedura. Il progetto completo è `docs/gioco-progressione.md` nella repo `~/Downloads/claude-time-is-relative` (branch `starcks`); la skill che lo segue è `tasketa-gioco`.

## 1. La funzione vera

- Azione vera: un task di Claude Code con la stima. Unità di gioco: una buca. La stima è il par.
- C'era già un gioco: le gemme. Entro l'8% della stima diamante (300 punti, hole in one), più veloce della forchetta zaffiro (150, birdie), dentro la forchetta smeraldo (100, par), oltre sasso (0, bogey). +25 per gemma di fila, fino a +250. Giri da 18. Nove livelli da Principiante a Leggenda del green.
- Tenuto tutto. Sopra: prove, poteri, campi del minigolf.

## 2. I numeri veri (23–24 ottobre)

- 149 buche in due giorni (55 e 94), circa 50 al giorno.
- 26.375 punti, circa 180 a buca. 74% di gemme. Serie migliore 14, sui medium 5.
- 4–5 bogey per giro, il migliore 2. In ogni giro almeno un disastro (oltre 5 volte la stima).
- Conseguenze: i punti aprono i green in fretta (40.000 in 4 giorni), quindi dopo la buca 5 a fermarti sono le prove, ed è voluto. La sfida del giorno è diventata una sfida per giro.
- Lo script `dove-sono.py` legge l'indice, applica le regole e dice a che buca sei, anche in JSON per la mappa.

## 3. Livelli e prove: 9 buche in 3 zone

| Zona | Buche | Prove per buca | Quanto ci vuole |
|---|---|---|---|
| Il Pratone dei Gardens | 1 Principiante, 2 Caddie, 3 Dilettante | 1 | il primo giorno |
| Trump Lake | 4 Handicap 18, 5 Handicap 9, 6 Scratch | 2 | qualche giorno |
| Monte Donato | 7 Pro, 8 Campione, 9 Leggenda del green | 3 | settimane e un'abitudine nuova |

Esempi di prove: 5 gemme di fila; un giro con 3 bogey o meno; 3 giorni di fila al 70%; un giro senza disastri; 25 di fila. Le soglie dei punti sono quelle dei livelli che c'erano già.

## 4. Poteri e sblocchi

| Buca | Potere | Tipo |
|---|---|---|
| 1 | Fairway: widget verde prato | aspetto |
| 2 | Il consiglio del caddie: una riga a ogni giro | aiuto |
| 3 | Mulligan: una volta al giorno il primo bogey non rompe la serie | regola |
| 4 | Mazza forte: tiri più lunghi nel minigolf | gioco nel gioco |
| 5 | Golf di notte: widget notturno | aspetto |
| 6 | Buca doppia: una buca per giro vale doppio | regola |
| 7 | Trofeo: widget oro | aspetto |
| 8 | Eagle: un diamante su un medium o long vale 500 | regola |
| 9 | Giacca verde e Stagione 2 | aspetto |

- Tutti i poteri insieme valgono meno del 20% dei punti.
- Minigolf a buche fatte (tutti i task con la stima, anche i bogey): prato subito, campo ghiacciato a 200, biliardo a 888. Prima erano "gettoni spesi": Nick li ha tolti.
- Gli stili non si scrivono più nel Parameter di Scriptable: si scelgono con un clic nella dashboard.

## 5. Costo a riposo

- Ogni potere è un numero letto all'avvio della partita o all'apertura della dashboard.
- Le costanti del minigolf diventano un piccolo insieme di regole scelto a inizio partita. Il timer a 60 al secondo gira solo mentre la pallina si muove.
- Buche fatte e poteri vengono dall'indice, letto con la cache che la Touch Bar ha già.

## 6. Ironia di casa

- Luoghi: Pratone dei Gardens, Trump Lake, Monte Donato, Urbe Hub (pollaio tech con pollo e dino, omaggio a Dino di Urbe.eth, autore di task-eta).
- Timbri degli esiti: 🤌 Dai che ci siamo, 🦵 C'hai quella gamba lì, 🎉 GG, 🔥 This is fine con 🦖 Dino Gay.
- Personaggi: il caddie; il dino del "Coming soon" ("Dai tempo al tempo, che nessuno mi sta pagando"); John Cena alla buca ("Oh yeah!").

## 7. Easter egg

| Dove | Clic | Cosa succede |
|---|---|---|
| Pallino di "in corso" | 8 | un pallino schizza e rimbalza per 8 secondi |
| | 69 | ne partono 69 |
| | 101 | 101 pallini, "Oh yeah! John Cena!", minigolf sbloccato per sempre |
| | ⌘ M G | trascinarlo con i tre tasti sblocca il minigolf con la stessa festa |
| Minigolf | 69 sponde in tutto | una volta sola entra il dino col cartello |
| Monopattino della mappa | 1, 2, 3 | un trick a ogni clic |
| | 5 | turbo a 300 km/h per 2,4 secondi |
| Trump Lake sulla mappa | 1 | galleggia un cappellino rosso |

Ogni clic sul pallino lo fa sussultare, mostra il numero e suona più alto verso il 101; il conteggio resta dopo il riavvio.

Sotto la mappa c'è il contatto: «Per gli easter egg scrivi su Telegram a @yakonft», con il link https://t.me/yakonft (regola di Nick del 24/10).

## 8. Social, umano e AI

- La stima è di Claude, il task è di tutti e due: si gioca in coppia con l'AI, contro se stessi.
- L'analisi della settimana la scrive un agente esterno che legge solo i numeri, senza la chat.
- Il caddie dà il consiglio che l'app già calcolava («se servono più di 3 strumenti, chiedi medium»).
- Avvisi da mostrare: «Buca 5 chiusa: nuovo potere, Golf di notte», «Campo ghiacciato aperto».

## 9. La mappa

- Un parco di minigolf visto dall'alto, nello stile sobrio di TaskETA, chiaro e scuro (scuro = golf di notte).
- Una pagina corta: titolo con le chip dei numeri, la mappa, una riga di aiuto.
- Schede al passaggio del cursore, al focus o al tocco; su telefono un foglio dal basso.
- Edifici: Urbe Hub (il motore), club house (come si gioca), bacheca (i poteri), tabellone (dove sei), prato, ghiaccio e biliardo (i campi), lavori in corso (cosa resta).
- In movimento: il monopattino che fa il percorso, la bandiera della buca di adesso, la pallina sul vialetto.
- Bocciata la prima versione: 9 schede in fila. «Più dinamica e più corta.»
- Pubblicata su `<link dell'artifact privato, nella skill installata>`, sorgente in `tasketa-gioco/templates/il-campo.html`.
