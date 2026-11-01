# Route runtime

The logic behind the step window: which step is current, how the addon sees that a step is done, checking, skipping with follow-up quests, going back, undo, abandoned quests and the XP balance. There is no window yet: it waits for the owner's approval of the design (AP 6). This document is the interface the window will use.

Status: built and tested offline (busted, Lua 5.1); not run in a client yet. Last update: 2026-11-01.

| File | What it does |
| --- | --- |
| `Pathmark/Routes/XP.lua` | Classic experience rules: level table, kill XP, quest XP by level difference, XP needed for a level, kills for a shortfall. Pure Lua. |
| `Pathmark/Routes/Runtime.lua` | The rules below. Pure Lua: the client state comes in through a world table, so the tests run the same code. |
| `Pathmark/Routes/Guide.lua` | Module `route`: picks the route, feeds game events in, saves progress, offers `ns.Route`. |

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
  },
}
```

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
| `Route.Mode()`, `Route.SetMode(mode)` | `"speed"` or `"explorer"`; switching rebuilds the route |
| `Route.RegisterCallback(event, owner, fn)`, `Route.UnregisterCallback(event, owner)` | `fn(owner, ...)`, one per owner and event |
| `Route.LastGain()` | `{ xp, level, at }` of the last XP gain (probe check `xp.kill`) |
| `Route.Runtime()` | the runtime object, for diagnostics and tests only |

Step info: `{ index, total, key, module, id, lv, ret, kind, label, quests, step }`. `kind` is `"quest"`, `"travel"` or `"other"`; `label` is the module's label (`vorläufig` or `stabil`); `quests` lists the quest IDs; `step` is the compiled step (read only, layout in docs/ROUTE-FORMAT.md). Quest and item names are not part of it: the window reads them from the client in the player's language. Every call builds new info tables: call on the events below, not on every frame (brain chapter 12, no tables per frame).

**Callbacks.** A failing listener is recorded in the error buffer under `route-listener` and stops no other listener; it never turns the `route` module off.

| Event | Arguments after `owner` | When |
| --- | --- | --- |
| `StepChanged` | `current, previous` (step info or nil) | the current step changed |
| `RouteRecalculated` | `reason`: `start`, `skip`, `back`, `undo`, `reaccept`, `missing` | the route was set up again or the skip set changed |
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

Quest XP: the client's `GetQuestLogRewardXP` while the quest is in the log, else the route data (full XP from Polestar) with the Classic reduction (full up to quest level + 5, then 80, 60, 40, 20, 10 %). Kill XP: Classic, `level * 5 + 45` for a creature at the character's level.

## Assumptions to measure in Forever

| Assumption | Probe check | How |
| --- | --- | --- |
| XP per level as in Classic (1 to 60: 4,084,700) | `xp.curve` | `/pathmark probe run`: client `UnitXPMax` against the table |
| Kill XP as in Classic; Forever has no level scaling (chapter 14 §2) | `xp.kill` | kill a creature solo, keep it targeted, `/pathmark probe check xp.kill` |
| Quest XP: Polestar value with the Classic reduction | `xp.quest` | with a route quest in the log: `/pathmark probe run` |
| Planned levels | none | AP 10 simulation and our measurements |

Until these checks pass in the Forever client, every number of the balance is shown as an estimate.

## Not built here

The step window, its right-click menu and texts (AP 6, after design approval); the dungeon hint (owner wish 11); arrival detection for steps with only a `goto` (the route data has none) and hearthstone use (no `hs` element in the data).
