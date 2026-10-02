// Zufällige Ereignisse.
// Platzhalter im Text: {land} = beteiligtes Land, {capital} = deine Hauptstadt, {country} = dein Land
// ctx: welches andere Land beteiligt ist ('random', 'rival', 'ally', 'partner', 'neighbor', 'nottrade')
// weight: Grundhäufigkeit (Zahl oder Funktion), cond: Voraussetzung
// Effekte: stats (approval wirkt als Stimmung), econ (direkte Änderung), groups, money (% BIP),
//          capital, mods [{key,value,months}], relation, trade, war, oil, campaign, chance {p, success, fail}

const EVENTS = [
  // ═════════════ WIRTSCHAFT ═════════════
  { id: 'generalstreik', icon: '✊', cat: 'wirtschaft', title: 'Generalstreik!',
    weight: s => s.groups.workers < 45 ? 2 : 0.6,
    text: 'Die Gewerkschaften legen das Land lahm. Züge stehen still, Fabriken sind besetzt. Sie fordern 8 % mehr Lohn und bessere Arbeitsbedingungen.',
    choices: [
      { label: 'Forderungen erfüllen', desc: 'Der Staat übernimmt einen Teil der Lohnerhöhungen.', effects: { money: 0.4, groups: { workers: 12, business: -8 }, econ: { inflation: 0.4 } } },
      { label: 'Kompromiss aushandeln', desc: 'Du vermittelst persönlich zwischen den Parteien.', effects: { capital: -10, groups: { workers: 4, business: -2 } } },
      { label: 'Hart bleiben', desc: 'Der Streik muss ausgesessen werden.', effects: { groups: { workers: -12, business: 4 }, stats: { stability: -4 }, mods: [{ key: 'growth', value: -0.8, months: 3 }] } },
    ] },

  { id: 'boersencrash', icon: '📉', cat: 'wirtschaft', title: 'Börsencrash',
    weight: 0.5,
    text: 'Die Aktienmärkte brechen an einem Tag um 20 % ein. Panik erfasst Anleger und Banken. Alle Augen richten sich auf die Regierung.',
    choices: [
      { label: 'Rettungsschirm für Banken', desc: 'Garantien und Kapitalspritzen stabilisieren das Finanzsystem.', effects: { money: 2.0, groups: { business: 8, workers: -6 }, mods: [{ key: 'growth', value: -0.5, months: 6 }] } },
      { label: 'Konjunkturprogramm', desc: 'Investitionen in Bürger und Infrastruktur.', effects: { money: 1.2, groups: { workers: 4 }, mods: [{ key: 'growth', value: -0.8, months: 6 }] } },
      { label: 'Märkte sich selbst überlassen', desc: 'Der Markt wird sich schon erholen …', effects: { groups: { business: -6 }, econ: { unemployment: 1.0 }, mods: [{ key: 'growth', value: -1.8, months: 9 }] } },
    ] },

  { id: 'oelschock', icon: '🛢️', cat: 'wirtschaft', title: 'Ölpreis explodiert',
    weight: 0.6,
    text: 'Nach Spannungen im Nahen Osten steigt der Ölpreis um 60 %. Benzin und Heizöl werden drastisch teurer.',
    choices: [
      { label: 'Spritpreisbremse', desc: 'Der Staat subventioniert Treibstoff.', effects: { oil: 0.6, money: 0.5, groups: { workers: 5, greens: -4 } } },
      { label: 'Energiewende beschleunigen', desc: 'Langfristig weg vom Öl.', effects: { oil: 0.6, money: 0.4, groups: { greens: 8, youth: 3 }, stats: { environment: 2 }, econ: { inflation: 0.8 } } },
      { label: 'Nicht eingreifen', desc: 'Die Preise regeln sich selbst.', effects: { oil: 0.6, econ: { inflation: 1.5 }, groups: { workers: -6, retirees: -4 } } },
    ] },

  { id: 'oelverfall', icon: '⛽', cat: 'wirtschaft', title: 'Ölpreis bricht ein',
    weight: 0.5,
    text: 'Die großen Förderländer fluten den Markt: Der Ölpreis fällt um 35 %. Für Importeure ein Segen, für Exporteure ein Albtraum.',
    choices: [
      { label: 'Strategische Reserve auffüllen', desc: 'Günstig einkaufen für schlechte Zeiten.', effects: { oil: -0.4, money: 0.15, stats: { security: 2 } } },
      { label: 'Zur Kenntnis nehmen', effects: { oil: -0.4 } },
    ] },

  { id: 'techboom', icon: '🤖', cat: 'wirtschaft', title: 'Technologie-Boom',
    weight: 0.8,
    text: 'Heimische Tech-Firmen erleben einen Höhenflug. Investoren aus aller Welt wollen einsteigen.',
    choices: [
      { label: 'Steuervorteile für Tech-Firmen', effects: { money: 0.2, groups: { business: 6, youth: 3 }, mods: [{ key: 'growth', value: 0.6, months: 12 }] } },
      { label: 'In MINT-Bildung investieren', desc: 'Langfristig mehr Fachkräfte.', effects: { money: 0.3, stats: { education: 3 }, groups: { youth: 5 }, mods: [{ key: 'growth', value: 0.3, months: 12 }] } },
      { label: 'Den Boom laufen lassen', effects: { mods: [{ key: 'growth', value: 0.25, months: 6 }] } },
    ] },

  { id: 'fabrik', icon: '🏗️', cat: 'wirtschaft', title: 'Weltkonzern plant Riesenfabrik',
    weight: 0.8,
    text: 'Ein internationaler Konzern will eine Gigafabrik mit 15.000 Arbeitsplätzen bauen – und verlangt Subventionen.',
    choices: [
      { label: 'Subventionen zahlen', effects: { money: 0.4, groups: { workers: 6, greens: -4 }, mods: [{ key: 'unemployment', value: -0.5, months: 24 }, { key: 'growth', value: 0.3, months: 24 }] } },
      { label: 'Ohne Subventionen verhandeln', effects: { capital: -5, chance: { p: 0.45, success: { text: 'Der Konzern baut trotzdem!', mods: [{ key: 'unemployment', value: -0.5, months: 24 }, { key: 'growth', value: 0.3, months: 24 }], groups: { workers: 5 } },
        fail: { text: 'Der Konzern baut im Nachbarland.', stats: { approval: -2 } } } } },
      { label: 'Ablehnen – Umweltbedenken', effects: { groups: { greens: 6, workers: -4 } } },
    ] },

  { id: 'bankenpleite', icon: '🏚️', cat: 'wirtschaft', title: 'Großbank vor der Pleite',
    weight: 0.4,
    text: 'Eine der größten Banken des Landes steht vor dem Kollaps. Millionen Sparer bangen um ihr Geld.',
    choices: [
      { label: 'Bank retten', effects: { money: 1.5, groups: { business: 5, workers: -8, youth: -4 } } },
      { label: 'Verstaatlichen', effects: { money: 1.0, groups: { business: -12, workers: 6 } } },
      { label: 'Pleite gehen lassen', effects: { groups: { business: -10, retirees: -6 }, econ: { unemployment: 0.8 }, mods: [{ key: 'growth', value: -1.0, months: 6 }] } },
    ] },

  { id: 'teuerungsprotest', icon: '🧾', cat: 'wirtschaft', title: 'Proteste gegen die Teuerung',
    cond: s => s.econ.inflation > s.country.inflBase + 3, weight: 2,
    text: 'Die Preise für Lebensmittel und Energie steigen ungebremst. Tausende demonstrieren gegen die Inflation.',
    choices: [
      { label: 'Preisdeckel für Grundnahrungsmittel', effects: { groups: { workers: 8, business: -8 }, mods: [{ key: 'inflation', value: -1.0, months: 6 }, { key: 'growth', value: -0.3, months: 12 }] } },
      { label: 'Zentralbank zu Zinserhöhung drängen', effects: { groups: { business: -4, retirees: 4 }, mods: [{ key: 'inflation', value: -2.0, months: 12 }, { key: 'growth', value: -0.8, months: 12 }] } },
      { label: 'Sozialhilfe erhöhen', effects: { money: 0.4, groups: { workers: 6, retirees: 4 } } },
    ] },

  { id: 'ki_jobs', icon: '🦾', cat: 'wirtschaft', title: 'KI ersetzt Hunderttausende Jobs',
    weight: 0.6,
    text: 'Künstliche Intelligenz automatisiert Büros, Callcenter und Logistik. Die Produktivität steigt – die Angst auch.',
    choices: [
      { label: 'Umschulungsprogramm', effects: { money: 0.4, groups: { workers: 6 }, mods: [{ key: 'unemployment', value: -0.4, months: 12 }, { key: 'growth', value: 0.3, months: 12 }] } },
      { label: 'KI-Steuer einführen', effects: { money: -0.3, groups: { workers: 6, business: -8, youth: -2 }, mods: [{ key: 'growth', value: -0.2, months: 24 }] } },
      { label: 'Fortschritt laufen lassen', effects: { groups: { workers: -8, business: 8 }, mods: [{ key: 'growth', value: 0.7, months: 12 }, { key: 'unemployment', value: 0.8, months: 12 }] } },
    ] },

  { id: 'rohstoffe', icon: '⛏️', cat: 'wirtschaft', title: 'Riesige Rohstoffvorkommen entdeckt',
    weight: 0.4, once: true,
    text: 'Geologen haben gewaltige Vorkommen an Lithium und seltenen Erden gefunden. Ein Milliardenschatz – mitten in einem Naturschutzgebiet.',
    choices: [
      { label: 'Staatlicher Abbau', effects: { money: -0.5, groups: { workers: 5, greens: -8 }, stats: { environment: -3 }, mods: [{ key: 'growth', value: 0.5, months: 36 }] } },
      { label: 'Lizenzen an Konzerne', effects: { money: -0.8, groups: { business: 6, greens: -6 }, stats: { corruption: 3, environment: -3 }, mods: [{ key: 'growth', value: 0.4, months: 24 }] } },
      { label: 'Unter Schutz stellen', effects: { groups: { greens: 10, youth: 3 }, stats: { environment: 2, reputation: 2 } } },
    ] },

  { id: 'rezession_welt', icon: '🌧️', cat: 'wirtschaft', title: 'Globale Rezession',
    weight: 0.35,
    text: 'Die Weltwirtschaft schrumpft. Exporte brechen ein, Unternehmen streichen Stellen.',
    choices: [
      { label: 'Gegensteuern mit Investitionen', effects: { money: 1.0, mods: [{ key: 'growth', value: -0.8, months: 12 }], groups: { workers: 3 } } },
      { label: 'Abwarten und sparen', effects: { mods: [{ key: 'growth', value: -1.5, months: 12 }], groups: { conservatives: 3, workers: -4 } } },
    ] },

  { id: 'aufschwung_welt', icon: '☀️', cat: 'wirtschaft', title: 'Weltwirtschaft brummt',
    weight: 0.5,
    text: 'Die globale Konjunktur zieht kräftig an. Die Auftragsbücher deiner Firmen sind voll.',
    choices: [
      { label: 'Rückenwind nutzen – Schulden tilgen', effects: { money: -0.4, mods: [{ key: 'growth', value: 0.6, months: 12 }], groups: { conservatives: 3 } } },
      { label: 'Rückenwind nutzen – Löhne steigen lassen', effects: { mods: [{ key: 'growth', value: 0.8, months: 12 }], groups: { workers: 4 } } },
    ] },

  { id: 'rating', icon: '📊', cat: 'wirtschaft', title: 'Ratingagentur stuft dich herab',
    cond: s => s.econ.debt > s.country.debt + 15 || s.budget.interestShare > 0.18, weight: 2.5,
    text: 'Eine große Ratingagentur senkt die Kreditwürdigkeit deines Landes. Investoren verlangen höhere Zinsen.',
    choices: [
      { label: 'Glaubwürdigen Sparplan vorlegen', desc: 'Signal an die Märkte.', effects: { capital: -10, groups: { workers: -4, retirees: -3, conservatives: 5 } } },
      { label: 'Ignorieren', effects: { mods: [{ key: 'interest', value: 1.5, months: 24 }] } },
    ] },

  { id: 'wohnungsnot', icon: '🏢', cat: 'wirtschaft', title: 'Mieten explodieren',
    weight: 0.8,
    text: 'In den Städten sind Wohnungen kaum noch bezahlbar. Junge Familien und Studenten gehen auf die Straße.',
    choices: [
      { label: 'Wohnungsbauprogramm', effects: { money: 0.5, groups: { youth: 6, workers: 5 }, mods: [{ key: 'growth', value: 0.2, months: 12 }] } },
      { label: 'Mietendeckel', effects: { groups: { youth: 8, workers: 3, business: -8 }, mods: [{ key: 'growth', value: -0.15, months: 12 }] } },
      { label: 'Markt regeln lassen', effects: { groups: { youth: -6, workers: -4, business: 4 } } },
    ] },

  { id: 'tourismus_boom', icon: '🏝️', cat: 'wirtschaft', title: 'Rekord-Tourismussaison',
    weight: 0.6,
    text: 'So viele Touristen wie nie zuvor besuchen dein Land. Hotels und Restaurants melden Rekordumsätze.',
    choices: [
      { label: 'In Infrastruktur investieren', effects: { money: 0.1, mods: [{ key: 'growth', value: 0.3, months: 12 }], groups: { business: 3 } } },
      { label: 'Tourismusabgabe einführen', effects: { money: -0.15, groups: { business: -3 } } },
    ] },

  // ═════════════ SOZIALES / GESELLSCHAFT ═════════════
  { id: 'pandemie', icon: '🦠', cat: 'soziales', title: 'Neues Virus breitet sich aus',
    weight: 0.25, cooldown: 120,
    text: 'Ein unbekanntes Virus verbreitet sich rasant. Krankenhäuser füllen sich, die Welt hält den Atem an.',
    choices: [
      { label: 'Harter Lockdown', effects: { stats: { health: 4, stability: -5 }, groups: { youth: -8, business: -12, retirees: 8 }, mods: [{ key: 'growth', value: -2.5, months: 6 }], money: 1.0 } },
      { label: 'Gezielte Maßnahmen', desc: 'Masken, Tests, Schutz der Risikogruppen.', effects: { money: 0.6, stats: { health: -3 }, mods: [{ key: 'growth', value: -0.8, months: 6 }] } },
      { label: 'Normal weitermachen', effects: { stats: { health: -12, approval: -6 }, groups: { retirees: -15 }, mods: [{ key: 'growth', value: -0.5, months: 4 }] } },
    ] },

  { id: 'erdbeben', icon: '🌋', cat: 'soziales', title: 'Schweres Erdbeben',
    weight: 0.5,
    text: 'Ein Erdbeben der Stärke 7,1 erschüttert eine Region deines Landes. Tausende sind obdachlos.',
    choices: [
      { label: 'Massive Hilfe und Wiederaufbau', effects: { money: 0.6, stats: { approval: 4, stability: 2 } } },
      { label: 'Internationale Hilfe annehmen', effects: { money: 0.2, stats: { approval: 1, reputation: 1 } } },
      { label: 'Minimale Hilfe', effects: { money: 0.05, stats: { approval: -8, stability: -5 } } },
    ] },

  { id: 'hochwasser', icon: '🌊', cat: 'soziales', title: 'Jahrhunderthochwasser',
    weight: 0.6,
    text: 'Tagelanger Starkregen lässt die Flüsse über die Ufer treten. Ganze Dörfer stehen unter Wasser.',
    choices: [
      { label: 'Fluthilfe und neue Deiche', effects: { money: 0.5, stats: { approval: 3 } } },
      { label: 'Soforthilfe – mehr nicht', effects: { money: 0.15, stats: { approval: -1 } } },
      { label: 'Klimaschutz als Antwort verschärfen', effects: { money: 0.3, capital: -8, groups: { greens: 10, youth: 3 }, stats: { environment: 3 } } },
    ] },

  { id: 'duerre', icon: '🏜️', cat: 'soziales', title: 'Dürre vernichtet die Ernte',
    weight: 0.6,
    text: 'Monatelang kein Regen: Die Ernte fällt zur Hälfte aus. Bauern stehen vor dem Ruin.',
    choices: [
      { label: 'Bauern entschädigen', effects: { money: 0.3, groups: { conservatives: 5 } } },
      { label: 'Lebensmittel importieren', effects: { money: 0.1, econ: { inflation: 0.5 } } },
      { label: 'Nichts tun', effects: { econ: { inflation: 1.2 }, groups: { workers: -5, conservatives: -6 } } },
    ] },

  { id: 'rentenkasse', icon: '👵', cat: 'soziales', title: 'Rentenkasse in Not',
    weight: 0.6,
    text: 'Die Bevölkerung altert, die Rentenkasse hat ein Milliardenloch. Eine Lösung muss her.',
    choices: [
      { label: 'Beiträge erhöhen', effects: { money: -0.3, groups: { workers: -6, business: -4 } } },
      { label: 'Renten kürzen', effects: { money: -0.5, groups: { retirees: -15 } } },
      { label: 'Mit Schulden stopfen', effects: { money: 0.6, groups: { conservatives: -4, retirees: 2 } } },
    ] },

  { id: 'lehrermangel', icon: '🧑‍🏫', cat: 'soziales', title: 'Dramatischer Lehrermangel',
    weight: 0.6,
    text: 'An vielen Schulen fällt jede vierte Stunde aus. Eltern sind wütend.',
    choices: [
      { label: 'Bildungsoffensive', effects: { money: 0.3, stats: { education: 3 }, groups: { youth: 5 } } },
      { label: 'Quereinsteiger zulassen', effects: { capital: -5, stats: { education: 1 } } },
      { label: 'Abwarten', effects: { stats: { education: -4 }, groups: { youth: -6, workers: -2 } } },
    ] },

  { id: 'pflegestreik', icon: '🩺', cat: 'soziales', title: 'Ärzte und Pflegekräfte streiken',
    weight: 0.6,
    text: 'Das Gesundheitspersonal ist am Limit und legt die Arbeit nieder. Operationen werden verschoben.',
    choices: [
      { label: 'Mehr Geld für das Gesundheitswesen', effects: { money: 0.3, stats: { health: 3 }, groups: { retirees: 4, workers: 2 } } },
      { label: 'Forderungen ablehnen', effects: { stats: { health: -4 }, groups: { retirees: -6, workers: -3 } } },
    ] },

  { id: 'fluechtlinge', icon: '⛺', cat: 'soziales', title: 'Flüchtlingswelle', ctx: 'random',
    weight: 0.6,
    text: 'Nach Unruhen in der Region suchen Hunderttausende Menschen Schutz in deinem Land.',
    choices: [
      { label: 'Menschen aufnehmen', effects: { money: 0.4, stats: { reputation: 8, stability: -3 }, groups: { conservatives: -12, youth: 5 } } },
      { label: 'Grenzen schließen', effects: { stats: { reputation: -8 }, groups: { conservatives: 10, youth: -8 } } },
      { label: 'Internationale Verteilung verhandeln', effects: { capital: -12, stats: { reputation: 3 }, groups: { conservatives: -3 } } },
    ] },

  { id: 'klimaprotest', icon: '🪧', cat: 'soziales', title: 'Klimaaktivisten blockieren {capital}',
    weight: s => s.groups.greens < 45 ? 1.5 : 0.5,
    text: 'Tausende Klimaaktivisten kleben sich auf die Straßen von {capital}. Der Verkehr bricht zusammen.',
    choices: [
      { label: 'Forderungen aufgreifen', effects: { capital: -10, groups: { greens: 12, business: -5 } } },
      { label: 'Gespräche anbieten', effects: { capital: -4, groups: { greens: 4 } } },
      { label: 'Hart durchgreifen', effects: { groups: { greens: -12, conservatives: 6, youth: -6 } } },
    ] },

  { id: 'chemieunfall', icon: '☣️', cat: 'soziales', title: 'Unfall in Chemiewerk',
    weight: 0.5,
    text: 'Eine Explosion in einem Chemiewerk verseucht einen Fluss. Fischsterben auf hunderten Kilometern.',
    choices: [
      { label: 'Strenge Auflagen für die Industrie', effects: { stats: { environment: 4 }, groups: { greens: 6, business: -6 } } },
      { label: 'Konzern zahlt eine Strafe', effects: { money: -0.1, groups: { greens: -6 }, stats: { approval: -2, environment: -2 } } },
    ] },

  { id: 'weltmeister', icon: '🏆', cat: 'soziales', title: 'Die Nationalmannschaft ist Weltmeister!',
    weight: 0.3, cooldown: 48,
    text: 'Unglaublich! Das ganze Land feiert den größten Sporterfolg seiner Geschichte.',
    choices: [
      { label: 'Großer Empfang in {capital}', effects: { money: 0.01, stats: { approval: 7, stability: 3 } } },
      { label: 'Nur gratulieren', effects: { stats: { approval: 3, stability: 2 } } },
    ] },

  { id: 'olympia', icon: '🏅', cat: 'soziales', title: 'Bewerbung für Olympische Spiele',
    weight: 0.3, once: true,
    text: 'Das Olympische Komitee lädt dein Land ein, sich für die Spiele in acht Jahren zu bewerben.',
    choices: [
      { label: 'Bewerben!', effects: { money: 0.3, chance: { p: 0.5, success: { text: 'Zuschlag! Die Spiele kommen in dein Land.', stats: { approval: 5, reputation: 8 }, mods: [{ key: 'growth', value: 0.3, months: 24 }] },
        fail: { text: 'Leider verloren – ein anderes Land bekommt den Zuschlag.', stats: { approval: -2 } } } } },
      { label: 'Verzichten – zu teuer', effects: { groups: { conservatives: 2 } } },
    ] },

  { id: 'popstar', icon: '🎤', cat: 'soziales', title: 'Superstar unterstützt die Regierung',
    weight: 0.4,
    text: 'Ein weltberühmter Popstar lobt deine Politik in einem viralen Video.',
    choices: [
      { label: 'Gemeinsamer Auftritt', effects: { stats: { approval: 3 }, groups: { youth: 6, conservatives: -2 } } },
      { label: 'Dankend Distanz halten', effects: { stats: { approval: 1 } } },
    ] },

  { id: 'forschung', icon: '🔬', cat: 'soziales', title: 'Durchbruch in der Forschung',
    weight: 0.5,
    text: 'Forscher einer staatlichen Universität entwickeln eine bahnbrechende Batterietechnologie.',
    choices: [
      { label: 'Massiv fördern', effects: { money: 0.2, stats: { education: 3 }, mods: [{ key: 'growth', value: 0.3, months: 18 }] } },
      { label: 'Patent verkaufen', effects: { money: -0.3, groups: { youth: -3 } } },
    ] },

  { id: 'blackout', icon: '🔌', cat: 'soziales', title: 'Landesweiter Blackout',
    weight: 0.4,
    text: 'Ein Defekt im Stromnetz legt das ganze Land für 30 Stunden lahm.',
    choices: [
      { label: 'Stromnetz modernisieren', effects: { money: 0.6, mods: [{ key: 'growth', value: 0.2, months: 24 }] } },
      { label: 'Notreparatur', effects: { money: 0.1, stats: { approval: -3 } } },
    ] },

  // ═════════════ POLITIK ═════════════
  { id: 'korruptionsskandal', icon: '💰', cat: 'politik', title: 'Korruptionsskandal im Ministerium',
    weight: s => 0.4 + s.stats.corruption / 50,
    text: 'Journalisten decken auf: Ein Minister hat Millionen an Schmiergeldern kassiert.',
    choices: [
      { label: 'Minister entlassen', effects: { capital: -5, stats: { approval: 2, corruption: -3 } } },
      { label: 'Unabhängige Untersuchung', effects: { capital: -10, stats: { corruption: -6, approval: -1, reputation: 3 } } },
      { label: 'Vertuschen', effects: { chance: { p: 0.6, success: { text: 'Die Geschichte verläuft im Sand.', stats: { corruption: 2 } },
        fail: { text: 'Die Vertuschung fliegt auf – ein Desaster!', stats: { approval: -10, stability: -5, corruption: 3 } } } } },
    ] },

  { id: 'demonstration', icon: '📢', cat: 'politik', title: 'Massendemonstrationen gegen die Regierung',
    cond: s => s.approval < 40, weight: 2,
    text: 'Hunderttausende fordern deinen Rücktritt. Die Proteste wachsen von Tag zu Tag.',
    choices: [
      { label: 'Dialog anbieten', effects: { capital: -10, stats: { approval: 3, stability: 3 } } },
      { label: 'Polizei räumt die Plätze', effects: { stats: { stability: 5, reputation: -8, approval: -4 }, groups: { youth: -15, conservatives: 4 } } },
      { label: 'Aussitzen', effects: { stats: { stability: -6, approval: -2 } } },
    ] },

  { id: 'medienskandal', icon: '🗞️', cat: 'politik', title: 'Schwere Vorwürfe gegen dich',
    weight: 0.6,
    text: 'Eine große Zeitung behauptet, du hättest im Wahlkampf illegale Spenden angenommen.',
    choices: [
      { label: 'Alles dementieren', effects: { chance: { p: 0.55, success: { text: 'Die Vorwürfe lassen sich nicht beweisen.', stats: { approval: 1 } },
        fail: { text: 'Neue Dokumente tauchen auf. Peinlich!', stats: { approval: -8 } } } } },
      { label: 'Fehler einräumen und entschuldigen', effects: { stats: { approval: -3, reputation: 2, stability: 1 } } },
      { label: 'Zeitung verklagen', effects: { stats: { approval: -1, reputation: -5 }, groups: { youth: -6, conservatives: 2 } } },
    ] },

  { id: 'unruhen_provinz', icon: '🔥', cat: 'politik', title: 'Unruhen in einer Provinz',
    cond: s => s.stats.stability < 50, weight: 1.5,
    text: 'In einer abgehängten Region kommt es zu gewaltsamen Unruhen. Separatisten gewinnen Zulauf.',
    choices: [
      { label: 'Autonomie anbieten', effects: { capital: -15, stats: { stability: 6 }, groups: { conservatives: -5 } } },
      { label: 'Investitionsprogramm für die Region', effects: { money: 0.4, stats: { stability: 4 } } },
      { label: 'Militär entsenden', effects: { stats: { stability: 3, reputation: -6 }, groups: { youth: -8, military: 4 } } },
    ] },

  { id: 'putschgeruecht', icon: '🪖', cat: 'politik', title: 'Gerüchte über Putschpläne',
    cond: s => s.groups.military < 35, weight: 3,
    text: 'Dein Geheimdienst warnt: Hochrangige Offiziere treffen sich heimlich. Die Armee ist unzufrieden.',
    choices: [
      { label: 'Mehr Geld fürs Militär zusagen', effects: { money: 0.3, groups: { military: 15 } } },
      { label: 'Verdächtige Generäle entlassen', effects: { chance: { p: 0.7, success: { text: 'Die Verschwörung ist zerschlagen.', groups: { military: -3 }, stats: { stability: 3 } },
        fail: { text: 'Ein Teil der Armee rebelliert – blutige Kämpfe in der Hauptstadt!', stats: { stability: -15, approval: -5 }, groups: { military: -10 } } } } },
      { label: 'Ignorieren', effects: { groups: { military: -5 } } },
    ] },

  { id: 'wahlmanipulation', icon: '🕸️', cat: 'politik', title: 'Ausländische Wahlbeeinflussung', ctx: 'rival',
    cond: s => s.country.gov === 'demokratie' && s.nextElection - s.month <= 12, weight: 1,
    text: 'Hinweise verdichten sich: Trollfabriken aus {land} verbreiten massenhaft Falschnachrichten über dich.',
    choices: [
      { label: 'Öffentlich anprangern', effects: { relation: -15, stats: { approval: 2 } } },
      { label: 'Still untersuchen und abwehren', effects: { capital: -8, stats: { stability: 3 } } },
    ] },

  { id: 'terror', icon: '💣', cat: 'militaer', title: 'Terroranschlag in {capital}',
    weight: s => s.terror / 45,
    text: 'Ein Anschlag erschüttert {capital}. Es gibt zahlreiche Tote. Das Land ist im Schock.',
    choices: [
      { label: 'Sicherheitsgesetze verschärfen', effects: { stats: { security: 6, reputation: -2 }, groups: { youth: -6, conservatives: 8 } } },
      { label: 'Besonnen reagieren – Einheit zeigen', effects: { stats: { approval: 2, reputation: 3, stability: -2 } } },
      { label: 'Militärschlag gegen Terrorcamps', effects: { money: 0.3, stats: { security: 3, reputation: -4 }, groups: { military: 8, conservatives: 4, youth: -4 } } },
    ] },

  { id: 'cyberangriff', icon: '👾', cat: 'militaer', title: 'Cyberangriff auf das Stromnetz', ctx: 'rival',
    weight: s => 'cyber' in s.policies ? 0.2 : 0.7,
    text: 'Hacker – vermutlich aus {land} – legen Teile der Energieversorgung lahm.',
    choices: [
      { label: 'Cyberabwehr massiv ausbauen', effects: { money: 0.3, stats: { security: 4 } } },
      { label: 'Gegenangriff auf {land}', effects: { relation: -20, groups: { military: 5 }, chance: { p: 0.6, success: { text: 'Der Gegenschlag sitzt – {land} ist gewarnt.', stats: { approval: 2 } },
        fail: { text: 'Der Gegenangriff wird öffentlich – diplomatisches Chaos.', stats: { reputation: -5 } } } } },
      { label: 'Schäden beheben', effects: { money: 0.1, stats: { approval: -3 }, mods: [{ key: 'growth', value: -0.3, months: 3 }] } },
    ] },

  // ═════════════ MILITÄR & DIPLOMATIE ═════════════
  { id: 'grenzzwischenfall', icon: '⚔️', cat: 'militaer', title: 'Grenzzwischenfall mit {land}', ctx: 'rival',
    cond: s => !s.wars.length, weight: s => s._rivalRel < -20 ? 1.2 : 0.2,
    text: 'Soldaten aus {land} haben die Grenze überschritten. Es gab einen Schusswechsel. Die Lage ist angespannt.',
    choices: [
      { label: 'Diplomatische Lösung suchen', effects: { capital: -10, relation: 10 } },
      { label: 'Truppen an die Grenze verlegen', effects: { money: 0.2, relation: -15, groups: { military: 6, conservatives: 4 } } },
      { label: 'Krieg erklären!', desc: 'Nur bei sehr schlechten Beziehungen sinnvoll – ein Krieg ist teuer und riskant.', effects: { war: true } },
    ] },

  { id: 'handelsangebot', icon: '📜', cat: 'diplomatie', title: '{land} bietet ein Handelsabkommen an', ctx: 'nottrade',
    weight: 1,
    text: 'Die Regierung von {land} möchte ein umfassendes Freihandelsabkommen mit deinem Land abschließen.',
    choices: [
      { label: 'Annehmen', effects: { trade: true, relation: 10, groups: { business: 5, workers: -2 } } },
      { label: 'Nachverhandeln', effects: { capital: -5, chance: { p: 0.6, success: { text: 'Bessere Konditionen erreicht!', trade: true, relation: 10, groups: { business: 5 } },
        fail: { text: '{land} bricht die Verhandlungen ab.', relation: -5 } } } },
      { label: 'Ablehnen', effects: { relation: -10, groups: { workers: 2 } } },
    ] },

  { id: 'waffendeal', icon: '🚀', cat: 'diplomatie', title: '{land} will Waffen kaufen', ctx: 'random',
    weight: 0.6,
    text: '{land} bietet Milliarden für Panzer und Kampfjets aus deiner Rüstungsindustrie.',
    choices: [
      { label: 'Verkaufen', effects: { money: -0.3, relation: 15, stats: { reputation: -5 }, groups: { military: 4, business: 3, greens: -8 } } },
      { label: 'Ablehnen', effects: { relation: -5, stats: { reputation: 2 } } },
    ] },

  { id: 'spionage', icon: '🕵️', cat: 'diplomatie', title: 'Spione aus {land} enttarnt', ctx: 'rival',
    weight: 0.7,
    text: 'Dein Geheimdienst hat ein Spionagenetzwerk aus {land} in mehreren Ministerien aufgedeckt.',
    choices: [
      { label: 'Diplomaten ausweisen', effects: { relation: -20, groups: { conservatives: 5 } } },
      { label: 'Stille Diplomatie', effects: { relation: -5, capital: -5 } },
      { label: 'Doppelagenten einsetzen', effects: { chance: { p: 0.5, success: { text: 'Wertvolle Informationen gewonnen!', stats: { security: 4 }, groups: { military: 3 } },
        fail: { text: 'Die Operation fliegt auf.', relation: -25, stats: { reputation: -3 } } } } },
    ] },

  { id: 'katastrophe_ausland', icon: '🆘', cat: 'diplomatie', title: 'Katastrophe in {land}', ctx: 'random',
    weight: 0.8,
    text: 'Ein verheerender Wirbelsturm hat {land} getroffen. Die Regierung bittet um internationale Hilfe.',
    choices: [
      { label: 'Großzügig helfen', effects: { money: 0.12, relation: 20, stats: { reputation: 5 } } },
      { label: 'Symbolische Hilfe', effects: { money: 0.02, relation: 5 } },
      { label: 'Keine Hilfe', effects: { relation: -5, stats: { reputation: -3 } } },
    ] },

  { id: 'bundeshilfe', icon: '🤝', cat: 'diplomatie', title: 'Verbündeter {land} bittet um Hilfe', ctx: 'ally',
    weight: 0.6,
    text: '{land} kämpft gegen eine Terrormiliz und bittet dich als Verbündeten um militärische Unterstützung.',
    choices: [
      { label: 'Truppen schicken', effects: { money: 0.3, relation: 15, groups: { military: 5, youth: -4 }, stats: { military: -1 } } },
      { label: 'Waffen liefern', effects: { money: 0.15, relation: 8 } },
      { label: 'Ablehnen', effects: { relation: -15, groups: { greens: 2 } } },
    ] },

  { id: 'sanktionsdrohung', icon: '🚫', cat: 'diplomatie', title: 'Internationale Sanktionen drohen',
    cond: s => s.stats.reputation < 35, weight: 2,
    text: 'Die Weltgemeinschaft ist empört über deine Politik und droht mit harten Wirtschaftssanktionen.',
    choices: [
      { label: 'Zugeständnisse machen', effects: { capital: -15, stats: { reputation: 8 } } },
      { label: 'Trotzig bleiben', effects: { mods: [{ key: 'growth', value: -0.7, months: 12 }], stats: { reputation: -5 }, groups: { conservatives: 4 } } },
    ] },

  { id: 'eklat', icon: '😤', cat: 'diplomatie', title: 'Diplomatischer Eklat mit {land}', ctx: 'random',
    weight: 0.6,
    text: 'Der Regierungschef von {land} hat dein Land in einer Rede öffentlich beleidigt.',
    choices: [
      { label: 'Scharf zurückschlagen', effects: { relation: -12, stats: { approval: 1 }, groups: { conservatives: 4 } } },
      { label: 'Botschafter einbestellen', effects: { relation: -5 } },
      { label: 'Souverän ignorieren', effects: { stats: { reputation: 1 } } },
    ] },

  { id: 'gipfel', icon: '🌐', cat: 'diplomatie', title: 'Einladung zum Weltgipfel',
    weight: 0.6,
    text: 'Die mächtigsten Staatschefs treffen sich. Du bist eingeladen, eine Rede zu halten.',
    choices: [
      { label: 'Teilnehmen und Führung zeigen', effects: { capital: -5, stats: { reputation: 5, approval: 1 } } },
      { label: 'Absagen – zu Hause ist genug zu tun', effects: { stats: { reputation: -3 } } },
    ] },

  { id: 'angriff', icon: '🔥', cat: 'militaer', title: '{land} greift an!', ctx: 'rival',
    cond: s => s._rivalRel < -70 && !s.wars.length, weight: 0.5, cooldown: 60,
    text: 'Truppen aus {land} sind über die Grenze vorgerückt. Dein Land wird angegriffen!',
    choices: [
      { label: 'Das Land verteidigen!', effects: { war: true, forced: true } },
      { label: 'Kapitulieren – Gebiete abtreten', effects: { money: 2.0, relation: 30, stats: { approval: -15, stability: -10, reputation: -5 }, groups: { military: -15, conservatives: -10 } } },
    ] },

  // ═════════════ AUTORITÄRE STAATEN ═════════════
  { id: 'palastintrige', icon: '🗡️', cat: 'politik', title: 'Intrige im Machtzentrum',
    cond: s => s.country.gov === 'autoritaer', weight: 1.2,
    text: 'Dein Geheimdienst meldet: Ein mächtiger Minister sammelt Verbündete in Partei und Armee, um dich zu stürzen.',
    choices: [
      { label: 'Säuberung anordnen', effects: { chance: { p: 0.7, success: { text: 'Der Verräter sitzt hinter Gittern. Niemand wagt es mehr, dich herauszufordern.', stats: { stability: 3, reputation: -4 } },
        fail: { text: 'Die Säuberung löst Chaos in der Elite aus.', stats: { stability: -10 }, groups: { military: -8 } } } } },
      { label: 'Den Minister mit Posten ruhigstellen', effects: { money: 0.2, stats: { corruption: 4 } } },
      { label: 'Abwarten und beobachten', effects: { chance: { p: 0.5, success: { text: 'Die Intrige verläuft im Sand.' }, fail: { text: 'Der Minister schlägt los – das Land ist erschüttert.', stats: { stability: -12, approval: -5 } } } } },
    ] },

  { id: 'demokratiebewegung', icon: '🕯️', cat: 'politik', title: 'Demokratiebewegung wächst',
    cond: s => s.country.gov === 'autoritaer' && s.groups.youth < 55, weight: 1.5,
    text: 'Studenten und junge Berufstätige fordern freie Wahlen und Meinungsfreiheit. Die Proteste breiten sich über soziale Medien aus.',
    choices: [
      { label: 'Vorsichtige Reformen zulassen', effects: { capital: -10, stats: { stability: -5, reputation: 10 }, groups: { youth: 12, military: -4 } } },
      { label: 'Zugeständnisse: Jobs & Geld für die Jugend', effects: { money: 0.4, groups: { youth: 6 } } },
      { label: 'Proteste niederschlagen', effects: { stats: { reputation: -12 }, groups: { youth: -15, military: 3 }, chance: { p: 0.7, success: { text: 'Die Straßen sind wieder ruhig – vorerst.', stats: { stability: 4 } },
        fail: { text: 'Die Gewalt heizt die Proteste erst richtig an!', stats: { stability: -15 } } } } },
    ] },

  // ═════════════ TERRORABWEHR & SPEZIALKRÄFTE ═════════════
  // chance.sf = true: Erfolgschance hängt von der Qualität deiner Spezialeinheit ab (p = Grundwert)
  { id: 'terrorwarnung', icon: '📡', cat: 'militaer', title: 'Geheimdienst warnt vor Anschlag',
    weight: s => s.terror / 35,
    text: 'Abgefangene Nachrichten deuten darauf hin, dass eine Terrorzelle in den nächsten Tagen zuschlagen will. Der Aufenthaltsort ist bekannt.',
    choices: [
      { label: 'Zugriff durch {sf}', desc: 'Die Eliteeinheit schlägt zuerst zu.', effects: { chance: { sf: true, p: 0.35,
        success: { text: '{sf} nimmt die Zelle fest, bevor sie zuschlagen kann.', terror: -25, stats: { approval: 3, security: 2 } },
        fail: { text: 'Der Zugriff misslingt, einige Verdächtige entkommen.', terror: 5, stats: { approval: -5, stability: -3 } } } } },
      { label: 'Polizei-Großeinsatz', effects: { money: 0.05, terror: -10, groups: { youth: -2 } } },
      { label: 'Öffentlich warnen', effects: { terror: -5, stats: { approval: -1 }, mods: [{ key: 'growth', value: -0.1, months: 2 }] } },
    ] },

  { id: 'geiselnahme', icon: '🚨', cat: 'militaer', title: 'Geiselnahme in {capital}',
    weight: s => s.terror / 60, cooldown: 24,
    text: 'Bewaffnete haben in {capital} Dutzende Menschen in ihre Gewalt gebracht und stellen politische Forderungen. Das ganze Land schaut zu.',
    choices: [
      { label: '{sf} befreit die Geiseln', desc: 'Riskant – das Ergebnis hängt von der Ausbildung der Einheit ab.', effects: { chance: { sf: true, p: 0.3,
        success: { text: '{sf} befreit alle Geiseln unverletzt. Das Land feiert die Einheit.', stats: { approval: 8 }, terror: -10, sfQuality: 2, groups: { military: 4 } },
        fail: { text: 'Die Befreiung endet tragisch. Es gibt Opfer unter den Geiseln.', stats: { approval: -12, stability: -4 }, sfQuality: -5 } } } },
      { label: 'Verhandeln', effects: { capital: -8, chance: { p: 0.6, success: { text: 'Die Geiselnehmer geben nach zähen Verhandlungen auf.', stats: { approval: 3 } },
        fail: { text: 'Die Verhandlungen scheitern – die Lage eskaliert.', stats: { approval: -6, stability: -2 } } } } },
      { label: 'Forderungen erfüllen', effects: { money: 0.05, terror: 10, stats: { approval: -4, reputation: -3 } } },
    ] },

  { id: 'terrorfuehrer', icon: '🎯', cat: 'militaer', title: 'Terrorführer in {land} aufgespürt', ctx: 'unsafe',
    weight: s => 0.3 + s.terror / 80,
    text: 'Der Kopf eines Terrornetzwerks, das Anschläge in deinem Land geplant hat, versteckt sich in {land}. Die dortige Regierung ist unwillig oder unfähig, ihn auszuliefern.',
    choices: [
      { label: 'Kommandoeinsatz von {sf}', desc: 'Grenzübertritt ohne Erlaubnis – belastet die Beziehung zu {land}.', effects: { relation: -12, chance: { sf: true, p: 0.2,
        success: { text: '{sf} fasst den Gesuchten und bringt ihn vor Gericht.', stats: { approval: 6 }, terror: -20, groups: { military: 4, conservatives: 3 } },
        fail: { text: 'Der Einsatz scheitert und wird öffentlich.', stats: { approval: -6, reputation: -4 }, relation: -15, sfQuality: -5 } } } },
      { label: 'Auslieferung fordern', effects: { capital: -8, relation: -3, chance: { p: 0.35, success: { text: '{land} liefert den Gesuchten aus.', stats: { approval: 3 }, terror: -10 },
        fail: { text: '{land} weigert sich.' } } } },
      { label: 'Informationen an Partner weitergeben', effects: { relation: 5, terror: -5 } },
    ] },
];
