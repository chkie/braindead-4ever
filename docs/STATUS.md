# Feature status

Every feature has one status: **planned**, **built** (code and offline tests pass), **verified in game** (checked in the WoW: Forever client) or **blocked**. German project documents use geplant, gebaut, im Spiel geprüft, blockiert.

Only a person sets **verified in game**, after playing it, never a test or the probe. The probe only measures (`OK`, `MISSING`, `ERROR`, `SECRET`, `FAILED`, `ARGERROR`).

Last update: 2026-11-03

## API probe (AP 3)

The developer probe checks in the client whether every function, event, value, atlas and CVar a planned feature needs exists and what it returns, before anything is built on it. It ships only in the developer build: the TOC lists it inside `#@do-not-package@` and `.pkgmeta` ignores `Braindead4Ever/Probe`.

| Command | What it does |
| --- | --- |
| `/bd4 probe run [label]` | runs every check that needs no context; label defaults to `free` or `combat` |
| `/bd4 probe check <id>` | runs one check, also the manual ones (`comm.burst`, `export.window`, `perf.memory`, `qitem.button`, `xp.kill`) |
| `/bd4 probe status <id> planned\|built\|verified\|blocked` | sets the plan status after a game test |
| `/bd4 probe report` | copyable report, one tab-separated line per check, plus blocked actions |

Context checks run by themselves when their window opens: quest dialog (`QUEST_DETAIL`), loot (`LOOT_OPENED`), book (`ITEM_TEXT_BEGIN`, `ITEM_TEXT_READY`), flight map (`TAXIMAP_OPENED`), gossip (`GOSSIP_SHOW`), greeting (`QUEST_GREETING`), target change and combat start. The checks of the modules' own requirements are added automatically as `mod.<module>.<name>`.

**Order of use:** Retail 12.1.5 test bed before 2026-11-04 (values are only a preview: Forever has other map data and events), then on 2026-11-05 in the Forever client: `/bd4 probe run` outside combat, again in the first fight (`run combat`), open a quest giver, a chest, a book, a flight master, click the quest item button, then copy the report.

| Feature | Status | Note |
| --- | --- | --- |
| Probe engine: functions, values, events with first payload, atlases, CVars, own tests | built | `Probe/Probe.lua`; not run in a client yet |
| Check list for every planned feature (below) | built | `Probe/Checks.lua`; `spec/status_spec.lua` keeps it in sync with this file |
| Checks derived from module requirements (`mod.collector.*`, `mod.exchange.*`, `mod.report.*`) | built | |
| Blocked and forbidden actions recorded with addon and function | built | `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN` |
| Run in the Retail 12.1.5 test bed | planned | owner, before 2026-11-04 |
| Run in the Forever client | planned | owner, 2026-11-05, launch runbook minute 10 to 25 |

## Core

| Feature | Status | Note |
| --- | --- | --- |
| TOC for Forever (`Braindead4Ever_Camelot.toc`, interface 16001) | built | 16001 is the beta interface; check the live client on 2026-11-05 with `/dump select(4, GetBuildInfo())` |
| TOC for the Retail 12.1.5 test bed (`Braindead4Ever.toc`, 120105 and 16001) | built | |
| Error buffer: first occurrence per session goes to the error handler, repeats are counted | built | `Core/Guard.lua` |
| Module turns off after 5 errors within 60 s | built | thresholds are chosen values, not measured |
| Modules declare required API functions and events, checked at login | built | `Core/Modules.lua` |
| Mandatory modules: no flag and no hand-set safe mode turns them off | built | collector and exchange (owner decision 2026-11-01); the automatic safe mode and the error buffer still apply |
| Start guard: safe mode after two unclean starts, lifted by a new version | built | does not help after a client crash (SavedVariables are written on logout and `/reload` only) |
| Messages nobody asked for (automatic safe mode, a module turned off, a newer version) go into the status line of the step window; one chat line per session only when the step window itself is down (concept §1.5, rule R2, requirement A54) | built | Welle 9; `spec/notice_spec.lua`, counter-check: with the chat line always on the test fails |
| Credits from one list: `CREDITS.md` (packaged beside the licences) and the Credits page name the same data sources with their licences, the licence line without warranty, the library line and the trademark line (release gate T13) | built | Welle 9; `spec/credits_spec.lua` compares `CREDITS.md` with `NOTICE` and the Credits page |
| Slash command `/bd4` (status, safe, flag, errors, quiet, export, report, probe) | built | |
| Copy window for export, report and probe | built | `Core/CopyWindow.lua`; the player copies with Ctrl+C (CopyToClipboard is restricted) |
| Texts in English and German | built | wording not approved yet |
| Only characters every client font draws: separator "•" instead of "·" (missing in the Cyrillic font), English texts (fallback of every language) checked against the five client fonts, German ones against the Latin font (requirement A61, release gate T19) | built | `spec/locale_glyphs_spec.lua`; glyph sets read from the client fonts (wago.tools, 2026-11-01); screenshot in a ruRU client pending |
| `Category` in the TOC (`Quests`) | built | value not checked against the in-game category list |

## Data collector (AP 4)

Records go into a ring buffer of text chunks (`Collector/Store.lua`): one line per record, one string per chunk (16 KiB or 5 minutes), at most 2 MiB of own records and 1 MiB of finds received from other players. The open chunk is written every 60 s out of combat and at logout. No character, realm, guild or chat names, no player GUIDs, time only as tenths of a second inside a chunk and the day number.

| Feature | Status | Note |
| --- | --- | --- |
| Ring buffer with fixed upper limit, dropped chunks counted | built | offline: 120,000 records stay under 2 MiB with fewer than 1,000 SavedVariables constants (`spec/store_spec.lua`) |
| SavedVariables replaced or lost at runtime: live state written back at logout | built | Forever beta trap (Polestar, Mapzeroth); cold start test `sv.coldstart` |
| Versioned migration on a copy, backup of the old data, newer data left untouched | built | `Collector/Migrate.lua`, schema 1 |
| Random install ID (12) and character ID (10) | built | never derived from name, realm or account |
| Session header: character ID, race, class, faction, level, locale, build, version, Forever preset, hardcore, legacy ranks | built | legacy ranks of tree 1188 only when the client offers `C_Traits` and `Constants.LegacyConsts` |
| Quest accept with giver, dialog position, NPC name, level, quest XP | built | context from `QUEST_DETAIL`, 600 s |
| Quest turn-in with XP and money; turn-in without `QUEST_TURNED_IN`; abandon | built | completion flag 1 s after `QUEST_REMOVED` |
| Objective progress, also for quests under collapsed headers and criteria quests | built | |
| XP with rested XP, level-ups, kills by the player | built | XP before `QUEST_TURNED_IN` is assigned by the pipeline, not the addon |
| Looted objects with item IDs (chests, ore, herbs, book objects) | built | `GetLootSourceInfo` is undocumented: optional |
| Readable objects (books) | built | GUID at `ITEM_TEXT_BEGIN` unconfirmed in Forever |
| Rare enemies from name plates, target and mouseover | built | |
| Vignettes | built | whether Forever zones have vignettes is unconfirmed |
| Flight masters with known nodes, new flight path message, taxi start and landing | built | |
| Flights (Welle 10): direct legs from the flight master's map (`GetNumRoutes`, `TaxiGetNodeSlot`; record `taxilegs`, once per flight point and session), the chosen flight with its flight points (post-hook on `TakeTaxiNode`; record `flight`), the landing with destination and seconds since the choice (`land`) | built | the legs and the seconds of flights without a stop also go into the flight vault and the exchange since Welle 11 (below); the legs are read again only when the known flight points changed: offline (Lua 5.1, 40 points with up to 4 legs) 0.15 ms more on the first open of a flight master in a session, nothing on later opens; the three functions are in the Forever global dump (Ketho, branch forever, d1ee569) and checked as `mod.collector.*`; `observe` turns the records into own flight facts |
| NPC names in the client language, zone changes, position samples, deaths, group size, hearthstone bind | built | |
| Export as `PM1` text (JSON, Deflate, Base64, length and Adler-32), only data not exported yet, acknowledged after Ctrl+C | built | `/bd4 export [all]`; Zlib only after `enc.zlib` passed in the client |
| Website decoder for the export (`decoder/decode.mjs`) | built | round trip Lua to Node decoder in `spec/export_spec.lua`; browser paste test with the `enc.deflate` text |
| Report a problem: version, build, module states, step, position, quest log, error buffer, marked player note | built | `/bd4 report [note]` and the step window's right-click menu; missing atlases are listed too |
| Two hours of simulated play without a Lua error, data anonymous | built | `spec/collect_spec.lua`; the acceptance "Forever start" needs two hours in the Forever client |

## In-game exchange (data contribution, M11)

Every installation shares what it discovers with other players who run the addon. There is no option to turn it off (owner decision 2026-11-01). Messages carry IDs and numbers only (`Collector/Proto.lua`), never names or localized text. Received finds are stored as unconfirmed (`rx`), a second independent player confirms them (`rx2`). Sender names live in memory for the session only.

| Feature | Status | Note |
| --- | --- | --- |
| Protocol: quest start, turn-in, object, book, rare, flight master, vignette, addon version (`a`, Welle 9), flight leg (`h`, Welle 11); newer versions and unknown kinds skipped | built | |
| Targets: group at once; guild and hidden channel after 30 to 90 s | built | the delay keeps a message from telling where a player is right now |
| Throttling: own bucket of 10, one per second, 2 s gap on the channel, queue of 30 | built | server values can change; `comm.burst` measures them |
| No sending during chat lockdown, from trial or veteran accounts | built | |
| Hidden custom channel with fallback names when the password is refused or the channel is taken over | built | pattern after ForeverItemFinder; channel reach in Forever unconfirmed |
| Receiving: validation, dedup, confirmation by a second player, mute after 5 broken messages or 40 finds in 5 minutes | built | |
| Run times: a section per level and per route module played from its first step (`s`), own and received ones in the run vault | built | [docs/RUN-TIMES.md](RUN-TIMES.md); token per character, no names |
| Run vault: 5000 sections, dedup per token and section, conflicting values drop both, plausibility band from the speedrun record pace | built | all limits are chosen values |
| Relaying run times: each section once per session, hidden channel only, one message per 10 s at most, own messages first | built | in-game traffic not measured yet |
| Channel budget: each client sends its share of 0.25 messages per second on the whole channel (runs and finds), estimated players as an upper bound, hard stop at 30 in 60 s; nothing on the channel in a fight or an instance | built | [docs/RUN-TIMES.md](RUN-TIMES.md); simulation with 100 to 20,000 clients in `spec/channel_budget_spec.lua`: at most 0.19 received per second on average, 30 in 60 s (limits 0.5 and 60) |
| Receiving: the event only queues the raw text (inbox of 100); reading 10 messages per second outside fights, instances and below 20 frames per second | built | 0.5 µs per message on the event, 13 µs reading (offline) |
| Run times in the export (`runs`), run table in the decoder, medians in `tools/routekit/runs.py` | built | |
| Version notice (requirement A47, concept §1.5): the own version once per group, once per session to guild and channel (on the channel with a finds credit of the channel budget, no extra traffic); the notice only when two different players report a newer version, once per session, in the status line until the next completed step, never read in a fight; pre-releases only for players who run one; untagged builds announce nothing | built | Welle 9; two players is a chosen value after DBM and BigWigs (brain chapter 17 §5); `spec/version_spec.lua`; needs players with a newer release in the game (release gate T8) |
| Flight legs (Welle 11): legs of the flight master's map and the seconds of flights without a stop as message `h` (flight point IDs and seconds only), flight vault with checks against the facts (`Routes/Data_Flights.lua`, model band 0.3 to 3) and saturation (3 sources, 5 measured flights); own flights offered like a find, relays on the channel only with a credit of the find pool; received legs in the export (`flights`), the decoder (`--flights`) and `observe` | built | [docs/ROUTE-FORMAT.md](ROUTE-FORMAT.md) §Flights in the exchange; simulation with 1,000 clients in `spec/flights_spec.lua`: 0.177 received per second on average (limit 0.5), 99 % of the legs other players saw reached an exporter; not used for the route in the addon yet; in-game traffic not measured yet |
| Two clients exchange a test message (release gate T8) | planned | needs a second player in the game |
| Catch-up of finds announced while offline | planned | AP 12 |

## Planned features and their probe checks

Stages from the project plan: MVP (first public release) and 1.0. Status refers to the feature, the probe checks to what the client must offer for it.

| Feature | Stage | Status | Probe checks |
| --- | --- | --- | --- |
| Client and restrictions: build, project ID, secret values, restriction state, locales, game rules, script budget, SavedVariables after a cold start | all | built (probe) | `ver.build`, `ver.project`, `ver.camelot`, `ver.secretfn`, `ver.secrets`, `ver.restrict`, `ver.locales`, `ver.preset`, `ver.hardcore`, `ver.selffound`, `ver.rulesevent`, `ver.throttle`, `sv.coldstart` |
| M1 Step display: current step and the next three, progress detected automatically, skip and back | MVP | built (logic and window, offline; Retail screenshots pending) | `quest.count`, `quest.info`, `quest.objectives`, `quest.flagged`, `quest.ready`, `quest.max`, `quest.trivial`, `quest.elite`, `quest.timers`, `quest.completed`, `quest.autocomplete`, `quest.progressev`, `quest.finished` |
| M2 Navigation: arrow, map and minimap markers, TomTom | MVP | built (arrow, map and minimap pins, TomTom hand-over with a stand-in of TomTom v4.3.13, offline; with a real TomTom: release gate T20) | `nav.map`, `nav.pos`, `nav.world`, `nav.facing`, `nav.worldpos`, `nav.canwaypoint`, `nav.setwaypoint`, `nav.mappoint`, `nav.supertrack`, `nav.nextwaypoint`, `nav.questsonmap`, `nav.maprestrict`, `nav.tomtom`, `mod.tomtom.*`, `nav.cvar`, `nav.range`, `nav.reached`, `nav.supertrackev`, `nav.waypointev`, `nav.moving` |
| M3 Matching route by faction, race and class, entry at any level | MVP | built (all 56 combinations in both modes, entry at any level, offline; see "Route runtime") | `route.race`, `route.class`, `route.faction`, `route.level`, `route.maxlevel`, `route.xpoff` |
| M4 Quest and item names from the client, NPC names from the collectors | MVP | planned | `name.quest`, `name.loadquest`, `name.questload`, `name.item`, `name.itemload`, `name.map`, `name.npc`, `name.npctooltip`, `name.creatureid` |
| M5 Hints on the way: trainer, hearthstone, flight master, supplies, sleeping bag | MVP | planned | `hint.bind`, `hint.binder`, `hint.trainer`, `hint.junk` |
| M6 Report a problem with one click | MVP | built | `mod.report.*` (command `/bd4 report` and the right-click menu) |
| M7 Discoveries recorded by the collector | MVP | built | `find.giverguid`, `find.giverquest`, `find.rewardxp`, `find.questxp`, `find.lootsource`, `find.lootcount`, `find.fishing`, `find.lootnpc`, `find.booknpc`, `find.booktitle`, `find.taxiid`, `find.taxinodes`, `find.taxiworld`, `find.flightstate`, `find.newtaxi`, `find.ontaxi`, `find.rareclass`, `find.rarecombat`, `find.targetguid`, `find.targetname`, `find.creatureid`, `find.vignettes`, `find.vignetteev`, `find.legacyconst`, `find.legacy1187`, `find.legacy1188`, `find.legacy1189`, `find.combatlog`, `mod.collector.*` |
| M8 Quest item button, if the probe reports the call as allowed | MVP if the probe is green | planned | `qitem.info`, `qitem.use`, `qitem.cvar`, `qitem.button` |
| M9 Routes 1 to 30 for all 56 combinations as building blocks | MVP | built | no client API; computed routes, see "Routes and route data" below |
| M10 Status per value (unconfirmed, confirmed) and per section (provisional) | MVP | built | in the route data (AP 5); shown in the step window: clock symbol per section, origin tooltip per step |
| M11 Data contribution through addon messages, export as extra | MVP | built | `comm.prefix`, `comm.lockdown`, `comm.outgoing`, `comm.trial`, `comm.veteran`, `comm.join`, `comm.filter`, `comm.channel`, `comm.nameformat`, `comm.stats`, `comm.burst`, `comm.restrictev`, `comm.noticeev`, `enc.json`, `enc.deflate`, `enc.zlib`, `enc.base64space`, `export.window`, `mod.exchange.*` |
| M12 Interface: setup dialog, settings, one look (Modern; Classic dropped, LK-1101) | MVP | built (setup, settings, one look Modern per LK-1101; offline) | `ui.settings`, `ui.opensettings`, `ui.editmode`, `ui.helptip`, `ui.compartment`, `atlas.header`, `atlas.nub`, `atlas.check`, `atlas.glow`, `atlas.collapse`, `atlas.parchment`, `atlas.arrow`, `atlas.pin`, `atlas.minipin`, `atlas.questnormal`, `atlas.questturnin`, `atlas.barbg`, `atlas.barfill`, `atlas.indicator`, `atlas.area`, `atlas.areafill`, `ui.resize`, `ui.scrollbox`, `ui.tracker`, `font.header`, `font.line`, `font.small`, `font.med3`, `font.highlight`, `font.outline`, `font.normaloutline`, `ui.popupshown`, `ui.helptiphide`, `ui.settingspanel`, `color.normal`, `color.highlight`, `color.tracker`, `color.dimred`, `sound.complete`, `sound.option`, `sound.select` |
| M13 Accessibility: scaling, contrast, shape and color, key bindings, gamepad does not break | MVP | built (scaling, text size, contrast, colorblind, key bindings, window places per UI type for the gamepad; offline) | `mod.bindings.*`, `ui.textsize`, `ui.gamepad`, `cvar.contrast`, `cvar.colorblind`, `cvar.fontscale`, `cvar.instant`, `cvar.gamepad` |
| M14 Safety for the start without a test: error buffer, runtime probe, safe mode, start guard, version notice | MVP | built (version notice since Welle 9, offline) | `safe.eventvalid`, `safe.errorhandler`, `safe.debugstack`, `safe.blocked`, `safe.forbidden`, `safe.scripterrors` |
| XP balance (owner wish 9): XP to the next level, XP of the step, route to the next zone against the need, kills as an estimate | MVP | built (logic and XP line, offline) | `xp.curve`, `xp.kill`, `xp.quest` |
| Performance budget: 10 MB, under 0.1 ms per frame | MVP | built (offline measurement; client measurement pending) | `perf.profiler`, `perf.average`, `perf.memory` |
| Game modes Speed, Explorer, Hardcore-safe | 1.0 | built (hardcore-safe since Welle 9: on Hardcore realms, always or never; warns for quests more than 2 levels above the character, a chosen value, and for quests the client marks elite; no dungeon hint; offline) | `ver.hardcore`, `quest.elite` |
| Hint levels | 1.0 | built (logic; window with Welle 5) | no client API |
| Time forecast | 1.0 | built (logic; shown in the XP line tooltip since Welle 5b) | `time.xp`, `time.xpmax`, `time.rested`, `time.played` |
| Optional automation (accept, turn in, reward) | 1.0 | planned | `auto.accept`, `auto.complete`, `auto.reward`, `auto.acknowledge`, `auto.autoaccept`, `auto.gossip`, `auto.gossipselect`, `auto.greeting` |
| Group and duo | 1.0 | planned | `group.ingroup`, `group.members`, M11 checks |
| Personal review: page "Your run" and review card at level 10, 20 and 30 in the game (Welle 8); "your way to 60" on the website | 1.0 | built in the game (offline; module `stats`, module `statspage`); website planned | `mod.stats.*`, `mod.statspage.*`; website: export (M11) and AP 9 |
| Later: route studio, dungeon inserts, profession leveling, controller | after 1.0 | planned | checked one by one when due |

## Tooling

| Feature | Status | Note |
| --- | --- | --- |
| Offline tests (busted, Lua 5.1.5) with WoW API stand-ins | built | |
| Export round trip against the website decoder (Node 22 or newer) | built | runs inside busted; CI uses the runner's Node |
| luacheck, StyLua, LuaLS type check, gitleaks, actionlint | built | |
| CI on GitHub with required checks | built | branch protection on `main` |
| Release by tag (BigWigs packager to CurseForge, Wago, GitHub) | planned | needs the CurseForge and Wago projects and their tokens |
| Hotfix readiness (release gate T30): release notes by hand in `CHANGELOG.md` (English and German, known issues, `manual-changelog` in `.pkgmeta`), CI on `hotfix/**` branches, hotfix steps in `CONTRIBUTING.md`, Discord notice in `release.yml` and a test post by hand (workflow "Discord test") | built | Welle 9; `spec/release_spec.lua`; the branch `hotfix/launch` comes from the release tag; the webhook needs the Discord server (comes with the release) |
| Package holds only the addon files and the licences (`.pkgmeta` leaves out `tools`, `data`, `decoder`, `spec`, `docs`, `scripts`, `types`, the probe) | built | `spec/pkgmeta_spec.lua` applies the packager's selection to the tracked files; a real packager run comes with the first alpha tag |

## Routes and route data

| Feature | Status | Note |
| --- | --- | --- |
| Route format with sources and status per value (`docs/ROUTE-FORMAT.md`) | built | format version 1 |
| Importers for Polestar forever-db, EG Link, All The Things (decision FD-1101) | built | sources cloned outside the repository; versions in `data/sources/*/SOURCE.json` |
| Merged facts with roots and prerequisite state (`data/facts/`) | built | every value `unbestätigt` |
| Linter: provenance, allowed sources, block list, items before turn-in, prerequisite order, travel and zone returns, filters for all 56 combinations, Speed rule, labels | built | ten prepared errors found, clean fixture passes (`tools/tests`) |
| Compiler to Lua tables (`Braindead4Ever/Routes/Data_*.lua`), composer `ns.Routes` | built | CI recompiles and compares |
| Building blocks 1–30: seven start areas (Zephras per faction), core route per faction, class quests inline and as inserts, Speed and Explorer | built | computed routes, not played; label `vorläufig` |
| Route data loaded only for the played faction | built | function per faction; `ns.Routes.Release()` drops the other faction's builder; measured offline (Lua 5.1): 1.56 MB for the Alliance data after release |
| Example route Elwynn Forest (human, levels 1–10) runs through | built | `spec/routes_spec.lua` |
| Start zones per race in the Forever client | planned | EG Link measured 20 of 56 combinations in the beta; confirm on 2026-11-05 |
| Route measurement: all 56 combinations in both modes priced in Modellstunden (model hours) up to level 30 | built | results in `docs/ROUTE-METRICS.md`; the measuring tools are kept outside this repository and are not needed to build the addon or the route data |
| Planned levels from measured XP | planned | levels are planning values until then |
| Quest facts in the compiled data: quest level, full XP (Polestar), prerequisite groups | built | `quests` table, docs/ROUTE-FORMAT.md §Compiled form |
| Facts on class trainers, innkeepers and flight masters in the route zones and on the flight network (flight points, flown legs, flight seconds measured or as a model value), each value with sources and status `unbestätigt` (Welle 10) | built | docs/ROUTE-FORMAT.md §Service NPCs and flights; merge of 2026-11-03: 224 trainers, 40 innkeepers, 35 flight masters, 66 flight points, 99 legs (25 with measured seconds); not in the compiled data yet, the routes take them up later; the linter checks them and accepts a trainer, innkeeper or flight master as the position of a `train`, `sethome` or `fp` step |

## Route runtime (step logic, owner wishes 9 and 10)

The logic behind the step window. Interface and rules: `docs/ROUTE-RUNTIME.md`. Module `route` (core); its requirements are checked as `mod.route.*`.

| Feature | Status | Note |
| --- | --- | --- |
| Route per faction, race ID, class ID and mode at login; a race without a start module is reported, not an error | built | all 56 combinations in both modes offline (`spec/route_guide_spec.lua`) |
| Progress by step key, survives `/reload`; written back at logout if the client replaced the SavedVariables table | built | counter-checks: without reading or writing back the progress the tests fail |
| Detection: quest accepted, objectives done, handed in, zone reached, level reached | built | from simulated events through the whole Elwynn start module; abandon and turn-in told apart by the completion flag 1 s after `QUEST_REMOVED`, also without `QUEST_TURNED_IN` |
| Quests done before the login skipped; entry at any level (steps planned more than 5 levels below are passed) | built | the margin of 5 levels is a chosen value; entry at level 12 and 25 per faction tested |
| Entry anchor after Polestar #86 (Welle 7): furthest step with a turn-in or objective progress, a quest only in the log does not count, back to the start when less than half of the quests up to it are done or in the log; list "N quests skipped earlier" in the XP tooltip | built | the half is a chosen value; entry at levels 1, 8, 15 and 24 with mixed progress tested; counter-check: with "quest in the log counts" the breadcrumb test fails |
| Over the plan (Welle 7, owner guideline 7): from 3 levels above the plan one question per block, "Adjust" leaves out quests under 80 % XP (R01) and keeps chains to quests that stay | built | 3 levels is a chosen value; tests with 3 and 6 levels of grinding and a dungeon in between |
| Switch points (Welle 7, stage 2): at a travel step into a new zone, 3 levels or more off the plan, the route offers a later block (jump) or an alternative module; never in the middle of a block, never without asking; the level rule no longer passes a zone change during play | built | alternative modules: interface ready (`alts` in docs/ROUTE-FORMAT.md, route built again with the choice, kept over `/reload`); the modules themselves come with the route builder (Welle 6b) |
| Reorder in the block (Welle 7, stage 1): after a skip, an abandoned quest skipped, "Adjust" or an entry in the middle of a block, nearest neighbour with precedence and 2-opt with the quest log limit, from the player's position; kept only when at least 5 % shorter; saved over `/reload`, undo takes it back | built | coroutine with 2 ms per frame, never in a fight; offline 1.7 ms at 40 and 6.7 ms at 80 points, 0.0003 ms per frame on average at 10 reorders per hour; counter-check: without the combat guard the fight test fails; 5 %, 80 points and the log limit 20 are chosen values |
| Check, skip with follow-up quests (prerequisite groups, any chain length), back, undo (20 actions) | built | chain over three quests tested with made-up and with real data; where no source secures the prerequisites (`unsure`), the step carries `chain = "incomplete"` until players confirm them (Welle 4 section) |
| Abandoned quest: question with two ways (take it again, skip with follow-up quests); nothing moves before the answer | built | owner wish 10 |
| XP balance (to the next level, step, route to the next zone, kills) | built | Classic rules with the Forever kill rule for creatures below the character (forever-bugs #138) in `Routes/XP.lua`, the same in `tools/routekit/xp.py`; estimates until `xp.curve`, `xp.kill` and `xp.quest` pass in the Forever client |
| Random test: 7,500 random actions (accept, abandon, play, check, skip, back, undo, answer, level, reload, and since Welle 7 moving, fights and the reorder job), route valid after each | built | `spec/route_random_spec.lua`, seeded; 4 to 8 reorders applied per seed; it found a step reopened by "back" behind a step that needs it, fixed before the merge |
| Step window, right-click menu ("undo" there), texts | built | Welle 5, see "Interface" below |
| Dungeon hint (owner wish 11) | built (logic and window) | see the Welle 4 section and "Interface" below |
| Detection in the client (Retail test bed, then Forever) | planned | release gate T2 |

## Explorer mode, dungeon hint, prerequisites from player data, time forecast (Welle 4)

The step window shows it since Welle 5 (section "Interface" below). Interface and rules: `docs/ROUTE-RUNTIME.md` §Explorer mode, §Dungeon hint, §Prerequisites from player data, §Time forecast. Module `explore` (not core); its requirements are checked as `mod.explore.*`.

| Feature | Status | Note |
| --- | --- | --- |
| Discovery types quest, treasure, book, rare, flight path, place | built | catalog from ATT (`finds`, unbestätigt); quests count when the data does not know them; looted objects only when the catalog names them as treasure or book; no source feeds `place` yet |
| Hint levels 0 to 3 per character; own finds against finds of other players; the point only on request | built | level 0 shows nothing foreign, also not on request (counter-check in `spec/route_explore_spec.lua`); radius of the area hint (100 yards) is a chosen value |
| Confirmation by a second independent player; a report replaces the catalog position | built | in-game exchange (`rx2`); within one session, sender names are never saved |
| Play styles of the first start: follow the arrow, with hints, discover myself | built | route mode and hint level; the level stays a slider of its own |
| Riddle and rumor sentences from templates (English, German) | built | only type, zone name from the client and part of the zone; wording not approved yet |
| Dungeon hint: level band, givers on the way (1200 yards, measured against the route data), prerequisites, optional and skippable | built | dungeon quests from ATT and Polestar (FD-1101); the hint never changes the route |
| Dungeon hint in speed mode only with a positive XP balance (Forever: dungeon quests −50 % extra XP) | built | kill XP inside the dungeon (+20 % in Forever) is not counted, the creatures per run are not measured; counter-check in `spec/route_dungeon_spec.lua` |
| Prerequisites from player data: the collector records link, unlock, recent turn-ins and checked candidates at each accept and offer list; observations go through the exchange (`p`) | built | rule shared with `tools/routekit/prereq.py` (`tools/tests/fixtures/prereq_cases.json`); thresholds 2 links, 3 observers, 5 for "none" are chosen values |
| The route uses a confirmed prerequisite at once (RouteRecalculated `prereq`) and marks the chain incomplete until then | built | observations account-wide in `BraindeadForeverDB.prereq`; simulated runs with three players in `spec/route_prereq_spec.lua` |
| ATT prerequisites for the new quests 21 to 30 | built | secured 37 of 113 before, 42 of 113 with ATT; simulated player runs (12 players) secure 111 to 113 of 113 without a wrong prerequisite (`tools/tests/test_own_data.py`) |
| Time forecast: route time from the median of real module runs (at least 5), comparison with the plan, time to the next level from the own XP rate (at least 10 minutes of play) | built | state `collecting` until then, shown as "collecting data"; no module times measured yet (`times` is empty) |
| Module runs measured as active play (gaps over 5 minutes count as 5) and recorded as `split` for the pipeline | built | thresholds are chosen values; `observe.py` builds `times` from the exports |

## Interface (Welle 5, design v2)

The windows of the approved design v2 (owner approval 2026-11-01; one look "Modern", decision LK-1101; arrow colors decision PF-1101). Fonts are copies of Blizzard's font objects (Friz Quadrata), graphics are Blizzard atlases checked with `C_Texture.GetAtlasInfo`, settings use Blizzard's settings panel. Every text exists in English and German. The windows read the logic only through `UI/Connect.lua`. Offline tests: one per view and state of the design (`spec/ui_*_spec.lua`). Design stage 2, the screenshots in the Retail test bed, follows `docs/TESTING-RETAIL.md`.

| Feature | Status | Note |
| --- | --- | --- |
| Step window (module `window`, `mod.window.*`): current step with counter, next steps (three by default, two lines each), XP line, check box, header with zone and step, clock symbol for provisional sections | built | 300 units wide, one background for header and content, fonts 15/13/12 (owner reading points 1 and 2); Welle 5d after the first Retail screenshots: background 70 % by default (35 % migrates, a chosen value stays) and next steps at 0.7, so every text of the window holds 4.5:1 on white ground; header band reaches the window edges; the window holds its top edge after a drag and grows downwards only; distance with its unit, detail line without the header's zone |
| Step window states: origin tooltip, done (check, glow, one sound), mini view, combat dim to 60 %, usage hint (HelpTip once, else in the status line), status line, route falls short, skip with follow-up quests (dialog names each one), quest abandoned (two ways; the fail symbol marks the step only when it is about the abandoned quest, step text stays white, Welle 5d), optional dungeon step, rumor line | built | dungeon step from `Route.DungeonHint`, rumor from `ns.Explore` (Welle 4); "collecting data" in the origin tooltip while prerequisites are unconfirmed |
| Right-click menu: undo with the name of the last action, skip, back, arrow, mini view, report, share data, settings, pause | built | also on the minimap button and in the addon compartment |
| Replanning in the step window (Welle 7): banner "N levels above the plan. Adjust the route?" and the switch point "… fits your level better … Go there next?" with the time gain, two buttons, never new in a fight; after "Adjust" the status line counts the quests left out; "N quests skipped earlier" in the XP tooltip; preview states `over`, `switch`, `earlier` | built | `spec/ui_replan_spec.lua`, `spec/ui_preview_spec.lua`; live checks in Forever: `docs/TESTING-RETAIL.md` §3a |
| Arrow (module `arrow`, `mod.arrow.*`): Navigation-Tracked-Arrow with black outline, TomTom color gradient, "behind you" from 135 degrees, colorblind colors, distance five times per second, arrival 12 yd | built | direction 20 times per second, rotation every frame, no allocation per frame (measured offline); Welle 5d: drawn desaturated with an additive copy, because the atlas is orange gold and turned the colorblind blue dark green; goal and distance in Blizzard's outline fonts; hidden while one of Blizzard's dialogs is open |
| Map pins (module `mappins`, `mod.mappins.*`): goal, quest givers and turn-ins with Blizzard's symbols; minimap pin off by default | built | Blizzard's user waypoint only with "use Blizzard navigation" |
| Minimap button and addon compartment entry (module `minimap`, `mod.minimap.*`) | built | the own logo does not exist yet (concept §3.2); until then Blizzard's waypoint atlas stands in |
| First start (module `setup`, `mod.setup.*`): one question with three cards, closing picks "With hints", once per account, never in combat | built | `/bd4 setup` and the settings reopen it |
| Settings (module `settings`, `mod.settings.*`): main page with four options and two buttons; Play style, Display, Arrow and Map, Accessibility, Credits | built | tooltips one sentence each, positive labels, dependent options greyed out |
| Positions (owner readings 16 and 17, Welle 5c): default place top right where Blizzard's quest tracker stands, measured at login and after layout, display and UI scale changes from `MinimapCluster`, `MultiBarRight` and `MultiBarLeft` (shown or not) and bars 6 to 8 at the right edge, gap 10 units; left of `ObjectiveTrackerFrame` while the tracker shows; fixed place TOPRIGHT -115/-266 when nothing can be measured. The step window moves by dragging its header band outside a fight ("Lock window" on the Display page stops that), the arrow with Shift held (click-free otherwise, rule P7), both in Blizzard's Edit Mode (`EditMode.Enter`/`EditMode.Exit`); a saved place is never overwritten; "Reset" on the Display page | built | `spec/ui_place_spec.lua` and `spec/ui_move_spec.lua` with Blizzard's frames in Retail measures (wow-ui-source live 12.1.5 and forever 1.60.1); counter-check: the old place TOPRIGHT -80/-260 lies on the tracker and reaches into the right bars; Edit Mode check in the client: `docs/TESTING-RETAIL.md` §4; places per UI type since Welle 9: mouse and keyboard and the gamepad UI keep their own places like Forever's Edit Mode layouts, switched after a fight (`spec/ui_gamepad_spec.lua`); the gamepad UI itself only in the Forever client (launch runbook minute 10 to 25) |
| Size 75 to 200 %, Blizzard's text size (`userFontScale`), quest text contrast raises the background to 80 % | built | |
| No protected call in combat: settings, setup window, HelpTip, waypoint and sound wait for the end of the fight; no window moves or sizes in a fight | built | `spec/ui_combat_spec.lua` with a counter-check: without the guard the test records 27 blocked calls of 12 kinds (since Welle 8 with the page "Your run") |
| Performance offline (Lua 5.1, stand-ins): arrow 0.001 ms per frame without allocation; step window 0.0001 ms per frame; quest log updates refresh only the window's texts (0.2 ms with the 20-step scroll list of Welle 5b, at most 5 per second: 0.017 ms per frame); a step or route change refreshes window, pins and arrow (0.7 ms) and recomputes XP balance and dungeon hint (0.46 ms); quest tracker pass with 25 quests 0.28 ms per burst of quest events (0.023 ms per frame at most); interface code about 0.27 MB | built | `spec/ui_perf_spec.lua`; binding values: `C_AddOnProfiler` in the client (release gate T16) |
| Developer preview `/bd4 preview <state>` for every design state | built | developer build only (`Braindead4Ever/Probe/Preview.lua`) |
| Window size (owner reading point 14, Welle 5b): grip at the bottom right (Blizzard's `PanelResizeButtonTemplate`), width 260 to 500, the height sets the visible next steps 0 to 10 and "steps ahead" follows both ways, the next 20 steps in a Blizzard ScrollBox with `MinimalScrollBar`, the rest scrolls; size per account, "Reset" resets it; never in a fight | built | 20 steps in the list is a chosen value; `spec/ui_size_spec.lua` |
| Blizzard's quest tracker (owner reading points 15 and 16, Welle 5b and 5c; module `questwatch`, `mod.questwatch.*`): unchanged, only quests of the route, hidden (default since Welle 5c: whoever kept the old default gets the new one, a choice stays, revision in `BraindeadForeverDB.ui`); pause and a module turned off bring the tracker back; marks saved per character and restored with "unchanged", pause, module off and at every logout; marks the player sets stay, removed ones stay removed; out of combat only | built | taint from addon code unconfirmed: `docs/TESTING-RETAIL.md` §3 with `taintLog 2`; "hidden" sets the tracker's alpha (a `Hide()` does not hold and taints, RealUI 2026-10-05); counter-check: without the combat guard `spec/ui_combat_spec.lua` and `spec/ui_questwatch_spec.lua` record `RemoveQuestWatch` in a fight and fail |
| Screenshots in the Retail test bed (design stage 2) | in progress | first pass 2026-11-01: 32 pictures, 13 must and 10 should findings, fixed in Welle 5d except the arrow shape (at 55 and 120 degrees a base corner of `Navigation-Tracked-Arrow` reads as the tip; the rotation itself matches, a design question); second pass with the commands of the test package, `docs/TESTING-RETAIL.md` |
| Tooltip of the XP line (Welle 5b): planned level at this step and the deviation of the character (owner guideline 7, requirement A16), time forecast from `Route.Forecast()` with "collecting data" until a part has enough real runs | built | `spec/ui_xptip_spec.lua`; planned levels are planning values until AP 10 |
| Hint level 1 in the step window (Welle 5b): the riddle of the player's zone as its own gold line "Hint: …" in the look of the rumor line; it goes after the next completed step and the next riddle of the zone follows; none with "Just follow the arrow", none new in a fight | built | `spec/ui_hints_spec.lua` with the ATT finds of Elwynn Forest |
| Hint level 2 on the world map (Welle 5b): the area of a find as a circle of Blizzard's atlases (`UI-prey-Scoutingmap-ring` over `common-mask-circle` tinted gold), sized in map units and scaling with the terrain, tooltip "Area" with one sentence per kind as in design v2 view 4; clicks go through to the map | built | the faint disc (18 %) is a chosen value; map pins now take mouse motion at creation, so the map wires their tooltips (Blizzard_MapCanvas.lua forever) |
| Key bindings (`Braindead4Ever/Bindings.xml`, module `bindings`, `mod.bindings.*`): guidance on and off, check off, skip, step back, step window on and off (this session), mini view, the page "Your run"; unbound by default, own section "Braindead 4ever" on Blizzard's key binding page, English and German names; the same entry points as the window, so the combat rule holds | built | Welle 9; `spec/ui_bindings_spec.lua`, keys in `spec/ui_combat_spec.lua`; whether gamepad players can bind them is open (concept §2.9) |
| TomTom hand-over (module `tomtom`, `mod.tomtom.*`): the current goal as one TomTom waypoint (quiet, not saved), replaced at every goal, removed at the end, on pause and with the option off ("Hand the goal to TomTom" on the Arrow and Map page, only with TomTom); after a fight | built | Welle 9; interface read in TomTom v4.3.13 (`AddWaypoint`, `RemoveWaypoint`); `spec/ui_tomtom_spec.lua` with a stand-in; a real TomTom: release gate T20 |
| Hardcore-safe mode in the window: gold warning line under the step (also in the mini view), no optional dungeon step; setting on the Play style page | built | Welle 9; `spec/route_hardcore_spec.lua`, docs/ROUTE-RUNTIME.md §Hardcore-safe mode |
| Coverage named honestly (requirement A32): TOC notes and README say levels 1 to 30, the end of the route says "Routes from level 30 on follow with updates" (the level from the route data) | built | Welle 9; `spec/coverage_spec.lua` |
| Umlauts in every window (release gate T19): step window, arrow goal (one line, width 220) and first start keep German texts whole, limited by width and lines | built | `spec/ui_size_spec.lua`, Welle 9 `spec/ui_umlaut_spec.lua`; lengths in the German client: release gate T25 |

## Your run (Welle 8)

The player's own statistics and the comparison with the class from the run vault ([RUN-STATS.md](RUN-STATS.md)). Module `stats` (`mod.stats.*`) keeps the tally per character and the best times of the account; module `statspage` (`mod.statspage.*`) shows the page and the review card.

| Feature | Status | Note |
| --- | --- | --- |
| Tally per level: active seconds as the run section of the vault, breaks apart, XP from quest rewards, enemies and other, time fighting, moving, flying and other, quests done and skipped, deaths; module runs | built | `spec/stats_spec.lua` on dummy records, `spec/ui_stats_spec.lua` in a session; new events `PLAYER_STARTED_MOVING` and `PLAYER_STOPPED_MOVING` (Forever docs `UnitDocumentation.lua`); XP of a quest whose `QUEST_TURNED_IN` never comes stays under "other" |
| Comparison with the class: median and rank per level, route section and band of ten levels, apart by way of play (follows the route, free play, partly); from 10 runs of other players, else "collecting"; built in slices only while a window waits, never in a fight | built | counter-checks: without the minimum nine runs show a median, without the fight guard the build reads the vault in a fight |
| Page "Your run": right-click menu, minimap button menu, `/bd4 stats`; tabs levels, sections, best times; a bar per row with a line at the median; never opens by itself, waits for the end of a fight | built | Blizzard templates (`BasicFrameTemplateWithInset`, `PanelTabButtonTemplate`, WowScrollBox), Blizzard's XP bar atlas `UI-HUD-ExperienceBar-Fill-Experience` (Forever and live inventories); counter-check: without the out-of-combat queue the page opens in a fight |
| Review card at level 10, 20 and 30: once per character, after the level-up banner, not in a fight or an instance, closable, switched off on the card or on the settings page Display | built | counter-check: without the shown mark the card comes a second time |
| Best times per band of ten levels over every character of the account, with race and class | built | `BraindeadForeverDB.stats`, taken over from the vault's own sections at the first start (migration to schema 1) |
| Cost offline (Lua 5.1, stand-ins): page closed 0 per frame, an event 0.3 µs; page open with 5000 sections 0.019 ms per frame over 10 s (longest frame 1.2 ms), review card 0.02 ms; comparison +104 KB, saved tally of a level-30 character about 8 KB | built | `spec/stats_perf_spec.lua`; binding values: `C_AddOnProfiler` in the client (gate T16) |
| Developer preview `stats`, `stats0`, `recap10`, `recap30` | built | `docs/TESTING-RETAIL.md` §2 |
