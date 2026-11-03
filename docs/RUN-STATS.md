# Your run: statistics in the game

The page "Your run" shows the player how the own run goes and where it stands against the class: time per level, XP per hour, where the XP came from, time by activity, quests done and skipped, deaths, the forecast to the end of the route, and median and rank of the player's class from the run times of the exchange ([RUN-TIMES.md](RUN-TIMES.md)). A review card sums up ten levels once at level 10, 20 and 30 (plan Welle 8, 2026-11-02; owner: "sinnvoll integriert und nicht störend"). No badges, no points, nothing in the chat.

Code: `Routes/Stats.lua` (tally, comparison, bands; pure Lua), `Routes/RunStats.lua` (module `stats`: events, saved tables, migration, comparison build), `UI/StatsPage.lua` (module `statspage`: page and review card), `Routes/Guide.lua` (feeds active seconds, level-ups and module runs). Tests: `spec/stats_spec.lua`, `spec/ui_stats_spec.lua`, `spec/stats_perf_spec.lua`, `spec/ui_preview_spec.lua`, `spec/ui_combat_spec.lua`.

## Where it shows

- **Page:** right-click menu of the step window and of the minimap button ("Your run"), `/pathmark stats` (toggles). Never opens by itself; in a fight the command waits for its end. Three tabs: levels, route sections, best times. A row's tooltip has the details.
- **Review card:** at the level-up to 10, 20 and 30, three seconds later (after Blizzard's level-up banner), once per character. It waits while the player fights or is in an instance and comes at the next zone change or loading screen outside. "Show the review at level 10, 20 and 30" on the card and on the settings page Display turns it off; a card due while it is off is dropped. The card is marked as shown when it opens, so it never comes twice. No card when the band has no whole level (the addon came in during its last level).

## What is counted

Per level of a character (`PathmarkCharDB.stats.lv[level]`):

| Value | Source |
| --- | --- |
| Active seconds | the same gaps as the level section of the run vault: game events of the route module, gaps above 300 s (`Forecast.IDLE_CAP`) count as 300. At the level-up the record takes the section's seconds and XP, so the page says what the vault says. |
| Breaks | the part of a gap above 300 s; shown apart, never in the active time |
| XP | gains between two XP updates (`PLAYER_XP_UPDATE`, as the route counts them) |
| XP from quests | the reward `QUEST_TURNED_IN` names (`xpReward`). Forever sends the event late or not at all (brain chapter 06 §3): such a quest counts as done, its XP stays under "other". |
| XP from enemies | one XP gain at most 1 s before or after a `PARTY_KILL` (the player's or a group member's kill; the GUIDs are not read, they can be secret) |
| Time by activity | fighting (`PLAYER_REGEN_DISABLED` to `ENABLED`), moving (`PLAYER_STARTED_MOVING` to `PLAYER_STOPPED_MOVING`), flying (`PLAYER_CONTROL_LOST`, then `UnitOnTaxi`, until `PLAYER_CONTROL_GAINED`), other (the rest: quest givers, looting, standing). A flight beats a fight beats moving. The activities of a gap share its counted seconds in proportion to their time. |
| Quests done | `QUEST_TURNED_IN`, or `QUEST_REMOVED` with the completion flag 1 s later, once per quest |
| Quests skipped | quests the route leaves out (skipped by the player and their follow-ups, `Route.Skipped`), the difference between the start and the end of the level |
| Deaths | `PLAYER_DEAD` |
| Way of play | mode letter and in-order share of the closed level section: follows the route (`s` or `e`, at least 80 % in order), free play (`f`), partly the route (the rest), as `tools/routekit/runs.py` |

Module runs (`PathmarkCharDB.stats.mods`): the "m" sections the route records, the first run per module and version. A level the addon did not see from its start is marked "part" and never compared.

**Events and their evidence** (Forever docs, wow-ui-source branch forever, commit aff0d8c "1.60.1 (70707)", `Blizzard_APIDocumentationGenerated`, read 2026-11-02): `PLAYER_STARTED_MOVING` and `PLAYER_STOPPED_MOVING` (`UnitDocumentation.lua` lines 3946 and 3964, no payload), `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED` (lines 3887 and 3893), `PARTY_KILL` (line 3726, `SecretWhenUnitIdentityRestricted`), `PLAYER_DEAD` (`DeathInfoDocumentation.lua` line 131), `QUEST_TURNED_IN` with `questID`, `xpReward`, `moneyReward` (`QuestLogDocumentation.lua` line 1396), `C_CreatureInfo.GetRaceInfo` and `GetClassInfo` with `raceName` and `className` (`CreatureInfoDocumentation.lua`). All of them are also in Ketho BlizzardInterfaceResources branch forever (commit d1ee569, `Resources/Events.lua`, `Resources/GlobalAPI.lua`). The movement events are new for Pathmark; the others were in use already.

## Comparison with the class

From the run vault (`PathmarkCollectDB.runs`): the sections of other players of the player's class, without the tokens of this installation's characters, grouped by kind (level, module, band), section, module version and way of play. A row shows median and rank only with at least 10 runs (`Stats.MIN_RUNS`) in its group; below that it says "collecting" and the tooltip names how many runs there are. Rank: the share of runs slower than the player's, ties count half. Bands for the review card are sums of whole levels per token (all ten levels present).

The comparison is built only while the page or the card waits for it, in slices of at most 250 vault texts and 1 ms per frame, never in a fight (the build pauses and goes on after it). A built comparison counts as up to date for 30 s; after that a window builds it again when the vault changed.

## Best times

`PathmarkDB.stats.best[top]` per band of ten levels (top 10, 20, ... 60): seconds, race, class, way of play, day and the run token of the character. A band counts when every level of it was seen whole. An equal time keeps the older best. The page names the race and class with `C_CreatureInfo` and marks the own character.

## Saved tables and migration

```lua
PathmarkCharDB.stats = {
  schema = 1,
  lv = { [level] = { s, p, x, q, k, c, m, f, n, b, d, full, mo, o, day } }, -- b0 while the level runs
  mods = { { num, key, v, s, o, mo, l }, ... },
  recap = { [10] = true, pending = 20 },
}
PathmarkDB.stats = { schema = 1, best = { [10] = { s, r, c, g, d, t } } }
```

Version 1 is made from what the run vault already holds: the own level and module sections of the character (records with time, XP, way of play only; the page says "Only time and XP are known for this level") and the whole bands of every own character for the best times. The migration runs on a copy (`Collector/Migrate.lua`); a newer schema leaves the data alone and the module shows "error". The live tables are written back at logout into whatever the globals hold then (brain chapter 15 §7).

## Cost

Measured offline (Lua 5.1 on the development machine, `spec/stats_perf_spec.lua`, not in the game; the binding values come from `C_AddOnProfiler`, gate T16):

| Case | Measured |
| --- | --- |
| Page closed | nothing runs per frame (the build frame is hidden); one event of the tally 0.3 µs |
| Page open, full vault of 5000 sections of the class | window and first render 0.9 ms, comparison 10 to 11 ms in 21 frames (longest frame 1.2 ms), a tab 0.4 ms; over 10 s open 0.019 ms per frame on average, afterwards 0 |
| Refresh of the open page after a change of the tally | 0.5 ms, at most every 0.5 s |
| Review card, full vault | comparison 10 to 13 ms in 21 frames (longest 0.9 ms); 0.02 ms per frame over 10 s |
| Memory | comparison of 5000 sections +104 KB; saved tally of a level-30 character with 60 module runs about 8 KB of SavedVariables text |

On the shared CI runner the same page took about twice as long on average (0.042 ms per frame) and its longest frame 4 ms. The test therefore takes the fastest of three runs for the average and holds the slice size (at most 250 texts per frame), not a wall-clock peak.

## Chosen values

| Value | Where | Setting |
| --- | --- | --- |
| Runs before median and rank | `Stats.MIN_RUNS` | 10 (the time forecast takes a median from 5; a rank needs more) |
| Following the route | `Stats.FOLLOW_MIN` | 80 % in order, as `tools/routekit/runs.py` |
| Kill and its XP | `Stats.KILL_WINDOW` | 1 s |
| Review card | `Stats.RECAP` | levels 10, 20, 30; 60 follows with the routes to 60 |
| Delay of the card | `StatsPage.RECAP_DELAY` | 3 s |
| Comparison slice | `RunStats.SLICE`, `RunStats.SLICE_MS` | 250 texts, 1 ms per frame |
| Comparison fresh for | `RunStats.REFRESH` | 30 s |
| Refresh of the open page | `StatsPage.REFRESH_DELAY` | 0.5 s |

## Developer preview

`/pathmark preview stats` (page with comparison data), `stats0` (without: "collecting"), `recap10` (card with comparison and a new best time of the account), `recap30` (card while the class has too few runs). The numbers are demo data of the design; the preview does not use up the real card.
