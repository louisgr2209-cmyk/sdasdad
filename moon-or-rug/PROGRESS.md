# Moon or Rug 🚀 Meme Coin Trading – PROGRESS

Plan: „Moon or Rug – Memecoin-Spiel (Roblox)“ (einzige Quelle für Regeln & Zahlen).
Alle Werte (Preise, Level, Gebühren, UI-Größen) stehen in **`Config`** – nur dort anpassen.

## Entscheidungen (Schritt 0)

| Thema | Entscheidung |
|---|---|
| Code nach Studio | Von Hand kopieren (Ordner = Studio-Struktur) |
| Git | Branch `moon-or-rug`, alles im Ordner `moon-or-rug/` |
| Kurve | Gesamtmenge 1.000.000, P0 = 0,001, S = 100.000 |
| „Almost done“ | ab 50 % der Grenze (≥ 34.500 MCap) |
| Chart | 1 Punkt alle 5 Sek., 60 Punkte (= 5 Min.) |
| Sprache im Spiel | Englisch |
| Phase-1-Test | kleine Debug-UI |
| Leaderboard-UI | eigenes Client-Modul (Phase 4) |
| Startgeld | 1.000 Cash |
| Geräte | Handy, iPad, PC; Inhalt immer im sicheren Bereich (Notch, Dynamic Island, Kamera-Loch, Roblox-Leiste) |

## So kommen die Dateien nach Studio

Dateiname ohne Endung = Name in Studio. Endung sagt den Typ:
`.server.luau` = **Script**, `.client.luau` = **LocalScript**, `.luau` = **ModuleScript**.
Ordner = **Folder** (Rechtsklick → Insert Object → Folder).

| Datei im Repo (`moon-or-rug/src/…`) | In Studio | Typ |
|---|---|---|
| `ReplicatedStorage/Shared/Config.luau` | ReplicatedStorage › Shared › Config | ModuleScript |
| `ReplicatedStorage/Shared/BondingCurve.luau` | ReplicatedStorage › Shared › BondingCurve | ModuleScript |
| `ReplicatedStorage/Shared/Format.luau` | ReplicatedStorage › Shared › Format | ModuleScript |
| `ServerScriptService/Main.server.luau` | ServerScriptService › Main | Script |
| `ServerScriptService/Services/MarketService.luau` | ServerScriptService › Services › MarketService | ModuleScript |
| `ServerScriptService/Services/PlayerDataService.luau` | ServerScriptService › Services › PlayerDataService | ModuleScript |
| `ServerScriptService/Util/Remotes.luau` | ServerScriptService › Util › Remotes | ModuleScript |
| `ServerScriptService/Util/RateLimiter.luau` | ServerScriptService › Util › RateLimiter | ModuleScript |
| `StarterPlayerScripts/ClientMain.client.luau` | StarterPlayer › StarterPlayerScripts › ClientMain | LocalScript |
| `StarterPlayerScripts/ClientModules/Screen.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › Screen | ModuleScript |
| `StarterPlayerScripts/ClientModules/DebugTerminal.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › DebugTerminal | ModuleScript |

RemoteEvents musst du **nicht** anlegen – der Server erstellt `ReplicatedStorage › Remotes` selbst.

## Phasen

| Phase | Status |
|---|---|
| 1 Markt-Engine | ✅ gebaut, wartet auf Test in Studio |
| 2 NPC-Trader + NPC-Coins | offen |
| 3 Terminal-UI | offen |
| 4 Speichern, Level/XP, Server-Leaderboard | offen |
| 5 Schutz | offen |
| 6 Coin erstellen + Boost | offen |
| 7 Rugpull | offen |
| 8 Robux-Produkte + Gamepässe | offen |
| 9 Globale Coins + globales Leaderboard | offen |

## Phase 1 – Markt-Engine

**Was:** Bonding-Curve, Kaufen/Verkaufen, Gebühren, 1 Test-Coin (`MTD`), Charts im Hintergrund,
Kurs-Updates gebündelt alle 0,5 Sek., Rate-Limit 5 Trades/Sek., kleine Debug-UI.

**Wie es rechnet:**
- Preis `P(s) = P0 · (1 + s/S)²`, Kauf kostet die Fläche unter der Kurve.
- Ab der Migrationsgrenze (69.000 MCap) geht die Kurve als **gerade, halb so steile Linie** weiter
  (`MigratedSlopeFactor`). Warum nicht „S × 2“: dann würde der Preis bei der Migration springen.
  Die Linie ist flacher und hat keine Obergrenze – Coins können weiter „moonen“.
- Marktkapital = Preis × 1.000.000.
- Dev-Anteil 5 % zählt als schon verkauft → Start-Preis 0,00225, Start-MCap 2.250.
  Bis zur Migration müssen ≈ 19.000 Cash in den Coin fließen.
- Gebühr 1 % wird vom Trade-Betrag abgezogen (Kauf und Verkauf): 0,5 % an den Ersteller,
  0,5 % verschwinden. So gibt „BUY MAX“ genau das ganze Cash aus.
- Cash wird immer auf Cent **abgerundet** → durch Rundung entsteht nie Geld.
- Test (Python-Nachbau): 1.000 kaufen und sofort alles verkaufen → 980,10 zurück (= 2 × 1 % Gebühr). ✔

**Sicherheit:** Client schickt nur `coinId`, `"Buy"/"Sell"` und einen Anteil (0–1).
Server prüft Typ, Wert, Coin, Cash/Bestand und Rate-Limit und rechnet alles selbst.

**Geräte:** `Screen.CreateRoot` baut jeden Bildschirm so:
Hintergrund über den ganzen Bildschirm, Inhalt nur im sicheren Bereich (`CoreUISafeInsets`),
Layout in 1000 × 560 Design-Pixeln, per `UIScale` passend skaliert.
Buttons 72 Design-Pixel hoch (≈ 44 pt auf dem kleinsten iPhone), Text mind. 20.
Roblox-Rucksack, Lebensanzeige, Spielerliste und Emotes sind aus, Querformat ist Standard.

## Offene Punkte

- **Phase 4 (Frage an dich, dann):** Server-Coins leben nur auf einem Server. Was passiert mit Positionen,
  wenn ein Spieler den Server verlässt? (z. B. automatisch verkaufen oder verfallen)
- Creator-Gebühr verfällt, wenn der Ersteller nicht auf dem Server ist (später ggf. speichern).
- Roblox-Chat bleibt an; auf dem PC kann das Chatfenster oben links etwas verdecken (kann man schließen). Bitte im Test ansehen.
- Ich kann hier kein Luau ausführen – nur die Mathematik ist per Python-Nachbau geprüft. Fehler aus Studio bitte melden.

## Fehler & Lösungen

| Datum | Fehler | Lösung |
|---|---|---|
| – | noch keine | – |
