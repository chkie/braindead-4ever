# Testing the interface in the Retail client (design stage 2)

Design stage 2 (concept §2.12): the addon runs in the Retail 12.1.5 test bed and every view of the approved design v2 is captured as a screenshot. The developer preview puts each window into each state of the design, also states the test bed cannot reach by itself (abandoned quest with follow-ups, optional dungeon, rumor, route falls short).

Last update: 2026-11-01

## 1. Install

1. Use a checkout of this repository, not a release zip: only the developer build has the preview (`Pathmark/Probe/`).
2. Copy the folder `Pathmark/` (the one that contains `Pathmark.toc`) into the AddOns folder of the Retail client, so the result is:
   - Windows: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\Pathmark\Pathmark.toc`
   - macOS: `/Applications/World of Warcraft/_retail_/Interface/AddOns/Pathmark/Pathmark.toc`
3. Start the game. In the character list open **AddOns**, make sure **Pathmark** is ticked. `Pathmark.toc` declares interface 120105, so "load out of date AddOns" is not needed.
4. Log in. After two seconds the first start opens once per account. To see it again: `/pathmark setup`.
5. After copying a new version: `/reload`.

The live route in Retail uses Forever quest IDs and maps, so quest names may show as "Quest 783" and the arrow may rest. That is expected; the screenshots use the preview below.

## 2. One command per design state

`/pathmark preview <state>`; `/pathmark preview off` returns to the live route. `/pathmark preview` alone lists the states.

| Design view and state | Command | Look for |
| --- | --- | --- |
| 1 Step window, normal | `/pathmark preview normal` | header and content same width, "3/8" in gold behind the goal, next three steps dimmed and wrapping, XP line |
| 1 Tooltip origin | `/pathmark preview tooltip` (or hover the step); hover the clock symbol for "provisional" | GameTooltip with "Where the data comes from" |
| 1 Step done | `/pathmark preview done` (or click the check box) | check symbol, short glow inside the window, one sound, next step after about one second |
| 1 Mini view | `/pathmark preview mini` (or the collapse button in the header) | only the current step |
| 1 In combat | `/pathmark preview combat`, better: attack a creature | window at 60 %, no glow or sound in the fight |
| 1 Usage hint | `/pathmark preview help` | HelpTip "Right-click the window …" with "Got It" |
| 1 Right-click menu | `/pathmark preview menu` (or right-click the window) | "Undo: checked off …" on top |
| 1 Status line | `/pathmark preview status` | "New version available" at the bottom |
| 1 Route falls short | `/pathmark preview reach` | gold note with missing XP and enemies |
| 1 Skip with follow-ups | `/pathmark preview skip` | dialog listing the follow-up quests, "Skip" and "Cancel" |
| 1 Quest abandoned | `/pathmark preview abandon` | fail symbol, red step, "Accept again" and "Skip with follow-ups" |
| 1 Optional dungeon | `/pathmark preview dungeon` | gold tag with Blizzard's words for optional and dungeon and the level range 18–24 on the second next step |
| 1 XP line tooltip with forecast (Welle 5b) | `/pathmark preview forecast` (or hover the XP line) | "Level and time": planned level 3, "Your level: 5, 2 levels above the plan", gold "Time forecast" with route end, section against the median, next level with XP per hour |
| 1 XP line tooltip without runs (Welle 5b) | `/pathmark preview collecting` | the same tooltip with "collecting data" instead of times |
| 1 Size: narrowest (Welle 5b) | `/pathmark preview narrow`, best in a German client | 260 units wide; umlauts whole, next steps wrap to two lines, nothing cut in the middle of a word |
| 1 Size: widest, ten steps (Welle 5b) | `/pathmark preview wide`; then drag the grip at the bottom right up and down, `/pathmark preview off` restores the size | 500 units wide, ten next steps, Blizzard's thin scroll bar on the right; the mouse wheel scrolls to steps 11 to 20; while dragging the height, "Show steps ahead" in the settings (Display) follows; in a fight the grip does nothing |
| 2 Arrow colors | `/pathmark preview arrow 0`, `arrow 55`, `arrow 90`, `arrow 120`, `arrow 160` | green, yellow-green, yellow, orange-red, red with "behind you"; stand still while taking the shot |
| 2 Arrival | `/pathmark preview arrival` | check and "Reached destination", gone after one second |
| 2 Colorblind | `/pathmark preview colorblind 5`, `colorblind 90`, `colorblind 170`; also Blizzard's settings, Accessibility, colorblind mode | blue, white, orange |
| 2 Map | open the world map (M) and the minimap after `/pathmark preview normal`; minimap pins: settings, Arrow and Map | waypoint pin; quest symbols come with the live route in Forever |
| 3 First start | `/pathmark preview setup` | one question, three cards, footer |
| 4 Rumor | play style "With hints" (settings, Play style), then `/pathmark preview rumor` | "Rumor: Someone found something in …" with "Show location" |
| 4 Riddle (hint level 1, Welle 5b) | play style "With hints", then `/pathmark preview riddle` | gold line "Hint: A book waits to be read in the south of …" above the current step, same look as the rumor line |
| 4 Area (hint level 2, Welle 5b) | `/pathmark preview area`, then open the world map (M) | gold ring with a faint gold disc around your position, about 100 yards across; hover shows "Area" and "A book lies within the marked circle."; zoom in and out: the circle grows and shrinks with the map; clicks on the map still work inside it |
| 5 Settings | `/pathmark preview settings` (or Esc, Options, AddOns, Pathmark) | main page and the five sub pages |

## 3. Blizzard's quest tracker (Welle 5b, owner reading point 15)

Whether the watch calls and the tracker's alpha from addon code cause taint is unconfirmed; this check settles it. The module turns itself off when the game blocks one of its calls (`/pathmark status` shows `questwatch` with the reason).

1. Before logging in: `/console taintLog 2` in the chat once (stays set), then `/reload`.
2. Accept three quests, mark one of them in the quest log yourself (shift-click or the check box) and note which ones Blizzard's tracker shows.
3. Settings, Display, "Blizzard's quest tracker":
   - "Only quests of the route" (default): quests the route does not know leave the tracker, your own mark stays; a newly accepted quest off the route leaves it again within a second.
   - "Hidden": the tracker disappears; quests you marked yourself stay in the list.
   - "Unchanged": the marks from step 2 come back, plus what you marked or removed meanwhile.
4. Right-click menu, "Pause guidance": the marks from step 2 come back; "Resume guidance" applies the option again.
5. Do the same once in a fight: nothing changes until the fight ends.
6. `/reload`, then open `World of Warcraft/_retail_/Logs/taint.log`: lines naming `Pathmark` together with `ObjectiveTracker`, `QuestWatch` or `blocked` are the finding; copy them into the report. No such line: the check passed.
7. Turn Pathmark off in the AddOns list and log in: the tracker shows the marks from step 2 (Pathmark puts them back at every logout).

## 4. Situations per screenshot

Concept §2.12 asks for these situations; take the views of section 2 in them:

- light and dark ground (snow or desert, and a cave or night),
- next to a quest giver and in a fight,
- size 75 % and 200 % (settings, main page, "Size"), and Blizzard's text size at its largest (Blizzard settings, Accessibility),
- German and English client (Battle.net launcher, game settings, text language),
- window and arrow moved in Edit Mode (Esc, Edit Mode, drag them; "Reset" on the settings page Display).

Screenshots land in `World of Warcraft/_retail_/Screenshots/` (key: Print). A name per view helps, for example `1-normal-de-light.jpg`.

## 5. If something breaks

- `/pathmark status` lists every module; a module that turned off shows its reason.
- `/pathmark report` opens the copyable problem report (also in the right-click menu), with missing atlases if the client lacks one.
- Lua errors: BugSack, or `/console scriptErrors 1`.
