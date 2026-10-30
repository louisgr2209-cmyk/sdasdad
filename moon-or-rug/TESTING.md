# Moon or Rug – Test in Roblox Studio (Checkliste)

Kurz und der Reihe nach. Wenn etwas nicht geht: **Screenshot vom Output-Fenster** (rote Zeilen) + was du gedrückt hast.

## 1. Vorbereiten (einmal)

- [ ] Neue Place in Studio öffnen (am besten eine **eigene Test-Place**, nicht das echte Spiel).
- [ ] `moon-or-rug/MoonOrRug.rbxmx` von GitHub herunterladen (Branch `moon-or-rug`).
- [ ] Im Explorer Rechtsklick auf **Workspace › „Insert from File…“** → die Datei wählen.
      Es erscheinen 3 Ordner mit allen Skripten (Namen und Typen stimmen schon).
- [ ] **Vor dem Play-Drücken** verschieben (ziehen):
      - Ordner `Shared` → in **ReplicatedStorage**
      - `Main`, `Services`, `Util` → in **ServerScriptService**
      - `ClientMain`, `ClientModules` → in **StarterPlayer › StarterPlayerScripts**
      - die 3 leeren Ordner im Workspace löschen.
- [ ] (Ohne Import-Datei geht es auch von Hand: Tabelle in `PROGRESS.md`.)
- [ ] Output-Fenster öffnen (Ansicht › Output).
- [ ] Erst **ohne** API-Zugriff testen (lokaler Testmodus, nichts wird gespeichert).
      Später: Spieleinstellungen › Sicherheit › „Studio-Zugriff auf API-Dienste“ an (dann wird gespeichert).

## 2. Start

- [ ] Play drücken. Im Output steht `[MoonOrRug] Server ready`.
- [ ] **Tutorial** (Pflicht): alles ist abgedunkelt außer der Aufgabe → Coin antippen → BUY → SELL ALL → „LET'S TRADE“.
      Ohne API-Zugriff wird nichts gespeichert, das Tutorial kommt dann bei jedem Play wieder (gewollt).
- [ ] Vollbild-Terminal, kein Avatar. Oben: Logo bzw. 🚀 + **ADMIN**, Tabs, 🛒, 🎁, Cash.
- [ ] Sounds: leiser Klick bei Knöpfen, Ping bei Erfolg. Im 🛒-Fenster oben „🔊 SOUND ON/OFF“.
- [ ] Nach ein paar Sekunden erscheinen NPC-Coins in PULSE, Ticker unten läuft.

## 3. Traden

- [ ] Coin antippen → Coin-Seite mit Chart und 4 Ampeln (antippen = Erklärung).
- [ ] BUY 10 % / SELL ALL → Meldung oben, Cash ändert sich, Coin im PORTFOLIO.
- [ ] Ganz schnell oft tippen → „Too fast“ statt Absturz.

## 4. Geräte (Studio: Test › Gerät-Emulator)

- [ ] iPhone mit Dynamic Island, Samsung, iPad, PC: **alles sichtbar**, nichts abgeschnitten, Knöpfe gut tippbar.

## 5. Schutz + Level

- [ ] 🎁 → Daily abholen. Rejoin → „Already claimed“.
- [ ] Level steigt beim Traden (ab 100 Cash Trade-Größe). Level-Up-Banner.
- [ ] Stop-Loss (ab Lv 3) und Versicherung (ab Lv 5) auf der Coin-Seite schalten.

## 6. Coin erstellen, Boost, Rug (mit Studio-Testkäufen geht es sofort)

- [ ] 🛒 → „Create a coin“ (Studio-Test = gratis Gutschein) → PULSE › CREATE → Formular → **CREATE (FREE)**.
- [ ] Eigener Coin hat 👨‍💻, BOOST-Knopf. 🛒 → Boost → BOOST drücken → BOOSTED-Leiste.
- [ ] 🛒 → Highlight → eigener Coin leuchtet in PULSE (✨).
- [ ] 🛒 → Rug pull license → nach 10 Min. Coin-Alter erscheint **☠ RUG** → drücken → „RUG PULL!“ im Ticker.
- [ ] Ohne Rug: eigenen Coin verkaufen → max. 25 % pro Minute.

## 7. Gamepässe (Studio-Test)

- [ ] 🛒 → Pro: 🕯-Knopf im Chart, Kachel „Top 10“ zeigt Namen, Dev-Trades mit 👨‍💻 DEV.
- [ ] 🛒 → VIP: türkiser Rahmen um die Wallet-Box, ⭐ im Namen.

## 8. Creator-Programm

- [ ] ADMIN → eigenen Roblox-Namen eingeben → Gold → GRANT → Meldung + Cash.
- [ ] 🎁 → eigenen Creator-Code wählen.

## 9. Speichern (nur mit API-Zugriff)

- [ ] Cash merken, Stop, Play → gleiches Cash, Coins noch da.

## Bekannt

- Im lokalen Testmodus gibt es nur einen Server und nichts wird gespeichert – das ist so gewollt.
- Mehrere Server (Weltmarkt) lassen sich nur im **veröffentlichten** Spiel testen (2 Geräte).
- Robux-Ids sind noch 0 → im echten Spiel steht „Coming soon“, bis sie in `Config.Shop` eingetragen sind.
