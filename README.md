# 🏛️ PRÄSIDENT – Der Staatssimulator

Ein Präsidentensimulator für den PC: Übernimm eines von **27 echten Ländern** – von der Schweiz bis zum Sudan, triff Entscheidungen in Wirtschaft, Sozialpolitik, Militär, Politik und Diplomatie – und überlebe Krisen, Skandale, Kriege und Wahlen.

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
| 🧭 **Lagezentrum** | Alle Kennzahlen auf einen Blick, Weltkarte, Bevölkerungsgruppen, Berater-Warnungen |
| 💰 **Haushalt** | Einkommen-, Unternehmens- und Mehrwertsteuer + 7 Ausgabenressorts per Schieberegler, Live-Vorschau, „Haushalt ausgleichen“-Vorschlag |
| 📈 **Wirtschaft** | 14 Gesetze (Mindestlohn, Bürokratieabbau, Schuldenbremse …) und Sofortmaßnahmen (Konjunkturpaket, Sparpaket …) |
| 🤝 **Soziales** | Bildung, Gesundheit, Rente, Wohnen, Einwanderung, Klima – 16 Gesetze |
| 🛡️ **Militär** | Mobilisierung, Offensiven (Boden, Luft, See), Spezialeinheiten (KSK, Navy SEALs, SAS, GIGN …), Terrorabwehr, Atomwaffen |
| 🏛️ **Politik** | Korruption, Medien, Notstand, Wahlkampf – und der Countdown zur nächsten Wahl |
| 🌍 **Diplomatie** | Beziehungen zu 26 Ländern, **Vertragsverhandlungen** mit eigenen Angeboten (Handel, Militärbündnis, Nichtangriffspakt, Forschung, Energie, Rüstungskontrolle), **Bündnisse** (EU, NATO, BRICS, USMCA, Pazifik-Partnerschaft) beitreten/verlassen oder **eigenes Bündnis gründen**, **Initiative für eine atomwaffenfreie Welt**, Sanktionen, Krieg & Frieden |
| 📊 **Statistiken** | Verlaufsdiagramme für Zustimmung, Wachstum, Schulden, Inflation u. v. m. |
| 📰 **Nachrichten** | Eigene Tageszeitung und Newsticker |

- **Realistische Unterschiede:** Die *Staatskapazität* bestimmt, wie gut Reformen wirken – ein schwacher Staat wie Sudan entwickelt sich nur langsam. Kriege brauchen Vorbereitung: Ohne Mobilisierung und Verbündete hat auch Deutschland gegen eine Großmacht keine Chance. Atommächte lassen sich nicht einfach besiegen.
- **Spezialeinheiten** jedes Landes für Terrorabwehr, Geiselbefreiung und Kommandoeinsätze – der Erfolg hängt von ihrer Ausbildung ab.
- **Atomwaffen** als letzte, katastrophale Eskalationsstufe: nukleare Drohung oder Atomschlag mit weltweiter Ächtung. Gegen Atommächte folgt eine **nukleare Krise**, die sich mit Deeskalation, UN-Vermittlung oder Kapitulation noch entschärfen lässt – nur bei totaler Eskalation endet das Spiel.
- **Atomwaffenfreie Welt:** Überzeuge jede Atommacht einzeln, gehe selbst mit gutem Beispiel voran – dann werden alle Arsenale abgebaut (Friedensnobelpreis inklusive).
- **54 Zufallsereignisse** mit 2–4 Entscheidungsoptionen: Generalstreik, Börsencrash, Pandemie, Terroranschlag, Ölschock, Spionage, Putschgerüchte, WM-Titel …
- **7 Bevölkerungsgruppen** (Arbeiter, Unternehmer, Rentner, Jugend, Militär, Umweltbewegung, Konservative) – ihre Zufriedenheit ergibt deine Zustimmung.
- **Politisches Kapital ⚡** als Ressource für Gesetze und Maßnahmen.
- **Wahlen** alle 4 Jahre (Demokratien) bzw. **Machtproben** (autoritäre Staaten).
- **Spielende** durch Abwahl, Misstrauensvotum, Revolution, Militärputsch, Staatsbankrott oder Atomkrieg – oder erfolgreich nach 3 Amtszeiten mit **Vermächtnis-Punkten**. Endlosmodus verfügbar.
- 3 Schwierigkeitsgrade, automatisches Speichern, Export/Import von Spielständen, Tastenkürzel.

## ⌨️ Steuerung

| Taste | Aktion |
|---|---|
| `Leertaste` | Nächster Monat |
| `1`–`9` | Bereich wechseln |
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
