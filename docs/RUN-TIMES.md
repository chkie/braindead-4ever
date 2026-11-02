# Run times in the exchange

Every installation measures how long its character takes for each level and each route module and shares that in the game. Every installation also keeps the run times it hears and passes them on, so one export brings the runs of many players. After the start this measures how fast the route is in real play, apart for players who follow it and players who play freely (plan "Laufzeiten im Austausch", 2026-11-02). Data contribution is part of the addon; there is no switch.

Code: `Collector/Runs.lua` (vault, checks, relaying), `Collector/Proto.lua` (message), `Collector/Collect.lua` (`RecordRun`, export), `Collector/Exchange.lua` (receiving, relaying), `Routes/Guide.lua` (sections). Tests: `spec/runs_spec.lua`, `tools/tests/test_runs.py`.

## Message `s`

One section per addon message, printable ASCII, fields separated by `;`, at most 255 bytes (the longest possible message has 78):

```
s;1;<token>;<race>;<class>;<mode>;<kind>;<section>;<version>;<seconds>;<xp>;<in order>;<level>;<day>
s;1;k3x9qa;1;1;s;l;5;0;1840;2800;100;6;20762
```

| Field | Values | Meaning |
| --- | --- | --- |
| token | six characters `0-9a-z` | rolled once per character (`PathmarkCharDB.run`), from nothing else; only for one value per section and character |
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

`PathmarkCollectDB.runs`, beside the buffer of received finds, so neither pushes the other out.

- At most 5000 sections; the oldest give way first.
- One section per (token, kind, section). The same text again is a duplicate. A different text for the same key drops the stored one too and blocks the key (at most 2000 blocked keys, then the list starts over). Own sections stay with their owner.
- Plausibility band (brain chapter 21 §3.4): seconds at most 48 h; a level at least 60 s, a module at least 20 s; XP per hour at most 1.5 times the solo self-found record pace of Classic Era (speedrun.com): 1 to 20 in 5:02:59 (33,111 XP/h, limit 49,666) below level 20, 1 to 60 in 44:39:29 (91,466 XP/h, limit 137,199) from level 20. A level counts at least the XP of the Classic curve for that level, whatever the message says. A level section ends above its level; a day in the future is dropped.
- Per sender and session: at most 40 run messages in 5 minutes, at most 150 tokens the sender brings in that this client did not know (its originals). A sender over a limit is muted for run times in that session; its finds are not affected. Sender names live in session tables only.

## Relaying

Each session (login or /reload) every section of the vault may go out once, over the hidden channel only: own sections first, then the newest. A section heard on the channel in this session is not relayed, because everybody online heard it already. Sections from the group or the guild join the list, because the channel has not heard them. The exchange asks for one section per second, gets one per 10 s at most, and only while no own message is due for the channel and the queue is less than half full. The channel itself takes one message per 2 s, so relaying uses at most a fifth of it.

**Spread simulation** (`spec/helpers/spread.lua`, run by `spec/runs_spec.lua`): 200 clients with the real `Proto.lua` and `Runs.lua` in one channel; 10 rounds of 4 hours; in each round a client starts one session with probability 0.5, 1 to 3 hours long, at any moment (sessions run on into the next round); one own section per 30 minutes of play, sent 30 to 90 s later. Coverage is the share of all sections that existed when a session began which the client holds when it ends.

| Round | Sessions ended | Coverage min | Median | At least 90 % |
| --- | --- | --- | --- | --- |
| 3 | 90 | 0.865 | 0.989 | 98 % |
| 4 | 94 | 0.934 | 0.995 | 100 % |
| 6 | 90 | 0.948 | 0.997 | 100 % |
| 8 | 92 | 0.964 | 0.997 | 100 % |
| 10 | 97 | 0.966 | 0.997 | 100 % |

Traffic per client and online hour: 74 messages sent (72 of them relays), 3,369 received (about one per second); the busiest client sent 137 and received 5,248. Peaks per sender: 66 new tokens in a session, 31 run messages in 5 minutes. Seeds 3 to 6 gave the same picture: minimum from round 4 on between 0.908 and 0.986, up to 76 new tokens per sender. The model values are chosen; how many players share a channel in Forever, and whether channels are split by faction, is measured in the game from 2026-11-05.

## Export and analysis

The PM1 export (`/pathmark export`) carries the vault's sections not exported yet under the key `runs`, as message texts. `node decoder/cli.mjs --runs < export.txt` writes the run table as CSV:

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
| New tokens per sender and session | `Runs.NEW_TOKENS_MAX` | 150 (simulation peak 66, 76 over four more seeds) |
| Blocked keys | `Runs.BLOCKED_MAX` | 2000 |
| Shortest level, module | `Runs.MIN_LEVEL_SECS`, `Runs.MIN_MODULE_SECS` | 60 s, 20 s |
| Longest section | `Runs.MAX_SECS` | 48 h |
| Margin over the record pace | `Runs.RECORD_MARGIN` | 1.5 |
| Guided share for the route mode | `Routes/Guide.lua` `ModeOf` | half of the active seconds |
| Following the route | `tools/routekit/runs.py` `FOLLOW_MIN` | 80 % in order |
