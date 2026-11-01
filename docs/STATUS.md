# Feature status

Every feature has one status: **planned**, **built** (code and offline tests pass), **verified in game** (checked in the WoW: Forever client) or **blocked**. German project documents use geplant, gebaut, im Spiel geprüft, blockiert.

Only a person sets **verified in game**, after playing it, never a test or the probe. The probe only measures (`OK`, `MISSING`, `ERROR`, `SECRET`, `FAILED`, `ARGERROR`).

Last update: 2026-11-01

## API probe (AP 3)

The developer probe checks in the client whether every function, event, value, atlas and CVar a planned feature needs exists and what it returns, before anything is built on it. It ships only in the developer build: the TOC lists it inside `#@do-not-package@` and `.pkgmeta` ignores `Pathmark/Probe`.

| Command | What it does |
| --- | --- |
| `/pathmark probe run [label]` | runs every check that needs no context; label defaults to `free` or `combat` |
| `/pathmark probe check <id>` | runs one check, also the manual ones (`comm.burst`, `export.window`, `perf.memory`, `qitem.button`) |
| `/pathmark probe status <id> planned\|built\|verified\|blocked` | sets the plan status after a game test |
| `/pathmark probe report` | copyable report, one tab-separated line per check, plus blocked actions |

Context checks run by themselves when their window opens: quest dialog (`QUEST_DETAIL`), loot (`LOOT_OPENED`), book (`ITEM_TEXT_BEGIN`, `ITEM_TEXT_READY`), flight map (`TAXIMAP_OPENED`), gossip (`GOSSIP_SHOW`), greeting (`QUEST_GREETING`), target change and combat start. The checks of the modules' own requirements are added automatically as `mod.<module>.<name>`.

**Order of use:** Retail 12.1.5 test bed before 2026-11-04 (values are only a preview: Forever has other map data and events), then on 2026-11-05 in the Forever client: `/pathmark probe run` outside combat, again in the first fight (`run combat`), open a quest giver, a chest, a book, a flight master, click the quest item button, then copy the report.

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
| TOC for Forever (`Pathmark_Camelot.toc`, interface 16001) | built | 16001 is the beta interface; check the live client on 2026-11-05 with `/dump select(4, GetBuildInfo())` |
| TOC for the Retail 12.1.5 test bed (`Pathmark.toc`, 120105 and 16001) | built | |
| Error buffer: first occurrence per session goes to the error handler, repeats are counted | built | `Core/Guard.lua` |
| Module turns off after 5 errors within 60 s | built | thresholds are chosen values, not measured |
| Modules declare required API functions and events, checked at login | built | `Core/Modules.lua` |
| Mandatory modules: no flag and no hand-set safe mode turns them off | built | collector and exchange (owner decision 2026-11-01); the automatic safe mode and the error buffer still apply |
| Start guard: safe mode after two unclean starts, lifted by a new version | built | does not help after a client crash (SavedVariables are written on logout and `/reload` only) |
| Slash command `/pathmark` (status, safe, flag, errors, quiet, export, report, probe) | built | |
| Copy window for export, report and probe | built | `Core/CopyWindow.lua`; the player copies with Ctrl+C (CopyToClipboard is restricted) |
| Texts in English and German | built | wording not approved yet |
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
| NPC names in the client language, zone changes, position samples, deaths, group size, hearthstone bind | built | |
| Export as `PM1` text (JSON, Deflate, Base64, length and Adler-32), only data not exported yet, acknowledged after Ctrl+C | built | `/pathmark export [all]`; Zlib only after `enc.zlib` passed in the client |
| Website decoder for the export (`decoder/decode.mjs`) | built | round trip Lua to Node decoder in `spec/export_spec.lua`; browser paste test with the `enc.deflate` text |
| Report a problem: version, build, module states, step, position, quest log, error buffer, marked player note | built | `/pathmark report [note]`; right-click menu comes with AP 6 |
| Two hours of simulated play without a Lua error, data anonymous | built | `spec/collect_spec.lua`; the acceptance "Forever start" needs two hours in the Forever client |

## In-game exchange (data contribution, M11)

Every installation shares what it discovers with other players who run the addon. There is no option to turn it off (owner decision 2026-11-01). Messages carry IDs and numbers only (`Collector/Proto.lua`), never names or localized text. Received finds are stored as unconfirmed (`rx`), a second independent player confirms them (`rx2`). Sender names live in memory for the session only.

| Feature | Status | Note |
| --- | --- | --- |
| Protocol: quest start, turn-in, object, book, rare, flight master, vignette; newer versions and unknown kinds skipped | built | |
| Targets: group at once; guild and hidden channel after 30 to 90 s | built | the delay keeps a message from telling where a player is right now |
| Throttling: own bucket of 10, one per second, 2 s gap on the channel, queue of 30 | built | server values can change; `comm.burst` measures them |
| No sending during chat lockdown, from trial or veteran accounts | built | |
| Hidden custom channel with fallback names when the password is refused or the channel is taken over | built | pattern after ForeverItemFinder; channel reach in Forever unconfirmed |
| Receiving: validation, dedup, confirmation by a second player, mute after 5 broken messages or 40 finds in 5 minutes | built | |
| Two clients exchange a test message (release gate T8) | planned | needs a second player in the game |
| Catch-up of finds announced while offline | planned | AP 12 |

## Planned features and their probe checks

Stages from the project plan: MVP (first public release) and 1.0. Status refers to the feature, the probe checks to what the client must offer for it.

| Feature | Stage | Status | Probe checks |
| --- | --- | --- | --- |
| Client and restrictions: build, project ID, secret values, restriction state, locales, game rules, script budget, SavedVariables after a cold start | all | built (probe) | `ver.build`, `ver.project`, `ver.camelot`, `ver.secretfn`, `ver.secrets`, `ver.restrict`, `ver.locales`, `ver.preset`, `ver.hardcore`, `ver.selffound`, `ver.rulesevent`, `ver.throttle`, `sv.coldstart` |
| M1 Step display: current step and the next three, progress detected automatically, skip and back | MVP | planned | `quest.count`, `quest.info`, `quest.objectives`, `quest.flagged`, `quest.ready`, `quest.max`, `quest.trivial`, `quest.elite`, `quest.timers`, `quest.completed`, `quest.autocomplete`, `quest.progressev`, `quest.finished` |
| M2 Navigation: arrow, map and minimap markers, TomTom | MVP | planned | `nav.map`, `nav.pos`, `nav.world`, `nav.facing`, `nav.worldpos`, `nav.canwaypoint`, `nav.setwaypoint`, `nav.mappoint`, `nav.supertrack`, `nav.nextwaypoint`, `nav.questsonmap`, `nav.maprestrict`, `nav.tomtom`, `nav.cvar`, `nav.range`, `nav.reached`, `nav.supertrackev`, `nav.waypointev`, `nav.moving` |
| M3 Matching route by faction, race and class, entry at any level | MVP | planned | `route.race`, `route.class`, `route.faction`, `route.level`, `route.maxlevel`, `route.xpoff` |
| M4 Quest and item names from the client, NPC names from the collectors | MVP | planned | `name.quest`, `name.loadquest`, `name.questload`, `name.item`, `name.itemload`, `name.map`, `name.npc`, `name.npctooltip`, `name.creatureid` |
| M5 Hints on the way: trainer, hearthstone, flight master, supplies, sleeping bag | MVP | planned | `hint.bind`, `hint.binder`, `hint.trainer`, `hint.junk` |
| M6 Report a problem with one click | MVP | built | `mod.report.*` (command `/pathmark report`; the click comes with AP 6) |
| M7 Discoveries recorded by the collector | MVP | built | `find.giverguid`, `find.giverquest`, `find.rewardxp`, `find.questxp`, `find.lootsource`, `find.lootcount`, `find.fishing`, `find.lootnpc`, `find.booknpc`, `find.booktitle`, `find.taxiid`, `find.taxinodes`, `find.taxiworld`, `find.flightstate`, `find.newtaxi`, `find.ontaxi`, `find.rareclass`, `find.rarecombat`, `find.targetguid`, `find.targetname`, `find.creatureid`, `find.vignettes`, `find.vignetteev`, `find.legacyconst`, `find.legacy1187`, `find.legacy1188`, `find.legacy1189`, `find.combatlog`, `mod.collector.*` |
| M8 Quest item button, if the probe reports the call as allowed | MVP if the probe is green | planned | `qitem.info`, `qitem.use`, `qitem.cvar`, `qitem.button` |
| M9 Routes 1 to 30 for all 56 combinations as building blocks | MVP | planned | no client API; route format and linter come with AP 5 |
| M10 Status per value (unconfirmed, confirmed) and per section (provisional) | MVP | planned | no client API; route data (AP 5) |
| M11 Data contribution through addon messages, export as extra | MVP | built | `comm.prefix`, `comm.lockdown`, `comm.outgoing`, `comm.trial`, `comm.veteran`, `comm.join`, `comm.filter`, `comm.channel`, `comm.nameformat`, `comm.stats`, `comm.burst`, `comm.restrictev`, `comm.noticeev`, `enc.json`, `enc.deflate`, `enc.zlib`, `enc.base64space`, `export.window`, `mod.exchange.*` |
| M12 Interface: setup dialog, settings, looks Modern and Classic | MVP | planned | `ui.settings`, `ui.opensettings`, `ui.editmode`, `ui.helptip`, `ui.compartment`, `atlas.header`, `atlas.nub`, `atlas.check`, `atlas.glow`, `atlas.collapse`, `atlas.parchment`, `atlas.arrow`, `atlas.pin`, `atlas.minipin`, `atlas.questnormal`, `atlas.questturnin`, `atlas.barbg`, `atlas.barfill`, `atlas.indicator`, `font.header`, `font.line`, `font.small`, `font.med3`, `font.highlight`, `color.normal`, `color.highlight`, `color.tracker`, `color.dimred`, `sound.complete`, `sound.option`, `sound.select` |
| M13 Accessibility: scaling, contrast, shape and color, key bindings, gamepad does not break | MVP | planned | `ui.textsize`, `ui.gamepad`, `cvar.contrast`, `cvar.colorblind`, `cvar.fontscale`, `cvar.instant`, `cvar.gamepad` |
| M14 Safety for the start without a test: error buffer, runtime probe, safe mode, start guard, version notice | MVP | built (version notice planned) | `safe.eventvalid`, `safe.errorhandler`, `safe.debugstack`, `safe.blocked`, `safe.forbidden`, `safe.scripterrors` |
| Performance budget: 10 MB, under 0.1 ms per frame | MVP | planned | `perf.profiler`, `perf.average`, `perf.memory` |
| Game modes Speed, Explorer, Hardcore-safe | 1.0 | planned | no client API beyond M1 and `ver.hardcore` |
| Hint levels | 1.0 | planned | no client API |
| Time forecast | 1.0 | planned | `time.xp`, `time.xpmax`, `time.rested`, `time.played` |
| Optional automation (accept, turn in, reward) | 1.0 | planned | `auto.accept`, `auto.complete`, `auto.reward`, `auto.acknowledge`, `auto.autoaccept`, `auto.gossip`, `auto.gossipselect`, `auto.greeting` |
| Group and duo | 1.0 | planned | `group.ingroup`, `group.members`, M11 checks |
| Personal review "your way to 60" | 1.0 | planned | export (M11) and website (AP 9) |
| Later: route studio, dungeon inserts, profession leveling, controller | after 1.0 | planned | checked one by one when due |

## Tooling

| Feature | Status | Note |
| --- | --- | --- |
| Offline tests (busted, Lua 5.1.5) with WoW API stand-ins | built | |
| Export round trip against the website decoder (Node 22 or newer) | built | runs inside busted; CI uses the runner's Node |
| luacheck, StyLua, LuaLS type check, gitleaks, actionlint | built | |
| CI on GitHub with required checks | built | branch protection on `main` |
| Release by tag (BigWigs packager to CurseForge, Wago, GitHub) | planned | needs the CurseForge and Wago projects and their tokens |
