# Route metrics

How fast and how sensible Pathmark's routes are, measured the same way for all 56 race and class combinations in both modes. The tool is `python3 -m tools.routekit metrics` (`tools/routekit/metrics.py` on top of the simulator `tools/routekit/sim.py`); CI runs it in the job "Route quality" and writes the report into the job summary. This file holds the measurement of the routes before the route optimizer (start route, Welle 5) and after it (Welle 6b), both with the tool of Welle 6b.

## What the numbers are

- **Modellstunden.** Every time in this file is a Modellstunde (model hour): what the model charges for a route, not a forecast of real play time. The parameters are priors from other tools and Classic values; none is measured in WoW: Forever yet (report DR 22b: Polestar's own model gives a 5–95 % band of 121.8 to 241.8 hours for one route). Rankings between routes and the metrics below carry; absolute hours do not. Our own measurements from the data collector replace the priors after the start.
- **Model check.** A speed route must need between 8,150 and 32,800 XP per Modellstunde for levels 1–20 (Forever beta average 20.5 h to level 20, Classic Era solo record 5:06 h, DR 22b). Outside this band the model is wrong, not the route good.
- **Parameters and limits** live in `data/plan/params.toml`, each with its source, date and Forever status (`ja`, `unbestätigt`, `gewählt`). Most limits are chosen start values from DR 22c/22d and the plan of Welle 6; Welle 6b calibrates them.
- **Chosen model rules** where the data has no value: creatures of an objective have the quest's level; one kill per collected item; flights fly the straight line (no flight path lengths in the data); a transport costs half a cycle of waiting plus one ride, without the walk to the dock; no food buff and no rested XP. Each is marked `gewählt` in `data/plan/params.toml`.
- **Kill XP** uses the Forever rule for creatures below the character (forever-bugs #138), the same in `Pathmark/Routes/XP.lua` and `tools/routekit/xp.py`.

## How the simulator plays a route

Step by step through the composed route of one combination: walk to every `goto` (straight line × detour factor of the continent ÷ 7 yd/s), take, work and hand in quests (6 s per talk, kills with the class factor, kills on the way), raise the level with quest and kill XP. An accept needs the planned level of its step and the quest's minimum level; a character below grinds creatures of its own level until it is there (grind fill). The route ends when the character reaches level 30. The quest log may hold 40 quests (client), the working limit for building routes is 35. Model time is also kept as counters (yards, kills, talks, transports, grind), so other class profiles and the 16 parameter draws of P3 need no new play.

## Metrics

| Id | What | Limit | Source |
| --- | --- | --- | --- |
| P1 | two runs on the same input give the same SHA-256 over all results | equal | DR 22c §F |
| P2 | quest XP + objective kill XP / XP of each start and core module's level band; grind share of the time in each level | ≥ 0.90; ≤ 0.10 per level | DR 22c §F, plan Welle 6 |
| P3 | Modellstunden 1–30 in 16 held-out parameter draws against the start route | no draw worse | DR 22c §D |
| P4 | legs inside one zone longer than 0.05 Modellstunden (3 minutes) for one quest whose XP rate is below half the route's; longest walk in one zone | 0; not worse than the start | DR 22c §F |
| P5 | avoidable returns (a visit ends 400 yd away; work on a later visit that was possible on the last one) and wasted trips (all of it was possible, no trainer or flight master) | not more than the start; 0 wasted | Polestar judge, DR 22c §5 |
| P6 | quests whose giver stood within 500 yd of the walked line while the character could take them there and they were worth it (§4.3: XP per second of detour and work at least the route's rate): never taken, or taken only after going 1,000 yd away; reported apart: P6z (needs a zone the route does not visit again), P6n (not worth it) | 0 | Polestar judge, DR 22c §4.3 |
| P7 | quest log peak; quests taken and never handed in | ≤ 35; 0 | plan Welle 6, DR 22a R30 |
| P8 | accept above level + 2, turn-in below 80 % quest XP, accept more than 5 levels above the median of its neighbours | 0 | DR 22c §F |
| P9 | zone changes, quests per zone visit | not worse than the start | DR 22c §F |
| P10 | spread of Modellstunden per level band over the combinations of a faction | report only; times compare within a class (G10) | DR 22c §F, DR 22d |
| P11 | Modellstunden 1–30 with the slow (warrior) and fast (hunter) class factor | not worse than the start | DR 22c §B.4 |
| G1 | linter errors per combination | 0 | DR 22d |
| G2 | the simulator plays every combination to level 30 without getting stuck | 0 | DR 22d |
| G3 | quest XP at the planned level / XP of the level band 1–10, 11–20, 21–30 | ≥ 0.80 | plan Welle 6, DR 22d |
| G4 | best minus own coverage per band | ≤ 0.10 | plan Welle 6, DR 22d |
| G5 | most accepted quests / own per band (also 1–20) | ≤ 1.25 | plan Welle 6, DR 22d |
| G6 | walked yards per quest XP / median per band | ≤ 1.20 | plan Welle 6, DR 22d |
| G7 | level on arrival at the first core block against its first level | ≤ 1 | DR 22d |
| G8 | Modellstunden of a class insert; of all inserts of a combination | ≤ 0.17; ≤ 0.5 | DR 22d |
| G9 | trainer visits on the way, never back | not checkable: no `train` steps yet | DR 22d |
| G10 | (Modellstunden 1–30 − best of the class) / best of the class | ≤ 0.10 | DR 22d |
| G11 | share of route quests whose race and class condition comes from our own measurement; applies to a route with a module labelled `stabil` | 1.0 before label `stabil` | DR 22d |
| G12 | G1–G10 for the two Skyborne races separately | as G1–G10 | DR 22d |
| R01–R35 | the rules of the DR 22a catalogue that the route data can show; the others are listed with the reason; R18z reports grinds next to quests the route cannot take there or that are not worth it | 0 for hard rules (H), report for soft ones (W) | DR 22a |

Level bands follow the planned level (`lv`) of a step. A band's XP is the XP to level through it: levels 1–10, 11–20 and 21–29 (the route ends on reaching 30).

## Corrections of the measurement in Welle 6b

Six metrics measured more than their rule says. Each correction follows the wording of the rule in DR 22a/22c (brain chapter 21) and is applied to the routes before and after the optimizer alike; the baseline below is measured again with the corrected tool. No limit value changed.

| Id | Rule (DR 22a/22c) | Before | Now |
| --- | --- | --- | --- |
| R04 | "Steht nach einer Abgabe am selben NPC eine Folgequest **bereit**, wird sie im selben Schritt angenommen" | every later accept of a follow-up at the same NPC counted, also when the character could not take it at the turn-in (level, log) | counts only follow-ups available right after the turn-in (level and quest log after the turn-in XP, prerequisites) |
| R05 | "kein **späterer Besuch** eines NPC nur zur Annahme einer Quest, die beim ersten Besuch verfügbar war" | an accept in any later step at the same NPC counted, also in the next step without leaving | counts an accept after the character went away from the NPC (a visit ends 400 yd away, as P5) |
| P6 | "keine **lohnende** passierte Quest ungenommen (§4.3)" | every available quest whose giver stood within 500 yd counted | counts quests the route can take where it passes (giver in the zone the character is in, all zones of the quest still ahead) and that are worth their extra time (§4.3: XP per second of detour and work at least the route's rate, half of it below 60 s of detour); the others are reported as P6z (needs a zone the route does not visit again) and P6n (not worth it) |
| R18 | "Kein Grind-Schritt, solange in erreichbarer Nähe **passende** Quests offen sind" | quests available at the level *after* the grind counted, so a quest the grind itself opened was a breach | level before the grind; only quests the route can take there and that are worth it (as P6); the rest is reported as R18z |
| P4 | "Strecke nur für eine Quest" | the walk into a new zone counted as a trip for the first quest there | legs inside one zone (the walk into a zone belongs to the travel step, as for P4yd) |
| G11 | "1,0 vor Etikett stabil" | applied to every route | applies to a route with a module labelled `stabil`; no module is (R33), so G11 is open |

## Gate (Welle 6b)

The CI job "Route quality" runs `python3 -m tools.routekit metrics --check`. It fails when two runs differ (P1), when a parameter has no source, and on every breach by a combination of

- a limit (P2, P4, P5w, P6, P6l, P7, P8, G1–G8, G10, G11),
- a guard against the start route (P3 in every one of the 16 parameter draws, P4b, P5b, P9b, P11b),
- a hard rule of DR 22a (R01, R02, R04–R07, R09–R13, R17–R19, R22, R23, R26, R28, R30, R33),
- the model check (XP per Modellstunde 1–20 inside the band of DR 22b),

that no entry of `data/plan/route-exceptions.toml` covers. An entry names the metric, the mode, the combinations and the value it allows, measured on the routes of this file (`max` for a metric that must stay low, `min` for one that must stay high), with its reason and measurement. A route that gets worse than the measured value, or a combination the entry does not name, breaks the job. Guards have no exceptions. Counter-check: `tools/tests/test_metrics.py` puts the first two core blocks of the Horde speed route in the wrong order; the job then fails.

## Before and after

Vorher: the start route (origin/main 65900c1), nachher: the routes of this branch; both measured with the tool of Welle 6b and the parameters in `data/plan/params.toml`. The worst combination per metric and mode; "nachher erfüllt" counts the combinations inside the limit (Bericht: no limit; offen: not checkable yet).

### Modellstunden 1–30 je Fraktion

| Modus | Fraktion | vorher schnellste / Median / langsamste | nachher schnellste / Median / langsamste | Median 1–20 vorher / nachher |
| --- | --- | --- | --- | --- |
| speed | Alliance | 21.12 / 24.76 / 26.87 | 19.83 / 22.93 / 25.14 | 10.23 / 8.97 |
| speed | Horde | 20.84 / 24.70 / 27.67 | 20.19 / 23.32 / 26.14 | 10.38 / 8.84 |
| explorer | Alliance | 20.73 / 25.09 / 26.10 | 19.38 / 22.36 / 24.46 | 10.02 / 8.73 |
| explorer | Horde | 20.49 / 24.24 / 28.51 | 19.81 / 22.82 / 25.50 | 9.90 / 8.57 |

### Kennzahlen

| Id | Kennzahl | Modus | schlechteste vorher | schlechteste nachher | Grenzwert | nachher erfüllt (von 56) |
| --- | --- | --- | --- | --- | --- | --- |
| h30 | Modellstunden 1–30 | speed | 27.67 | 26.14 | – | Bericht |
| h30 | Modellstunden 1–30 | explorer | 28.51 | 25.50 | – | Bericht |
| xph | XP je Modellstunde 1–20 (Prüfband 22b) | speed | 12765 | 16368 | 8150–32800 | 56 |
| xph | XP je Modellstunde 1–20 (Prüfband 22b) | explorer | 12519 | 16966 | 8150–32800 | 56 |
| P2 | P2 kleinste Deckung eines Moduls (Quest- + Ziel-Kill-XP) | speed | 0.22 | 0.10 | ≥ 0.90 | 0 |
| P2 | P2 kleinste Deckung eines Moduls (Quest- + Ziel-Kill-XP) | explorer | 0.21 | 0.11 | ≥ 0.90 | 0 |
| P2g | P2 größter Grind-Anteil einer Stufe | speed | 0.99 | 0.99 | ≤ 0.10 | 0 |
| P2g | P2 größter Grind-Anteil einer Stufe | explorer | 0.99 | 0.99 | ≤ 0.10 | 0 |
| P3 | P3 Ziehungen schlechter als Startlösung (von 16) | speed | 0 | 0 | ≤ Startlösung | 56 |
| P3 | P3 Ziehungen schlechter als Startlösung (von 16) | explorer | 0 | 2 | ≤ Startlösung | 52 |
| P3h | P3 Modellstunden 1–30, längste der 16 Ziehungen | speed | 37.69 | 35.88 | – | Bericht |
| P3h | P3 Modellstunden 1–30, längste der 16 Ziehungen | explorer | 37.03 | 34.70 | – | Bericht |
| P4 | P4 lange Einzelquest-Wege im Gebiet (über 0,05 Modellstunden, unter ½ Routenrate) | speed | 14 | 5 | ≤ 0 | 15 |
| P4 | P4 lange Einzelquest-Wege im Gebiet (über 0,05 Modellstunden, unter ½ Routenrate) | explorer | 15 | 5 | ≤ 0 | 15 |
| P4b | P4 lange Einzelquest-Wege mehr als Startlösung | speed | 0 | -1 | ≤ Startlösung | 56 |
| P4b | P4 lange Einzelquest-Wege mehr als Startlösung | explorer | 0 | 0 | ≤ Startlösung | 56 |
| P4yd | P4 längster Fußweg im selben Gebiet (yd) | speed | 4257 | 3704 | – | Bericht |
| P4yd | P4 längster Fußweg im selben Gebiet (yd) | explorer | 4257 | 3695 | – | Bericht |
| P5 | P5 vermeidbare Rückkehren | speed | 27 | 25 | – | Bericht |
| P5 | P5 vermeidbare Rückkehren | explorer | 39 | 31 | – | Bericht |
| P5b | P5 vermeidbare Rückkehren mehr als Startlösung | speed | 0 | 0 | ≤ Startlösung | 56 |
| P5b | P5 vermeidbare Rückkehren mehr als Startlösung | explorer | 0 | -1 | ≤ Startlösung | 56 |
| P5w | P5 verschwendete Wege | speed | 14 | 6 | ≤ 0 | 0 |
| P5w | P5 verschwendete Wege | explorer | 15 | 6 | ≤ 0 | 0 |
| P6 | P6 vorbeigelaufen, nie genommen | speed | 12 | 9 | ≤ 0 | 0 |
| P6 | P6 vorbeigelaufen, nie genommen | explorer | 14 | 15 | ≤ 0 | 0 |
| P6l | P6 vorbeigelaufen, erst später genommen | speed | 19 | 8 | ≤ 0 | 0 |
| P6l | P6 vorbeigelaufen, erst später genommen | explorer | 21 | 15 | ≤ 0 | 0 |
| P6z | P6 vorbeigelaufen, braucht ein Gebiet, das die Route nicht mehr besucht (Wächter P9) | speed | 61 | 20 | – | Bericht |
| P6z | P6 vorbeigelaufen, braucht ein Gebiet, das die Route nicht mehr besucht (Wächter P9) | explorer | 80 | 28 | – | Bericht |
| P6n | P6 vorbeigelaufen, lohnt nicht (XP je Zusatzsekunde unter der Routenrate) | speed | 12 | 11 | – | Bericht |
| P6n | P6 vorbeigelaufen, lohnt nicht (XP je Zusatzsekunde unter der Routenrate) | explorer | 17 | 17 | – | Bericht |
| P7 | P7 Questlog-Spitze | speed | 14 | 17 | ≤ 35 | 56 |
| P7 | P7 Questlog-Spitze | explorer | 19 | 18 | ≤ 35 | 56 |
| P7o | P7 angenommen und nie abgegeben | speed | 0 | 0 | ≤ 0 | 56 |
| P7o | P7 angenommen und nie abgegeben | explorer | 0 | 0 | ≤ 0 | 56 |
| P8 | P8 Annahme über Stufe + 2, graue Abgabe, Ausreißer | speed | 4 | 0 | ≤ 0 | 56 |
| P8 | P8 Annahme über Stufe + 2, graue Abgabe, Ausreißer | explorer | 4 | 0 | ≤ 0 | 56 |
| P9 | P9 Gebietswechsel | speed | 17 | 9 | – | Bericht |
| P9 | P9 Gebietswechsel | explorer | 21 | 9 | – | Bericht |
| P9b | P9 Gebietswechsel mehr als Startlösung | speed | 0 | 0 | ≤ Startlösung | 56 |
| P9b | P9 Gebietswechsel mehr als Startlösung | explorer | 0 | 0 | ≤ Startlösung | 56 |
| P9q | P9 Quests je Gebietsbesuch | speed | 9.31 | 18.14 | – | Bericht |
| P9q | P9 Quests je Gebietsbesuch | explorer | 10.16 | 15.78 | – | Bericht |
| P11 | P11 Modellstunden 1–30 Profil langsam (Krieger-Faktor) | speed | 29.60 | 26.16 | – | Bericht |
| P11 | P11 Modellstunden 1–30 Profil langsam (Krieger-Faktor) | explorer | 30.52 | 25.51 | – | Bericht |
| P11f | P11 Modellstunden 1–30 Profil schnell (Jäger-Faktor) | speed | 24.50 | 20.96 | – | Bericht |
| P11f | P11 Modellstunden 1–30 Profil schnell (Jäger-Faktor) | explorer | 25.83 | 20.60 | – | Bericht |
| P11b | P11 Mehrstunden gegen Startlösung, Profil langsam oder schnell | speed | 0.00 | -0.45 | ≤ Startlösung | 56 |
| P11b | P11 Mehrstunden gegen Startlösung, Profil langsam oder schnell | explorer | 0.00 | -0.21 | ≤ Startlösung | 56 |
| G1 | G1 Linter-Fehler | speed | 0 | 0 | ≤ 0 | 56 |
| G1 | G1 Linter-Fehler | explorer | 0 | 0 | ≤ 0 | 56 |
| G2 | G2 Hänger im Simulator | speed | 0 | 0 | ≤ 0 | 56 |
| G2 | G2 Hänger im Simulator | explorer | 0 | 0 | ≤ 0 | 56 |
| G3 | G3 kleinste Quest-XP-Deckung eines Bands | speed | 0.23 | 0.14 | ≥ 0.80 | 0 |
| G3 | G3 kleinste Quest-XP-Deckung eines Bands | explorer | 0.27 | 0.17 | ≥ 0.80 | 0 |
| G4 | G4 Abstand zur besten Deckung im Band | speed | 0.35 | 0.20 | ≤ 0.10 | 18 |
| G4 | G4 Abstand zur besten Deckung im Band | explorer | 0.49 | 0.23 | ≤ 0.10 | 17 |
| G5 | G5 Questzahl: meiste / eigene je Band | speed | 1.96 | 1.79 | ≤ 1.25 | 28 |
| G5 | G5 Questzahl: meiste / eigene je Band | explorer | 1.96 | 1.77 | ≤ 1.25 | 28 |
| G6 | G6 Laufweg je Quest-XP / Median je Band | speed | 2.01 | 1.51 | ≤ 1.20 | 52 |
| G6 | G6 Laufweg je Quest-XP / Median je Band | explorer | 2.44 | 1.44 | ≤ 1.20 | 52 |
| G7 | G7 Abweichung der Ankunftsstufe vom Beginn des ersten Kernblocks | speed | 3.35 | 0.96 | ≤ 1.00 | 56 |
| G7 | G7 Abweichung der Ankunftsstufe vom Beginn des ersten Kernblocks | explorer | 4.87 | 0.99 | ≤ 1.00 | 56 |
| G8 | G8 längster Klasseneinschub (Modellstunden) | speed | 2.42 | 0.12 | ≤ 0.17 | 56 |
| G8 | G8 längster Klasseneinschub (Modellstunden) | explorer | 2.20 | 0.14 | ≤ 0.17 | 56 |
| G8s | G8 Klasseneinschübe gesamt (Modellstunden) | speed | 3.92 | 0.12 | ≤ 0.50 | 56 |
| G8s | G8 Klasseneinschübe gesamt (Modellstunden) | explorer | 4.97 | 0.14 | ≤ 0.50 | 56 |
| G9 | G9 train-Schritte auf der Route (Lehrerwege prüfbar ab einem) | speed | 0 | 0 | – | offen |
| G9 | G9 train-Schritte auf der Route (Lehrerwege prüfbar ab einem) | explorer | 0 | 0 | – | offen |
| G10 | G10 Rückstand zur besten Route der Klasse | speed | 0.11 | 0.06 | ≤ 0.10 | 56 |
| G10 | G10 Rückstand zur besten Route der Klasse | explorer | 0.12 | 0.06 | ≤ 0.10 | 56 |
| G11 | G11 Anteil Routenquests mit eigener Volk-/Klassen-Messung (gilt ab Etikett stabil) | speed | – | – | ≥ 1.00 | Bericht |
| G11 | G11 Anteil Routenquests mit eigener Volk-/Klassen-Messung (gilt ab Etikett stabil) | explorer | – | – | ≥ 1.00 | Bericht |
| R01 | R01 Abgabe über Questlevel + 5 (H) | speed | 4 | 0 | ≤ 0 | 56 |
| R01 | R01 Abgabe über Questlevel + 5 (H) | explorer | 9 | 0 | ≤ 0 | 56 |
| R02 | R02 Abgabe ab Questlevel + 10 (H) | speed | 1 | 0 | ≤ 0 | 56 |
| R02 | R02 Abgabe ab Questlevel + 10 (H) | explorer | 1 | 0 | ≤ 0 | 56 |
| R04 | R04 Folgequest am selben NPC nicht im selben Schritt (H) | speed | 18 | 19 | ≤ 0 | 0 |
| R04 | R04 Folgequest am selben NPC nicht im selben Schritt (H) | explorer | 20 | 19 | ≤ 0 | 0 |
| R05 | R05 späterer Besuch nur zur Annahme (H) | speed | 12 | 3 | ≤ 0 | 32 |
| R05 | R05 späterer Besuch nur zur Annahme (H) | explorer | 16 | 4 | ≤ 0 | 28 |
| R06 | R06 aktives Ziel passiert, später eigener Besuch (H) | speed | 1 | 4 | ≤ 0 | 0 |
| R06 | R06 aktives Ziel passiert, später eigener Besuch (H) | explorer | 1 | 4 | ≤ 0 | 0 |
| R07 | R07 Zwischenabgabe zwischen zwei nahen Zielen (H) | speed | 1 | 1 | ≤ 0 | 50 |
| R07 | R07 Zwischenabgabe zwischen zwei nahen Zielen (H) | explorer | 1 | 1 | ≤ 0 | 50 |
| R09 | R09 Rückkehr ins Gebiet mit weniger als 3 Quests (H) | speed | 7 | 0 | ≤ 0 | 56 |
| R09 | R09 Rückkehr ins Gebiet mit weniger als 3 Quests (H) | explorer | 7 | 0 | ≤ 0 | 56 |
| R10 | R10 Ruhestein ohne Bedingungen (H) | speed | 0 | 0 | ≤ 0 | 56 |
| R10 | R10 Ruhestein ohne Bedingungen (H) | explorer | 0 | 0 | ≤ 0 | 56 |
| R11 | R11 Bindung ohne späteren Besuch (H) | speed | 0 | 0 | ≤ 0 | 56 |
| R11 | R11 Bindung ohne späteren Besuch (H) | explorer | 0 | 0 | ≤ 0 | 56 |
| R12 | R12 Ruhestein vor Ablauf der Abklingzeit (H) | speed | 0 | 0 | ≤ 0 | 56 |
| R12 | R12 Ruhestein vor Ablauf der Abklingzeit (H) | explorer | 0 | 0 | ≤ 0 | 56 |
| R13 | R13 unbekannter Flugmeister passiert (H) | speed | 10 | 5 | ≤ 0 | 18 |
| R13 | R13 unbekannter Flugmeister passiert (H) | explorer | 10 | 2 | ≤ 0 | 18 |
| R17 | R17 Grind-Schritt ohne Ort (H) | speed | 0 | 0 | ≤ 0 | 56 |
| R17 | R17 Grind-Schritt ohne Ort (H) | explorer | 0 | 0 | ≤ 0 | 56 |
| R18 | R18 Grind trotz annehmbarer Quest in 500 yd (H) | speed | 3 | 4 | ≤ 0 | 0 |
| R18 | R18 Grind trotz annehmbarer Quest in 500 yd (H) | explorer | 4 | 3 | ≤ 0 | 7 |
| R18z | R18 Grind neben Quests, die ein Gebiet außerhalb der Route brauchen oder nicht lohnen | speed | 9 | 7 | – | Bericht |
| R18z | R18 Grind neben Quests, die ein Gebiet außerhalb der Route brauchen oder nicht lohnen | explorer | 7 | 6 | – | Bericht |
| R19 | R19 Grind ohne vorherige Ankündigung (H) | speed | 17 | 3 | ≤ 0 | 6 |
| R19 | R19 Grind ohne vorherige Ankündigung (H) | explorer | 14 | 0 | ≤ 0 | 56 |
| R20 | R20 Eskorten-/Ereignisquests im Speed-Pfad (W) | speed | 8 | 8 | – | Bericht |
| R20 | R20 Eskorten-/Ereignisquests im Speed-Pfad (W) | explorer | 8 | 8 | – | Bericht |
| R21 | R21 Sammelquests ohne Abbruchregel (W) | speed | 113 | 107 | – | Bericht |
| R21 | R21 Sammelquests ohne Abbruchregel (W) | explorer | 133 | 116 | – | Bericht |
| R22 | R22 Gruppen-/Elitequests im Solo-Pfad (H) | speed | 0 | 0 | ≤ 0 | 56 |
| R22 | R22 Gruppen-/Elitequests im Solo-Pfad (H) | explorer | 0 | 0 | ≤ 0 | 56 |
| R23 | R23 nicht verfügbare Quest (H) | speed | 0 | 0 | ≤ 0 | 56 |
| R23 | R23 nicht verfügbare Quest (H) | explorer | 0 | 0 | ≤ 0 | 56 |
| R26 | R26 Hauptstadtbesuch ohne Grund (H) | speed | 3 | 0 | ≤ 0 | 56 |
| R26 | R26 Hauptstadtbesuch ohne Grund (H) | explorer | 3 | 0 | ≤ 0 | 56 |
| R27 | R27 Questziel mehr als 2 Stufen über dem Spieler (W) | speed | 0 | 0 | – | Bericht |
| R27 | R27 Questziel mehr als 2 Stufen über dem Spieler (W) | explorer | 0 | 0 | – | Bericht |
| R28 | R28 Dungeonquest im Speed-Pfad (H) | speed | 0 | 0 | ≤ 0 | 56 |
| R28 | R28 Dungeonquest im Speed-Pfad (H) | explorer | 0 | 0 | ≤ 0 | 56 |
| R30 | R30 Questlog über 40 (H) | speed | 0 | 0 | ≤ 0 | 56 |
| R30 | R30 Questlog über 40 (H) | explorer | 0 | 0 | ≤ 0 | 56 |
| R31 | R31 Quest am Ende noch im Log (W) | speed | 0 | 0 | – | Bericht |
| R31 | R31 Quest am Ende noch im Log (W) | explorer | 0 | 0 | – | Bericht |
| R33 | R33 Etikett stabil ohne Messung (H) | speed | 0 | 0 | ≤ 0 | 56 |
| R33 | R33 Etikett stabil ohne Messung (H) | explorer | 0 | 0 | ≤ 0 | 56 |

## Bounds of the data under the zone-change guard

`python3 -m tools.routekit bounds` (`tools/routekit/bounds.py`) measures what no route can exceed. Guard P9 lets the core change zones as often as the start route of the combination with the fewest changes: 7 for the Alliance, 6 for the Horde. The quests that lie inside one core zone (giver, objectives, ender; quest level 9 to 31; quest XP plus objective kills at the quest's level) of the richest zones the guard allows give, all of them taken (no level window, no quest log, no time), less XP than levels 11 to 30 need; and quest XP alone cannot fill 80 % of the band 21–30 even when every quest of these zones and the start zones is picked by its share of quest XP:

```
Alliance: Wächter P9 erlaubt 7 Kerngebiete; reichste: Wetlands 96288, Duskwood 85475, Ashenvale 74894, Darkshore 70398, Redridge Mountains 46616, Westfall 44935, Loch Modan 32854
  alle Quests dieser Gebiete (Quest- + Ziel-Kill-XP): 451461; nötig von Stufe 11 bis 30: 463800 (0.97)
  G3-Schranke 1-10: höchstens 1.015 mit allen Quests der Fraktion, 1.001 in Start- und P9-Gebieten
  G3-Schranke 11-20: höchstens 0.945 mit allen Quests der Fraktion, 0.904 in Start- und P9-Gebieten
  G3-Schranke 21-30: höchstens 0.937 mit allen Quests der Fraktion, 0.793 in Start- und P9-Gebieten
Horde: Wächter P9 erlaubt 6 Kerngebiete; reichste: The Barrens 159355, Hillsbrad Foothills 59522, Thousand Needles 50240, Stonetalon Mountains 44422, Ashenvale 42014, Silverpine Forest 38348
  alle Quests dieser Gebiete (Quest- + Ziel-Kill-XP): 393901; nötig von Stufe 11 bis 30: 463800 (0.85)
  G3-Schranke 1-10: höchstens 1.012 mit allen Quests der Fraktion, 0.982 in Start- und P9-Gebieten
  G3-Schranke 11-20: höchstens 0.931 mit allen Quests der Fraktion, 0.863 in Start- und P9-Gebieten
  G3-Schranke 21-30: höchstens 0.816 mit allen Quests der Fraktion, 0.700 in Start- und P9-Gebieten
```

So with P9 hard, every route grinds part of the way to 30 (P2, P2g) and stays below 0.80 quest XP in band 21–30 (G3). The bounds for the whole faction (all zones) lie above 0.80: a route with more zone changes could reach G3 in every band. Raising the P9 budget is a decision about the guard, not taken here.

## The optimizer (Welle 6b)

`python3 -m tools.routekit build` (`tools/routekit/optimize.py`) builds every module from the model instead of the earlier nearest-action greed; method after brain chapter 21 §4 and report DR 22c:

1. **Start modules**, one per start zone: construction with the worth test, then large neighbourhood search (destroy and repair, relocate, or-opt, 2-opt, swap), Held-Karp at hubs, folding at the same NPC; quests of other races and classes go in where they pay. Every combination of the faction arrives in one window of one level at the first core block (G7); a combination that runs out of quests moves the window down (Horde and Alliance: 10.0 to 11.0).
2. **Core route**: a beam search over zone visits, as many as the start route of the combination with the fewest zone changes made (guard P9: Alliance 7, Horde 6). A visit may grind to open the next quests of its zone (announced `xp` step). The order inside a visit is searched with the brain's objective J (model time, grind weighted, 900 s per avoidable return); quests whose actions lie in two visited zones are carried.
3. **Repair rounds** play the emitted route of all 28 combinations of the faction in the simulator and read the broken rules from `tools/routekit/metrics.py` (the CI code): content first (passed quests worth it, long low-value trips), then a polish of the walking order with the return weight, then the order rules (R04, R05 with an early accept for the combinations already at a quest's level, P6, R06, R07, P5, flight paths R13, grind announcements R17/R19). The round with the fewest breaches is kept, guards weigh most.
4. **Weights**: the grind weights (w_g, w_over) are policy; the build tries `opt.weight_settings` from most quests to pure model time and keeps the first plan that meets the guards P3, P4b, P5b, P9b and P11b against the start route.
5. **Explorer** = speed route plus the new Forever quests with at most 180 model seconds of detour per module (owner point 2); finds on the way come from `ns.Explore` in the client.

Every search counts tries and rounds, never seconds; the same input gives the same route (P1). Runtime of the build on 2026-11-02 (MacBook, one process per faction, Python 3.11): Alliance two weight settings, 300 s and 147 s, plus the explorer 57 s (about 8.4 minutes); Horde five settings, 337, 296, 190, 183 and 266 s, plus the explorer 40 s (about 22 minutes). The two factions run in parallel with `build --faction`. `metrics --check` takes 8 s.

## Comparison with RestedXP Forever 1–20/22 (methodology only, FD-1101)

RestedXP's Forever guides (github.com/RestedXP/RXPGuides, `Guides/forever`, commit 1a7324e of 2026-11-01, licence CC BY-NC-SA 4.0) were read only to count; no quest, order or text went into Pathmark (decision FD-1101). Counted per combination with the guides' own race and class filters: distinct accepted quests up to the guide's end level, steps, steps with a parallel objective (`#completewith`), hearthstone (`.hs`), binding (`.home`), flight paths learnt (`.fp`), flights (`.fly`), trainer visits (`.trainer`/`.train`), level targets (`.xp`) and the zone sections. Our figures come from the simulator on the speed route up to the same level. Counter script: `rxp_count.py` in the session scratchpad of 2026-11-02 (not part of the repository, the guides are not ours).

| Combination | RestedXP: quests / steps / parallel / hs / fp / trainer / xp | RestedXP sections | Pathmark speed: quests / quest steps / objectives next to each other / fp / xp | Pathmark zones | quests in both |
| --- | --- | --- | --- | --- | --- |
| Orc Warrior 1–22 | 165 / 706 / 205 (29 %) / 5 / 5 / 41 / 28 | [1-6 Durotar, 6-10 Durotar, 10-12 Durotar, 10-12 Tirisfal (Orc/Troll), 12-17 The Barrens, 17-22 Stonetalon/Barrens/Ashenvale] | 111 / 255 / 41 % / 5 / 13 | Durotar > Silverpine Forest > The Barrens > Hillsbrad Foothills | 76 |
| Undead Warrior 1–22 | 191 / 746 / 215 (29 %) / 7 / 7 / 37 / 45 | [1-6 Tirisfal Glades, 6-12 Tirisfal Glades, 12-14 Silverpine Forest, 12-17 The Barrens, 17-22 Stonetalon/Barrens/Ashenvale] | 119 / 267 / 42 % / 5 / 10 | Tirisfal Glades > Silverpine Forest > The Barrens > Hillsbrad Foothills | 95 |
| Tauren Warrior 1–22 | 165 / 650 / 196 (30 %) / 6 / 5 / 31 / 36 | [1-6 Mulgore, 6-12 Mulgore, 12-17 The Barrens, 17-22 Stonetalon/Barrens/Ashenvale] | 117 / 260 / 38 % / 5 / 5 | Mulgore > Silverpine Forest > The Barrens > Hillsbrad Foothills | 87 |
| Human Warrior 1–21 | 212 / 968 / 291 (30 %) / 6 / 7 / 49 / 54 | [1-6 Northshire, 6-11 Elwynn Forest, 11-13 Loch Modan, 13-15 Westfall, 14-16 Darkshore, 15-16 Loch Modan, 16-19 Darkshore, 19-20 Redridge, 20-21 Darkshore/Ashenvale] | 153 / 339 / 46 % / 0 / 5 | Elwynn Forest > Darkshore > Westfall > The Barrens > Darkshore > Redridge Mountains | 105 |
| Dwarf Warrior 1–21 | 206 / 940 / 272 (29 %) / 8 / 7 / 31 / 48 | [1-5 Coldridge Valley, 5-11 Dun Morogh, 11-12 Elwynn (Dwarf/Gnome), 12-14 Loch Modan (Dwarf/Gnome), 13-15 Westfall, 14-16 Darkshore, 15-16 Loch Modan, 16-19 Darkshore, 19-20 Redridge, 20-21 Darkshore/Ashenvale] | 129 / 299 / 47 % / 0 / 4 | Dun Morogh > Darkshore > Westfall > The Barrens > Darkshore | 86 |
| NightElf Warrior 1–21 | 176 / 730 / 186 (25 %) / 7 / 3 / 18 / 36 | [1-6 Shadowglen, 6-11 Teldrassil, 14-16 Darkshore, 15-16 Loch Modan, 16-19 Darkshore, 19-20 Redridge, 20-21 Darkshore/Ashenvale] | 135 / 301 / 49 % / 0 / 5 | Teldrassil > Darkshore > Westfall > The Barrens > Darkshore | 84 |

What the comparison shows (methodology, not content):

- **Zone changes.** RestedXP changes zone far more often than the guard P9 allows us: the Human guide alone has nine sections to level 21 with three visits to Darkshore and two to Loch Modan; the Orc guide sends Orcs and Trolls to Tirisfal at 10–12 before the Barrens. Our core may change zones only 7 (Alliance) or 6 (Horde) times up to level 30, so it covers fewer quests after level 20 and grinds the rest (see "Bounds" above). This is the main difference and the reason behind the exceptions for P2, P2g and G3.
- **Parallel objectives.** About 30 % of RestedXP's steps carry `#completewith` (an objective worked along the way). Our format has no parallel objective; the nearest measure is how often two objectives next to each other (150 yd) are worked one after the other.
- **Plan steps.** RestedXP uses the hearthstone, binds it, learns flight paths, flies and sends the player to the class trainer (31–49 times to level 21/22). We take flight paths on the way and announce every grind with a level target; hearthstone, binding and trainer steps need innkeeper and trainer positions that are not imported yet.
- **Quest count.** Within the same levels the counts are of the same order; the overlap column counts quests both routes take.

## Open after Welle 6b (state of this branch)

The gate is not green. What breaks it, measured on the routes of this file:

1. **Explorer guard P3 against the old explorer route** (4 combinations: SKYBORNE_A warrior, SKYBORNE_H warrior, hunter and shaman, slower in 1 or 2 of the 16 draws; P11b holds). The owner's explorer is the speed route plus finds (owner point 2). The old explorer start route took breadcrumbs and quests with unconfirmed prerequisites and was a median 0.45 Modellstunden faster than the old speed route (range −1.02 to +1.09). Measured: the new speed route itself is slower than the old explorer route in at least one of the 16 parameter draws for 19 combinations (against the old speed route: for none). So "explorer = speed route plus finds" cannot hold the explorer guard against the old explorer route; which reference the explorer guard uses is a decision about the guard.
2. **Hard rules and craft limits** (R04, R05, R06, R07, R13, R18, R19, P4, P5w, P6, P6l, G6): the repair rounds reduce them but do not reach 0; no measurement shows them to be unavoidable, so they carry no exception. Counts per combination in the tables below.
3. **Plan steps `train`, `hs`, `sethome`**: the runtime knows them; the routes do not place them yet (trainer and innkeeper positions not imported; Polestar forever-db has them in `npc.jsonl` and `spawn.jsonl`). R25, G9 and R10–R12 stay open or trivially met.
4. **Alternative modules for the switch points of Welle 7** (`alts`) are not built yet.
5. **Specs that follow the old route structure** (Welle 5d M9, Welle 7 replanning and `ui_replan`, the Alliance Deadmines hint, prerequisites from player data on the explorer route) need scenarios on the new routes.

## Cross-checks of the tool

The baseline agrees with the measurements taken before the tool existed:

- accepted quests per band equal `python3 -m tools.routekit stats` for every combination (test `test_quest_counts_agree_with_routekit_stats`); G5 gives 144/99 = 1.45 for 1–20 and 64/37 = 1.73 for 21–30 as in DR 22d;
- the longest walk in one zone is 4,257 yd in the warrior inserts `a-*-class-*-warrior-07`, as measured for the requirements catalogue (A04);
- quest XP alone covers 13 to 67 % of the XP of a core block (P2 without kill XP), against 13 to 69 % measured from the module files (that count included quests of other classes);
- every combination gains 12,519 to 20,086 XP per Modellstunde for levels 1–20 (speed 12,765 to 19,842), inside the model check band of 8,150 to 32,800.

## Reproduce

```sh
python3 -m tools.routekit metrics                       # table on the console
python3 -m tools.routekit metrics --md report.md --json report.json
python3 -m tools.routekit metrics --write-baseline      # store the current routes as the start route
```

`data/plan/metrics-baseline.json` stores the counters at level 30 of every combination of the start route. P3, P4, P5, P9 and P11 compare against it with the current parameters, so a changed parameter prices both routes alike.

The two sections below are the tool's Markdown output of 2026-11-02, with German labels like the linter's messages.

## Nachher 2026-11-02: routes of Welle 6b (route optimizer)

Modellstunden aus `tools/routekit/sim.py` mit den Parametern aus `data/plan/params.toml`, keine Vorhersage echter Spielzeit. Status: erfüllt oder verletzt (Zahl der Kombinationen) gegen den Grenzwert aus `data/plan/params.toml`; Bericht ohne Grenzwert; offen, wenn nicht prüfbar. Bänder 1–10, 11–20, 21–30 nach der geplanten Stufe des Schritts. Seit Welle 6b bricht jede Überschreitung, die keine gemessene Ausnahme in `data/plan/route-exceptions.toml` deckt, den CI-Job „Route quality“ ab.

P1 Determinismus: Prüfsumme `63755ce2fde753e21137ec01ffcc076b34586dac1fae054fdaf776c581c05da7`, zweiter Lauf gleich.

### Modellstunden 1–30 je Fraktion

| Modus | Fraktion | schnellste | Median | langsamste | Median 1–20 |
| --- | --- | --- | --- | --- | --- |
| speed | Alliance | 19.83 (SKYBORNE_A HUNTER) | 22.93 | 25.14 (GNOME WARRIOR) | 8.97 |
| speed | Horde | 20.19 (SKYBORNE_H HUNTER) | 23.32 | 26.14 (TAUREN WARRIOR) | 8.84 |
| explorer | Alliance | 19.38 (SKYBORNE_A HUNTER) | 22.36 | 24.46 (GNOME WARRIOR) | 8.73 |
| explorer | Horde | 19.81 (SKYBORNE_H HUNTER) | 22.82 | 25.50 (TAUREN WARRIOR) | 8.57 |

### Kennzahlen mit den fünf schlechtesten Kombinationen

| Id | Modus | Kennzahl | Grenzwert | Status | schlechteste 5 |
| --- | --- | --- | --- | --- | --- |
| h30 | speed | Modellstunden 1–30 | – | Bericht | TAUREN WARRIOR 26.14; ORC WARRIOR 25.53; TROLL WARRIOR 25.53; UNDEAD WARRIOR 25.46; SKYBORNE_H WARRIOR 25.32 |
| h30 | explorer | Modellstunden 1–30 | – | Bericht | TAUREN WARRIOR 25.50; ORC WARRIOR 24.97; TROLL WARRIOR 24.97; UNDEAD WARRIOR 24.83; SKYBORNE_H WARRIOR 24.74 |
| xph | speed | XP je Modellstunde 1–20 (Prüfband 22b) | 8150–32800 | erfüllt | TAUREN WARRIOR 16368; ORC WARRIOR 17405; TROLL WARRIOR 17405; UNDEAD WARRIOR 17534; DWARF WARRIOR 17564 |
| xph | explorer | XP je Modellstunde 1–20 (Prüfband 22b) | 8150–32800 | erfüllt | TAUREN WARRIOR 16966; ORC WARRIOR 17929; TROLL WARRIOR 17929; DWARF WARRIOR 18093; GNOME WARRIOR 18093 |
| P2 | speed | P2 kleinste Deckung eines Moduls (Quest- + Ziel-Kill-XP) | ≥ 0.90 | verletzt (56) | DWARF HUNTER 0.10; DWARF PALADIN 0.10; DWARF PRIEST 0.10; DWARF ROGUE 0.10; DWARF SHAMAN 0.10 |
| P2 | explorer | P2 kleinste Deckung eines Moduls (Quest- + Ziel-Kill-XP) | ≥ 0.90 | verletzt (56) | DWARF WARRIOR 0.11; GNOME WARRIOR 0.11; HUMAN WARRIOR 0.11; NIGHTELF WARRIOR 0.11; SKYBORNE_A WARRIOR 0.11 |
| P2g | speed | P2 größter Grind-Anteil einer Stufe | ≤ 0.10 | verletzt (56) | DWARF WARRIOR 0.99; GNOME WARRIOR 0.99; HUMAN WARRIOR 0.99; NIGHTELF WARRIOR 0.99; ORC WARRIOR 0.99 |
| P2g | explorer | P2 größter Grind-Anteil einer Stufe | ≤ 0.10 | verletzt (56) | DWARF WARRIOR 0.99; GNOME WARRIOR 0.99; HUMAN WARRIOR 0.99; NIGHTELF WARRIOR 0.99; ORC WARRIOR 0.99 |
| P3 | speed | P3 Ziehungen schlechter als Startlösung (von 16) | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P3 | explorer | P3 Ziehungen schlechter als Startlösung (von 16) | ≤ Startlösung | verletzt (4) | SKYBORNE_A WARRIOR 2; SKYBORNE_H SHAMAN 2; SKYBORNE_H WARRIOR 2; SKYBORNE_H HUNTER 1; DWARF HUNTER 0 |
| P3h | speed | P3 Modellstunden 1–30, längste der 16 Ziehungen | – | Bericht | TAUREN WARRIOR 35.88; ORC WARRIOR 35.10; TROLL WARRIOR 35.10; DWARF WARRIOR 35.00; GNOME WARRIOR 35.00 |
| P3h | explorer | P3 Modellstunden 1–30, längste der 16 Ziehungen | – | Bericht | TAUREN WARRIOR 34.70; ORC WARRIOR 34.11; TROLL WARRIOR 34.11; UNDEAD WARRIOR 33.91; DWARF WARRIOR 33.79 |
| P4 | speed | P4 lange Einzelquest-Wege im Gebiet (über 0,05 Modellstunden, unter ½ Routenrate) | ≤ 0 | verletzt (41) | DWARF HUNTER 5; DWARF PALADIN 4; DWARF PRIEST 4; DWARF ROGUE 4; DWARF SHAMAN 4 |
| P4 | explorer | P4 lange Einzelquest-Wege im Gebiet (über 0,05 Modellstunden, unter ½ Routenrate) | ≤ 0 | verletzt (41) | TAUREN HUNTER 5; DWARF HUNTER 4; ORC WARLOCK 4; TROLL WARLOCK 4; GNOME WARLOCK 3 |
| P4b | speed | P4 lange Einzelquest-Wege mehr als Startlösung | ≤ Startlösung | erfüllt | ORC WARLOCK -1; TROLL WARLOCK -1; ORC SHAMAN -2; SKYBORNE_H DRUID -2; SKYBORNE_H ROGUE -2 |
| P4b | explorer | P4 lange Einzelquest-Wege mehr als Startlösung | ≤ Startlösung | erfüllt | ORC WARLOCK 0; TROLL WARLOCK 0; SKYBORNE_H DRUID -2; SKYBORNE_H HUNTER -2; SKYBORNE_H ROGUE -2 |
| P4yd | speed | P4 längster Fußweg im selben Gebiet (yd) | – | Bericht | ORC HUNTER 3704; ORC MAGE 3704; ORC ROGUE 3704; ORC SHAMAN 3704; ORC WARLOCK 3704 |
| P4yd | explorer | P4 längster Fußweg im selben Gebiet (yd) | – | Bericht | ORC HUNTER 3695; ORC MAGE 3695; ORC ROGUE 3695; ORC SHAMAN 3695; ORC WARLOCK 3695 |
| P5 | speed | P5 vermeidbare Rückkehren | – | Bericht | HUMAN HUNTER 25; HUMAN MAGE 25; HUMAN PALADIN 25; HUMAN PRIEST 25; HUMAN ROGUE 25 |
| P5 | explorer | P5 vermeidbare Rückkehren | – | Bericht | HUMAN HUNTER 31; HUMAN MAGE 31; HUMAN PALADIN 31; HUMAN PRIEST 31; HUMAN ROGUE 31 |
| P5b | speed | P5 vermeidbare Rückkehren mehr als Startlösung | ≤ Startlösung | erfüllt | HUMAN PALADIN 0; HUMAN ROGUE 0; UNDEAD ROGUE 0; DWARF PALADIN -1; DWARF ROGUE -1 |
| P5b | explorer | P5 vermeidbare Rückkehren mehr als Startlösung | ≤ Startlösung | erfüllt | ORC WARRIOR -1; TROLL WARRIOR -1; ORC HUNTER -2; ORC MAGE -2; ORC ROGUE -2 |
| P5w | speed | P5 verschwendete Wege | ≤ 0 | verletzt (56) | HUMAN HUNTER 6; HUMAN MAGE 6; HUMAN PALADIN 6; HUMAN PRIEST 6; HUMAN ROGUE 6 |
| P5w | explorer | P5 verschwendete Wege | ≤ 0 | verletzt (56) | HUMAN HUNTER 6; HUMAN MAGE 6; HUMAN PALADIN 6; HUMAN PRIEST 6; HUMAN ROGUE 6 |
| P6 | speed | P6 vorbeigelaufen, nie genommen | ≤ 0 | verletzt (56) | DWARF PRIEST 9; GNOME PRIEST 9; HUMAN HUNTER 9; HUMAN PRIEST 9; NIGHTELF ROGUE 9 |
| P6 | explorer | P6 vorbeigelaufen, nie genommen | ≤ 0 | verletzt (56) | UNDEAD WARRIOR 15; HUMAN HUNTER 14; HUMAN PRIEST 14; NIGHTELF PRIEST 14; SKYBORNE_A DRUID 14 |
| P6l | speed | P6 vorbeigelaufen, erst später genommen | ≤ 0 | verletzt (56) | HUMAN HUNTER 8; HUMAN MAGE 8; HUMAN PALADIN 8; HUMAN PRIEST 8; HUMAN ROGUE 8 |
| P6l | explorer | P6 vorbeigelaufen, erst später genommen | ≤ 0 | verletzt (56) | HUMAN HUNTER 15; HUMAN MAGE 15; HUMAN PALADIN 15; HUMAN PRIEST 15; HUMAN ROGUE 15 |
| P6z | speed | P6 vorbeigelaufen, braucht ein Gebiet, das die Route nicht mehr besucht (Wächter P9) | – | Bericht | DWARF PRIEST 20; NIGHTELF PRIEST 20; TAUREN WARRIOR 20; DWARF SHAMAN 19; DWARF WARRIOR 19 |
| P6z | explorer | P6 vorbeigelaufen, braucht ein Gebiet, das die Route nicht mehr besucht (Wächter P9) | – | Bericht | NIGHTELF PRIEST 28; TAUREN WARRIOR 28; TAUREN DRUID 27; TAUREN SHAMAN 26; NIGHTELF DRUID 25 |
| P6n | speed | P6 vorbeigelaufen, lohnt nicht (XP je Zusatzsekunde unter der Routenrate) | – | Bericht | TAUREN SHAMAN 11; UNDEAD WARRIOR 9; TAUREN HUNTER 8; TAUREN WARRIOR 8; NIGHTELF PRIEST 7 |
| P6n | explorer | P6 vorbeigelaufen, lohnt nicht (XP je Zusatzsekunde unter der Routenrate) | – | Bericht | ORC WARLOCK 17; TROLL WARLOCK 17; UNDEAD WARLOCK 15; NIGHTELF PRIEST 11; UNDEAD WARRIOR 11 |
| P7 | speed | P7 Questlog-Spitze | ≤ 35 | erfüllt | UNDEAD PRIEST 17; UNDEAD MAGE 16; UNDEAD PALADIN 16; UNDEAD ROGUE 16; UNDEAD WARLOCK 16 |
| P7 | explorer | P7 Questlog-Spitze | ≤ 35 | erfüllt | UNDEAD PRIEST 18; UNDEAD MAGE 17; UNDEAD PALADIN 17; UNDEAD ROGUE 17; UNDEAD WARLOCK 17 |
| P7o | speed | P7 angenommen und nie abgegeben | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P7o | explorer | P7 angenommen und nie abgegeben | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P8 | speed | P8 Annahme über Stufe + 2, graue Abgabe, Ausreißer | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P8 | explorer | P8 Annahme über Stufe + 2, graue Abgabe, Ausreißer | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P9 | speed | P9 Gebietswechsel | – | Bericht | NIGHTELF PRIEST 9; DWARF HUNTER 7; DWARF PALADIN 7; DWARF PRIEST 7; DWARF ROGUE 7 |
| P9 | explorer | P9 Gebietswechsel | – | Bericht | NIGHTELF PRIEST 9; ORC WARLOCK 8; TROLL WARLOCK 8; UNDEAD WARLOCK 8; DWARF HUNTER 7 |
| P9b | speed | P9 Gebietswechsel mehr als Startlösung | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF ROGUE 0; DWARF SHAMAN 0; GNOME ROGUE 0 |
| P9b | explorer | P9 Gebietswechsel mehr als Startlösung | ≤ Startlösung | erfüllt | DWARF HUNTER 0; HUMAN HUNTER 0; NIGHTELF HUNTER 0; ORC HUNTER 0; ORC MAGE 0 |
| P9q | speed | P9 Quests je Gebietsbesuch | – | Bericht | ORC WARLOCK 18.14; TROLL WARLOCK 18.14; NIGHTELF PRIEST 18.40; ORC MAGE 19.14; ORC ROGUE 19.14 |
| P9q | explorer | P9 Quests je Gebietsbesuch | – | Bericht | ORC WARLOCK 15.78; TROLL WARLOCK 15.78; UNDEAD WARLOCK 17.44; NIGHTELF PRIEST 19.90; ORC MAGE 20.71 |
| P11 | speed | P11 Modellstunden 1–30 Profil langsam (Krieger-Faktor) | – | Bericht | TAUREN DRUID 26.16; TAUREN HUNTER 26.16; TAUREN SHAMAN 26.16; TAUREN WARRIOR 26.14; ORC WARLOCK 25.69 |
| P11 | explorer | P11 Modellstunden 1–30 Profil langsam (Krieger-Faktor) | – | Bericht | TAUREN DRUID 25.51; TAUREN SHAMAN 25.51; TAUREN HUNTER 25.51; TAUREN WARRIOR 25.50; ORC WARLOCK 25.17 |
| P11f | speed | P11 Modellstunden 1–30 Profil schnell (Jäger-Faktor) | – | Bericht | TAUREN WARRIOR 20.96; TAUREN DRUID 20.94; TAUREN HUNTER 20.94; TAUREN SHAMAN 20.94; ORC WARLOCK 20.42 |
| P11f | explorer | P11 Modellstunden 1–30 Profil schnell (Jäger-Faktor) | – | Bericht | TAUREN WARRIOR 20.60; TAUREN DRUID 20.57; TAUREN SHAMAN 20.57; TAUREN HUNTER 20.57; ORC WARLOCK 20.15 |
| P11b | speed | P11 Mehrstunden gegen Startlösung, Profil langsam oder schnell | ≤ Startlösung | erfüllt | SKYBORNE_H SHAMAN -0.45; SKYBORNE_H HUNTER -0.45; SKYBORNE_H WARRIOR -0.57; ORC WARRIOR -0.77; TROLL WARRIOR -0.77 |
| P11b | explorer | P11 Mehrstunden gegen Startlösung, Profil langsam oder schnell | ≤ Startlösung | erfüllt | SKYBORNE_H SHAMAN -0.21; SKYBORNE_H HUNTER -0.22; SKYBORNE_H WARRIOR -0.37; ORC WARRIOR -0.65; TROLL WARRIOR -0.65 |
| G1 | speed | G1 Linter-Fehler | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G1 | explorer | G1 Linter-Fehler | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G2 | speed | G2 Hänger im Simulator | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G2 | explorer | G2 Hänger im Simulator | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G3 | speed | G3 kleinste Quest-XP-Deckung eines Bands | ≥ 0.80 | verletzt (56) | DWARF HUNTER 0.14; DWARF PALADIN 0.14; DWARF PRIEST 0.14; DWARF ROGUE 0.14; DWARF SHAMAN 0.14 |
| G3 | explorer | G3 kleinste Quest-XP-Deckung eines Bands | ≥ 0.80 | verletzt (56) | DWARF HUNTER 0.17; DWARF PALADIN 0.17; DWARF PRIEST 0.17; DWARF ROGUE 0.17; DWARF SHAMAN 0.17 |
| G4 | speed | G4 Abstand zur besten Deckung im Band | ≤ 0.10 | verletzt (38) | SKYBORNE_H DRUID 0.20; SKYBORNE_H HUNTER 0.20; SKYBORNE_H ROGUE 0.20; SKYBORNE_H SHAMAN 0.20; UNDEAD MAGE 0.20 |
| G4 | explorer | G4 Abstand zur besten Deckung im Band | ≤ 0.10 | verletzt (39) | SKYBORNE_H DRUID 0.23; SKYBORNE_H HUNTER 0.23; SKYBORNE_H ROGUE 0.23; SKYBORNE_H SHAMAN 0.23; UNDEAD MAGE 0.23 |
| G5 | speed | G5 Questzahl: meiste / eigene je Band | ≤ 1.25 | verletzt (28) | ORC WARLOCK 1.79; TROLL WARLOCK 1.79; SKYBORNE_H DRUID 1.58; SKYBORNE_H HUNTER 1.58; SKYBORNE_H ROGUE 1.58 |
| G5 | explorer | G5 Questzahl: meiste / eigene je Band | ≤ 1.25 | verletzt (28) | ORC WARLOCK 1.77; TROLL WARLOCK 1.77; SKYBORNE_H DRUID 1.56; SKYBORNE_H HUNTER 1.56; SKYBORNE_H ROGUE 1.56 |
| G6 | speed | G6 Laufweg je Quest-XP / Median je Band | ≤ 1.20 | verletzt (4) | TAUREN DRUID 1.51; TAUREN HUNTER 1.51; TAUREN SHAMAN 1.51; TAUREN WARRIOR 1.51; ORC HUNTER 1.14 |
| G6 | explorer | G6 Laufweg je Quest-XP / Median je Band | ≤ 1.20 | verletzt (4) | TAUREN HUNTER 1.44; TAUREN WARRIOR 1.44; TAUREN DRUID 1.44; TAUREN SHAMAN 1.44; ORC WARLOCK 1.19 |
| G7 | speed | G7 Abweichung der Ankunftsstufe vom Beginn des ersten Kernblocks | ≤ 1.00 | erfüllt | SKYBORNE_H HUNTER 0.96; SKYBORNE_H WARRIOR 0.96; HUMAN HUNTER 0.96; HUMAN MAGE 0.96; HUMAN PALADIN 0.96 |
| G7 | explorer | G7 Abweichung der Ankunftsstufe vom Beginn des ersten Kernblocks | ≤ 1.00 | erfüllt | HUMAN PRIEST 0.99; HUMAN HUNTER 0.98; HUMAN MAGE 0.98; HUMAN PALADIN 0.98; HUMAN ROGUE 0.98 |
| G8 | speed | G8 längster Klasseneinschub (Modellstunden) | ≤ 0.17 | erfüllt | NIGHTELF PRIEST 0.12; DWARF HUNTER 0.00; DWARF PALADIN 0.00; DWARF PRIEST 0.00; DWARF ROGUE 0.00 |
| G8 | explorer | G8 längster Klasseneinschub (Modellstunden) | ≤ 0.17 | erfüllt | ORC WARLOCK 0.14; TROLL WARLOCK 0.14; UNDEAD WARLOCK 0.14; NIGHTELF PRIEST 0.12; DWARF HUNTER 0.00 |
| G8s | speed | G8 Klasseneinschübe gesamt (Modellstunden) | ≤ 0.50 | erfüllt | NIGHTELF PRIEST 0.12; DWARF HUNTER 0.00; DWARF PALADIN 0.00; DWARF PRIEST 0.00; DWARF ROGUE 0.00 |
| G8s | explorer | G8 Klasseneinschübe gesamt (Modellstunden) | ≤ 0.50 | erfüllt | ORC WARLOCK 0.14; TROLL WARLOCK 0.14; UNDEAD WARLOCK 0.14; NIGHTELF PRIEST 0.12; DWARF HUNTER 0.00 |
| G9 | speed | G9 train-Schritte auf der Route (Lehrerwege prüfbar ab einem) | – | offen (keine train-Schritte in den Routen) | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G9 | explorer | G9 train-Schritte auf der Route (Lehrerwege prüfbar ab einem) | – | offen (keine train-Schritte in den Routen) | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G10 | speed | G10 Rückstand zur besten Route der Klasse | ≤ 0.10 | erfüllt | TAUREN HUNTER 0.06; TAUREN DRUID 0.05; TAUREN WARRIOR 0.05; TAUREN SHAMAN 0.04; ORC WARLOCK 0.03 |
| G10 | explorer | G10 Rückstand zur besten Route der Klasse | ≤ 0.10 | erfüllt | TAUREN HUNTER 0.06; TAUREN DRUID 0.05; TAUREN WARRIOR 0.05; TAUREN SHAMAN 0.04; ORC WARLOCK 0.04 |
| G11 | speed | G11 Anteil Routenquests mit eigener Volk-/Klassen-Messung (gilt ab Etikett stabil) | ≥ 1.00 | offen |  |
| G11 | explorer | G11 Anteil Routenquests mit eigener Volk-/Klassen-Messung (gilt ab Etikett stabil) | ≥ 1.00 | offen |  |
| R01 | speed | R01 Abgabe über Questlevel + 5 (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R01 | explorer | R01 Abgabe über Questlevel + 5 (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R02 | speed | R02 Abgabe ab Questlevel + 10 (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R02 | explorer | R02 Abgabe ab Questlevel + 10 (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R04 | speed | R04 Folgequest am selben NPC nicht im selben Schritt (H) | ≤ 0 | verletzt (56) | HUMAN PALADIN 19; HUMAN ROGUE 19; HUMAN WARLOCK 19; HUMAN HUNTER 18; HUMAN MAGE 18 |
| R04 | explorer | R04 Folgequest am selben NPC nicht im selben Schritt (H) | ≤ 0 | verletzt (56) | HUMAN PALADIN 19; HUMAN ROGUE 19; HUMAN WARLOCK 19; HUMAN WARRIOR 19; HUMAN HUNTER 18 |
| R05 | speed | R05 späterer Besuch nur zur Annahme (H) | ≤ 0 | verletzt (24) | HUMAN HUNTER 3; HUMAN MAGE 3; HUMAN PALADIN 3; HUMAN PRIEST 3; HUMAN ROGUE 3 |
| R05 | explorer | R05 späterer Besuch nur zur Annahme (H) | ≤ 0 | verletzt (28) | HUMAN WARRIOR 4; HUMAN HUNTER 3; HUMAN MAGE 3; HUMAN PALADIN 3; HUMAN PRIEST 3 |
| R06 | speed | R06 aktives Ziel passiert, später eigener Besuch (H) | ≤ 0 | verletzt (56) | UNDEAD MAGE 4; UNDEAD PALADIN 4; UNDEAD PRIEST 4; UNDEAD ROGUE 4; UNDEAD WARLOCK 4 |
| R06 | explorer | R06 aktives Ziel passiert, später eigener Besuch (H) | ≤ 0 | verletzt (56) | UNDEAD MAGE 4; UNDEAD PALADIN 4; UNDEAD PRIEST 4; UNDEAD ROGUE 4; UNDEAD WARLOCK 4 |
| R07 | speed | R07 Zwischenabgabe zwischen zwei nahen Zielen (H) | ≤ 0 | verletzt (6) | UNDEAD MAGE 1; UNDEAD PALADIN 1; UNDEAD PRIEST 1; UNDEAD ROGUE 1; UNDEAD WARLOCK 1 |
| R07 | explorer | R07 Zwischenabgabe zwischen zwei nahen Zielen (H) | ≤ 0 | verletzt (6) | UNDEAD MAGE 1; UNDEAD PALADIN 1; UNDEAD PRIEST 1; UNDEAD ROGUE 1; UNDEAD WARLOCK 1 |
| R09 | speed | R09 Rückkehr ins Gebiet mit weniger als 3 Quests (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R09 | explorer | R09 Rückkehr ins Gebiet mit weniger als 3 Quests (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R10 | speed | R10 Ruhestein ohne Bedingungen (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R10 | explorer | R10 Ruhestein ohne Bedingungen (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R11 | speed | R11 Bindung ohne späteren Besuch (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R11 | explorer | R11 Bindung ohne späteren Besuch (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R12 | speed | R12 Ruhestein vor Ablauf der Abklingzeit (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R12 | explorer | R12 Ruhestein vor Ablauf der Abklingzeit (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R13 | speed | R13 unbekannter Flugmeister passiert (H) | ≤ 0 | verletzt (38) | DWARF HUNTER 5; DWARF PALADIN 5; DWARF PRIEST 5; DWARF ROGUE 5; DWARF SHAMAN 5 |
| R13 | explorer | R13 unbekannter Flugmeister passiert (H) | ≤ 0 | verletzt (38) | DWARF HUNTER 2; DWARF PALADIN 2; DWARF PRIEST 2; DWARF ROGUE 2; DWARF SHAMAN 2 |
| R17 | speed | R17 Grind-Schritt ohne Ort (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R17 | explorer | R17 Grind-Schritt ohne Ort (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R18 | speed | R18 Grind trotz annehmbarer Quest in 500 yd (H) | ≤ 0 | verletzt (56) | DWARF PALADIN 4; DWARF PRIEST 4; DWARF ROGUE 4; DWARF SHAMAN 4; DWARF WARRIOR 4 |
| R18 | explorer | R18 Grind trotz annehmbarer Quest in 500 yd (H) | ≤ 0 | verletzt (49) | ORC WARLOCK 3; TROLL WARLOCK 3; UNDEAD MAGE 3; UNDEAD PRIEST 3; UNDEAD ROGUE 3 |
| R18z | speed | R18 Grind neben Quests, die ein Gebiet außerhalb der Route brauchen oder nicht lohnen | – | Bericht | DWARF PALADIN 7; DWARF PRIEST 7; DWARF ROGUE 7; DWARF SHAMAN 7; DWARF WARRIOR 7 |
| R18z | explorer | R18 Grind neben Quests, die ein Gebiet außerhalb der Route brauchen oder nicht lohnen | – | Bericht | ORC WARLOCK 6; TROLL WARLOCK 6; DWARF PALADIN 4; DWARF PRIEST 4; DWARF ROGUE 4 |
| R19 | speed | R19 Grind ohne vorherige Ankündigung (H) | ≤ 0 | verletzt (50) | DWARF PALADIN 3; DWARF PRIEST 3; DWARF ROGUE 3; DWARF SHAMAN 3; DWARF WARRIOR 3 |
| R19 | explorer | R19 Grind ohne vorherige Ankündigung (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R20 | speed | R20 Eskorten-/Ereignisquests im Speed-Pfad (W) | – | Bericht | TAUREN DRUID 8; TAUREN HUNTER 8; TAUREN SHAMAN 8; TAUREN WARRIOR 8; NIGHTELF DRUID 6 |
| R20 | explorer | R20 Eskorten-/Ereignisquests im Speed-Pfad (W) | – | Bericht | TAUREN DRUID 8; TAUREN HUNTER 8; TAUREN SHAMAN 8; TAUREN WARRIOR 8; NIGHTELF DRUID 7 |
| R21 | speed | R21 Sammelquests ohne Abbruchregel (W) | – | Bericht | HUMAN WARLOCK 107; HUMAN PALADIN 106; HUMAN PRIEST 106; HUMAN ROGUE 106; HUMAN HUNTER 105 |
| R21 | explorer | R21 Sammelquests ohne Abbruchregel (W) | – | Bericht | HUMAN WARLOCK 116; NIGHTELF WARRIOR 116; GNOME WARLOCK 115; HUMAN PALADIN 115; HUMAN PRIEST 115 |
| R22 | speed | R22 Gruppen-/Elitequests im Solo-Pfad (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R22 | explorer | R22 Gruppen-/Elitequests im Solo-Pfad (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R23 | speed | R23 nicht verfügbare Quest (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R23 | explorer | R23 nicht verfügbare Quest (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R26 | speed | R26 Hauptstadtbesuch ohne Grund (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R26 | explorer | R26 Hauptstadtbesuch ohne Grund (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R27 | speed | R27 Questziel mehr als 2 Stufen über dem Spieler (W) | – | Bericht | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R27 | explorer | R27 Questziel mehr als 2 Stufen über dem Spieler (W) | – | Bericht | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R28 | speed | R28 Dungeonquest im Speed-Pfad (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R28 | explorer | R28 Dungeonquest im Speed-Pfad (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R30 | speed | R30 Questlog über 40 (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R30 | explorer | R30 Questlog über 40 (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R31 | speed | R31 Quest am Ende noch im Log (W) | – | Bericht | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R31 | explorer | R31 Quest am Ende noch im Log (W) | – | Bericht | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R33 | speed | R33 Etikett stabil ohne Messung (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R33 | explorer | R33 Etikett stabil ohne Messung (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |

### P10 Spannweite der Modellstunden je Band und Fraktion

| Modus | Fraktion | Band | kürzeste | längste | Verhältnis |
| --- | --- | --- | --- | --- | --- |
| speed | Alliance | 1-10 | 1.83 (NIGHTELF HUNTER) | 2.27 (GNOME WARRIOR) | 1.24 |
| speed | Alliance | 11-20 | 7.08 (SKYBORNE_A HUNTER) | 8.16 (NIGHTELF WARRIOR) | 1.15 |
| speed | Alliance | 21-30 | 10.81 (HUMAN HUNTER) | 14.71 (GNOME WARRIOR) | 1.36 |
| speed | Horde | 1-10 | 1.94 (SKYBORNE_H HUNTER) | 2.97 (TAUREN WARRIOR) | 1.53 |
| speed | Horde | 11-20 | 6.83 (SKYBORNE_H HUNTER) | 8.41 (TAUREN WARRIOR) | 1.23 |
| speed | Horde | 21-30 | 11.42 (SKYBORNE_H HUNTER) | 14.76 (UNDEAD WARRIOR) | 1.29 |
| explorer | Alliance | 1-10 | 1.83 (NIGHTELF HUNTER) | 2.23 (GNOME WARRIOR) | 1.22 |
| explorer | Alliance | 11-20 | 6.89 (SKYBORNE_A HUNTER) | 7.99 (GNOME WARRIOR) | 1.16 |
| explorer | Alliance | 21-30 | 10.55 (DWARF HUNTER) | 14.24 (GNOME WARRIOR) | 1.35 |
| explorer | Horde | 1-10 | 1.94 (SKYBORNE_H HUNTER) | 2.98 (TAUREN WARRIOR) | 1.53 |
| explorer | Horde | 11-20 | 6.62 (TAUREN HUNTER) | 8.18 (UNDEAD WARRIOR) | 1.24 |
| explorer | Horde | 21-30 | 11.22 (SKYBORNE_H HUNTER) | 14.38 (TROLL WARRIOR) | 1.28 |

### G12 Himmelsgeborene je Fraktion

| Volk | Modus | Kombinationen | verletzte Prüfungen (Anzahl Kombinationen) |
| --- | --- | --- | --- |
| SKYBORNE_A | speed | 5 | G3 (5), G4 (4) |
| SKYBORNE_A | explorer | 5 | G3 (5), G4 (4) |
| SKYBORNE_H | speed | 5 | G3 (5), G4 (5), G5 (5) |
| SKYBORNE_H | explorer | 5 | G3 (5), G4 (5), G5 (5) |

### Nicht an der Route prüfbar

- R03: Eigenschaft des Codes, nicht der Route: xp.py und XP.lua rechnen den Questwert aus dem Stufenabstand
- R08: Wegverlängerung durch Kill-Abschnitte: die Daten haben keine Wege der Kills
- R14: Flug gegen Fußweg: data/facts hat kein Flugnetz (TaxiPathNode)
- R15: Klassenreisemittel: keine Teleport-Daten je Klasse
- R16: Tod als Reise: das Routenformat hat keinen solchen Schritt
- R24: Pflichtliste der Klassenquests je Klasse fehlt
- R25: Lehrer im Stufenfenster: die Routen haben keine train-Schritte
- R29: begründete Verzweigung: Strukturfrage des Baukastens (Welle 6b); alle Kombinationen werden simuliert
- R32: Ende bei Stufe 60: die Routen enden bei 30
- R34: Buff-Hinweise: die Routen haben keine
- R35: Looten: Hinweistext, keine Routeneigenschaft

### Alle Kombinationen, speed

| Kombination | Modellstunden 1–20 | Modellstunden 1–30 | P2 Deckung min | P2 Grind max | P4 längster Weg yd | P5 | P6 nie/später | P7 | P9 | G3 1–10/11–20/21–30 | Quests 1–10/11–20/21–30 | G7 | G8 h | G10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HUMAN WARRIOR | 9.30 | 24.92 | 0.10 | 0.99 | 2366 | 25 | 8/8 | 13 | 7 | 0.56/0.59/0.14 | 58/95/29 | -0.96 | 0.00 | 0.00 |
| HUMAN PALADIN | 9.15 | 24.25 | 0.10 | 0.99 | 2366 | 25 | 8/8 | 13 | 7 | 0.56/0.58/0.14 | 59/94/29 | -0.96 | 0.00 | 0.00 |
| HUMAN HUNTER | 8.22 | 19.86 | 0.10 | 0.99 | 2366 | 25 | 9/8 | 13 | 7 | 0.56/0.58/0.14 | 58/94/29 | -0.96 | 0.00 | 0.00 |
| HUMAN ROGUE | 8.84 | 22.79 | 0.10 | 0.99 | 2366 | 25 | 8/8 | 13 | 7 | 0.56/0.58/0.14 | 59/94/29 | -0.96 | 0.00 | 0.00 |
| HUMAN PRIEST | 8.99 | 23.52 | 0.10 | 0.99 | 2366 | 25 | 9/8 | 13 | 7 | 0.56/0.58/0.14 | 59/94/29 | -0.96 | 0.00 | 0.00 |
| HUMAN MAGE | 8.53 | 21.32 | 0.10 | 0.99 | 2366 | 25 | 8/8 | 13 | 7 | 0.56/0.58/0.14 | 58/94/29 | -0.96 | 0.00 | 0.00 |
| HUMAN WARLOCK | 8.36 | 20.58 | 0.10 | 0.99 | 2366 | 25 | 8/8 | 13 | 7 | 0.57/0.58/0.14 | 60/94/29 | -0.96 | 0.00 | 0.00 |
| DWARF WARRIOR | 9.52 | 25.14 | 0.10 | 0.99 | 2366 | 16 | 8/6 | 14 | 7 | 0.62/0.54/0.14 | 50/89/29 | -0.10 | 0.00 | 0.01 |
| DWARF PALADIN | 9.36 | 24.46 | 0.10 | 0.99 | 2366 | 16 | 8/6 | 14 | 7 | 0.62/0.54/0.14 | 50/88/29 | -0.10 | 0.00 | 0.01 |
| DWARF HUNTER | 8.40 | 20.04 | 0.10 | 0.99 | 2366 | 17 | 8/7 | 14 | 7 | 0.66/0.54/0.14 | 53/89/29 | -0.47 | 0.00 | 0.01 |
| DWARF ROGUE | 9.02 | 22.96 | 0.10 | 0.99 | 2366 | 16 | 8/6 | 14 | 7 | 0.63/0.54/0.14 | 51/88/29 | -0.15 | 0.00 | 0.01 |
| DWARF PRIEST | 9.19 | 23.72 | 0.10 | 0.99 | 2366 | 16 | 9/6 | 14 | 7 | 0.62/0.54/0.14 | 50/88/29 | -0.10 | 0.00 | 0.01 |
| DWARF SHAMAN | 9.03 | 22.98 | 0.10 | 0.99 | 2366 | 16 | 8/6 | 14 | 7 | 0.62/0.54/0.14 | 50/88/29 | -0.10 | 0.00 | 0.00 |
| NIGHTELF WARRIOR | 9.30 | 24.92 | 0.10 | 0.99 | 2366 | 19 | 8/6 | 14 | 7 | 0.66/0.57/0.14 | 54/91/29 | -0.58 | 0.00 | 0.00 |
| NIGHTELF HUNTER | 8.36 | 20.00 | 0.10 | 0.99 | 2366 | 21 | 8/7 | 14 | 7 | 0.66/0.58/0.14 | 54/93/29 | -0.90 | 0.00 | 0.01 |
| NIGHTELF ROGUE | 8.85 | 22.80 | 0.10 | 0.99 | 2366 | 19 | 9/6 | 14 | 7 | 0.66/0.57/0.14 | 54/90/29 | -0.58 | 0.00 | 0.00 |
| NIGHTELF PRIEST | 8.99 | 23.60 | 0.10 | 0.99 | 2366 | 20 | 8/6 | 15 | 9 | 0.66/0.57/0.14 | 56/92/29 | -0.61 | 0.12 | 0.00 |
| NIGHTELF DRUID | 8.85 | 22.80 | 0.10 | 0.99 | 2366 | 19 | 8/6 | 14 | 7 | 0.66/0.57/0.14 | 54/90/29 | -0.58 | 0.00 | 0.00 |
| GNOME WARRIOR | 9.52 | 25.14 | 0.10 | 0.99 | 2366 | 16 | 8/6 | 14 | 7 | 0.62/0.54/0.14 | 50/89/29 | -0.10 | 0.00 | 0.01 |
| GNOME ROGUE | 9.02 | 22.96 | 0.10 | 0.99 | 2366 | 16 | 8/6 | 14 | 7 | 0.63/0.54/0.14 | 51/88/29 | -0.15 | 0.00 | 0.01 |
| GNOME PRIEST | 9.19 | 23.72 | 0.10 | 0.99 | 2366 | 16 | 9/6 | 14 | 7 | 0.62/0.54/0.14 | 50/88/29 | -0.10 | 0.00 | 0.01 |
| GNOME MAGE | 8.70 | 21.50 | 0.10 | 0.99 | 2366 | 16 | 8/6 | 14 | 7 | 0.62/0.54/0.14 | 50/88/29 | -0.10 | 0.00 | 0.01 |
| GNOME WARLOCK | 8.54 | 20.76 | 0.10 | 0.99 | 2366 | 17 | 8/6 | 14 | 7 | 0.63/0.54/0.14 | 51/88/29 | -0.13 | 0.00 | 0.01 |
| SKYBORNE_A WARRIOR | 9.40 | 25.02 | 0.10 | 0.99 | 2366 | 15 | 8/4 | 14 | 7 | 0.55/0.56/0.14 | 58/91/29 | -0.38 | 0.00 | 0.00 |
| SKYBORNE_A HUNTER | 8.19 | 19.83 | 0.10 | 0.99 | 2366 | 17 | 8/5 | 14 | 7 | 0.61/0.55/0.14 | 61/90/29 | -0.64 | 0.00 | 0.00 |
| SKYBORNE_A ROGUE | 8.95 | 22.90 | 0.10 | 0.99 | 2366 | 15 | 8/4 | 14 | 7 | 0.53/0.55/0.14 | 57/90/29 | -0.31 | 0.00 | 0.00 |
| SKYBORNE_A MAGE | 8.62 | 21.41 | 0.10 | 0.99 | 2366 | 15 | 8/4 | 14 | 7 | 0.53/0.55/0.14 | 58/90/29 | -0.36 | 0.00 | 0.00 |
| SKYBORNE_A DRUID | 8.95 | 22.90 | 0.10 | 0.99 | 2366 | 15 | 8/4 | 14 | 7 | 0.53/0.55/0.14 | 57/91/29 | -0.41 | 0.00 | 0.00 |
| ORC WARRIOR | 9.61 | 25.53 | 0.16 | 0.99 | 3704 | 10 | 5/5 | 14 | 6 | 0.63/0.40/0.22 | 41/64/31 | -0.81 | 0.00 | 0.02 |
| ORC HUNTER | 7.93 | 20.37 | 0.16 | 0.99 | 3704 | 9 | 4/4 | 14 | 6 | 0.65/0.39/0.21 | 42/61/31 | -0.93 | 0.00 | 0.03 |
| ORC ROGUE | 8.86 | 23.34 | 0.16 | 0.99 | 3704 | 9 | 4/4 | 14 | 6 | 0.63/0.39/0.21 | 41/61/31 | -0.81 | 0.00 | 0.02 |
| ORC SHAMAN | 8.84 | 23.32 | 0.16 | 0.99 | 3704 | 9 | 4/4 | 14 | 6 | 0.65/0.39/0.21 | 43/61/31 | -0.90 | 0.00 | 0.01 |
| ORC MAGE | 8.40 | 21.86 | 0.16 | 0.99 | 3704 | 9 | 4/4 | 14 | 6 | 0.63/0.39/0.21 | 41/61/31 | -0.81 | 0.00 | 0.03 |
| ORC WARLOCK | 8.22 | 21.17 | 0.16 | 0.99 | 3704 | 9 | 2/4 | 14 | 6 | 0.51/0.39/0.21 | 34/61/31 | -0.13 | 0.00 | 0.03 |
| UNDEAD WARRIOR | 9.54 | 25.46 | 0.16 | 0.99 | 3704 | 15 | 3/7 | 16 | 6 | 0.62/0.40/0.22 | 50/63/31 | -0.82 | 0.00 | 0.02 |
| UNDEAD PALADIN | 9.33 | 24.82 | 0.16 | 0.99 | 3704 | 14 | 3/4 | 16 | 6 | 0.57/0.39/0.21 | 50/60/31 | -0.44 | 0.00 | 0.02 |
| UNDEAD ROGUE | 8.86 | 23.34 | 0.16 | 0.99 | 3704 | 14 | 3/4 | 16 | 6 | 0.56/0.39/0.21 | 47/60/31 | -0.44 | 0.00 | 0.02 |
| UNDEAD PRIEST | 9.10 | 24.09 | 0.16 | 0.99 | 3704 | 15 | 3/4 | 17 | 6 | 0.57/0.39/0.21 | 50/60/31 | -0.44 | 0.00 | 0.02 |
| UNDEAD MAGE | 8.38 | 21.85 | 0.16 | 0.99 | 3704 | 14 | 3/4 | 16 | 6 | 0.56/0.39/0.21 | 48/60/31 | -0.44 | 0.00 | 0.02 |
| UNDEAD WARLOCK | 8.14 | 21.09 | 0.16 | 0.99 | 3704 | 14 | 3/4 | 16 | 6 | 0.56/0.39/0.21 | 49/60/31 | -0.44 | 0.00 | 0.02 |
| TAUREN WARRIOR | 10.22 | 26.14 | 0.16 | 0.99 | 3704 | 9 | 9/6 | 14 | 6 | 0.56/0.40/0.22 | 47/64/31 | -0.10 | 0.00 | 0.05 |
| TAUREN HUNTER | 8.49 | 20.94 | 0.16 | 0.99 | 3704 | 9 | 8/4 | 14 | 6 | 0.56/0.39/0.21 | 46/61/31 | -0.10 | 0.00 | 0.06 |
| TAUREN SHAMAN | 9.44 | 23.92 | 0.16 | 0.99 | 3704 | 9 | 8/4 | 14 | 6 | 0.56/0.39/0.21 | 46/61/31 | -0.10 | 0.00 | 0.04 |
| TAUREN DRUID | 9.45 | 23.93 | 0.16 | 0.99 | 3704 | 9 | 8/4 | 14 | 6 | 0.56/0.39/0.21 | 47/61/31 | -0.10 | 0.00 | 0.05 |
| TROLL WARRIOR | 9.61 | 25.53 | 0.16 | 0.99 | 3704 | 10 | 5/5 | 14 | 6 | 0.63/0.40/0.22 | 41/64/31 | -0.81 | 0.00 | 0.02 |
| TROLL HUNTER | 7.93 | 20.37 | 0.16 | 0.99 | 3704 | 9 | 4/4 | 14 | 6 | 0.65/0.39/0.21 | 42/61/31 | -0.93 | 0.00 | 0.03 |
| TROLL ROGUE | 8.86 | 23.34 | 0.16 | 0.99 | 3704 | 9 | 4/4 | 14 | 6 | 0.63/0.39/0.21 | 41/61/31 | -0.81 | 0.00 | 0.02 |
| TROLL PRIEST | 9.09 | 24.08 | 0.16 | 0.99 | 3704 | 9 | 5/4 | 14 | 6 | 0.63/0.39/0.21 | 41/61/31 | -0.81 | 0.00 | 0.02 |
| TROLL SHAMAN | 8.84 | 23.32 | 0.16 | 0.99 | 3704 | 9 | 4/4 | 14 | 6 | 0.65/0.39/0.21 | 43/61/31 | -0.90 | 0.00 | 0.01 |
| TROLL MAGE | 8.40 | 21.86 | 0.16 | 0.99 | 3704 | 9 | 4/4 | 14 | 6 | 0.63/0.39/0.21 | 41/61/31 | -0.81 | 0.00 | 0.03 |
| TROLL WARLOCK | 8.22 | 21.17 | 0.16 | 0.99 | 3704 | 9 | 2/4 | 14 | 6 | 0.51/0.39/0.21 | 34/61/31 | -0.13 | 0.00 | 0.03 |
| SKYBORNE_H WARRIOR | 9.40 | 25.32 | 0.16 | 0.99 | 3704 | 7 | 3/6 | 14 | 6 | 0.63/0.40/0.22 | 61/63/31 | -0.96 | 0.00 | 0.02 |
| SKYBORNE_H HUNTER | 7.74 | 20.19 | 0.16 | 0.99 | 3704 | 7 | 3/4 | 14 | 6 | 0.63/0.39/0.21 | 61/60/31 | -0.96 | 0.00 | 0.02 |
| SKYBORNE_H ROGUE | 8.70 | 23.18 | 0.16 | 0.99 | 3704 | 7 | 2/4 | 14 | 6 | 0.61/0.39/0.21 | 60/60/31 | -0.84 | 0.00 | 0.02 |
| SKYBORNE_H SHAMAN | 8.70 | 23.18 | 0.16 | 0.99 | 3704 | 7 | 2/4 | 14 | 6 | 0.62/0.39/0.21 | 61/60/31 | -0.86 | 0.00 | 0.01 |
| SKYBORNE_H DRUID | 8.70 | 23.18 | 0.16 | 0.99 | 3704 | 7 | 2/4 | 14 | 6 | 0.61/0.39/0.21 | 60/60/31 | -0.84 | 0.00 | 0.02 |

### Alle Kombinationen, explorer

| Kombination | Modellstunden 1–20 | Modellstunden 1–30 | P2 Deckung min | P2 Grind max | P4 längster Weg yd | P5 | P6 nie/später | P7 | P9 | G3 1–10/11–20/21–30 | Quests 1–10/11–20/21–30 | G7 | G8 h | G10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HUMAN WARRIOR | 9.06 | 24.28 | 0.11 | 0.99 | 2366 | 31 | 13/15 | 13 | 7 | 0.56/0.62/0.17 | 60/103/33 | -0.98 | 0.00 | 0.00 |
| HUMAN PALADIN | 8.91 | 23.64 | 0.11 | 0.99 | 2366 | 31 | 13/15 | 13 | 7 | 0.56/0.61/0.17 | 61/102/33 | -0.98 | 0.00 | 0.00 |
| HUMAN HUNTER | 8.06 | 19.47 | 0.11 | 0.99 | 2366 | 31 | 14/15 | 13 | 7 | 0.56/0.61/0.17 | 60/102/33 | -0.98 | 0.00 | 0.00 |
| HUMAN ROGUE | 8.63 | 22.25 | 0.11 | 0.99 | 2366 | 31 | 13/15 | 13 | 7 | 0.56/0.61/0.17 | 61/102/33 | -0.98 | 0.00 | 0.00 |
| HUMAN PRIEST | 8.77 | 22.95 | 0.11 | 0.99 | 2366 | 31 | 14/15 | 14 | 7 | 0.56/0.61/0.17 | 62/102/33 | -0.99 | 0.00 | 0.00 |
| HUMAN MAGE | 8.34 | 20.86 | 0.11 | 0.99 | 2366 | 31 | 13/15 | 13 | 7 | 0.56/0.61/0.17 | 60/102/33 | -0.98 | 0.00 | 0.00 |
| HUMAN WARLOCK | 8.19 | 20.15 | 0.11 | 0.99 | 2366 | 31 | 13/15 | 13 | 7 | 0.57/0.61/0.17 | 62/102/33 | -0.98 | 0.00 | 0.00 |
| DWARF WARRIOR | 9.24 | 24.46 | 0.11 | 0.99 | 2366 | 23 | 12/10 | 14 | 7 | 0.61/0.58/0.17 | 52/97/33 | -0.14 | 0.00 | 0.01 |
| DWARF PALADIN | 9.09 | 23.82 | 0.11 | 0.99 | 2366 | 23 | 12/10 | 14 | 7 | 0.61/0.57/0.17 | 52/96/33 | -0.14 | 0.00 | 0.01 |
| DWARF HUNTER | 8.22 | 19.62 | 0.11 | 0.99 | 2366 | 25 | 12/11 | 14 | 7 | 0.63/0.59/0.17 | 54/98/33 | -0.51 | 0.00 | 0.01 |
| DWARF ROGUE | 8.78 | 22.40 | 0.11 | 0.99 | 2366 | 23 | 12/10 | 14 | 7 | 0.62/0.57/0.17 | 53/96/33 | -0.19 | 0.00 | 0.01 |
| DWARF PRIEST | 8.94 | 23.11 | 0.11 | 0.99 | 2366 | 23 | 13/10 | 14 | 7 | 0.61/0.57/0.17 | 52/96/33 | -0.14 | 0.00 | 0.01 |
| DWARF SHAMAN | 8.79 | 22.41 | 0.11 | 0.99 | 2366 | 23 | 12/10 | 14 | 7 | 0.61/0.57/0.17 | 52/96/33 | -0.14 | 0.00 | 0.00 |
| NIGHTELF WARRIOR | 9.04 | 24.26 | 0.11 | 0.99 | 2366 | 26 | 12/10 | 14 | 7 | 0.66/0.61/0.17 | 58/99/33 | -0.60 | 0.00 | 0.00 |
| NIGHTELF HUNTER | 8.20 | 19.61 | 0.11 | 0.99 | 2366 | 27 | 12/14 | 14 | 7 | 0.66/0.62/0.17 | 57/101/33 | -0.91 | 0.00 | 0.01 |
| NIGHTELF ROGUE | 8.63 | 22.25 | 0.11 | 0.99 | 2366 | 25 | 13/10 | 14 | 7 | 0.66/0.60/0.17 | 57/98/33 | -0.59 | 0.00 | 0.00 |
| NIGHTELF PRIEST | 8.76 | 23.02 | 0.11 | 0.99 | 2366 | 26 | 14/10 | 15 | 9 | 0.67/0.61/0.17 | 59/100/33 | -0.65 | 0.12 | 0.00 |
| NIGHTELF DRUID | 8.63 | 22.25 | 0.11 | 0.99 | 2366 | 25 | 12/10 | 14 | 7 | 0.66/0.60/0.17 | 57/98/33 | -0.59 | 0.00 | 0.00 |
| GNOME WARRIOR | 9.24 | 24.46 | 0.11 | 0.99 | 2366 | 23 | 12/10 | 14 | 7 | 0.61/0.58/0.17 | 52/97/33 | -0.14 | 0.00 | 0.01 |
| GNOME ROGUE | 8.78 | 22.40 | 0.11 | 0.99 | 2366 | 23 | 12/10 | 14 | 7 | 0.62/0.57/0.17 | 53/96/33 | -0.19 | 0.00 | 0.01 |
| GNOME PRIEST | 8.94 | 23.11 | 0.11 | 0.99 | 2366 | 23 | 13/10 | 14 | 7 | 0.61/0.57/0.17 | 52/96/33 | -0.14 | 0.00 | 0.01 |
| GNOME MAGE | 8.49 | 21.00 | 0.11 | 0.99 | 2366 | 23 | 12/10 | 14 | 7 | 0.61/0.57/0.17 | 52/96/33 | -0.14 | 0.00 | 0.01 |
| GNOME WARLOCK | 8.35 | 20.31 | 0.11 | 0.99 | 2366 | 24 | 12/10 | 14 | 7 | 0.62/0.57/0.17 | 53/96/33 | -0.20 | 0.00 | 0.01 |
| SKYBORNE_A WARRIOR | 9.07 | 24.30 | 0.11 | 0.99 | 2366 | 23 | 14/11 | 14 | 7 | 0.56/0.60/0.17 | 59/101/33 | -0.69 | 0.00 | 0.00 |
| SKYBORNE_A HUNTER | 7.97 | 19.38 | 0.11 | 0.99 | 2366 | 24 | 14/14 | 14 | 7 | 0.62/0.59/0.17 | 62/100/33 | -0.95 | 0.00 | 0.00 |
| SKYBORNE_A ROGUE | 8.66 | 22.28 | 0.11 | 0.99 | 2366 | 23 | 14/11 | 14 | 7 | 0.53/0.59/0.17 | 58/100/33 | -0.61 | 0.00 | 0.00 |
| SKYBORNE_A MAGE | 8.34 | 20.86 | 0.11 | 0.99 | 2366 | 24 | 14/11 | 14 | 7 | 0.53/0.60/0.17 | 59/101/33 | -0.77 | 0.00 | 0.00 |
| SKYBORNE_A DRUID | 8.69 | 22.31 | 0.11 | 0.99 | 2366 | 24 | 14/11 | 14 | 7 | 0.53/0.60/0.17 | 58/101/33 | -0.71 | 0.00 | 0.00 |
| ORC WARRIOR | 9.33 | 24.97 | 0.16 | 0.99 | 3695 | 14 | 13/11 | 15 | 6 | 0.63/0.40/0.26 | 42/70/35 | -0.82 | 0.00 | 0.03 |
| ORC HUNTER | 7.71 | 20.02 | 0.16 | 0.99 | 3695 | 13 | 11/10 | 15 | 6 | 0.66/0.39/0.25 | 43/67/35 | -0.94 | 0.00 | 0.03 |
| ORC ROGUE | 8.61 | 22.86 | 0.16 | 0.99 | 3695 | 13 | 12/10 | 15 | 6 | 0.63/0.39/0.25 | 42/67/35 | -0.82 | 0.00 | 0.03 |
| ORC SHAMAN | 8.59 | 22.84 | 0.16 | 0.99 | 3695 | 13 | 13/10 | 15 | 6 | 0.65/0.39/0.25 | 44/67/35 | -0.91 | 0.00 | 0.02 |
| ORC MAGE | 8.17 | 21.45 | 0.16 | 0.99 | 3695 | 13 | 11/10 | 15 | 6 | 0.63/0.39/0.25 | 42/67/35 | -0.82 | 0.00 | 0.03 |
| ORC WARLOCK | 8.03 | 20.87 | 0.16 | 0.99 | 3695 | 13 | 11/10 | 15 | 8 | 0.51/0.39/0.26 | 35/67/39 | -0.35 | 0.14 | 0.04 |
| UNDEAD WARRIOR | 9.19 | 24.83 | 0.16 | 0.99 | 3695 | 19 | 15/13 | 17 | 6 | 0.65/0.40/0.26 | 52/69/35 | -0.88 | 0.00 | 0.02 |
| UNDEAD PALADIN | 9.00 | 24.22 | 0.16 | 0.99 | 3695 | 18 | 13/10 | 17 | 6 | 0.59/0.39/0.25 | 52/66/35 | -0.50 | 0.00 | 0.02 |
| UNDEAD ROGUE | 8.55 | 22.81 | 0.16 | 0.99 | 3695 | 18 | 14/10 | 17 | 6 | 0.58/0.39/0.25 | 49/66/35 | -0.50 | 0.00 | 0.02 |
| UNDEAD PRIEST | 8.78 | 23.52 | 0.16 | 0.99 | 3695 | 19 | 13/10 | 18 | 6 | 0.59/0.39/0.25 | 52/66/35 | -0.50 | 0.00 | 0.03 |
| UNDEAD MAGE | 8.10 | 21.38 | 0.16 | 0.99 | 3695 | 18 | 12/10 | 17 | 6 | 0.58/0.39/0.25 | 50/66/35 | -0.50 | 0.00 | 0.03 |
| UNDEAD WARLOCK | 7.87 | 20.71 | 0.16 | 0.99 | 3695 | 18 | 14/10 | 17 | 8 | 0.59/0.39/0.26 | 51/66/39 | -0.50 | 0.14 | 0.03 |
| TAUREN WARRIOR | 9.86 | 25.50 | 0.16 | 0.99 | 3695 | 14 | 11/13 | 15 | 6 | 0.65/0.40/0.26 | 55/70/35 | -0.67 | 0.00 | 0.05 |
| TAUREN HUNTER | 8.27 | 20.57 | 0.16 | 0.99 | 3695 | 14 | 10/11 | 15 | 6 | 0.65/0.39/0.25 | 54/67/35 | -0.67 | 0.00 | 0.06 |
| TAUREN SHAMAN | 9.14 | 23.39 | 0.16 | 0.99 | 3695 | 14 | 10/11 | 15 | 6 | 0.65/0.39/0.25 | 55/67/35 | -0.67 | 0.00 | 0.04 |
| TAUREN DRUID | 9.14 | 23.39 | 0.16 | 0.99 | 3695 | 14 | 10/11 | 15 | 6 | 0.65/0.39/0.25 | 55/67/35 | -0.67 | 0.00 | 0.05 |
| TROLL WARRIOR | 9.33 | 24.97 | 0.16 | 0.99 | 3695 | 14 | 13/11 | 15 | 6 | 0.63/0.40/0.26 | 42/70/35 | -0.82 | 0.00 | 0.03 |
| TROLL HUNTER | 7.71 | 20.02 | 0.16 | 0.99 | 3695 | 13 | 11/10 | 15 | 6 | 0.66/0.39/0.25 | 43/67/35 | -0.94 | 0.00 | 0.03 |
| TROLL ROGUE | 8.61 | 22.86 | 0.16 | 0.99 | 3695 | 13 | 12/10 | 15 | 6 | 0.63/0.39/0.25 | 42/67/35 | -0.82 | 0.00 | 0.03 |
| TROLL PRIEST | 8.83 | 23.57 | 0.16 | 0.99 | 3695 | 13 | 13/10 | 15 | 6 | 0.63/0.39/0.25 | 42/67/35 | -0.82 | 0.00 | 0.03 |
| TROLL SHAMAN | 8.59 | 22.84 | 0.16 | 0.99 | 3695 | 13 | 13/10 | 15 | 6 | 0.65/0.39/0.25 | 44/67/35 | -0.91 | 0.00 | 0.02 |
| TROLL MAGE | 8.17 | 21.45 | 0.16 | 0.99 | 3695 | 13 | 11/10 | 15 | 6 | 0.63/0.39/0.25 | 42/67/35 | -0.82 | 0.00 | 0.03 |
| TROLL WARLOCK | 8.03 | 20.87 | 0.16 | 0.99 | 3695 | 13 | 11/10 | 15 | 8 | 0.51/0.39/0.26 | 35/67/39 | -0.35 | 0.14 | 0.04 |
| SKYBORNE_H WARRIOR | 9.10 | 24.74 | 0.16 | 0.99 | 3695 | 10 | 13/12 | 15 | 6 | 0.63/0.40/0.26 | 61/69/35 | -0.96 | 0.00 | 0.02 |
| SKYBORNE_H HUNTER | 7.51 | 19.81 | 0.16 | 0.99 | 3695 | 10 | 12/10 | 15 | 6 | 0.63/0.39/0.25 | 61/66/35 | -0.96 | 0.00 | 0.02 |
| SKYBORNE_H ROGUE | 8.43 | 22.69 | 0.16 | 0.99 | 3695 | 10 | 12/10 | 15 | 6 | 0.61/0.39/0.25 | 60/66/35 | -0.84 | 0.00 | 0.02 |
| SKYBORNE_H SHAMAN | 8.43 | 22.68 | 0.16 | 0.99 | 3695 | 10 | 12/10 | 15 | 6 | 0.62/0.39/0.25 | 61/66/35 | -0.86 | 0.00 | 0.01 |
| SKYBORNE_H DRUID | 8.43 | 22.69 | 0.16 | 0.99 | 3695 | 10 | 12/10 | 15 | 6 | 0.61/0.39/0.25 | 60/66/35 | -0.84 | 0.00 | 0.02 |


## Vorher: start route of origin/main 65900c1 (Welle 5), measured with the tool of Welle 6b

Modellstunden aus `tools/routekit/sim.py` mit den Parametern aus `data/plan/params.toml`, keine Vorhersage echter Spielzeit. Status: erfüllt oder verletzt (Zahl der Kombinationen) gegen den Grenzwert aus `data/plan/params.toml`; Bericht ohne Grenzwert; offen, wenn nicht prüfbar. Bänder 1–10, 11–20, 21–30 nach der geplanten Stufe des Schritts. Seit Welle 6b bricht jede Überschreitung, die keine gemessene Ausnahme in `data/plan/route-exceptions.toml` deckt, den CI-Job „Route quality“ ab.

P1 Determinismus: Prüfsumme `4f2441017b79881e6886260a4bcb84e5c2be881cbb8e15f27e17c8d8d35a041c`, zweiter Lauf gleich.

### Modellstunden 1–30 je Fraktion

| Modus | Fraktion | schnellste | Median | langsamste | Median 1–20 |
| --- | --- | --- | --- | --- | --- |
| speed | Alliance | 21.12 (SKYBORNE_A HUNTER) | 24.76 | 26.87 (GNOME WARRIOR) | 10.23 |
| speed | Horde | 20.84 (SKYBORNE_H HUNTER) | 24.70 | 27.67 (TAUREN WARRIOR) | 10.38 |
| explorer | Alliance | 20.73 (SKYBORNE_A HUNTER) | 25.09 | 26.10 (GNOME WARRIOR) | 10.02 |
| explorer | Horde | 20.49 (SKYBORNE_H HUNTER) | 24.24 | 28.51 (TAUREN DRUID) | 9.90 |

### Kennzahlen mit den fünf schlechtesten Kombinationen

| Id | Modus | Kennzahl | Grenzwert | Status | schlechteste 5 |
| --- | --- | --- | --- | --- | --- |
| h30 | speed | Modellstunden 1–30 | – | Bericht | TAUREN WARRIOR 27.67; TAUREN DRUID 27.41; DWARF WARRIOR 26.87; GNOME WARRIOR 26.87; DWARF PRIEST 26.83 |
| h30 | explorer | Modellstunden 1–30 | – | Bericht | TAUREN DRUID 28.51; TAUREN WARRIOR 27.10; UNDEAD PALADIN 26.51; SKYBORNE_H DRUID 26.21; DWARF WARRIOR 26.10 |
| xph | speed | XP je Modellstunde 1–20 (Prüfband 22b) | 8150–32800 | erfüllt | TAUREN DRUID 12765; TAUREN WARRIOR 14233; SKYBORNE_H DRUID 14742; NIGHTELF DRUID 14891; UNDEAD MAGE 14933 |
| xph | explorer | XP je Modellstunde 1–20 (Prüfband 22b) | 8150–32800 | erfüllt | TAUREN DRUID 12519; TAUREN WARRIOR 14608; UNDEAD PALADIN 14762; NIGHTELF DRUID 15265; UNDEAD MAGE 15325 |
| P2 | speed | P2 kleinste Deckung eines Moduls (Quest- + Ziel-Kill-XP) | ≥ 0.90 | verletzt (56) | ORC HUNTER 0.22; ORC MAGE 0.22; ORC ROGUE 0.22; ORC SHAMAN 0.22; ORC WARLOCK 0.22 |
| P2 | explorer | P2 kleinste Deckung eines Moduls (Quest- + Ziel-Kill-XP) | ≥ 0.90 | verletzt (56) | SKYBORNE_H DRUID 0.21; SKYBORNE_H SHAMAN 0.21; SKYBORNE_H HUNTER 0.21; SKYBORNE_H WARRIOR 0.22; SKYBORNE_H ROGUE 0.22 |
| P2g | speed | P2 größter Grind-Anteil einer Stufe | ≤ 0.10 | verletzt (56) | DWARF WARRIOR 0.99; GNOME WARRIOR 0.99; HUMAN WARRIOR 0.99; NIGHTELF WARRIOR 0.99; SKYBORNE_A WARRIOR 0.99 |
| P2g | explorer | P2 größter Grind-Anteil einer Stufe | ≤ 0.10 | verletzt (56) | DWARF WARRIOR 0.99; GNOME WARRIOR 0.99; HUMAN WARRIOR 0.99; NIGHTELF WARRIOR 0.99; SKYBORNE_A WARRIOR 0.99 |
| P3 | speed | P3 Ziehungen schlechter als Startlösung (von 16) | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P3 | explorer | P3 Ziehungen schlechter als Startlösung (von 16) | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P3h | speed | P3 Modellstunden 1–30, längste der 16 Ziehungen | – | Bericht | TAUREN WARRIOR 37.69; UNDEAD WARRIOR 36.53; TAUREN DRUID 36.48; DWARF WARRIOR 36.32; GNOME WARRIOR 36.32 |
| P3h | explorer | P3 Modellstunden 1–30, längste der 16 Ziehungen | – | Bericht | TAUREN DRUID 37.03; TAUREN WARRIOR 36.34; UNDEAD PALADIN 34.86; DWARF WARRIOR 34.68; GNOME WARRIOR 34.68 |
| P4 | speed | P4 lange Einzelquest-Wege im Gebiet (über 0,05 Modellstunden, unter ½ Routenrate) | ≤ 0 | verletzt (56) | DWARF HUNTER 14; DWARF ROGUE 13; GNOME ROGUE 13; SKYBORNE_A HUNTER 13; DWARF SHAMAN 12 |
| P4 | explorer | P4 lange Einzelquest-Wege im Gebiet (über 0,05 Modellstunden, unter ½ Routenrate) | ≤ 0 | verletzt (56) | DWARF HUNTER 15; DWARF ROGUE 14; GNOME MAGE 14; GNOME ROGUE 14; NIGHTELF HUNTER 14 |
| P4b | speed | P4 lange Einzelquest-Wege mehr als Startlösung | ≤ Startlösung | erfüllt | ORC HUNTER 0; ORC MAGE 0; ORC SHAMAN 0; ORC WARRIOR 0; SKYBORNE_H HUNTER 0 |
| P4b | explorer | P4 lange Einzelquest-Wege mehr als Startlösung | ≤ Startlösung | erfüllt | ORC HUNTER 0; ORC MAGE 0; ORC SHAMAN 0; ORC WARRIOR 0; SKYBORNE_H HUNTER 0 |
| P4yd | speed | P4 längster Fußweg im selben Gebiet (yd) | – | Bericht | DWARF WARRIOR 4257; GNOME WARRIOR 4257; HUMAN WARRIOR 4257; NIGHTELF WARRIOR 4257; SKYBORNE_A WARRIOR 4257 |
| P4yd | explorer | P4 längster Fußweg im selben Gebiet (yd) | – | Bericht | DWARF WARRIOR 4257; GNOME WARRIOR 4257; HUMAN WARRIOR 4257; NIGHTELF WARRIOR 4257; SKYBORNE_A WARRIOR 4257 |
| P5 | speed | P5 vermeidbare Rückkehren | – | Bericht | HUMAN HUNTER 27; HUMAN MAGE 26; HUMAN PRIEST 26; HUMAN WARLOCK 26; HUMAN WARRIOR 26 |
| P5 | explorer | P5 vermeidbare Rückkehren | – | Bericht | GNOME WARLOCK 39; HUMAN PRIEST 37; HUMAN WARLOCK 37; HUMAN HUNTER 36; HUMAN MAGE 36 |
| P5b | speed | P5 vermeidbare Rückkehren mehr als Startlösung | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P5b | explorer | P5 vermeidbare Rückkehren mehr als Startlösung | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P5w | speed | P5 verschwendete Wege | ≤ 0 | verletzt (56) | HUMAN PRIEST 14; HUMAN WARRIOR 14; HUMAN HUNTER 13; HUMAN MAGE 13; HUMAN PALADIN 13 |
| P5w | explorer | P5 verschwendete Wege | ≤ 0 | verletzt (56) | HUMAN PRIEST 15; HUMAN MAGE 14; HUMAN WARLOCK 14; HUMAN WARRIOR 14; GNOME WARLOCK 13 |
| P6 | speed | P6 vorbeigelaufen, nie genommen | ≤ 0 | verletzt (36) | ORC WARLOCK 12; TROLL WARLOCK 12; UNDEAD WARLOCK 9; TAUREN DRUID 8; TAUREN SHAMAN 6 |
| P6 | explorer | P6 vorbeigelaufen, nie genommen | ≤ 0 | verletzt (56) | ORC WARLOCK 14; TROLL WARLOCK 14; SKYBORNE_H DRUID 13; UNDEAD WARLOCK 12; UNDEAD MAGE 11 |
| P6l | speed | P6 vorbeigelaufen, erst später genommen | ≤ 0 | verletzt (54) | TAUREN HUNTER 19; TAUREN SHAMAN 19; TAUREN DRUID 18; TAUREN WARRIOR 18; HUMAN PRIEST 15 |
| P6l | explorer | P6 vorbeigelaufen, erst später genommen | ≤ 0 | verletzt (56) | NIGHTELF HUNTER 21; NIGHTELF DRUID 20; TAUREN DRUID 20; TAUREN HUNTER 20; TAUREN SHAMAN 20 |
| P6z | speed | P6 vorbeigelaufen, braucht ein Gebiet, das die Route nicht mehr besucht (Wächter P9) | – | Bericht | NIGHTELF PRIEST 61; DWARF ROGUE 51; DWARF SHAMAN 51; GNOME ROGUE 51; DWARF HUNTER 50 |
| P6z | explorer | P6 vorbeigelaufen, braucht ein Gebiet, das die Route nicht mehr besucht (Wächter P9) | – | Bericht | NIGHTELF PRIEST 80; NIGHTELF DRUID 56; NIGHTELF ROGUE 55; DWARF ROGUE 52; GNOME ROGUE 52 |
| P6n | speed | P6 vorbeigelaufen, lohnt nicht (XP je Zusatzsekunde unter der Routenrate) | – | Bericht | TROLL PRIEST 12; ORC ROGUE 9; TROLL ROGUE 9; TROLL MAGE 8; GNOME WARLOCK 7 |
| P6n | explorer | P6 vorbeigelaufen, lohnt nicht (XP je Zusatzsekunde unter der Routenrate) | – | Bericht | TROLL PRIEST 17; TROLL MAGE 13; ORC ROGUE 12; TROLL ROGUE 12; UNDEAD PRIEST 11 |
| P7 | speed | P7 Questlog-Spitze | ≤ 35 | erfüllt | NIGHTELF DRUID 14; NIGHTELF HUNTER 14; NIGHTELF PRIEST 14; NIGHTELF ROGUE 14; NIGHTELF WARRIOR 14 |
| P7 | explorer | P7 Questlog-Spitze | ≤ 35 | erfüllt | UNDEAD PALADIN 19; UNDEAD PRIEST 19; UNDEAD MAGE 18; UNDEAD ROGUE 18; UNDEAD WARLOCK 18 |
| P7o | speed | P7 angenommen und nie abgegeben | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P7o | explorer | P7 angenommen und nie abgegeben | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P8 | speed | P8 Annahme über Stufe + 2, graue Abgabe, Ausreißer | ≤ 0 | verletzt (36) | TAUREN WARRIOR 4; ORC WARRIOR 3; SKYBORNE_H WARRIOR 3; TROLL WARRIOR 3; UNDEAD WARRIOR 3 |
| P8 | explorer | P8 Annahme über Stufe + 2, graue Abgabe, Ausreißer | ≤ 0 | verletzt (38) | SKYBORNE_A DRUID 4; SKYBORNE_A HUNTER 4; SKYBORNE_A MAGE 4; SKYBORNE_A ROGUE 4; SKYBORNE_A WARRIOR 4 |
| P9 | speed | P9 Gebietswechsel | – | Bericht | DWARF PRIEST 17; NIGHTELF DRUID 16; SKYBORNE_A DRUID 16; UNDEAD WARLOCK 16; GNOME WARLOCK 15 |
| P9 | explorer | P9 Gebietswechsel | – | Bericht | GNOME WARLOCK 21; HUMAN WARLOCK 21; NIGHTELF DRUID 21; SKYBORNE_A DRUID 19; TAUREN DRUID 18 |
| P9b | speed | P9 Gebietswechsel mehr als Startlösung | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P9b | explorer | P9 Gebietswechsel mehr als Startlösung | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P9q | speed | P9 Quests je Gebietsbesuch | – | Bericht | TROLL PRIEST 9.31; UNDEAD WARLOCK 9.65; DWARF PRIEST 10.28; ORC WARLOCK 10.50; TROLL WARLOCK 10.50 |
| P9q | explorer | P9 Quests je Gebietsbesuch | – | Bericht | TAUREN DRUID 10.16; GNOME WARLOCK 10.23; TROLL PRIEST 10.62; HUMAN WARLOCK 10.91; NIGHTELF DRUID 11.09 |
| P11 | speed | P11 Modellstunden 1–30 Profil langsam (Krieger-Faktor) | – | Bericht | TAUREN DRUID 29.60; UNDEAD WARLOCK 29.45; UNDEAD MAGE 28.41; DWARF PRIEST 28.28; GNOME MAGE 28.20 |
| P11 | explorer | P11 Modellstunden 1–30 Profil langsam (Krieger-Faktor) | – | Bericht | TAUREN DRUID 30.52; UNDEAD WARLOCK 28.38; SKYBORNE_H DRUID 28.11; GNOME MAGE 27.90; NIGHTELF DRUID 27.87 |
| P11f | speed | P11 Modellstunden 1–30 Profil schnell (Jäger-Faktor) | – | Bericht | TAUREN DRUID 24.50; UNDEAD WARLOCK 24.38; UNDEAD MAGE 23.30; DWARF PRIEST 23.23; GNOME MAGE 23.16 |
| P11f | explorer | P11 Modellstunden 1–30 Profil schnell (Jäger-Faktor) | – | Bericht | TAUREN DRUID 25.83; UNDEAD WARLOCK 23.79; SKYBORNE_H DRUID 23.67; NIGHTELF DRUID 23.45; GNOME MAGE 23.25 |
| P11b | speed | P11 Mehrstunden gegen Startlösung, Profil langsam oder schnell | ≤ Startlösung | erfüllt | DWARF HUNTER 0.00; DWARF PALADIN 0.00; DWARF PRIEST 0.00; DWARF ROGUE 0.00; DWARF SHAMAN 0.00 |
| P11b | explorer | P11 Mehrstunden gegen Startlösung, Profil langsam oder schnell | ≤ Startlösung | erfüllt | DWARF HUNTER 0.00; DWARF PALADIN 0.00; DWARF PRIEST 0.00; DWARF ROGUE 0.00; DWARF SHAMAN 0.00 |
| G1 | speed | G1 Linter-Fehler | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G1 | explorer | G1 Linter-Fehler | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G2 | speed | G2 Hänger im Simulator | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G2 | explorer | G2 Hänger im Simulator | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G3 | speed | G3 kleinste Quest-XP-Deckung eines Bands | ≥ 0.80 | verletzt (56) | ORC HUNTER 0.23; ORC MAGE 0.23; ORC SHAMAN 0.23; ORC WARRIOR 0.23; SKYBORNE_H DRUID 0.23 |
| G3 | explorer | G3 kleinste Quest-XP-Deckung eines Bands | ≥ 0.80 | verletzt (56) | ORC HUNTER 0.27; ORC MAGE 0.27; ORC SHAMAN 0.27; ORC WARRIOR 0.27; SKYBORNE_H HUNTER 0.27 |
| G4 | speed | G4 Abstand zur besten Deckung im Band | ≤ 0.10 | verletzt (48) | ORC ROGUE 0.35; ORC WARRIOR 0.35; TROLL ROGUE 0.35; TROLL WARRIOR 0.35; DWARF PALADIN 0.33 |
| G4 | explorer | G4 Abstand zur besten Deckung im Band | ≤ 0.10 | verletzt (56) | TAUREN WARRIOR 0.49; TAUREN SHAMAN 0.48; DWARF PALADIN 0.48; DWARF SHAMAN 0.48; DWARF WARRIOR 0.47 |
| G5 | speed | G5 Questzahl: meiste / eigene je Band | ≤ 1.25 | verletzt (45) | ORC ROGUE 1.96; TROLL ROGUE 1.96; ORC MAGE 1.91; ORC WARRIOR 1.91; TROLL WARRIOR 1.91 |
| G5 | explorer | G5 Questzahl: meiste / eigene je Band | ≤ 1.25 | verletzt (51) | TROLL ROGUE 1.96; ORC MAGE 1.92; ORC ROGUE 1.92; ORC WARRIOR 1.92; TROLL WARRIOR 1.92 |
| G6 | speed | G6 Laufweg je Quest-XP / Median je Band | ≤ 1.20 | verletzt (13) | TAUREN DRUID 2.01; UNDEAD WARLOCK 1.66; TAUREN SHAMAN 1.55; TAUREN WARRIOR 1.55; TAUREN HUNTER 1.49 |
| G6 | explorer | G6 Laufweg je Quest-XP / Median je Band | ≤ 1.20 | verletzt (27) | TAUREN DRUID 2.44; TAUREN WARRIOR 1.65; TAUREN SHAMAN 1.64; TAUREN HUNTER 1.59; UNDEAD WARLOCK 1.47 |
| G7 | speed | G7 Abweichung der Ankunftsstufe vom Beginn des ersten Kernblocks | ≤ 1.00 | verletzt (56) | SKYBORNE_H SHAMAN 3.35; SKYBORNE_H HUNTER 3.29; SKYBORNE_H DRUID 3.08; SKYBORNE_H WARRIOR 3.07; SKYBORNE_H ROGUE 2.99 |
| G7 | explorer | G7 Abweichung der Ankunftsstufe vom Beginn des ersten Kernblocks | ≤ 1.00 | verletzt (56) | SKYBORNE_A HUNTER 4.87; SKYBORNE_H SHAMAN 4.86; SKYBORNE_A DRUID 4.85; SKYBORNE_H HUNTER 4.78; SKYBORNE_A MAGE 4.74 |
| G8 | speed | G8 längster Klasseneinschub (Modellstunden) | ≤ 0.17 | verletzt (29) | ORC WARLOCK 2.42; TROLL WARLOCK 2.42; UNDEAD WARLOCK 2.42; GNOME MAGE 2.02; HUMAN MAGE 2.02 |
| G8 | explorer | G8 längster Klasseneinschub (Modellstunden) | ≤ 0.17 | verletzt (38) | ORC WARLOCK 2.20; TROLL WARLOCK 2.20; UNDEAD WARLOCK 2.20; TAUREN DRUID 2.16; SKYBORNE_H DRUID 2.13 |
| G8s | speed | G8 Klasseneinschübe gesamt (Modellstunden) | ≤ 0.50 | verletzt (24) | UNDEAD WARLOCK 3.92; NIGHTELF DRUID 2.95; SKYBORNE_A DRUID 2.78; TROLL MAGE 2.69; UNDEAD MAGE 2.67 |
| G8s | explorer | G8 Klasseneinschübe gesamt (Modellstunden) | ≤ 0.50 | verletzt (32) | TAUREN DRUID 4.97; SKYBORNE_H DRUID 3.86; UNDEAD WARLOCK 3.70; NIGHTELF DRUID 3.45; TROLL MAGE 2.91 |
| G9 | speed | G9 train-Schritte auf der Route (Lehrerwege prüfbar ab einem) | – | offen (keine train-Schritte in den Routen) | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G9 | explorer | G9 train-Schritte auf der Route (Lehrerwege prüfbar ab einem) | – | offen (keine train-Schritte in den Routen) | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| G10 | speed | G10 Rückstand zur besten Route der Klasse | ≤ 0.10 | verletzt (1) | UNDEAD WARLOCK 0.11; UNDEAD MAGE 0.09; GNOME MAGE 0.08; TAUREN DRUID 0.08; TAUREN HUNTER 0.08 |
| G10 | explorer | G10 Rückstand zur besten Route der Klasse | ≤ 0.10 | verletzt (2) | TAUREN DRUID 0.12; GNOME MAGE 0.10; UNDEAD MAGE 0.10; TROLL MAGE 0.09; TAUREN HUNTER 0.08 |
| G11 | speed | G11 Anteil Routenquests mit eigener Volk-/Klassen-Messung (gilt ab Etikett stabil) | ≥ 1.00 | offen |  |
| G11 | explorer | G11 Anteil Routenquests mit eigener Volk-/Klassen-Messung (gilt ab Etikett stabil) | ≥ 1.00 | offen |  |
| R01 | speed | R01 Abgabe über Questlevel + 5 (H) | ≤ 0 | verletzt (36) | DWARF HUNTER 4; DWARF PALADIN 4; DWARF PRIEST 4; DWARF ROGUE 4; DWARF SHAMAN 4 |
| R01 | explorer | R01 Abgabe über Questlevel + 5 (H) | ≤ 0 | verletzt (56) | SKYBORNE_A DRUID 9; SKYBORNE_A HUNTER 9; SKYBORNE_A MAGE 9; SKYBORNE_A ROGUE 9; SKYBORNE_A WARRIOR 9 |
| R02 | speed | R02 Abgabe ab Questlevel + 10 (H) | ≤ 0 | verletzt (28) | DWARF HUNTER 1; DWARF PALADIN 1; DWARF PRIEST 1; DWARF ROGUE 1; DWARF SHAMAN 1 |
| R02 | explorer | R02 Abgabe ab Questlevel + 10 (H) | ≤ 0 | verletzt (29) | DWARF HUNTER 1; DWARF PALADIN 1; DWARF PRIEST 1; DWARF ROGUE 1; DWARF SHAMAN 1 |
| R04 | speed | R04 Folgequest am selben NPC nicht im selben Schritt (H) | ≤ 0 | verletzt (56) | SKYBORNE_H DRUID 18; SKYBORNE_H HUNTER 18; SKYBORNE_H ROGUE 18; SKYBORNE_H SHAMAN 18; SKYBORNE_H WARRIOR 18 |
| R04 | explorer | R04 Folgequest am selben NPC nicht im selben Schritt (H) | ≤ 0 | verletzt (56) | SKYBORNE_A DRUID 20; SKYBORNE_A HUNTER 20; SKYBORNE_A MAGE 20; SKYBORNE_A ROGUE 20; SKYBORNE_A WARRIOR 20 |
| R05 | speed | R05 späterer Besuch nur zur Annahme (H) | ≤ 0 | verletzt (56) | UNDEAD PRIEST 12; NIGHTELF DRUID 11; NIGHTELF PRIEST 11; NIGHTELF HUNTER 10; NIGHTELF ROGUE 10 |
| R05 | explorer | R05 späterer Besuch nur zur Annahme (H) | ≤ 0 | verletzt (56) | UNDEAD PALADIN 16; UNDEAD PRIEST 16; NIGHTELF PRIEST 15; SKYBORNE_H DRUID 15; NIGHTELF DRUID 14 |
| R06 | speed | R06 aktives Ziel passiert, später eigener Besuch (H) | ≤ 0 | verletzt (12) | HUMAN HUNTER 1; HUMAN MAGE 1; HUMAN PALADIN 1; HUMAN PRIEST 1; HUMAN ROGUE 1 |
| R06 | explorer | R06 aktives Ziel passiert, später eigener Besuch (H) | ≤ 0 | verletzt (12) | HUMAN HUNTER 1; HUMAN MAGE 1; HUMAN PALADIN 1; HUMAN PRIEST 1; HUMAN ROGUE 1 |
| R07 | speed | R07 Zwischenabgabe zwischen zwei nahen Zielen (H) | ≤ 0 | verletzt (6) | UNDEAD MAGE 1; UNDEAD PALADIN 1; UNDEAD PRIEST 1; UNDEAD ROGUE 1; UNDEAD WARLOCK 1 |
| R07 | explorer | R07 Zwischenabgabe zwischen zwei nahen Zielen (H) | ≤ 0 | verletzt (1) | UNDEAD PRIEST 1; DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0 |
| R09 | speed | R09 Rückkehr ins Gebiet mit weniger als 3 Quests (H) | ≤ 0 | verletzt (23) | DWARF PRIEST 7; UNDEAD WARLOCK 7; TROLL PRIEST 6; NIGHTELF DRUID 4; ORC WARLOCK 4 |
| R09 | explorer | R09 Rückkehr ins Gebiet mit weniger als 3 Quests (H) | ≤ 0 | verletzt (31) | DWARF PRIEST 7; NIGHTELF DRUID 7; GNOME WARLOCK 6; HUMAN WARLOCK 6; SKYBORNE_A DRUID 6 |
| R10 | speed | R10 Ruhestein ohne Bedingungen (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R10 | explorer | R10 Ruhestein ohne Bedingungen (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R11 | speed | R11 Bindung ohne späteren Besuch (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R11 | explorer | R11 Bindung ohne späteren Besuch (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R12 | speed | R12 Ruhestein vor Ablauf der Abklingzeit (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R12 | explorer | R12 Ruhestein vor Ablauf der Abklingzeit (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R13 | speed | R13 unbekannter Flugmeister passiert (H) | ≤ 0 | verletzt (56) | UNDEAD WARLOCK 10; ORC WARLOCK 9; TAUREN DRUID 9; TAUREN HUNTER 9; TAUREN SHAMAN 9 |
| R13 | explorer | R13 unbekannter Flugmeister passiert (H) | ≤ 0 | verletzt (56) | UNDEAD WARLOCK 10; ORC ROGUE 9; ORC WARLOCK 9; TAUREN DRUID 9; TAUREN HUNTER 9 |
| R17 | speed | R17 Grind-Schritt ohne Ort (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R17 | explorer | R17 Grind-Schritt ohne Ort (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R18 | speed | R18 Grind trotz annehmbarer Quest in 500 yd (H) | ≤ 0 | verletzt (52) | ORC WARLOCK 3; TROLL WARLOCK 3; TAUREN DRUID 2; TROLL PRIEST 2; UNDEAD PRIEST 2 |
| R18 | explorer | R18 Grind trotz annehmbarer Quest in 500 yd (H) | ≤ 0 | verletzt (47) | GNOME WARLOCK 4; HUMAN WARLOCK 4; DWARF HUNTER 2; DWARF PALADIN 2; DWARF PRIEST 2 |
| R18z | speed | R18 Grind neben Quests, die ein Gebiet außerhalb der Route brauchen oder nicht lohnen | – | Bericht | DWARF PALADIN 9; DWARF ROGUE 9; DWARF SHAMAN 9; DWARF WARRIOR 9; GNOME PRIEST 9 |
| R18z | explorer | R18 Grind neben Quests, die ein Gebiet außerhalb der Route brauchen oder nicht lohnen | – | Bericht | DWARF HUNTER 7; DWARF PALADIN 7; DWARF PRIEST 7; DWARF ROGUE 7; DWARF SHAMAN 7 |
| R19 | speed | R19 Grind ohne vorherige Ankündigung (H) | ≤ 0 | verletzt (56) | ORC WARLOCK 17; TROLL WARLOCK 17; ORC HUNTER 16; ORC MAGE 16; ORC ROGUE 16 |
| R19 | explorer | R19 Grind ohne vorherige Ankündigung (H) | ≤ 0 | verletzt (56) | ORC HUNTER 14; ORC MAGE 14; ORC ROGUE 14; ORC SHAMAN 14; ORC WARLOCK 14 |
| R20 | speed | R20 Eskorten-/Ereignisquests im Speed-Pfad (W) | – | Bericht | TAUREN DRUID 8; TAUREN HUNTER 8; TAUREN SHAMAN 8; TAUREN WARRIOR 8; UNDEAD MAGE 7 |
| R20 | explorer | R20 Eskorten-/Ereignisquests im Speed-Pfad (W) | – | Bericht | TAUREN DRUID 8; TAUREN HUNTER 8; TAUREN SHAMAN 8; TAUREN WARRIOR 8; UNDEAD MAGE 7 |
| R21 | speed | R21 Sammelquests ohne Abbruchregel (W) | – | Bericht | NIGHTELF DRUID 113; NIGHTELF ROGUE 111; HUMAN WARLOCK 110; NIGHTELF HUNTER 110; NIGHTELF PRIEST 110 |
| R21 | explorer | R21 Sammelquests ohne Abbruchregel (W) | – | Bericht | NIGHTELF DRUID 133; NIGHTELF ROGUE 130; NIGHTELF HUNTER 129; NIGHTELF PRIEST 129; NIGHTELF WARRIOR 129 |
| R22 | speed | R22 Gruppen-/Elitequests im Solo-Pfad (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R22 | explorer | R22 Gruppen-/Elitequests im Solo-Pfad (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R23 | speed | R23 nicht verfügbare Quest (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R23 | explorer | R23 nicht verfügbare Quest (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R26 | speed | R26 Hauptstadtbesuch ohne Grund (H) | ≤ 0 | verletzt (6) | UNDEAD WARLOCK 3; ORC WARLOCK 2; TROLL WARLOCK 2; GNOME MAGE 1; HUMAN MAGE 1 |
| R26 | explorer | R26 Hauptstadtbesuch ohne Grund (H) | ≤ 0 | verletzt (7) | UNDEAD WARLOCK 3; ORC WARLOCK 2; TROLL WARLOCK 2; GNOME MAGE 1; HUMAN MAGE 1 |
| R27 | speed | R27 Questziel mehr als 2 Stufen über dem Spieler (W) | – | Bericht | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R27 | explorer | R27 Questziel mehr als 2 Stufen über dem Spieler (W) | – | Bericht | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R28 | speed | R28 Dungeonquest im Speed-Pfad (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R28 | explorer | R28 Dungeonquest im Speed-Pfad (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R30 | speed | R30 Questlog über 40 (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R30 | explorer | R30 Questlog über 40 (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R31 | speed | R31 Quest am Ende noch im Log (W) | – | Bericht | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R31 | explorer | R31 Quest am Ende noch im Log (W) | – | Bericht | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R33 | speed | R33 Etikett stabil ohne Messung (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| R33 | explorer | R33 Etikett stabil ohne Messung (H) | ≤ 0 | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |

### P10 Spannweite der Modellstunden je Band und Fraktion

| Modus | Fraktion | Band | kürzeste | längste | Verhältnis |
| --- | --- | --- | --- | --- | --- |
| speed | Alliance | 1-10 | 2.02 (SKYBORNE_A HUNTER) | 2.47 (GNOME WARRIOR) | 1.22 |
| speed | Alliance | 11-20 | 7.96 (SKYBORNE_A HUNTER) | 10.90 (DWARF PRIEST) | 1.37 |
| speed | Alliance | 21-30 | 11.14 (SKYBORNE_A HUNTER) | 14.46 (NIGHTELF WARRIOR) | 1.30 |
| speed | Horde | 1-10 | 1.98 (SKYBORNE_H HUNTER) | 3.46 (TAUREN WARRIOR) | 1.75 |
| speed | Horde | 11-20 | 7.55 (SKYBORNE_H HUNTER) | 10.78 (TAUREN DRUID) | 1.43 |
| speed | Horde | 21-30 | 11.32 (TAUREN HUNTER) | 14.75 (SKYBORNE_H WARRIOR) | 1.30 |
| explorer | Alliance | 1-10 | 2.01 (SKYBORNE_A HUNTER) | 2.72 (GNOME WARRIOR) | 1.35 |
| explorer | Alliance | 11-20 | 7.42 (SKYBORNE_A HUNTER) | 10.61 (NIGHTELF DRUID) | 1.43 |
| explorer | Alliance | 21-30 | 11.30 (SKYBORNE_A HUNTER) | 14.37 (GNOME WARRIOR) | 1.27 |
| explorer | Horde | 1-10 | 1.97 (SKYBORNE_H HUNTER) | 3.42 (TAUREN WARRIOR) | 1.73 |
| explorer | Horde | 11-20 | 7.32 (SKYBORNE_H HUNTER) | 11.07 (TAUREN DRUID) | 1.51 |
| explorer | Horde | 21-30 | 11.20 (ORC HUNTER) | 14.48 (SKYBORNE_H WARRIOR) | 1.29 |

### G12 Himmelsgeborene je Fraktion

| Volk | Modus | Kombinationen | verletzte Prüfungen (Anzahl Kombinationen) |
| --- | --- | --- | --- |
| SKYBORNE_A | speed | 5 | G3 (5), G4 (5), G5 (2), G6 (1), G7 (5), G8 (3), G8s (2) |
| SKYBORNE_A | explorer | 5 | G3 (5), G4 (5), G6 (2), G7 (5), G8 (4), G8s (3) |
| SKYBORNE_H | speed | 5 | G3 (5), G5 (5), G7 (5), G8 (2), G8s (2) |
| SKYBORNE_H | explorer | 5 | G3 (5), G4 (5), G5 (5), G6 (1), G7 (5), G8 (2), G8s (2) |

### Nicht an der Route prüfbar

- R03: Eigenschaft des Codes, nicht der Route: xp.py und XP.lua rechnen den Questwert aus dem Stufenabstand
- R08: Wegverlängerung durch Kill-Abschnitte: die Daten haben keine Wege der Kills
- R14: Flug gegen Fußweg: data/facts hat kein Flugnetz (TaxiPathNode)
- R15: Klassenreisemittel: keine Teleport-Daten je Klasse
- R16: Tod als Reise: das Routenformat hat keinen solchen Schritt
- R24: Pflichtliste der Klassenquests je Klasse fehlt
- R25: Lehrer im Stufenfenster: die Routen haben keine train-Schritte
- R29: begründete Verzweigung: Strukturfrage des Baukastens (Welle 6b); alle Kombinationen werden simuliert
- R32: Ende bei Stufe 60: die Routen enden bei 30
- R34: Buff-Hinweise: die Routen haben keine
- R35: Looten: Hinweistext, keine Routeneigenschaft

### Alle Kombinationen, speed

| Kombination | Modellstunden 1–20 | Modellstunden 1–30 | P2 Deckung min | P2 Grind max | P4 längster Weg yd | P5 | P6 nie/später | P7 | P9 | G3 1–10/11–20/21–30 | Quests 1–10/11–20/21–30 | G7 | G8 h | G10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HUMAN WARRIOR | 10.61 | 26.63 | 0.27 | 0.99 | 4257 | 26 | 0/14 | 12 | 8 | 0.84/0.33/0.31 | 71/52/64 | -1.91 | 0.29 | 0.03 |
| HUMAN PALADIN | 10.74 | 26.35 | 0.27 | 0.99 | 2874 | 25 | 2/13 | 12 | 9 | 0.83/0.32/0.30 | 70/52/62 | -1.90 | 0.63 | 0.01 |
| HUMAN HUNTER | 8.74 | 21.49 | 0.27 | 0.98 | 2874 | 27 | 0/14 | 12 | 7 | 0.92/0.32/0.30 | 73/51/62 | -2.23 | 0.00 | 0.03 |
| HUMAN ROGUE | 9.80 | 24.45 | 0.27 | 0.99 | 2874 | 25 | 0/13 | 12 | 7 | 0.83/0.32/0.30 | 70/51/62 | -1.90 | 0.00 | 0.02 |
| HUMAN PRIEST | 10.14 | 25.95 | 0.27 | 0.99 | 2874 | 26 | 3/15 | 12 | 13 | 0.85/0.33/0.30 | 73/54/62 | -1.94 | 1.21 | 0.01 |
| HUMAN MAGE | 10.69 | 24.39 | 0.27 | 0.99 | 2874 | 26 | 2/13 | 12 | 11 | 0.86/0.33/0.30 | 71/52/62 | -2.00 | 2.16 | 0.07 |
| HUMAN WARLOCK | 9.09 | 22.53 | 0.27 | 0.98 | 2874 | 26 | 2/13 | 12 | 15 | 0.84/0.36/0.31 | 71/55/64 | -1.93 | 1.25 | 0.00 |
| DWARF WARRIOR | 10.85 | 26.87 | 0.27 | 0.99 | 4257 | 17 | 0/7 | 11 | 8 | 0.71/0.33/0.31 | 56/53/64 | -1.06 | 0.29 | 0.04 |
| DWARF PALADIN | 10.59 | 26.19 | 0.27 | 0.99 | 2874 | 17 | 0/7 | 11 | 7 | 0.70/0.32/0.30 | 55/52/62 | -1.05 | 0.00 | 0.00 |
| DWARF HUNTER | 9.05 | 21.80 | 0.27 | 0.98 | 2874 | 20 | 0/9 | 11 | 7 | 0.79/0.32/0.30 | 59/52/62 | -1.42 | 0.00 | 0.05 |
| DWARF ROGUE | 10.11 | 24.76 | 0.27 | 0.99 | 2874 | 17 | 0/7 | 11 | 7 | 0.72/0.32/0.30 | 56/52/62 | -1.10 | 0.00 | 0.03 |
| DWARF PRIEST | 10.92 | 26.83 | 0.27 | 0.99 | 2874 | 18 | 3/6 | 11 | 17 | 0.73/0.33/0.30 | 60/55/62 | -1.16 | 2.15 | 0.05 |
| DWARF SHAMAN | 10.09 | 24.74 | 0.27 | 0.99 | 2874 | 17 | 0/7 | 11 | 7 | 0.70/0.32/0.30 | 55/52/62 | -1.05 | 0.00 | 0.04 |
| NIGHTELF WARRIOR | 10.40 | 26.42 | 0.27 | 0.99 | 4257 | 22 | 0/7 | 14 | 8 | 0.92/0.33/0.31 | 68/52/64 | -1.81 | 0.29 | 0.02 |
| NIGHTELF HUNTER | 8.88 | 21.62 | 0.27 | 0.98 | 2874 | 22 | 1/7 | 14 | 7 | 1.00/0.32/0.30 | 72/51/62 | -2.15 | 0.00 | 0.04 |
| NIGHTELF ROGUE | 9.69 | 24.34 | 0.27 | 0.99 | 2874 | 22 | 0/7 | 14 | 7 | 0.93/0.32/0.30 | 69/51/62 | -1.87 | 0.00 | 0.01 |
| NIGHTELF PRIEST | 10.38 | 26.02 | 0.27 | 0.99 | 2874 | 23 | 3/7 | 14 | 15 | 0.95/0.33/0.30 | 74/55/62 | -1.94 | 1.37 | 0.02 |
| NIGHTELF DRUID | 11.23 | 25.88 | 0.27 | 0.99 | 2874 | 24 | 2/7 | 14 | 16 | 0.96/0.35/0.30 | 72/57/62 | -2.01 | 2.95 | 0.02 |
| GNOME WARRIOR | 10.85 | 26.87 | 0.27 | 0.99 | 4257 | 17 | 0/7 | 11 | 8 | 0.71/0.33/0.31 | 56/53/64 | -1.06 | 0.29 | 0.04 |
| GNOME ROGUE | 10.11 | 24.76 | 0.27 | 0.99 | 2874 | 17 | 0/7 | 11 | 7 | 0.72/0.32/0.30 | 56/52/62 | -1.10 | 0.00 | 0.03 |
| GNOME PRIEST | 10.47 | 25.60 | 0.27 | 0.99 | 2874 | 18 | 0/6 | 11 | 8 | 0.72/0.32/0.30 | 58/52/62 | -1.11 | 0.10 | 0.00 |
| GNOME MAGE | 10.90 | 24.60 | 0.27 | 0.99 | 2874 | 17 | 2/6 | 11 | 11 | 0.73/0.33/0.30 | 56/53/62 | -1.16 | 2.29 | 0.08 |
| GNOME WARLOCK | 9.38 | 22.81 | 0.27 | 0.98 | 2874 | 21 | 1/7 | 11 | 15 | 0.71/0.36/0.31 | 56/56/64 | -1.11 | 1.25 | 0.01 |
| SKYBORNE_A WARRIOR | 10.12 | 26.09 | 0.27 | 0.99 | 4257 | 18 | 0/4 | 12 | 8 | 0.77/0.34/0.31 | 70/53/63 | -1.97 | 0.29 | 0.01 |
| SKYBORNE_A HUNTER | 8.43 | 21.12 | 0.27 | 0.98 | 2874 | 19 | 0/4 | 12 | 7 | 0.84/0.33/0.30 | 74/52/61 | -2.22 | 0.00 | 0.01 |
| SKYBORNE_A ROGUE | 9.44 | 24.04 | 0.27 | 0.99 | 2874 | 17 | 0/4 | 12 | 7 | 0.75/0.33/0.30 | 69/52/61 | -1.86 | 0.00 | 0.00 |
| SKYBORNE_A MAGE | 10.32 | 23.97 | 0.27 | 0.99 | 2874 | 17 | 2/5 | 12 | 11 | 0.78/0.33/0.30 | 71/53/61 | -2.01 | 2.10 | 0.05 |
| SKYBORNE_A DRUID | 10.83 | 25.43 | 0.27 | 0.99 | 2874 | 18 | 0/4 | 12 | 16 | 0.78/0.36/0.30 | 72/58/61 | -2.07 | 2.78 | 0.00 |
| ORC WARRIOR | 10.45 | 26.38 | 0.22 | 0.99 | 3619 | 14 | 2/3 | 12 | 6 | 0.69/0.37/0.23 | 46/55/37 | -1.31 | 0.00 | 0.02 |
| ORC HUNTER | 9.09 | 21.25 | 0.22 | 0.98 | 3619 | 14 | 0/4 | 11 | 6 | 0.76/0.36/0.23 | 48/53/37 | -1.63 | 0.00 | 0.02 |
| ORC ROGUE | 9.89 | 24.63 | 0.22 | 0.98 | 3619 | 14 | 2/5 | 11 | 8 | 0.69/0.36/0.23 | 45/54/38 | -1.31 | 1.43 | 0.02 |
| ORC SHAMAN | 9.80 | 24.12 | 0.22 | 0.98 | 3619 | 15 | 2/3 | 12 | 6 | 0.72/0.37/0.23 | 49/53/37 | -1.44 | 0.00 | 0.02 |
| ORC MAGE | 9.51 | 22.75 | 0.22 | 0.98 | 3619 | 14 | 1/3 | 11 | 6 | 0.71/0.36/0.23 | 46/53/37 | -1.41 | 0.00 | 0.00 |
| ORC WARLOCK | 9.30 | 23.30 | 0.22 | 0.98 | 3619 | 14 | 12/3 | 11 | 13 | 0.73/0.36/0.25 | 48/53/41 | -1.51 | 2.63 | 0.03 |
| UNDEAD WARRIOR | 10.91 | 26.83 | 0.22 | 0.99 | 3619 | 16 | 3/9 | 12 | 6 | 0.83/0.37/0.23 | 62/55/37 | -2.01 | 0.00 | 0.04 |
| UNDEAD PALADIN | 10.80 | 26.19 | 0.22 | 0.99 | 3619 | 15 | 3/9 | 12 | 6 | 0.77/0.36/0.23 | 60/53/37 | -1.73 | 0.00 | 0.00 |
| UNDEAD ROGUE | 10.45 | 25.20 | 0.22 | 0.98 | 3619 | 14 | 3/10 | 12 | 8 | 0.76/0.36/0.23 | 58/54/38 | -1.70 | 1.43 | 0.05 |
| UNDEAD PRIEST | 11.00 | 26.17 | 0.22 | 0.99 | 3619 | 18 | 5/10 | 12 | 13 | 0.78/0.36/0.24 | 63/53/40 | -1.78 | 1.91 | 0.02 |
| UNDEAD MAGE | 11.20 | 24.76 | 0.22 | 0.98 | 3619 | 15 | 6/8 | 12 | 11 | 0.78/0.37/0.24 | 59/54/38 | -1.80 | 2.67 | 0.09 |
| UNDEAD WARLOCK | 11.11 | 25.11 | 0.22 | 0.98 | 3619 | 15 | 9/9 | 12 | 16 | 0.84/0.36/0.25 | 63/53/41 | -2.06 | 3.92 | 0.11 |
| TAUREN WARRIOR | 11.75 | 27.67 | 0.22 | 0.99 | 3619 | 18 | 6/18 | 13 | 7 | 0.73/0.37/0.23 | 60/55/37 | -1.27 | 0.10 | 0.07 |
| TAUREN HUNTER | 10.31 | 22.47 | 0.22 | 0.98 | 3619 | 18 | 2/19 | 12 | 6 | 0.79/0.36/0.23 | 62/53/37 | -1.51 | 0.00 | 0.08 |
| TAUREN SHAMAN | 11.10 | 25.41 | 0.22 | 0.98 | 3619 | 19 | 6/19 | 13 | 7 | 0.73/0.37/0.23 | 61/53/37 | -1.30 | 0.10 | 0.07 |
| TAUREN DRUID | 13.10 | 27.41 | 0.22 | 0.98 | 3619 | 20 | 8/18 | 12 | 13 | 0.77/0.38/0.23 | 63/58/37 | -1.46 | 2.41 | 0.08 |
| TROLL WARRIOR | 10.45 | 26.38 | 0.22 | 0.99 | 3619 | 14 | 2/3 | 12 | 6 | 0.69/0.37/0.23 | 46/55/37 | -1.31 | 0.00 | 0.02 |
| TROLL HUNTER | 9.09 | 21.25 | 0.22 | 0.98 | 3619 | 14 | 0/4 | 11 | 6 | 0.76/0.36/0.23 | 48/53/37 | -1.63 | 0.00 | 0.02 |
| TROLL ROGUE | 9.89 | 24.63 | 0.22 | 0.98 | 3619 | 14 | 2/5 | 11 | 8 | 0.69/0.36/0.23 | 45/54/38 | -1.31 | 1.43 | 0.02 |
| TROLL PRIEST | 10.69 | 26.15 | 0.22 | 0.99 | 3619 | 15 | 3/6 | 12 | 15 | 0.72/0.36/0.24 | 51/53/40 | -1.42 | 2.24 | 0.02 |
| TROLL SHAMAN | 9.80 | 24.12 | 0.22 | 0.98 | 3619 | 15 | 2/3 | 12 | 6 | 0.72/0.37/0.23 | 49/53/37 | -1.44 | 0.00 | 0.02 |
| TROLL MAGE | 10.76 | 24.32 | 0.22 | 0.98 | 3619 | 14 | 3/3 | 11 | 11 | 0.74/0.37/0.24 | 47/54/38 | -1.52 | 2.69 | 0.07 |
| TROLL WARLOCK | 9.30 | 23.30 | 0.22 | 0.98 | 3619 | 14 | 12/3 | 11 | 13 | 0.73/0.36/0.25 | 48/53/41 | -1.51 | 2.63 | 0.03 |
| SKYBORNE_H WARRIOR | 9.97 | 25.89 | 0.22 | 0.99 | 3619 | 11 | 2/0 | 12 | 6 | 0.97/0.38/0.23 | 85/56/37 | -3.07 | 0.00 | 0.00 |
| SKYBORNE_H HUNTER | 8.68 | 20.84 | 0.22 | 0.98 | 3619 | 12 | 0/1 | 12 | 6 | 1.04/0.37/0.23 | 88/54/37 | -3.29 | 0.00 | 0.00 |
| SKYBORNE_H ROGUE | 9.53 | 24.27 | 0.22 | 0.98 | 3619 | 10 | 2/2 | 12 | 8 | 0.95/0.37/0.23 | 83/55/38 | -2.99 | 1.43 | 0.01 |
| SKYBORNE_H SHAMAN | 9.41 | 23.72 | 0.22 | 0.98 | 3619 | 11 | 2/1 | 12 | 6 | 0.97/0.39/0.23 | 87/57/37 | -3.35 | 0.00 | 0.00 |
| SKYBORNE_H DRUID | 11.34 | 25.66 | 0.22 | 0.98 | 3619 | 12 | 4/0 | 12 | 12 | 0.98/0.39/0.23 | 85/59/37 | -3.08 | 1.76 | 0.01 |

### Alle Kombinationen, explorer

| Kombination | Modellstunden 1–20 | Modellstunden 1–30 | P2 Deckung min | P2 Grind max | P4 längster Weg yd | P5 | P6 nie/später | P7 | P9 | G3 1–10/11–20/21–30 | Quests 1–10/11–20/21–30 | G7 | G8 h | G10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HUMAN WARRIOR | 10.06 | 25.63 | 0.38 | 0.99 | 4257 | 35 | 1/14 | 12 | 9 | 0.88/0.41/0.38 | 76/65/77 | -1.99 | 0.34 | 0.02 |
| HUMAN PALADIN | 10.23 | 25.41 | 0.38 | 0.99 | 2874 | 34 | 4/13 | 12 | 9 | 0.88/0.40/0.37 | 75/65/74 | -1.98 | 0.63 | 0.00 |
| HUMAN HUNTER | 8.43 | 20.90 | 0.38 | 0.98 | 2874 | 36 | 2/18 | 12 | 7 | 0.96/0.40/0.37 | 78/64/74 | -2.29 | 0.00 | 0.02 |
| HUMAN ROGUE | 9.85 | 24.67 | 0.38 | 0.99 | 2874 | 35 | 7/14 | 12 | 14 | 0.89/0.41/0.38 | 76/66/75 | -2.01 | 0.73 | 0.05 |
| HUMAN PRIEST | 9.72 | 25.13 | 0.38 | 0.99 | 2874 | 37 | 5/17 | 12 | 13 | 0.90/0.41/0.37 | 79/67/74 | -2.04 | 0.98 | 0.00 |
| HUMAN MAGE | 10.30 | 24.13 | 0.38 | 0.99 | 2874 | 36 | 9/17 | 12 | 13 | 0.92/0.41/0.37 | 77/65/75 | -2.12 | 2.08 | 0.08 |
| HUMAN WARLOCK | 9.30 | 23.09 | 0.38 | 0.98 | 2874 | 37 | 7/17 | 12 | 21 | 0.91/0.44/0.38 | 78/70/77 | -2.10 | 2.35 | 0.01 |
| DWARF WARRIOR | 10.53 | 26.10 | 0.38 | 0.99 | 4257 | 32 | 2/17 | 13 | 9 | 0.75/0.41/0.38 | 61/66/77 | -1.13 | 0.34 | 0.04 |
| DWARF PALADIN | 10.76 | 25.94 | 0.38 | 0.99 | 2874 | 31 | 5/15 | 13 | 10 | 0.75/0.40/0.37 | 60/67/74 | -1.12 | 0.87 | 0.02 |
| DWARF HUNTER | 8.95 | 21.41 | 0.38 | 0.98 | 2874 | 34 | 2/19 | 13 | 7 | 0.83/0.40/0.37 | 65/65/74 | -1.50 | 0.00 | 0.04 |
| DWARF ROGUE | 10.30 | 25.12 | 0.38 | 0.99 | 2874 | 33 | 8/17 | 13 | 14 | 0.76/0.41/0.38 | 61/67/75 | -1.17 | 0.94 | 0.07 |
| DWARF PRIEST | 10.52 | 26.04 | 0.38 | 0.99 | 2874 | 34 | 7/16 | 14 | 17 | 0.77/0.41/0.37 | 66/68/74 | -1.24 | 1.85 | 0.04 |
| DWARF SHAMAN | 9.74 | 24.02 | 0.38 | 0.99 | 2874 | 32 | 4/15 | 13 | 9 | 0.75/0.40/0.38 | 60/65/75 | -1.12 | 0.33 | 0.04 |
| NIGHTELF WARRIOR | 9.93 | 25.50 | 0.38 | 0.99 | 4257 | 31 | 1/17 | 14 | 9 | 0.97/0.41/0.38 | 75/65/77 | -1.92 | 0.34 | 0.02 |
| NIGHTELF HUNTER | 8.69 | 21.16 | 0.38 | 0.98 | 2874 | 32 | 3/21 | 14 | 7 | 1.05/0.40/0.37 | 79/64/74 | -2.25 | 0.00 | 0.03 |
| NIGHTELF ROGUE | 9.74 | 24.56 | 0.38 | 0.99 | 2874 | 31 | 6/17 | 14 | 14 | 0.98/0.41/0.38 | 75/66/75 | -1.97 | 0.76 | 0.04 |
| NIGHTELF PRIEST | 9.98 | 25.22 | 0.38 | 0.99 | 2874 | 33 | 4/18 | 14 | 15 | 1.00/0.41/0.37 | 81/68/74 | -2.04 | 1.16 | 0.00 |
| NIGHTELF DRUID | 10.95 | 25.98 | 0.38 | 0.99 | 2874 | 34 | 3/20 | 14 | 21 | 1.02/0.44/0.37 | 81/75/74 | -2.12 | 3.45 | 0.02 |
| GNOME WARRIOR | 10.53 | 26.10 | 0.38 | 0.99 | 4257 | 32 | 2/17 | 13 | 9 | 0.75/0.41/0.38 | 61/66/77 | -1.13 | 0.34 | 0.04 |
| GNOME ROGUE | 10.30 | 25.12 | 0.38 | 0.99 | 2874 | 33 | 8/17 | 13 | 14 | 0.76/0.41/0.38 | 61/67/75 | -1.17 | 0.94 | 0.07 |
| GNOME PRIEST | 10.08 | 25.27 | 0.38 | 0.99 | 2874 | 34 | 6/17 | 14 | 12 | 0.76/0.41/0.37 | 64/67/74 | -1.19 | 0.75 | 0.01 |
| GNOME MAGE | 10.74 | 24.58 | 0.38 | 0.99 | 2874 | 34 | 10/17 | 13 | 13 | 0.77/0.41/0.37 | 62/66/75 | -1.24 | 2.55 | 0.10 |
| GNOME WARLOCK | 9.26 | 23.05 | 0.38 | 0.98 | 2874 | 39 | 10/16 | 13 | 21 | 0.77/0.44/0.38 | 62/71/77 | -1.23 | 2.18 | 0.01 |
| SKYBORNE_A WARRIOR | 9.55 | 25.06 | 0.38 | 0.99 | 4257 | 28 | 4/16 | 12 | 9 | 0.95/0.49/0.38 | 83/87/76 | -4.71 | 0.34 | 0.00 |
| SKYBORNE_A HUNTER | 8.32 | 20.73 | 0.38 | 0.98 | 2874 | 28 | 4/16 | 12 | 7 | 1.01/0.48/0.37 | 87/86/73 | -4.87 | 0.00 | 0.01 |
| SKYBORNE_A ROGUE | 9.49 | 24.25 | 0.38 | 0.99 | 2874 | 27 | 8/16 | 12 | 14 | 0.93/0.49/0.38 | 82/88/74 | -4.64 | 0.70 | 0.03 |
| SKYBORNE_A MAGE | 10.09 | 23.40 | 0.38 | 0.99 | 2874 | 27 | 9/17 | 12 | 11 | 0.97/0.49/0.37 | 84/87/73 | -4.74 | 1.56 | 0.05 |
| SKYBORNE_A DRUID | 10.52 | 25.52 | 0.38 | 0.99 | 2874 | 29 | 4/16 | 12 | 19 | 0.96/0.52/0.37 | 85/95/73 | -4.85 | 2.90 | 0.00 |
| ORC WARRIOR | 9.97 | 25.62 | 0.22 | 0.89 | 3619 | 15 | 3/4 | 12 | 6 | 0.75/0.43/0.27 | 51/64/44 | -1.70 | 0.00 | 0.02 |
| ORC HUNTER | 8.85 | 20.90 | 0.22 | 0.86 | 3619 | 15 | 2/4 | 11 | 6 | 0.83/0.42/0.27 | 54/62/44 | -2.03 | 0.00 | 0.02 |
| ORC ROGUE | 9.51 | 23.97 | 0.22 | 0.88 | 3619 | 15 | 4/5 | 11 | 9 | 0.76/0.42/0.27 | 51/64/45 | -1.73 | 1.42 | 0.02 |
| ORC SHAMAN | 9.58 | 23.69 | 0.22 | 0.88 | 3619 | 18 | 3/4 | 12 | 6 | 0.79/0.43/0.27 | 55/63/44 | -1.87 | 0.00 | 0.03 |
| ORC MAGE | 9.20 | 22.27 | 0.22 | 0.87 | 3619 | 15 | 2/4 | 11 | 6 | 0.78/0.42/0.27 | 51/62/44 | -1.80 | 0.00 | 0.00 |
| ORC WARLOCK | 9.05 | 22.85 | 0.22 | 0.86 | 3619 | 15 | 14/6 | 11 | 13 | 0.79/0.42/0.28 | 53/62/50 | -1.90 | 2.43 | 0.00 |
| UNDEAD WARRIOR | 10.18 | 25.83 | 0.22 | 0.89 | 3619 | 23 | 3/3 | 18 | 6 | 1.02/0.43/0.27 | 75/64/44 | -3.19 | 0.00 | 0.03 |
| UNDEAD PALADIN | 11.33 | 26.51 | 0.22 | 0.89 | 3619 | 25 | 7/4 | 19 | 9 | 1.07/0.43/0.27 | 78/63/45 | -3.67 | 1.23 | 0.04 |
| UNDEAD ROGUE | 9.83 | 24.29 | 0.22 | 0.88 | 3619 | 20 | 5/3 | 18 | 9 | 0.95/0.42/0.27 | 70/64/45 | -2.94 | 1.42 | 0.03 |
| UNDEAD PRIEST | 10.26 | 25.21 | 0.22 | 0.88 | 3619 | 24 | 7/2 | 19 | 13 | 0.97/0.42/0.27 | 74/62/47 | -2.99 | 1.91 | 0.00 |
| UNDEAD MAGE | 10.91 | 24.41 | 0.22 | 0.87 | 3619 | 21 | 11/2 | 18 | 13 | 0.97/0.43/0.28 | 70/64/46 | -3.01 | 2.91 | 0.10 |
| UNDEAD WARLOCK | 10.64 | 24.45 | 0.22 | 0.86 | 3619 | 22 | 12/4 | 18 | 16 | 1.03/0.42/0.28 | 74/62/50 | -3.21 | 3.70 | 0.07 |
| TAUREN WARRIOR | 11.45 | 27.10 | 0.22 | 0.89 | 3619 | 21 | 6/19 | 13 | 7 | 0.74/0.43/0.27 | 61/65/44 | -1.32 | 0.10 | 0.08 |
| TAUREN HUNTER | 10.18 | 22.22 | 0.22 | 0.86 | 3619 | 21 | 2/20 | 12 | 6 | 0.80/0.43/0.27 | 63/63/44 | -1.57 | 0.00 | 0.08 |
| TAUREN SHAMAN | 10.85 | 24.96 | 0.22 | 0.88 | 3619 | 23 | 6/20 | 13 | 7 | 0.75/0.43/0.27 | 62/64/44 | -1.35 | 0.10 | 0.08 |
| TAUREN DRUID | 13.36 | 28.51 | 0.22 | 0.88 | 3619 | 23 | 10/20 | 12 | 18 | 0.79/0.45/0.28 | 67/68/49 | -1.55 | 4.97 | 0.12 |
| TROLL WARRIOR | 9.97 | 25.62 | 0.22 | 0.89 | 3619 | 15 | 3/4 | 12 | 6 | 0.75/0.43/0.27 | 51/64/44 | -1.70 | 0.00 | 0.02 |
| TROLL HUNTER | 8.85 | 20.90 | 0.22 | 0.86 | 3619 | 15 | 2/4 | 11 | 6 | 0.83/0.42/0.27 | 54/62/44 | -2.03 | 0.00 | 0.02 |
| TROLL ROGUE | 9.46 | 23.92 | 0.22 | 0.88 | 3619 | 15 | 4/5 | 11 | 9 | 0.75/0.42/0.27 | 50/64/45 | -1.70 | 1.42 | 0.02 |
| TROLL PRIEST | 10.24 | 25.38 | 0.22 | 0.88 | 3619 | 16 | 5/6 | 12 | 15 | 0.78/0.42/0.27 | 56/62/47 | -1.81 | 2.23 | 0.01 |
| TROLL SHAMAN | 9.58 | 23.69 | 0.22 | 0.88 | 3619 | 18 | 3/4 | 12 | 6 | 0.79/0.43/0.27 | 55/63/44 | -1.87 | 0.00 | 0.03 |
| TROLL MAGE | 10.68 | 24.18 | 0.22 | 0.87 | 3619 | 15 | 7/4 | 11 | 13 | 0.80/0.43/0.28 | 52/64/46 | -1.91 | 2.91 | 0.09 |
| TROLL WARLOCK | 9.05 | 22.85 | 0.22 | 0.86 | 3619 | 15 | 14/6 | 11 | 13 | 0.79/0.42/0.28 | 53/62/50 | -1.90 | 2.43 | 0.00 |
| SKYBORNE_H WARRIOR | 9.43 | 25.11 | 0.22 | 0.88 | 3619 | 22 | 7/15 | 12 | 6 | 1.16/0.46/0.27 | 96/70/44 | -4.61 | 0.00 | 0.00 |
| SKYBORNE_H HUNTER | 8.33 | 20.49 | 0.21 | 0.86 | 3619 | 23 | 7/18 | 12 | 6 | 1.22/0.45/0.27 | 98/69/44 | -4.78 | 0.00 | 0.00 |
| SKYBORNE_H ROGUE | 9.13 | 23.56 | 0.22 | 0.87 | 3619 | 21 | 6/16 | 12 | 9 | 1.14/0.45/0.27 | 94/70/45 | -4.55 | 1.42 | 0.00 |
| SKYBORNE_H SHAMAN | 8.82 | 23.10 | 0.21 | 0.87 | 3619 | 22 | 7/18 | 12 | 6 | 1.16/0.47/0.27 | 97/72/44 | -4.86 | 0.00 | 0.00 |
| SKYBORNE_H DRUID | 10.86 | 26.21 | 0.21 | 0.87 | 3619 | 24 | 13/18 | 12 | 15 | 1.17/0.47/0.27 | 97/73/46 | -4.70 | 3.86 | 0.03 |
