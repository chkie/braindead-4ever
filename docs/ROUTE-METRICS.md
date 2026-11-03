# Route metrics

How fast Braindead 4ever's routes are, measured the same way for all 56 race and class combinations in both modes. This file holds the results; the measuring tools are kept outside this repository. They are not needed to build the addon or the route data (see [ROUTE-FORMAT.md](ROUTE-FORMAT.md)).

## What the numbers are

- **Modellstunden.** Every time in this file is a Modellstunde (model hour): what a model of the game charges for a route, not a forecast of real play time. Rankings between routes carry; absolute hours do not.
- **Real play time replaces them.** Braindead 4ever shares run times per level and route section between players ([RUN-TIMES.md](RUN-TIMES.md)). Once enough runs come in, the routes are measured against real play, published as summarised values (median and number of runs).
- **Scope.** Every combination is played to level 30 in both modes; all 56 get there in both.

## Results 2026-11-01: routes of the current release data (Welle 5)

Modellstunden for levels 1 to 30 per faction and mode:

| Mode | Faction | fastest | median | slowest | median 1–20 |
| --- | --- | --- | --- | --- | --- |
| speed | Alliance | 21.12 (Skyborne hunter) | 24.76 | 26.87 (gnome warrior) | 10.23 |
| speed | Horde | 20.84 (Skyborne hunter) | 24.70 | 27.67 (tauren warrior) | 10.38 |
| explorer | Alliance | 20.73 (Skyborne hunter) | 25.09 | 26.10 (gnome warrior) | 10.02 |
| explorer | Horde | 20.49 (Skyborne hunter) | 24.24 | 28.51 (tauren druid) | 9.90 |

New route data comes with new results in this file.
