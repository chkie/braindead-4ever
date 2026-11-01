# Route metrics

How fast and how sensible Pathmark's routes are, measured the same way for all 56 race and class combinations in both modes. The tool is `python3 -m tools.routekit metrics` (`tools/routekit/metrics.py` on top of the simulator `tools/routekit/sim.py`); CI runs it in the job "Route quality" and writes the report into the job summary. This file holds the baseline measurement of the routes before the route optimizer (Welle 6b); Welle 6b adds the measurement after it.

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
| P4 | legs longer than 0.05 Modellstunden (3 minutes) for one quest whose XP rate is below half the route's; longest walk in one zone | 0; not worse than the start | DR 22c §F |
| P5 | avoidable returns (a visit ends 400 yd away; work on a later visit that was possible on the last one) and wasted trips (all of it was possible, no trainer or flight master) | not more than the start; 0 wasted | Polestar judge, DR 22c §5 |
| P6 | quests whose giver stood within 500 yd of the walked line while the character could take them: never taken, or taken only after going 1,000 yd away | 0 | Polestar judge |
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
| G11 | share of route quests whose race and class condition comes from our own measurement | 1.0 before label `stabil` | DR 22d |
| G12 | G1–G10 for the two Skyborne races separately | as G1–G10 | DR 22d |
| R01–R35 | the rules of the DR 22a catalogue that the route data can show; the others are listed with the reason | 0 for hard rules (H), report for soft ones (W) | DR 22a |

Level bands follow the planned level (`lv`) of a step. A band's XP is the XP to level through it: levels 1–10, 11–20 and 21–29 (the route ends on reaching 30).

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

The sections below are the tool's Markdown output as it was on 2026-11-01, with German labels like the linter's messages.

## Baseline 2026-11-01: routes of origin/main a590510 (Welle 5, route data unchanged in 21b396c, Welle 5b), before the optimizer

Modellstunden aus `tools/routekit/sim.py` mit den Parametern aus `data/plan/params.toml`, keine Vorhersage echter Spielzeit. Status: erfüllt oder verletzt (Zahl der Kombinationen) gegen den Grenzwert aus `data/plan/params.toml`; Bericht ohne Grenzwert; offen, wenn nicht prüfbar. Bänder 1–10, 11–20, 21–30 nach der geplanten Stufe des Schritts. In Welle 6a bricht keine Kennzahl den Build ab.

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
| P4 | speed | P4 lange Einzelquest-Wege (über 0,05 Modellstunden, unter ½ Routenrate) | ≤ 0 | verletzt (56) | GNOME MAGE 19; DWARF PRIEST 18; HUMAN MAGE 18; DWARF HUNTER 17; DWARF ROGUE 16 |
| P4 | explorer | P4 lange Einzelquest-Wege (über 0,05 Modellstunden, unter ½ Routenrate) | ≤ 0 | verletzt (56) | GNOME MAGE 23; GNOME WARLOCK 22; HUMAN WARLOCK 21; HUMAN MAGE 20; DWARF PRIEST 19 |
| P4b | speed | P4 lange Einzelquest-Wege mehr als Startlösung | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P4b | explorer | P4 lange Einzelquest-Wege mehr als Startlösung | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P4yd | speed | P4 längster Fußweg im selben Gebiet (yd) | – | Bericht | DWARF WARRIOR 4257; GNOME WARRIOR 4257; HUMAN WARRIOR 4257; NIGHTELF WARRIOR 4257; SKYBORNE_A WARRIOR 4257 |
| P4yd | explorer | P4 längster Fußweg im selben Gebiet (yd) | – | Bericht | DWARF WARRIOR 4257; GNOME WARRIOR 4257; HUMAN WARRIOR 4257; NIGHTELF WARRIOR 4257; SKYBORNE_A WARRIOR 4257 |
| P5 | speed | P5 vermeidbare Rückkehren | – | Bericht | HUMAN HUNTER 27; HUMAN MAGE 26; HUMAN PRIEST 26; HUMAN WARLOCK 26; HUMAN WARRIOR 26 |
| P5 | explorer | P5 vermeidbare Rückkehren | – | Bericht | GNOME WARLOCK 39; HUMAN PRIEST 37; HUMAN WARLOCK 37; HUMAN HUNTER 36; HUMAN MAGE 36 |
| P5b | speed | P5 vermeidbare Rückkehren mehr als Startlösung | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P5b | explorer | P5 vermeidbare Rückkehren mehr als Startlösung | ≤ Startlösung | erfüllt | DWARF HUNTER 0; DWARF PALADIN 0; DWARF PRIEST 0; DWARF ROGUE 0; DWARF SHAMAN 0 |
| P5w | speed | P5 verschwendete Wege | ≤ 0 | verletzt (56) | HUMAN PRIEST 14; HUMAN WARRIOR 14; HUMAN HUNTER 13; HUMAN MAGE 13; HUMAN PALADIN 13 |
| P5w | explorer | P5 verschwendete Wege | ≤ 0 | verletzt (56) | HUMAN PRIEST 15; HUMAN MAGE 14; HUMAN WARLOCK 14; HUMAN WARRIOR 14; GNOME WARLOCK 13 |
| P6 | speed | P6 vorbeigelaufen, nie genommen | ≤ 0 | verletzt (56) | NIGHTELF PRIEST 70; DWARF ROGUE 53; DWARF SHAMAN 53; DWARF WARRIOR 53; GNOME ROGUE 53 |
| P6 | explorer | P6 vorbeigelaufen, nie genommen | ≤ 0 | verletzt (56) | NIGHTELF PRIEST 94; DWARF PRIEST 67; GNOME WARLOCK 67; GNOME PRIEST 66; GNOME MAGE 65 |
| P6l | speed | P6 vorbeigelaufen, erst später genommen | ≤ 0 | verletzt (55) | TAUREN DRUID 22; TAUREN SHAMAN 20; HUMAN WARLOCK 19; TAUREN HUNTER 19; TAUREN WARRIOR 19 |
| P6l | explorer | P6 vorbeigelaufen, erst später genommen | ≤ 0 | verletzt (56) | NIGHTELF DRUID 26; TAUREN DRUID 25; GNOME WARLOCK 24; HUMAN WARLOCK 24; SKYBORNE_A DRUID 23 |
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
| G11 | speed | G11 Anteil Routenquests mit eigener Volk-/Klassen-Messung | ≥ 1.00 | verletzt (56) | DWARF HUNTER 0.00; DWARF PALADIN 0.00; DWARF PRIEST 0.00; DWARF ROGUE 0.00; DWARF SHAMAN 0.00 |
| G11 | explorer | G11 Anteil Routenquests mit eigener Volk-/Klassen-Messung | ≥ 1.00 | verletzt (56) | DWARF HUNTER 0.00; DWARF PALADIN 0.00; DWARF PRIEST 0.00; DWARF ROGUE 0.00; DWARF SHAMAN 0.00 |
| R01 | speed | R01 Abgabe über Questlevel + 5 (H) | ≤ 0 | verletzt (36) | DWARF HUNTER 4; DWARF PALADIN 4; DWARF PRIEST 4; DWARF ROGUE 4; DWARF SHAMAN 4 |
| R01 | explorer | R01 Abgabe über Questlevel + 5 (H) | ≤ 0 | verletzt (56) | SKYBORNE_A DRUID 9; SKYBORNE_A HUNTER 9; SKYBORNE_A MAGE 9; SKYBORNE_A ROGUE 9; SKYBORNE_A WARRIOR 9 |
| R02 | speed | R02 Abgabe ab Questlevel + 10 (H) | ≤ 0 | verletzt (28) | DWARF HUNTER 1; DWARF PALADIN 1; DWARF PRIEST 1; DWARF ROGUE 1; DWARF SHAMAN 1 |
| R02 | explorer | R02 Abgabe ab Questlevel + 10 (H) | ≤ 0 | verletzt (29) | DWARF HUNTER 1; DWARF PALADIN 1; DWARF PRIEST 1; DWARF ROGUE 1; DWARF SHAMAN 1 |
| R04 | speed | R04 Folgequest am selben NPC nicht im selben Schritt (H) | ≤ 0 | verletzt (56) | SKYBORNE_A DRUID 25; SKYBORNE_A HUNTER 25; SKYBORNE_A MAGE 25; SKYBORNE_A ROGUE 25; SKYBORNE_A WARRIOR 25 |
| R04 | explorer | R04 Folgequest am selben NPC nicht im selben Schritt (H) | ≤ 0 | verletzt (56) | SKYBORNE_A DRUID 31; SKYBORNE_A HUNTER 31; SKYBORNE_A MAGE 31; SKYBORNE_A ROGUE 31; SKYBORNE_A WARRIOR 31 |
| R05 | speed | R05 späterer Besuch nur zur Annahme (H) | ≤ 0 | verletzt (56) | UNDEAD PRIEST 27; SKYBORNE_H WARRIOR 26; UNDEAD PALADIN 26; UNDEAD WARLOCK 26; SKYBORNE_H DRUID 25 |
| R05 | explorer | R05 späterer Besuch nur zur Annahme (H) | ≤ 0 | verletzt (56) | UNDEAD PALADIN 33; SKYBORNE_H DRUID 32; SKYBORNE_H HUNTER 31; SKYBORNE_H SHAMAN 31; SKYBORNE_H WARRIOR 31 |
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
| R18 | speed | R18 Grind trotz annehmbarer Quest in 500 yd (H) | ≤ 0 | verletzt (56) | ORC WARLOCK 15; TROLL WARLOCK 15; ORC HUNTER 14; ORC MAGE 14; ORC ROGUE 14 |
| R18 | explorer | R18 Grind trotz annehmbarer Quest in 500 yd (H) | ≤ 0 | verletzt (56) | ORC HUNTER 12; ORC MAGE 12; ORC ROGUE 12; ORC SHAMAN 12; ORC WARLOCK 12 |
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
| HUMAN WARRIOR | 10.61 | 26.63 | 0.27 | 0.99 | 4257 | 26 | 27/17 | 12 | 8 | 0.84/0.33/0.31 | 71/52/64 | -1.91 | 0.29 | 0.03 |
| HUMAN PALADIN | 10.74 | 26.35 | 0.27 | 0.99 | 2874 | 25 | 34/16 | 12 | 9 | 0.83/0.32/0.30 | 70/52/62 | -1.90 | 0.63 | 0.01 |
| HUMAN HUNTER | 8.74 | 21.49 | 0.27 | 0.98 | 2874 | 27 | 26/17 | 12 | 7 | 0.92/0.32/0.30 | 73/51/62 | -2.23 | 0.00 | 0.03 |
| HUMAN ROGUE | 9.80 | 24.45 | 0.27 | 0.99 | 2874 | 25 | 27/16 | 12 | 7 | 0.83/0.32/0.30 | 70/51/62 | -1.90 | 0.00 | 0.02 |
| HUMAN PRIEST | 10.14 | 25.95 | 0.27 | 0.99 | 2874 | 26 | 33/18 | 12 | 13 | 0.85/0.33/0.30 | 73/54/62 | -1.94 | 1.21 | 0.01 |
| HUMAN MAGE | 10.69 | 24.39 | 0.27 | 0.99 | 2874 | 26 | 30/17 | 12 | 11 | 0.86/0.33/0.30 | 71/52/62 | -2.00 | 2.16 | 0.07 |
| HUMAN WARLOCK | 9.09 | 22.53 | 0.27 | 0.98 | 2874 | 26 | 27/19 | 12 | 15 | 0.84/0.36/0.31 | 71/55/64 | -1.93 | 1.25 | 0.00 |
| DWARF WARRIOR | 10.85 | 26.87 | 0.27 | 0.99 | 4257 | 17 | 53/10 | 11 | 8 | 0.71/0.33/0.31 | 56/53/64 | -1.06 | 0.29 | 0.04 |
| DWARF PALADIN | 10.59 | 26.19 | 0.27 | 0.99 | 2874 | 17 | 51/10 | 11 | 7 | 0.70/0.32/0.30 | 55/52/62 | -1.05 | 0.00 | 0.00 |
| DWARF HUNTER | 9.05 | 21.80 | 0.27 | 0.98 | 2874 | 20 | 52/12 | 11 | 7 | 0.79/0.32/0.30 | 59/52/62 | -1.42 | 0.00 | 0.05 |
| DWARF ROGUE | 10.11 | 24.76 | 0.27 | 0.99 | 2874 | 17 | 53/10 | 11 | 7 | 0.72/0.32/0.30 | 56/52/62 | -1.10 | 0.00 | 0.03 |
| DWARF PRIEST | 10.92 | 26.83 | 0.27 | 0.99 | 2874 | 18 | 46/10 | 11 | 17 | 0.73/0.33/0.30 | 60/55/62 | -1.16 | 2.15 | 0.05 |
| DWARF SHAMAN | 10.09 | 24.74 | 0.27 | 0.99 | 2874 | 17 | 53/10 | 11 | 7 | 0.70/0.32/0.30 | 55/52/62 | -1.05 | 0.00 | 0.04 |
| NIGHTELF WARRIOR | 10.40 | 26.42 | 0.27 | 0.99 | 4257 | 22 | 38/7 | 14 | 8 | 0.92/0.33/0.31 | 68/52/64 | -1.81 | 0.29 | 0.02 |
| NIGHTELF HUNTER | 8.88 | 21.62 | 0.27 | 0.98 | 2874 | 22 | 38/7 | 14 | 7 | 1.00/0.32/0.30 | 72/51/62 | -2.15 | 0.00 | 0.04 |
| NIGHTELF ROGUE | 9.69 | 24.34 | 0.27 | 0.99 | 2874 | 22 | 38/7 | 14 | 7 | 0.93/0.32/0.30 | 69/51/62 | -1.87 | 0.00 | 0.01 |
| NIGHTELF PRIEST | 10.38 | 26.02 | 0.27 | 0.99 | 2874 | 23 | 70/7 | 14 | 15 | 0.95/0.33/0.30 | 74/55/62 | -1.94 | 1.37 | 0.02 |
| NIGHTELF DRUID | 11.23 | 25.88 | 0.27 | 0.99 | 2874 | 24 | 49/9 | 14 | 16 | 0.96/0.35/0.30 | 72/57/62 | -2.01 | 2.95 | 0.02 |
| GNOME WARRIOR | 10.85 | 26.87 | 0.27 | 0.99 | 4257 | 17 | 53/10 | 11 | 8 | 0.71/0.33/0.31 | 56/53/64 | -1.06 | 0.29 | 0.04 |
| GNOME ROGUE | 10.11 | 24.76 | 0.27 | 0.99 | 2874 | 17 | 53/10 | 11 | 7 | 0.72/0.32/0.30 | 56/52/62 | -1.10 | 0.00 | 0.03 |
| GNOME PRIEST | 10.47 | 25.60 | 0.27 | 0.99 | 2874 | 18 | 52/9 | 11 | 8 | 0.72/0.32/0.30 | 58/52/62 | -1.11 | 0.10 | 0.00 |
| GNOME MAGE | 10.90 | 24.60 | 0.27 | 0.99 | 2874 | 17 | 42/9 | 11 | 11 | 0.73/0.33/0.30 | 56/53/62 | -1.16 | 2.29 | 0.08 |
| GNOME WARLOCK | 9.38 | 22.81 | 0.27 | 0.98 | 2874 | 21 | 51/13 | 11 | 15 | 0.71/0.36/0.31 | 56/56/64 | -1.11 | 1.25 | 0.01 |
| SKYBORNE_A WARRIOR | 10.12 | 26.09 | 0.27 | 0.99 | 4257 | 18 | 31/4 | 12 | 8 | 0.77/0.34/0.31 | 70/53/63 | -1.97 | 0.29 | 0.01 |
| SKYBORNE_A HUNTER | 8.43 | 21.12 | 0.27 | 0.98 | 2874 | 19 | 30/4 | 12 | 7 | 0.84/0.33/0.30 | 74/52/61 | -2.22 | 0.00 | 0.01 |
| SKYBORNE_A ROGUE | 9.44 | 24.04 | 0.27 | 0.99 | 2874 | 17 | 30/4 | 12 | 7 | 0.75/0.33/0.30 | 69/52/61 | -1.86 | 0.00 | 0.00 |
| SKYBORNE_A MAGE | 10.32 | 23.97 | 0.27 | 0.99 | 2874 | 17 | 33/5 | 12 | 11 | 0.78/0.33/0.30 | 71/53/61 | -2.01 | 2.10 | 0.05 |
| SKYBORNE_A DRUID | 10.83 | 25.43 | 0.27 | 0.99 | 2874 | 18 | 40/5 | 12 | 16 | 0.78/0.36/0.30 | 72/58/61 | -2.07 | 2.78 | 0.00 |
| ORC WARRIOR | 10.45 | 26.38 | 0.22 | 0.99 | 3619 | 14 | 25/5 | 12 | 6 | 0.69/0.37/0.23 | 46/55/37 | -1.31 | 0.00 | 0.02 |
| ORC HUNTER | 9.09 | 21.25 | 0.22 | 0.98 | 3619 | 14 | 25/5 | 11 | 6 | 0.76/0.36/0.23 | 48/53/37 | -1.63 | 0.00 | 0.02 |
| ORC ROGUE | 9.89 | 24.63 | 0.22 | 0.98 | 3619 | 14 | 28/7 | 11 | 8 | 0.69/0.36/0.23 | 45/54/38 | -1.31 | 1.43 | 0.02 |
| ORC SHAMAN | 9.80 | 24.12 | 0.22 | 0.98 | 3619 | 15 | 25/4 | 12 | 6 | 0.72/0.37/0.23 | 49/53/37 | -1.44 | 0.00 | 0.02 |
| ORC MAGE | 9.51 | 22.75 | 0.22 | 0.98 | 3619 | 14 | 24/4 | 11 | 6 | 0.71/0.36/0.23 | 46/53/37 | -1.41 | 0.00 | 0.00 |
| ORC WARLOCK | 9.30 | 23.30 | 0.22 | 0.98 | 3619 | 14 | 30/5 | 11 | 13 | 0.73/0.36/0.25 | 48/53/41 | -1.51 | 2.63 | 0.03 |
| UNDEAD WARRIOR | 10.91 | 26.83 | 0.22 | 0.99 | 3619 | 16 | 19/9 | 12 | 6 | 0.83/0.37/0.23 | 62/55/37 | -2.01 | 0.00 | 0.04 |
| UNDEAD PALADIN | 10.80 | 26.19 | 0.22 | 0.99 | 3619 | 15 | 19/9 | 12 | 6 | 0.77/0.36/0.23 | 60/53/37 | -1.73 | 0.00 | 0.00 |
| UNDEAD ROGUE | 10.45 | 25.20 | 0.22 | 0.98 | 3619 | 14 | 23/11 | 12 | 8 | 0.76/0.36/0.23 | 58/54/38 | -1.70 | 1.43 | 0.05 |
| UNDEAD PRIEST | 11.00 | 26.17 | 0.22 | 0.99 | 3619 | 18 | 30/10 | 12 | 13 | 0.78/0.36/0.24 | 63/53/40 | -1.78 | 1.91 | 0.02 |
| UNDEAD MAGE | 11.20 | 24.76 | 0.22 | 0.98 | 3619 | 15 | 21/9 | 12 | 11 | 0.78/0.37/0.24 | 59/54/38 | -1.80 | 2.67 | 0.09 |
| UNDEAD WARLOCK | 11.11 | 25.11 | 0.22 | 0.98 | 3619 | 15 | 30/11 | 12 | 16 | 0.84/0.36/0.25 | 63/53/41 | -2.06 | 3.92 | 0.11 |
| TAUREN WARRIOR | 11.75 | 27.67 | 0.22 | 0.99 | 3619 | 18 | 27/19 | 13 | 7 | 0.73/0.37/0.23 | 60/55/37 | -1.27 | 0.10 | 0.07 |
| TAUREN HUNTER | 10.31 | 22.47 | 0.22 | 0.98 | 3619 | 18 | 26/19 | 12 | 6 | 0.79/0.36/0.23 | 62/53/37 | -1.51 | 0.00 | 0.08 |
| TAUREN SHAMAN | 11.10 | 25.41 | 0.22 | 0.98 | 3619 | 19 | 29/20 | 13 | 7 | 0.73/0.37/0.23 | 61/53/37 | -1.30 | 0.10 | 0.07 |
| TAUREN DRUID | 13.10 | 27.41 | 0.22 | 0.98 | 3619 | 20 | 28/22 | 12 | 13 | 0.77/0.38/0.23 | 63/58/37 | -1.46 | 2.41 | 0.08 |
| TROLL WARRIOR | 10.45 | 26.38 | 0.22 | 0.99 | 3619 | 14 | 25/5 | 12 | 6 | 0.69/0.37/0.23 | 46/55/37 | -1.31 | 0.00 | 0.02 |
| TROLL HUNTER | 9.09 | 21.25 | 0.22 | 0.98 | 3619 | 14 | 25/5 | 11 | 6 | 0.76/0.36/0.23 | 48/53/37 | -1.63 | 0.00 | 0.02 |
| TROLL ROGUE | 9.89 | 24.63 | 0.22 | 0.98 | 3619 | 14 | 28/7 | 11 | 8 | 0.69/0.36/0.23 | 45/54/38 | -1.31 | 1.43 | 0.02 |
| TROLL PRIEST | 10.69 | 26.15 | 0.22 | 0.99 | 3619 | 15 | 33/7 | 12 | 15 | 0.72/0.36/0.24 | 51/53/40 | -1.42 | 2.24 | 0.02 |
| TROLL SHAMAN | 9.80 | 24.12 | 0.22 | 0.98 | 3619 | 15 | 25/4 | 12 | 6 | 0.72/0.37/0.23 | 49/53/37 | -1.44 | 0.00 | 0.02 |
| TROLL MAGE | 10.76 | 24.32 | 0.22 | 0.98 | 3619 | 14 | 31/4 | 11 | 11 | 0.74/0.37/0.24 | 47/54/38 | -1.52 | 2.69 | 0.07 |
| TROLL WARLOCK | 9.30 | 23.30 | 0.22 | 0.98 | 3619 | 14 | 30/5 | 11 | 13 | 0.73/0.36/0.25 | 48/53/41 | -1.51 | 2.63 | 0.03 |
| SKYBORNE_H WARRIOR | 9.97 | 25.89 | 0.22 | 0.99 | 3619 | 11 | 15/0 | 12 | 6 | 0.97/0.38/0.23 | 85/56/37 | -3.07 | 0.00 | 0.00 |
| SKYBORNE_H HUNTER | 8.68 | 20.84 | 0.22 | 0.98 | 3619 | 12 | 15/1 | 12 | 6 | 1.04/0.37/0.23 | 88/54/37 | -3.29 | 0.00 | 0.00 |
| SKYBORNE_H ROGUE | 9.53 | 24.27 | 0.22 | 0.98 | 3619 | 10 | 18/3 | 12 | 8 | 0.95/0.37/0.23 | 83/55/38 | -2.99 | 1.43 | 0.01 |
| SKYBORNE_H SHAMAN | 9.41 | 23.72 | 0.22 | 0.98 | 3619 | 11 | 16/1 | 12 | 6 | 0.97/0.39/0.23 | 87/57/37 | -3.35 | 0.00 | 0.00 |
| SKYBORNE_H DRUID | 11.34 | 25.66 | 0.22 | 0.98 | 3619 | 12 | 23/1 | 12 | 12 | 0.98/0.39/0.23 | 85/59/37 | -3.08 | 1.76 | 0.01 |

### Alle Kombinationen, explorer

| Kombination | Modellstunden 1–20 | Modellstunden 1–30 | P2 Deckung min | P2 Grind max | P4 längster Weg yd | P5 | P6 nie/später | P7 | P9 | G3 1–10/11–20/21–30 | Quests 1–10/11–20/21–30 | G7 | G8 h | G10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HUMAN WARRIOR | 10.06 | 25.63 | 0.38 | 0.99 | 4257 | 35 | 36/17 | 12 | 9 | 0.88/0.41/0.38 | 76/65/77 | -1.99 | 0.34 | 0.02 |
| HUMAN PALADIN | 10.23 | 25.41 | 0.38 | 0.99 | 2874 | 34 | 47/16 | 12 | 9 | 0.88/0.40/0.37 | 75/65/74 | -1.98 | 0.63 | 0.00 |
| HUMAN HUNTER | 8.43 | 20.90 | 0.38 | 0.98 | 2874 | 36 | 37/21 | 12 | 7 | 0.96/0.40/0.37 | 78/64/74 | -2.29 | 0.00 | 0.02 |
| HUMAN ROGUE | 9.85 | 24.67 | 0.38 | 0.99 | 2874 | 35 | 47/17 | 12 | 14 | 0.89/0.41/0.38 | 76/66/75 | -2.01 | 0.73 | 0.05 |
| HUMAN PRIEST | 9.72 | 25.13 | 0.38 | 0.99 | 2874 | 37 | 51/20 | 12 | 13 | 0.90/0.41/0.37 | 79/67/74 | -2.04 | 0.98 | 0.00 |
| HUMAN MAGE | 10.30 | 24.13 | 0.38 | 0.99 | 2874 | 36 | 50/21 | 12 | 13 | 0.92/0.41/0.37 | 77/65/75 | -2.12 | 2.08 | 0.08 |
| HUMAN WARLOCK | 9.30 | 23.09 | 0.38 | 0.98 | 2874 | 37 | 63/24 | 12 | 21 | 0.91/0.44/0.38 | 78/70/77 | -2.10 | 2.35 | 0.01 |
| DWARF WARRIOR | 10.53 | 26.10 | 0.38 | 0.99 | 4257 | 32 | 54/20 | 13 | 9 | 0.75/0.41/0.38 | 61/66/77 | -1.13 | 0.34 | 0.04 |
| DWARF PALADIN | 10.76 | 25.94 | 0.38 | 0.99 | 2874 | 31 | 57/19 | 13 | 10 | 0.75/0.40/0.37 | 60/67/74 | -1.12 | 0.87 | 0.02 |
| DWARF HUNTER | 8.95 | 21.41 | 0.38 | 0.98 | 2874 | 34 | 55/22 | 13 | 7 | 0.83/0.40/0.37 | 65/65/74 | -1.50 | 0.00 | 0.04 |
| DWARF ROGUE | 10.30 | 25.12 | 0.38 | 0.99 | 2874 | 33 | 64/20 | 13 | 14 | 0.76/0.41/0.38 | 61/67/75 | -1.17 | 0.94 | 0.07 |
| DWARF PRIEST | 10.52 | 26.04 | 0.38 | 0.99 | 2874 | 34 | 67/20 | 14 | 17 | 0.77/0.41/0.37 | 66/68/74 | -1.24 | 1.85 | 0.04 |
| DWARF SHAMAN | 9.74 | 24.02 | 0.38 | 0.99 | 2874 | 32 | 53/19 | 13 | 9 | 0.75/0.40/0.38 | 60/65/75 | -1.12 | 0.33 | 0.04 |
| NIGHTELF WARRIOR | 9.93 | 25.50 | 0.38 | 0.99 | 4257 | 31 | 53/17 | 14 | 9 | 0.97/0.41/0.38 | 75/65/77 | -1.92 | 0.34 | 0.02 |
| NIGHTELF HUNTER | 8.69 | 21.16 | 0.38 | 0.98 | 2874 | 32 | 51/21 | 14 | 7 | 1.05/0.40/0.37 | 79/64/74 | -2.25 | 0.00 | 0.03 |
| NIGHTELF ROGUE | 9.74 | 24.56 | 0.38 | 0.99 | 2874 | 31 | 65/17 | 14 | 14 | 0.98/0.41/0.38 | 75/66/75 | -1.97 | 0.76 | 0.04 |
| NIGHTELF PRIEST | 9.98 | 25.22 | 0.38 | 0.99 | 2874 | 33 | 94/18 | 14 | 15 | 1.00/0.41/0.37 | 81/68/74 | -2.04 | 1.16 | 0.00 |
| NIGHTELF DRUID | 10.95 | 25.98 | 0.38 | 0.99 | 2874 | 34 | 62/26 | 14 | 21 | 1.02/0.44/0.37 | 81/75/74 | -2.12 | 3.45 | 0.02 |
| GNOME WARRIOR | 10.53 | 26.10 | 0.38 | 0.99 | 4257 | 32 | 54/20 | 13 | 9 | 0.75/0.41/0.38 | 61/66/77 | -1.13 | 0.34 | 0.04 |
| GNOME ROGUE | 10.30 | 25.12 | 0.38 | 0.99 | 2874 | 33 | 64/20 | 13 | 14 | 0.76/0.41/0.38 | 61/67/75 | -1.17 | 0.94 | 0.07 |
| GNOME PRIEST | 10.08 | 25.27 | 0.38 | 0.99 | 2874 | 34 | 66/20 | 14 | 12 | 0.76/0.41/0.37 | 64/67/74 | -1.19 | 0.75 | 0.01 |
| GNOME MAGE | 10.74 | 24.58 | 0.38 | 0.99 | 2874 | 34 | 65/20 | 13 | 13 | 0.77/0.41/0.37 | 62/66/75 | -1.24 | 2.55 | 0.10 |
| GNOME WARLOCK | 9.26 | 23.05 | 0.38 | 0.98 | 2874 | 39 | 67/24 | 13 | 21 | 0.77/0.44/0.38 | 62/71/77 | -1.23 | 2.18 | 0.01 |
| SKYBORNE_A WARRIOR | 9.55 | 25.06 | 0.38 | 0.99 | 4257 | 28 | 39/16 | 12 | 9 | 0.95/0.49/0.38 | 83/87/76 | -4.71 | 0.34 | 0.00 |
| SKYBORNE_A HUNTER | 8.32 | 20.73 | 0.38 | 0.98 | 2874 | 28 | 38/16 | 12 | 7 | 1.01/0.48/0.37 | 87/86/73 | -4.87 | 0.00 | 0.01 |
| SKYBORNE_A ROGUE | 9.49 | 24.25 | 0.38 | 0.99 | 2874 | 27 | 50/16 | 12 | 14 | 0.93/0.49/0.38 | 82/88/74 | -4.64 | 0.70 | 0.03 |
| SKYBORNE_A MAGE | 10.09 | 23.40 | 0.38 | 0.99 | 2874 | 27 | 48/17 | 12 | 11 | 0.97/0.49/0.37 | 84/87/73 | -4.74 | 1.56 | 0.05 |
| SKYBORNE_A DRUID | 10.52 | 25.52 | 0.38 | 0.99 | 2874 | 29 | 53/23 | 12 | 19 | 0.96/0.52/0.37 | 85/95/73 | -4.85 | 2.90 | 0.00 |
| ORC WARRIOR | 9.97 | 25.62 | 0.22 | 0.89 | 3619 | 15 | 33/4 | 12 | 6 | 0.75/0.43/0.27 | 51/64/44 | -1.70 | 0.00 | 0.02 |
| ORC HUNTER | 8.85 | 20.90 | 0.22 | 0.86 | 3619 | 15 | 33/5 | 11 | 6 | 0.83/0.42/0.27 | 54/62/44 | -2.03 | 0.00 | 0.02 |
| ORC ROGUE | 9.51 | 23.97 | 0.22 | 0.88 | 3619 | 15 | 37/6 | 11 | 9 | 0.76/0.42/0.27 | 51/64/45 | -1.73 | 1.42 | 0.02 |
| ORC SHAMAN | 9.58 | 23.69 | 0.22 | 0.88 | 3619 | 18 | 35/4 | 12 | 6 | 0.79/0.43/0.27 | 55/63/44 | -1.87 | 0.00 | 0.03 |
| ORC MAGE | 9.20 | 22.27 | 0.22 | 0.87 | 3619 | 15 | 32/5 | 11 | 6 | 0.78/0.42/0.27 | 51/62/44 | -1.80 | 0.00 | 0.00 |
| ORC WARLOCK | 9.05 | 22.85 | 0.22 | 0.86 | 3619 | 15 | 41/7 | 11 | 13 | 0.79/0.42/0.28 | 53/62/50 | -1.90 | 2.43 | 0.00 |
| UNDEAD WARRIOR | 10.18 | 25.83 | 0.22 | 0.89 | 3619 | 23 | 27/3 | 18 | 6 | 1.02/0.43/0.27 | 75/64/44 | -3.19 | 0.00 | 0.03 |
| UNDEAD PALADIN | 11.33 | 26.51 | 0.22 | 0.89 | 3619 | 25 | 32/5 | 19 | 9 | 1.07/0.43/0.27 | 78/63/45 | -3.67 | 1.23 | 0.04 |
| UNDEAD ROGUE | 9.83 | 24.29 | 0.22 | 0.88 | 3619 | 20 | 32/4 | 18 | 9 | 0.95/0.42/0.27 | 70/64/45 | -2.94 | 1.42 | 0.03 |
| UNDEAD PRIEST | 10.26 | 25.21 | 0.22 | 0.88 | 3619 | 24 | 41/3 | 19 | 13 | 0.97/0.42/0.27 | 74/62/47 | -2.99 | 1.91 | 0.00 |
| UNDEAD MAGE | 10.91 | 24.41 | 0.22 | 0.87 | 3619 | 21 | 39/3 | 18 | 13 | 0.97/0.43/0.28 | 70/64/46 | -3.01 | 2.91 | 0.10 |
| UNDEAD WARLOCK | 10.64 | 24.45 | 0.22 | 0.86 | 3619 | 22 | 44/5 | 18 | 16 | 1.03/0.42/0.28 | 74/62/50 | -3.21 | 3.70 | 0.07 |
| TAUREN WARRIOR | 11.45 | 27.10 | 0.22 | 0.89 | 3619 | 21 | 35/21 | 13 | 7 | 0.74/0.43/0.27 | 61/65/44 | -1.32 | 0.10 | 0.08 |
| TAUREN HUNTER | 10.18 | 22.22 | 0.22 | 0.86 | 3619 | 21 | 35/21 | 12 | 6 | 0.80/0.43/0.27 | 63/63/44 | -1.57 | 0.00 | 0.08 |
| TAUREN SHAMAN | 10.85 | 24.96 | 0.22 | 0.88 | 3619 | 23 | 38/23 | 13 | 7 | 0.75/0.43/0.27 | 62/64/44 | -1.35 | 0.10 | 0.08 |
| TAUREN DRUID | 13.36 | 28.51 | 0.22 | 0.88 | 3619 | 23 | 44/25 | 12 | 18 | 0.79/0.45/0.28 | 67/68/49 | -1.55 | 4.97 | 0.12 |
| TROLL WARRIOR | 9.97 | 25.62 | 0.22 | 0.89 | 3619 | 15 | 33/4 | 12 | 6 | 0.75/0.43/0.27 | 51/64/44 | -1.70 | 0.00 | 0.02 |
| TROLL HUNTER | 8.85 | 20.90 | 0.22 | 0.86 | 3619 | 15 | 33/5 | 11 | 6 | 0.83/0.42/0.27 | 54/62/44 | -2.03 | 0.00 | 0.02 |
| TROLL ROGUE | 9.46 | 23.92 | 0.22 | 0.88 | 3619 | 15 | 36/6 | 11 | 9 | 0.75/0.42/0.27 | 50/64/45 | -1.70 | 1.42 | 0.02 |
| TROLL PRIEST | 10.24 | 25.38 | 0.22 | 0.88 | 3619 | 16 | 44/7 | 12 | 15 | 0.78/0.42/0.27 | 56/62/47 | -1.81 | 2.23 | 0.01 |
| TROLL SHAMAN | 9.58 | 23.69 | 0.22 | 0.88 | 3619 | 18 | 35/4 | 12 | 6 | 0.79/0.43/0.27 | 55/63/44 | -1.87 | 0.00 | 0.03 |
| TROLL MAGE | 10.68 | 24.18 | 0.22 | 0.87 | 3619 | 15 | 54/5 | 11 | 13 | 0.80/0.43/0.28 | 52/64/46 | -1.91 | 2.91 | 0.09 |
| TROLL WARLOCK | 9.05 | 22.85 | 0.22 | 0.86 | 3619 | 15 | 41/7 | 11 | 13 | 0.79/0.42/0.28 | 53/62/50 | -1.90 | 2.43 | 0.00 |
| SKYBORNE_H WARRIOR | 9.43 | 25.11 | 0.22 | 0.88 | 3619 | 22 | 29/16 | 12 | 6 | 1.16/0.46/0.27 | 96/70/44 | -4.61 | 0.00 | 0.00 |
| SKYBORNE_H HUNTER | 8.33 | 20.49 | 0.21 | 0.86 | 3619 | 23 | 29/19 | 12 | 6 | 1.22/0.45/0.27 | 98/69/44 | -4.78 | 0.00 | 0.00 |
| SKYBORNE_H ROGUE | 9.13 | 23.56 | 0.22 | 0.87 | 3619 | 21 | 30/18 | 12 | 9 | 1.14/0.45/0.27 | 94/70/45 | -4.55 | 1.42 | 0.00 |
| SKYBORNE_H SHAMAN | 8.82 | 23.10 | 0.21 | 0.87 | 3619 | 22 | 30/19 | 12 | 6 | 1.16/0.47/0.27 | 97/72/44 | -4.86 | 0.00 | 0.00 |
| SKYBORNE_H DRUID | 10.86 | 26.21 | 0.21 | 0.87 | 3619 | 24 | 42/20 | 12 | 15 | 1.17/0.47/0.27 | 97/73/46 | -4.70 | 3.86 | 0.03 |
