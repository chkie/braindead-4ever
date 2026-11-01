# Feature status

Every feature has one status: **planned**, **built** (code and offline tests pass), **verified in game** (checked in the WoW: Forever client) or **blocked**. German project documents use geplant, gebaut, im Spiel geprüft, blockiert.

Last update: 2026-11-01

## Core

| Feature | Status | Note |
| --- | --- | --- |
| TOC for Forever (`Pathmark_Camelot.toc`, interface 16001) | built | 16001 is the beta interface; check the live client on 2026-11-05 with `/dump select(4, GetBuildInfo())` |
| TOC for the Retail 12.1.5 test bed (`Pathmark.toc`, 120105 and 16001) | built | |
| Error buffer: first occurrence per session goes to the error handler, repeats are counted | built | `Core/Guard.lua` |
| Module turns off after 5 errors within 60 s | built | thresholds are chosen values, not measured |
| Modules declare required API functions and events, checked at login | built | `Core/Modules.lua` |
| Start guard: safe mode after two unclean starts, lifted by a new version | built | does not help after a client crash (SavedVariables are written on logout and `/reload` only) |
| Slash command `/pathmark` (status, safe, flag, errors, quiet) | built | |
| Texts in English and German | built | wording not approved yet |
| `Category` in the TOC (`Quests`) | built | value not checked against the in-game category list |

## Tooling

| Feature | Status | Note |
| --- | --- | --- |
| Offline tests (busted, Lua 5.1.5) with WoW API stand-ins | built | |
| luacheck, StyLua, LuaLS type check, gitleaks, actionlint | built | |
| CI on GitHub with required checks | planned | needs the public repository |
| Release by tag (BigWigs packager to CurseForge, Wago, GitHub) | planned | needs the CurseForge and Wago projects and their tokens |
