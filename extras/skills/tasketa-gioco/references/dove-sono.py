#!/usr/bin/env python3
"""Dove sei sul campo del gioco delle stime di TaskETA.

Legge l'indice di task-eta (~/.claude/task-eta/index.json, o $TASK_ETA_DIR/index.json) e applica le
regole del campo scritte in docs/gioco-progressione.md: 9 buche, prove, poteri, campi del minigolf.
Non scrive niente. Uso:

    python3 -I dove-sono.py          # riassunto in italiano
    python3 -I dove-sono.py --json   # gli stessi numeri, per aggiornare la mappa

I punti sono quelli di oggi (Gems.swift): i poteri che cambiano i punti (Mulligan, Buca doppia, Eagle)
non sono ancora costruiti e qui non si applicano.
"""
import collections
import datetime
import json
import os
import sys

POINTS = {"D": 300, "S": 150, "E": 100, "P": 0}
TO_PAR = {"D": -2, "S": -1, "E": 0, "P": 1}
GOAL = 0.7            # una giornata "al 70%"
WORKDAY_HOLES = 10    # i giorni con meno buche non contano e non rompono le serie di giorni
DISASTER = 5          # un disastro: reale oltre 5 volte la stima
ROUND = 18
MINIGOLF = [(0, "Prato"), (200, "Campo ghiacciato"), (888, "Biliardo")]

# (numero, titolo, zona, green a, prove, potere, tipo)
COURSE = [
    (1, "Principiante", "Il Pratone dei Gardens", 0, [("first_round",)], "Fairway", "widget"),
    (2, "Caddie", "Il Pratone dei Gardens", 4000, [("streak", 5)], "Il consiglio del caddie", "aiuto"),
    (3, "Dilettante", "Il Pratone dei Gardens", 10000, [("round_challenge",)], "Mulligan", "stime"),
    (4, "Handicap 18", "Trump Lake", 20000, [("streak", 10), ("round_max_bogeys", 3)], "Mazza forte", "minigolf"),
    (5, "Handicap 9", "Trump Lake", 40000, [("days_at_goal", 3), ("round_no_quick_bogey",)], "Golf di notte", "widget"),
    (6, "Scratch", "Trump Lake", 75000, [("streak", 15), ("round_no_disaster",)], "Buca doppia", "stime"),
    (7, "Pro", "Monte Donato", 125000, [("streak", 20), ("days_at_goal", 5), ("round_max_bogeys", 1)], "Trofeo", "widget"),
    (8, "Campione", "Monte Donato", 200000, [("kind_streak", "medium", 10), ("round_to_par", -15), ("clean_rounds_in_a_row", 2)], "Eagle", "stime"),
    (9, "Leggenda del green", "Monte Donato", 300000, [("streak", 25), ("round_max_bogeys", 0), ("days_at_goal_in_month", 20)], "Giacca verde", "aspetto"),
]

# La sfida del giro: una per ogni giro da 18, scelta da giorno e numero del giro.
CHALLENGES = ["5 diamanti", "8 gemme di fila", "3 bogey o meno", "nessun disastro", "un birdie su un medium", "−6 nel giro"]


def gem_of(real, est, rng):
    if abs(real - est) <= max(10, est * 0.08):
        return "D"
    lo, hi = rng if rng else (est * 0.7, est * 1.5)
    return "S" if real < lo else "P" if real > hi else "E"


def load_holes():
    base = os.environ.get("TASK_ETA_DIR") or os.path.expanduser("~/.claude/task-eta")
    with open(os.path.join(base, "index.json")) as f:
        tasks = json.load(f).get("tasks", {})
    holes = []
    for t in tasks.values():
        if t.get("headless"):
            continue
        real, start, est = t.get("dur_s"), t.get("start_ts"), t.get("estimate_min")
        if not real or not start or not est or real <= 0 or est <= 0:
            continue
        est *= 60
        r = t.get("est_range")
        rng = (r[0], r[1]) if isinstance(r, list) and len(r) == 2 and r[1] > r[0] >= 0 else None
        holes.append({"start": start, "end": start + real, "real": real, "est": est,
                      "gem": gem_of(real, est, rng), "kind": t.get("kind_declared"),
                      "segments": t.get("segments", 1), "tools": t.get("tools", 0)})
    holes.sort(key=lambda h: h["start"])
    streak = 0
    for h in holes:
        h["points"] = POINTS[h["gem"]] + 25 * min(streak, 10) if h["gem"] != "P" else 0
        streak = streak + 1 if h["gem"] != "P" else 0
    return holes


def best_run(seq, ok):
    best = run = 0
    for x in seq:
        run = run + 1 if ok(x) else 0
        best = max(best, run)
    return best


class Game:
    def __init__(self, holes):
        self.holes = holes
        self.points = sum(h["points"] for h in holes)
        self.days = collections.OrderedDict()
        for h in holes:
            self.days.setdefault(datetime.date.fromtimestamp(h["end"]), []).append(h)
        self.rounds = []  # (giorno, numero del giro, buche); solo i giri completi
        self.current_round = []
        for day, hs in self.days.items():
            for i in range(0, len(hs), ROUND):
                chunk = hs[i:i + ROUND]
                if len(chunk) == ROUND:
                    self.rounds.append((day, i // ROUND + 1, chunk))
            self.current_round = hs[(len(hs) - 1) // ROUND * ROUND:] if hs else []
        self.workdays = [(d, sum(h["gem"] != "P" for h in hs) / len(hs)) for d, hs in self.days.items() if len(hs) >= WORKDAY_HOLES]

    @staticmethod
    def bogeys(r):
        return sum(h["gem"] == "P" for h in r)

    @staticmethod
    def disasters(r):
        return sum(h["real"] > DISASTER * h["est"] for h in r)

    def challenge_met(self, day, n, r):
        c = (day.toordinal() * 7 + n) % len(CHALLENGES)
        return [sum(h["gem"] == "D" for h in r) >= 5,
                best_run(r, lambda h: h["gem"] != "P") >= 8,
                self.bogeys(r) <= 3,
                self.disasters(r) == 0,
                any(h["gem"] == "S" and h["kind"] == "medium" for h in r),
                sum(TO_PAR[h["gem"]] for h in r) <= -6][c]

    def trial(self, t):
        """(fatta, nome della prova, a che punto sei)."""
        kind = t[0]
        rounds = [r for _, _, r in self.rounds]
        if kind == "first_round":
            return bool(rounds), "chiudi il primo giro da 18 buche", f"{len(rounds)} giri chiusi"
        if kind == "streak":
            best = best_run(self.holes, lambda h: h["gem"] != "P")
            return best >= t[1], f"{t[1]} gemme di fila", f"il record è {best}"
        if kind == "kind_streak":
            best = best_run([h for h in self.holes if h["kind"] == t[1]], lambda h: h["gem"] != "P")
            return best >= t[2], f"{t[2]} gemme di fila sui {t[1]}", f"il record è {best}"
        if kind == "round_challenge":
            won = sum(self.challenge_met(d, n, r) for d, n, r in self.rounds)
            return won > 0, "vinci una sfida del giro", f"{won} sfide vinte su {len(rounds)} giri"
        if kind == "round_max_bogeys":
            best = min((self.bogeys(r) for r in rounds), default=None)
            name = "un giro senza bogey" if t[1] == 0 else f"un giro con {t[1]} bogey o meno"
            return best is not None and best <= t[1], name, f"il migliore ne ha {best}" if best is not None else "nessun giro chiuso"
        if kind == "round_no_quick_bogey":
            best = min((sum(h["gem"] == "P" and h["kind"] == "quick" for h in r) for r in rounds), default=None)
            return best == 0, "un giro senza bogey sui quick", f"il migliore ne ha {best}"
        if kind == "round_no_disaster":
            best = min((self.disasters(r) for r in rounds), default=None)
            return best == 0, "un giro senza disastri", f"il migliore ne ha {best}"
        if kind == "round_to_par":
            best = min((sum(TO_PAR[h["gem"]] for h in r) for r in rounds), default=None)
            return best is not None and best <= t[1], f"un giro a {t[1]} o meglio", f"il migliore è {best}"
        if kind == "clean_rounds_in_a_row":
            best = best_run(rounds, lambda r: self.disasters(r) == 0)
            return best >= t[1], f"{t[1]} giri di fila senza disastri", f"il record è {best}"
        if kind == "days_at_goal":
            best = best_run(self.workdays, lambda d: d[1] >= GOAL)
            return best >= t[1], f"{t[1]} giorni di fila al 70%", f"{min(best, t[1])} di {t[1]}: " + ", ".join(
                f"{d.day}/{d.month} {round(s * 100)}%" for d, s in self.workdays[-t[1]:])
        if kind == "days_at_goal_in_month":
            best = 0
            for d, _ in self.workdays:
                best = max(best, sum(s >= GOAL and d <= e < d + datetime.timedelta(days=30) for e, s in self.workdays))
            return best >= t[1], f"{t[1]} giorni al 70% in un mese", f"il massimo in 30 giorni è {best}"
        raise ValueError(kind)

    def course(self):
        out, open_ = [], True
        for n, title, zone, green, trials, power, ptype in COURSE:
            ts = [self.trial(t) for t in trials]
            closed = open_ and self.points >= green and all(t[0] for t in ts)
            out.append({"hole": n, "title": title, "zone": zone, "green": green, "power": power, "power_type": ptype,
                        "closed": closed, "trials": [{"done": d, "name": nm, "progress": p} for d, nm, p in ts]})
            open_ = closed
        return out


def summary(g):
    course = g.course()
    closed = [h for h in course if h["closed"]]
    now = next((h for h in course if not h["closed"]), None)
    played = len(g.holes)
    best = best_run(g.holes, lambda h: h["gem"] != "P")
    streak = len(g.holes) - max([i + 1 for i, h in enumerate(g.holes) if h["gem"] == "P"], default=0)
    gems = sum(h["gem"] != "P" for h in g.holes)
    minigolf = [name for need, name in MINIGOLF if played >= need]
    nxt = next(((need, name) for need, name in MINIGOLF if played < need), None)
    prev_green = closed[-1]["green"] if closed else 0
    def clean(h):  # colpo pulito: un turno solo e rimasto del suo tipo
        k, n = h["kind"], h["tools"]
        return h["segments"] == 1 and not (k == "quick" and n > 3) and not (k == "medium" and n > 15)
    cl = [h for h in g.holes if clean(h)]
    data = {
        "clean_share": round(len(cl) / played, 3) if played else 0,
        "at": datetime.datetime.now().strftime("%d/%m %H:%M"),
        "points": g.points, "holes_played": played, "gem_share": round(gems / played, 3) if played else 0,
        "streak": streak, "best_streak": best,
        "title": closed[-1]["title"] if closed else None,
        "closed": [h["hole"] for h in closed],
        "powers": [h["power"] for h in closed] + [c for c in minigolf if c != "Prato"],
        "now": now,
        "now_points_share": round((g.points - prev_green) / (now["green"] - prev_green), 3) if now and now["green"] > prev_green else 1,
        "minigolf_open": minigolf,
        "minigolf_next": {"name": nxt[1], "at": nxt[0], "missing": nxt[0] - played} if nxt else None,
        "current_round": {"number": (len(g.days[next(reversed(g.days))]) - 1) // ROUND + 1 if g.days else 1,
                          "holes": "".join(h["gem"] for h in g.current_round),
                          "to_par": sum(TO_PAR[h["gem"]] for h in g.current_round)},
        "course": course,
    }
    return data


def fmt(n):
    return f"{n:,}".replace(",", ".")


def main():
    g = Game(load_holes())
    d = summary(g)
    if "--json" in sys.argv:
        json.dump(d, sys.stdout, ensure_ascii=False, indent=1)
        print()
        return
    print(f"Il campo, {d['at']}")
    print(f"- {fmt(d['points'])} punti, {d['holes_played']} buche fatte, {round(d['gem_share'] * 100)}% di gemme, serie {d['streak']} (record {d['best_streak']})")
    print(f"- Titolo: {d['title'] or 'nessuno'}; buche chiuse: {', '.join(map(str, d['closed'])) or 'nessuna'}")
    print(f"- Poteri: {', '.join(d['powers']) or 'nessuno'}")
    now = d["now"]
    if now:
        print(f"- Sei alla buca {now['hole']} · {now['title']} (green a {fmt(now['green'])} punti, "
              f"{'raggiunto' if d['points'] >= now['green'] else 'ne mancano ' + fmt(now['green'] - d['points'])})")
        for t in now["trials"]:
            print(f"    {'✓' if t['done'] else '·'} {t['name']}: {t['progress']}")
        print(f"  Potere della buca: {now['power']} ({now['power_type']})")
    else:
        print("- Campo finito: Leggenda del green")
    m = d["minigolf_next"]
    print(f"- Minigolf: aperti {', '.join(d['minigolf_open'])}" + (f"; {m['name']} a {m['at']} buche, ne mancano {m['missing']}" if m else ""))
    print(f"- Colpi puliti: {round(d['clean_share'] * 100)}% delle buche")
    r = d["current_round"]
    print(f"- Giro {r['number']} di oggi: {len(r['holes'])}/18, {r['to_par']:+d}".replace("+0", "par"))


if __name__ == "__main__":
    main()
