# Pathmark

Pathmark (working title) is a free leveling guide addon for World of Warcraft: Forever, levels 1 to 60.

**Status:** early development. There is no release yet, and the addon does not guide you anywhere so far.

[Deutsch weiter unten](#deutsch)

## What it is for

- Step-by-step routes from level 1 to 60 for both factions, free of charge with no paid tier.
- Every step shows where its data comes from. Data taken from other open projects starts out as unconfirmed and is replaced as soon as our own in-game measurements cover it.
- English and German from the start.

## How it is built

Pathmark is developed with AI assistance (Claude by Anthropic). Every change has to pass automated tests, linting, a type check, a format check and a secret scan before it can be merged. Features are tested in the game client before a release. The addon itself contains no AI.

Quest IDs, coordinates and times never come from an AI model. Each value carries its source.

## Data contribution

Pathmark records what you do while leveling, in your own game folder: quests accepted and turned in with their place, experience, objects you loot, rare enemies, flight masters and similar finds. Nothing in it names your character, your realm, your guild or other players, and there is no chat. Time is kept relative to the session, the date only as a day.

What you discover, Pathmark shares in the game with other players who use it, through addon messages: IDs and map positions only, to your group at once, to your guild and other players 30 to 90 seconds later. This is part of the addon and cannot be switched off. Addon messages show the game's sender name to the receiving addon; Pathmark never stores it.

`/pathmark export` shows your data as a text to copy, for the website that comes later. `/pathmark report` builds a problem report without names.

## Repository layout

| Path | Content |
| --- | --- |
| `Pathmark/` | the addon as it goes into `Interface/AddOns` |
| `spec/` | offline tests (busted, Lua 5.1) with stand-ins for the WoW API |
| `types/` | type stubs for the Lua Language Server |
| `docs/STATUS.md` | every feature with its status and the probe checks it needs |
| `decoder/` | reads an export text in the browser or in Node |
| `scripts/` | local setup and checks |

How to set up the tools and run the checks: [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-or-later with an additional permission for the Ace3 libraries, see [LICENSE](LICENSE) and [LICENSE-EXCEPTION.md](LICENSE-EXCEPTION.md).

World of Warcraft, Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. in the U.S. and/or other countries. Pathmark is not affiliated with or endorsed by Blizzard Entertainment.

---

## Deutsch

Pathmark (Arbeitstitel) ist ein kostenloser Leveling-Guide für World of Warcraft: Forever, Stufe 1 bis 60.

**Stand:** frühe Entwicklung. Es gibt noch keine Veröffentlichung, und das Addon führt noch nirgendwohin.

### Wofür es gedacht ist

- Routen Schritt für Schritt von Stufe 1 bis 60 für beide Fraktionen, kostenlos und ohne Bezahlstufe.
- Jeder Schritt zeigt, woher seine Daten stammen. Daten aus anderen offenen Projekten gelten zunächst als unbestätigt und werden ersetzt, sobald eigene Messungen im Spiel sie abdecken.
- Deutsch und Englisch von Anfang an.

### Wie es entsteht

Pathmark wird mit KI-Unterstützung entwickelt (Claude von Anthropic). Jede Änderung muss vor dem Zusammenführen automatische Tests, Linter, Typprüfung, Formatprüfung und einen Scan auf Zugangsdaten bestehen. Funktionen werden vor einer Veröffentlichung im Spiel getestet. Das Addon selbst enthält keine KI.

Quest-IDs, Koordinaten und Zeiten stammen nie aus einem KI-Modell. Jede Angabe trägt ihre Quelle.

### Datenbeitrag

Pathmark zeichnet beim Leveln in deinem eigenen Spielordner auf, was du tust: angenommene und abgegebene Quests mit ihrem Ort, Erfahrung, geplünderte Objekte, seltene Gegner, Flugmeister und ähnliche Funde. Darin steht kein Name deines Charakters, deines Realms, deiner Gilde oder anderer Spieler, und kein Chat. Zeiten zählen relativ zur Sitzung, das Datum nur als Tag.

Was du entdeckst, teilt Pathmark im Spiel mit anderen Spielern, die es auch nutzen, über Addon-Nachrichten: nur Kennungen und Kartenpositionen, an deine Gruppe sofort, an deine Gilde und andere Spieler 30 bis 90 Sekunden später. Das gehört zum Addon und lässt sich nicht ausschalten. Addon-Nachrichten zeigen dem empfangenden Addon den Absendernamen des Spiels; Pathmark speichert ihn nie.

`/pathmark export` zeigt deine Daten als Text zum Kopieren, für die Website, die später kommt. `/pathmark report` erstellt einen Fehlerbericht ohne Namen.

### Lizenz

GPL-3.0-or-later mit einer Zusatzerlaubnis für die Ace3-Bibliotheken, siehe [LICENSE](LICENSE) und [LICENSE-EXCEPTION.md](LICENSE-EXCEPTION.md).

World of Warcraft, Warcraft und Blizzard Entertainment sind Marken oder eingetragene Marken von Blizzard Entertainment, Inc. in den USA und/oder anderen Ländern. Pathmark ist nicht mit Blizzard Entertainment verbunden und wird nicht von Blizzard Entertainment unterstützt.
