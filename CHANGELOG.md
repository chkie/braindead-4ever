# Braindead 4ever

<!--
Release notes. The packager uses this file for every upload (manual-changelog in .pkgmeta).
Before a tag: give the top section the version and the date, newest section on top, in English.
After renamed or deleted files add:
"Restart the game client completely after this update, /reload is not enough."
Keep "Known issues" current. Hotfix steps: CONTRIBUTING.md, "Hotfix".
-->

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

- The routes are computed from open data and not played yet; every section is marked as provisional until our own runs replace it.
- The Speed routes leave out some quests in the starting zones that the quest givers offer, for example "Cutting Teeth" in the Valley of Trials. Corrected routes follow with the next update.
- Braindead 4ever could not be tested in the Forever client before the start. If a part fails, it turns off and the rest keeps running; after two failed starts the safe mode keeps the core running.
