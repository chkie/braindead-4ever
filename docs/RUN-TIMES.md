# Run times in the exchange

Every installation measures how long its character takes for each level and each route module and shares that in the game. Every installation also keeps the run times it hears and passes them on, so one export brings the runs of many players. After the start this measures how fast the route is in real play, apart for players who follow it and players who play freely (plan "Laufzeiten im Austausch", 2026-11-02). Data contribution is part of the addon; there is no switch.

The page "Your run" compares the player's own levels and sections with the vault's runs of the same class ([RUN-STATS.md](RUN-STATS.md)), so the shared times bring every player something back.

Code: `Collector/Runs.lua` (vault, checks, relaying), `Collector/Proto.lua` (message), `Collector/Collect.lua` (`RecordRun`, export), `Collector/Exchange.lua` (receiving, relaying), `Collector/Budget.lua` (channel budget), `Routes/Guide.lua` (sections). Tests: `spec/runs_spec.lua`, `spec/channel_budget_spec.lua`, `tools/tests/test_runs.py`.

## Message `s`

One section per addon message, printable ASCII, fields separated by `;`, at most 255 bytes (the longest possible message has 78):

```
s;1;<token>;<race>;<class>;<mode>;<kind>;<section>;<version>;<seconds>;<xp>;<in order>;<level>;<day>
s;1;k3x9qa;1;1;s;l;5;0;1840;2800;100;6;20762
```

| Field | Values | Meaning |
| --- | --- | --- |
| token | six characters `0-9a-z` | rolled once per character (`BraindeadForeverCharDB.run`), from nothing else; only for one value per section and character |
| race, class | IDs | `UnitRace` and `UnitClass`, third return value |
| mode | `s`, `e`, `f` | speed route, explorer route, free play |
| kind | `l`, `m` | a level or a route module |
| section | number | the level played through, or the module number (below) |
| version | number | version of the module, 0 for levels |
| seconds | 1 or more | active play: gaps between game events count up to 5 minutes |
| xp | 0 or more | experience gained in the section |
| in order | 0 to 100 | share of the section's route steps that were done, the rest was skipped or passed |
| level | 1 to 100 | character level at the end of the section |
| day | number | server day (`GetServerTime() / 86400`), no time of day |

Messages carry no names, realms, GUIDs, the installation ID or the character ID. Readers that do not know `s` skip it without counting it as broken.

**Module number.** Messages carry no text, so a module key goes out as `djb2(key) mod 9999991 + 1` (`Proto.ModuleNumber`, `tools/routekit/runs.py` `module_number`). `tools/tests/test_runs.py` checks that all route modules have different numbers; `tools/tests/fixtures/module_numbers.json` holds cases both languages must agree on.

## Sections

- **Level:** from one level-up to the next. A level counts only when it started at a level-up, or at level 1 without XP; the level the addon first sees halfway is never reported. The seconds are saved per character and survive a /reload; a level-up seen twice reports once.
- **Module:** a run from the module's first step past its last step. It also goes out when steps were skipped; the share of done steps says how closely the player followed. The clean `split` record for the time forecast stays as it was.
- **Mode:** the route mode when the route existed, the step window was on and the guidance was not paused for at least half of the section's active seconds; otherwise `f`. Without a route for race and class every section is `f`.
- **In order:** for a module the done steps of the module; for a level the steps the route passed during the level, of which the done ones (0 when it passed none).

Each own section is written as record `run` (same fields from the token on, after kind, dt and three empty position fields), stored in the vault and sent like a find: to the group at once, to guild and channel 30 to 90 s later.

## Run vault

`BraindeadForeverCollectDB.runs`, beside the buffer of received finds, so neither pushes the other out.

- At most 5000 sections; the oldest give way first.
- One section per (token, kind, section). The same text again is a duplicate. A different text for the same key drops the stored one too and blocks the key (at most 2000 blocked keys, then the list starts over). Own sections stay with their owner.
- Plausibility band (brain chapter 21 §3.4): seconds at most 48 h; a level at least 60 s, a module at least 20 s; XP per hour at most 1.5 times the solo self-found record pace of Classic Era (speedrun.com): 1 to 20 in 5:02:59 (33,111 XP/h, limit 49,666) below level 20, 1 to 60 in 44:39:29 (91,466 XP/h, limit 137,199) from level 20. A level counts at least the XP of the Classic curve for that level, whatever the message says. A level section ends above its level; a day in the future is dropped.
- Per sender and session: at most 40 run messages in 5 minutes, at most 150 tokens the sender brings in that this client did not know (its originals). A sender over a limit is muted for run times in that session; its finds are not affected. Sender names live in session tables only.

## Relaying

Each session (login or /reload) every section of the vault may go out once, over the hidden channel only: own sections first, then the newest. A section heard on the channel in this session is not relayed, because everybody online heard it already. Sections from the group or the guild join the list, because the channel has not heard them. The exchange asks for one section per second and relays one per 10 s at most, only while no own message is due for the channel and the queue is less than half full, and only with a credit of the channel budget (below). Nothing is relayed in a fight or in an instance.

## Channel budget

Every message on the hidden channel reaches every player in it. Without a limit, what each player receives grows with the number of players: the first spread simulation (200 clients) had every client receive about one message per second, and 5,000 players online in one channel would have meant about 100 per second. The owner set the limits on 2026-11-02 ("so rare that there are really no performance problems, that Blizzard does not complain, the addon must stay lean"):

- A client receives at most 0.5 channel messages per second on average and at most 1 per second in any 60 s, for 100, 1,000, 5,000 and 20,000 players.
- Receiving costs next to nothing; reading happens in slices outside fights and instances and not at a low frame rate.
- Relays go out only outside fights and instances.

The budget covers both kinds of channel messages, run sections and finds. The version notice (message `a`, Welle 9: major, minor, patch, pre-release flag; once per session on the channel) needs a credit of the finds pool like a find, so it adds nothing to the channel's traffic. Flight legs (message `h`, Welle 11, [ROUTE-FORMAT.md](ROUTE-FORMAT.md) §Flights in the exchange) need a credit of the finds pool too, relays only while no own find is waiting; the spread simulation with them is in `spec/flights_spec.lua`. Group and guild are not part of it.

**Estimate of the players** (`Collector/Budget.lua`). Each client estimates how many players send on the channel and takes only its share of a fixed total: `SHARE[pool] / estimate` messages per second for runs (0.15 in total) and finds (0.1 in total). The estimate is an upper bound, the smaller of two:

- **Repeats:** of the players heard in the last hour, how many were heard at least twice. If every player sends a Poisson number of messages, the share of repeated players fixes the messages per player and with it the number of players. The bound takes the low end of a one-sided 90 % interval for the repeats (Wilson-Hilferty), so it errs towards more players. No repeat at all means 20,000 players (`SENDERS_MAX`). A player counts once however much it sends, so a flooding sender moves the estimate by one repeat at most.
- **Traffic:** every client sends at least `SHARE / SENDERS_MAX` per second, so the channel's messages per second times `SENDERS_MAX / SHARE` bound the players from above (90 % end of the Poisson interval). This gets a quiet channel going: there, repeats would take hours.

Credits come at random moments (a Poisson process of the client's rate); a pool holds at most one, and a channel message takes one. Run messages wait for a credit, finds wait 60 s and are then left off the channel. A hard stop sits on top: when 30 channel messages arrived in the last 60 s, nobody sends and held credits are dropped. In the simulation the estimate alone keeps the limits; without the stop the results are the same (most in 60 s: 31 instead of 30 at 5,000 clients).

**Member count of the channel.** Forever has `GetChannelDisplayInfo` (with a count), `GetNumChannelMembers` and the event `CHANNEL_COUNT_UPDATE` (Ketho BlizzardInterfaceResources, branch forever, `Resources/GlobalAPI.lua` and `Events.lua`, read 2026-11-02). Blizzard's channel pane shows the count only for group channels and fills it after `SetSelectedDisplayChannel` asks the server for the roster (wow-ui-source forever ca8368f, `Blizzard_Channels/Mainline/ChannelFrame.lua`, `ChannelList.lua`); `GetNumChannelMembers` has no documentation. Asking for the roster of a channel with thousands of players would load the server and change the player's channel pane, so the estimate uses the messages only. Sender names stay in memory for the hour of the window and are never saved.

**Receiving.** `CHAT_MSG_ADDON` checks the prefix and puts the raw text with its arrival time into one of two inboxes (channel; group and guild), 100 messages each, the oldest give way. The exchange's one-second ticker reads at most 10 messages and at most 1 ms per second, and only when the player is not fighting, not in an instance and the frame rate is at least 20 (ChatThrottleLib's floor). The estimate takes each message at its arrival time. While the channel inbox holds unread messages, nothing goes on the channel.

**Spread simulation** (`spec/helpers/spread.lua`, run by `spec/channel_budget_spec.lua`): clients with the real `Proto.lua`, `Runs.lua` and `Budget.lua` in one channel; 10 rounds of 4 hours; in each round a client starts one session with probability 0.5, 1 to 3 hours long, at any moment (sessions run on into the next round); one own section per 30 minutes of play, due 30 to 90 s later; every client always has a find waiting. Received means channel messages while online, without the client's own. Reach: the share of other players' sections that reached one exporting client (heard on the channel while it was online) within n rounds after the end of the round they were made in, mean over 10 exporters. Seed 20261102:

| Clients | Online on average | Received per client and s, mean | Busiest client | Most in 60 s | Own sections on the channel | Reach after 1 round | 2 | 5 | 9 | Sections one exporter collected in 10 rounds |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 100 | 22 | 0.137 | 0.159 | 24 | 96 % | 0.290 | 0.493 | 0.873 | 0.969 | 1,122 |
| 1,000 | 230 | 0.174 | 0.190 | 26 | 60 % | 0.133 | 0.154 | 0.202 | 0.366 | 3,068 |
| 5,000 | 1,136 | 0.186 | 0.233 | 30 | 16 % | 0.034 | 0.042 | 0.051 | 0.075 | 3,821 |
| 20,000 | 4,552 | 0.153 | 0.249 | 29 | 3 % | 0.006 | 0.008 | 0.010 | 0.016 | 2,855 |

Limits 0.5 and 60 hold with room at every size; seeds 3, 4 and 5 gave at most 0.181 on average, 0.251 for the busiest client and 30 in 60 s. The estimate was on average 1.3 to 1.6 times the players online (it also counts players who left within the hour). The price is reach: with many players most sections never reach the channel, and one exporter collects a sample of roughly 3,000 sections in 10 rounds, whatever the number of players (seeds 3 to 5: 2,780 to 3,754 from 1,000 players on).

Counter-check without budget (the clients send as before the budget, one round so it stays short): 1,000 clients receive 3.79 messages per second on average and up to 311 in 60 s, without counting the relays that start in later rounds.

Simplifications, so that 20,000 clients run in about 25 s: clients older than an hour hear the same channel and share one estimate; younger ones share one per login minute. Above 100 clients only the exporters' vaults hear the channel; the others relay their own sections only. Checked against the exact model: one estimate per login second at 1,000 clients gave reach 0.379 instead of 0.370 after 9 rounds; every vault hearing gave 0.370 instead of 0.366 at 1,000 clients and 0.073 instead of 0.075 at 5,000. The model values are chosen; how many players share a channel in Forever, and whether channels are split by faction, is measured in the game from 2026-11-05.

**Cost** (`spec/channel_budget_spec.lua`, Lua 5.1 on the development machine, not in the game): the event costs 0.5 µs per message, reading 13 µs (parsing, estimate, vault or find buffer). At the limit of 0.5 messages per second that is 0.11 µs per frame at 60 frames per second, 0.11 % of the addon's 0.1 ms. Memory: two full inboxes 21 KB, a full estimate window (2,000 messages from different players) 226 KB, a full run vault of 5,000 sections 1,562 KB in the running game (the texts alone 215 KB), together 1.8 MB of the 10 MB budget; the vault is most of it.

## Export and analysis

The PM1 export (`/bd4 export`) carries the vault's sections not exported yet under the key `runs`, as message texts. `node decoder/cli.mjs --runs < export.txt` writes the run table as CSV:

```
token,race,class,mode,kind,section,version,seconds,xp,in_order,level,day,source
```

`source` is `own` for the exporting player's own `run` records and `net` for the vault; one row per token, kind and section, conflicting values drop both. `python3 -m tools.routekit runs CSV... [--json OUT]` gives the median seconds and XP per hour per section, class, mode and group: **follows** (mode `s` or `e`, at least 80 % in order), **free** (mode `f`) and **partial** (the rest). Module numbers are mapped back to their keys from `data/routes`.

## Chosen values

| Value | Where | Setting |
| --- | --- | --- |
| Vault size | `Runs.VAULT_MAX` | 5000 sections |
| Relay gap | `Runs.RELAY_GAP` | 10 s |
| Run messages per sender | `Runs.SENDER_MAX`, `Runs.SENDER_WINDOW` | 40 in 300 s |
| New tokens per sender and session | `Runs.NEW_TOKENS_MAX` | 150 (simulation peak before the channel budget 66, 76 over four more seeds) |
| Blocked keys | `Runs.BLOCKED_MAX` | 2000 |
| Shortest level, module | `Runs.MIN_LEVEL_SECS`, `Runs.MIN_MODULE_SECS` | 60 s, 20 s |
| Longest section | `Runs.MAX_SECS` | 48 h |
| Margin over the record pace | `Runs.RECORD_MARGIN` | 1.5 |
| Guided share for the route mode | `Routes/Guide.lua` `ModeOf` | half of the active seconds |
| Following the route | `tools/routekit/runs.py` `FOLLOW_MIN` | 80 % in order |
| Channel shares | `Budget.SHARE` | runs 0.15, finds 0.1 messages per second on the whole channel (half of the owner's 0.5) |
| Estimate window | `Budget.WINDOW` | 3600 s |
| Most players assumed | `Budget.SENDERS_MAX` | 20,000 (largest size simulated) |
| Confidence of the bounds | `Budget.Z` | one-sided 90 % |
| Estimate reused for | `Budget.REFRESH` | 30 s |
| Hard stop | `Budget.BUSY` | 30 channel messages in 60 s |
| Remembered channel messages | `Budget.EVENTS_MAX` | 2000 |
| Find waits for the channel | `Exchange.FIND_WAIT` | 60 s |
| Inbox | `Exchange.INBOX_MAX` | 100 messages each for channel and for group and guild |
| Reading per second | `Exchange.SLICE`, `Exchange.SLICE_MS` | 10 messages, 1 ms |
| Lowest frame rate for reading | `Exchange.MIN_FPS` | 20 |
