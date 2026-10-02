// Test für aggressives Spiel: Ein "Eroberer-Bot" rüstet auf, stellt Ultimaten,
// erklärt schwächeren Ländern den Krieg und annektiert sie.
// Aufruf: node tools/aggro-test.js [land] [durchläufe]
const fs = require('fs'), vm = require('vm'), path = require('path');
const root = path.join(__dirname, '..');
const files = ['js/data/worldmap.js', 'js/data/countries.js', 'js/data/policies.js', 'js/data/events.js', 'js/engine.js'];
const code = files.map(f => fs.readFileSync(path.join(root, f), 'utf8')).join('\n') + '\n;({ Engine, COUNTRIES })';
const { Engine } = vm.runInContext(code, vm.createContext({ console, Math, JSON }));
const ids = process.argv[2] ? [process.argv[2]] : ['US', 'CN', 'RU', 'DE', 'IN', 'TR', 'BR'];
const runs = +(process.argv[3] || 5);
for (const id of ids) {
  const res = {}; let annexTotal = 0, puppetsTotal = 0, wars = 0;
  for (let r = 0; r < runs; r++) {
    const s = Engine.newGame(id, { autopilot: true });
    s.spending.military += 2; s.readinessTarget = 100; s.auto.militaer = true;
    while (s.month < 144 && !s.gameOver) {
      Engine.tick(s);
      // Ziel suchen: schwächstes erreichbares Nicht-Bündnisland ohne Atomwaffen
      if (!s.wars.length) {
        const targets = Object.keys(s.relations).filter(t => !s.alliance[t] && !s.puppets[t] && !Engine.hasNukes(s, t))
          .map(t => ({ t, odds: Engine.warOdds(s, t) })).filter(x => x.odds > 0.6).sort((a, b) => b.odds - a.odds);
        if (targets.length && s.month % 6 === 0) {
          const t = targets[0].t;
          Engine.dipAction(s, t, 'ultimatum');
          if (s.casusBelli[t] && !s.wars.length) { Engine.dipAction(s, t, 'krieg'); wars++; }
        }
      } else {
        for (const k of ['bodenoffensive', 'luftschlaege']) Engine.warAction(s, k);
      }
      while (s.pendingEvents.length) {
        const ev = s.pendingEvents[0];
        const idx = ev.id === '_sieg' ? 0 : Engine.recommend(s, ev).best;
        Engine.resolveEvent(s, idx);
      }
    }
    annexTotal += Object.keys(s.annexed).length; puppetsTotal += Object.keys(s.puppets).length;
    const k = s.gameOver ? s.gameOver.title : 'läuft';
    res[k] = (res[k] || 0) + 1;
    if (r === 0) console.log(`  ${id} Beispiel: annektiert ${Object.keys(s.annexed).join(',') || '–'} · BIP ${Math.round(s.econ.gdp)} (Start ${Engine.byId(id).gdp}) · Ansehen ${Math.round(s.stats.reputation)} · Zustimmung ${Math.round(s.approval)} · Stabilität ${Math.round(s.stats.stability)}`);
  }
  console.log(`${id}: Kriege ${wars}, Ø annektiert ${(annexTotal / runs).toFixed(1)}, Ausgang ${JSON.stringify(res)}`);
}
