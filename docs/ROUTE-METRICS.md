# Route metrics

How fast Braindead 4ever's routes are, measured the same way for all 56 race and class combinations in both modes. This file holds the results; the measuring tools are kept outside this repository. They are not needed to build the addon or the route data (see [ROUTE-FORMAT.md](ROUTE-FORMAT.md)).

## What the numbers are

- **Modellstunden.** Every time in this file is a Modellstunde (model hour): what a model of the game charges for a route, not a forecast of real play time. Rankings between routes carry; absolute hours do not.
- **Real play time replaces them.** Braindead 4ever shares run times per level and route section between players ([RUN-TIMES.md](RUN-TIMES.md)). Once enough runs come in, the routes are measured against real play, published as summarised values (median and number of runs).
- **Scope.** Every combination is played to level 30 in both modes; all 56 get there in both.

## Results 2026-11-04: routes of 0.9.1

Modellstunden for levels 1 to 30 per faction and mode, grind hours (time spent killing mobs for XP beyond the quests), and the smallest share of quest XP in a band of ten levels (by the level a quest is handed in at):

| Mode | Faction | fastest | median | slowest | median 1–20 | grind median | quest XP share, lowest band |
| --- | --- | --- | --- | --- | --- | --- | --- |
| speed | Alliance | 23.40 (Skyborne hunter) | 26.52 | 28.56 (dwarf warrior) | 9.50 | 7.76 | 0.42 |
| speed | Horde | 22.15 (Skyborne hunter) | 25.08 | 27.55 (tauren warrior) | 9.14 | 7.00 | 0.44 |
| explorer | Alliance | 22.72 (Skyborne hunter) | 25.84 | 27.91 (dwarf warrior) | 9.40 | 7.94 | 0.44 |
| explorer | Horde | 21.63 (Skyborne hunter) | 24.38 | 26.79 (tauren warrior) | 9.04 | 6.18 | 0.47 |

The routes of 0.9.0, measured with the same model on the same day:

| Mode | Faction | fastest | median | slowest | median 1–20 | grind median | quest XP share, lowest band |
| --- | --- | --- | --- | --- | --- | --- | --- |
| speed | Alliance | 25.54 (Skyborne hunter) | 30.58 | 33.53 (dwarf warrior) | 11.66 | 16.02 | 0.29 |
| speed | Horde | 25.28 (Skyborne hunter) | 30.51 | 34.67 (tauren warrior) | 11.38 | 16.77 | 0.23 |
| explorer | Alliance | 23.88 (Skyborne hunter) | 29.47 | 31.62 (dwarf warrior) | 10.80 | 12.77 | 0.38 |
| explorer | Horde | 23.96 (Skyborne hunter) | 28.98 | 33.54 (tauren druid) | 10.30 | 13.77 | 0.27 |

Every one of the 112 routes (56 combinations, two modes) is faster than its 0.9.0 counterpart, by 5 to 25 % (median 15 %), and grinds 27 to 61 % less. The model was refined since the 2026-11-01 results below, so the hours of the two dates do not compare with each other; the two tables above do.

## Results 2026-11-01: route data of that date (Welle 5)

Modellstunden for levels 1 to 30 per faction and mode:

| Mode | Faction | fastest | median | slowest | median 1–20 |
| --- | --- | --- | --- | --- | --- |
| speed | Alliance | 21.12 (Skyborne hunter) | 24.76 | 26.87 (gnome warrior) | 10.23 |
| speed | Horde | 20.84 (Skyborne hunter) | 24.70 | 27.67 (tauren warrior) | 10.38 |
| explorer | Alliance | 20.73 (Skyborne hunter) | 25.09 | 26.10 (gnome warrior) | 10.02 |
| explorer | Horde | 20.49 (Skyborne hunter) | 24.24 | 28.51 (tauren druid) | 9.90 |

New route data comes with new results in this file.
