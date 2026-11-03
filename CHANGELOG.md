# Braindead 4ever

<!--
Release notes. The packager uses this file for every upload (manual-changelog in .pkgmeta).
Before a tag: give the top section the version and the date, newest section on top, in English.
After renamed or deleted files add:
"Restart the game client completely after this update, /reload is not enough."
Keep "Known issues" current. Hotfix steps: CONTRIBUTING.md, "Hotfix".
-->

## 0.9.0 (2026-11-03)

- Step-by-step routes for levels 1 to 30, both factions, all races and classes; levels 30 to 60 follow with updates.
- Step window, arrow, map and minimap pins, first start, settings in English and German.
- Page "Your run" with your times per level and the comparison with your class.
- Hardcore-safe mode: warnings for elite quests and quests 3 or more levels above you, no dungeon hints.
- Key bindings (unbound by default), TomTom hand-over when TomTom is installed, version notice.

## Known issues

- The routes are computed from open data and not played yet; every section is marked as provisional until our own runs replace it.
- Braindead 4ever could not be tested in the Forever client before the start. If a part fails, it turns off and the rest keeps running; after two failed starts the safe mode keeps the core running.
