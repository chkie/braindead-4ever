# Route runtime

The logic behind the step window: which step is current, how the addon sees that a step is done, checking, skipping with follow-up quests, going back, undo, abandoned quests and the XP balance. The step window (Welle 5, `Pathmark/UI/`) reads this interface only through the adapter `UI/Connect.lua`; this document is that interface.

Status: built and tested offline (busted, Lua 5.1); not run in a client yet. Last update: 2026-11-01 (Welle 4: prerequisites from player data, explorer mode, dungeon hint, time forecast; Welle 5: window binding; Welle 5b: `Route.Quests`, riddle, area, forecast tooltip).

| File | What it does |
| --- | --- |
| `Pathmark/Routes/XP.lua` | Experience rules: Classic level table, kill XP (Forever rule for creatures below the character), quest XP by level difference, XP needed for a level, kills for a shortfall. Pure Lua; `tools/routekit/xp.py` computes the same (shared cases `tools/tests/fixtures/xp_cases.json`). |
| `Pathmark/Routes/Prereq.lua` | Prerequisites from player observations (Welle 4): the rule shared with `tools/routekit/prereq.py`. Pure Lua. |
| `Pathmark/Routes/Discover.lua` | Explorer mode rules (Welle 4): hint levels, riddle and rumor sentences, the area hint. Pure Lua. |
| `Pathmark/Routes/Dungeon.lua` | Dungeon hint (Welle 4). Pure Lua over the runtime and the compiled dungeon tables. |
| `Pathmark/Routes/Forecast.lua` | Time forecast (Welle 4). Pure Lua. |
| `Pathmark/Routes/Runtime.lua` | The rules below. Pure Lua: the client state comes in through a world table, so the tests run the same code. |
| `Pathmark/Routes/Guide.lua` | Module `route`: picks the route, feeds game events in, saves progress, offers `ns.Route`. |
| `Pathmark/Routes/Explore.lua` | Module `explore`: own finds, finds of other players, the catalog; offers `ns.Explore`. |

## Module `route`

Core module (runs in safe mode). Required: `C_QuestLog.IsQuestFlaggedCompleted`, `C_QuestLog.GetLogIndexForQuestID`, `C_QuestLog.IsComplete`, `C_Map.GetBestMapForUnit`, `UnitLevel`, `UnitRace`, `UnitClass`, `UnitFactionGroup`, `UnitXP`, `UnitXPMax`; events `PLAYER_LOGIN`, `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_LOG_UPDATE`. Optional: `GetQuestLogRewardXP` (undocumented), `GetXPExhaustion`, `C_Map.GetMapInfo`, `C_Item.GetItemCount` and the events `PLAYER_LOGOUT`, `QUEST_TURNED_IN`, `QUEST_WATCH_UPDATE`, `QUEST_LOG_CRITERIA_UPDATE`, `UNIT_QUEST_LOG_CHANGED`, `ZONE_CHANGED_NEW_AREA`, `BAG_UPDATE_DELAYED`, `PLAYER_LEVEL_UP`, `PLAYER_XP_UPDATE`, `UPDATE_EXHAUSTION`, `UI_INFO_MESSAGE`, `HEARTHSTONE_BOUND`. The probe checks them as `mod.route.*`.

At `PLAYER_LOGIN` the module reads faction (`UnitFactionGroup`), race ID and class ID (third return values of `UnitRace` and `UnitClass`; the two Skyborne races differ only there) and builds the route with `ns.Routes.Steps(faction, mode, raceID, classID)`. A race without a start module (new races are announced) gives no route; the problem report then says `no route for <faction> <race>/<class>`.

Quest events come in bursts, so the module evaluates at most once per 0.1 s. After `QUEST_REMOVED` it waits 1 s and reads the completion flag: flagged means handed in, not flagged and not back in the log means abandoned. `QUEST_TURNED_IN` is not needed for that, because Forever sends it late or not at all (brain chapter 06 §3, §4).

## Saved progress

`PathmarkCharDB.route` (per character), written back at logout even if the client replaced the table during the session:

```lua
PathmarkCharDB.route = {
  mode = "speed",                      -- "speed" | "explorer"; each mode keeps its own progress
  speed = {
    v = 1, race = 1, class = 1,        -- a different race or class starts over
    anchor = "a-speed-start-elwynn/c33", -- current step key, "_end" after the last step
    pin = nil,                         -- step the player went back to (see Back)
    marks = { ["<key>"] = "c" | "s" | "e" }, -- checked, skipped, event seen
    roots = { [questID] = "<key>" },   -- quests the player skipped, and from which step
    pending = nil,                     -- quest ID of an abandon question without answer
    undo = { ... },                    -- up to 20 snapshots of the fields above
    split = { m = "<module>", secs = 0, clean = true }, -- current module run (time forecast)
    dungeons = { [instanceID] = true },                -- dungeon hints the player skipped
  },
  rate = { secs = 0, xp = 0 },         -- own XP rate from active play, last 2 hours (time forecast)
}
PathmarkCharDB.explore = { level = 0, style = "self", found = { ["rare:100"] = "1429;2700;8800" },
                           asked = { ["treasure:3642"] = 3 } }
PathmarkDB.prereq = { obs = { [questID] = { [token] = "link;unlock;done;missing" } }, ref = { [questID] = "c1.c2" } }
PathmarkDB.explore = { heard = { ["rare:62"] = "1429;4231;6512;2" } }  -- map;x;y;reports (1 or 2)
```

`PathmarkDB.prereq` and `PathmarkDB.explore` are account-wide: what other players reported is true for every character. Own finds and the hint level belong to the character.

A step key is `<module>/<step id>`; step IDs are chosen by the route author and never renumbered (docs/ROUTE-FORMAT.md). Quest state is never saved: it comes from the server each time.

## Rules

**When an element is done**

| Element | Done when |
| --- | --- |
| `accept` | quest in the log or handed in |
| `complete` | quest in the log with `C_QuestLog.IsComplete`, or handed in |
| `turnin` | handed in (`C_QuestLog.IsQuestFlaggedCompleted`, or `QUEST_TURNED_IN` this session) |
| `travel` | the player's map is the target or one of its parent maps |
| `xp` | level reached |
| `collect` | `C_Item.GetItemCount` reaches the count |
| `hs`, `sethome`, `fp` | the event was seen (`HEARTHSTONE_BOUND`, flight path message) for this step or one of the next three |
| `goto`, `note`, `train` | not counted; a step with only these needs the player's check |

A step is **done** when every counted element is done or the player checked it, **skipped** when the player skipped it, when all its quests are skipped, or (travel step) when every step of the zone it leads into is skipped, and **open** otherwise. An element of a skipped quest counts as done.

**Current step.** From the saved anchor the route moves forward over every step that is done, skipped or passed. Passed means: planned more than 5 levels below the character (chosen value; such quests give at most 80 % XP) unless a quest of the step is in the log; a travel step or a step without quests whose next quest step shows server progress; on a first start without saved progress, every step before the last step with server progress, unless a quest of it is in the log. So the route starts at the right step at any level and moves on when the player grinds instead of questing. A step the player went back to is never passed by these rules.

**Skip.** Skipping a step skips the step and every quest it names that is not handed in yet, and with them every quest that needs them: a quest is skipped when one of its prerequisite groups has only skipped quests left (one quest per group is enough, as in the route data). The rule repeats until nothing changes, so a chain of any length goes at once. A quest handed in is never skipped. For the new Forever quests of levels 21 to 30 the sources state no prerequisites yet (Polestar 0 of 112), so the chain is incomplete there until our measurements fill it.

**Back** reopens the nearest earlier step that the player checked, skipped, marked by an event or that the route passed by itself; a skip made there is taken back with all its follow-up quests. Steps the server state has done stay done. **Undo** restores the state before the last check, skip, back or answer.

**Abandoned quest** (owner wish 10). When a quest the route had counted as taken (its accept step lies behind the current step) leaves the log without being handed in, the runtime asks: `QuestAbandoned` fires and `Pending()` returns the quest. Nothing moves until the answer: `ResolveAbandon("reaccept")` goes back to the quest giver, `ResolveAbandon("skip")` skips the quest with its follow-up quests. Taking the quest again in the game also answers the question. Both answers can be undone.

## Interface `ns.Route`

| Function | Returns |
| --- | --- |
| `Route.Current()` | step info of the current step, or nil (no route, route finished, module off) |
| `Route.Upcoming(n)` | list of the next `n` open steps (default 3) |
| `Route.StepState(key)` | `"done"`, `"skipped"`, `"open"` or nil |
| `Route.Check(key?)` | marks a step done (default: current); true if done |
| `Route.Skip(key?)` | skips a step with its quests and their follow-up quests; true if done |
| `Route.Back()` | true if a step was reopened |
| `Route.Undo()` | true if an action was undone |
| `Route.Pending()` | quest ID of an open abandon question, or nil |
| `Route.ResolveAbandon(choice)` | `"reaccept"` or `"skip"`; true if answered |
| `Route.Balance()` | XP balance (below) |
| `Route.SkipPreview(key?)` | quest IDs a skip of the step would take with it (follow-up quests, not the step's own), sorted; changes nothing; nil for an unknown key |
| `Route.AbandonPreview()` | follow-up quests of the quest an open abandon question is about, or nil |
| `Route.LastAction()` | the action the next `Undo` takes back: `{ kind, key, quest }` with kind `check`, `skip`, `back`, `reaccept`, `skipquest`; `{ kind = "unknown" }` for undo entries saved before; nil without one |
| `Route.Module(key)` | compiled module (read only) of a module key or a step key, for the "provisional" symbol and the origin tooltip |
| `Route.Mode()`, `Route.SetMode(mode)` | `"speed"` or `"explorer"`; switching rebuilds the route |
| `Route.RegisterCallback(event, owner, fn)`, `Route.UnregisterCallback(event, owner)` | `fn(owner, ...)`, one per owner and event |
| `Route.LastGain()` | `{ xp, level, at }` of the last XP gain (probe check `xp.kill`) |
| `Route.ChainState(questID)` | `"known"`, `"observed"`, `"none"` or `"incomplete"` (§Prerequisites from player data); nil without a route |
| `Route.DungeonHint()` | list of dungeon hints (§Dungeon hint), `{}` when none |
| `Route.SkipDungeon(instanceID, show?)` | hides a dungeon hint (`show = true` shows it again); the route does not change; true if done |
| `Route.Forecast()` | time forecast (§Time forecast) |
| `Route.Quests()` | set `{ [questID] = true }` of the route's quests without the skipped ones and their follow-up quests (Welle 5b, Blizzard's quest tracker) |
| `Route.Observe(...)`, `Route.ObserveFind(find)`, `Route.Candidates(questID)`, `Route.Wants(questID)` | used by the collector and the exchange, not by the window |
| `Route.Runtime()` | the runtime object, for diagnostics and tests only |

Step info: `{ index, total, key, module, id, lv, ret, kind, label, quests, step, chain }`. `chain` is `"incomplete"` when a quest of the step has prerequisites nobody knows yet (show the status text `L.STATUS_COLLECTING`, "collecting data": skipping may leave a follow-up quest the game will not offer), else nil. `kind` is `"quest"`, `"travel"` or `"other"`; `label` is the module's label (`vorläufig` or `stabil`); `quests` lists the quest IDs; `step` is the compiled step (read only, layout in docs/ROUTE-FORMAT.md). Quest and item names are not part of it: the window reads them from the client in the player's language. Every call builds new info tables: call on the events below, not on every frame (brain chapter 12, no tables per frame).

**Callbacks.** A failing listener is recorded in the error buffer under `route-listener` and stops no other listener; it never turns the `route` module off.

| Event | Arguments after `owner` | When |
| --- | --- | --- |
| `StepChanged` | `current, previous` (step info or nil) | the current step changed |
| `RouteRecalculated` | `reason`: `start`, `skip`, `back`, `undo`, `reaccept`, `missing`, `prereq` | the route was set up again, the skip set changed, or players confirmed prerequisites (`prereq`) |
| `XPBalance` | balance | after a step change, XP or level change, at most once per 0.1 s |
| `QuestAbandoned` | `questID` | an abandon question waits for the answer |

**XP balance** (owner wish 9):

```lua
{
  level = 12, xp = 4200, xpMax = 10100, rested = 0,
  toLevel = 5900,                       -- XP to the next level (client values)
  step = { xp = 450, source = "log" },  -- open turn-ins of the current step; "log" | "data" | "mixed"
  zone = {                              -- nil when no zone change follows
    endIndex = 184, nextMap = 1436, nextLevel = 14,
    routeXP = 6100,                     -- open turn-ins up to the next zone change (no class detours)
    needed = 17300,                     -- XP to the planned level after the zone change
    shortfall = 11200, enough = false,
    kills = 107, killXP = 105,          -- creatures at the character's level, rested kills double
  },
  estimate = true,                      -- show as "ca."
  stopped = nil,                        -- true at the maximum level or with XP turned off
}
```

Quest XP: the client's `GetQuestLogRewardXP` while the quest is in the log, else the route data (full XP from Polestar) with the Classic reduction (full up to quest level + 5, then 80, 60, 40, 20, 10 %). Kill XP: `level * 5 + 45` for a creature at the character's level. A creature below the character gives `(creature level * 5 + 45) * (1 - difference / zero difference)` in Forever, not the Classic `level * 5 + 45` as base (beta measurement level 10 against 5: 40 XP rested, Classic Era 54; closed as "Not A Bug" in forever-bugs #138).

## Assumptions to measure in Forever

| Assumption | Probe check | How |
| --- | --- | --- |
| XP per level as in Classic (1 to 60: 4,084,700) | `xp.curve` | `/pathmark probe run`: client `UnitXPMax` against the table |
| Kill XP as in Classic for creatures at or above the character, the Forever rule (forever-bugs #138) below; Forever has no level scaling (chapter 14 §2) | `xp.kill` | kill a creature solo, keep it targeted, `/pathmark probe check xp.kill` |
| Quest XP: Polestar value with the Classic reduction | `xp.quest` | with a route quest in the log: `/pathmark probe run` |
| Planned levels | none | AP 10 simulation and our measurements |

Until these checks pass in the Forever client, every number of the balance is shown as an estimate.

## Prerequisites from player data

No source states prerequisites for most new Forever quests of levels 21 to 30 (Polestar 0 of 112). The compiled data lists every quest whose prerequisites are not secured as `unsure`; players fill the gaps while they play.

**What the collector observes** (`Collector/Collect.lua`). At every quest accept: the quest turned in directly before at the same giver, at most 120 s earlier (`link`); whether that giver listed its offers before the turn-in without the quest (`unlock`); the quests turned in this session and the known candidates the player has done (`done`); known candidates he has not done (`missing`). When an NPC lists its offers (`GOSSIP_SHOW`, `QUEST_GREETING`), once per quest and session for quests that are `unsure` or have candidates: `done` and `missing`. Each observation carries a token, a hash of the random install ID and the quest: one player counts once per quest, two observations of different quests cannot be linked. Records `accept` (fields 13 to 17) and `offer` go into the export; the observation goes to the route at once and through the exchange (kind `p`, no position) to other players when the quest is `unsure` or has candidates.

**Rule** (same in `Routes/Prereq.lua` and `tools/routekit/prereq.py`, cases in `tools/tests/fixtures/prereq_cases.json`; chosen values): candidate c is a prerequisite (`observed`) when no observer has c in `missing`, at least 2 observers link it, at least 1 saw the unlock and at least 3 have done it. A quest has none (`observed-none`) after at least 5 observers when no candidate done by at least max(3, half of the observers) is left unrefuted and no unrefuted candidate has 2 links. Measured with simulated runs (`tools/tests/test_own_data.py`): co-occurrence alone gave 69 wrong prerequisites, the link without the unlock 2, the full rule none.

**Use in the route.** A confirmed result changes the route at once (`RouteRecalculated` with `prereq`): skipping a confirmed prerequisite skips the follow-up. Observed groups replace the groups of the sources; an observed "none" keeps a prerequisite a source states. `Route.ChainState(q)`: `known` (a source secures it), `observed`, `none` or `incomplete`.

**Measured share for the new quests of levels 21 to 30** (113 quests, both factions): secured 37 before Welle 4, 42 with the ATT prerequisites, 111 to 113 after simulated runs of 12 players per faction (three seeds) without a wrong prerequisite. The simulation plays the prerequisites the sources state as truth; the real share comes with real players.

## Explorer mode

Interface `ns.Explore` (module `explore`, not core). Rules in `Routes/Discover.lua`.

| Function | Returns |
| --- | --- |
| `Explore.Level()`, `Explore.SetLevel(n)` | hint level 0 to 3; default by route mode (speed 3, explorer 0) until the player sets one |
| `Explore.Styles()` | `{ { key = "arrow", mode = "speed", level = 3 }, { key = "hints", mode = "explorer", level = 1 }, { key = "self", mode = "explorer", level = 0 } }`, the three cards of the first start |
| `Explore.Style()`, `Explore.SetStyle(key)` | chosen style or nil (not asked yet); setting one sets route mode and level |
| `Explore.List(uiMapID?)` | visible finds on one map or everywhere, sorted by key |
| `Explore.Ask(key, 2 or 3)` | the player asks for the area or the point of one find he sees; false at level 0 |
| `Explore.RegisterCallback("FindsChanged", owner, fn)`, `Explore.UnregisterCallback(event, owner)` | `fn(owner, key?)` after a new find, a level or style change, a request |

Entry of `List`:

```lua
{
  key = "rare:100", kind = "rare", id = 100,   -- kind: quest, treasure, book, rare, flightpath, place
  map = 1429,                                  -- uiMapID
  source = "data",                             -- "own" | "players" | "data" (catalog, ATT)
  status = "unconfirmed",                      -- "own" | "confirmed" | "unconfirmed"
  show = "riddle",                             -- "point" | "area" | "riddle" | "rumor"
  points = { { 2760, 8840 } },                 -- show = "point": map coordinates, hundredths of a percent
  area = { x = 2825, y = 8766, rx = 288, ry = 432 }, -- show = "area": ellipse that holds the point
  text = "A rare creature roams in the south-west of Elwynn Forest.", -- riddle or rumor; nil without zone name
  part = "sw",                                 -- riddle: part of the zone (n, ne, e, se, s, sw, w, nw, c)
}
```

| Level | Own finds | Catalog | Finds of other players |
| --- | --- | --- | --- |
| 0 | point | hidden | hidden, also on request |
| 1 | point | riddle (type, zone, part of the zone) | rumor (type and zone) |
| 2 | point | area | area |
| 3 | point | point | point |

A request (`Ask`) raises one visible find to area or point. Nothing counts what remains. The area is a circle of 100 yards (map size from `C_Map.GetMapWorldSize`, else 3 % of the map) whose centre is moved by up to half the radius, so it holds the point without showing it. Sentences come only from `L.RIDDLE_<kind>`, `L.WHERE_<part>` and `L.RUMOR_<kind>` filled with the zone name from the client (`C_Map.GetMapInfo`) and the part of the zone from the coordinates; without a zone name there is no text.

Sources: the catalog (`finds`, ATT, unbestätigt); own finds from the collector (quest givers of quests the data does not know, catalog treasures and books when looted, books read, rares, flight masters); finds of other players from the exchange. A second independent player confirms a find; a report on a catalog find confirms it and replaces its position. Looted objects the catalog does not know are no discovery (ore and herbs cannot be told apart yet); no source feeds `place` yet.

## Dungeon hint

`Route.DungeonHint()` returns a list, sorted by the step where the first quest is picked up:

```lua
{
  id = 63, area = 1581,                  -- instance ID; area ID for the name (C_Map.GetAreaInfo)
  min = 10, lo = 15, hi = 24,            -- instance minimum level and the band of the hint
  entrance = { 1436, 1539.7, -11327.3 }, -- uiMapID, world west, north; nil if unknown
  quests = {
    { q = 166, level = 22, xp = 3975, map = 1436, wx = 1045, wy = -10509,
      state = "take",                    -- "take" (giver on the way) | "log" (already in the log)
      step = "a-explorer-core-01-1436/t109", yards = 0 },  -- route step that passes the giver closest
  },
  first = 170,                           -- step index of the first pickup
  gain = 3975, need = 0, balance = -3975, justified = false,
}
```

**Rules.** A dungeon is suggested when the character's level lies in `lo..hi` and at least one of its quests can be taken on the way: the giver is within 1200 yards of a goto point of the route (same continent, `maps` table) from the current step on while the planned level stays in the band, the character has the quest's minimum level, race and class fit, and its prerequisites are handed in or handed in by the route before that step. Measured against the route data: givers on the route lie within 310 yards, capitals next to a route 306 to 1084 yards away (Thunder Bluff, Orgrimmar, Undercity), Stormwind from Westfall 1443 yards and more. Quests in the log count, handed-in ones not. The hint is optional: `Route.SkipDungeon(id)` hides it and changes nothing else.

**Speed mode.** Only when the XP balance justifies it. `need` = XP the route lacks up to the next zone (`Balance().zone.shortfall`); `gain` = quest XP of the listed quests (Forever rule already in the data: the part above a normal quest of the same level is halved; then the Classic reduction by level difference); `balance` = min(gain, need) − max(0, gain − need). Shown when balance > 0. Explorer mode shows every fitting dungeon. Kill XP inside the dungeon (+20 % in Forever) is not counted.

Known data limits: the Deadmines quests at Sentinel Hill need the Defias chain (155) and the Orgrimmar quests of Ragefire Chasm need 5727; no route takes these chains, so the hint names them only after the player did them.

## Time forecast

`Route.Forecast()`:

```lua
{
  state = "ready",        -- "ready" | "collecting" | "done" (route finished)
  seconds = 41200,        -- to the end of the route; only when ready
  level = 30,             -- planned level at the end of the route
  runs = 7,               -- fewest real runs among the modules ahead
  plan = { module = "a-speed-core-01-1436", delta = 240 },  -- delta > 0: ahead of the median
  minRuns = 5,
  nextLevel = { state = "ready", seconds = 1800, perHour = 12000 },  -- own XP rate
}
```

**Route part.** From the median of real module runs (compiled `times`, built by `tools/routekit/observe.py` from `split` records). Every module ahead needs at least 5 runs, else `state = "collecting"` and no numbers: show `L.STATUS_COLLECTING`. The current module counts with the share of its steps still ahead. `plan` compares a clean run of the current module with the median.

**Level part.** Time to the next level from the player's own XP per second of active play (at least 10 minutes, the last 2 hours weigh). Until then `nextLevel.state = "collecting"`.

**Measuring.** Active play: the time between two game events the route module handles, each gap counted up to 5 minutes. A module run is clean when it starts at the module's first step and every step up to its end is done (not skipped, not passed by the route); a clean run goes to the collector as `split` (module, seconds, mode). All thresholds are chosen values.

## Not built here

Arrival detection for steps with only a `goto` (the route data has none) and hearthstone use (no `hs` element in the data); guidance inside dungeons (after 1.0).

## Window binding (Welle 5)

The windows (`Pathmark/UI/`) read the logic only through the adapter `UI/Connect.lua`; a change of an interface above lands there.

| Logic | What the window shows |
| --- | --- |
| `Route.Current`, `Upcoming`, `Balance`, `StepState` | step window: current step, next steps, XP line, "route falls short" note |
| `Route.Check`, `Skip`, `Back`, `Undo`, `LastAction`, `SkipPreview` | check box, right-click menu ("Undo: …"), skip dialog that names every follow-up quest |
| `Route.Pending`, `AbandonPreview`, `ResolveAbandon` | abandoned quest: fail symbol and the two buttons |
| `Route.Module` | clock symbol for provisional sections and its tooltip |
| step info `chain = "incomplete"` | a line "Follow-up quests: collecting data" in the step's origin tooltip |
| `Route.DungeonHint`, `SkipDungeon` | the first hint as an optional step among the next steps, behind the step where its first giver is passed; right-click skips it |
| `Explore.Styles`, `SetStyle`, `Level`, `SetLevel` | first start and settings page "Play style"; style and hint level are kept account-wide on the settings page and handed to `ns.Explore` at login and on every change |
| `Explore.List`, `FindsChanged` | a new rumor (`show = "rumor"`) once in the step window with "Show location"; finds with `show = "point"` on the world map (own finds with the check) |
| `Explore.Ask(key, 3)` | "Show location": waypoint pin and arrow goal for this one find |
| `Route.Forecast`, step info `lv`, `Balance().level` | tooltip of the XP line (Welle 5b): planned level at this step and the character's deviation, then route end, the section against the median and the next level; "collecting data" while a part has too few runs |
| `Route.Quests` | option "Blizzard's quest tracker" (Welle 5b): with "only quests of the route" the tracker follows the route's quests in the log |

Since Welle 5b also: `show = "riddle"` of the player's zone as the line "Hint: …" in the step window (one at a time, the next after a completed step) and `show = "area"` as a circle on the world map with the tooltip "Area".
