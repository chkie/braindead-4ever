# Braindead 4ever

Braindead 4ever is a free leveling guide addon for World of Warcraft: Forever. Its working title was Pathmark. The routes cover levels 1 to 30; levels 30 to 60 follow with updates.

**Status:** early development. There is no release yet, and the addon does not guide you anywhere so far.

[Deutsch weiter unten](#deutsch)

## What it is for

- Step-by-step routes from level 1 to 30 for both factions, free of charge with no paid tier. Routes from level 30 to 60 follow with updates.
- Every step shows where its data comes from. Data taken from other open projects starts out as unconfirmed and is replaced as soon as our own in-game measurements cover it.
- English and German from the start.

## How it is built

Braindead 4ever is developed with AI assistance (Claude by Anthropic). Every change has to pass automated tests, linting, a type check, a format check and a secret scan before it can be merged. Features are tested in the game client before a release. The addon itself contains no AI.

Quest IDs, coordinates and times never come from an AI model. Each value carries its source.

## Data contribution

Braindead 4ever records what you do while leveling, in your own game folder: quests accepted and turned in with their place, experience, objects you loot, rare enemies, flight masters, the flights you take and similar finds. Nothing in it names your character, your realm, your guild or other players, and there is no chat. Time is kept relative to the session, the date only as a day.

What you discover, Braindead 4ever shares in the game with other players who use it, through addon messages: IDs and map positions only, to your group at once, to your guild and other players 30 to 90 seconds later. This is part of the addon and cannot be switched off. Addon messages show the game's sender name to the receiving addon; Braindead 4ever never stores it.

Braindead 4ever also shares how long each level and each route part took you: active seconds, experience, race and class as numbers, whether you followed the route, the level and the day. These run times carry a random token that Braindead 4ever rolls once per character and derives from nothing else; it only serves to count each level of a character once. Other copies of Braindead 4ever keep them and pass them on, so the routes can be measured against real play ([format](docs/RUN-TIMES.md)). The page "Your run" (right-click menu, `/bd4 stats`) shows your own times per level and, once at least ten runs of your class have reached you, their median and where you stand ([details](docs/RUN-STATS.md)).

Braindead 4ever tells other players which version of it you run (to your group, your guild and the hidden channel, once per session), so it can say when a newer version is out.

`/bd4 export` shows your data as a text to copy, for the website that comes later. `/bd4 report` builds a problem report without names.

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

---

## Deutsch

Braindead 4ever ist ein kostenloser Leveling-Guide für World of Warcraft: Forever. Sein Arbeitstitel war Pathmark. Die Routen reichen von Stufe 1 bis 30; Stufe 30 bis 60 folgt mit Updates.

**Stand:** frühe Entwicklung. Es gibt noch keine Veröffentlichung, und das Addon führt noch nirgendwohin.

### Wofür es gedacht ist

- Routen Schritt für Schritt von Stufe 1 bis 30 für beide Fraktionen, kostenlos und ohne Bezahlstufe. Routen von Stufe 30 bis 60 folgen mit Updates.
- Jeder Schritt zeigt, woher seine Daten stammen. Daten aus anderen offenen Projekten gelten zunächst als unbestätigt und werden ersetzt, sobald eigene Messungen im Spiel sie abdecken.
- Deutsch und Englisch von Anfang an.

### Wie es entsteht

Braindead 4ever wird mit KI-Unterstützung entwickelt (Claude von Anthropic). Jede Änderung muss vor dem Zusammenführen automatische Tests, Linter, Typprüfung, Formatprüfung und einen Scan auf Zugangsdaten bestehen. Funktionen werden vor einer Veröffentlichung im Spiel getestet. Das Addon selbst enthält keine KI.

Quest-IDs, Koordinaten und Zeiten stammen nie aus einem KI-Modell. Jede Angabe trägt ihre Quelle.

### Datenbeitrag

Braindead 4ever zeichnet beim Leveln in deinem eigenen Spielordner auf, was du tust: angenommene und abgegebene Quests mit ihrem Ort, Erfahrung, geplünderte Objekte, seltene Gegner, Flugmeister und ähnliche Funde. Darin steht kein Name deines Charakters, deines Realms, deiner Gilde oder anderer Spieler, und kein Chat. Zeiten zählen relativ zur Sitzung, das Datum nur als Tag.

Was du entdeckst, teilt Braindead 4ever im Spiel mit anderen Spielern, die es auch nutzen, über Addon-Nachrichten: nur Kennungen und Kartenpositionen, an deine Gruppe sofort, an deine Gilde und andere Spieler 30 bis 90 Sekunden später. Das gehört zum Addon und lässt sich nicht ausschalten. Addon-Nachrichten zeigen dem empfangenden Addon den Absendernamen des Spiels; Braindead 4ever speichert ihn nie.

Braindead 4ever teilt außerdem, wie lange du für jede Stufe und jeden Routenabschnitt gebraucht hast: aktive Sekunden, Erfahrung, Volk und Klasse als Zahl, ob du der Route gefolgt bist, die Stufe und den Tag. Diese Spielzeiten tragen eine zufällige Kennung, die Braindead 4ever einmal je Charakter würfelt und aus nichts anderem ableitet; sie dient nur dazu, jede Stufe eines Charakters einmal zu zählen. Andere Braindead-Forever-Installationen bewahren sie auf und geben sie weiter, damit sich die Routen am echten Spiel messen lassen ([Format](docs/RUN-TIMES.md)). Die Seite „Dein Lauf“ (Rechtsklickmenü, `/bd4 stats`) zeigt deine eigenen Zeiten je Stufe und, sobald mindestens zehn Läufe deiner Klasse bei dir angekommen sind, deren Median und wo du stehst ([Details](docs/RUN-STATS.md)).

Braindead 4ever sagt anderen Spielern, welche Version davon du nutzt (deiner Gruppe, deiner Gilde und dem versteckten Kanal, einmal je Sitzung), damit es dir sagen kann, wenn es eine neuere gibt.

`/bd4 export` zeigt deine Daten als Text zum Kopieren, für die Website, die später kommt. `/bd4 report` erstellt einen Fehlerbericht ohne Namen.

### Lizenz

GPL-3.0-or-later mit einer Zusatzerlaubnis für die Ace3-Bibliotheken, siehe [LICENSE](LICENSE) und [LICENSE-EXCEPTION.md](LICENSE-EXCEPTION.md).

Die Routendateien in `data/routes` sind die Quellform der kompilierten Routendaten in `Braindead4Ever/Routes/Data_*.lua`; alles, was man braucht, um sie daraus neu zu erzeugen, liegt in diesem Repository. Die Werkzeuge, mit denen die Routen geplant und vermessen werden, liegen außerhalb.

World of Warcraft, Warcraft und Blizzard Entertainment sind Marken oder eingetragene Marken von Blizzard Entertainment, Inc. in den USA und/oder anderen Ländern. Braindead 4ever ist nicht mit Blizzard Entertainment verbunden und wird nicht von Blizzard Entertainment unterstützt.
