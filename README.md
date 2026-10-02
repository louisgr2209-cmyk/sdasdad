# 🏛️ PRÄSIDENT – Der Staatssimulator

Ein Präsidentensimulator für den PC: Übernimm eines von **61 echten Ländern** – von der Schweiz bis zum Sudan, von den USA bis Nordkorea, triff Entscheidungen in Wirtschaft, Sozialpolitik, Militär, Politik und Diplomatie – und überlebe Krisen, Skandale, Kriege und Wahlen.

Man muss kein Politik-Profi sein: **Berater** erklären jede Lage, zeigen die Folgen jeder Option als farbige Chips (grün = gut, rot = schlecht) und markieren ihre Empfehlung mit ⭐.

## 🎮 Spiel starten

**Ohne Installation:** einfach `index.html` doppelklicken. Das Spiel läuft komplett offline im Browser (Chrome, Edge, Firefox).

**Als Desktop-App (Windows/macOS/Linux)** mit [Node.js](https://nodejs.org):

```bash
npm install
npm start              # Spiel im eigenen Fenster starten (F11 = Vollbild)
npm run build:win      # erzeugt eine portable .exe im Ordner dist/
```

## ✨ Funktionen

| Bereich | Was du tun kannst |
|---|---|
| 🧭 **Übersicht** | Lebendige Weltkarte, „Ampeln“ für die Lage der Nation, Bevölkerung, Kabinettsbericht |
| 🏛️ **Regierung** | Gesetze und Sofortmaßnahmen ohne Wartezeit – plus **Minister-Autopilot** pro Bereich |
| 💰 **Finanzen** | **Staatskonto** mit Verfügungsfonds und Überschüssen, Schulden tilgen, Kredite, Staatsfonds, **Sonderprojekte**, Steuern & Ausgaben |
| 🗺️ **Länderfenster** | Klick auf ein Land auf der Karte: Übersicht, Diplomatie & Handel (Verträge, Waffenverkauf, Sanktionen), Militär (Streitkräfte im Vergleich, Ultimatum, Krieg) |
| 🌍 **Welt** | **Konflikte & Krisenherde** (vermitteln, helfen, Friedenstruppen, eingreifen), Vertragsverhandlungen, Bündnisse (EU, NATO, BRICS …, eigenes Bündnis), atomwaffenfreie Welt |
| 🛡️ **Militär** | **8 Truppengattungen** (Infanterie, Panzer, Artillerie, Jets, Drohnen, Flugabwehr, Schiffe, U-Boote) kaufen & ausmustern, Mobilisierung, **Kriegslagezentrum** (Waffe wählen → Ziel anklicken: Frontverbände, Luftwaffe, Flugabwehr, Marine, Kommandozentralen, Rüstung, Raketen, Energie; Strategie offensiv/ausgewogen/defensiv; Atomschlag nur auf militärische Ziele), Spezialeinheiten (KSK, Navy SEALs …), Terrorabwehr |
| 📊 **Chronik** | Verlaufsdiagramme und Nachrichtenarchiv |

- **Realistische Unterschiede:** Die *Staatskapazität* bestimmt, wie gut Reformen wirken – ein schwacher Staat wie Sudan entwickelt sich nur langsam. Kriege brauchen Vorbereitung: Ohne Mobilisierung und Verbündete hat auch Deutschland gegen eine Großmacht keine Chance. Atommächte lassen sich nicht einfach besiegen.
- **Aggressiv spielen:** Ultimaten stellen, Kriege gegen jedes Nicht-Bündnisland erklären und nach dem Sieg die Bedingungen diktieren – **Annexion**, **Marionettenregierung** oder **Reparationen**. Entfernung (Machtprojektion), Bündnisse des Gegners (z. B. NATO), Atommächte und weltweite Sanktionen machen Eroberungen aber schwer.
- **Spezialeinheiten** jedes Landes für Terrorabwehr, Geiselbefreiung und Kommandoeinsätze – der Erfolg hängt von ihrer Ausbildung ab.
- **Atomwaffen** als letzte, katastrophale Eskalationsstufe: nukleare Drohung oder Atomschlag mit weltweiter Ächtung. Gegen Atommächte folgt eine **nukleare Krise**, die sich mit Deeskalation, UN-Vermittlung oder Kapitulation noch entschärfen lässt – nur bei totaler Eskalation endet das Spiel.
- **Atomwaffenfreie Welt:** Überzeuge jede Atommacht einzeln, gehe selbst mit gutem Beispiel voran – dann werden alle Arsenale abgebaut (Friedensnobelpreis inklusive).
- **54 Zufallsereignisse** mit 2–4 Entscheidungsoptionen: Generalstreik, Börsencrash, Pandemie, Terroranschlag, Ölschock, Spionage, Putschgerüchte, WM-Titel …
- **7 Bevölkerungsgruppen** (Arbeiter, Unternehmer, Rentner, Jugend, Militär, Umweltbewegung, Konservative) – ihre Zufriedenheit ergibt deine Zustimmung.
- **Staatskonto statt Punkten:** Alles wird sofort beschlossen und vom Konto bezahlt; wiederholte Maßnahmen wirken schwächer.
- **Minister-Autopilot (optional, standardmäßig aus):** Minister kümmern sich auf Wunsch selbst um Finanzen, Wirtschaft, Soziales, Militär, Diplomatie und kleine Ereignisse – große Entscheidungen bleiben bei dir.
- **Lebendige Welt:** Andere Länder führen Kriege, Krisenherde entstehen und verschwinden – sichtbar auf der Karte.
- **Wahlen** alle 4 Jahre (Demokratien) bzw. **Machtproben** (autoritäre Staaten).
- **Spielende** durch Abwahl, Misstrauensvotum, Revolution, Militärputsch, Staatsbankrott oder Atomkrieg – oder erfolgreich nach 3 Amtszeiten mit **Vermächtnis-Punkten**. Endlosmodus verfügbar.
- 3 Schwierigkeitsgrade, automatisches Speichern, Export/Import von Spielständen, Tastenkürzel.

## ⌨️ Steuerung

| Taste | Aktion |
|---|---|
| `Leertaste` | Nächster Monat |
| `1`–`6` | Bereich wechseln |
| `1`–`4` | Option im Ereignis wählen |
| `A` | Automatischer Zeitablauf |
| `Esc` | Menü |

## 🗂️ Projektstruktur

```
index.html            Einstieg
css/style.css         Gestaltung
js/engine.js          Simulation (Wirtschaft, Gruppen, Wahlen, Kriege, Ereignisse)
js/ui.js              Oberfläche
js/data/countries.js  Länderdaten (an der realen Welt angelehnt)
js/data/policies.js   Gesetze, Sofortmaßnahmen, Gruppen, Berater
js/data/events.js     Zufallsereignisse
js/data/worldmap.js   Punktraster-Weltkarte (aus Natural Earth, Public Domain)
assets/flags/         Flaggen (flag-icons, MIT-Lizenz)
electron/main.js      Desktop-App-Hülle
tools/sim-test.js     Balance-Test ohne Oberfläche
tools/aggro-test.js   Test für aggressives Spiel (Eroberer-Bot)
```

## 🧪 Balance testen

```bash
node tools/sim-test.js 144 20 advisor   # 12 Jahre, 20 Durchläufe, nur Ereignisse nach Beraterrat
node tools/sim-test.js 144 20 smart     # Bot beschließt zusätzlich empfohlene Gesetze
```

## ➕ Eigene Inhalte

Neue Ereignisse, Gesetze oder Länder lassen sich einfach in den Dateien unter `js/data/` ergänzen – das Format ist dort jeweils oben beschrieben.

---
Alle Länderwerte sind vereinfacht und gerundet. Ereignisse und Figuren sind fiktiv.
