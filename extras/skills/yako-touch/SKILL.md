---
name: yako-touch
description: Yako Touch, il modo di Nick di trasformare una funzione o un prodotto in un gioco leggero, con ironia ed easter egg, per persone e per agenti AI (anche il lato social). Parte da una funzione vera, tara i numeri sui dati veri, fa una progressione a gradini con poteri e sblocchi evidenti, costo zero a riposo, e lo spiega con una mappa. ATTIVARE SEMPRE quando Nick dice "Yako Touch", "mettici la Yako Touch", "gamifica", "gamificare", "gamification", "fallo diventare un gioco", "rendilo un gioco", "mettici un easter egg", "un tocco di ironia", "rendilo leggero e giocoso", "livelli e poteri", "sblocchi", "premi", "badge", "social per AI", "agenti che giocano". Per il gioco di TaskETA c'è già tasketa-gioco. Versione 1 del 24/10/2026, ricavata da "Il campo", il gioco delle stime di TaskETA.
---

# Yako Touch

## Obiettivo di Nick

Prendere una funzione vera e farla diventare un gioco: semplice, leggero, con ironia. Vale per le persone e per gli agenti AI, anche nel lato social. Il modello è "Il campo" di TaskETA, progettato con Nick il 24/10/2026: le stime di Claude diventate un minigolf da 9 buche.

Tre cose che Nick vuole sempre:
- un gioco vero, che cambia come si usa la funzione, non una pioggia di badge;
- leggero: non pesa sull'app e non chiede niente da configurare;
- spiegato con una figura, nello stile del prodotto, con le battute di casa.

## Dove stanno le cose

| Cosa | Dove |
|---|---|
| Il caso del campo in breve: decisioni e numeri, passo per passo | `references/il-campo-in-breve.md` |
| La scheda da riempire per un gioco nuovo | `templates/scheda-gioco.md` |
| L'esempio vero, la skill del gioco di TaskETA | `~/.claude/skills/tasketa-gioco/`: `references/dove-sono.py` (lo script sui dati veri), `templates/il-campo.html` (la mappa) |
| Il progetto scritto del campo | `~/Downloads/claude-time-is-relative/docs/gioco-progressione.md` |
| Timbri, pallino, minigolf, dino | `YAKO.md` nella stessa repo, sezioni "Animazioni di fine task" e "Easter egg" |
| La mappa pubblicata | `<link dell'artifact privato, nella skill installata>` |

I file dell'esempio si leggono e basta. Se Nick parla del gioco di TaskETA, usa `tasketa-gioco`, non questa skill.

## Procedura

**1. Parti da una funzione vera.**
- Cosa fa già, ogni giorno, la persona o l'agente? Quell'azione è l'unità di gioco. In TaskETA un task con la stima è una buca, e la stima è il par.
- La metafora nasce dalla funzione: stima contro tempo reale è par contro colpi, quindi golf. Scegli una metafora che sia un posto (un parco, un campo, una città): diventerà la mappa.
- Il gioco misura la qualità, non la quantità. «I punti misurano quanto giochi, le prove quanto giochi bene.»
- Se un pezzo di gioco c'è già (gemme, timbri, livelli), lo tieni e ci costruisci sopra. Segna cosa c'è già, cosa cambia e cosa è nuovo.

**2. Tara su dati veri.**
- Leggi i dati della funzione (indice, log, database). Conta: azioni al giorno, quota di successi, record, caso peggiore, differenze fra i tipi.
- Scrivi un piccolo script che legge e non scrive, come `dove-sono.py`: applica le regole ai dati e dice "dove sei". Le regole stanno in un posto solo nello script e nel documento: se ne cambi una, cambiale in tutti e due.
- Scegli le soglie con quei numeri: la prima zona si chiude il primo giorno, la seconda in qualche giorno, la terza chiede un'abitudine nuova.
- Guarda il volume: con 50 azioni al giorno una sfida del giorno si vince a metà mattina. In TaskETA è diventata una sfida per ogni giro da 18.
- Scrivi l'equilibrio con i numeri: quando si arriva a ogni zona e quanto pesano i poteri.

**3. Progressione a gradini, pochi obiettivi.**
- Livelli come luoghi di una mappa: 3 zone da 3 livelli, con 1, 2 e 3 prove per livello a seconda della zona.
- I punti portano vicino (al green), le prove chiudono il livello (in buca). Le prove sono serie, quote, giri, giorni di fila. Mai quantità pura.
- Riusa i livelli e le soglie che ci sono già. Una prova fatta resta fatta, anche prima di arrivare a quel livello.
- Al massimo due parole nuove, spiegate in una riga (in TaskETA "disastro" e "al 70%").

**4. Poteri e sblocchi evidenti.**
- Ogni livello chiuso accende un potere che cambia come si gioca o come si vede: un aspetto (uno stile del widget), un aiuto (il consiglio del caddie), una regola (Mulligan, Buca doppia, Eagle), un gioco nel gioco (Mazza forte nel minigolf).
- I poteri restano piccoli: tutti insieme meno del 20% dei punti. Il gioco cambia, la classifica no.
- Si avanza per azioni fatte. In TaskETA le "buche fatte" aprono i campi nuovi del minigolf: ghiaccio a 200, biliardo a 888. Niente da spendere.
- Lo sblocco è automatico e si vede. Un potere vinto funziona da solo, uno da vincere dice quale livello lo dà. Si sceglie con un clic, dove l'utente guarda già.

**5. Costo zero a riposo.**
- Ogni potere è un numero letto quando parte una partita o si apre una schermata. Nessun timer, nessuna animazione a riposo, nessuna immagine o suono nuovo.
- Le animazioni girano solo durante l'azione: il timer del minigolf va solo mentre la pallina si muove.
- Niente di salvato se si può ricalcolare dai dati. I dati pesanti si leggono con una cache che si ricarica solo quando cambiano.
- Nel documento, per ogni pezzo: cosa tocca nel codice e quanto costa.

**6. Nomi e ironia di casa.**
- I luoghi prendono nomi dal mondo di Nick: il Pratone dei Gardens, Trump Lake, Monte Donato, l'Urbe Hub (un pollaio tech con un pollo e un dino, perché task-eta l'ha scritto Dino, di Urbe.eth).
- Ogni esito ha un timbro che fa ridere, anche il fallimento: 🤌 Dai che ci siamo, 🦵 C'hai quella gamba lì, 🎉 GG, 🔥 This is fine (con 🦖 Dino Gay di lato). L'errore deve far sorridere, non pesare.
- Un personaggio che parla leggero e corto: il caddie che consiglia; il dino col cartello "Coming soon", che poi lo gira: "Dai tempo al tempo, che nessuno mi sta pagando".
- Meme che Nick conosce: John Cena alla buca, "Oh yeah!". Una battuta per oggetto, non dieci.

**7. Easter egg a gradini di clic.**
- Il numero di clic decide la ricompensa, e la ricompensa cresce. Il pallino: a 8 clic un pallino che rimbalza, a 69 ne partono 69, a 101 sono 101, "Oh yeah! John Cena!" e il minigolf si sblocca per sempre. Il monopattino della mappa fa un trick a 1, 2 e 3 clic; a 5 parte il turbo a 300 km/h per 2,4 secondi. Un clic sul lago fa galleggiare un cappellino rosso.
- Ogni clic risponde subito: un sussulto, il numero, un suono che sale verso la meta. Il conteggio resta anche se l'app si riavvia.
- Numeri con una battuta dentro (8, 69, 101). La sorpresa grande arriva una volta sola (il dino a 69 sponde).
- Una strada segreta per chi la sa: trascinare il pallino tenendo ⌘ M G.
- Ogni easter egg ha in vista il contatto: «Per gli easter egg scrivi su Telegram a @yakonft», con il link https://t.me/yakonft. Nella mappa del campo sta sotto la mappa.
- Gli easter egg sono premi in più: la funzione vera resta tutta lì per chi non li trova.
- Con "Riduci movimento" resta solo il timbro.

**8. Il lato social, umano e AI.**
- Chi gioca: la persona, l'agente o tutti e due. In TaskETA la stima la fa Claude e il task lo fanno insieme: il par è dell'AI, il colpo è di tutti e due.
- L'agente che gioca: le sue azioni vere sono i colpi (una stima, una risposta, una revisione). Premia la precisione, mai il volume: un agente fa cento azioni piccole in un attimo. Niente punti dal nulla.
- L'agente personaggio: il caddie, il dino. Voce leggera, una riga, consigli veri (il consiglio del caddie riusa un testo che l'app aveva già).
- L'agente arbitro: revisioni e analisi da un agente esterno, senza il contesto della chat, che legge solo i numeri (l'analista della settimana di TaskETA).
- Le persone: momenti da far vedere (la festa a schermo, l'avviso "Buca 5 chiusa"), nomi e battute del giro, crediti affettuosi a chi c'è dietro (Dino, Urbe.eth).
- In TaskETA si gioca contro se stessi: niente classifiche. Se servono confronti fra persone o fra agenti, chiedi a Nick prima.

**9. Spiegalo con una mappa, nel suo stile.**
- Una mappa come quelle vere (il parco visto dall'alto), nello stile del prodotto: per TaskETA sobrio, verde prato, chiaro e scuro. Per una slide di Starcks vale `stile-starcks-stage`.
- Pagina corta: il titolo, la mappa, una riga di aiuto.
- Ogni luogo apre una scheda al passaggio del cursore, al focus o al tocco; su telefono la scheda è un foglio dal basso. Le spiegazioni lunghe stanno nel documento, non nella pagina.
- Piccoli movimenti che raccontano: il monopattino che fa il percorso, la bandiera che sventola sul livello di adesso, la pallina ferma sul vialetto. Si fermano con "Riduci movimento".
- Un edificio per ogni pezzo del sistema. In TaskETA: il motore (Urbe Hub), come si gioca (club house), i poteri (bacheca), dove sei (tabellone), cosa resta da fare (lavori in corso).
- Tutti i numeri in un oggetto `DATA` in cima allo script, con l'ora dei numeri: si aggiorna senza toccare il disegno.
- Per la meccanica (schede, foglio, percorso animato, accessibilità) copia `tasketa-gioco/templates/il-campo.html` nella scratchpad e parti da lì. L'originale non si tocca.
- Pubblica come artifact privato. Quando la aggiorni, stesso URL.
- La mappa vive anche dentro il prodotto, dove l'utente guarda già i suoi numeri: in TaskETA nella finestra Analytics ("Analytics dei task"). E le parti del gioco dentro il prodotto prendono lo stile della mappa: in TaskETA tutta la sezione del minigolf di Analytics (24/10).

**10. Scrivi il progetto, poi un pezzo alla volta.**
- Riempi `templates/scheda-gioco.md`. Se una riga resta vuota, il gioco non è pronto.
- Scrivi il documento del progetto, come `gioco-progressione.md`: legenda [c'è già] / [cambia] / [nuovo], l'idea in quattro righe, livelli, prove e poteri in tabella con cosa tocca nel codice, l'equilibrio con i numeri veri, dove si vede, come può crescere, i primi passi in ordine, dove sei adesso.
- Prima il progetto e la mappa. Il codice quando Nick lo chiede, un pezzo alla volta, ognuno con il suo test.
- Se il gioco diventa un progetto vivo, dagli una skill sua (come `tasketa-gioco`), seguendo `skill-manutenzione`.

## Regole di Nick, non negoziabili

- Niente valute da spendere. Si avanza per azioni fatte e fatte bene. Il 24/10 Nick ha corretto i "gettoni spesi" in "buche fatte".
- Niente configurazioni nascoste. Niente da scrivere in un campo per attivare un premio: Nick non capiva lo stile del widget da scrivere nel Parameter di Scriptable.
- Niente icone cringe. Nella Touch Bar solo testo, niente gemme né diamanti. Le emoji stanno nei timbri.
- Niente pagine lunghe a lista. La prima mappa, 9 schede in fila, è stata bocciata: «più dinamica e più corta».
- La mappa non è solo una pagina a parte: va anche dentro le analytics del prodotto, e le parti del gioco lì dentro hanno lo stile della mappa. Nick, 24/10: «la mappa è okay ma va messa dentro Analytics anche», «tutto lo stile delle analytics del minigolf con lo stile della mini mappa».
- Gli easter egg rimandano a Telegram. Dove c'è un easter egg, in vista c'è «Per gli easter egg scrivi su Telegram a @yakonft», con il link https://t.me/yakonft. Regola di Nick del 24/10: «per gli easter egg scrivi su Telegram @yakonft».
- Leggero, sempre: costo zero a riposo.
- Italiano semplice, frasi corte. Spiegazioni con le figure.
- Sobrio dove serve. L'ironia sta nei nomi, nei timbri e negli easter egg, non in ogni riga dell'interfaccia.

## Gotcha pagati

- Prima di promettere una prova, controlla che l'app legga davvero il dato. In TaskETA `PastTask` non leggeva `kind_declared`, che serviva a tre prove e a un potere.
- Le soglie a occhio non reggono il volume vero: la sfida del giorno era pensata per poche buche, con 50 al giorno si vinceva subito.
- Tanti task piccoli danno punti. Per questo le prove sono quote, serie e giri.
- I numeri si muovono mentre Nick lavora: nella mappa e nel documento scrivi l'ora.
- Anteprime locali: porta libera, e chiudi solo il tuo processo, per PID. Il 24/10 un `pkill -f "http.server 879"` ha chiuso i server di altre sessioni.
- Su telefono la mappa scorre di lato (larga almeno 820 px). Ogni luogo cliccabile ha `tabindex="0"`, `role="button"` e un `aria-label`.
- Niente audio o immagini con copyright dentro l'app: l'audio vero di John Cena non c'è, l'app suona una sua fanfara e Nick può mettere un suo file nella cartella dei suoni.
- Da chiedere a Nick, non ancora deciso: su un prodotto di scommesse di un cliente di Starcks il gioco non deve premiare il volume di giocate o di depositi. Prima di proporlo serve un controllo di gioco responsabile (`legal:compliance-check`).

## Output atteso

- Prima proposta, in chat in 6–10 righe: la funzione e l'unità di gioco, la metafora, le 3 zone con le prove, i poteri, gli easter egg, il costo a riposo. Più la scheda riempita.
- Poi il documento del progetto, la mappa pubblicata (link, sempre lo stesso) e, se ci sono dati, lo script che dice dove sei.

## Non ancora fatto

- La Yako Touch è stata usata una volta sola, su TaskETA. Lì il campo esiste come progetto, mappa e script, ma non è ancora costruito nell'app (24/10/2026).
- "L'agente che gioca" e il social fra persone sono principi, non ancora provati su un prodotto.
- Idee pronte dal campo: Vento a favore (bonus serie fino a +500), campo di sabbia, Stagione 2 (i punti ripartono, i poteri restano).
- Ogni volta che la usi su un prodotto nuovo, aggiungi il caso in `references/` e le regole nuove di Nick qui.
