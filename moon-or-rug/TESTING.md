# Moon or Rug – Test in Roblox Studio (Checkliste)

Kurz und der Reihe nach. Wenn etwas nicht geht: **Screenshot vom Output-Fenster** (rote Zeilen) + was du gedrückt hast.

## 1. Vorbereiten (einmal)

- [ ] Neue Place in Studio öffnen (am besten eine **eigene Test-Place**, nicht das echte Spiel).
- [ ] In ReplicatedStorage einen Ordner **Shared**, in ServerScriptService die Ordner **Services** und **Util**,
      in StarterPlayer › StarterPlayerScripts einen Ordner **ClientModules** anlegen.
- [ ] Jede Datei aus `moon-or-rug/src/` als Script einfügen – **Name und Typ** stehen in `PROGRESS.md`
      (Tabelle „So kommen die Dateien nach Studio“). Wichtig: `Main` = **Script**, `ClientMain` = **LocalScript**,
      alles andere = **ModuleScript**. Name ohne `.luau`.
- [ ] Output-Fenster öffnen (Ansicht › Output).
- [ ] Erst **ohne** API-Zugriff testen (lokaler Testmodus, nichts wird gespeichert).
      Später: Spieleinstellungen › Sicherheit › „Studio-Zugriff auf API-Dienste“ an (dann wird gespeichert).

## 2. Start

- [ ] Play drücken. Im Output steht `[MoonOrRug] Server ready`.
- [ ] Vollbild-Terminal, kein Avatar. Oben: Logo bzw. 🚀 + **ADMIN**, Tabs, 🛒, 🎁, Cash.
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
