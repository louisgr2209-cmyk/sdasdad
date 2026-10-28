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
| `ReplicatedStorage/Shared/Indicators.luau` | ReplicatedStorage › Shared › Indicators | ModuleScript |
| `ReplicatedStorage/Shared/Levels.luau` | ReplicatedStorage › Shared › Levels | ModuleScript |
| `ServerScriptService/Main.server.luau` | ServerScriptService › Main | Script |
| `ServerScriptService/Services/MarketService.luau` | ServerScriptService › Services › MarketService | ModuleScript |
| `ServerScriptService/Services/PlayerDataService.luau` | ServerScriptService › Services › PlayerDataService | ModuleScript |
| `ServerScriptService/Services/NpcTraderService.luau` | ServerScriptService › Services › NpcTraderService | ModuleScript |
| `ServerScriptService/Services/WorldService.luau` | ServerScriptService › Services › WorldService | ModuleScript |
| `ServerScriptService/Services/LeaderboardService.luau` | ServerScriptService › Services › LeaderboardService | ModuleScript |
| `ServerScriptService/Services/ProtectionService.luau` | ServerScriptService › Services › ProtectionService | ModuleScript |
| `ServerScriptService/Util/Ledger.luau` | ServerScriptService › Util › Ledger | ModuleScript |
| `ServerScriptService/Util/Store.luau` | ServerScriptService › Util › Store | ModuleScript |
| `ServerScriptService/Util/Remotes.luau` | ServerScriptService › Util › Remotes | ModuleScript |
| `ServerScriptService/Util/RateLimiter.luau` | ServerScriptService › Util › RateLimiter | ModuleScript |
| `StarterPlayerScripts/ClientMain.client.luau` | StarterPlayer › StarterPlayerScripts › ClientMain | LocalScript |
| `StarterPlayerScripts/ClientModules/Screen.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › Screen | ModuleScript |
| `StarterPlayerScripts/ClientModules/MarketClient.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › MarketClient | ModuleScript |
| `StarterPlayerScripts/ClientModules/TerminalUI.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › TerminalUI | ModuleScript |
| `StarterPlayerScripts/ClientModules/PulseList.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › PulseList | ModuleScript |
| `StarterPlayerScripts/ClientModules/CoinPage.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › CoinPage | ModuleScript |
| `StarterPlayerScripts/ClientModules/ChartRenderer.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › ChartRenderer | ModuleScript |
| `StarterPlayerScripts/ClientModules/Portfolio.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › Portfolio | ModuleScript |
| `StarterPlayerScripts/ClientModules/LeaderboardUI.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › LeaderboardUI | ModuleScript |
| `StarterPlayerScripts/ClientModules/DailyRewardUI.luau` | StarterPlayer › StarterPlayerScripts › ClientModules › DailyRewardUI | ModuleScript |

`DebugTerminal` (Phase 1–2) gibt es nicht mehr → in Studio löschen.
RemoteEvents musst du **nicht** anlegen – der Server erstellt `ReplicatedStorage › Remotes` selbst.

## Phasen

| Phase | Status |
|---|---|
| 1 Markt-Engine | ✅ gebaut, noch nicht in Studio getestet |
| 2 NPC-Trader + NPC-Coins | ✅ gebaut, noch nicht in Studio getestet |
| 3 Terminal-UI | ✅ gebaut, wartet auf Test in Studio |
| 4a Weltmarkt + Speichern (Duplikat-Schutz) | ✅ gebaut, wartet auf Test (Studio + veröffentlicht) |
| 4b Level/XP, Leaderboard | ✅ gebaut, wartet auf Test |
| 5 Schutz | ✅ gebaut, wartet auf Test |
| 6 Coin erstellen + Boost | offen |
| 7 Rugpull | offen |
| 8 Robux-Produkte + Gamepässe | offen |
| 9 Globales Leaderboard (globale Coins gibt es durch den Weltmarkt schon) | offen |
| Creator-Programm A–D | geplant direkt **nach Phase 6** (eigenes Dokument „Moon or Rug – Creator-Programm“) |

## Phase 1 – Markt-Engine

**Was:** Bonding-Curve, Kaufen/Verkaufen, Gebühren, 1 Test-Coin (in Phase 2 durch NPC-Coins ersetzt), Charts im Hintergrund,
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
Layout in 1000 × 520 Design-Pixeln, per `UIScale` passend skaliert.
Buttons 72 Design-Pixel hoch (≈ 44 pt auf dem kleinsten iPhone), Text mind. 20.
Roblox-Rucksack, Lebensanzeige, Spielerliste und Emotes sind aus, Querformat ist Standard.

## Phase 2 – NPC-Trader + NPC-Coins

**Was:** 20 NPCs (je 5 Sniper, Momentum, Panik, Zufall) handeln über dieselben Regeln und Gebühren wie Spieler.
Beim Start gibt es 3 NPC-Coins, danach alle 1–3 Min. einen neuen (max. 40 lebende). Ca. 10 % sind NPC-Rugs.
Neue Datei: `NpcTraderService`. Der Test-Coin `MTD` ist weg (die NPC-Coins ersetzen ihn).

**Regeln (alle Werte in `Config.Npc`):**
- NPC-Geld: 2.500 pro NPC. Unter 2.500 kommen langsam 25/Min. nach, über 6.000 verschwindet der Rest → keine endlosen Pumps.
- Sniper kaufen zufällig: 40 % kaufen einen neuen Coin, nach 5–120 Sek., mit 5–15 % ihres Geldes (`Config.Npc.Sniper`).
- NPCs kaufen nur Coins, die jünger als 15 Min. sind, nie den eigenen Coin, nie gerugte oder tote Coins.
  Bei älteren Coins steigen sie aus → der Kurs läuft aus, nach 30 Min. ohne Trade ist der Coin „Dead“.
- Tote Coins verschwinden. Hält ein Spieler (online) noch Coins, bleibt der Coin zum Verkaufen da (Kaufen gesperrt).
- NPC-Rug: Der Ersteller kauft am Anfang mit 30–50 % seines Geldes dazu. Steigt der Kurs danach auf x1,5–x3
  (frühestens nach 2 Min.) oder ist der Coin 10 Min. alt, verkauft er alles auf einmal → Kurs crasht, Meldung „RUG PULL!“.
- „Rug-Lizenz“-Warnung: alle NPC-Rug-Ersteller **und** 20 % der ehrlichen NPCs. Die Warnung heißt also „Risiko“, nicht „sicher Rug“.
- NPC-Trades sind mit 🤖 markiert (`IsNpc`), Namen sind erfunden.

**Simulation (Python-Nachbau, 3 Std. ohne Spieler):** ca. 1,3 Trades/Sek., 25–32 lebende Coins, NPC-Geld stabil,
Rugs ≈ 10 % der Coins. Fehler gefunden und behoben: Zufall-NPCs verkauften alte Coins nur teilweise → Coins starben nie.
Jetzt steigen alle NPCs aus alten Coins komplett aus.

## Creator-Programm (geplant)

Quelle: Dokument „Moon or Rug – Creator-Programm“. Start frühestens nach Phase 4, vorher Schritt 0 (Fragen gestellt, Antworten offen).
- Phase A: `CreatorService` + Speichern + Admin-Liste + Log
- Phase B: Admin-Panel (nur für Admins sichtbar)
- Phase C: Titel, Abzeichen, Namensfarbe, Rahmen, Coin-Highlight in Terminal, Leaderboard, Ticker
- Phase D: Creator-Codes (Eingabe für neue Spieler, Zähler im Creator-Profil)

Antworten (Schritt 0):
| Frage | Antwort |
|---|---|
| Zeitpunkt | direkt nach Phase 6 |
| Admin-IDs | Platzhalter-Liste in `Config`; in Studio ist jeder Admin (nur zum Testen) |
| Admin-Panel | „ADMIN“-Knopf (nur Admins) → Fenster: Name, 4 Stufen, Freischalten/Entziehen, letzte 10 Aktionen |
| Creator-Code | Views bleiben die Hauptbelohnung. Code gibt neuen Spielern ein **Vorteil-Paket**, der Creator bekommt **pro eingelöstem Code extra Belohnung**. Inhalt der Pakete + Code-Format: klären vor Phase D |
| Wer darf Code eingeben | jeder Spieler genau **einmal** im ganzen Spiel, danach nie wieder |
| Stufe übersprungen | nur Belohnung dieser Stufe |
| Entziehen | Titel/Abzeichen/Farben/Highlight/Code weg, ausgezahltes Cash bleibt |
| Video-Link | Feld im Admin-Panel, nur für Admins sichtbar |

## Phase 3 – Terminal-UI

**Was:** `DebugTerminal` ersetzt durch das echte Terminal.
- `TerminalUI`: Kopfleiste (Logo, Tabs PULSE/PORTFOLIO, Cash), Seiten, Hinweis nach Trades (2,5 Sek.),
  Ticker unten (Rugpulls 🚨, große Gewinne 💰 ab 1.000 Cash Gewinn, sonst Hinweis „Fictional meme coins – just a game“).
- `PulseList`: 3 Spalten New · Almost done · Migrated (max. 20 Karten je Spalte). Karte: Icon, Ticker, Alter, MC, Holder,
  Dev-Anteil, ⚠ LIC (Rug-Lizenz), roter Rahmen bei RUGGED, BUY = Schnellkauf 10 % des Cash (`Config.Trade.QuickBuyFraction`).
  Antippen der Karte öffnet die Coin-Seite. Tote Coins erscheinen nicht.
- `CoinPage`: Chart (Linie), Preis + Änderung über den Chart, Infos, Ersteller, Lizenz-Warnung,
  Position mit P/L, BUY 10/25/50 %/MAX, SELL 10/25/50 %/ALL, Live-Trades.
- `ChartRenderer`: Linie aus kleinen gedrehten Frames, 60 Punkte + aktueller Punkt, High/Low-Beschriftung.
- `Portfolio`: Cash, Wert in Coins, Gesamt, offener Gewinn/Verlust; Liste der Positionen mit SELL ALL.
- `MarketClient`: empfängt alle Server-Daten an einer Stelle; die Seiten lesen nur daraus.
- Server: Verkauf mit ≥ 1.000 Gewinn → Meldung im Ticker (`Config.Ticker`).

**Geräte:** Alles liegt in `Screen.CreateRoot` (sicherer Bereich + Skalierung).
Kleinster Platz ist 1000 × 520 Design-Pixel (iPad, PC); Handys im Querformat haben mehr Breite (ca. 1100–1300).
Für 1000 Breite nachgerechnet: Pulse-Karten ca. 16 Zeichen pro Zeile, Coin-Seite rechts 3 Live-Trades,
alle Buttons mind. 72 hoch (Tabs 64). Zu lange Texte werden mit „…“ gekürzt statt überzulaufen.

**Prüfung:** Python-Prüfskript für Luau-Blöcke (`function`/`if`/`for`/`end`, Klammern) über alle Dateien: 0 Fehler.

## Phase 5 – Schutz vor Bankrott

**Entscheidungen (Klick-Fragen):** Daily steigend 500·750·1.000·1.500·2.000·3.000·5.000, Lücke = Tag 1, Knopf + Fenster;
Stop-Loss feste Stufen, **auch offline**; Versicherung per Schalter pro Coin, bezahlt aus Prämien-Topf + max. 500/Tag/Spieler
vom Spiel; Anfänger mit Versicherung: der höhere Wert zählt. Neu: `ProtectionService`, `DailyRewardUI`.

- **Mindestgeld:** Vermögen (Cash + Coins) unter 100 → alle 10 Min. +250, solange online. Zeitpunkt steht in der
  Geldbörse → Rejoin bringt nichts.
- **Daily Reward:** 🎁-Knopf oben (gelb = bereit), Fenster mit 7 Tagen. Nach Tag 7 wieder Tag 1. UTC-Tage.
  Einmal pro Tag garantiert (Ledger.WalletDaily, Wiederholung bucht nicht doppelt). Doppelter Reward (Gamepass) → Phase 8.
- **Stop-Loss (ab Lv 3):** Knopf auf der Coin-Seite schaltet OFF → -10 % → -20 % → -30 % → -50 %. Gemessen: Verkaufswert
  nach Gebühr gegen eigenen Einsatz → verkauft alles. Auftrag liegt im Coin (Wahrheit). **Online** verkauft der eigene
  Server nach ca. 1 Sek.; **offline** verkauft der Host, wenn der Stop seit 15 Sek. erreicht ist → Cash + Gewinn-Statistik
  ins Postfach (Hinweis beim nächsten Join). Andere sehen nur die *Anzahl* der Aufträge, nie die Preise (sonst „Stop-Jagd“).
- **Rug-Versicherung (ab Lv 5):** Schalter „🛡 INSURE“ pro Coin. Jeder Kauf kostet +5 % (wird mit dem Kauf reserviert,
  bei Fehlschlag mit erstattet). Bei einem Rug: 60 % des versicherten Verlusts.
- **Anfänger-Erstattung (unter Lv 5):** 50 % des Verlusts bei einem Rug. Mit Versicherung zählt der höhere Wert.
- **Regeln für Erstattungen:** letzter Kauf mind. 60 Sek. vor dem Rug; Geld aus Versicherungstopf (Prämien) bzw.
  Erstattungstopf (30 % jedes Rug-Erlöses, auch von NPC-Rugs); fehlt etwas, legt das Spiel max. 500 pro Spieler und Tag drauf.
  Auszahlung ins Postfach mit Hinweis „🛡 Rug refund“.
- **Geprüft:** Absturz-Test mit Versicherungsprämien (131.000 Trades): 0 Doppelbuchungen, 0 Verlust.
  Topf-Logik mit Beispielen nachgerechnet (Tageslimit greift, nächster Tag neu).
- **Coin-Seite:** BUY/SELL-Knöpfe zweizeilig („BUY / 10%“), darunter 🛑 STOP und 🛡 INSURE (mit 🔒 Lv-Hinweis).
- **Portfolio:** Positionen zeigen 🛑-20% / 🛡.

## Phase 4b – Level/XP + Leaderboard

**Entscheidungen (Klick-Fragen):** Tempo schnell; Ranglisten Vermögen, bester Trade, PNL (realisiert);
Zeiträume Gesamt, Woche, Tag; weltweit schon jetzt; keine NPCs; Level-Up als Banner.

- **XP:** +1 pro Trade ab 100 Cash (höchstens alle 10 Sek. – kein Farmen mit Mini-Trades), +1 pro 100 Cash Gewinn.
  Level L ab 3 × (L−1)² XP → Lv 3 nach ca. 4 Min., Lv 5 ca. 16 Min., Lv 10 ca. 1,5 Std., Lv 25 ca. 10 Std., Lv 40 ca. 25 Std.
- **Ränge:** Rookie (1), Trader (3, Stop-Loss), Degen (5, Rug-Versicherung), Whale (10, Coin erstellen),
  Shark (15, Boost), Dev (25, Rug-Lizenz), Legend (40, Kosmetik) – `Config.Levels`.
- **Statistiken** (XP, PNL, bester Trade, je Tag/Woche) werden im selben Schritt wie das Geld gebucht
  (`Ledger.WalletFinish`) → zählen genau einmal, auch bei Absturz. Gespeichert mit dem Spielstand.
- **Leaderboard-Seite** (3. Tab): WORLD/SERVER, ALL TIME (Net worth, PnL, Best trade) / WEEK / TODAY (PnL, Best trade),
  Top 50, eigene Werte unten („You: …“). Woche startet Montag, Tag um 0 Uhr UTC.
- **Weltweit:** jeder Server schreibt geänderte Werte seiner Spieler alle 2 Min. + beim Verlassen in OrderedDataStores;
  nur der Host liest die Top 50 (alle 90 Sek.) und teilt sie über den Weltmarkt-Speicher (alle Server holen sie jede Minute).
  Im Studio-Testmodus gibt es nur die SERVER-Liste.
- **Kopfleiste:** Cash, darunter „Lv 7 · Whale“ + XP-Balken. Level-Up → gelber Banner 4 Sek. mit Freischaltung.
- **Portfolio:** 5. Kachel „Level“ mit Fortschritt und fehlenden XP.

## Indikatoren (Zusatz zu Phase 3, Wunsch: „wie axiom, aber für jeden verständlich“)

Auf der Coin-Seite unter dem Chart 5 Ampel-Kacheln. Antippen → Fenster mit Erklärung und „ab wann“ grün/gelb/rot.
| Kachel | Bedeutung | 🟢 gut | 🟡 vorsichtig | 🔴 riskant |
|---|---|---|---|---|
| Top 10 | Anteil der 10 größten Holder an allen Coins | bis 15 % | 15–30 % | über 30 % |
| Dev | Anteil des Erstellers (Start = 5 %) | bis 5 % | 5–10 % | über 10 % |
| Early | Anteil der Früh-Käufer (erste 30 Sek.), die noch halten | bis 10 % | 10–20 % | über 20 % |
| Holders | Anzahl verschiedener Holder (mehr = besser) | ab 8 | 3–7 | unter 3 |
| Rug lic. | Ersteller hat Rug-Lizenz | NO | – | YES |

Grenzen in `Config.Indicators` (Startwerte aus der Simulation: normale Coins Top 10 meist 5–25 %, NPC-Rug-Coin
Dev 25 % / Top 10 35 % → rot). Pulse-Karten: „Dev x %“ in derselben Ampelfarbe.
Neue Datei `Indicators` (gemeinsam für Server/Client). Server schickt `Top10` und `EarlyShare` mit.
Die Infozeile zeigt jetzt auch den Fortschritt bis zur Migration („Migration 45%“).

## Gesamt-Prüfung (nach Phase 3)

Ohne Roblox Studio geprüft (Luau ausführen ist hier nicht erlaubt, deshalb kein echter Testlauf):
1. **Syntax:** alle 17 Dateien mit dem echten Luau-Parser von StyLua geparst → 0 Fehler
   (Gegenprobe mit absichtlich kaputter Datei → Fehler erkannt).
2. **Namen:** eigener Checker für nicht definierte Variablen/vergessene `require` → keine echten Funde.
3. **Von Hand gelesen:** alle Dateien Zeile für Zeile (Logik, Roblox-APIs, Remote-Daten, Randfälle).
4. **Mathematik/NPCs:** Python-Nachbau (Kurve, Gebühren, 3 Std. NPC-Markt), siehe Phase 1 und 2.
5. **Geräte:** Skalierung für 11 Geräte nachgerechnet (Tabelle unten).

| Gerät | Skalierung | Button (72) | Text (20) |
|---|---|---|---|
| iPhone SE | 0,61 | 44 pt | 12,2 pt |
| iPhone 15 Pro (Dynamic Island) | 0,60 | 43 pt | 12,1 pt |
| iPhone 15 Pro Max | 0,68 | 49 pt | 13,5 pt |
| Samsung Galaxy S23 (Kameraloch) | 0,58 | 42 pt | 11,6 pt |
| iPad quer / iPad mini hoch | 1,18 / 0,74 | 85 / 54 pt | 23,6 / 14,9 pt |
| PC 1366×768 / 1920×1080 | 1,37 / 1,50 | 98 / 108 px | 27 / 30 px |

## Sicherheit & Denklücken

**Wege vom Client zum Server (nur 2):**
| Remote | Schutz |
|---|---|
| `TradeRequest` | Typ-Prüfung (String ≤ 20, "Buy"/"Sell", Zahl 0–1, kein NaN/∞), Coin muss existieren, Cash/Bestand prüft der Server, max. 5/Sek.; bei Spam höchstens 1 Antwort/Sek. |
| `GetMarketSnapshot` | max. 3 pro 30 Sek., gibt nur eigene Daten + öffentliche Marktdaten zurück (keine fremden Positionen) |

Weitere Punkte: Geld entsteht nie durch Rundung (Auszahlungen abgerundet), Namen werden ohne RichText angezeigt
(keine Formatierungs-Tricks), geheime NPC-Rug-Pläne bleiben auf dem Server, Gewinne ab 10.000 pro Verkauf
werden geloggt (`[Security]` im Server-Output), Speicher wird bei langen Servern aufgeräumt.

**Gefunden & behoben – „NPCs melken“:** Simulation zeigte: Wer jeden neuen Coin sofort kauft und nach 20 Sek.
verkauft, machte aus 1.000 Cash in 1 Std. ca. 48.000 (Sniper-NPCs kauften vorhersehbar, NPC-Geld wurde nachgefüllt).
Fix: Sniper kaufen zufällig (ob/wann/wie viel), Nachfüllen 100 → 25/Min. Danach: 2.900–6.300 nach 1 Std.
(früh kaufen lohnt sich weiter, aber keine Gelddruckmaschine), Markt genauso aktiv.

**Denklücken für spätere Phasen (deine Entscheidung: alle Vorschläge OK, NPC-Rugs: ja, und „keine Duplikat-Lücken“):**
| Phase | Lücke | Vorschlag |
|---|---|---|
| 4 | „1 XP pro Trade“ → XP-Farmen mit 1-Cash-Mini-Trades (bis 18.000 XP/Std.) | XP pro Trade erst ab 100 Cash Trade-Größe, max. 1 Trade-XP pro 10 Sek. |
| 4 | Positionen in Server-Coins beim Verlassen (Coins gibt es nur auf diesem Server) | beim Verlassen automatisch zum aktuellen Kurs verkaufen, Cash wird gespeichert |
| 5 | Mindestgeld „unter 100 Cash“ → Geld in Coins parken und alle 10 Min. 250 kassieren | Bedingung: Cash **+ Wert der Coins** unter 100 |
| 5/7 | Versicherung (60 %) + Anfänger-Erstattung, die das Spiel bezahlt, wenn der Topf leer ist → mit Zweit-Accounts Geld drucken (eigenen Coin ruggen, Alt kassiert) | Erstattungen nur aus dem Erstattungstopf/Rug-Erlös; Spiel legt max. 500 Cash pro Spieler und Tag drauf; Kauf muss ≥ 60 Sek. vor dem Rug sein |
| 6 | Spieler-Coins mit echten Krypto-Namen/Tickern (BTC, ETH, PEPE …) – der Roblox-Filter lässt die durch | zusätzliche Sperrliste in `Config` + keine doppelten Ticker |
| 8 | Robux-Kauf doppelt gutgeschrieben oder verloren | `ProcessReceipt` nur mit geladenen Daten, PurchaseId speichern, erst dann „granted“ |
| 9 | Globale Coins: gleichzeitige Trades auf mehreren Servern | alle globalen Trades atomar über MemoryStore `UpdateAsync` |
| Creator | Admin-Rechte | nur Server prüft UserId-Liste; „in Studio jeder Admin“ nur mit `RunService:IsStudio()` |

## Phase 4a – Weltmarkt + Speichern

**Entscheidungen:** ein Markt für alle Server (ersetzt „eigener Markt pro Server“), so wenig Verzögerung wie
möglich; delistete Coins bleiben verkaufbar; gelistete Coins wachsen mit der Spielerzahl; NPC-Coins weltweit
alle 1–3 Min.; Pro-Terminal = Ampeln für alle, Pro zeigt Top-10-Namen/Kerzen/Dev-Verkäufe.

**Aufbau (neu: `Ledger`, `Store`, `WorldService`; neu geschrieben: `MarketService`, `PlayerDataService`, `NpcTraderService`, `Main`):**
- **Coins** = je ein MemoryStore-Schlüssel (Wahrheit für Menge/Preis/Holder). Trades ändern ihn atomar.
- **Kurzinfos** aller Coins in 4 Sammel-Schlüsseln. Jeder Server liest sie alle 0,5 Sek. (bei winzigen Servern bis 2 Sek.,
  damit das Roblox-Budget reicht) und schreibt eigene Änderungen. Eigene Trades sind sofort sichtbar,
  Trades anderer Server nach ca. 0,5–1,5 Sek.
- **Geldbörse** (Cash, offener Trade, gehaltene Coins) im MemoryStore, solange gespielt wird. **Session-Lock:**
  nur ein Server hält sie (Lebenszeichen alle 15 Sek.; erst nach 45 Sek. Stille darf ein anderer übernehmen).
- **Speichern:** DataStore alle 60 Sek., beim Verlassen und beim Herunterfahren (BindToClose). Laden: erst
  Weltmarkt (neuester Stand), sonst DataStore, sonst Startgeld. DataStore nicht erreichbar → Spieler wird mit
  Hinweis gekickt statt mit falschem Stand zu spielen.
- **NPC-Host:** genau ein Server lässt NPCs handeln, erstellt Coins, markiert tote Coins, speichert Charts.
  Fällt er aus, übernimmt nach max. 30 Sek. ein anderer (NPC-Zustand wird alle 10 Sek. gespeichert).
- **Delistete Coins:** weiter verkaufbar. Nach 72 Std. ohne Trade verkauft das Spiel Reste automatisch,
  Cash kommt ins Postfach (beim nächsten Join / jede Minute gutgeschrieben).
- **Lokaler Testmodus:** ohne veröffentlichtes Spiel / ohne API-Zugriff läuft alles nur im Speicher (Warnung im Output).

**Duplikat-Schutz (Trade in 3 Schritten mit fortlaufender Nummer):**
1. Geldbörse merkt sich den Trade, Kauf-Geld wird reserviert. 2. Coin bucht genau einmal (merkt sich die Nummer).
3. Geldbörse schließt genau einmal ab. Absturz/verlorene Antwort dazwischen → Schritte 2+3 werden später
wiederholt (beim nächsten Trade oder Join) und ändern nichts doppelt. Buchungen ohne Nummer (NPC-Trades, Gebühren,
Postfach) werden nie automatisch wiederholt: im Zweifel geht ein kleiner Betrag verloren, aber nie doppelt.

**Prüfungen:**
- Python-Nachbau des Ledgers, 40 Läufe mit 110.000–135.000 Trades, 8 % Fehler pro Speicherzugriff
  (Anfrage verloren / geschrieben aber Antwort verloren), Serverwechsel, verspätete alte Anfragen:
  **0 Doppelbuchungen**, nie mehr Geld/Coins als gebucht, Coins exakt. Gegenprobe ohne Schutz: sofort Hunderte Fehler.
- Budget nachgerechnet (Roblox: 1000 + 120 pro Spieler Anfragen/Min., 64 KB + 1,2 KB pro Spieler Speicher):
  typisch 50–90 % Auslastung, auch bei vielen kleinen Servern.
- Grenzen: 1 Speicher-Wert max. 32 KB → max. 200 Holder pro Coin (seit Phase 5), 30 volle Buchungsbelege pro Coin
  (ältere nur mit Nummer – Schutz bleibt). Gelistete Coins: 20 + 1 pro 5 Spieler, max. 120.
- Luau-Parser (StyLua) über alle Dateien: 0 Fehler.

## Offene Punkte

- **Test Phase 4a braucht ein veröffentlichtes Spiel** (MemoryStore/DataStore). In Studio ohne API-Zugriff läuft
  der lokale Testmodus (alles funktioniert, aber nichts wird gespeichert und es gibt nur einen Server).
  Achtung: Mit API-Zugriff schreibt Studio in die **echten** Spielstände → am besten eine eigene Test-Place nutzen.
- Mehrere Server gleichzeitig lassen sich nur im veröffentlichten Spiel testen (z. B. 2 Geräte, 2 Server).
- ~~Bekannt bis Phase 4: Verlassen + Wiederkommen gab wieder 1.000 Cash~~ → gelöst mit Phase 4a (Speichern + Weltmarkt).

- Phase 8: Pro-Terminal zeigt Top-10-Holder mit Namen, Kerzen-Chart, Dev-Verkäufe live (entschieden).
- Kopfleiste: Level (Phase 4b), Daily Reward (Phase 5) und Shop (Phase 8) kommen rechts neben die Tabs.
- Gebühren an Spieler-Ersteller (0,5 %) kommen mit Phase 6 (dann über das Spieler-Postfach).

- **Balancing (beim Test entscheiden):** Ohne Spieler erreicht fast nie ein Coin die Migration (69.000).
  Selbst mit doppeltem NPC-Geld nur ca. 1 Coin in 3 Std. Mit Spielern fließt mehr Geld. Falls die Spalte
  „Migrated“ zu leer wirkt: Grenze senken (z. B. 40.000) oder NPC-Geld erhöhen – nur in `Config`.
- **Phase 5/7:** Gelten Anfänger-Erstattung und Rug-Versicherung auch bei NPC-Rugs? (Frage an dich, dann)

- **Phase 4 (Frage an dich, dann):** Server-Coins leben nur auf einem Server. Was passiert mit Positionen,
  wenn ein Spieler den Server verlässt? (z. B. automatisch verkaufen oder verfallen)
- Creator-Gebühr verfällt, wenn der Ersteller nicht auf dem Server ist (später ggf. speichern).
- Roblox-Chat bleibt an; auf dem PC kann das Chatfenster oben links etwas verdecken (kann man schließen). Bitte im Test ansehen.
- Ich kann hier kein Luau ausführen – nur die Mathematik ist per Python-Nachbau geprüft. Fehler aus Studio bitte melden.

## Fehler & Lösungen

| Datum | Fehler | Lösung |
|---|---|---|
| Phase 1 | `Format` in MarketService nicht geladen (wäre beim ersten Trade abgestürzt) | `require` ergänzt, vor dem ersten Push gefunden |
| Phase 2 | Simulation: alte Coins starben nie (Zufall-NPCs verkauften nur Teile) | alle NPCs steigen aus Coins > 15 Min. komplett aus |
| Phase 3 | Mehrere Zeilen begannen mit `(` → Luau meldet „ambiguous syntax“ | in lokale Variablen umgeschrieben |
| Prüfung | Ein Fehler in `checkRugs`/`createNpcCoin` oder im Markt-Takt hätte die Schleife für immer gestoppt (Markt steht still) | Schleifen mit `pcall` abgesichert, Fehler erscheinen als Warnung im Output |
| 5 | `%d` mit 0.1*100 (=10.000000000000002) bricht in Luau ab | vorher runden (math.floor(x*100+0.5)) |
| 5 | Holder-Einträge größer (Versicherung, Kaufzeit, Level) → 400 Holder > 32 KB | max. 200 Holder pro Coin, Kaufzeit als ganze Sekunde |
| 5-Test | Test-Buchhaltung vergaß Prämie bei verlorener Antwort | Prämie vor dem Speicherzugriff gemerkt |
| 4a | Wiederholung nach verlorener Antwort hätte NPC-Trades/Gebühren doppelt gebucht | ohne automatische Wiederholung + Bestand nachprüfen |
| 4a | Coin-Wert (max. 32 KB) wäre bei sehr vielen Händlern übergelaufen | Belege schrumpfen auf Nummer, max. 400 Holder |
| 4a | Budget-Rechnung: viele kleine Server → 141 % des Roblox-Limits | Abfrage-Takt passt sich an (0,5–2 Sek.), sparsamere Werte → max. ~90 % |
| 4a | Delistete Coins von Spielern, die nie wiederkommen, hätten den Speicher gefüllt | nach 72 Std. automatisch verkaufen, Cash ins Postfach |
| 4a | Schleifen über Tabellen, die sich während Speicherzugriffen ändern | vorher Kopie der Liste |
| 4a-Test | Test-Fehler: alte Anfragen aus anderen Testläufen | Liste pro Lauf geleert |
| Sicherheit | NPCs vorhersehbar → 1.000 → 48.000 Cash/Std. per Sofort-Kauf | Sniper zufällig, Nachfüllen 25/Min. (Simulation: 2.900–6.300) |
| Sicherheit | Spam von `TradeRequest` erzeugte eine Antwort pro Anfrage (Last) | „Too fast“ höchstens 1x/Sek. |
| Sicherheit | `GetMarketSnapshot` (große Datenmenge) 2x/Sek. abrufbar | max. 3 pro 30 Sek. |
| Sicherheit | NPC-Tabellen wuchsen bei langen Servern unbegrenzt | Aufräumen jede Minute |
| Prüfung | Auf Handys Buttons nur 39–41 pt (Richtwert 44), Text ca. 11 pt | Design-Höhe 560 → 520: Buttons 42–49 pt, Text ca. 12 pt |
