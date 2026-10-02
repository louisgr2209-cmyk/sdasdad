// ════════════════════════════════════════════════════════════════════
//  Simulations-Engine des Präsidentensimulators
//  Ein Spielzug = ein Monat. Alle Werte werden relativ zum Startzustand
//  des Landes berechnet – wer nichts ändert, hält den Status quo.
// ════════════════════════════════════════════════════════════════════

const STAT_INFO = {
  approval:     { name: 'Zustimmung', icon: '👍', unit: '%', desc: 'Wie viele Bürger mit dir zufrieden sind. Entscheidet über Wahlen. Ergibt sich aus der Zufriedenheit aller Gruppen.' },
  stability:    { name: 'Stabilität', icon: '🏛️', desc: 'Innere Ruhe des Landes. Unter 10 droht eine Revolution.' },
  education:    { name: 'Bildung', icon: '🎓', desc: 'Qualität von Schulen und Universitäten. Steigt mit Bildungsausgaben, fördert langfristig das Wachstum.' },
  health:       { name: 'Gesundheit', icon: '🏥', desc: 'Qualität des Gesundheitssystems. Wichtig für Rentner.' },
  security:     { name: 'Sicherheit', icon: '🚓', desc: 'Schutz vor Kriminalität und Terror. Steigt mit Polizeiausgaben.' },
  environment:  { name: 'Umwelt', icon: '🌳', desc: 'Zustand von Natur und Klima. Wichtig für Umweltbewegung und Jugend.' },
  military:     { name: 'Militärstärke', icon: '🛡️', desc: 'Schlagkraft deiner Armee. Entscheidet über Kriege. Steigt mit Verteidigungsausgaben.' },
  corruption:   { name: 'Korruption', icon: '💰', desc: 'Je höher, desto mehr Steuergeld versickert. Niedrig ist gut!', invert: true },
  reputation:   { name: 'Ansehen', icon: '🌍', desc: 'Dein internationales Ansehen. Beeinflusst Beziehungen zu anderen Ländern.' },
  welfare:      { name: 'Soziales Netz', icon: '🤝', desc: 'Absicherung bei Armut, Krankheit und Alter. Steigt mit Sozialausgaben.' },
  growth:       { name: 'Wachstum', icon: '📈', unit: '%', desc: 'Reales Wirtschaftswachstum pro Jahr.' },
  unemployment: { name: 'Arbeitslosigkeit', icon: '👷', unit: '%', desc: 'Anteil der Arbeitslosen. Niedrig ist gut!', invert: true },
  inflation:    { name: 'Inflation', icon: '🏷️', unit: '%', desc: 'Preissteigerung pro Jahr. Ideal sind ca. 2 %.', invert: true },
  capacity:     { name: 'Staatskapazität', icon: '🏗️', desc: 'Wie gut dein Staat Reformen umsetzen kann (Verwaltung, Rechtsstaat, Infrastruktur). Begrenzt, wie weit sich Bildung, Gesundheit usw. entwickeln können. Wächst nur sehr langsam.' },
  terror:       { name: 'Terrorgefahr', icon: '💣', desc: 'Wahrscheinlichkeit von Anschlägen und Geiselnahmen. Sinkt durch Polizei, Sicherheit und Einsätze der Spezialkräfte.', invert: true },
  debt:         { name: 'Staatsschulden', icon: '🧾', unit: '% BIP', desc: 'Gesamtschulden im Verhältnis zur Wirtschaftsleistung. Hohe Schulden bedeuten hohe Zinsen.', invert: true },
};

const TAX_INFO = {
  income:    { name: 'Einkommensteuer', icon: '👛', min: 0, max: 60, factor: 0.32, hint: 'Belastet Arbeiter & Jugend, bremst Wachstum leicht.' },
  corporate: { name: 'Unternehmenssteuer', icon: '🏢', min: 0, max: 50, factor: 0.10, hint: 'Unternehmer hassen sie, bremst Investitionen stark.' },
  vat:       { name: 'Mehrwertsteuer', icon: '🛒', min: 0, max: 30, factor: 0.38, hint: 'Bringt viel Geld, erhöht aber Preise. Trifft Arbeiter & Rentner.' },
};

const SPEND_INFO = {
  military:       { name: 'Verteidigung', icon: '🛡️', max: 10, hint: 'Militärstärke ↑, Militär 😊' },
  education:      { name: 'Bildung', icon: '🎓', max: 10, hint: 'Bildung ↑, Jugend 😊, langfristig Wachstum ↑' },
  health:         { name: 'Gesundheit', icon: '🏥', max: 15, hint: 'Gesundheit ↑, Rentner 😊' },
  social:         { name: 'Soziales & Renten', icon: '🤝', max: 25, hint: 'Soziales Netz ↑, Arbeiter & Rentner 😊' },
  infrastructure: { name: 'Infrastruktur', icon: '🛣️', max: 10, hint: 'Wachstum ↑ (stärkster Wachstumshebel)' },
  police:         { name: 'Polizei & Justiz', icon: '🚓', max: 5, hint: 'Sicherheit ↑, Korruption ↓, Konservative 😊' },
  environment:    { name: 'Umweltschutz', icon: '🌳', max: 5, hint: 'Umwelt ↑, Umweltbewegung 😊' },
};

const DIFFICULTY = {
  leicht:  { name: 'Leicht',  capital: 1.3, eventChance: 0.38, approval: 4, interest: -0.3 },
  normal:  { name: 'Normal',  capital: 1.0, eventChance: 0.48, approval: 0, interest: 0 },
  schwer:  { name: 'Schwer',  capital: 0.8, eventChance: 0.58, approval: -4, interest: 0.4 },
};

const MONTHS = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
const TERM_MONTHS = 48;
const ADMIN_COST = 4; // feste Verwaltungskosten in % BIP

const Engine = (() => {
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const rand = (a, b) => a + Math.random() * (b - a);
  const gauss = () => (Math.random() + Math.random() + Math.random() - 1.5) / 1.5;
  const pick = arr => arr[Math.floor(Math.random() * arr.length)];
  const byId = id => COUNTRIES.find(c => c.id === id);
  const policyById = id => POLICIES.find(p => p.id === id);
  const actionById = id => ACTIONS.find(a => a.id === id);

  // ─────────────────────────── Spielstart ───────────────────────────
  function newGame(countryId, opts = {}) {
    const c = byId(countryId);
    const s = {
      version: 1,
      countryId,
      country: c,
      leader: { name: opts.name || 'Alex Muster', title: opts.title || 'Präsident' },
      difficulty: opts.difficulty || 'normal',
      mode: opts.mode || 'klassisch',
      month: 0,
      startYear: 2027,
      econ: { gdp: c.gdp, growth: c.growth, unemployment: c.unemployment, inflation: c.inflation, debt: c.debt },
      stats: { ...c.stats },
      taxes: { ...c.taxes },
      spending: { ...c.spending },
      groups: {}, groupMood: {}, groupStart: {},
      approval: c.approval,
      approvalMood: 0,
      honeymoon: 8,
      capital: 40,
      policies: {},
      cooldowns: {},
      mods: [],
      relations: {}, baseRelations: {}, trade: {}, alliance: {}, sanctions: {},
      wars: [],
      oil: 1, global: 0,
      nextElection: TERM_MONTHS, campaign: 0, terms: 1,
      history: { month: [], approval: [], stability: [], growth: [], unemployment: [], inflation: [], debt: [], balance: [], gdp: [], military: [] },
      news: [],
      eventHistory: {},
      pendingEvents: [],
      lowStab: 0, lowAppr: 0,
      gameOver: null,
      stats0: { ...c.stats },
      flags: {},
      lastReport: null,
    };
    const offsets = { business: 4, military: 4, greens: -4, conservatives: 0, workers: -1, retirees: 1, youth: -2 };
    for (const g in GROUPS) {
      s.groups[g] = clamp(c.approval + (offsets[g] || 0) + rand(-4, 4), 5, 95);
      s.groupStart[g] = s.groups[g];
      s.groupMood[g] = 0;
    }
    initDiplomacy(s);
    s.capacity = c.capacity;
    s.readiness = 25; s.readinessTarget = 25;
    s.sf = { quality: c.sf.quality, missions: 0, success: 0 };
    s.terror = clamp(75 - c.stats.security * 0.7, 5, 90);
    s.nukes = c.nukes; s.nukeProgram = null; s.nukeUsed = false;
    s.sfTarget = null;
    s.pacts = {}; s.blocs = [...c.blocs]; s.ownBloc = null;
    s.worldNukes = {};
    for (const o of COUNTRIES) if (o.id !== c.id && o.nukes > 0) s.worldNukes[o.id] = o.nukes;
    s.disarm = { active: false, signed: {}, dismantling: false, done: false };
    if (c.crisis) for (const k of ['growth', 'stability', 'security']) if (c.crisis[k]) s.mods.push({ key: k, value: c.crisis[k], months: c.crisis.months, label: c.crisis.label });
    // Haushalt kalibrieren: sonstige Einnahmen so wählen, dass das reale Defizit herauskommt
    s.taxEff = 1; s.otherRevenue = 0;
    const b0 = computeBudget(s);
    const needed = b0.expenses + c.deficit;
    const diff = needed - b0.taxRevenue;
    if (diff >= 1) { s.otherRevenue = diff; } else { s.otherRevenue = 1; s.taxEff = (needed - 1) / b0.taxRevenue; }
    s.budget = computeBudget(s);
    s.start = { trade: countTrue(s.trade), sanctions: countTrue(s.sanctions), alliance: countTrue(s.alliance), balance: s.budget.balance, interestShare: s.budget.interestShare, blocs: [...s.blocs] };
    recordHistory(s);
    addNews(s, `${s.leader.title} ${s.leader.name} tritt das Amt an – das Land blickt gespannt auf die ersten Entscheidungen.`, 'info');
    return s;
  }

  function countTrue(o) { return Object.values(o).filter(Boolean).length; }

  function initDiplomacy(s) {
    const me = s.country;
    for (const o of COUNTRIES) {
      if (o.id === me.id) continue;
      let r = 10;
      if (o.region === me.region) r += 15;
      const shared = o.blocs.filter(b => me.blocs.includes(b));
      if (shared.includes('EU')) r = Math.max(r, 65);
      if (shared.includes('NATO')) r = Math.max(r, 55);
      if (shared.includes('BRICS')) r = Math.max(r, 35);
      if (shared.includes('NA') || shared.includes('PAZ')) r = Math.max(r, 45);
      const ov = (RELATION_OVERRIDES[me.id] || {})[o.id] ?? (RELATION_OVERRIDES[o.id] || {})[me.id];
      if (ov !== undefined) r = ov;
      r = clamp(Math.round(r + rand(-5, 5)), -100, 100);
      s.relations[o.id] = r;
      s.baseRelations[o.id] = r;
      s.trade[o.id] = shared.some(b => ['EU', 'NA', 'PAZ'].includes(b)) ||
        START_TRADE.some(([a, b]) => (a === me.id && b === o.id) || (b === me.id && a === o.id));
      s.alliance[o.id] = shared.includes('NATO');
      s.sanctions[o.id] = START_SANCTIONS.some(([a, b]) => (a === me.id && b === o.id) || (b === me.id && a === o.id));
      if (s.sanctions[o.id]) s.trade[o.id] = false;
    }
  }

  // ─────────────────────────── Modifikatoren ───────────────────────────
  function computeMods(s) {
    const M = { groups: {} };
    const add = (k, v) => { M[k] = (M[k] || 0) + v; };
    // Schwache Staaten setzen Gesetze nur teilweise um
    const pe = 0.45 + (s.capacity ?? 70) / 100 * 0.7;
    for (const id in s.policies) {
      const p = policyById(id);
      if (!p) continue;
      for (const k in p.effects) add(k, p.effects[k] * (['interest', 'capitalGain', 'capacity', 'terror', 'sf'].includes(k) ? 1 : pe));
      for (const g in p.groups) M.groups[g] = (M.groups[g] || 0) + p.groups[g];
    }
    for (const m of s.mods) add(m.key, m.value);
    // Verträge
    for (const id in (s.pacts || {})) {
      const pc = s.pacts[id];
      if (pc.forschung) { add('growth', 0.05); add('education', 1); }
      if (pc.energie) { add('growth', 0.03); add('inflation', -0.05); }
      if (pc.ruestung) add('reputation', 1);
    }
    // Bündnisse (relativ zum Start, damit der Status quo stabil bleibt)
    if (s.blocs && s.start) {
      const bonus = list => { const b = {}; for (const k of list) for (const [mk, mv] of Object.entries((BLOCS[k] || {}).mods || {})) b[mk] = (b[mk] || 0) + mv; return b; };
      const now = bonus(s.blocs), then = bonus(s.start.blocs || []);
      for (const k of new Set([...Object.keys(now), ...Object.keys(then)])) add(k, (now[k] || 0) - (then[k] || 0));
    }
    if (s.ownBloc) { add('security', Math.min(6, s.ownBloc.members.length)); add('reputation', Math.min(5, s.ownBloc.members.length)); }
    if (s.disarm && s.disarm.done) add('reputation', 10);
    if (s.wars.length) { add('growth', -0.8 * s.wars.length); add('security', -3); add('reputation', -5); }
    // Abnehmender Grenznutzen: viele positive Maßnahmen stapeln sich nicht unbegrenzt
    const soft = (x, k) => x > 0 ? k * (1 - Math.exp(-x / k)) : x;
    if (M.growth) M.growth = soft(M.growth, 1.4);
    if (M.unemployment) M.unemployment = -soft(-M.unemployment, 1.4);
    for (const k of ['education', 'health', 'security', 'environment', 'welfare', 'stability', 'approval']) if (M[k]) M[k] = soft(M[k], 18);
    for (const g in M.groups) M.groups[g] = soft(M.groups[g], 22);
    return M;
  }

  function interestRate(s, M = computeMods(s)) {
    const c = s.country;
    let r = c.ir + (M.interest || 0) + DIFFICULTY[s.difficulty].interest;
    r += Math.max(0, s.econ.debt - c.debt - 15) * 0.05;
    r += Math.max(0, s.econ.inflation - Math.max(c.inflation, c.inflBase) - 2) * 0.25;
    r += Math.max(0, 40 - s.stats.stability) * 0.05;
    return Math.max(0.2, r);
  }

  // ─────────────────────────── Haushalt ───────────────────────────
  function computeBudget(s, taxes = s.taxes, spending = s.spending) {
    const c = s.country;
    const corrFactor = 1 - (s.stats.corruption - c.stats.corruption) * 0.004;
    const taxItems = {};
    let taxRevenue = 0;
    for (const k in TAX_INFO) {
      // leicht abnehmende Effizienz bei sehr hohen Sätzen (Laffer-Effekt)
      const rate = taxes[k];
      const eff = rate > TAX_INFO[k].max * 0.7 ? 1 - (rate - TAX_INFO[k].max * 0.7) / (TAX_INFO[k].max * 1.2) : 1;
      taxItems[k] = rate * TAX_INFO[k].factor * eff * (s.taxEff ?? 1) * corrFactor;
      taxRevenue += taxItems[k];
    }
    const oilRevenue = c.oil * (s.oil - 1);
    const revenue = taxRevenue + (s.otherRevenue || 0) + oilRevenue;
    let policyCost = 0;
    for (const id in s.policies) { const p = policyById(id); if (p) policyCost += p.upkeep; }
    const warCost = s.wars.length * 1.5 + Math.max(0, (s.readiness ?? 25) - 25) * 0.035;
    const rate = interestRate(s);
    const interest = s.econ.debt * rate / 100;
    let spendSum = 0;
    for (const k in SPEND_INFO) spendSum += spending[k];
    const expenses = spendSum + ADMIN_COST + policyCost + warCost + interest;
    const balance = revenue - expenses;
    return { taxItems, taxRevenue, oilRevenue, otherRevenue: s.otherRevenue || 0, revenue, spendSum, admin: ADMIN_COST, policyCost, warCost, interest, rate,
      expenses, balance, interestShare: interest / Math.max(1, revenue) };
  }

  function budgetChangeCost(s, taxes, spending) {
    let d = 0;
    for (const k in taxes) d += Math.abs(taxes[k] - s.taxes[k]) * 0.8;
    for (const k in spending) d += Math.abs(spending[k] - s.spending[k]) * 2;
    if (d < 0.05) return 0;
    return Math.max(3, Math.round(d));
  }

  function applyBudget(s, taxes, spending) {
    const cost = budgetChangeCost(s, taxes, spending);
    if (cost > s.capital) return { ok: false, msg: 'Nicht genug politisches Kapital.' };
    s.capital -= cost;
    s.taxes = { ...taxes };
    s.spending = { ...spending };
    s.budget = computeBudget(s);
    addNews(s, `Parlament verabschiedet neuen Haushalt (Saldo: ${fmtSigned(s.budget.balance, 1)} % des BIP).`, 'info');
    return { ok: true, cost };
  }

  // ─────────────────────────── Monatssimulation ───────────────────────────
  function tick(s) {
    if (s.gameOver) return;
    const c = s.country;
    const prev = snapshot(s);
    s.month++;

    // Weltlage: Ölpreis & Weltkonjunktur als Zufallsbewegung
    s.oil = clamp(s.oil + (1 - s.oil) * 0.04 + gauss() * 0.04, 0.4, 2.6);
    s.global = clamp(s.global * 0.95 + gauss() * 0.12, -1.5, 1.2);

    const M = computeMods(s);
    const e = s.econ, st = s.stats, t0 = c.taxes, sp0 = c.spending;
    const b = computeBudget(s);

    // ── Wachstum ──
    let gT = c.potential + s.global + (M.growth || 0);
    gT -= (s.taxes.income - t0.income) * 0.035 + (s.taxes.corporate - t0.corporate) * 0.05 + (s.taxes.vat - t0.vat) * 0.04;
    gT += (s.spending.infrastructure - sp0.infrastructure) * 0.3 + (st.education - c.stats.education) * 0.03;
    gT += (s.start.balance - b.balance) * 0.08; // Konjunkturimpuls durch Defizit
    gT += (st.stability - c.stats.stability) * 0.02;
    gT -= Math.max(0, e.inflation - Math.max(c.inflBase, c.inflation) - 3) * 0.12;
    gT -= (st.corruption - c.stats.corruption) * 0.02;
    gT += c.oil > 2 ? (s.oil - 1) * c.oil * 0.08 : -(s.oil - 1) * 0.8;
    gT += (countTrue(s.trade) - s.start.trade) * 0.12;
    gT -= (countTrue(s.sanctions) - s.start.sanctions) * 0.25;
    e.growth = clamp(e.growth + (gT - e.growth) * 0.12 + gauss() * 0.08, -15, 15);

    // ── Arbeitslosigkeit ──
    const uT = c.unemployment - (e.growth - c.potential) * 0.5 + (M.unemployment || 0);
    e.unemployment = clamp(e.unemployment + (uT - e.unemployment) * 0.07 + gauss() * 0.04, 0.5, 50);

    // ── Inflation ──
    let iT = c.inflBase + (M.inflation || 0) + Math.max(0, -b.balance - 3) * 0.25 + (e.growth - c.potential) * 0.3;
    iT += (s.taxes.vat - t0.vat) * 0.05 + (s.oil - 1) * 1.5;
    e.inflation = clamp(e.inflation + (iT - e.inflation) * 0.1 + gauss() * 0.1, -5, 300);

    // ── Schulden & BIP ──
    // Inflation entwertet Schulden nur bis zur Höhe des Zinssatzes (sonst würden Hochinflationsländer schuldenfrei)
    e.debt = Math.max(0, e.debt * (1 - (e.growth + Math.min(e.inflation, b.rate, 4)) / 1200) - b.balance / 12);
    e.gdp = e.gdp * (1 + e.growth / 1200);

    // ── Qualitätswerte (langsame Annäherung an Zielwerte) ──
    const s0 = c.stats;
    const targets = {
      education: s0.education + (s.spending.education - sp0.education) * 7 + (M.education || 0),
      health: s0.health + (s.spending.health - sp0.health) * 4 + (M.health || 0),
      security: s0.security + (s.spending.police - sp0.police) * 12 + (M.security || 0) + (st.stability - s0.stability) * 0.15,
      environment: s0.environment + (s.spending.environment - sp0.environment) * 12 + (M.environment || 0) - (e.growth - c.potential) * 0.5,
      military: s0.military + (s.spending.military - sp0.military) * 7 + (M.military || 0),
      corruption: s0.corruption + (M.corruption || 0) - (s.spending.police - sp0.police) * 2,
      reputation: s0.reputation + (M.reputation || 0) + (countTrue(s.alliance) - s.start.alliance) * 1.5,
      welfare: s0.welfare + (s.spending.social - sp0.social) * 2.5 + (M.welfare || 0) - (e.unemployment - c.unemployment) * 0.8,
    };
    // Staatskapazität begrenzt, wie gut und wie schnell sich ein Land entwickeln kann
    const capMax = 38 + s.capacity * 0.62, rate = 0.05 * (0.35 + s.capacity / 100 * 0.9);
    for (const k in targets) {
      let tg = clamp(targets[k], 0, 100);
      if (k === 'corruption') tg = Math.max(tg, Math.min(s0[k], 100 - capMax));
      else if (k !== 'military' && k !== 'reputation') tg = Math.min(tg, Math.max(capMax, s0[k]));
      st[k] = clamp(st[k] + (tg - st[k]) * rate, 0, 100);
    }
    const capT = c.capacity + (st.education - s0.education) * 0.25 - (st.corruption - s0.corruption) * 0.35 + (st.stability - s0.stability) * 0.2 + (M.capacity || 0) - s.wars.length * 5;
    s.capacity = clamp(s.capacity + (clamp(capT, 2, 98) - s.capacity) * 0.015, 2, 98);

    // ── Bevölkerungsgruppen ──
    const d = k => st[k] - s0[k];
    const dTax = k => s.taxes[k] - t0[k];
    const dInfl = e.inflation - c.inflation;
    const gT2 = {
      workers: -(e.unemployment - c.unemployment) * 2.5 - dTax('income') * 0.7 - dTax('vat') * 0.6 + d('welfare') * 0.4 - dInfl * 1.2,
      business: -dTax('corporate') * 1.2 - dTax('income') * 0.3 + (e.growth - c.potential) * 4 + d('stability') * 0.3 - d('corruption') * 0.2,
      retirees: d('health') * 0.5 + d('welfare') * 0.4 - dInfl * 1.5 + d('security') * 0.3 - dTax('vat') * 0.4,
      youth: d('education') * 0.5 + d('environment') * 0.3 - (e.unemployment - c.unemployment) * 2 - dTax('income') * 0.3,
      military: (s.spending.military - sp0.military) * 10 + d('military') * 0.3,
      greens: d('environment') * 0.9 + (s.spending.environment - sp0.environment) * 10,
      conservatives: d('security') * 0.5 - Math.max(0, e.debt - c.debt) * 0.12 + d('stability') * 0.3 - dTax('income') * 0.3 - dTax('vat') * 0.2,
    };
    for (const g in GROUPS) {
      const target = clamp(s.groupStart[g] + gT2[g] + (M.groups[g] || 0) + s.groupMood[g], 0, 100);
      s.groups[g] = clamp(s.groups[g] + (target - s.groups[g]) * 0.15, 0, 100);
      s.groupMood[g] *= 0.95;
    }

    // ── Zustimmung ──
    let apT = 0;
    for (const g in GROUPS) apT += s.groups[g] * GROUPS[g].weight;
    apT += s.approvalMood + s.honeymoon + (M.approval || 0) + DIFFICULTY[s.difficulty].approval;
    apT -= (s.terms - 1) * 3; // Amtsmüdigkeit: Wähler wollen irgendwann Veränderung
    s.approval = clamp(s.approval + (apT - s.approval) * 0.35, 0, 100);
    s.approvalMood *= 0.92;
    s.honeymoon *= 0.9;

    // ── Stabilität ──
    const stT = s0.stability + (s.approval - c.approval) * 0.4 + d('security') * 0.3 - (e.unemployment - c.unemployment) * 1.0
      - Math.max(0, e.inflation - Math.max(c.inflation, c.inflBase) - 5) * 0.5 - s.wars.length * 5 - d('corruption') * 0.3 + (M.stability || 0);
    st.stability = clamp(st.stability + (clamp(stT, 0, 100) - st.stability) * 0.08, 0, 100);

    // ── Politisches Kapital ──
    // Jedes aktive Gesetz bindet Regierungsarbeit und senkt den Kapitalzuwachs
    const gain = Math.max(0.5, (2 + s.approval / 25 + (M.capitalGain || 0) - Object.keys(s.policies).length * 0.12) * DIFFICULTY[s.difficulty].capital);
    s.capital = clamp(s.capital + gain, 0, 100);

    // ── Mobilisierung ──
    s.readiness = clamp(s.readiness + clamp(s.readinessTarget - s.readiness, -6, 4), 0, 100);
    if (s.readiness > 55 && !s.wars.length) { s.groupMood.youth -= (s.readiness - 55) * 0.012; s.groupMood.workers -= (s.readiness - 55) * 0.006; }

    // ── Terrorgefahr & Spezialkräfte ──
    const tT = 70 - st.security * 0.65 + s.wars.length * 12 + (st.stability < 40 ? 10 : 0) + (M.terror || 0);
    s.terror = clamp(s.terror + (tT - s.terror) * 0.05 + gauss() * 1.5, 0, 100);
    const sfMax = Math.max(c.sf.quality, 40 + s.capacity * 0.6);
    const sfT = clamp(c.sf.quality + (s.spending.military - sp0.military) * 3 + (M.sf || 0), 5, sfMax);
    s.sf.quality = clamp(s.sf.quality + (sfT - s.sf.quality) * 0.03, 0, 100);

    // ── Atomprogramm ──
    if (s.nukeProgram && s.month >= s.nukeProgram) {
      s.nukes = 20; s.nukeProgram = null;
      s.stats.reputation = clamp(s.stats.reputation - 10, 0, 100);
      addNews(s, '☢️ Erster erfolgreicher Atomtest – wir sind jetzt eine Atommacht.', 'bad');
      s.pendingEvents.push(infoEvent('☢️', 'Wir sind Atommacht', 'Das Atomprogramm ist abgeschlossen. Der erste Test war erfolgreich. Die Welt reagiert mit Empörung – aber kaum ein Land wird es noch wagen, uns anzugreifen.'));
    }

    // ── Diplomatie & Krieg ──
    tickDiplomacy(s);
    tickWars(s);

    // ── Modifikatoren altern ──
    for (const m of s.mods) m.months--;
    s.mods = s.mods.filter(m => m.months > 0);
    s.campaign *= 0.98;

    s.budget = computeBudget(s);
    recordHistory(s);
    s.lastReport = makeReport(prev, snapshot(s));

    // ── Wahlen, Krisen, Ereignisse ──
    checkSchedule(s);
    checkCrises(s);
    if (!s.gameOver && !s.pendingEvents.length) rollRandomEvent(s);
    headline(s, prev);
  }

  function snapshot(s) {
    return { approval: s.approval, stability: s.stats.stability, growth: s.econ.growth, unemployment: s.econ.unemployment,
      inflation: s.econ.inflation, debt: s.econ.debt, balance: s.budget ? s.budget.balance : 0, capital: s.capital, gdp: s.econ.gdp };
  }
  function makeReport(a, b) { const r = {}; for (const k in a) r[k] = b[k] - a[k]; return r; }

  function recordHistory(s) {
    const h = s.history;
    h.month.push(s.month);
    h.approval.push(+s.approval.toFixed(1));
    h.stability.push(+s.stats.stability.toFixed(1));
    h.growth.push(+s.econ.growth.toFixed(2));
    h.unemployment.push(+s.econ.unemployment.toFixed(2));
    h.inflation.push(+s.econ.inflation.toFixed(2));
    h.debt.push(+s.econ.debt.toFixed(1));
    h.balance.push(+(s.budget ? s.budget.balance : 0).toFixed(2));
    h.gdp.push(Math.round(s.econ.gdp));
    h.military.push(+s.stats.military.toFixed(1));
  }

  // ─────────────────────────── Diplomatie ───────────────────────────
  function tickDiplomacy(s) {
    tickDisarm(s);
    for (const id in s.pacts) if (s.pacts[id].nichtangriff) s.relations[id] = clamp(s.relations[id] + 0.15, -100, 100);
    const repShift = (s.stats.reputation - s.country.stats.reputation) * 0.2;
    for (const id in s.relations) {
      if (atWarWith(s, id)) { s.relations[id] = -100; continue; }
      let r = s.relations[id];
      const base = clamp(s.baseRelations[id] + repShift, -100, 100);
      r += (base - r) * 0.02 + (s.trade[id] ? 0.2 : 0) + (s.alliance[id] ? 0.3 : 0) - (s.sanctions[id] ? 0.3 : 0) + gauss() * 0.8;
      s.relations[id] = clamp(r, -100, 100);
      const o = byId(id);
      if (s.trade[id] && r < -10 && Math.random() < 0.08) {
        s.trade[id] = false;
        addNews(s, `${o.flag} ${o.name} kündigt das Handelsabkommen auf!`, 'bad');
      }
      if (s.alliance[id] && r < 20 && Math.random() < 0.08) {
        s.alliance[id] = false;
        addNews(s, `${o.flag} ${o.name} verlässt das Militärbündnis mit uns.`, 'bad');
      }
    }
  }

  function atWarWith(s, id) { return s.wars.some(w => w.enemy === id); }

  // Kriegsbereitschaft: 25 = Frieden, 100 = Generalmobilmachung. Wirkt als Multiplikator auf die Kampfkraft.
  const readinessFactor = r => 0.5 + r / 100;
  function militaryPower(s, withAllies = true) {
    let p = s.stats.military * s.country.milSize * readinessFactor(s.readiness ?? 25);
    if (withAllies) for (const id in s.alliance) if (s.alliance[id] && !atWarWith(s, id)) { const o = byId(id); p += o.stats.military * o.milSize * 0.15 * Math.max(0, s.relations[id]) / 100; }
    return Math.max(1, p);
  }
  // Gegner mobilisieren im Krieg Monat für Monat nach
  function enemyPower(id, w) {
    const o = byId(id);
    const r = w ? Math.min(90, 45 + w.months * 6) : 45;
    return o.stats.military * o.milSize * readinessFactor(r) * (1 - (w && w.attrition || 0));
  }
  function warOdds(s, id) { const my = militaryPower(s), en = enemyPower(id, s.wars.find(x => x.enemy === id)); return my / (my + en); }

  function startWar(s, id, forced) {
    if (atWarWith(s, id)) return 'Wir befinden uns bereits im Krieg mit diesem Land.';
    if (!forced && s.wars.length) return 'Wir führen bereits einen Krieg – ein zweiter wäre Wahnsinn.';
    const o = byId(id);
    s.wars.push({ enemy: id, progress: 0, months: 0, forced: !!forced, attrition: 0 });
    s.relations[id] = -100;
    s.trade[id] = false; s.alliance[id] = false;
    if (forced) {
      s.approvalMood += 10;
      s.groupMood.military += 8; s.groupMood.conservatives += 5;
      addNews(s, `KRIEG! ${o.flag} ${o.name} hat uns angegriffen. Die Nation steht zusammen.`, 'bad');
    } else {
      s.approvalMood += 4; s.stats.reputation = clamp(s.stats.reputation - 15, 0, 100);
      s.groupMood.military += 10; s.groupMood.conservatives += 4; s.groupMood.youth -= 12; s.groupMood.greens -= 12;
      addNews(s, `KRIEG! Wir haben ${o.flag} ${o.name} den Krieg erklärt. Die Welt ist schockiert.`, 'bad');
    }
    // Verbündete des Gegners reagieren
    for (const cid in s.relations) if (cid !== id && byId(cid).blocs.some(b => b !== 'EU' && o.blocs.includes(b))) s.relations[cid] = clamp(s.relations[cid] - 25, -100, 100);
    return null;
  }

  function tickWars(s) {
    for (const w of [...s.wars]) {
      const o = byId(w.enemy);
      const my = militaryPower(s), en = enemyPower(w.enemy, w) * rand(0.9, 1.1);
      let delta = (my / (my + en) - 0.5) * 30 + rand(-6, 6) + (w.boost || 0);
      w.boost = (w.boost || 0) * 0.5;
      if (hasNukes(s, w.enemy) && delta > 0 && w.progress > 40) delta *= 0.3;
      if (s.nukes > 0 && delta < 0 && w.progress < -40) delta *= 0.3;
      w.progress = clamp(w.progress + delta, -100, 100);
      w.months++;
      s.stats.military = clamp(s.stats.military - 0.4, 0, 100);
      if (w.months > 6) s.approvalMood -= 0.6;
      // Eine in die Enge getriebene Atommacht kann eskalieren
      if (hasNukes(s, w.enemy) && w.progress > 75 && !w.nukeWarned) {
        w.nukeWarned = true;
        s.pendingEvents.push(infoEvent('☢️', 'Nukleare Drohung', `${o.name} ist militärisch am Ende und droht offen mit dem Einsatz von Atomwaffen. Deine Berater raten dringend, Frieden anzubieten, statt weiter vorzurücken.`));
      }
      // In die Enge getrieben, kann eine Atommacht eine Atomwaffe einsetzen – das Spiel geht aber weiter
      const pNuke = (s.nukes > 0 ? 0.04 : 0.1) * (s.pacts[w.enemy]?.ruestung ? 0.5 : 1);
      if (hasNukes(s, w.enemy) && w.progress > 85 && (w.enemyNukeCd || 0) <= w.months && Math.random() < pNuke) {
        w.enemyNukeCd = w.months + 6;
        w.progress -= 25;
        nuclearDamage(s, w.enemy);
        s.pendingEvents.push(nuclearCrisisEvent(s, w, 'enemy'));
        continue;
      }
      if (w.progress >= 100) endWar(s, w, 'sieg');
      else if (w.progress <= -100) endWar(s, w, 'niederlage');
      else if (w.progress > 45 && Math.random() < 0.18 && !s.pendingEvents.length) s.pendingEvents.push(peaceOfferEvent(s, w, true));
      else if (w.progress < -45 && Math.random() < 0.15 && !s.pendingEvents.length) s.pendingEvents.push(peaceOfferEvent(s, w, false));
    }
  }

  function endWar(s, w, result) {
    const o = byId(w.enemy);
    s.wars = s.wars.filter(x => x !== w);
    s.baseRelations[w.enemy] = Math.min(s.baseRelations[w.enemy], -40);
    if (result === 'sieg') {
      s.econ.debt = Math.max(0, s.econ.debt - 3);
      s.groupMood.military += 20; s.groupMood.conservatives += 8; s.approvalMood += 10;
      s.stats.reputation = clamp(s.stats.reputation - 5, 0, 100);
      s.relations[w.enemy] = -60;
      s.mods.push({ key: 'growth', value: 0.5, months: 12, label: 'Reparationen' });
      addNews(s, `SIEG! ${o.flag} ${o.name} kapituliert und zahlt Reparationen.`, 'good');
      s.pendingEvents.push(infoEvent('🏆', 'Sieg!', `Nach ${w.months} Monaten Krieg kapituliert ${o.name}. Reparationszahlungen füllen die Staatskasse, das Militär feiert dich als Helden.`));
    } else if (result === 'niederlage') {
      s.econ.debt += 4;
      s.approvalMood -= 20; s.stats.stability = clamp(s.stats.stability - 25, 0, 100);
      s.groupMood.military -= 20; s.groupMood.conservatives -= 10;
      s.stats.military = clamp(s.stats.military - 10, 0, 100);
      s.relations[w.enemy] = -40;
      addNews(s, `NIEDERLAGE! Wir müssen vor ${o.flag} ${o.name} kapitulieren.`, 'bad');
      s.pendingEvents.push(infoEvent('🏳️', 'Kapitulation', `Der Krieg gegen ${o.name} ist verloren. Wir müssen Reparationen zahlen, das Land ist erschüttert und das Militär gedemütigt.`));
    } else {
      s.relations[w.enemy] = -50;
      addNews(s, `Frieden mit ${o.flag} ${o.name} geschlossen.`, 'info');
    }
  }

  function peaceOfferEvent(s, w, weWin) {
    const o = byId(w.enemy);
    if (weWin) return {
      id: '_frieden', icon: '🕊️', cat: 'militaer', land: w.enemy, title: `${o.name} bittet um Frieden`,
      text: `${o.name} ist militärisch in Bedrängnis und bietet Frieden sowie Reparationszahlungen an. Deine Generäle wollen weiterkämpfen.`,
      choices: [
        { label: 'Frieden annehmen', effects: { peace: true, money: -1.5, stats: { approval: 5 }, groups: { military: 4 } } },
        { label: 'Weiterkämpfen bis zum Sieg', effects: { groups: { military: 5, youth: -4 } } },
      ] };
    return {
      id: '_kapitulationsforderung', icon: '⚠️', cat: 'militaer', land: w.enemy, title: `${o.name} stellt Bedingungen`,
      text: `Unsere Truppen sind auf dem Rückzug. ${o.name} bietet Waffenstillstand an – gegen hohe Zahlungen.`,
      choices: [
        { label: 'Waffenstillstand akzeptieren', effects: { peace: true, money: 1.5, stats: { approval: -6, stability: -4 }, groups: { military: -8 } } },
        { label: 'Weiterkämpfen!', effects: { groups: { military: 3 }, stats: { stability: -2 } } },
      ] };
  }

  function infoEvent(icon, title, text, extra = {}) {
    return { id: '_info', icon, cat: 'info', title, text, choices: [{ label: 'Verstanden', effects: {} }], ...extra };
  }

  // ─────────────────────────── Wahlen & Krisen ───────────────────────────
  function checkSchedule(s) {
    const demo = s.country.gov === 'demokratie';
    const finalTerm = s.mode === 'klassisch' && s.terms >= 3;
    if (demo && !finalTerm && s.month === s.nextElection - 3) s.pendingEvents.push(campaignEvent(s));
    if (s.month !== s.nextElection) return;

    if (finalTerm) {
      s.gameOver = { won: true, icon: '🏅', title: 'Amtszeit erfolgreich beendet!',
        text: `Nach ${s.terms * 4} Jahren übergibst du das Amt geordnet an deine Nachfolge. Die Geschichtsbücher werden über dich schreiben.` };
      return;
    }
    if (demo) {
      const vote = clamp(s.approval * 0.85 + 9 + s.campaign + rand(-3, 3), 3, 97);
      const opp = clamp((100 - vote) * rand(0.7, 0.85), 1, 100);
      const others = Math.max(0, 100 - vote - opp);
      const won = vote >= 50;
      s.campaign = 0;
      s.pendingEvents.push({ id: '_wahl', type: 'election', icon: '🗳️', cat: 'politik', title: won ? 'Wahlsieg!' : 'Wahlniederlage',
        text: won ? `Die Bürger haben gesprochen: Du bleibst im Amt! Eine neue Amtszeit beginnt.` : `Die Opposition gewinnt die Wahl. Deine Amtszeit ist vorbei.`,
        result: { vote, opp, others, won }, choices: [{ label: won ? 'Auf in die nächste Amtszeit!' : 'Abschied nehmen', effects: {} }] });
      if (won) {
        s.terms++; s.nextElection += TERM_MONTHS; s.honeymoon = 6; s.capital = clamp(s.capital + 15, 0, 100);
        addNews(s, `Wahlsieg mit ${vote.toFixed(1)} %! ${s.leader.title} ${s.leader.name} regiert weiter.`, 'good');
      } else {
        s.gameOver = { won: false, icon: '🗳️', title: 'Abgewählt', text: `Mit nur ${vote.toFixed(1)} % der Stimmen hast du die Wahl verloren. Die Opposition übernimmt die Regierung.` };
      }
    } else {
      const ok = (s.stats.stability >= 30 && s.groups.military >= 30) || Math.random() < 0.3;
      if (ok) {
        s.terms++; s.nextElection += TERM_MONTHS; s.capital = clamp(s.capital + 15, 0, 100);
        s.pendingEvents.push(infoEvent('🏛️', 'Machtprobe bestanden', 'Der Parteikongress bestätigt dich einstimmig im Amt. Deine Macht ist für weitere vier Jahre gesichert.'));
        addNews(s, `Parteikongress bestätigt ${s.leader.name} im Amt.`, 'good');
      } else {
        s.gameOver = { won: false, icon: '🎭', title: 'Entmachtet', text: 'Bei der Machtprobe stellen sich Militär und Parteielite gegen dich. Du wirst in den Ruhestand gezwungen.' };
      }
    }
  }

  function campaignEvent(s) {
    return { id: '_wahlkampf', icon: '📣', cat: 'politik', title: 'Der Wahlkampf beginnt!',
      text: `In drei Monaten wird gewählt. Deine aktuelle Zustimmung liegt bei ${s.approval.toFixed(0)} %. Wie willst du in den Wahlkampf ziehen?`,
      choices: [
        { label: 'Positive Kampagne', desc: 'Erfolge betonen, Zukunft versprechen.', effects: { capital: -10, campaign: 3 } },
        { label: 'Teure Medienoffensive', desc: 'Werbung auf allen Kanälen.', effects: { money: 0.3, campaign: 4 } },
        { label: 'Negativkampagne gegen die Opposition', desc: 'Riskant, aber wirkungsvoll.', effects: { chance: { p: 0.65, success: { text: 'Die Angriffe sitzen!', campaign: 5 }, fail: { text: 'Die Schmutzkampagne geht nach hinten los.', campaign: -3, stats: { reputation: -2 } } } } },
        { label: 'Keine besondere Kampagne', effects: {} },
      ] };
  }

  function checkCrises(s) {
    if (s.gameOver) return;
    const st = s.stats, c = s.country;
    // Revolution
    if (st.stability < 10) s.lowStab++; else s.lowStab = 0;
    if (s.lowStab >= 3 && Math.random() < 0.4) {
      s.gameOver = { won: false, icon: '🔥', title: 'Revolution!', text: 'Das Volk stürmt den Regierungssitz. Du musst ins Exil fliehen. Die Stabilität deines Landes war zu lange am Boden.' };
      return;
    }
    // Putsch
    if (s.groups.military < 15 && st.stability < 45 && Math.random() < (c.gov === 'autoritaer' ? 0.2 : 0.12)) {
      s.gameOver = { won: false, icon: '🪖', title: 'Militärputsch!', text: 'Panzer rollen durch die Hauptstadt. Die Generäle haben die Macht übernommen – das Militär war zu unzufrieden.' };
      return;
    }
    // Staatsbankrott
    const limit = Math.max(250, c.debt + 120);
    const shareLimit = Math.max(0.45, s.start.interestShare + 0.25);
    if (s.budget.interestShare > shareLimit || s.econ.debt > limit) {
      s.gameOver = { won: false, icon: '💸', title: 'Staatsbankrott', text: 'Niemand leiht deinem Land mehr Geld. Der Staat ist zahlungsunfähig, der Währungsfonds übernimmt die Kontrolle.' };
      return;
    }
    if ((s.budget.interestShare > shareLimit - 0.12 || s.econ.debt > limit - 30) && !s.flags.bankruptWarn) {
      s.flags.bankruptWarn = true;
      s.pendingEvents.push(infoEvent('⚠️', 'Warnung: Pleite droht!', 'Deine Finanzministerin schlägt Alarm: Die Zinslast wird erdrückend. Wenn du nicht sofort sparst oder Steuern erhöhst, droht der Staatsbankrott!'));
    }
    if (s.budget.interestShare < shareLimit - 0.18 && s.econ.debt < limit - 45) s.flags.bankruptWarn = false;
    // Misstrauensvotum
    if (c.gov === 'demokratie') {
      if (s.approval < 18) s.lowAppr++; else s.lowAppr = 0;
      if (s.lowAppr === 3) s.pendingEvents.push(infoEvent('📉', 'Misstrauensvotum droht', 'Deine Zustimmung ist katastrophal. Das Parlament droht mit einem Misstrauensvotum, wenn sich nichts ändert!'));
      if (s.lowAppr >= 6) {
        s.gameOver = { won: false, icon: '🏛️', title: 'Misstrauensvotum', text: 'Das Parlament hat dir das Vertrauen entzogen. Eine neue Regierung übernimmt.' };
      }
    }
  }

  // ─────────────────────────── Ereignisse ───────────────────────────
  function resolveCtx(s, ctx) {
    const others = Object.keys(s.relations).filter(id => !atWarWith(s, id));
    if (!others.length) return null;
    switch (ctx) {
      case 'rival': { const sorted = others.sort((a, b) => s.relations[a] - s.relations[b]); return pick(sorted.slice(0, 3)); }
      case 'ally': { const l = others.filter(id => s.alliance[id]); return l.length ? pick(l) : null; }
      case 'partner': { const l = others.filter(id => s.trade[id]); return l.length ? pick(l) : null; }
      case 'unsafe': { const l = others.filter(id => !s.alliance[id] && byId(id).stats.security < 60); return l.length ? pick(l) : null; }
      case 'nottrade': { const l = others.filter(id => !s.trade[id] && !s.sanctions[id] && s.relations[id] > 0); return l.length ? pick(l) : null; }
      default: return pick(others);
    }
  }

  function fill(str, s, land) {
    const o = land ? byId(land) : null;
    return str.replace(/\{sf\}/g, s.country.sf.name).replace(/\{land\}/g, o ? o.name : 'ein Nachbarland').replace(/\{capital\}/g, s.country.capital).replace(/\{country\}/g, s.country.name);
  }

  function instantiate(s, def, land) {
    const ev = { id: def.id, icon: def.icon, cat: def.cat, land, title: fill(def.title, s, land), text: fill(def.text, s, land),
      choices: def.choices.map(ch => ({ label: fill(ch.label, s, land), desc: ch.desc ? fill(ch.desc, s, land) : '', effects: JSON.parse(JSON.stringify(ch.effects)) })) };
    // Texte in Zufallsergebnissen ersetzen
    for (const ch of ev.choices) if (ch.effects.chance) {
      for (const k of ['success', 'fail']) if (ch.effects.chance[k].text) ch.effects.chance[k].text = fill(ch.effects.chance[k].text, s, land);
    }
    return ev;
  }

  function rollRandomEvent(s, force = false) {
    if (!force && Math.random() > DIFFICULTY[s.difficulty].eventChance) return null;
    const others = Object.keys(s.relations);
    s._rivalRel = Math.min(...others.map(id => s.relations[id]));
    const pool = [];
    for (const def of EVENTS) {
      const last = s.eventHistory[def.id];
      if (last !== undefined && (def.once || s.month - last < (def.cooldown || 30))) continue;
      if (def.cond && !def.cond(s)) continue;
      const w = typeof def.weight === 'function' ? def.weight(s) : (def.weight ?? 1);
      if (w > 0) pool.push({ def, w });
    }
    let total = pool.reduce((a, p) => a + p.w, 0);
    while (pool.length) {
      let r = Math.random() * total, chosen = pool[0];
      for (const p of pool) { r -= p.w; if (r <= 0) { chosen = p; break; } }
      let land = null;
      if (chosen.def.ctx) land = resolveCtx(s, chosen.def.ctx);
      if ((chosen.def.ctx && !land) || (land && chosen.def.skip && chosen.def.skip(s, land))) { pool.splice(pool.indexOf(chosen), 1); total -= chosen.w; continue; }
      s.eventHistory[chosen.def.id] = s.month;
      const ev = instantiate(s, chosen.def, land);
      s.pendingEvents.push(ev);
      return ev;
    }
    return null;
  }

  // Wirkung eines Ereignisses / einer Maßnahme anwenden. Gibt Meldungen zurück.
  function applyEffects(s, eff, land) {
    const msgs = [];
    if (!eff) return msgs;
    if (eff.stats) for (const k in eff.stats) {
      if (k === 'approval') s.approvalMood += eff.stats[k];
      else s.stats[k] = clamp(s.stats[k] + eff.stats[k], 0, 100);
    }
    if (eff.econ) for (const k in eff.econ) s.econ[k] = Math.max(k === 'growth' || k === 'inflation' ? -20 : 0, s.econ[k] + eff.econ[k]);
    if (eff.groups) for (const g in eff.groups) s.groupMood[g] += eff.groups[g];
    if (eff.money) s.econ.debt = Math.max(0, s.econ.debt + eff.money);
    if (eff.capital) s.capital = clamp(s.capital + eff.capital, 0, 100);
    if (eff.mods) for (const m of eff.mods) s.mods.push({ ...m });
    if (eff.oil) s.oil = clamp(s.oil + eff.oil, 0.4, 2.6);
    if (eff.campaign) s.campaign += eff.campaign;
    if (eff.terror) s.terror = clamp(s.terror + eff.terror, 0, 100);
    if (eff.ostracize) ostracize(s);
    if (land && eff.pact) s.pacts[land] = { ...(s.pacts[land] || {}), [eff.pact]: true };
    if (land && eff.warEnd) { const w = s.wars.find(x => x.enemy === land); if (w) endWar(s, w, eff.warEnd); }
    if (eff.nukeDamage) nuclearDamage(s, land);
    if (eff.doom) s.gameOver = { won: false, icon: '☢️', title: 'Atomkrieg', text: 'Die nukleare Eskalation war nicht mehr aufzuhalten. Es gibt keine Gewinner – nur Verlierer. Deine Regierung existiert nicht mehr.' };
    if (eff.sfQuality) s.sf.quality = clamp(s.sf.quality + eff.sfQuality, 0, 100);
    if (land && eff.relation) s.relations[land] = clamp(s.relations[land] + eff.relation, -100, 100);
    if (land && eff.trade) { s.trade[land] = true; s.sanctions[land] = false; msgs.push(`Handelsabkommen mit ${byId(land).name} geschlossen.`); }
    if (land && eff.war) { const err = startWar(s, land, eff.forced); if (err) msgs.push(err); }
    if (land && eff.peace) { const w = s.wars.find(x => x.enemy === land); if (w) endWar(s, w, 'frieden'); }
    if (eff.chance) {
      const ok = Math.random() < chanceP(s, eff.chance);
      const sub = ok ? eff.chance.success : eff.chance.fail;
      if (sub.text) msgs.push((ok ? '✅ ' : '❌ ') + sub.text);
      msgs.push(...applyEffects(s, sub, land));
    }
    s.budget = computeBudget(s);
    return msgs;
  }

  function resolveEvent(s, choiceIndex) {
    const ev = s.pendingEvents.shift();
    if (!ev) return [];
    const ch = ev.choices[choiceIndex] || ev.choices[0];
    const msgs = applyEffects(s, ch.effects, ev.land);
    if (ev.cat !== 'info' && ev.type !== 'election') addNews(s, `${ev.title}: ${ch.label}`, 'event');
    return msgs;
  }

  // Bewertung einer Wirkung für die Berater-Empfehlung
  function scoreEffects(s, eff) {
    if (!eff) return 0;
    let sc = 0;
    const moneyW = 5 + Math.max(0, s.econ.debt - 60) / 15 + (s.budget.balance < -5 ? 4 : 0) + s.budget.interestShare * 20;
    const W = { approval: 1.2, stability: 0.8, education: 0.35, health: 0.35, security: 0.35, environment: 0.3, military: 0.3, corruption: -0.4, reputation: 0.3, welfare: 0.35 };
    if (eff.stats) for (const k in eff.stats) sc += eff.stats[k] * (W[k] ?? 0.3) * (k === 'stability' && s.stats.stability < 40 ? 2 : 1);
    if (eff.econ) sc += (eff.econ.growth || 0) * 6 - (eff.econ.unemployment || 0) * 5 - (eff.econ.inflation || 0) * 2.5;
    if (eff.groups) for (const g in eff.groups) {
      const urgency = s.groups[g] < 30 ? 1.8 : 1;
      sc += eff.groups[g] * GROUPS[g].weight * 0.9 * urgency * (g === 'military' && s.groups.military < 30 ? 6 : 1);
    }
    if (eff.money) sc -= eff.money * moneyW;
    if (eff.capital) sc += eff.capital * 0.25;
    const MW = { growth: 7, unemployment: -5, inflation: -2.5, interest: -3, approval: 1, stability: 0.6 };
    if (eff.mods) for (const m of eff.mods) sc += m.value * (MW[m.key] ?? 0.3) * Math.min(m.months, 24) / 12;
    if (eff.relation) sc += eff.relation * 0.08;
    if (eff.trade) sc += 4;
    if (eff.campaign) sc += eff.campaign * 1.5;
    if (eff.war) sc -= eff.forced ? 2 : 25;
    if (eff.peace) sc += 3;
    if (eff.oil) sc += s.country.oil > 2 ? eff.oil * s.country.oil * 0.5 : -eff.oil * 3;
    if (eff.chance) { const p = chanceP(s, eff.chance); sc += p * scoreEffects(s, eff.chance.success) + (1 - p) * scoreEffects(s, eff.chance.fail); }
    if (eff.terror) sc -= eff.terror * 0.15;
    if (eff.warEnd) sc += { sieg: 20, frieden: 8, niederlage: -15 }[eff.warEnd];
    if (eff.nukeDamage) sc -= 40;
    if (eff.doom) sc -= 1000;
    if (eff.ostracize) sc -= 80;
    return sc;
  }

  // Bewertung eines Gesetzes für die Berater-Empfehlung
  function scorePolicy(s, p) {
    let sc = 0;
    for (const g in p.groups) sc += p.groups[g] * GROUPS[g].weight * 0.9 * (s.groups[g] < 30 ? 1.8 : 1) * (g === 'military' && s.groups.military < 30 ? 5 : 1);
    const W = { growth: 12, unemployment: -8, inflation: -3, education: 0.25, health: 0.25, security: 0.25, environment: 0.2, welfare: 0.25,
      military: 0.12, corruption: -0.3, reputation: 0.12, stability: 0.6 * (s.stats.stability < 40 ? 2 : 1), approval: 1, capitalGain: 4,
      interest: -s.econ.debt / 40 };
    for (const k in p.effects) sc += p.effects[k] * (W[k] ?? 0);
    const moneyW = 3 + s.econ.debt / 40 + (s.budget.balance < -4 ? 3 : 0) + (s.budget.balance > 0 ? -1.5 : 0);
    sc -= p.upkeep * moneyW;
    return sc - p.cost * 0.05;
  }
  function recommendedPolicies(s, area, n = 2) {
    return POLICIES.filter(p => (!area || p.area === area) && !(p.id in s.policies) && canEnact(s, p.id).why !== 'Bereits aktiv' && !(p.excludes || []).some(x => x in s.policies) && !(p.nonNuclearOnly && (s.nukes > 0 || s.nukeProgram)))
      .map(p => ({ p, sc: scorePolicy(s, p) })).filter(x => x.sc > 2).sort((a, b) => b.sc - a.sc).slice(0, n).map(x => x.p.id);
  }

  function recommend(s, ev) {
    const scores = ev.choices.map(ch => scoreEffects(s, ch.effects));
    let best = 0;
    scores.forEach((v, i) => { if (v > scores[best]) best = i; });
    return { scores, best };
  }

  // ─────────────────────────── Gesetze & Maßnahmen ───────────────────────────
  function canEnact(s, id) {
    const p = policyById(id);
    if (id in s.policies) return { ok: false, why: 'Bereits aktiv' };
    if (p.nonNuclearOnly && (s.nukes > 0 || s.nukeProgram)) return { ok: false, why: 'Dein Land besitzt bereits Atomwaffen' };
    if (p.nonNuclearOnly && s.disarm && (s.disarm.signed[s.countryId] || s.disarm.done || s.disarm.dismantling)) return { ok: false, why: 'Verstößt gegen den Abrüstungsvertrag' };
    const blocked = (p.excludes || []).find(x => x in s.policies);
    if (blocked) return { ok: false, why: `Unvereinbar mit „${policyById(blocked).name}“` };
    if (s.capital < p.cost) return { ok: false, why: `Benötigt ${p.cost} ⚡ politisches Kapital` };
    return { ok: true };
  }
  function enactPolicy(s, id) {
    const chk = canEnact(s, id);
    if (!chk.ok) return chk;
    const p = policyById(id);
    s.capital -= p.cost;
    s.policies[id] = s.month;
    if (id === 'atomwaffen') { s.nukeProgram = s.month + 30; addNews(s, 'Geheimdienste melden: Wir arbeiten an eigenen Atomwaffen.', 'bad'); }
    s.budget = computeBudget(s);
    addNews(s, `Neues Gesetz beschlossen: ${p.name}.`, 'good');
    return { ok: true };
  }
  function repealCost(p) { return Math.round(p.cost / 2); }
  function repealPolicy(s, id) {
    const p = policyById(id);
    if (!(id in s.policies)) return { ok: false, why: 'Nicht aktiv' };
    if (s.capital < repealCost(p)) return { ok: false, why: `Benötigt ${repealCost(p)} ⚡` };
    s.capital -= repealCost(p);
    delete s.policies[id];
    if (id === 'atomwaffen') s.nukeProgram = null;
    s.budget = computeBudget(s);
    addNews(s, `Gesetz aufgehoben: ${p.name}.`, 'info');
    return { ok: true };
  }

  function canDoAction(s, id) {
    const a = actionById(id);
    if (a.condition && !a.condition(s)) return { ok: false, why: 'Voraussetzung nicht erfüllt' };
    const cd = (s.cooldowns[id] || 0) - s.month;
    if (cd > 0) return { ok: false, why: `Wieder verfügbar in ${cd} Monat${cd > 1 ? 'en' : ''}` };
    if (s.capital < a.cost) return { ok: false, why: `Benötigt ${a.cost} ⚡` };
    return { ok: true };
  }
  function doAction(s, id) {
    const chk = canDoAction(s, id);
    if (!chk.ok) return chk;
    const a = actionById(id);
    s.capital -= a.cost;
    s.cooldowns[id] = s.month + a.cooldown;
    const msgs = applyEffects(s, a.effects, null);
    addNews(s, `Maßnahme: ${a.name}.`, 'info');
    return { ok: true, msgs };
  }

  // ─────────────────────────── Diplomatische Aktionen ───────────────────────────
  const DIP_ACTIONS = {
    besuch:      { name: 'Staatsbesuch', icon: '✈️', cost: 8, cd: 6, desc: 'Beziehung +10' },
    hilfe:       { name: 'Hilfspaket senden', icon: '📦', cost: 3, money: 0.05, cd: 6, desc: 'Beziehung +15, Ansehen +2' },
    handel:      { name: 'Handelsabkommen', icon: '📜', cost: 15, desc: 'Wachstum +0,12 %. Benötigt Beziehung ≥ 25' },
    handel_end:  { name: 'Handelsabkommen kündigen', icon: '✂️', cost: 0, desc: 'Beziehung −15' },
    buendnis:    { name: 'Militärbündnis', icon: '🤝', cost: 20, desc: 'Hilft im Krieg, Ansehen +. Benötigt Beziehung ≥ 60' },
    buendnis_end:{ name: 'Bündnis aufkündigen', icon: '💔', cost: 0, desc: 'Beziehung −25' },
    sanktion:    { name: 'Sanktionen verhängen', icon: '🚫', cost: 10, desc: 'Beziehung −30, eigenes Wachstum −0,25 %' },
    sanktion_end:{ name: 'Sanktionen aufheben', icon: '🔓', cost: 5, desc: 'Beziehung +10, Wachstum +0,25 %' },
    krieg:       { name: 'Krieg erklären', icon: '⚔️', cost: 30, desc: 'Nur bei Beziehung ≤ −40. Enorm riskant!' },
    frieden:     { name: 'Frieden anbieten', icon: '🕊️', cost: 10, cd: 3, desc: 'Erfolg hängt vom Kriegsverlauf ab' },
  };

  function dipOptions(s, id) {
    const r = s.relations[id], war = atWarWith(s, id);
    const list = [];
    const cdLeft = key => Math.max(0, (s.cooldowns['dip:' + id + ':' + key] || 0) - s.month);
    const opt = (key, ok, why) => {
      const a = DIP_ACTIONS[key];
      let reason = why;
      if (ok && s.capital < a.cost) { ok = false; reason = `Benötigt ${a.cost} ⚡`; }
      if (ok && cdLeft(key)) { ok = false; reason = `Wieder in ${cdLeft(key)} Mon.`; }
      list.push({ key, ...a, ok, why: reason });
    };
    if (war) { opt('frieden', true); return list; }
    opt('besuch', true);
    opt('hilfe', true);
    if (s.sanctions[id]) opt('sanktion_end', true); else opt('sanktion', !s.alliance[id], 'Nicht gegen Verbündete');
    opt('krieg', r <= -40 && !s.alliance[id] && s.wars.length === 0, s.wars.length ? 'Bereits im Krieg' : 'Beziehung nicht feindlich genug');
    return list;
  }

  function dipAction(s, id, key) {
    const opt = dipOptions(s, id).find(o => o.key === key);
    if (!opt || !opt.ok) return { ok: false, why: opt ? opt.why : 'Nicht möglich' };
    const o = byId(id);
    s.capital -= opt.cost;
    if (opt.cd) s.cooldowns['dip:' + id + ':' + key] = s.month + opt.cd;
    const rel = v => { s.relations[id] = clamp(s.relations[id] + v, -100, 100); };
    let msg = '';
    switch (key) {
      case 'besuch': rel(8 + Math.round(rand(0, 5))); s.baseRelations[id] = clamp(s.baseRelations[id] + 3, -100, 100); msg = `Erfolgreicher Staatsbesuch in ${o.name}.`; break;
      case 'hilfe': rel(15); s.econ.debt += opt.money; s.stats.reputation = clamp(s.stats.reputation + 2, 0, 100); s.baseRelations[id] = clamp(s.baseRelations[id] + 3, -100, 100); msg = `Hilfspaket an ${o.name} geliefert.`; break;
      case 'handel': s.trade[id] = true; rel(5); s.groupMood.business += 3; msg = `Handelsabkommen mit ${o.name} unterzeichnet!`; break;
      case 'handel_end': s.trade[id] = false; rel(-15); msg = `Handelsabkommen mit ${o.name} gekündigt.`; break;
      case 'buendnis': s.alliance[id] = true; rel(5); s.groupMood.military += 3; msg = `Militärbündnis mit ${o.name} geschlossen!`; break;
      case 'buendnis_end': s.alliance[id] = false; rel(-25); s.baseRelations[id] -= 10; msg = `Bündnis mit ${o.name} aufgekündigt.`; break;
      case 'sanktion': s.sanctions[id] = true; s.trade[id] = false; rel(-30); s.baseRelations[id] -= 15;
        s.stats.reputation = clamp(s.stats.reputation + (o.stats.reputation < 40 ? 2 : -2), 0, 100); s.groupMood.conservatives += 2; msg = `Sanktionen gegen ${o.name} verhängt.`; break;
      case 'sanktion_end': s.sanctions[id] = false; rel(10); s.baseRelations[id] += 10; msg = `Sanktionen gegen ${o.name} aufgehoben.`; break;
      case 'krieg':
        if (s.pacts[id]?.nichtangriff) { delete s.pacts[id].nichtangriff; s.stats.reputation = clamp(s.stats.reputation - 10, 0, 100); addNews(s, `Wir brechen den Nichtangriffspakt mit ${o.name}!`, 'bad'); }
        startWar(s, id, false); msg = `Krieg gegen ${o.name} erklärt!`; break;
      case 'frieden': {
        const w = s.wars.find(x => x.enemy === id);
        const p = clamp(0.25 + w.progress / 150 + w.months * 0.01, 0.05, 0.95);
        if (Math.random() < p) { endWar(s, w, 'frieden'); s.approvalMood += 3; msg = `${o.name} akzeptiert den Frieden!`; }
        else msg = `${o.name} lehnt das Friedensangebot ab.`;
        break;
      }
    }
    s.budget = computeBudget(s);
    addNews(s, msg, key === 'krieg' || key.endsWith('_end') || key === 'sanktion' ? 'bad' : 'good');
    return { ok: true, msg };
  }

  // Kriegsmaßnahmen
  // ─────────────────────────── Kriegsführung ───────────────────────────
  const WAR_ACTIONS = {
    bodenoffensive: { name: 'Bodenoffensive', icon: '🪖', cost: 8, money: 0.3, cd: 2, desc: 'Großangriff der Landstreitkräfte. Wirkung hängt stark vom Kräfteverhältnis ab. Verluste: Militärstärke −2, Zustimmung −1' },
    luftschlaege:   { name: 'Luftschläge', icon: '✈️', cost: 6, money: 0.25, cd: 2, desc: 'Kampfjets und Drohnen greifen militärische Ziele an. Ansehen −2' },
    seeblockade:    { name: 'Seeblockade', icon: '⚓', cost: 8, money: 0.2, cd: 4, minSize: 1.5, desc: 'Die Marine schneidet den Nachschub ab: Feind dauerhaft −6 % Kampfkraft. Braucht eine große Flotte' },
    hilfe_bitte:    { name: 'Verbündete um Hilfe bitten', icon: '📞', cost: 10, cd: 6, desc: 'Nur mit Verbündeten. Front +10' },
  };
  function warAction(s, key) {
    const a = WAR_ACTIONS[key], w = s.wars[0];
    if (!w) return { ok: false, why: 'Kein Krieg' };
    if ((s.cooldowns['war:' + key] || 0) > s.month) return { ok: false, why: 'Noch nicht wieder verfügbar' };
    if (s.capital < a.cost) return { ok: false, why: `Benötigt ${a.cost} ⚡` };
    if (a.minSize && s.country.milSize < a.minSize) return { ok: false, why: 'Unsere Marine ist dafür zu klein' };
    const allies = Object.keys(s.alliance).filter(id => s.alliance[id]);
    if (key === 'hilfe_bitte' && !allies.length) return { ok: false, why: 'Keine Verbündeten' };
    s.capital -= a.cost; s.cooldowns['war:' + key] = s.month + a.cd;
    if (a.money) s.econ.debt += a.money;
    const odds = warOdds(s, w.enemy);
    const eff = Math.pow(odds * 2, 1.6); // Unterlegene Armeen erreichen mit Offensiven kaum etwas
    let msg = `${a.name} angeordnet.`;
    if (key === 'bodenoffensive') {
      s.stats.military = clamp(s.stats.military - 2, 0, 100); s.approvalMood -= 1;
      if (Math.random() < 0.15 + odds) { w.boost = (w.boost || 0) + 14 * eff; msg = 'Die Offensive kommt voran – die Front verschiebt sich zu unseren Gunsten.'; }
      else { w.boost = (w.boost || 0) - 6; s.stats.military = clamp(s.stats.military - 2, 0, 100); msg = 'Die Offensive bleibt stecken. Schwere Verluste.'; }
    }
    if (key === 'luftschlaege') { w.boost = (w.boost || 0) + 9 * eff; s.stats.reputation = clamp(s.stats.reputation - 2, 0, 100); msg = 'Luftschläge gegen militärische Ziele durchgeführt.'; }
    if (key === 'seeblockade') { w.attrition = Math.min(0.5, (w.attrition || 0) + 0.06); msg = 'Die Seeblockade schwächt den Nachschub des Gegners.'; }
    if (key === 'hilfe_bitte') { w.boost = (w.boost || 0) + Math.min(15, (militaryPower(s) - militaryPower(s, false)) / enemyPower(w.enemy, w) * 25); for (const id of allies) s.relations[id] = clamp(s.relations[id] - 4, -100, 100); msg = 'Verbündete schicken Unterstützung.'; }
    s.budget = computeBudget(s);
    return { ok: true, msg };
  }

  // ─────────────────────────── Mobilisierung ───────────────────────────
  const READINESS_LEVELS = [
    { value: 25, name: 'Friedensbetrieb', desc: 'Normale Bereitschaft, keine Zusatzkosten' },
    { value: 50, name: 'Erhöhte Bereitschaft', desc: 'Reserven einberufen, Übungen' },
    { value: 75, name: 'Teilmobilisierung', desc: 'Truppen an die Grenzen, Rüstungsproduktion hoch' },
    { value: 100, name: 'Generalmobilmachung', desc: 'Das ganze Land im Kriegsmodus' },
  ];
  function setReadiness(s, value) {
    if (s.readinessTarget === value) return { ok: false, why: 'Bereits eingestellt' };
    const cost = value > s.readinessTarget ? 5 : 2;
    if (s.capital < cost) return { ok: false, why: `Benötigt ${cost} ⚡` };
    s.capital -= cost; s.readinessTarget = value;
    if (value >= 75) { s.groupMood.military += 4; addNews(s, `Regierung ordnet ${value === 100 ? 'Generalmobilmachung' : 'Teilmobilisierung'} an.`, 'bad'); }
    s.budget = computeBudget(s);
    return { ok: true, msg: `Neue Bereitschaftsstufe: ${READINESS_LEVELS.find(l => l.value === value).name}. Die Umstellung dauert einige Monate.` };
  }

  // ─────────────────────────── Spezialkräfte ───────────────────────────
  const SF_OPS = {
    terrorzelle:  { name: 'Terrorzelle ausheben', icon: '🎯', cost: 6, cd: 3, base: 0.35, desc: 'Zugriff auf eine bekannte Zelle im Inland. Erfolg: Terrorgefahr −20, Sicherheit +2' },
    festnahme:    { name: 'Zielperson im Ausland festnehmen', icon: '🕵️', cost: 12, cd: 6, base: 0.15, desc: 'Ein gesuchter Terroristenführer. Erfolg: Zustimmung +4, Terrorgefahr −15. Belastet die Beziehung zum Gastland' },
    sabotage:     { name: 'Sabotage hinter feindlichen Linien', icon: '💥', cost: 10, cd: 3, base: 0.2, war: true, desc: 'Nur im Krieg: Feind −5 % Kampfkraft, Front +5' },
    ausbildung:   { name: 'Intensivtraining', icon: '🏋️', cost: 5, money: 0.03, cd: 6, desc: 'Qualität +5 (begrenzt durch Staatskapazität)' },
  };
  function sfChance(s, base) { return clamp(base + s.sf.quality / 130 - (s.terror > 70 ? 0.05 : 0), 0.05, 0.95); }
  function chanceP(s, ch) { return ch.sf ? sfChance(s, ch.p) : ch.p; }
  function sfTarget(s) {
    if (s.sfTarget && s.relations[s.sfTarget] !== undefined && !s.alliance[s.sfTarget]) return s.sfTarget;
    const l = Object.keys(s.relations).filter(id => !s.alliance[id] && !atWarWith(s, id) && byId(id).stats.security < 60);
    s.sfTarget = l.length ? pick(l) : pick(Object.keys(s.relations));
    return s.sfTarget;
  }
  function sfOp(s, key) {
    const a = SF_OPS[key];
    const cd = (s.cooldowns['sf:' + key] || 0) - s.month;
    if (cd > 0) return { ok: false, why: `Wieder bereit in ${cd} Mon.` };
    if (s.capital < a.cost) return { ok: false, why: `Benötigt ${a.cost} ⚡` };
    if (a.war && !s.wars.length) return { ok: false, why: 'Nur im Krieg möglich' };
    s.capital -= a.cost; s.cooldowns['sf:' + key] = s.month + a.cd;
    if (a.money) s.econ.debt += a.money;
    const sfn = s.country.sf.name;
    if (key === 'ausbildung') {
      const max = Math.max(s.country.sf.quality, 40 + s.capacity * 0.6) + 5;
      s.sf.quality = Math.min(max, s.sf.quality + 5);
      return { ok: true, msg: `${sfn}: Intensivtraining abgeschlossen.` };
    }
    s.sf.missions++;
    const ok = Math.random() < sfChance(s, a.base);
    if (ok) s.sf.success++; else { s.sf.quality = clamp(s.sf.quality - 5, 0, 100); s.approvalMood -= 3; }
    let msg;
    if (key === 'terrorzelle') {
      if (ok) { s.terror = clamp(s.terror - 20, 0, 100); s.stats.security = clamp(s.stats.security + 2, 0, 100); s.approvalMood += 1; msg = `✅ ${sfn}: Zugriff erfolgreich, die Zelle ist zerschlagen.`; }
      else { s.terror = clamp(s.terror - 5, 0, 100); msg = `❌ ${sfn}: Der Zugriff scheitert, die Verdächtigen sind untergetaucht.`; }
    }
    if (key === 'festnahme') {
      const id = sfTarget(s), o = byId(id);
      if (ok) { s.terror = clamp(s.terror - 15, 0, 100); s.approvalMood += 4; s.relations[id] = clamp(s.relations[id] - 10, -100, 100); s.groupMood.military += 3; msg = `✅ ${sfn}: Zielperson in ${o.name} gefasst und ins Land gebracht!`; }
      else { s.relations[id] = clamp(s.relations[id] - 25, -100, 100); s.stats.reputation = clamp(s.stats.reputation - 4, 0, 100); msg = `❌ ${sfn}: Einsatz in ${o.name} aufgeflogen – diplomatischer Eklat.`; }
      s.sfTarget = null;
    }
    if (key === 'sabotage') {
      const w = s.wars[0];
      if (ok) { w.attrition = Math.min(0.5, (w.attrition || 0) + 0.04); w.boost = (w.boost || 0) + 3; msg = `✅ ${sfn}: Nachschublinien des Gegners sabotiert.`; }
      else msg = `❌ ${sfn}: Das Kommando wird entdeckt und muss sich zurückziehen.`;
    }
    addNews(s, msg.replace(/^[✅❌] /, ''), ok ? 'good' : 'bad');
    return { ok: true, msg };
  }

  // ─────────────────────────── Atomwaffen ───────────────────────────
  function nuclearThreat(s) {
    const w = s.wars[0];
    if (!w) return { ok: false, why: 'Kein Krieg' };
    if (!(s.nukes > 0)) return { ok: false, why: 'Wir besitzen keine Atomwaffen' };
    if ((s.cooldowns.nukeThreat || 0) > s.month) return { ok: false, why: 'Gerade erst gedroht' };
    if (s.capital < 20) return { ok: false, why: 'Benötigt 20 ⚡' };
    s.capital -= 20; s.cooldowns.nukeThreat = s.month + 12;
    const o = byId(w.enemy);
    s.stats.reputation = clamp(s.stats.reputation - 12, 0, 100);
    for (const id in s.relations) s.relations[id] = clamp(s.relations[id] - 8, -100, 100);
    const p = hasNukes(s, w.enemy) ? 0.12 : clamp(0.45 + w.progress / 200, 0.15, 0.85);
    if (Math.random() < p) { endWar(s, w, 'frieden'); s.econ.debt = Math.max(0, s.econ.debt - 1); return { ok: true, msg: `✅ ${o.name} lenkt ein und akzeptiert einen Waffenstillstand zu unseren Bedingungen.` }; }
    s.stats.stability = clamp(s.stats.stability - 5, 0, 100);
    return { ok: true, msg: `❌ ${o.name} lässt sich nicht einschüchtern. Die Welt ist alarmiert.` };
  }

  function hasNukes(s, id) { return (s.worldNukes?.[id] || 0) > 0; }

  // Weltweite Ächtung nach eigenem Atomwaffeneinsatz
  function ostracize(s) {
    s.stats.reputation = 0;
    for (const id in s.relations) {
      s.relations[id] = clamp(s.relations[id] - 60, -100, 100);
      s.baseRelations[id] = clamp(s.baseRelations[id] - 50, -100, 100);
      s.alliance[id] = false;
      if (s.relations[id] < 30) { s.sanctions[id] = true; s.trade[id] = false; }
    }
    s.blocs = s.blocs.filter(b => !BLOCS[b] || !BLOCS[b].alliance);
    if (s.ownBloc) s.ownBloc.members = [];
    s.approvalMood -= 30;
    s.stats.stability = clamp(s.stats.stability - 30, 0, 100);
    s.stats.environment = clamp(s.stats.environment - 20, 0, 100);
    s.groupMood.greens -= 40; s.groupMood.youth -= 30; s.groupMood.workers -= 10; s.groupMood.retirees -= 10;
    s.mods.push({ key: 'growth', value: -3, months: 36, label: 'Weltweite Ächtung' });
    if (s.disarm) { s.disarm.signed = {}; s.disarm.dismantling = false; }
  }

  // Schaden durch einen gegnerischen Atomwaffeneinsatz (abstrakt)
  function nuclearDamage(s, id) {
    s.econ.gdp *= 0.9;
    s.econ.debt += 6;
    s.stats.stability = clamp(s.stats.stability - 20, 0, 100);
    s.stats.health = clamp(s.stats.health - 10, 0, 100);
    s.stats.environment = clamp(s.stats.environment - 12, 0, 100);
    s.approvalMood -= 10;
    for (const g in s.groupMood) s.groupMood[g] -= 5;
    s.mods.push({ key: 'growth', value: -2, months: 24, label: 'Nuklearschaden' });
    addNews(s, `☢️ ${byId(id).name} setzt eine Atomwaffe gegen uns ein. Das Land steht unter Schock.`, 'bad');
    s.budget = computeBudget(s);
  }

  function nuclearCrisisEvent(s, w, origin) {
    const o = byId(w.enemy);
    const treatyBonus = s.pacts[w.enemy]?.ruestung ? 0.15 : 0;
    if (origin === 'own') return {
      id: '_nuklearkrise', icon: '☢️', cat: 'militaer', land: w.enemy, title: 'Nukleare Krise',
      text: `${o.name} hat seine Atomstreitkräfte in höchste Alarmbereitschaft versetzt und droht mit einem Gegenschlag. Die Welt hält den Atem an. Jetzt entscheidet sich, ob die Lage noch zu retten ist.`,
      choices: [
        { label: 'Heißer Draht: sofortige Deeskalation', desc: 'Direkter Kontakt zur Gegenseite, Angebot eines Waffenstillstands.', effects: { chance: { p: 0.55 + treatyBonus,
          success: { text: 'Die Deeskalation gelingt. Beide Seiten vereinbaren einen Waffenstillstand.', warEnd: 'frieden' },
          fail: { text: `${o.name} antwortet mit einem begrenzten Gegenschlag. Der Krieg geht weiter.`, nukeDamage: true } } } },
        { label: 'UN-Sicherheitsrat einschalten', desc: 'Internationale Vermittlung unter enormem Zeitdruck.', effects: { capital: -15, chance: { p: 0.5 + treatyBonus,
          success: { text: 'Die Vermittlung gelingt in letzter Minute. Waffenstillstand unter UN-Aufsicht.', warEnd: 'frieden', stats: { reputation: 5 } },
          fail: { text: 'Die Vermittlung scheitert – es kommt zu einem begrenzten Gegenschlag.', nukeDamage: true } } } },
        { label: 'Volle Abschreckung: mit Zweitschlag drohen', desc: 'Alles auf eine Karte. Extrem gefährlich.', effects: { chance: { p: 0.45,
          success: { text: `${o.name} weicht zurück und kapituliert.`, warEnd: 'sieg' },
          fail: { text: 'Die Eskalation ist nicht mehr aufzuhalten.', doom: true } } } },
        { label: 'Kapitulieren, um das Schlimmste zu verhindern', effects: { warEnd: 'niederlage' } },
      ] };
    const choices = [
      { label: 'Sofortiger Waffenstillstand', desc: 'Weitere Opfer verhindern – um jeden Preis.', effects: { warEnd: 'frieden', stats: { approval: -5 } } },
      { label: 'UN-Vermittlung anrufen', effects: { capital: -15, chance: { p: 0.6 + treatyBonus,
        success: { text: 'Unter internationalem Druck willigt der Gegner in einen Waffenstillstand ein.', warEnd: 'frieden', stats: { reputation: 5 } },
        fail: { text: 'Die Vermittlung scheitert. Der Krieg geht weiter.' } } } },
      { label: 'Weiterkämpfen', desc: 'Wir lassen uns nicht erpressen.', effects: { groups: { military: 5, youth: -8 } } },
    ];
    if (s.nukes > 0) choices.push({ label: 'Nukleare Vergeltung', desc: 'Antwort mit eigenen Atomwaffen. Höchstes Risiko einer totalen Eskalation.', effects: { ostracize: true, chance: { p: 0.45,
      success: { text: `${o.name} gibt auf, bevor es zu einer weiteren Eskalation kommt.`, warEnd: 'sieg' },
      fail: { text: 'Die Spirale der Vergeltung lässt sich nicht mehr stoppen.', doom: true } } } });
    return { id: '_atomangriff', icon: '☢️', cat: 'militaer', land: w.enemy, title: `${o.name} setzt eine Atomwaffe ein`,
      text: `In die Enge getrieben, hat ${o.name} eine Atomwaffe gegen militärische Ziele in unserem Land eingesetzt. Die Schäden sind schwer, Wirtschaft und Gesundheitssystem sind schwer getroffen. Die Welt fordert sofortige Deeskalation. Wie reagierst du?`,
      choices };
  }

  function nuclearStrike(s) {
    const w = s.wars[0];
    if (!w) return { ok: false, why: 'Kein Krieg' };
    if (!(s.nukes > 0)) return { ok: false, why: 'Wir besitzen keine Atomwaffen' };
    const o = byId(w.enemy);
    s.nukeUsed = true;
    s.nukes = Math.max(0, s.nukes - 1);
    ostracize(s);
    if (hasNukes(s, w.enemy)) {
      addNews(s, `☢️ Atomschlag gegen ${o.name}. ${o.name} droht mit Vergeltung – die Welt steht am Abgrund.`, 'bad');
      s.pendingEvents.push(nuclearCrisisEvent(s, w, 'own'));
      s.budget = computeBudget(s);
      return { ok: true, msg: 'Nukleare Krise!' };
    }
    s.wars = s.wars.filter(x => x !== w);
    s.relations[w.enemy] = -100; s.baseRelations[w.enemy] = -100;
    addNews(s, `☢️ Atomschlag gegen ${o.name}. Der Krieg ist vorbei – die Welt verhängt Sanktionen und bricht die Beziehungen ab.`, 'bad');
    s.pendingEvents.push(infoEvent('☢️', 'Die Welt steht unter Schock', `${o.name} hat kapituliert. Doch der Preis ist unermesslich: Unzählige Opfer, weltweite Ächtung, Sanktionen fast aller Staaten, und alle Bündnisse sind zerbrochen. Dein Name wird für immer mit dieser Entscheidung verbunden sein.`));
    s.budget = computeBudget(s);
    return { ok: true, msg: `Atomschlag gegen ${o.name}.` };
  }

  // ─────────────────────────── Verträge ───────────────────────────
  const TREATIES = {
    handel:       { name: 'Handelsabkommen', icon: '📜', cost: 10, diff: 15, desc: 'Wachstum +0,12 % · Unternehmer 😊' },
    buendnis:     { name: 'Militärbündnis', icon: '🛡️', cost: 15, diff: 55, desc: 'Gegenseitiger Beistand im Krieg · Militär 😊' },
    nichtangriff: { name: 'Nichtangriffspakt', icon: '🤞', cost: 8, diff: -10, desc: 'Dieses Land greift uns nicht an, Beziehung verbessert sich stetig' },
    forschung:    { name: 'Forschungsabkommen', icon: '🔬', cost: 8, diff: 20, desc: 'Wachstum +0,05 %, Bildung +1' },
    energie:      { name: 'Energiepartnerschaft', icon: '⚡', cost: 8, diff: 20, desc: 'Wachstum +0,03 %, Inflation −0,05' },
    ruestung:     { name: 'Rüstungskontrollvertrag', icon: '🕊️', cost: 12, diff: 25, desc: 'Halbiert das Risiko nuklearer Eskalation, erleichtert Abrüstung, Ansehen +1' },
    beitritt:     { name: 'Beitritt zu deinem Bündnis', icon: '🏳️', cost: 12, diff: 45, desc: 'Wird Mitglied deines Bündnisses (Beistand & Handel)' },
  };
  const MONEY_OFFERS = [0, 0.05, 0.15, 0.3];

  function hasTreaty(s, id, type) {
    if (type === 'handel') return !!s.trade[id];
    if (type === 'buendnis') return !!s.alliance[id];
    if (type === 'beitritt') return !!(s.ownBloc && s.ownBloc.members.includes(id));
    return !!(s.pacts[id] && s.pacts[id][type]);
  }
  function treatyBlocked(s, id, type) {
    if (atWarWith(s, id)) return 'Wir sind im Krieg';
    if (type === 'handel' && s.sanctions[id]) return 'Erst Sanktionen aufheben';
    if (type === 'ruestung' && !hasNukes(s, id) && !(s.nukes > 0)) return 'Nur sinnvoll, wenn eine Seite Atomwaffen hat';
    if (type === 'beitritt' && !s.ownBloc) return 'Gründe zuerst ein eigenes Bündnis';
    const cd = (s.cooldowns['neg:' + id + ':' + type] || 0) - s.month;
    if (cd > 0) return `Nach der Absage erst in ${cd} Mon. wieder`;
    return null;
  }
  function negotiationChance(s, id, type, offer = {}) {
    const t = TREATIES[type], o = byId(id);
    if (atWarWith(s, id)) return 0;
    let v = s.relations[id] - t.diff;
    v += [0, 10, 22, 35][offer.money || 0] * Math.sqrt(clamp(s.econ.gdp / o.gdp, 0.3, 4));
    if (offer.concession) v += 15;
    if (offer.tech) v += 12;
    v += (s.stats.reputation - 50) * 0.2;
    if (s.sanctions[id]) v -= 25;
    if (type === 'buendnis' || type === 'beitritt') {
      const westMe = s.blocs.includes('NATO'), westThem = o.blocs.includes('NATO');
      if (westMe !== westThem) v -= 20;
      if (o.gov !== s.country.gov) v -= 10;
    }
    return clamp(0.5 + v / 70, 0.03, 0.95);
  }
  function negotiate(s, id, type, offer = {}) {
    const t = TREATIES[type], o = byId(id);
    if (hasTreaty(s, id, type)) return { ok: false, why: 'Vertrag besteht bereits' };
    const blocked = treatyBlocked(s, id, type);
    if (blocked) return { ok: false, why: blocked };
    if (s.capital < t.cost) return { ok: false, why: `Benötigt ${t.cost} ⚡` };
    s.capital -= t.cost;
    const p = negotiationChance(s, id, type, offer);
    if (Math.random() >= p) {
      s.cooldowns['neg:' + id + ':' + type] = s.month + 4;
      s.relations[id] = clamp(s.relations[id] - 3, -100, 100);
      addNews(s, `${o.name} lehnt unser Angebot für ein${type === 'beitritt' ? 'en Bündnisbeitritt' : ' ' + t.name} ab.`, 'bad');
      return { ok: true, accepted: false, msg: `❌ ${o.name} lehnt ab.` };
    }
    // Angenommen: Gegenleistungen werden fällig
    s.econ.debt += MONEY_OFFERS[offer.money || 0];
    if (offer.concession) { s.groupMood.workers -= 3; s.groupMood.conservatives -= 3; }
    if (offer.tech) { s.groupMood.business -= 3; }
    if (type === 'handel') { s.trade[id] = true; s.groupMood.business += 3; }
    else if (type === 'buendnis') { s.alliance[id] = true; s.groupMood.military += 3; }
    else if (type === 'beitritt') { s.ownBloc.members.push(id); s.alliance[id] = true; if (!s.sanctions[id]) s.trade[id] = true; }
    else { s.pacts[id] = { ...(s.pacts[id] || {}), [type]: true }; }
    s.relations[id] = clamp(s.relations[id] + 5, -100, 100);
    s.baseRelations[id] = clamp(s.baseRelations[id] + 5, -100, 100);
    s.budget = computeBudget(s);
    const msg = type === 'beitritt' ? `${o.name} tritt dem ${s.ownBloc.name} bei!` : `${t.name} mit ${o.name} unterzeichnet!`;
    addNews(s, msg, 'good');
    return { ok: true, accepted: true, msg: '✅ ' + msg };
  }
  function cancelTreaty(s, id, type) {
    if (!hasTreaty(s, id, type)) return { ok: false, why: 'Kein solcher Vertrag' };
    const o = byId(id);
    if (type === 'handel') s.trade[id] = false;
    else if (type === 'buendnis') s.alliance[id] = false;
    else if (type === 'beitritt') { s.ownBloc.members = s.ownBloc.members.filter(x => x !== id); s.alliance[id] = false; }
    else delete s.pacts[id][type];
    const hit = type === 'buendnis' || type === 'beitritt' ? 25 : type === 'nichtangriff' ? 20 : 10;
    s.relations[id] = clamp(s.relations[id] - hit, -100, 100);
    s.baseRelations[id] -= hit / 3;
    if (type === 'nichtangriff') s.stats.reputation = clamp(s.stats.reputation - 4, 0, 100);
    s.budget = computeBudget(s);
    addNews(s, `${TREATIES[type].name} mit ${o.name} gekündigt.`, 'bad');
    return { ok: true, msg: `${TREATIES[type].name} gekündigt.` };
  }

  // ─────────────────────────── Bündnisse (Blöcke) ───────────────────────────
  const BLOCS = {
    EU:    { name: 'Europäische Union', icon: '⭐', kind: 'Wirtschaft & Politik', desc: 'Binnenmarkt mit allen Mitgliedern, Wachstum +0,2 %', trade: true, mods: { growth: 0.2 },
             req: s => s.country.region !== 'Europa' ? 'Nur europäische Länder' : s.country.gov !== 'demokratie' ? 'Nur Demokratien' : s.stats.corruption > 45 ? 'Korruption muss unter 45 liegen' : null },
    NATO:  { name: 'NATO', icon: '🛡️', kind: 'Militärbündnis', desc: 'Beistand aller Mitglieder im Krieg, Sicherheit +3', alliance: true, mods: { security: 3 },
             req: s => s.country.gov !== 'demokratie' ? 'Nur Demokratien' : s.blocs.includes('BRICS') ? 'Unvereinbar mit BRICS' : null },
    BRICS: { name: 'BRICS', icon: '🌐', kind: 'Wirtschaftsforum', desc: 'Günstige Kredite und Partner: Zinsen −0,4, Wachstum +0,1 %', mods: { interest: -0.4, growth: 0.1 },
             req: s => s.blocs.includes('NATO') ? 'Unvereinbar mit NATO' : null },
    NA:    { name: 'USMCA (Nordamerika)', icon: '🌎', kind: 'Freihandel', desc: 'Freihandel mit den USA, Kanada und Mexiko', trade: true, mods: { growth: 0.1 },
             req: s => ['US', 'CA', 'MX'].includes(s.countryId) ? null : 'Nur Nordamerika' },
    PAZ:   { name: 'Pazifik-Partnerschaft', icon: '🌊', kind: 'Freihandel', desc: 'Freihandel rund um den Pazifik, Wachstum +0,1 %', trade: true, mods: { growth: 0.1 },
             req: s => ['Asien', 'Ozeanien', 'Amerika'].includes(s.country.region) ? null : 'Nur Pazifik-Anrainer' },
  };
  const RIVAL_BLOC = { NATO: 'BRICS', BRICS: 'NATO' };
  function blocMembers(s, key) { return COUNTRIES.filter(c => c.id !== s.countryId && c.blocs.includes(key)).map(c => c.id); }
  function blocStatus(s, key) {
    const b = BLOCS[key], members = blocMembers(s, key);
    const member = s.blocs.includes(key);
    const avg = members.length ? members.reduce((a, id) => a + s.relations[id], 0) / members.length : 0;
    const chance = clamp(0.2 + avg / 100 + (s.stats.reputation - 50) / 150, 0.05, 0.92);
    const cd = Math.max(0, (s.cooldowns['bloc:' + key] || 0) - s.month);
    let why = member ? null : b.req(s) || (cd ? `Neuer Antrag in ${cd} Mon. möglich` : null) || (s.wars.some(w => members.includes(w.enemy)) ? 'Wir sind im Krieg mit einem Mitglied' : null);
    return { member, members, chance, why, avg, joinCost: 25, leaveCost: 10 };
  }
  function joinBloc(s, key) {
    const st = blocStatus(s, key), b = BLOCS[key];
    if (st.member) return { ok: false, why: 'Bereits Mitglied' };
    if (st.why) return { ok: false, why: st.why };
    if (s.capital < st.joinCost) return { ok: false, why: `Benötigt ${st.joinCost} ⚡` };
    s.capital -= st.joinCost;
    if (Math.random() >= st.chance) {
      s.cooldowns['bloc:' + key] = s.month + 12;
      addNews(s, `Beitrittsantrag zur ${b.name} abgelehnt.`, 'bad');
      return { ok: true, msg: `❌ Die Mitglieder lehnen unseren Beitritt zur ${b.name} ab.` };
    }
    s.blocs.push(key);
    for (const id of st.members) {
      if (b.trade && !s.sanctions[id]) s.trade[id] = true;
      if (b.alliance) s.alliance[id] = true;
      s.relations[id] = clamp(s.relations[id] + 10, -100, 100);
      s.baseRelations[id] = clamp(s.baseRelations[id] + 10, -100, 100);
    }
    if (RIVAL_BLOC[key]) for (const id of blocMembers(s, RIVAL_BLOC[key])) s.relations[id] = clamp(s.relations[id] - 15, -100, 100);
    s.budget = computeBudget(s);
    addNews(s, `Historischer Schritt: Wir sind jetzt Mitglied der ${b.name}!`, 'good');
    return { ok: true, msg: `✅ Willkommen in der ${b.name}!` };
  }
  function leaveBloc(s, key) {
    const st = blocStatus(s, key), b = BLOCS[key];
    if (!st.member) return { ok: false, why: 'Kein Mitglied' };
    if (s.capital < st.leaveCost) return { ok: false, why: `Benötigt ${st.leaveCost} ⚡` };
    s.capital -= st.leaveCost;
    s.blocs = s.blocs.filter(x => x !== key);
    const still = (id, prop) => s.blocs.some(k => BLOCS[k]?.[prop] && blocMembers(s, k).includes(id));
    for (const id of st.members) {
      if (b.trade && !still(id, 'trade')) s.trade[id] = false;
      if (b.alliance && !still(id, 'alliance')) s.alliance[id] = false;
      s.relations[id] = clamp(s.relations[id] - 15, -100, 100);
      s.baseRelations[id] = clamp(s.baseRelations[id] - 10, -100, 100);
    }
    s.budget = computeBudget(s);
    addNews(s, `Wir treten aus der ${b.name} aus.`, 'bad');
    return { ok: true, msg: `Austritt aus der ${b.name} vollzogen.` };
  }
  function foundBloc(s, name) {
    if (s.ownBloc) return { ok: false, why: 'Du hast bereits ein Bündnis gegründet' };
    if (s.stats.reputation < 30) return { ok: false, why: 'Dein Ansehen ist zu gering (mind. 30)' };
    if (s.capital < 30) return { ok: false, why: 'Benötigt 30 ⚡' };
    s.capital -= 30;
    s.ownBloc = { name: (name || '').trim().slice(0, 40) || `${s.country.name}-Pakt`, members: [], founded: s.month };
    addNews(s, `${s.leader.title} ${s.leader.name} gründet das Bündnis „${s.ownBloc.name}“.`, 'good');
    return { ok: true, msg: `✅ „${s.ownBloc.name}“ gegründet. Lade jetzt Länder per Vertrag ein!` };
  }
  function dissolveBloc(s) {
    if (!s.ownBloc) return { ok: false, why: 'Kein eigenes Bündnis' };
    for (const id of s.ownBloc.members) { s.alliance[id] = false; s.relations[id] = clamp(s.relations[id] - 15, -100, 100); }
    addNews(s, `Das Bündnis „${s.ownBloc.name}“ wird aufgelöst.`, 'bad');
    s.ownBloc = null;
    return { ok: true, msg: 'Bündnis aufgelöst.' };
  }

  // ─────────────────────────── Atomwaffenfreie Welt ───────────────────────────
  function nuclearHolders(s) {
    const l = Object.keys(s.worldNukes).filter(id => s.worldNukes[id] > 0);
    if (s.nukes > 0 || s.nukeProgram) l.push(s.countryId);
    return l;
  }
  function disarmChance(s, id) {
    if (atWarWith(s, id)) return 0;
    const signed = Object.keys(s.disarm.signed).length;
    const selfOpen = (s.nukes > 0 || s.nukeProgram) && !s.disarm.signed[s.countryId];
    return clamp(0.1 + s.relations[id] / 160 + (s.stats.reputation - 50) / 200 + signed * 0.07 + (s.pacts[id]?.ruestung ? 0.15 : 0) - (selfOpen ? 0.25 : 0), 0.02, 0.85);
  }
  function startDisarm(s) {
    if (s.disarm.active) return { ok: false, why: 'Initiative läuft bereits' };
    if (s.nukeUsed) return { ok: false, why: 'Nach deinem Atomschlag glaubt dir niemand' };
    if (s.stats.reputation < 45) return { ok: false, why: 'Ansehen mindestens 45 nötig' };
    if (s.capital < 20) return { ok: false, why: 'Benötigt 20 ⚡' };
    s.capital -= 20;
    s.disarm.active = true;
    s.stats.reputation = clamp(s.stats.reputation + 3, 0, 100);
    s.groupMood.greens += 6; s.groupMood.youth += 4;
    addNews(s, `${s.leader.title} ${s.leader.name} startet eine Weltinitiative für die Abschaffung aller Atomwaffen.`, 'good');
    return { ok: true, msg: '✅ Abrüstungsinitiative gestartet. Überzeuge jetzt jede Atommacht einzeln.' };
  }
  function persuadeDisarm(s, id) {
    if (!s.disarm.active) return { ok: false, why: 'Starte zuerst die Initiative' };
    if (s.disarm.signed[id]) return { ok: false, why: 'Hat bereits unterzeichnet' };
    const cd = (s.cooldowns['disarm:' + id] || 0) - s.month;
    if (cd > 0) return { ok: false, why: `Erst in ${cd} Mon. wieder` };
    if (s.capital < 12) return { ok: false, why: 'Benötigt 12 ⚡' };
    s.capital -= 12;
    s.cooldowns['disarm:' + id] = s.month + 6;
    const o = byId(id);
    if (Math.random() < disarmChance(s, id)) {
      s.disarm.signed[id] = true;
      s.relations[id] = clamp(s.relations[id] + 5, -100, 100);
      addNews(s, `${o.name} unterzeichnet den Vertrag über die Abschaffung von Atomwaffen!`, 'good');
      return { ok: true, msg: `✅ ${o.name} unterzeichnet!` };
    }
    s.relations[id] = clamp(s.relations[id] - 2, -100, 100);
    return { ok: true, msg: `❌ ${o.name} lehnt (noch) ab.` };
  }
  function pledgeDisarm(s) {
    if (!s.disarm.active) return { ok: false, why: 'Starte zuerst die Initiative' };
    if (!(s.nukes > 0 || s.nukeProgram)) return { ok: false, why: 'Wir besitzen keine Atomwaffen' };
    if (s.disarm.signed[s.countryId]) return { ok: false, why: 'Bereits unterzeichnet' };
    if (s.capital < 10) return { ok: false, why: 'Benötigt 10 ⚡' };
    s.capital -= 10;
    s.disarm.signed[s.countryId] = true;
    if (s.nukeProgram) { s.nukeProgram = null; delete s.policies.atomwaffen; }
    s.groupMood.military -= 10; s.groupMood.conservatives -= 5; s.groupMood.greens += 10;
    s.stats.reputation = clamp(s.stats.reputation + 5, 0, 100);
    addNews(s, 'Wir verpflichten uns, unser eigenes Atomarsenal abzubauen.', 'good');
    return { ok: true, msg: '✅ Wir haben unterzeichnet – das macht uns glaubwürdig.' };
  }
  function tickDisarm(s) {
    const d = s.disarm;
    if (!d || !d.active || d.done) return;
    // Unterzeichner können wieder abspringen
    for (const id in d.signed) {
      if (id === s.countryId) continue;
      if (atWarWith(s, id) || (s.relations[id] < -40 && Math.random() < 0.05)) {
        delete d.signed[id];
        if (d.dismantling) { d.dismantling = false; addNews(s, `${byId(id).name} stoppt die Abrüstung – der Prozess gerät ins Stocken!`, 'bad'); }
        else addNews(s, `${byId(id).name} zieht seine Unterschrift unter den Abrüstungsvertrag zurück.`, 'bad');
      }
    }
    const holders = nuclearHolders(s);
    const allSigned = holders.every(id => d.signed[id]);
    if (!d.dismantling && allSigned && holders.length) {
      d.dismantling = true;
      s.stats.reputation = clamp(s.stats.reputation + 15, 0, 100);
      s.approvalMood += 6;
      addNews(s, '🕊️ Alle Atommächte haben unterzeichnet – die Abrüstung beginnt!', 'good');
      s.pendingEvents.push(infoEvent('🕊️', 'Historischer Abrüstungsvertrag', 'Alle Atommächte der Welt haben den Vertrag unterzeichnet. Unter internationaler Aufsicht werden die Arsenale in den nächsten Jahren Schritt für Schritt vernichtet. Die Welt feiert dich als Friedensstifter.'));
    }
    if (d.dismantling) {
      for (const id in s.worldNukes) s.worldNukes[id] = Math.max(0, Math.floor(s.worldNukes[id] * 0.94 - 5));
      if (s.nukes > 0) s.nukes = Math.max(0, Math.floor(s.nukes * 0.94 - 5));
      if (!nuclearHolders(s).length) {
        d.done = true; d.dismantling = false; s.flags.nukeFree = true;
        s.approvalMood += 8;
        addNews(s, '🕊️ Die letzte Atomwaffe der Welt ist vernichtet!', 'good');
        s.pendingEvents.push(infoEvent('🏅', 'Eine Welt ohne Atomwaffen', 'Die letzte Atomwaffe ist vernichtet. Zum ersten Mal seit 1945 lebt die Menschheit ohne die Gefahr eines Atomkriegs. Dir wird der Friedensnobelpreis verliehen.'));
      }
    }
  }

  // ─────────────────────────── Berater-Tipps ───────────────────────────
  function bestPoliciesFor(s, group, n = 2) {
    return POLICIES.filter(p => !(p.id in s.policies) && (p.groups[group] || 0) > 0 && canEnact(s, p.id).why !== 'Bereits aktiv')
      .sort((a, b) => b.groups[group] - a.groups[group]).slice(0, n).map(p => p.name);
  }

  function tips(s) {
    const T = [], c = s.country, e = s.econ, st = s.stats, b = s.budget;
    const add = (area, level, text) => T.push({ area, level, text });
    // Wirtschaft
    if (e.growth < 0) add('wirtschaft', 'danger', `Rezession! Die Wirtschaft schrumpft um ${fmt(-e.growth, 1)} %. Ein Konjunkturpaket, mehr Infrastruktur-Ausgaben oder niedrigere Unternehmenssteuern helfen.`);
    else if (e.growth < c.potential - 0.7) add('wirtschaft', 'warn', `Das Wachstum ist schwach (${fmt(e.growth, 1)} %). Bürokratieabbau, Digitalisierung oder Infrastruktur-Investitionen kurbeln es an.`);
    if (e.inflation > Math.max(c.inflBase, c.inflation) + 2) add('wirtschaft', 'danger', `Die Inflation (${fmt(e.inflation, 1)} %) ist zu hoch. Senke das Defizit oder sprich mit der Zentralbank.`);
    if (e.unemployment > c.unemployment + 1.5) add('wirtschaft', 'warn', `Die Arbeitslosigkeit steigt (${fmt(e.unemployment, 1)} %). Kurzarbeitergeld, Industriesubventionen oder ein Konjunkturpaket helfen.`);
    if (b.balance < -6) add('wirtschaft', 'danger', `Das Haushaltsdefizit ist mit ${fmt(-b.balance, 1)} % des BIP gefährlich hoch. Erhöhe Steuern oder kürze Ausgaben im Haushalt.`);
    else if (b.balance < c.deficit - 1.5) add('wirtschaft', 'warn', `Das Defizit wächst (${fmt(b.balance, 1)} % des BIP). Behalte die Schulden im Blick.`);
    if (b.interestShare > Math.max(0.2, s.start.interestShare + 0.08)) add('wirtschaft', 'danger', `Zinsen fressen ${fmt(b.interestShare * 100, 0)} % deiner Einnahmen! Eine Schuldenbremse senkt die Zinsen.`);
    if (b.balance > 1.5) add('wirtschaft', 'good', `Haushaltsüberschuss von ${fmt(b.balance, 1)} %! Du hast Spielraum für Investitionen oder Steuersenkungen.`);
    if (c.oil > 5 && s.oil < 0.8) add('wirtschaft', 'warn', 'Der Ölpreis ist niedrig – deine Einnahmen brechen weg. Diversifiziere die Wirtschaft!');
    // Soziales
    if (st.health < c.stats.health - 5) add('soziales', 'warn', 'Das Gesundheitssystem verschlechtert sich. Erhöhe die Gesundheitsausgaben.');
    if (st.education < c.stats.education - 5) add('soziales', 'warn', 'Die Bildung leidet. Mehr Bildungsausgaben oder ein Bildungsgipfel helfen.');
    if (st.environment < 35) add('soziales', 'warn', 'Die Umwelt ist in schlechtem Zustand. Erneuerbare Energien oder Umweltausgaben helfen.');
    if (st.welfare < c.stats.welfare - 6) add('soziales', 'warn', 'Das soziale Netz wird löchrig. Arbeiter und Rentner sind besorgt.');
    // Militär
    if (s.groups.military < 30) add('militaer', 'danger', `Das Militär ist unzufrieden (${fmt(s.groups.military, 0)} %). Putschgefahr! Erhöhe das Verteidigungsbudget oder beschließe die Veteranenversorgung.`);
    if (st.security < 40) add('militaer', 'warn', 'Die innere Sicherheit ist schlecht. Mehr Polizei hilft gegen Kriminalität und Terror.');
    if (s.wars.length) { const w = s.wars[0]; add('militaer', w.progress < 0 ? 'danger' : 'info', `Krieg gegen ${byId(w.enemy).name}: Fortschritt ${fmt(w.progress, 0)}. ${w.progress < 0 ? 'Mobilisiere oder biete Frieden an!' : 'Wir sind auf Siegkurs.'}`); }
    if (s.terror > 60) add('militaer', s.terror > 75 ? 'danger' : 'warn', `Die Terrorgefahr ist hoch (${fmt(s.terror, 0)}). Setze ${c.sf.name} gegen Terrorzellen ein oder stärke die Polizei.`);
    if (s.readiness > 55 && !s.wars.length) add('militaer', 'info', `Die Mobilisierung kostet ${fmt((s.readiness - 25) * 0.035, 1)} % des BIP pro Jahr und belastet die Bevölkerung.`);
    if (s.wars.length) {
      const w = s.wars[0], odds = warOdds(s, w.enemy), o = byId(w.enemy);
      if (odds < 0.4) add('militaer', 'danger', `Wir sind ${o.name} militärisch klar unterlegen (Kräfteverhältnis ${fmt(odds * 100, 0)} %). Mobilisiere, suche Verbündete oder biete Frieden an.`);
      if (hasNukes(s, w.enemy) && w.progress > 55) add('militaer', 'danger', `${o.name} ist eine Atommacht. Drängst du sie zu weit in die Enge, droht nukleare Eskalation!`);
      if (s.readiness < 60) add('militaer', 'warn', `Unsere Kriegsbereitschaft ist zu niedrig (${fmt(s.readiness, 0)}). Erhöhe die Bereitschaftsstufe, sonst kämpft die Armee mit halber Kraft.`);
    }
    if (s.capacity < 35) add('politik', 'info', `Die Staatskapazität ist gering (${fmt(s.capacity, 0)}): Gesetze wirken nur teilweise, Fortschritt braucht Jahrzehnte. Korruptionsbekämpfung und Verwaltungsreformen stärken sie.`);
    const rival = Object.keys(s.relations).sort((a, b) => s.relations[a] - s.relations[b])[0];
    if (rival && s.relations[rival] < -60 && !s.wars.length && enemyPower(rival) > militaryPower(s)) add('militaer', s.relations[rival] < -80 ? 'warn' : 'info', `${byId(rival).name} ist feindselig und militärisch stärker als wir. Rüste auf oder suche Verbündete.`);
    // Politik
    if (st.stability < 25) add('politik', 'danger', `Die Stabilität ist kritisch (${fmt(st.stability, 0)}). Revolutionsgefahr! Eine Rede an die Nation oder der Ausnahmezustand helfen kurzfristig.`);
    else if (st.stability < 45) add('politik', 'warn', 'Die Stabilität sinkt. Achte auf Arbeitslosigkeit, Sicherheit und Zustimmung.');
    if (st.corruption > 55) add('politik', 'warn', `Hohe Korruption (${fmt(st.corruption, 0)}) kostet dich Steuereinnahmen. Eine Antikorruptionsbehörde hilft.`);
    const toElection = s.nextElection - s.month;
    if (c.gov === 'demokratie' && toElection <= 12 && s.approval < 50 && !(s.mode === 'klassisch' && s.terms >= 3))
      add('politik', s.approval < 42 ? 'danger' : 'warn', `Wahl in ${toElection} Monaten – du liegst bei ${fmt(s.approval, 0)} % Zustimmung. Du brauchst etwa 48 % für einen Sieg.`);
    if (s.capital > 75) add('politik', 'info', `Du hast ${fmt(s.capital, 0)} ⚡ politisches Kapital. Nutze es für Reformen, bevor es verfällt!`);
    for (const g in GROUPS) if (s.groups[g] < 30 && g !== 'military') {
      const best = bestPoliciesFor(s, g);
      add('politik', 'warn', `${GROUPS[g].icon} ${GROUPS[g].name} sind unzufrieden (${fmt(s.groups[g], 0)} %). ${best.length ? 'Hilfreich wäre: ' + best.join(', ') + '.' : ''}`);
    }
    // Diplomatie
    if (st.reputation < 35) add('diplomatie', 'warn', 'Dein Ansehen ist schlecht. Hilfspakete und Klimakonferenzen verbessern es.');
    const partners = Object.keys(s.relations).filter(id => !s.trade[id] && !s.sanctions[id] && s.relations[id] >= 25);
    if (partners.length) add('diplomatie', 'info', `Handelsabkommen möglich mit: ${partners.slice(0, 4).map(id => byId(id).name).join(', ')}. Jedes bringt zusätzliches Wachstum.`);
    if (!T.length) add('politik', 'good', 'Das Land ist auf einem guten Weg. Weiter so!');
    const order = { danger: 0, warn: 1, info: 2, good: 3 };
    return T.sort((a, b) => order[a.level] - order[b.level]);
  }

  // ─────────────────────────── Nachrichten ───────────────────────────
  function addNews(s, text, type = 'info') {
    s.news.unshift({ month: s.month, text, type });
    if (s.news.length > 120) s.news.length = 120;
  }

  function headline(s, prev) {
    const r = s.lastReport;
    if (Math.abs(r.growth) > 0.6) addNews(s, r.growth > 0 ? `Konjunktur zieht an: Wachstum steigt auf ${fmt(s.econ.growth, 1)} %.` : `Wirtschaft kühlt ab: Wachstum fällt auf ${fmt(s.econ.growth, 1)} %.`, r.growth > 0 ? 'good' : 'bad');
    if (s.month % 12 === 0) addNews(s, `Jahresbilanz: BIP ${fmtMoney(s.econ.gdp)}, Arbeitslosigkeit ${fmt(s.econ.unemployment, 1)} %, Inflation ${fmt(s.econ.inflation, 1)} %.`, 'info');
    if (prev.approval >= 50 && s.approval < 50) addNews(s, 'Umfrage: Mehrheit der Bürger ist unzufrieden mit der Regierung.', 'bad');
    if (prev.approval < 50 && s.approval >= 50) addNews(s, 'Umfrage: Mehrheit steht hinter der Regierung!', 'good');
  }

  // ─────────────────────────── Bewertung ───────────────────────────
  function legacy(s) {
    const c = s.country, h = s.history;
    const avgAppr = h.approval.reduce((a, b) => a + b, 0) / h.approval.length;
    const gdpGrowth = (s.econ.gdp / c.gdp - 1) * 100;
    let quality = 0;
    for (const k of ['education', 'health', 'security', 'environment', 'welfare', 'reputation']) quality += s.stats[k] - c.stats[k];
    quality -= (s.stats.corruption - c.stats.corruption);
    const debtChange = s.econ.debt - c.debt;
    const score = Math.round(s.month * 3 + avgAppr * 4 + gdpGrowth * 6 + quality * 3 - Math.max(0, debtChange) * 2 + (s.gameOver && s.gameOver.won ? 200 : 0) + (s.flags.nukeFree ? 400 : 0));
    let rank = 'Fußnote der Geschichte';
    if (s.flags.nukeFree && !s.nukeUsed) return { score, rank: 'Friedensnobelpreisträger', avgAppr, gdpGrowth, quality, debtChange };
    if (s.nukeUsed) return { score: Math.min(score, 0) - 500, rank: 'Von der Welt geächtet', avgAppr, gdpGrowth, quality, debtChange };
    if (score > 300) rank = 'Solides Staatsoberhaupt';
    if (score > 600) rank = 'Großer Reformer';
    if (score > 900) rank = 'Vater/Mutter der Nation';
    if (score > 1200) rank = 'Legende';
    return { score, rank, avgAppr, gdpGrowth, quality, debtChange };
  }

  // ─────────────────────────── Speichern / Laden ───────────────────────────
  function serialize(s) {
    const copy = { ...s }; delete copy.country;
    return JSON.stringify(copy);
  }
  function deserialize(str) {
    const s = JSON.parse(str);
    s.country = byId(s.countryId);
    if (!s.country) throw new Error('Unbekanntes Land');
    // Ältere Spielstände ergänzen
    const c = s.country;
    if (s.capacity === undefined) s.capacity = c.capacity;
    if (s.readiness === undefined) { s.readiness = 25; s.readinessTarget = 25; }
    if (!s.sf) s.sf = { quality: c.sf.quality, missions: 0, success: 0 };
    if (s.terror === undefined) s.terror = clamp(75 - s.stats.security * 0.7, 5, 90);
    if (s.nukes === undefined) { s.nukes = c.nukes; s.nukeProgram = null; s.nukeUsed = false; }
    if (!s.pacts) s.pacts = {};
    if (!s.blocs) s.blocs = [...c.blocs];
    if (!s.start.blocs) s.start.blocs = [...c.blocs];
    if (s.ownBloc === undefined) s.ownBloc = null;
    if (!s.worldNukes) { s.worldNukes = {}; for (const o of COUNTRIES) if (o.id !== c.id && o.nukes > 0) s.worldNukes[o.id] = o.nukes; }
    if (!s.disarm) s.disarm = { active: false, signed: {}, dismantling: false, done: false };
    s.budget = computeBudget(s);
    return s;
  }

  // ─────────────────────────── Formatierung ───────────────────────────
  function fmt(v, d = 1) { return Number(v).toLocaleString('de-DE', { minimumFractionDigits: d, maximumFractionDigits: d }); }
  function fmtSigned(v, d = 1) { return (v > 0 ? '+' : v < 0 ? '−' : '±') + fmt(Math.abs(v), d); }
  function fmtMoney(mrd) {
    if (Math.abs(mrd) >= 1000) return fmt(mrd / 1000, 2) + ' Bio. $';
    if (Math.abs(mrd) >= 1) return fmt(mrd, Math.abs(mrd) >= 100 ? 0 : 1) + ' Mrd. $';
    return fmt(mrd * 1000, 0) + ' Mio. $';
  }
  function dateStr(s, m = s.month) { const y = s.startYear + Math.floor(m / 12); return `${MONTHS[m % 12]} ${y}`; }
  function creditRating(s) {
    const x = s.budget.interestShare * 100 + Math.max(0, s.econ.debt - 60) * 0.15 - (s.stats.stability - 50) * 0.1 + (s.stats.corruption - 30) * 0.1;
    const scale = ['AAA', 'AA+', 'AA', 'A+', 'A', 'BBB', 'BB', 'B', 'CCC', 'CC', 'D'];
    return scale[clamp(Math.floor(x / 4), 0, scale.length - 1)];
  }

  return {
    newGame, tick, computeBudget, budgetChangeCost, applyBudget, computeMods, interestRate,
    rollRandomEvent, resolveEvent, applyEffects, scoreEffects, recommend, scorePolicy, recommendedPolicies,
    canEnact, enactPolicy, repealPolicy, repealCost, canDoAction, doAction,
    dipOptions, dipAction, DIP_ACTIONS, WAR_ACTIONS, warAction, militaryPower, enemyPower, atWarWith, warOdds,
    hasNukes, TREATIES, MONEY_OFFERS, hasTreaty, treatyBlocked, negotiationChance, negotiate, cancelTreaty,
    BLOCS, blocMembers, blocStatus, joinBloc, leaveBloc, foundBloc, dissolveBloc,
    nuclearHolders, disarmChance, startDisarm, persuadeDisarm, pledgeDisarm,
    READINESS_LEVELS, setReadiness, SF_OPS, sfOp, sfChance, sfTarget, chanceP, nuclearThreat, nuclearStrike,
    tips, legacy, serialize, deserialize, addNews,
    fmt, fmtSigned, fmtMoney, dateStr, creditRating, byId, policyById, actionById, clamp,
  };
})();
