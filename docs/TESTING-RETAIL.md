# Testing the interface in the Retail client (design stage 2)

Design stage 2 (concept §2.12): the addon runs in the Retail 12.1.5 test bed and every view of the approved design v2 is captured as a screenshot. The developer preview puts each window into each state of the design, also states the test bed cannot reach by itself (abandoned quest with follow-ups, optional dungeon, rumor, route falls short).

Last update: 2026-11-03

## 1. Install

1. Use a checkout of this repository, not a release zip: only the developer build has the preview (`Braindead4Ever/Probe/`).
2. Copy the folder `Braindead4Ever/` (the one that contains `Braindead4Ever.toc`) into the AddOns folder of the Retail client, so the result is:
   - Windows: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\Braindead4Ever\Braindead4Ever.toc`
   - macOS: `/Applications/World of Warcraft/_retail_/Interface/AddOns/Braindead4Ever/Braindead4Ever.toc`
3. Start the game. In the character list open **AddOns**, make sure **Braindead 4ever** is ticked. `Braindead4Ever.toc` declares interface 120105, so "load out of date AddOns" is not needed.
4. Log in. After two seconds the first start opens once per account. To see it again: `/bd4 setup`.
5. After copying a new version: `/reload`.

The live route in Retail uses Forever quest IDs and maps, so quest names may show as "Quest 783" and the arrow may rest. That is expected; the screenshots use the preview below.

## 2. One command per design state

`/bd4 preview <state>`; `/bd4 preview off` returns to the live route. `/bd4 preview` alone lists the states. Every state starts from a clean window (Welle 5d): the usage hint, the skip dialog, the first start, rumor and riddle lines, a demo arrow and a demo size of the state before are gone.

| Design view and state | Command | Look for |
| --- | --- | --- |
| 1 Step window, normal | `/bd4 preview normal` | the gold lines of the header band end at the window edges like the dark background; "3/8" in gold behind the goal and on the line of the last word; detail line with the distance and its unit ("48 m entfernt", the zone only when it differs from the header); next three steps dimmed and wrapping, the last one with its descenders whole ("abgeben"); no scroll bar at three steps; XP line with "EP" never alone on a line; text readable on bright sky (background 70 %) |
| 1 Tooltip origin | `/bd4 preview tooltip` (or hover the step); hover the clock symbol for "provisional" | GameTooltip with "Where the data comes from" |
| 1 Step done | `/bd4 preview done` (or click the check box) | check symbol, short glow inside the window, one sound, next step after about one second |
| 1 Mini view | `/bd4 preview mini` (or the collapse button in the header) | only the current step, the button shows "+", no scroll bar below the window; the next state shows "−" again |
| 1 In combat | `/bd4 preview combat`, better: attack a creature | window at 60 %, no glow or sound in the fight |
| 1 Usage hint | `/bd4 preview help` | HelpTip "Right-click the window …" with "Got It" |
| 1 Right-click menu | `/bd4 preview menu` (or right-click the window) | "Undo: checked off …" on top |
| 1 Status line | `/bd4 preview status` | "New version available" at the bottom; the header band stays where it was in "normal" (the window grows downwards only) |
| 1 Route falls short | `/bd4 preview reach` | gold note with Westfall, missing XP and enemies; never "?" |
| 1 Skip with follow-ups | `/bd4 preview skip` | dialog listing the follow-up quests, "Skip" and "Cancel"; the arrow is hidden while the dialog is open |
| 1 Quest abandoned | `/bd4 preview abandon` | the note and the marked step name the same quest ("Kobold Camp Cleanup"); fail symbol at the step, step text white with "3/8" in white, "Accept again" and "Skip with follow-ups" |
| 1 Optional dungeon | `/bd4 preview dungeon` | gold tag with Blizzard's words for optional and dungeon and the level range 18–24 on the second next step; XP line at level 18 |
| 1 XP line tooltip with forecast (Welle 5b) | `/bd4 preview forecast` (or hover the XP line) | "Level and time": planned level 3, "Your level: 5, 2 levels above the plan", gold "Time forecast" with route end, section against the median, next level with XP per hour |
| 1 XP line tooltip without runs (Welle 5b) | `/bd4 preview collecting` | the same tooltip with "collecting data" instead of times |
| 1 Over the plan (Welle 7) | `/bd4 preview over`, then "Adjust" | banner "You are 3 levels above the plan. Adjust the route?" with "Adjust" and "Keep route"; after "Adjust" the status line "2 quests left out: …" and no buttons |
| 1 Switch point (Welle 7) | `/bd4 preview switch` | banner "Westfall fits your level better (planned from level 9). Go there next? About 25 min faster." with "Go there" and "Keep route" |
| 1 Quests skipped earlier (Welle 7) | `/bd4 preview earlier` (or hover the XP line) | tooltip of the XP line with gold "7 quests skipped earlier:", five quest names and "and 2 more" |
| 1 Size: narrowest (Welle 5b) | `/bd4 preview narrow`, best in a German client | 260 units wide; umlauts whole, next steps wrap to two lines, nothing cut in the middle of a word |
| 1 Size: widest, ten steps (Welle 5b) | `/bd4 preview wide`; then drag the grip at the bottom right up and down, the next state or `/bd4 preview off` restores the size | 500 units wide, ten next steps, Blizzard's thin scroll bar on the right (only with more than three steps ahead); the mouse wheel scrolls to steps 11 to 20; while dragging the height, "Show steps ahead" in the settings (Display) follows; in a fight the grip does nothing |
| 1 NPC names (M4, 0.9.1) | `/bd4 preview npc`, also in a German client | "Accept “Wolves Across the Border” from Eagan Peltskinner" and below "Turn in “Kobold Camp Cleanup” to Marshal McBride" (German: "„Wölfe an der Grenze“ bei Eagan Peltskinner annehmen"); live, the name shows once the client knows the NPC (seen nearby, targeted or talked to) |
| 1 Quest item button (M8, 0.9.1) | `/bd4 preview questitem`; live: a quest with a usable item, e.g. a quest that hands you an item to use at a place | the button stands at the right of the current step inside the window, round gold frame like Blizzard's quest tracker, "3" at the bottom right, a gray dot at the top right (red when too far, a bound key shows its letter instead); the step text wraps before the button; the preview button uses nothing when clicked |
| 1 Hint steps (A35, 0.9.1) | `/bd4 preview hints`, also in a German client; then open the world map (M) | current step "Learn new skills at your trainer", below "Set your hearthstone at the inn", "Get the flight path" and "Fly to Westfall" (German: "Beim Lehrer neue Fähigkeiten lernen", "Ruhestein im Gasthaus setzen", "Flugpunkt holen", "Nach Westfall fliegen"), in the same look as the quest steps of `normal`; on the world map near your position the waypoint pin and the tracking symbols trainer (`Class`), innkeeper and flight master, none for the flight |
| 2 Arrow colors | `/bd4 preview arrow 0`, `arrow 55`, `arrow 90`, `arrow 120`, `arrow 160` | green, yellow-green, yellow, orange-red, red with "behind you"; goal and distance with a black outline, readable on bright sky; stand still while taking the shot. The tip is the corner opposite the notched edge: at 55 and 120 degrees a base corner can look like the tip (measured on the first screenshots, Welle 5d M11) |
| 2 Arrival | `/bd4 preview arrival` | check and "Reached destination", held ten seconds in the preview (one second live) |
| 2 Colorblind | `/bd4 preview colorblind 5`, `colorblind 90`, `colorblind 170`; also Blizzard's settings, Accessibility, colorblind mode | blue, white, orange in full brightness (not dark green and gold) |
| 2 Map | open the world map (M) and the minimap after `/bd4 preview normal`; minimap pins: settings, Arrow and Map | waypoint pin; quest symbols come with the live route in Forever |
| 3 First start | `/bd4 preview setup` | one question, three cards whose texts start on one line, footer ending with "Closing picks “With hints”."; no usage hint over the window |
| 4 Rumor | play style "With hints" (settings, Play style), then `/bd4 preview rumor` | "Rumor: Someone found something in …" with "Show location" |
| 4 Riddle (hint level 1, Welle 5b) | play style "With hints", then `/bd4 preview riddle` | gold line "Hint: A book waits to be read in the south of …" above the current step, same look as the rumor line |
| 4 Area (hint level 2, Welle 5b) | `/bd4 preview area`, then open the world map (M) | a round gold ring (not an oval) with a faint gold disc around your position, about 100 yards across; hover shows "Area" and "A book lies within the marked circle."; zoom in and out: the circle grows and shrinks with the map; clicks on the map still work inside it |
| 5 Settings | `/bd4 preview settings` (or Esc, Options, AddOns, Braindead 4ever) | main page and the five sub pages; a usage hint still open waits until the settings close |
| 5 Automation switch | `/bd4 preview auto` | the settings open on the main page at "Automate route quests", the fifth option, unchecked by default; its tooltip is one sentence and names Shift |
| 6 Your run, with comparison (Welle 8) | `/bd4 preview stats`; hover a row; click the tabs below the window | window "Your run" in Blizzard's frame, header "Level 12 • race • class", six summary values, table newest level on top with time, a bar in Blizzard's XP bar look and a white line at the class median, median and "faster than" in percent, XP per hour; level 12 says "running" in grey; row tooltip with active time, breaks, XP from quests, enemies and other, time fighting, moving, flying and other, quests, deaths, way of play and the class median; tabs "Sections" and "Best times"; tabs sit below the window like Blizzard's character window; Escape closes it |
| 6 Your run, without comparison data | `/bd4 preview stats0` | "collecting" in the median column, no line on the bars, "collecting data" for XP per hour and the end of the route; nothing reads like a number that is not there |
| 6 Review card at level 10 | `/bd4 preview recap10` | card "Review" in the middle: "Level 10 reached", race, class and way of play, active play time of levels 1 to 10 large, class median with the number of runs, "faster than" in percent, best time of the account marked "new, this character", XP per hour, quests, deaths, time by activity, a bar per level with the median line, legend, the check box "Show the review at level 10, 20 and 30", "All values" and "Close", "Braindead 4ever" in the footer; good to screenshot |
| 6 Review card at level 30, too few runs | `/bd4 preview recap30` | the same card with "collecting data (6 of 10 runs)" and no "faster than" line; best time of another character (race and class named) |

## 3. Blizzard's quest tracker (Welle 5b, owner reading points 15 and 16)

Whether the watch calls and the tracker's alpha from addon code cause taint is unconfirmed; this check settles it. The module turns itself off when the game blocks one of its calls (`/bd4 status` shows `questwatch` with the reason).

1. Before logging in: `/console taintLog 2` in the chat once (stays set), then `/reload`.
2. Accept three quests, mark one of them in the quest log yourself (shift-click or the check box) and note which ones Blizzard's tracker shows.
3. Settings, Display, "Blizzard's quest tracker":
   - "Hidden" (default since Welle 5c): the tracker disappears while Braindead 4ever guides and the step window stands in its place; quests you marked yourself stay in the list. A player who never changed the option before Welle 5c gets this default too; one who chose "Unchanged" or "Hidden" keeps it.
   - "Only quests of the route": quests the route does not know leave the tracker, your own mark stays; a newly accepted quest off the route leaves it again within a second.
   - "Unchanged": the marks from step 2 come back, plus what you marked or removed meanwhile.
4. Right-click menu, "Pause guidance": the tracker shows again with the marks from step 2; "Resume guidance" applies the option again.
5. Do the same once in a fight: nothing changes until the fight ends.
6. `/reload`, then open `World of Warcraft/_retail_/Logs/taint.log`: lines naming `Braindead4Ever` together with `ObjectiveTracker`, `QuestWatch` or `blocked` are the finding; copy them into the report. No such line: the check passed.
7. Turn Braindead 4ever off in the AddOns list and log in: the tracker shows the marks from step 2 (Braindead 4ever puts them back at every logout).

## 3a. Replanning in the live route (Welle 7)

In Retail the Forever quests are missing, so the live route cannot be checked there; these checks wait for the Forever client. In Forever:

1. New character: turn Braindead 4ever off in the AddOns list, play a few quests of the start zone in your own order and leave one out, then turn Braindead 4ever on and log in: the route stands at the step after the furthest quest you handed in or made progress on, not at the start. Hover the XP line: the quest you left out is listed as "skipped earlier".
2. Take a breadcrumb quest that leads to a later zone and keep it in the log, then `/reload`: the route does not jump ahead to that zone.
3. Grind three levels above the plan of the current quest step: the banner asks "You are 3 levels above the plan. Adjust the route?" once; "Adjust" leaves out the quests under 80 % XP, the right-click menu can undo it.
4. Grind on until the route reaches a travel step into a new zone: it stops there and offers the block that fits ("Go there", "Keep route"); in a fight no new banner appears.
5. Skip a quest in the middle of a zone, then stand still a moment: the next steps may change their order (only when the way gets at least 5 % shorter); in a fight nothing changes until it ends. `/reload` keeps the order; undo of the skip brings the plan order back.
6. Profiling: with `C_AddOnProfiler` (or `/bd4 probe run`) the route module stays under 0.1 ms per frame on average during steps 3 to 5.

## 3b. Your run in the live game (Welle 8)

Retail lacks the Forever quests, so these checks wait for the Forever client; steps 1 to 3 work in Retail too.

1. `/bd4 stats`, the right-click menu "Your run" and the minimap button's right-click menu open the page; `/bd4 stats` again closes it. After a login nothing opens by itself.
2. Start a fight, then type `/bd4 stats`: nothing opens until the fight ends, then the page comes.
3. Walk, fight and take a flight for a while, then level up: the level's tooltip splits the time into fighting, moving, flying and other, and XP into quests, enemies and other. A flight path counts as flying; standing at a quest giver counts as other.
4. Reach level 10 (or 20, 30) out of a fight: about three seconds after the level-up the review card opens once. Close it, `/reload`, change the zone: it does not come again. Reach the next of these levels inside a dungeon: the card waits until you leave it.
5. Turn "Show the review at level 10, 20 and 30" off (on the card or settings, Display): the next of these levels brings no card.
6. Profiling: with `C_AddOnProfiler` (or `/bd4 probe run`) the modules `stats` and `statspage` stay at 0 per frame while the page is closed; with the page open the first second costs most, then nothing.

## 4. Moving the windows (Welle 5c, owner readings 16 and 17)

Start from the default: settings, Display, "Reset" (positions and size).

1. Default place: the step window stands top right where Blizzard's quest tracker stood, below the minimap and left of the two right action bars, with a gap to both. Turn the two right bars (action bars 4 and 5) on and off in Blizzard's settings and `/reload`: the window never reaches into them, also not with one of them off. Repeat at a second resolution or UI scale.
2. Set "Blizzard's quest tracker" to "Only quests of the route": the tracker shows and the window moves left of it without overlap. "Hidden" puts it back.
3. Drag the window by its header band (the gold title band) with the left mouse button: it follows; after `/reload` it is where you left it, and step 1 and 2 no longer move it. Dragging the step text or the list does nothing; right-click still opens the menu and the check box still works.
4. Settings, Display, "Lock window" on: the header band no longer drags. Off again: it does.
5. Edit Mode (Esc, Edit Mode): both windows show a gold tint with their name ("Braindead 4ever: step window", "Braindead 4ever: arrow") and can be dragged, also with "Lock window" on; closing Edit Mode removes the tint. This proves Blizzard fires `EditMode.Enter` and `EditMode.Exit` in this client (wow-ui-source `Blizzard_EditMode/Shared/EditModeManager.lua`, `EditModeManagerFrameMixin:EnterEditMode` and `:ExitEditMode`: live 12.1.5 lines 100 and 119, forever 1.60.1 lines 105 and 124). No tint appears: report it with `/bd4 status`.
6. Arrow: without a key it lets clicks through to the world. Hold Shift and drag it; release Shift and it is click-free again.
7. In a fight: neither window moves, not by the header, not with Shift, not in Edit Mode. A drag that runs when the fight starts stops there and keeps the place.
8. Edit Mode, drag bar 6 (MultiBar5) to the right edge left of the right bars, close Edit Mode: after "Reset" the window keeps a gap to it too.

## 4a. Key bindings, TomTom, hardcore-safe mode (Welle 9)

1. Blizzard settings, Keybindings: a section "Braindead 4ever" lists seven actions (guidance on/off, check off step, skip step, step back, step window on/off, mini view, your run), all unbound. Bind two of them, press them in and out of a fight: the same as the window's buttons, and no "action blocked" message.
2. With TomTom installed (release gate T20): a TomTom waypoint stands on the current goal, without a TomTom chat line; it moves with the next step and goes on pause. Settings, Arrow and Map: "Hand the goal to TomTom" off removes it. Without TomTom the option is not there.
3. Settings, Play style, "Hardcore-safe": "Always". A quest 3 or more levels above the character shows a gold "Careful: …" line under the step; no optional dungeon step.

## 4b. Optional automation (requirement A74)

The route uses Forever quest IDs; the old Elwynn quests have the same IDs in Retail, so a new human character in Northshire can check most of it. Turn on "Automate route quests" (settings, main page) and `/console taintLog 1`.

1. Talk to the giver of the current step: the route quest is accepted without a click; a quest the route does not take, or takes only later, stays in the list for you.
2. Hand in a route quest with one reward or none: it is handed in at once. With several rewards the reward page stays open and you choose.
3. Hold Shift while you talk to the giver: nothing happens in this dialog, also after you let go. The next dialog works again.
4. In a fight nothing happens; after it the next dialog works.
5. A gossip NPC with a route quest and other options (vendor, flight master): only the quest line is chosen, never another option.
6. Forever client: the same with the gamepad interface. When the log is full, the dialog stays open and the gamepad buttons still work; no repeated pop-ups.
7. Afterwards `/bd4 status` shows `auto` on; the taint log names no blocked call of Braindead 4ever.

## 5. Situations per screenshot

Concept §2.12 asks for these situations; take the views of section 2 in them:

- light and dark ground (snow or desert, and a cave or night),
- next to a quest giver and in a fight,
- size 75 % and 200 % (settings, main page, "Size"), and Blizzard's text size at its largest (Blizzard settings, Accessibility),
- German and English client (Battle.net launcher, game settings, text language),
- window and arrow moved (section 4; "Reset" on the settings page Display).

Screenshots land in `World of Warcraft/_retail_/Screenshots/` (key: Print). A name per view helps, for example `1-normal-de-light.jpg`.

## 6. If something breaks

- `/bd4 status` lists every module; a module that turned off shows its reason.
- `/bd4 report` opens the copyable problem report (also in the right-click menu), with missing atlases if the client lacks one.
- Lua errors: BugSack, or `/console scriptErrors 1`.
