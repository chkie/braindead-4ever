# Route format

Pathmark's routes live in the repository as readable text files (`data/routes/**/*.route`). A compiler turns them into compact Lua tables (`Pathmark/Routes/Data_<Faction>.lua`) that the addon loads. A linter checks every file and every one of the 56 race and class combinations before a merge. This document is the specification; the tools in `tools/routekit` implement it.

Format version: 1 (2026-11-01).

## Pipeline

```
foreign data (cloned outside the repo)      our route logic
        |  python3 -m tools.routekit import          data/plan/*.toml
        v                                            |
data/sources/<source>/   ----merge---->  data/facts/quests.jsonl
                                                     |  build
                                                     v
                                      data/routes/<faction>/*.route + COMPOSE
                                                     |  lint (all 56 combinations)
                                                     |  compile
                                                     v
                                      Pathmark/Routes/Data_<Faction>.lua
```

| Command (from the repository root) | What it does |
| --- | --- |
| `python3 -m tools.routekit import --polestar DIR --eglink DIR --att DIR` | reads the three sources from local clones and writes `data/sources/` |
| `python3 -m tools.routekit merge` | merges the sources into `data/facts/` with sources and status per value |
| `python3 -m tools.routekit build` | builds the module files from `data/plan/` and `data/facts/`, then lints all combinations and leaves out quests that cause errors until the linter is clean |
| `python3 -m tools.routekit lint [FILES]` | checks route files; without arguments all files and all 56 combinations |
| `python3 -m tools.routekit compile` | writes `Pathmark/Routes/Data_Alliance.lua` and `Data_Horde.lua` |
| `python3 -m tools.routekit check` | lint, then compile into a temporary folder and compare with the committed files (CI) |
| `python3 -m tools.routekit stats` | steps and quests per combination and level band |

The tools need Python 3.11 or later (standard library only). Reading All The Things needs Lua 5.1 (`scripts/setup.sh` installs it in `.tools/`).

## Sources

Only these sources may provide data (decision FD-1101 of 2026-11-01):

| Key | Source | Licence | Used for |
| --- | --- | --- | --- |
| `polestar` | Polestar forever-db, tables only (not the Polestar guides) | GPL-3.0-only | quests, levels, races and classes, givers, turn-ins, prerequisites, objectives, spawn points, map frames |
| `att` | All The Things, Forever database | MIT | givers, coordinates, prerequisites, races, classes, required level |
| `eglink` | EG Link output (Efficient Games) | CC BY 4.0 | measured giver and turn-in positions, faction per quest, levels and race mask, start positions |
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
- **Core route**: one per faction, split into zone blocks with a level band each (`data/plan/<faction>.toml`). Class quests that stay inside a block's zone are steps with a class filter.
- **Class inserts**: per race and class, the class quests in zones the route does not visit (capitals, Moonglade); placed after the start module or after the core block whose level band reaches the quest's minimum level. Their travel steps carry `!return "Klassenquest"`.
- **Speed** (`#mode speed`): no quest without a secured prerequisite, no breadcrumbs.
- **Explorer** (`#mode explorer`): also quests with an unknown or conflicting prerequisite and breadcrumbs. Known prerequisites are still enforced.

The builder orders the actions of a block greedily: the cheapest next action (accept, objectives, turn-in), cost in yards plus 600 yards for every level an accept would raise the planned level; quest log at most 20; quests more than 4 levels below the block start are skipped; quest level at most 2 above the planned level. The planned level never goes down. These are computed routes, not played ones; the simulator (AP 10) and our measurements replace the planned levels.

## Linter

Run per file and per combination (56 combinations, both modes). Each error has a code:

| Code | Rule |
| --- | --- |
| `syntax`, `kopf`, `schritt` | syntax, required header lines, unique step IDs, no empty step |
| `herkunft` | every element names its sources (`src=`) |
| `quelle` | only sources allowed by FD-1101; data elements need a data source |
| `beleg` | the named sources really hold the quest (data/facts), and a `goto` lies within 10 yards of a position those sources give for a quest of the step |
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

Acceptance (Plan, work package 5): ten prepared errors in `tools/tests/fixtures/bad` (one per rule: herkunft, quelle, sperrliste, gegenstand, vorquest, ruecksprung, reise, filter, speed, label) are each found with exactly their code; the clean route in `tools/tests/fixtures/good` passes. The fixtures use made-up quest IDs (900001 and up).

## Compiled form

`Pathmark/Routes/Data_<Faction>.lua` sets `ns.RouteData.<Faction>` to a function that returns the data, so only the played faction's tables are built. `Pathmark/Routes/Routes.lua` puts a route together (`ns.Routes.Steps(faction, mode, raceID, classID)`).

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

`data/sources/polestar`, `data/facts`, `data/routes` and the compiled files contain Polestar data and are GPL-3.0-only, without the Ace3 permission of `LICENSE-EXCEPTION.md`. `data/sources/eglink` is CC BY 4.0, `data/sources/att` MIT. `data/plan` and `tools` are our own work under GPL-3.0-or-later. Details: `NOTICE`.
