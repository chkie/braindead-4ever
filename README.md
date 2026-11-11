# Braindead 4ever

Braindead 4ever is a free leveling guide addon for World of Warcraft: Forever. Its working title was Pathmark. The routes cover levels 1 to 30; levels 30 to 60 follow with updates.

**Status:** on [CurseForge](https://www.curseforge.com/wow/addons/braindead-4ever) since the start of WoW: Forever on 5 November 2026; what changed in each version is in [CHANGELOG.md](CHANGELOG.md), together with the known issues. The routes are computed from open data and marked as provisional. They are being rebuilt zone by zone, starting with the first 20 levels; until a zone is rebuilt, the current route stays.

## What it is for

- Step-by-step routes from level 1 to 30 for both factions, free of charge with no paid tier. Routes from level 30 to 60 follow with updates.
- Every step shows where its data comes from. Data taken from other open projects starts out as unconfirmed and is replaced as soon as our own in-game measurements cover it.
- Interface in English and German.

## How it is built

Every change has to pass automated tests, linting, a type check, a format check and a secret scan before it can be merged. I develop Braindead 4ever on my own. I play parts of each release in the Forever client before it goes out, but not every feature.

Quest IDs, coordinates and times come from open sources with a known licence or from our own measurements. Each value carries its source.

## Data contribution

Braindead 4ever records what you do while leveling, in your own game folder: quests accepted and turned in with their place, experience, objects you loot, rare enemies, flight masters, the flights you take and similar finds. Nothing in it names your character, your realm, your guild or other players, and there is no chat. Time is kept relative to the session, the date only as a day.

What you discover, Braindead 4ever shares in the game with other players who use it: IDs and map positions only, to your group at once, to your guild and other players 30 to 90 seconds later. Group and guild get addon messages. Other players get short chat lines in a hidden channel that only Braindead 4ever joins and reads, because WoW Forever does not pass addon messages on in such a channel; a line goes out with one of your key presses or clicks, never in a fight or an instance, and no chat window shows it. You can switch sharing on the hidden channel off in the settings, page "Sharing"; the addon then leaves the channel and hears no other players there, and your group and guild still get addon messages. Addon messages and chat lines show the game's sender name to the receiving addon; Braindead 4ever never stores it. Like any chat line, a line in the hidden channel shows the character name to everyone in that channel; the channel has a password, which is part of this source code.

Braindead 4ever also shares how long each level and each route part took you: active seconds, experience, race and class as numbers, whether you followed the route, the level and the day. These run times carry a random token that Braindead 4ever rolls once per character and derives from nothing else; it only serves to count each level of a character once. Other copies of Braindead 4ever keep them and pass them on, so the routes can be measured against real play ([format](docs/RUN-TIMES.md)). The page "Your run" (right-click menu, `/bd4 stats`) shows your own times per level and, once at least ten runs of your class have reached you, their median and where you stand ([details](docs/RUN-STATS.md)).

The flight connections you see at a flight master and the seconds of flights without a stop go out the same way, as flight point IDs and seconds only, and other copies pass them on until enough players know them ([details](docs/ROUTE-FORMAT.md#flights-in-the-exchange)).

Braindead 4ever tells other players which version of it you run (to your group, your guild and the hidden channel, once per session), so it can say when a newer version is out.

`/bd4 export` shows your data as a text to copy. It holds what you recorded and what other players shared with you, without names; nothing leaves the game unless you copy it. `/bd4 report` builds a problem report without names.

## Help and problem reports

Discord: discord.gg/ujjEM9NE5D. Right-click the minimap button or the step window and choose "Report a problem" (or type `/bd4 report`): the window shows a text without names to copy, and the link to our Discord. Post the text in the channel #bug-reports. Bugs can also be reported as an [issue](https://github.com/chkie/braindead-4ever/issues) here. The Credits page in the settings shows the link as well.

## Repository layout

| Path | Content |
| --- | --- |
| `Braindead4Ever/` | the addon as it goes into `Interface/AddOns` |
| `spec/` | offline tests (busted, Lua 5.1) with stand-ins for the WoW API |
| `types/` | type stubs for the Lua Language Server |
| `docs/STATUS.md` | every feature with its status and the probe checks it needs |
| `decoder/` | reads an export text in the browser or in Node |
| `scripts/` | local setup and checks |
| `data/` | route data: imported sources, merged facts, route files ([format](docs/ROUTE-FORMAT.md)) |
| `tools/` | route tools: importers, linter, compiler (Python 3, Lua 5.1) |
| `NOTICE` | credits and licences of the data from other projects |

The route files in `data/routes` are the source form of the compiled route data in `Braindead4Ever/Routes/Data_*.lua`; everything needed to rebuild it from them is in this repository. The tools that plan and measure the routes are kept outside it.

How to set up the tools and run the checks: [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-or-later with an additional permission for the Ace3 libraries, see [LICENSE](LICENSE) and [LICENSE-EXCEPTION.md](LICENSE-EXCEPTION.md).

World of Warcraft, Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. in the U.S. and/or other countries. Braindead 4ever is not affiliated with or endorsed by Blizzard Entertainment.
