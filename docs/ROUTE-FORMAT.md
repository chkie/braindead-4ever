# Route format

Braindead 4ever's routes live in the repository as readable text files (`data/routes/**/*.route`). A compiler turns them into compact Lua tables (`Braindead4Ever/Routes/Data_<Faction>.lua`) that the addon loads. A linter checks every file and every one of the 56 race and class combinations before a merge. This document is the specification; the tools in `tools/routekit` implement it.

Format version: 1 (2026-11-01).

## Pipeline

```
foreign data (cloned outside the repo)
        |  python3 -m tools.routekit import
        v
data/sources/<source>/   ----merge---->  data/facts/quests.jsonl, dungeons, finds, times,
                                         npcs, flightnodes, flightedges (+ FACTS.json)

data/routes/<faction>/*.route + COMPOSE        (the source form of the route data)
        |  lint (all 56 combinations, against data/facts)
        |  compile
        v
Braindead4Ever/Routes/Data_<Faction>.lua
```

The route files are the source form of the compiled data: they are read and changed as text, and `compile` turns them into the Lua tables. Everything needed for that is in this repository. The tools that plan and measure the routes are kept outside it; they are not needed to lint, compile or change a route.

| Command (from the repository root) | What it does |
| --- | --- |
| `python3 -m tools.routekit import --polestar DIR --eglink DIR --att DIR` | reads the three sources from local clones and writes `data/sources/` |
| `python3 -m tools.routekit merge` | merges the sources into `data/facts/` with sources and status per value |
| `python3 -m tools.routekit lint [FILES]` | checks route files; without arguments all files, all 56 combinations and the facts on service NPCs and flights |
| `python3 -m tools.routekit compile` | writes `Braindead4Ever/Routes/Data_Alliance.lua` and `Data_Horde.lua` |
| `python3 -m tools.routekit check` | lint, then compile into a temporary folder and compare with the committed files (CI) |

The tools need Python 3.11 or later (standard library only). Reading All The Things needs Lua 5.1 (`scripts/setup.sh` installs it in `.tools/`).

## Sources

Only these sources may provide data (decision FD-1101 of 2026-11-01):

| Key | Source | Licence | Used for |
| --- | --- | --- | --- |
| `polestar` | Polestar forever-db, tables only (not the Polestar guides) | GPL-3.0-only | quests, levels, races and classes, givers, turn-ins, prerequisites, objectives, spawn points, map frames; service NPCs (role and class from the title, faction template, spawn points) |
| `att` | All The Things, Forever database | MIT | givers, coordinates, prerequisites, races, classes, required level; flight points with their flight master |
| `eglink` | EG Link output (Efficient Games) | CC BY 4.0 | measured giver and turn-in positions, faction per quest, levels and race mask, start positions; service NPCs (window opened, side, where players stood), flights (flight points of each trip, flight seconds) |
| `own` | our own measurements | GPL-3.0-or-later | everything, once the data collector delivers |
| `plan` | route logic written by the team | GPL-3.0-or-later | travel steps, notes, planned levels; never IDs or coordinates |

RestedXP, Leveldon, QuestieDB, warcraft.wiki.gg and Warcraft Tavern may be used for comparison only; their data never goes into a file. All other sources are excluded. Credits and licence texts: `NOTICE`.

No names or texts from the game go into the repository: quest and item names come from the client at runtime (`C_QuestLog.GetTitleForQuestID`), in the player's language.

## Facts (`data/facts/quests.jsonl`)

One JSON object per quest. Every field that holds a value from a source has the form `{"v": value, "src": [sources that agree]}`; positions also have `seen` (all sources that gave a position) and `roots`. Every record has `"status": "unbestätigt"`.

Rules applied by `merge` (decided 2026-11-01, revisable):

1. **Roots.** `polestar`, `att` and `eglink` count as separate roots. For a new quest (ID 70000 and above) Polestar and EG Link agreeing count as one root, because Polestar takes part of its new-quest data from EG Link.
2. **Positions.** EG Link (measured) wins over Polestar (spawn point) over ATT (map percent). Positions agree within 10 yards. On the four maps whose frame changed in Forever (Mulgore 1412, Eastern Plaguelands 1423, Redridge Mountains 1433, Stormwind City 1453) map-percent coordinates are not used. The zone of a bare world point is the zone frame that contains it, preferring the quest's ATT zone and then the zone most quests of the same Polestar `zone_area` were measured in.
3. **Prerequisites.** Groups of quest IDs; one ID per group is enough. Breadcrumb quests are never required. The state is
   - `secured` when at least one root states the prerequisites and no root states something else (a root that names a subset agrees), or when a Classic quest (ID below 70000) has none in any root, or when a new quest has none in both Polestar and ATT in a level band where both roots state prerequisites for at least half of the new quests they list (measured: levels 1 to 10 only, see `data/facts/FACTS.json`);
   - `conflict` when roots state different prerequisites;
   - `unknown` otherwise.
4. **Levels.** Minimum level from EG Link, then ATT, then Polestar; Polestar's placeholder minimum level 1 for quests above level 5 is ignored.
5. **Band.** Quests with a minimum level up to 30 and a quest level up to 34.
6. **XP.** `xp` is the full quest XP as Polestar states it (no other source has it); the addon applies the level reduction itself and prefers the client's value while the quest is in the log (`docs/ROUTE-RUNTIME.md`).

## Service NPCs and flights (`data/facts/npcs.jsonl`, `flightnodes.jsonl`, `flightedges.jsonl`)

Facts for the plan elements `train`, `sethome` and `fp` and for planning flights (added 2026-11-03, Welle 10). They are not in the compiled data yet; the routes take them up in a later step. `merge` writes them (`tools/routekit/services.py`); every value has `src`, every record `"status": "unbestätigt"`.

**Service NPCs**, one record per role and NPC, sorted by NPC ID:

```json
{"id": 198, "role": {"v": "trainer", "src": ["polestar"]},
 "class": {"v": 8, "src": ["polestar"]}, "side": {"v": "A", "src": ["polestar"]},
 "pos": {"v": [1429, -188, -8851.5], "src": ["polestar"], "seen": ["polestar"], "roots": 1},
 "zone": 1429, "status": "unbestätigt"}
```

- `role`: `trainer` (class trainer), `innkeeper` or `flightmaster`. Polestar chooses by title (`<Class> Trainer`, `Innkeeper`, `Gryphon Master`, `Wind Rider Master`, `Hippogryph Master`, `Flight Master`, `Bat Handler`); EG Link by the window a player opened (`Binder`, `TaxiNode`, a trainer list of trainer type 0); ATT by the flight master of a flight point. Titles and names are read, never written.
- `class` (trainers only): classID from Polestar's title. A trainer without it is left out: EG Link's trainer type 0 also covers pet trainers, weapon masters and riding instructors (measured 2026-11-03).
- `side`: `A`, `H` or `B` (both). EG Link (as the game showed it) wins over ATT (races of the flight point) over Polestar. Polestar's side is derived from the faction template: per template, the quests NPCs with it give and take count by quest side; one side when at least 95 % of the one-faction quests have it and there are at least 3, both sides when both factions have such quests and quests for both are at least half of all, otherwise none. On the merge of 2026-11-03 all 50 NPCs with an EG Link side and all 32 with an ATT side agreed with the derived side. A source that states another side goes to `alt`.
- `pos`: as for quests, EG Link (where a player stood at the open window) before Polestar (spawn point) before ATT (map percent, not on the four changed maps); agreement within 10 yards. Polestar takes part of its Forever data from EG Link, so for service NPCs the two count as one root.
- `zone`: the uiMap. A bare world point (Polestar) lies in several zone rectangles at zone borders (Darkshire inside the frame of Deadwind Pass, Ratchet inside Durotar's); it takes the map of another source within 50 yards, else the zone that most EG Link positions within 150 yards name, else the smallest frame.
- `node` (flight masters): the flight point, from EG Link and ATT.
- Only NPCs in a route zone are kept: the zones in `tools/routekit/game.py` `ZONES` (the zones of levels 1 to 34 and the capitals; `FACTS.json` `rules.serviceZones`).

**Flight points**, one record per point (`node` is the flight point ID the client reports as `nodeID`): `src` (sources that name the point), `masters` (flight master NPC IDs), `side`, `pos` (the flight master's position, else ATT's coordinate), `zone`. All points of the sources are kept, also outside the route zones, so a trip through a point outside them can be planned.

**Flight legs**, one record per direct leg, directed, key `<from>><to>`:

```json
{"key": "10>11", "from": 10, "to": 11, "src": ["eglink"], "trips": 1,
 "seconds": {"v": 112, "src": ["eglink"], "flights": 4}, "status": "unbestätigt"}
```

- A leg exists only when a source flew it: two consecutive flight points of a trip in EG Link (`flights.json`, `hops`) or in our own records. No leg is derived from anything else, also not the way back. The stops of a trip depend on the points the character knows (EG Link saw 22>80 both through 25 and through 77 and 25); every sequence seen counts.
- `seconds` measured: the median of the flights of a trip flown without a stop (one sequence of two points), our own before EG Link; trips with the Legacy talent Frequent Flier do not count.
- `seconds` model value: `{"v": n, "basis": "model"}`, the straight distance between the two flight points times the median seconds per yard of all measured legs (`FACTS.json` `flightModel`; 2026-11-03: 0.0484 s per yard over 25 legs, about 20.7 yards per second). Leaving one measured leg out at a time, the model missed it by 22 % in the median and 34 % at most; the measured legs of nine trips with stops added up to the measured trip within 0 to 7 % (median 0.6 %), so a trip with stops costs the sum of its legs. Measured values replace the model value at the next merge.

Own measurements come from the data collector (records `taxilegs`, `flight`, `land`, docs/STATUS.md) through `observe` into `data/sources/own/flights.jsonl` (same layout as EG Link's, legs from the flight master's map as `leg:<a>><b>`); landings outside 5 to 1800 seconds are dropped (chosen values). Legs and seconds other players sent in the game come along in the export (below) and go into the same file: legs as `leg:<a>><b>`, seconds as `net:<a>><b>`, counted with the own ones.

## Flights in the exchange

Flight legs and measured flight seconds reach other players in the game and with them every export, without adding traffic to the hidden channel (plan "Flugdaten im Austausch", Welle 11, 2026-11-03; owner, 2026-11-03: why do the flight data stay with the player instead of going through the exchange?). Before, they stayed in the own records. In the addon they are not used for the route yet; routes come from the facts above.

Code: `Collector/Flights.lua` (flight vault, checks, saturation, relaying), `Collector/Proto.lua` (message), `Collector/Collect.lua` (flight master's map, landing, export), `Collector/Exchange.lua` (receiving, relaying), `Routes/Data_Flights.lua` (facts for the checks, generated by `compile` from `flightnodes.jsonl`, `flightedges.jsonl` and `FACTS.json` `flightModel`). Tests: `spec/flights_spec.lua`, `tools/tests/test_services.py`.

**Message `h`**, one directed leg, printable ASCII:

```
h;1;<from>;<to>;<seconds>
h;1;2;5;135
```

`from` and `to` are flight point IDs as the client reports them in `nodeID`; `seconds` is one flight from `from` to `to` without a stop, from the choice at the flight master to the landing, or 0 when only the connection was seen (a leg of the flight master's map, or seconds that cannot be checked). Nothing else: no map, no position, no name, no token, no time. Readers that do not know `h` skip it without counting it as broken.

**Flight vault** (`BraindeadForeverCollectDB.flights`): per leg the independent sources and measured flights this client knows, the last five measured seconds and whether the player saw it; the flight points seen at the player's own flight masters; the received messages taken, for the export (2000, the oldest give way). Sender names live in session tables only.

- **Sources:** the own observation (once), each other player once per leg and session, the facts (once). **Measures:** own and received seconds plus the flights the facts measured.
- **Checks:** both flight points in the facts or seen at an own flight master; not a leg to itself and not across two continents; seconds from 5 to 1800 and from 0.3 to 3 times the model value (straight distance of the facts' points times `secondsPerYard`, 0.0484 on 2026-11-03). A leg that fails is dropped. Seconds that cannot be checked (a point without a position in the facts) count as the connection only. A 5-second flight over the 3.0 km of 22>38 (model 159 s) is dropped; without the model band it would pass (counter-check in `spec/flights_spec.lua`).
- **Saturation:** a message about a leg goes out (sent or relayed) only while it adds something for others: the connection while the client knows it from fewer than 3 sources, seconds while it has fewer than 3 sources or fewer than 5 measured flights. So the flight messages fall as the network becomes known.

**Sending.** A flight without a stop that passes the checks and adds something is offered like a find: to the group at once, to guild and channel 30 to 90 s later (once per leg and session). The legs of a flight master's map and what came from group or guild are relayed on the hidden channel only, each leg once per session, the player's own legs first, then the newest, one message per 10 s at most, only while no own find is due there and the queue is less than half full, and never in a fight or an instance. A leg heard on the channel in this session is not relayed. On the channel every flight message needs a credit of the find pool of the channel budget ([RUN-TIMES.md](RUN-TIMES.md) §Channel budget): flight legs take no share of their own, so the channel carries no more than before; they use credits no own find is waiting for. A received leg counts towards the sender's limit of 40 finds in 5 minutes.

**Export.** The PM1 export carries the received messages taken and not exported yet under the key `flights`, `flightsFrom` is the sequence number of the first, so overlapping exports count each message once. `node decoder/cli.mjs --flights < export.txt` writes them as CSV (`from,to,seconds`); `observe` adds them to `data/sources/own/flights.jsonl` (above). A measurement relayed to several exporting players counts once per export.

**Spread simulation** (`spec/helpers/spread.lua` with `flights = true`, run by `spec/flights_spec.lua`): the runs model of [RUN-TIMES.md](RUN-TIMES.md) plus the real `Flights.lua` and facts. The network is the 97 fact legs between two placed points, each with the model seconds times 0.9 to 1.3; 30 % of them (30 legs) are left out of the facts the clients get, so only players can bring them. Every 30 minutes of play a client opens a flight master at a random point (the legs of the point and of its neighbours go into the vault) and in half of the cases takes a flight without a stop. Finds are real here: one per minute of play, each waiting a minute for a credit; a credit of the find pool goes to the first due find or own flight, else to a relay. Every online client hears every flight message. Seed 20261102, 10 exporting clients:

| Clients, rounds | Received per client and s, mean | Busiest client | Most in 60 s | Flight messages (own flights, relays) | Finds on the channel | Legs of others that reached an exporter, mean (at least one) | Legs unknown to the facts | Legs with seconds |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1,000, 10 | 0.177 | 0.190 | 27 | 1,840 (86, 1,754) | 8,631 | 0.993 (1.000) | 0.997 (1.000) | 0.802 (0.887) |
| 100, 30 | 0.152 | 0.163 | 26 | 5,021 (112, 4,909) | 23,275 | 1.000 (1.000) | 1.000 (1.000) | 0.932 (0.959) |

The limits of 0.5 per second and 60 in 60 s hold as before (runs model alone at 1,000 clients: 0.174, 0.190, 26). Flight messages took 18 % of the find pool's messages at 1,000 clients in the first 10 rounds. Saturation needs time: at 100 clients over 30 rounds the flight messages fell from 2,039 in rounds 1 to 10 to 1,113 in rounds 21 to 30. Counter-check without saturation (`SOURCES_MIN` infinite): 2,133 in rounds 21 to 30, about as many as at the start; the channel's total stays within the budget either way, so without saturation the legs keep taking credits from the finds. Model values are chosen; how often players fly and how many flight points exist in Forever is measured from 2026-11-05.

**Chosen values**

| Value | Where | Setting |
| --- | --- | --- |
| Sources after which a connection is not sent | `Flights.SOURCES_MIN` | 3 |
| Measured flights after which seconds are not sent | `Flights.MEASURES_MIN` | 5 |
| Model band | `Flights.MODEL_LOW`, `Flights.MODEL_HIGH` | 0.3 to 3 times the model value |
| Seconds of a flight | `Flights.SECONDS_MIN`, `Flights.SECONDS_MAX` | 5 to 1800 (as `observe`) |
| Relay gap | `Flights.RELAY_GAP` | 10 s |
| Legs, flight points seen, messages kept for the export | `Flights.LEGS_MAX`, `NODES_MAX`, `EXPORT_MAX` | 1000, 500, 2000 |

## NPCs of the step texts

Accept and turn-in steps name the quest giver and the turn-in NPC (M4). `compile` writes `Braindead4Ever/Routes/Data_Npcs.lua` from `data/facts/quests.jsonl`: per faction a function (only the played faction's table is built), per quest `{ giver, sources, turn-in, sources, status }`.

```lua
ns.NpcFacts.Alliance = function()
	return {
		[33] = { 196, 3, 196, 1, 0 },   -- giver NPC, sources bit field, turn-in NPC, sources, status
		[2] = { 0, 0, 12696, 5, 0 },    -- 0: the sources name no single NPC (an item starts quest 2)
	}
end
```

- NPC IDs only, never names: the addon takes the name from the client in the player's language (creature cache or learned when the player meets the NPC, `Braindead4Ever/UI/NpcNames.lua`), so no English name shows in another client.
- An NPC is kept only when the fact names exactly one NPC and nothing else (no item, no object); with two givers the step stays without a name.
- Every quest the faction can take (side of the faction, both or unknown), not only the quests of the routes, so a route change needs no new table. Sources and status as in the facts (bit field as for elements, status 0 = unbestätigt).

Tests: `spec/ui_npcnames_spec.lua`, `tools/tests/test_routekit.py` (`Compiler`).

## Route files

UTF-8, one module per file, `data/routes/<faction>/<module>.route`. `--` starts a comment (outside quotes).

### Header

```
#module  a-speed-start-elwynn      unique key: letters, digits, hyphens
#kind    start                     start | core | class
#faction Alliance                  Alliance | Horde
#mode    speed                     speed | explorer
#levels  1-10                      planned level band
#for     race=HUMAN                optional module filter
#text    Wald von Elwynn           optional description (block list applies)
#label   vorläufig                 vorläufig | stabil
#version 1                         integer, raised on every change of content
#sources polestar=2026.10.1@463c52c att=f8d538a eglink=572beca
```

`#label stabil` is reserved for sections with 20 measured runs whose median moved less than 5 % between two weekly releases (Plan, stable rule). Until the data collector delivers, every module is `vorläufig`.

### Steps

```
@a783 lv=1 << race=HUMAN class=WARRIOR !return "Klassenquest"
  accept 783                         | src=polestar,att status=unbestätigt
  goto 1429 -136.5,-8933.5 r=10      | src=polestar,att status=unbestätigt roots=2
```

- `@<id>`: step ID chosen by the author, unique in the module, never renumbered. Progress is stored by module key and step ID, never by line. The builder uses `a<quest>` (accept), `c<quest>` (objectives), `t<quest>` (turn-in) and `r<uiMapID>` (travel).
- `lv=<n>`: planned level at this step.
- `<< filter`: who sees the step (below).
- `!return "<reason>"`: the step goes back into a zone the route has left before; the reason is required.

### Elements

| Element | Meaning | Source required |
| --- | --- | --- |
| `accept <quest>` | take the quest | data source |
| `complete <quest>` | finish all objectives | data source |
| `turnin <quest>` | hand the quest in | data source |
| `collect <item> <count>` | have the items in the bags | data source |
| `goto <uiMapID> <wx>,<wy> [r=<yards>]` | go to a world position; `wx` is the west axis (second value of `UnitPosition`), `wy` the north axis (first value) | data source |
| `travel <how> <uiMapID>` | change zone; `how` is walk, fly, boat, zeppelin, airship, tram, portal or hearth | `plan` or data |
| `hs`, `sethome`, `fp`, `train` | use or set the hearthstone, get a flight path, visit the trainer | `plan` or data |
| `xp <level>` | reach a level | `plan` or data |
| `note "<text>"` | a hint in our own words, infinitive style | `plan` |

Every element ends with `| src=<sources> status=<status>`, optionally `roots=<n>` on `goto`. `status` is `unbestätigt` or `bestätigt`; `bestätigt` needs `own` in `src`.

A step's zone is the target of its last `travel` element, else the map of its `goto`. Several `goto` in one step must be in the same zone.

### Filters

`race=` and `class=` with comma-separated tokens; a leading `!` negates the whole list. Dimensions are combined with AND, tokens with OR.

| Race token | raceID | Class token | classID |
| --- | --- | --- | --- |
| HUMAN | 1 | WARRIOR | 1 |
| DWARF | 3 | PALADIN | 2 |
| NIGHTELF | 4 | HUNTER | 3 |
| GNOME | 7 | ROGUE | 4 |
| SKYBORNE_A | 95 | PRIEST | 5 |
| ORC | 2 | SHAMAN | 7 |
| UNDEAD | 5 | MAGE | 8 |
| TAUREN | 6 | WARLOCK | 9 |
| TROLL | 8 | DRUID | 11 |
| SKYBORNE_H | 96 | | |

Both Skyborne races report `raceFile` "Skyborne"; the addon tells them apart by raceID (brain chapter 14). The allowed combinations are the 56 rows of the client table `CharBaseInfo` (`tools/routekit/game.py`).

### Composition (`data/routes/<faction>/COMPOSE`)

```
#faction Alliance
#mode speed
start a-speed-start-elwynn << race=HUMAN
core  a-speed-core-01-1436 a-speed-core-02-1432 ...
insert after a-speed-core-01-1436 a-speed-class-human-priest-01 << race=HUMAN class=PRIEST
```

The route of a combination: the first `start` module whose filter applies, then for each anchor (`start`, then every core module in order) the core module itself and the `insert` modules after it whose filter applies.

## Building blocks and modes

- **Start modules**: one per start zone and faction (Elwynn Forest, Dun Morogh, Teldrassil, Durotar, Mulgore, Tirisfal Glades, Zephras Isle for each faction). Start zones per race are measured by EG Link (`data/sources/eglink/starts.jsonl`). Class quests inside the start zone are steps with a class filter.
- **Core route**: one per faction, split into zone blocks with a level band each. Class quests that stay inside a block's zone are steps with a class filter.
- **Class inserts**: per race and class, the class quests in zones the route does not visit (capitals, Moonglade); placed after the start module or after the core block whose level band reaches the quest's minimum level. Their travel steps carry `!return "Klassenquest"`.
- **Speed** (`#mode speed`): no quest without a secured prerequisite, no breadcrumbs.
- **Explorer** (`#mode explorer`): also quests with an unknown or conflicting prerequisite and breadcrumbs. Known prerequisites are still enforced.

These are computed routes, not played ones. Until our own measurements arrive, the planned levels (`lv`) stay planning values. How the routes measure: [ROUTE-METRICS.md](ROUTE-METRICS.md).

## Linter

Run per file and per combination (56 combinations, both modes). Each error has a code:

| Code | Rule |
| --- | --- |
| `syntax`, `kopf`, `schritt` | syntax, required header lines, unique step IDs, no empty step |
| `herkunft` | every element names its sources (`src=`) |
| `quelle` | only sources allowed by FD-1101; data elements need a data source |
| `beleg` | the named sources really hold the quest (data/facts), and a `goto` lies within 10 yards of a position those sources give for a quest of the step, or, in a step with `train`, `sethome`, `fp` or `travel fly` (the flight lands at a flight master), for a class trainer, innkeeper or flight master (or flight point) whose side is not the other faction |
| `status` | status given; `bestätigt` only with `own` |
| `label` | no section is `stabil` without measurements |
| `sperrliste` | block list in notes and `#text`: typical AI phrases (for example "tauche ein", "nahtlos", "mühelos", "episch"), exclamation marks, emoji |
| `karte` | a `goto` lies on its map (catches swapped axes); known travel targets |
| `fraktion` | quest belongs to the module's faction |
| `filter` | a quest only some races or classes can take has a filter that is not wider; per combination: every accepted quest is available to it |
| `stufe` | planned level within `#levels`; minimum level not above the planned level; quest level at most 2 above it |
| `speed` | Speed modules contain no quest without a secured prerequisite |
| `reihenfolge` | per combination: accept before objectives and turn-in, no quest taken twice |
| `vorquest` | per combination: a prerequisite is handed in before the follow-up is accepted |
| `gegenstand` | per combination: a quest with items to bring is handed in only after `complete` or `collect` of all items |
| `reise` | per combination: every zone change has a `travel` element |
| `ruecksprung` | per combination: no return into a zone left earlier without `!return "<reason>"` |
| `compose` | every combination gets a route; modules exist and match faction and mode |

Without file arguments the linter also checks the facts on service NPCs and flights, with the same codes: `herkunft` (a value without `src` that is not marked `"basis": "model"`), `quelle` (a source FD-1101 does not allow), `status`, `karte` (position on its uiMap, `zone` equal to that map, service NPCs in a route zone), `beleg` (legs and flight masters name known flight points), `fakt` (unknown role, trainer without class). Counter-checks for each in `tools/tests/test_services.py`.

Acceptance (Plan, work package 5): ten prepared errors in `tools/tests/fixtures/bad` (one per rule: herkunft, quelle, sperrliste, gegenstand, vorquest, ruecksprung, reise, filter, speed, label) are each found with exactly their code; the clean route in `tools/tests/fixtures/good` passes. The fixtures use made-up quest IDs (900001 and up).

## Compiled form

`Braindead4Ever/Routes/Data_<Faction>.lua` sets `ns.RouteData.<Faction>` to a function that returns the data, so only the played faction's tables are built. `Braindead4Ever/Routes/Routes.lua` puts a route together (`ns.Routes.Steps(faction, mode, raceID, classID)`).

```lua
{
  format = 1, faction = "Alliance", sources = "...",
  modules = {
    ["a-speed-start-elwynn"] = {
      kind = "start", mode = "speed", levels = { 1, 10 }, label = "vorläufig", version = 1,
      r = { 1 },                             -- module filter: raceIDs (r) and classIDs (c)
      steps = {
        { id = "a783", lv = 1, c = { 1 }, ret = nil, <element>, <element>, ... },
      },
    },
  },
  compose = { speed = { starts = { { key = "...", r = { 1 } } }, core = { "..." },
                        inserts = { { after = "start", key = "...", r = { 1 }, c = { 5 } } } },
              explorer = { ... } },
  quests = {                                 -- every quest the faction's modules name
    [6] = { 5, 340, { { 18 } } },            -- quest level, full XP, prerequisite groups
    [783] = { 1, 40 },                       -- no prerequisites: no third value
  },
}
```

Added with Welle 4 (additive, format stays 1):

```lua
  unsure = { 3116, 3117, ... },              -- route and dungeon quests whose prerequisites no source secures
  dungeons = { [63] = { area = 1581, min = 10, lo = 15, hi = 24, entrance = { 1436, 1539.7, -11327.3 },
                        quests = { 166, 167 } } },
  dquests = { [166] = { 22, 14, 3975, 1436, 1045, -10509, pre = { { 155 } }, r = { 1 }, c = { 9 } } },
                                             -- quest level, min level, full XP (Forever rule), giver uiMap, wx, wy
  finds = { { 4, 100, 1429, 2760, 8840 } },  -- type (1 quest, 2 treasure, 3 book, 4 rare, 5 flight path,
                                             -- 6 place), ID, uiMap, x, y pairs (hundredths of a percent)
  times = { ["a-speed-start-elwynn"] = { 20, 3600 } },  -- real runs, median seconds (own data)
  classic = { 2, 5, 6, ... },                -- quest IDs the facts know as Classic (not new in Forever)
  maps = { [1411] = 1, [1453] = 0 },         -- continent of every uiMap of goto points and dungeon givers
```

Interface for Welle 7 (additive, format stays 1; filled by the route builder of Welle 6b, until then absent):

```lua
  alts = {                                   -- alternative modules per switch point (docs/ROUTE-RUNTIME.md §Replanning)
    ["a-speed-core-01-1436"] = {             -- the module that starts at the switch point
      { key = "<module key>", plan = 16, map = 1437, gain = 900 },
    },                                       -- module key (in `modules`, own r/c filter), planned level,
  },                                         -- uiMap it leads to, seconds saved against the replaced module
```

`quests` (added 2026-11-01, additive, format stays 1) comes from `data/facts`: quest level (0 if unknown), full quest XP (0 if unknown) and the prerequisite groups of `pre` (one quest per group is enough; breadcrumbs are never in it). The route runtime uses it for skipping follow-up quests and for the XP balance.

Elements are flat arrays `{ verb, arguments..., sources, status [, roots] }`:

| Verb | Code | Layout |
| --- | --- | --- |
| accept, complete, turnin | 1, 2, 3 | `{ code, questID, sources, status }` |
| collect | 4 | `{ 4, itemID, count, sources, status }` |
| goto | 5 | `{ 5, uiMapID, wx, wy, radius, sources, status, roots }` |
| travel | 6 | `{ 6, how, uiMapID, sources, status }`; how: 1 walk, 2 fly, 3 boat, 4 zeppelin, 5 airship, 6 tram, 7 portal, 8 hearth |
| hs, sethome, fp, train | 7, 8, 9, 10 | `{ code, sources, status }` |
| xp | 11 | `{ 11, level, sources, status }` |
| note | 12 | `{ 12, "text", sources, status }` |

`sources` is a bit field: 1 polestar, 2 att, 4 eglink, 8 own, 16 plan. `status`: 0 unbestätigt, 1 bestätigt. An element with its own filter has `r`/`c` fields as well.

The compiled files are generated; CI recompiles and fails if they differ from the committed ones.

## Licence of the data

`data/sources/polestar`, `data/facts`, `data/routes` and the compiled files contain Polestar data and are GPL-3.0-only, without the Ace3 permission of `LICENSE-EXCEPTION.md`. `data/sources/eglink` is CC BY 4.0, `data/sources/att` MIT. `tools` is our own work under GPL-3.0-or-later. Details: `NOTICE`.
