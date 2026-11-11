# Braindead 4ever

<!--
Release notes. The packager uses this file for every upload (manual-changelog in .pkgmeta).
Before a tag: give the top section the version and the date, newest section on top, in English.
After renamed or deleted files add:
"Restart the game client completely after this update, /reload is not enough."
Keep "Known issues" current. Hotfix steps: CONTRIBUTING.md, "Hotfix".
-->

## 0.9.12 (2026-11-11)

- New settings page "Sharing" with one option, on by default. When it's off, the addon leaves the hidden channel, sends nothing there and hears nobody there. Your group and guild still get addon messages, which no chat window shows.
- `/bd4 flag exchange off` now tells you where the Sharing setting is.

## 0.9.11 (2026-11-11)

- Profession quests are optional. Where the route reaches Camping 101 in a start zone, the step window asks whether you want to fit the profession quests in now or do them on your own. "Fit in" keeps them in the route as before. "On my own" leaves them out, and the route goes on with the next quest. Undo in the right-click menu brings them back. The quest The Great Outdoors stays in the route. The quest automation picks these quests up only after "Fit in".
- A left click on the check box of the current step now checks the step off. Before, only the right-click menu worked.
- Quest data as of 11 November. Quest givers that Forever moved are at their new spots: in Teldrassil and Redridge Mountains some waypoints moved by up to 135 yards, and one turn-in each in Elwynn Forest and Teldrassil is in Stormwind or Darnassus, with a walk step into the city and back out.

## 0.9.10 (2026-11-09)

- A ride step now names where the ride lands. The zeppelin from Orgrimmar lands in Tirisfal Glades, and a walk step then leads on to Silverpine Forest. Before, the step said "zeppelin to Silverpine Forest". Same for every boat, zeppelin, airship and tram step, both factions.
- Quest data as of 9 November. Quests the game offers only after another quest now come after that quest in the route, for example a chain in the Barrens and a quest in Tirisfal Glades. Quest givers that Forever moved are at their new spots, for example Burning Shadows is handed in in Orgrimmar, with a walk step into the city and back out.
- A few quests are out of the route until the next large update brings in the quests they need: one Silverpine Forest quest for every Horde character, one more Silverpine Forest quest in the Speed route, and some Undead Paladin and Night Elf Druid class quests. Before, the route asked for them although the game does not offer them yet.
- "Blizzard's quest tracker: Hidden" (the default) now only hides the tracker and leaves your quest marks alone. The game marks new quests by itself again, and the quest areas show on the minimap. Before, the option removed the marks, and with them the areas on the minimap.
- The tooltip of "Only quests of the route" says that quest areas on the minimap show only for marked quests. Choose "Unchanged" if you want every quest marked.

## 0.9.9 (2026-11-07)

- A rumor about other players' finds now shows only in the zone of the find. Before, a rumor from any zone could show up at once, for example a quest in the Barrens for a level 3 character in Tirisfal Glades, and read like an offer to go there. A rumor of another zone now waits until you are in that zone.

## 0.9.8 (2026-11-06)

- When you reach the level for your next class quest, the route tells you which quest it is and where to pick it up, and asks: now or later. Now takes you there and then back to the step you left. Later keeps the class quest where the route has planned it.
- Before the route sends you to a class quest in another zone, it asks: now or later.
- Class quests are never lost. A step of your class chain that you skip, abandon or pass by level waits on a list, and the route asks again at the next zone change whether you want to do it now.

## 0.9.7 (2026-11-06)

- Finds reach other players far more often while few players share the hidden channel, as now after the launch: with a handful of players almost every find goes out, instead of about half. Each player receives at most one short message per second on average, which costs well under one percent of the addon's own frame budget.

## 0.9.6 (2026-11-06)

- Braindead 4ever is a WoW Forever addon and is no longer offered for Retail.

## 0.9.5 (2026-11-06)

- Route order fixed where the game offers a quest only after another one is handed in, as players have checked in WoW Forever since the launch:
  - Wetlands: "From the Ashes" now comes after you hand in "War Banners" (all Alliance routes).
  - Hillsbrad Foothills: "Scout Support" now comes after "Battle of Hillsbrad" part II (all Horde routes).
  - Deathknell: the Undead Paladin's class quest "A Difficult Path" now comes after "The Mindless Ones".
  - Sen'jin Village: "Forgotten Loa Idols" now comes after "Report to Sen'jin Village".
  - Tirisfal Glades (Explorer routes): "The Adventurer" now comes after "The Red Messenger".
- No quest was added or removed.

## 0.9.4 (2026-11-06)

- Sharing with players outside your group and guild works on WoW Forever. The game does not pass addon messages on in the hidden channel Braindead 4ever uses, so nothing reached other players there. Each find now also goes out as a short line in that channel: one line with one of your key presses or clicks, at most one every two seconds, never in a fight or an instance. No chat window shows these lines. Sharing with your group and guild is unchanged.

## 0.9.3 (2026-11-05)

- Sharing in the game works again: since the start, Braindead 4ever sent nothing to your group, guild or the hidden channel, because it trusted a client flag that reports chat for addons as restricted on normal realms. It now tries to send and goes by the server's answer.

## 0.9.2 (2026-11-05)

- When the quest giver of the current step does not offer its quest although the route expects it (the quests before it are handed in), the route no longer waits: it sets the quest aside with its follow-ups, says so in the step window and takes it back as soon as an NPC offers it or you accept it anyway. This covers quests whose prerequisites in the open data are wrong, for example "The Adventurer" and "Tomb Weed" in Tirisfal Glades and "Stormy Potential" and "Forgotten Loa Idols" in Durotar.
- The step window names an XP shortfall only near the end of a zone. At level 1 it counted the whole starting zone as grinding.

## 0.9.1 (2026-11-04)

- Sharper arrow: its own high-resolution arrowhead with a notch, so the tip is clear at every angle. Same colors as before.
- Round minimap button with the gold ring of the game's own buttons.
- After you reach a goal, the arrow shows the name and distance of the next goal again.
- German texts in the settings and on the page "Your run" no longer get cut off.
- The step tooltip and the Credits page say "open game data" for imported quest and map data; credits and licences are in the file NOTICE.
- Optional automation, off by default: one switch on the main settings page accepts and hands in the quests of the route when you talk to the NPC and takes the reward when there is no choice. Other quests, other dialog options and quests with several rewards stay yours; hold Shift to pause it for a dialog. It never acts in a fight, and in the hardcore-safe mode it takes no quest the route warns about.
- Flight connections and the times of flights without a stop are now shared with other players of Braindead 4ever, as flight point IDs and seconds only, within the existing limit of the hidden channel.
- Accept and turn-in steps name the NPC, for example: Accept "Wolves Across the Border" from Eagan Peltskinner. The name is in your game's language. A name shows once your game knows the NPC (seen nearby, targeted or talked to); names you learn are kept for your other characters. Until then the step reads as before.
- Quest item button: when the quest of the current step has an item to use, a button with the item appears next to the step, with charges, cooldown and the range dot of the game's quest tracker. A key for it: Key Bindings, Braindead 4ever, "Use quest item" (unbound by default). In a fight the button keeps its item and its place until the fight ends.
- New routes for levels 1 to 30, both factions, both modes. In the route model every one of the 56 race and class combinations reaches level 30 faster than with 0.9.0 (5 to 25 % less time, 15 % in the middle) and spends far less time grinding mobs between quests (27 to 61 % less). The Speed routes now also take quests that start from a dropped item, and quests whose prerequisite is not known yet when their giver stands at a place the route visits anyway; if such a quest is not offered to you, skip the step.
- Trainer, hearthstone, flight point and flight steps: the routes now send you to your class trainer when you have new skills to learn, pick up flight points on the way, set and use your hearthstone where it saves the walk back and, on the Horde routes, take a flight where it is faster than walking (the open data has no flown Alliance connection on the way yet). Such a step checks itself off when you open your class trainer, set or use your hearthstone, open the flight map or land after a flight, and the world map marks trainer, innkeeper and flight master with the game's own symbols.
- The problem report window and the credits page show the link to our Discord server.

## 0.9.0 (2026-11-03)

- Step-by-step routes for levels 1 to 30, both factions, all races and classes; levels 30 to 60 follow with updates.
- Step window, arrow, map and minimap pins, first start, settings in English and German.
- Page "Your run" with your times per level and the comparison with your class.
- Hardcore-safe mode: warnings for elite quests and quests 3 or more levels above you, no dungeon hints.
- Key bindings (unbound by default), TomTom hand-over when TomTom is installed, version notice.

## Known issues

- The routes are computed from open data, and every section is marked as provisional. Rebuilt routes replace them zone by zone, starting with the first 20 levels.
- The Speed routes leave out some quests in the starting zones that the quest givers offer, for example "Cutting Teeth" in the Valley of Trials. The rebuilt routes take them in.
- Not every release is played in the Forever client before it goes out. If a part fails, it turns off and the rest keeps running; after two failed starts the safe mode keeps the core running. Please report it with "Report a problem".
