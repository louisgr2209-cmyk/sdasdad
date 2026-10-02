// Headless-Balancetest: simuliert alle Länder ohne/mit Berater-Entscheidungen.
// Aufruf: node tools/sim-test.js [monate] [durchläufe] [strategie: none|advisor]
const fs = require('fs'), vm = require('vm'), path = require('path');
const root = path.join(__dirname, '..');
const files = ['js/data/worldmap.js', 'js/data/countries.js', 'js/data/policies.js', 'js/data/events.js', 'js/engine.js'];
const code = files.map(f => fs.readFileSync(path.join(root, f), 'utf8')).join('\n') + '\n;({ Engine, COUNTRIES, POLICIES, ACTIONS })';
const ctx = vm.createContext({ console, Math, JSON });
const { Engine, COUNTRIES } = vm.runInContext(code, ctx);

const months = +(process.argv[2] || 144), runs = +(process.argv[3] || 20), strat = process.argv[4] || 'advisor';
const rows = [];
let errors = 0;
for (const c of COUNTRIES) {
  const agg = { appr: 0, debt: 0, growth: 0, stab: 0, unemp: 0, infl: 0, over: {}, survived: 0, months: 0 };
  for (let r = 0; r < runs; r++) {
    const s = Engine.newGame(c.id, { difficulty: 'normal' });
    try {
      while (s.month < months && !s.gameOver) {
        Engine.tick(s);
        if (strat === 'smart') {
          const rec = Engine.recommendedPolicies(s, null, 1);
          if (rec.length && s.capital >= 35) Engine.enactPolicy(s, rec[0]);
          if (s.approval < 50) for (const a of ['rede', 'buergerdialog', 'pressekonferenz']) if (Engine.canDoAction(s, a).ok && s.capital > 25) Engine.doAction(s, a);
          if (s.groups.military < 30 && Engine.canEnact(s, 'veteranen').ok) Engine.enactPolicy(s, 'veteranen');
          if (s.budget.balance < s.country.deficit - 1.5) {
            const t = { ...s.taxes, vat: Math.min(30, s.taxes.vat + 1) };
            if (Engine.budgetChangeCost(s, t, s.spending) <= s.capital) Engine.applyBudget(s, t, s.spending);
          }
          while (s.pendingEvents.length) Engine.resolveEvent(s, Engine.recommend(s, s.pendingEvents[0]).best);
        }
        while (s.pendingEvents.length) {
          const ev = s.pendingEvents[0];
          const idx = strat !== 'random' ? Engine.recommend(s, ev).best : Math.floor(Math.random() * ev.choices.length);
          Engine.resolveEvent(s, idx);
        }
      }
    } catch (e) { errors++; console.error(c.id, e.stack); break; }
    agg.appr += s.approval; agg.debt += s.econ.debt; agg.growth += s.econ.growth; agg.stab += s.stats.stability;
    agg.unemp += s.econ.unemployment; agg.infl += s.econ.inflation; agg.months += s.month;
    const k = s.gameOver ? s.gameOver.title : 'läuft';
    agg.over[k] = (agg.over[k] || 0) + 1;
  }
  const f = v => (v / runs).toFixed(1);
  rows.push(`${c.id}  Zust ${f(agg.appr).padStart(5)}  Stab ${f(agg.stab).padStart(5)}  Wachs ${f(agg.growth).padStart(5)}  AL ${f(agg.unemp).padStart(5)}  Infl ${f(agg.infl).padStart(5)}  Schuld ${f(agg.debt).padStart(6)} (start ${c.debt})  Ø Monate ${f(agg.months)}  ${JSON.stringify(agg.over)}`);
}
console.log(rows.join('\n'));
if (errors) { console.error('FEHLER:', errors); process.exit(1); }
