// ════════════════════════════════════════════════════════════════════
//  Benutzeroberfläche
// ════════════════════════════════════════════════════════════════════
const UI = (() => {
  let S = null;                 // aktueller Spielzustand
  let view = 'overview';
  let selCountry = null;        // ausgewähltes Land in der Diplomatie
  let draft = null;             // Haushaltsentwurf
  let chartMetric = 'approval';
  let autoTimer = null;
  let prev = null;              // Werte vor dem letzten Monat (für Trends)
  let setupSel = 'DE', setupFilter = 'Alle';
  let setupOpts = { name: '', title: 'Präsident', difficulty: 'normal', mode: 'klassisch' };
  let startAnim = null;
  const prefs = loadPrefs();

  const $ = sel => document.querySelector(sel);
  const esc = str => String(str ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const F = Engine.fmt, FS = Engine.fmtSigned, FM = Engine.fmtMoney;
  const flag = (id, cls = 'flag') => `<img class="${cls}" src="assets/flags/${id.toLowerCase()}.svg" alt="${id}">`;
  const SAVE_KEY = 'praesident.save.v1';

  const NAV = [
    { id: 'overview', icon: '🧭', name: 'Lagezentrum' },
    { id: 'budget', icon: '💰', name: 'Haushalt' },
    { id: 'wirtschaft', icon: '📈', name: 'Wirtschaft' },
    { id: 'soziales', icon: '🤝', name: 'Soziales' },
    { id: 'militaer', icon: '🛡️', name: 'Militär' },
    { id: 'politik', icon: '🏛️', name: 'Politik' },
    { id: 'diplomatie', icon: '🌍', name: 'Diplomatie' },
    { id: 'stats', icon: '📊', name: 'Statistiken' },
    { id: 'news', icon: '📰', name: 'Nachrichten' },
  ];
  const TITLES = ['Präsident', 'Präsidentin', 'Kanzler', 'Kanzlerin', 'Premierminister', 'Premierministerin', 'Staatsoberhaupt'];
  const LABELS = {
    approval: 'Zustimmung', stability: 'Stabilität', growth: 'Wachstum', unemployment: 'Arbeitslosigkeit', inflation: 'Inflation',
    debt: 'Schulden', interest: 'Zinsen', capitalGain: 'Kapital/Monat', education: 'Bildung', health: 'Gesundheit', security: 'Sicherheit',
    environment: 'Umwelt', military: 'Militärstärke', corruption: 'Korruption', reputation: 'Ansehen', welfare: 'Soziales Netz',
    capacity: 'Staatskapazität', terror: 'Terrorgefahr', sf: 'Spezialkräfte',
  };
  const INVERT = { corruption: 1, unemployment: 1, inflation: 1, debt: 1, interest: 1, terror: 1 };
  const ADVISOR_IDLE = {
    wirtschaft: 'Die Wirtschaft läuft stabil. Bürokratieabbau und Digitalisierung sind fast immer gute Investitionen.',
    soziales: 'Sozial ist das Land ruhig. Bildung und Gesundheit zahlen sich langfristig immer aus.',
    militaer: 'Die Lage ist ruhig. Halte das Militär zufrieden – unzufriedene Generäle sind gefährlich.',
    politik: 'Politisch sitzt du fest im Sattel. Nutze dein politisches Kapital für große Reformen.',
    diplomatie: 'Gute Beziehungen öffnen Türen: Handelsabkommen bringen Wachstum, Bündnisse Schutz.',
  };

  // ─────────────────────────── Einstellungen & Ton ───────────────────────────
  function loadPrefs() {
    try { return { sound: true, speed: 1600, tutorialSeen: false, ...JSON.parse(localStorage.getItem('praesident.prefs') || '{}') }; }
    catch { return { sound: true, speed: 1600, tutorialSeen: false }; }
  }
  function savePrefs() { try { localStorage.setItem('praesident.prefs', JSON.stringify(prefs)); } catch { } }

  let actx = null;
  function sfx(type) {
    if (!prefs.sound) return;
    try {
      actx = actx || new (window.AudioContext || window.webkitAudioContext)();
      const seq = { click: [[660, 0.04]], tick: [[440, 0.05], [550, 0.05]], event: [[523, 0.1], [784, 0.16]],
        good: [[523, 0.08], [659, 0.08], [784, 0.14]], bad: [[392, 0.12], [311, 0.2]], war: [[196, 0.2], [185, 0.3]] }[type] || [[500, 0.05]];
      let t = actx.currentTime;
      for (const [f, d] of seq) {
        const o = actx.createOscillator(), g = actx.createGain();
        o.type = 'triangle'; o.frequency.value = f;
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.08, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + d);
        o.connect(g).connect(actx.destination); o.start(t); o.stop(t + d + 0.02); t += d * 0.9;
      }
    } catch { }
  }

  // ─────────────────────────── Bildschirme ───────────────────────────
  function hideTip() { const t = $('#tooltip'); if (t) t.classList.remove('show'); }
  function showScreen(id) {
    hideTip();
    if (id !== 'game') $('#toast-root').innerHTML = '';
    document.querySelectorAll('.screen').forEach(el => el.classList.toggle('active', el.id === 'screen-' + id));
    if (id === 'start') startMapLoop(); else stopMapLoop();
  }

  function initStart() {
    $('#btn-continue').style.display = hasSave() ? '' : 'none';
    showScreen('start');
  }

  // ─────────────────────────── Spielvorbereitung ───────────────────────────
  const REGION_FILTER = ['Alle', 'Europa', 'Amerika', 'Asien', 'Nahost & Afrika', 'Ozeanien', 'Leicht'];
  function stars(n) {
    if (n >= 4) return '<span class="stars" title="Schwierigkeit" style="color:var(--bad)">★★★★</span>';
    return `<span class="stars" title="Schwierigkeit">${'★'.repeat(n)}<span class="off">${'★'.repeat(3 - n)}</span></span>`;
  }
  function diffName(n) { return ['', 'Leicht', 'Mittel', 'Schwer', 'Extrem'][n]; }

  function showSetup() {
    $('#setup-filter').innerHTML = REGION_FILTER.map(f => `<button class="btn btn-sm ${f === setupFilter ? 'active' : ''}" data-action="setup-filter" data-f="${f}">${f}</button>`).join('');
    const list = COUNTRIES.filter(c => setupFilter === 'Alle' || (setupFilter === 'Leicht' ? c.difficulty === 1 :
      setupFilter === 'Nahost & Afrika' ? ['Nahost', 'Afrika'].includes(c.region) : setupFilter === 'Asien' ? ['Asien', 'Eurasien'].includes(c.region) : c.region === setupFilter));
    $('#country-grid').innerHTML = list.map(c => `
      <div class="country-card ${c.id === setupSel ? 'selected' : ''}" data-action="setup-select" data-id="${c.id}">
        ${flag(c.id, 'flag flag-lg')}
        <div><div class="cc-name">${esc(c.name)}</div><div class="cc-meta">${c.region} · ${c.gov === 'demokratie' ? 'Demokratie' : 'Autoritär'}</div>${stars(c.difficulty)}</div>
      </div>`).join('');
    renderSetupDetail();
    showScreen('setup');
  }

  function renderSetupDetail() {
    const c = Engine.byId(setupSel);
    const perCap = c.gdp * 1e9 / (c.pop * 1e6);
    const titleOpts = TITLES.map(t => `<option ${t === setupOpts.title ? 'selected' : ''}>${t}</option>`).join('');
    const seg = (key, opts) => `<div class="seg">${opts.map(([v, l]) => `<button class="${setupOpts[key] === v ? 'active' : ''}" data-action="setup-opt" data-k="${key}" data-v="${v}">${l}</button>`).join('')}</div>`;
    $('#setup-detail').innerHTML = `
      <div class="detail-head">${flag(c.id, 'flag flag-xl')}<div><h3>${esc(c.name)}</h3><div class="muted">${esc(c.capital)} · ${c.region}</div>${stars(c.difficulty)} <span class="muted">${diffName(c.difficulty)}</span></div></div>
      <p class="muted" style="margin:0">${esc(c.blurb)}</p>
      <div class="kv-grid">
        <div><span>Einwohner</span><b>${F(c.pop, c.pop < 20 ? 1 : 0)} Mio.</b></div>
        <div><span>BIP</span><b>${FM(c.gdp)}</b></div>
        <div><span>BIP/Kopf</span><b>${F(perCap, 0)} $</b></div>
        <div><span>Wachstum</span><b>${F(c.growth, 1)} %</b></div>
        <div><span>Arbeitslosigkeit</span><b>${F(c.unemployment, 1)} %</b></div>
        <div><span>Inflation</span><b>${F(c.inflation, 1)} %</b></div>
        <div><span>Schulden</span><b>${F(c.debt, 0)} %</b></div>
        <div><span>Haushalt</span><b>${FS(c.deficit, 1)} %</b></div>
        <div><span>Zustimmung</span><b>${c.approval} %</b></div>
        <div><span>Militär</span><b>${c.stats.military}${c.nuclear ? ' ☢️' : ''}</b></div>
        <div><span>Staatsform</span><b>${c.gov === 'demokratie' ? 'Demokratie' : 'Autoritär'}</b></div>
        <div><span>Bündnisse</span><b>${c.blocs.join(', ') || '–'}</b></div>
        <div><span>Staatskapazität</span><b class="${c.capacity < 35 ? 'bad' : c.capacity < 60 ? 'warn' : 'good'}">${c.capacity}</b></div>
        <div><span>Spezialeinheit</span><b>${esc(c.sf.name)}</b></div>
        <div><span>Atomwaffen</span><b>${c.nukes ? '☢️ ~' + F(c.nukes, 0) : 'keine'}</b></div>
        <div><span>Kampfkraft</span><b>${F(c.stats.military * c.milSize, 0)}</b></div>
      </div>
      <div class="form-row"><label>Dein Name</label><input type="text" id="inp-name" maxlength="28" placeholder="z. B. Alex Muster" value="${esc(setupOpts.name)}"></div>
      <div class="form-row"><label>Dein Titel</label><select id="inp-title">${titleOpts}</select></div>
      <div class="form-row"><label>Schwierigkeit</label>${seg('difficulty', [['leicht', 'Leicht'], ['normal', 'Normal'], ['schwer', 'Schwer']])}</div>
      <div class="form-row"><label>Spielmodus</label>${seg('mode', [['klassisch', '3 Amtszeiten'], ['endlos', 'Endlos']])}</div>
      <p class="muted" style="font-size:12px;margin:0">${c.gov === 'demokratie' ? 'Alle 4 Jahre wird gewählt – du brauchst die Mehrheit.' : 'Keine freien Wahlen – aber alle 4 Jahre eine Machtprobe. Achte auf Stabilität und Militär!'}</p>
      <button class="btn btn-primary btn-lg" data-action="start-game" style="min-width:0">Amt antreten ▶</button>`;
  }

  // ─────────────────────────── Spielstart / Laden ───────────────────────────
  function startGame() {
    setupOpts.name = ($('#inp-name')?.value || '').trim() || 'Alex Muster';
    setupOpts.title = $('#inp-title')?.value || 'Präsident';
    S = Engine.newGame(setupSel, setupOpts);
    view = 'overview'; draft = null; selCountry = null; prev = null;
    enterGame();
    save();
    if (!prefs.tutorialSeen) { prefs.tutorialSeen = true; savePrefs(); showHelp(true); }
  }
  function enterGame() {
    showScreen('game');
    renderAll();
    processQueue();
  }
  function hasSave() { try { return !!localStorage.getItem(SAVE_KEY); } catch { return false; } }
  function save() { try { if (S && !S.gameOver) localStorage.setItem(SAVE_KEY, Engine.serialize(S)); } catch { } }
  function continueGame() {
    try { S = Engine.deserialize(localStorage.getItem(SAVE_KEY)); view = 'overview'; draft = null; enterGame(); }
    catch (e) { toast('Spielstand konnte nicht geladen werden.', 'bad'); }
  }
  function exportSave() {
    const blob = new Blob([Engine.serialize(S)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `praesident_${S.countryId}_${Engine.dateStr(S).replace(' ', '_')}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    toast('Spielstand gespeichert.', 'good');
  }
  function importSave(file) {
    const r = new FileReader();
    r.onload = () => {
      try { S = Engine.deserialize(r.result); view = 'overview'; draft = null; closeModal(); enterGame(); save(); toast('Spielstand geladen.', 'good'); }
      catch { toast('Ungültige Spielstand-Datei.', 'bad'); }
    };
    r.readAsText(file);
  }

  // ─────────────────────────── Monatswechsel ───────────────────────────
  function modalOpen() { return !!$('#modal-root').children.length; }

  function nextMonth() {
    if (!S || S.gameOver || modalOpen()) return;
    prev = { groups: { ...S.groups }, stats: { ...S.stats }, approval: S.approval };
    Engine.tick(S);
    draft = null;
    save();
    sfx('tick');
    renderAll();
    monthToast();
    processQueue();
  }

  function processQueue() {
    if (!S) return;
    if (S.pendingEvents.length) { stopAuto(false); showEvent(S.pendingEvents[0]); return; }
    if (S.gameOver) { stopAuto(false); try { localStorage.removeItem(SAVE_KEY); } catch { } setTimeout(showEnd, 300); }
  }

  function toggleAuto() {
    if (autoTimer) { stopAuto(); return; }
    autoTimer = setInterval(() => { if (!modalOpen()) nextMonth(); }, prefs.speed);
    renderTopbar();
  }
  function stopAuto(render = true) {
    if (autoTimer) { clearInterval(autoTimer); autoTimer = null; if (render) renderTopbar(); else setTimeout(renderTopbar, 0); }
  }

  function monthToast() {
    const r = S.lastReport;
    if (!r) return;
    const line = (l, v, d, inv, unit = '') => {
      const cls = Math.abs(v) < 0.05 ? 'muted' : (v > 0) !== !!inv ? 'good' : 'bad';
      return `<span>${l}</span><span class="${cls}">${FS(v, d)}${unit}</span>`;
    };
    toast(`<div class="t-title">📅 ${Engine.dateStr(S)}</div><div class="month-sum">
      ${line('Zustimmung', r.approval, 1, false, ' %')}${line('Stabilität', r.stability, 1)}
      ${line('Wachstum', r.growth, 2, false, ' %')}${line('Schulden', r.debt, 1, true, ' %')}
      ${line('Polit. Kapital', r.capital, 0, false, ' ⚡')}</div>`, 'info', 2200, 'month');
  }

  // ─────────────────────────── Rendering ───────────────────────────
  function renderAll() {
    renderTopbar();
    renderSidebar();
    renderView();
    renderTicker();
  }

  function renderTopbar() {
    if (!S) return;
    const b = S.budget, demo = S.country.gov === 'demokratie';
    const toE = S.nextElection - S.month;
    const finalTerm = S.mode === 'klassisch' && S.terms >= 3;
    const elText = finalTerm ? `Amtsende in ${toE} Mon.` : demo ? `Wahl in ${toE} Mon.` : `Machtprobe in ${toE} Mon.`;
    const stat = (cls, l, v, tip) => `<div class="tb-stat ${cls}" data-tip="${esc(tip)}"><div class="l">${l}</div><div class="v">${v}</div></div>`;
    const apCls = S.approval >= 50 ? 'good' : S.approval >= 40 ? 'warn' : 'bad';
    const stCls = S.stats.stability >= 50 ? 'good' : S.stats.stability >= 30 ? 'warn' : 'bad';
    $('#topbar').innerHTML = `
      <div class="tb-country">${flag(S.countryId, 'flag flag-lg')}<div><div class="name">${esc(S.country.name)}</div><div class="leader">${esc(S.leader.title)} ${esc(S.leader.name)}</div></div></div>
      <div class="tb-date"><div class="d">${Engine.dateStr(S)}</div><div class="e ${toE <= 6 ? 'warn' : ''}">${elText}</div></div>
      <div class="tb-stats">
        ${stat('', '👍 Zustimmung', `<span class="${apCls}">${F(S.approval, 1)}<small>%</small></span>`, STAT_INFO.approval.desc)}
        ${stat('', '🏛️ Stabilität', `<span class="${stCls}">${F(S.stats.stability, 0)}</span>`, STAT_INFO.stability.desc)}
        ${stat('', '📈 Wachstum', `<span class="${S.econ.growth >= 1 ? 'good' : S.econ.growth >= 0 ? 'warn' : 'bad'}">${F(S.econ.growth, 1)}<small>%</small></span>`, STAT_INFO.growth.desc)}
        ${stat('', '💰 Haushalt', `<span class="${b.balance >= -1 ? 'good' : b.balance >= -4 ? 'warn' : 'bad'}">${FS(b.balance, 1)}<small>%</small></span>`, 'Haushaltssaldo in % des BIP pro Jahr. Negativ = Defizit (neue Schulden).')}
        ${stat('', '🧾 Schulden', `${F(S.econ.debt, 0)}<small>%</small>`, STAT_INFO.debt.desc + ' Kreditrating: ' + Engine.creditRating(S))}
        ${stat('capital', '⚡ Kapital', `${F(S.capital, 0)}`, 'Politisches Kapital: Damit setzt du Gesetze, Maßnahmen und Haushaltsänderungen durch. Steigt jeden Monat – schneller bei hoher Zustimmung.')}
      </div>
      <div class="tb-actions">
        <button class="btn btn-icon btn-auto ${autoTimer ? 'on' : ''}" data-action="auto" data-tip="Automatisch Monate ablaufen lassen. Pausiert bei Ereignissen.">${autoTimer ? '⏸' : '⏩'}</button>
        <button class="btn btn-primary btn-next" data-action="next" data-tip="Nächster Monat <kbd>Leertaste</kbd>">Nächster Monat ▶</button>
      </div>`;
  }

  function renderSidebar() {
    const tips = Engine.tips(S);
    const danger = new Set(tips.filter(t => t.level === 'danger').map(t => t.area));
    $('#sidebar').innerHTML = NAV.map((n, i) => `
      <div class="nav-item ${view === n.id ? 'active' : ''}" data-action="nav" data-view="${n.id}">
        <span class="ico">${n.icon}</span><span class="lbl">${n.name}</span><span class="key">${i + 1}</span>
        ${danger.has(n.id) ? '<span class="alert pulse"></span>' : ''}
        ${n.id === 'militaer' && S.wars.length ? '<span class="alert pulse"></span>' : ''}
      </div>`).join('') + `
      <div class="side-foot">
        <button class="btn btn-sm" data-action="menu">☰ <span class="lbl">Menü</span></button>
      </div>`;
  }

  function renderTicker() {
    const items = S.news.slice(0, 8).map(n => `<span>${n.type === 'bad' ? '🔴' : n.type === 'good' ? '🟢' : '🔵'} ${esc(n.text)}</span>`).join('');
    const el = $('#ticker');
    if (el.dataset.sig !== items) { el.dataset.sig = items; el.innerHTML = items; el.style.animation = 'none'; el.offsetHeight; el.style.animation = ''; }
  }

  function renderView() {
    const v = $('#view');
    const scroll = v.dataset.view === view ? v.scrollTop : 0;
    v.dataset.view = view;
    const fn = { overview: viewOverview, budget: viewBudget, diplomatie: viewDiplomacy, stats: viewStats, news: viewNews }[view] || (() => viewArea(view));
    v.innerHTML = fn();
    v.scrollTop = scroll;
    afterRender();
  }

  function afterRender() {
    document.querySelectorAll('canvas[data-spark]').forEach(c => drawSpark(c, S.history[c.dataset.spark], c.dataset.color));
    document.querySelectorAll('canvas[data-map]').forEach(c => drawMap(c));
    document.querySelectorAll('canvas[data-chart]').forEach(c => drawChart(c, c.dataset.chart));
    document.querySelectorAll('.vote-bar i[data-w]').forEach(i => requestAnimationFrame(() => { i.style.width = i.dataset.w + '%'; }));
  }

  // ─────────────────────────── Hilfsbausteine ───────────────────────────
  function barColor(v, inv) { const x = inv ? 100 - v : v; return x >= 60 ? 'var(--good)' : x >= 35 ? 'var(--warn)' : 'var(--bad)'; }
  function trendArrow(now, before, inv) {
    if (before === undefined) return '';
    const d = now - before;
    if (Math.abs(d) < 0.3) return '<span class="trend muted">•</span>';
    const good = (d > 0) !== !!inv;
    return `<span class="trend ${good ? 'good' : 'bad'}">${d > 0 ? '▲' : '▼'}</span>`;
  }
  function barRow(label, v, opts = {}) {
    const mark = opts.mark !== undefined ? `<span class="mark" style="left:${Engine.clamp(opts.mark, 0, 100)}%"></span>` : '';
    return `<div class="bar-row" data-tip="${esc(opts.tip || '')}"><span class="lbl">${label}</span>
      <div class="bar"><i style="width:${Engine.clamp(v, 0, 100)}%;background:${barColor(v, opts.inv)}"></i>${mark}</div>
      <span class="num">${F(v, 0)}${trendArrow(v, opts.before, opts.inv)}</span></div>`;
  }

  function moneyText(pct) { return `${F(Math.abs(pct), 2)} % BIP ≈ ${FM(Math.abs(pct) * S.econ.gdp / 100)}`; }
  function chip(text, cls = 'neutral') { return `<span class="chip ${cls}">${text}</span>`; }
  function signedChip(label, v, inv, d = 1, suffix = '') {
    if (!v) return '';
    const good = (v > 0) !== !!inv;
    return chip(`${label} ${FS(v, d)}${suffix}`, good ? 'good' : 'bad');
  }

  // Wirkungen als Chips (Ereignisse & Maßnahmen)
  function effectChips(eff, land) {
    if (!eff) return '';
    const out = [];
    const L = land ? Engine.byId(land) : null;
    if (eff.money) out.push(chip((eff.money > 0 ? '💸 Kosten ' : '💰 Einnahmen ') + moneyText(eff.money), eff.money > 0 ? 'bad' : 'good'));
    if (eff.capital) out.push(signedChip('⚡ Kapital', eff.capital, false, 0));
    if (eff.stats) for (const k in eff.stats) out.push(signedChip(LABELS[k] || k, eff.stats[k], INVERT[k], 0));
    if (eff.econ) for (const k in eff.econ) out.push(signedChip(LABELS[k], eff.econ[k], INVERT[k], 1, ' %'));
    if (eff.groups) for (const g in eff.groups) out.push(signedChip(GROUPS[g].icon + ' ' + GROUPS[g].name, eff.groups[g], false, 0));
    if (eff.mods) for (const m of eff.mods) out.push(signedChip(`⏳ ${LABELS[m.key] || m.key}`, m.value, INVERT[m.key], 1, ` (${m.months} Mon.)`));
    if (eff.relation && L) out.push(signedChip(`🤝 ${L.name}`, eff.relation, false, 0));
    if (eff.trade && L) out.push(chip(`📜 Handelsabkommen mit ${L.name}`, 'good'));
    if (eff.war && L) out.push(chip(`⚔️ KRIEG mit ${L.name}`, 'bad'));
    if (eff.peace) out.push(chip('🕊️ Frieden', 'good'));
    if (eff.oil) { const exp = S.country.oil > 2; out.push(chip(`🛢️ Ölpreis ${FS(eff.oil * 100, 0)} %`, (eff.oil > 0) === exp ? 'good' : 'bad')); }
    if (eff.campaign) out.push(signedChip('📣 Wahlkampf', eff.campaign, false, 0));
    if (eff.terror) out.push(signedChip('💣 Terrorgefahr', eff.terror, true, 0));
    if (eff.sfQuality) out.push(signedChip(`🥷 ${S.country.sf.name}`, eff.sfQuality, false, 0));
    let html = `<div class="chips">${out.join('')}</div>`;
    if (eff.chance) {
      const p = Math.round(Engine.chanceP(S, eff.chance) * 100);
      html += `<div class="chance-block">${eff.chance.sf ? `<div class="ch-line">🥷 Erfolgschance abhängig von <b>${esc(S.country.sf.name)}</b> (Qualität ${F(S.sf.quality, 0)})</div>` : ''}
        <div class="ch-line">🎲 <b>${p} %</b> Erfolg: ${effectChips(eff.chance.success, land) || chip('keine Folgen')}</div>
        <div class="ch-line">🎲 <b>${100 - p} %</b> Misserfolg: ${effectChips(eff.chance.fail, land) || chip('keine Folgen')}</div></div>`;
    }
    return out.length || eff.chance ? html : '';
  }

  function policyChips(p) {
    const out = [];
    if (p.upkeep) out.push(chip((p.upkeep > 0 ? '💸 ' : '💰 ') + `${F(Math.abs(p.upkeep), 1)} % BIP/Jahr ≈ ${FM(Math.abs(p.upkeep) * S.econ.gdp / 100)}`, p.upkeep > 0 ? 'bad' : 'good'));
    for (const k in p.effects) out.push(signedChip(LABELS[k] || k, p.effects[k], INVERT[k], ['growth', 'unemployment', 'inflation', 'interest', 'capitalGain'].includes(k) ? 2 : 0));
    for (const g in p.groups) out.push(signedChip(GROUPS[g].icon + ' ' + GROUPS[g].name, p.groups[g], false, 0));
    return `<div class="chips">${out.join('')}</div>`;
  }

  // ─────────────────────────── Ansicht: Lagezentrum ───────────────────────────
  function kpi(label, value, sub, key, color, tip) {
    return `<div class="kpi" data-tip="${esc(tip)}"><div class="l">${label}</div><div class="v">${value}</div><div class="d">${sub}</div>
      ${key ? `<canvas data-spark="${key}" data-color="${color}"></canvas>` : ''}</div>`;
  }
  function deltaTxt(key, d = 1, inv) {
    const h = S.history[key]; if (h.length < 2) return '<span class="muted">–</span>';
    const v = h[h.length - 1] - h[Math.max(0, h.length - 13)];
    const cls = Math.abs(v) < 0.05 ? 'muted' : (v > 0) !== !!inv ? 'good' : 'bad';
    return `<span class="${cls}">${FS(v, d)}</span> <span class="muted">12 Mon.</span>`;
  }

  function adviceList(tips, max) {
    if (!tips.length) return '<div class="tip good"><span class="ti">✅</span><span>Keine Probleme in diesem Bereich.</span></div>';
    const icon = { danger: '🚨', warn: '⚠️', info: '💡', good: '✅' };
    return tips.slice(0, max).map(t => `<div class="tip ${t.level}"><span class="ti">${icon[t.level]}</span><span>${esc(t.text)}</span>
      ${t.area && view === 'overview' ? `<button class="btn btn-sm go" data-action="nav" data-view="${t.area}">${AREAS[t.area].icon}</button>` : ''}</div>`).join('');
  }

  function viewOverview() {
    const e = S.econ, b = S.budget, c = S.country;
    const tips = Engine.tips(S);
    const kpis = `<div class="kpis">
      ${kpi('👍 Zustimmung', F(S.approval, 1) + ' %', deltaTxt('approval'), 'approval', '#f5b942', STAT_INFO.approval.desc)}
      ${kpi('🏛️ Stabilität', F(S.stats.stability, 0), deltaTxt('stability'), 'stability', '#4da3ff', STAT_INFO.stability.desc)}
      ${kpi('📈 Wachstum', F(e.growth, 1) + ' %', deltaTxt('growth', 2), 'growth', '#3ecf8e', STAT_INFO.growth.desc)}
      ${kpi('👷 Arbeitslosigkeit', F(e.unemployment, 1) + ' %', deltaTxt('unemployment', 1, true), 'unemployment', '#ff8a5c', STAT_INFO.unemployment.desc)}
      ${kpi('🏷️ Inflation', F(e.inflation, 1) + ' %', deltaTxt('inflation', 1, true), 'inflation', '#c58cff', STAT_INFO.inflation.desc)}
      ${kpi('🧾 Schulden', F(e.debt, 0) + ' %', `Rating <b>${Engine.creditRating(S)}</b>`, 'debt', '#ff5d6c', STAT_INFO.debt.desc)}
      ${kpi('🏭 BIP', FM(e.gdp), `${F(e.gdp * 1e9 / (c.pop * 1e6), 0)} $ pro Kopf`, 'gdp', '#6cb8ff', 'Bruttoinlandsprodukt – die gesamte Wirtschaftsleistung pro Jahr.')}
    </div>`;
    const groups = Object.keys(GROUPS).map(g => barRow(`${GROUPS[g].icon} ${GROUPS[g].name}`, S.groups[g],
      { before: prev?.groups[g], tip: `<b>${GROUPS[g].name}</b> (${Math.round(GROUPS[g].weight * 100)} % der Wähler)<br>Wichtig: ${GROUPS[g].likes}` })).join('');
    const qual = ['education', 'health', 'security', 'environment', 'welfare', 'military', 'reputation', 'corruption'].map(k =>
      barRow(`${STAT_INFO[k].icon} ${STAT_INFO[k].name}`, S.stats[k], { inv: STAT_INFO[k].invert, mark: c.stats[k], before: prev?.stats[k], tip: `<b>${STAT_INFO[k].name}</b><br>${STAT_INFO[k].desc}<br><i>Strich = Startwert</i>` })).join('')
      + barRow(`${STAT_INFO.capacity.icon} ${STAT_INFO.capacity.name}`, S.capacity, { mark: c.capacity, tip: `<b>${STAT_INFO.capacity.name}</b><br>${STAT_INFO.capacity.desc}` })
      + barRow(`${STAT_INFO.terror.icon} ${STAT_INFO.terror.name}`, S.terror, { inv: true, tip: `<b>${STAT_INFO.terror.name}</b><br>${STAT_INFO.terror.desc}` });
    const mods = S.mods.slice(0, 6).map(m => `<div class="bs-line"><span>⏳ ${LABELS[m.key] || m.key} ${FS(m.value, 1)}</span><span class="muted">${m.months} Mon.</span></div>`).join('');
    const war = S.wars.map(w => { const o = Engine.byId(w.enemy); return `<div class="tip danger"><span class="ti">⚔️</span><span>Krieg gegen ${flag(o.id)} <b>${esc(o.name)}</b> – Frontverlauf ${FS(w.progress, 0)}</span><button class="btn btn-sm go" data-action="nav" data-view="militaer">→</button></div>`; }).join('');
    const pols = Object.keys(S.policies).length;
    const news = S.news.slice(0, 6).map(n => `<div class="news-item ${n.type}"><span class="when">${Engine.dateStr(S, n.month)}</span><span class="txt">${esc(n.text)}</span></div>`).join('');
    return `
      <div class="view-head"><h2>🧭 Lagezentrum</h2><span class="sub">Willkommen, ${esc(S.leader.title)} ${esc(S.leader.name)}. Hier ist die Lage der Nation.</span></div>
      ${kpis}
      <div class="grid g-main">
        <div class="panel"><div class="panel-title">🌍 Weltlage <span class="right muted">Klicke auf ein Land für Diplomatie</span></div>
          <div class="map-wrap"><canvas data-map="1"></canvas></div>${mapLegend()}</div>
        <div class="panel"><div class="panel-title">🧑‍💼 Deine Berater</div>${war}${adviceList(tips, 6)}</div>
      </div>
      <div class="grid g3" style="margin-top:14px">
        <div class="panel"><div class="panel-title">👥 Bevölkerungsgruppen <span class="right muted">Zufriedenheit</span></div>${groups}</div>
        <div class="panel"><div class="panel-title">📋 Lage der Nation</div>${qual}</div>
        <div class="panel"><div class="panel-title">📌 Aktuelles</div>
          <div class="bs-line"><span>📜 Aktive Gesetze</span><span>${pols}</span></div>
          <div class="bs-line"><span>💰 Haushaltssaldo</span><span class="${b.balance >= 0 ? 'good' : 'bad'}">${FS(b.balance, 1)} % (${FM(b.balance * e.gdp / 100)})</span></div>
          <div class="bs-line"><span>🏦 Zinssatz</span><span>${F(b.rate, 1)} %</span></div>
          <div class="bs-line"><span>🛢️ Ölpreis</span><span>${F(S.oil * 100, 0)} %</span></div>
          <div class="bs-line"><span>🌐 Weltkonjunktur</span><span class="${S.global > 0.3 ? 'good' : S.global < -0.3 ? 'bad' : ''}">${S.global > 0.3 ? 'Boom' : S.global < -0.3 ? 'Schwach' : 'Normal'}</span></div>
          ${mods ? '<div class="panel-title" style="margin-top:12px">⏳ Zeitlich begrenzte Effekte</div>' + mods : ''}
          <div class="panel-title" style="margin-top:12px">📰 Letzte Meldungen</div>${news}
        </div>
      </div>`;
  }

  // ─────────────────────────── Ansicht: Haushalt ───────────────────────────
  function viewBudget() {
    if (!draft) draft = { taxes: { ...S.taxes }, spending: { ...S.spending } };
    const taxRows = Object.keys(TAX_INFO).map(k => sliderRow('tax', k, TAX_INFO[k], draft.taxes[k], S.taxes[k], TAX_INFO[k].min, TAX_INFO[k].max, 0.5)).join('');
    const spRows = Object.keys(SPEND_INFO).map(k => sliderRow('spend', k, SPEND_INFO[k], draft.spending[k], S.spending[k], 0, SPEND_INFO[k].max, 0.1)).join('');
    return `
      <div class="view-head"><h2>💰 Staatshaushalt</h2><span class="sub">Lege Steuern und Ausgaben fest. Alle Werte in % des BIP (${FM(S.econ.gdp)}).</span></div>
      ${advisorBlock('wirtschaft', Engine.tips(S).filter(t => t.area === 'wirtschaft' && /Defizit|Zinsen|Überschuss|Inflation/.test(t.text)), 'Ein ausgeglichener Haushalt hält die Zinsen niedrig. Kleine Defizite sind okay, solange die Wirtschaft wächst.')}
      <div class="budget-layout" style="margin-top:14px">
        <div>
          <div class="panel"><div class="panel-title">🧾 Steuern <span class="right muted">Einnahmen</span></div>${taxRows}</div>
          <div class="panel" style="margin-top:14px"><div class="panel-title">🏗️ Ausgaben <span class="right muted">pro Jahr</span></div>${spRows}</div>
        </div>
        <div class="panel budget-summary" id="budget-summary">${budgetSummary()}</div>
      </div>`;
  }

  function sliderRow(kind, k, info, val, cur, min, max, step) {
    return `<div class="slider-row">
      <div><div class="sl-name">${info.icon} ${info.name}</div><div class="sl-hint">${info.hint}</div></div>
      <input type="range" min="${min}" max="${max}" step="${step}" value="${val}" data-budget="${kind}:${k}">
      <div class="sl-val" id="sv-${kind}-${k}">${sliderVal(kind, k, val, cur)}</div></div>`;
  }
  function sliderVal(kind, k, val, cur) {
    const changed = Math.abs(val - cur) > 0.001;
    let amount;
    if (kind === 'tax') {
      const b = Engine.computeBudget(S, draft.taxes, draft.spending);
      amount = FM(b.taxItems[k] * S.econ.gdp / 100);
    } else amount = FM(val * S.econ.gdp / 100);
    return `<b class="${changed ? 'changed' : ''}">${F(val, 1)} %</b>${changed ? ` <span class="muted" style="font-size:11px">(${FS(val - cur, 1)})</span>` : ''}<small>${amount}</small>`;
  }

  function budgetSummary() {
    const b = Engine.computeBudget(S, draft.taxes, draft.spending);
    const cur = S.budget;
    const cost = Engine.budgetChangeCost(S, draft.taxes, draft.spending);
    const gdp = S.econ.gdp;
    const line = (l, v, cls = '') => `<div class="bs-line ${cls}"><span>${l}</span><span>${F(v, 1)} % <span class="muted">· ${FM(v * gdp / 100)}</span></span></div>`;
    const preview = budgetPreview();
    return `<div class="panel-title">📊 Haushaltsübersicht</div>
      ${line('Steuereinnahmen', b.taxRevenue)}
      ${line('Sonstige Einnahmen', b.otherRevenue, 'sub')}
      ${b.oilRevenue ? line('Öl-Effekt', b.oilRevenue, 'sub') : ''}
      ${line('Einnahmen gesamt', b.revenue, 'total')}
      <div style="height:8px"></div>
      ${line('Ressorts', b.spendSum)}
      ${line('Verwaltung', b.admin, 'sub')}
      ${line('Gesetze & Programme', b.policyCost, 'sub')}
      ${b.warCost ? line('Kriegskosten', b.warCost, 'sub') : ''}
      ${line(`Zinsen (${F(b.rate, 1)} %)`, b.interest, 'sub')}
      ${line('Ausgaben gesamt', b.expenses, 'total')}
      <div class="balance-big ${b.balance >= 0 ? 'pos' : 'neg'}"><div class="muted" style="font-size:12px">${b.balance >= 0 ? 'Überschuss' : 'Defizit'} pro Jahr</div>
        <div class="v">${FS(b.balance, 2)} %</div><div style="font-size:12.5px">${FM(b.balance * gdp / 100)}</div>
        ${Math.abs(b.balance - cur.balance) > 0.005 ? `<div class="muted" style="font-size:12px">aktuell: ${FS(cur.balance, 2)} %</div>` : ''}</div>
      ${preview ? `<div class="panel-title">🔮 Erwartete Wirkung</div><div class="chips" style="margin-bottom:12px">${preview}</div>` : ''}
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button class="btn btn-primary" data-action="budget-apply" ${cost === 0 || cost > S.capital ? 'disabled' : ''} style="flex:1">Beschließen${cost ? ` (${cost} ⚡)` : ''}</button>
        <button class="btn" data-action="budget-reset" ${cost === 0 ? 'disabled' : ''}>Zurücksetzen</button>
      </div>
      <button class="btn btn-sm" data-action="budget-balance" style="width:100%;margin-top:8px" data-tip="Deine Finanzministerin schlägt einen Haushalt mit höchstens 1 % Defizit vor.">💡 Vorschlag: Haushalt ausgleichen</button>
      ${cost > S.capital ? `<p class="bad" style="font-size:12px;margin:8px 0 0">Nicht genug politisches Kapital (${F(S.capital, 0)} ⚡).</p>` : ''}
      <p class="muted" style="font-size:12px;margin:10px 0 0">Größere Änderungen kosten mehr politisches Kapital. Die Wirkung entfaltet sich über mehrere Monate.</p>`;
  }

  function budgetPreview() {
    const out = [];
    const T = k => draft.taxes[k] - S.taxes[k], P = k => draft.spending[k] - S.spending[k];
    const g = -T('income') * 0.035 - T('corporate') * 0.05 - T('vat') * 0.04 + P('infrastructure') * 0.3;
    if (Math.abs(g) > 0.02) out.push(signedChip('Wachstum', g, false, 2, ' %'));
    if (Math.abs(T('vat')) > 0.01) out.push(signedChip('Inflation', T('vat') * 0.05, true, 2, ' %'));
    const st = { education: P('education') * 7, health: P('health') * 4, security: P('police') * 12, environment: P('environment') * 12, military: P('military') * 7, welfare: P('social') * 2.5 };
    for (const k in st) if (Math.abs(st[k]) >= 0.5) out.push(signedChip(LABELS[k], st[k], false, 0));
    const grp = {
      workers: -T('income') * 0.7 - T('vat') * 0.6 + P('social') * 2.5 * 0.4, business: -T('corporate') * 1.2 - T('income') * 0.3,
      retirees: P('health') * 4 * 0.5 + P('social') * 2.5 * 0.4 - T('vat') * 0.4, youth: P('education') * 7 * 0.5 - T('income') * 0.3 + P('environment') * 12 * 0.3,
      military: P('military') * 10 + P('military') * 7 * 0.3, greens: P('environment') * 12 * 0.9 + P('environment') * 10,
      conservatives: P('police') * 12 * 0.5 - T('income') * 0.3 - T('vat') * 0.2,
    };
    for (const k in grp) if (Math.abs(grp[k]) >= 0.5) out.push(signedChip(GROUPS[k].icon + ' ' + GROUPS[k].name, grp[k], false, 0));
    return out.join('');
  }

  function balanceProposal() {
    const target = Math.max(-1, S.budget.balance);
    let b = Engine.computeBudget(S, draft.taxes, draft.spending);
    let need = target - b.balance;
    if (need <= 0.01) { toast('Der Haushalt ist bereits solide. 👍', 'good'); return; }
    // Hälfte über Mehrwertsteuer, Hälfte über proportionale Ausgabenkürzung
    const vatUp = Math.min(TAX_INFO.vat.max - draft.taxes.vat, need * 0.5 / 0.38);
    draft.taxes.vat = Math.round((draft.taxes.vat + vatUp) * 2) / 2;
    b = Engine.computeBudget(S, draft.taxes, draft.spending);
    need = target - b.balance;
    if (need > 0) {
      const factor = Math.max(0.6, 1 - need / b.spendSum);
      for (const k in draft.spending) draft.spending[k] = Math.round(draft.spending[k] * factor * 10) / 10;
    }
    renderView();
    toast('Vorschlag eingetragen – prüfe ihn und klicke auf „Beschließen“.', 'info');
  }

  // ─────────────────────────── Ansicht: Fachbereiche ───────────────────────────
  function advisorBlock(area, tips, idle) {
    const a = AREAS[area];
    const body = tips.length ? adviceList(tips, 4) : `<div>${esc(idle || ADVISOR_IDLE[area])}</div>`;
    return `<div class="panel advisor"><div class="avatar">${a.avatar}</div><div class="bubble"><div class="who"><b>${a.advisor}</b> · ${a.role}</div>${body}</div></div>`;
  }

  function viewArea(area) {
    const a = AREAS[area];
    const tips = Engine.tips(S).filter(t => t.area === area);
    const actions = ACTIONS.filter(x => x.area === area).map(actionCard).join('');
    const recs = Engine.recommendedPolicies(S, area, 2);
    const rank = p => (p.id in S.policies) ? 0 : recs.includes(p.id) ? 1 : Engine.canEnact(S, p.id).ok ? 2 : 3;
    const pols = POLICIES.filter(p => p.area === area).sort((x, y) => rank(x) - rank(y)).map(p => policyCard(p, recs.includes(p.id))).join('');
    const active = POLICIES.filter(p => p.area === area && (p.id in S.policies)).length;
    return `
      <div class="view-head"><h2>${a.icon} ${a.name}</h2><span class="sub">${areaSub(area)}</span></div>
      ${advisorBlock(area, tips)}
      ${areaPanel(area)}
      <div class="section-title">⚡ Sofortmaßnahmen <span class="count">Einmalige Entscheidungen mit sofortiger Wirkung</span></div>
      <div class="cards">${actions}</div>
      <div class="section-title">📜 Gesetze <span class="count">${active} aktiv · wirken dauerhaft, solange sie gelten</span></div>
      <div class="cards">${pols}</div>`;
  }

  function areaSub(area) {
    return { wirtschaft: 'Wachstum, Jobs und Preise – die Basis von allem.', soziales: 'Bildung, Gesundheit, Soziales und Umwelt.',
      militaer: 'Armee, innere Sicherheit und Kriege.', politik: 'Macht, Medien, Korruption und Wahlen.' }[area];
  }

  function areaPanel(area) {
    const e = S.econ, st = S.stats, c = S.country;
    if (area === 'wirtschaft') return `<div class="kpis" style="margin-top:14px">
      ${kpi('📈 Wachstum', F(e.growth, 1) + ' %', `Potenzial ${F(c.potential, 1)} %`, 'growth', '#3ecf8e', STAT_INFO.growth.desc)}
      ${kpi('👷 Arbeitslosigkeit', F(e.unemployment, 1) + ' %', deltaTxt('unemployment', 1, true), 'unemployment', '#ff8a5c', STAT_INFO.unemployment.desc)}
      ${kpi('🏷️ Inflation', F(e.inflation, 1) + ' %', `Ziel ≈ ${F(c.inflBase, 0)} %`, 'inflation', '#c58cff', STAT_INFO.inflation.desc)}
      ${kpi('💰 Haushalt', FS(S.budget.balance, 1) + ' %', 'des BIP', 'balance', '#f5b942', 'Haushaltssaldo pro Jahr.')}
      ${kpi('🤝 Handelsabkommen', Object.values(S.trade).filter(Boolean).length, 'Partnerländer', null, null, 'Jedes Handelsabkommen steigert das Wachstum.')}
    </div>`;
    if (area === 'soziales') return `<div class="panel" style="margin-top:14px"><div class="grid g2">
      <div>${['education', 'health', 'welfare'].map(k => barRow(`${STAT_INFO[k].icon} ${STAT_INFO[k].name}`, st[k], { mark: c.stats[k], before: prev?.stats[k], tip: STAT_INFO[k].desc })).join('')}</div>
      <div>${['environment', 'security'].map(k => barRow(`${STAT_INFO[k].icon} ${STAT_INFO[k].name}`, st[k], { mark: c.stats[k], before: prev?.stats[k], tip: STAT_INFO[k].desc })).join('')}
        ${['retirees', 'youth', 'greens'].map(g => barRow(`${GROUPS[g].icon} ${GROUPS[g].name}`, S.groups[g], { before: prev?.groups[g], tip: 'Wichtig: ' + GROUPS[g].likes })).join('')}</div>
    </div></div>`;
    if (area === 'militaer') return warPanel();
    if (area === 'politik') {
      const demo = c.gov === 'demokratie', toE = S.nextElection - S.month;
      const final = S.mode === 'klassisch' && S.terms >= 3;
      const est = Engine.clamp(S.approval * 0.85 + 9 + S.campaign, 0, 100);
      return `<div class="grid g2" style="margin-top:14px">
        <div class="panel"><div class="panel-title">${demo ? '🗳️ Nächste Wahl' : '🏛️ Nächste Machtprobe'}</div>
          <div style="font-size:30px;font-weight:800;font-family:var(--mono)">${toE} <span style="font-size:15px" class="muted">Monate</span></div>
          <div class="muted">${final ? 'Deine letzte Amtszeit – danach endet das Spiel mit deiner Bilanz.' : demo ? `Geschätztes Wahlergebnis heute: <b class="${est >= 50 ? 'good' : 'bad'}">${F(est, 1)} %</b> (50 % nötig)` : 'Du brauchst Stabilität ≥ 30 und ein zufriedenes Militär (≥ 30).'}</div>
          <div class="bs-line" style="margin-top:8px"><span>Amtszeit</span><span>${S.terms}${S.mode === 'klassisch' ? ' / 3' : ''}</span></div>
          <div class="bs-line"><span>Korruption</span><span class="${st.corruption > 50 ? 'bad' : 'good'}">${F(st.corruption, 0)}</span></div>
          <div class="bs-line"><span>Stabilität</span><span>${F(st.stability, 0)}</span></div></div>
        <div class="panel"><div class="panel-title">👥 Bevölkerungsgruppen</div>${Object.keys(GROUPS).map(g => barRow(`${GROUPS[g].icon} ${GROUPS[g].name}`, S.groups[g], { before: prev?.groups[g], tip: 'Wichtig: ' + GROUPS[g].likes })).join('')}</div>
      </div>`;
    }
    return '';
  }

  function opRow(icon, name, desc, btn) {
    return `<div class="dip-act"><span style="font-size:20px">${icon}</span><div class="t"><b>${name}</b><small>${desc}</small></div>${btn}</div>`;
  }

  function warPanel() {
    const my = Engine.militaryPower(S);
    const c = S.country;
    const rows = Object.keys(S.relations).sort((a, b) => S.relations[a] - S.relations[b]).slice(0, 4).map(id => {
      const o = Engine.byId(id), p = Engine.enemyPower(id), odds = my / (my + p);
      return `<div class="bs-line" data-tip="Kräfteverhältnis: Unter 40 % ist ein Krieg aussichtslos, über 60 % gut gewinnbar."><span>${flag(id)} ${esc(o.name)} <span class="muted">(Beziehung ${F(S.relations[id], 0)})</span></span>
        <span class="${odds < 0.4 ? 'bad' : odds < 0.55 ? 'warn' : 'good'}">${F(p, 0)}${o.nuclear ? ' ☢️' : ''} · ${F(odds * 100, 0)} %</span></div>`;
    }).join('');

    // ── Aktiver Krieg ──
    let war = '';
    if (S.wars.length) {
      const w = S.wars[0], o = Engine.byId(w.enemy), p = Engine.enemyPower(w.enemy, w), odds = Engine.warOdds(S, w.enemy);
      const pos = (w.progress + 100) / 2;
      const acts = Object.entries(Engine.WAR_ACTIONS).map(([k, a]) => {
        const cd = (S.cooldowns['war:' + k] || 0) - S.month;
        const dis = cd > 0 || S.capital < a.cost || (a.minSize && c.milSize < a.minSize);
        return `<button class="btn btn-sm" data-action="war-act" data-key="${k}" ${dis ? 'disabled' : ''} data-tip="${esc(a.desc)}${a.money ? ' · Kosten ' + moneyText(a.money) : ''}">${a.icon} ${a.name} (${a.cost} ⚡)${cd > 0 ? ' · ' + cd + ' Mon.' : ''}</button>`;
      }).join('');
      const nuke = S.nukes > 0 ? `<div class="panel" style="margin-top:12px;border-color:rgba(255,93,108,.6);background:rgba(255,93,108,.06)">
          <div class="panel-title" style="color:var(--bad)">☢️ Atomare Optionen <span class="right muted">Arsenal: ~${F(S.nukes, 0)} Sprengköpfe</span></div>
          <p class="muted" style="font-size:12.5px;margin:0 0 10px">${o.nuclear ? `<b class="bad">${esc(o.name)} ist selbst Atommacht.</b> Ein Atomschlag führt fast sicher zum nuklearen Gegenschlag – und damit zum Ende.` : 'Ein Atomschlag beendet den Krieg sofort – aber dein Land wird weltweit geächtet: Sanktionen, zerbrochene Bündnisse, Wirtschaftseinbruch und Massenproteste.'}</p>
          <div style="display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn btn-sm" data-action="nuke-threat" ${S.capital < 20 || (S.cooldowns.nukeThreat || 0) > S.month ? 'disabled' : ''} data-tip="Drohung mit Atomwaffen: Der Gegner lenkt vielleicht ein. Ansehen −12, alle Beziehungen −8.">⚠️ Nukleare Drohung (20 ⚡)</button>
            <button class="btn btn-sm btn-danger" data-action="nuke-strike">☢️ Atomschlag befehlen</button>
          </div></div>` : '';
      war = `<div class="panel war-panel" style="margin-top:14px"><div class="panel-title">⚔️ Krieg gegen ${flag(o.id)} ${esc(o.name)} <span class="right">${w.months} Monate</span></div>
        <div class="power-cmp"><div><div class="muted">Wir</div><div class="p good">${F(my, 0)}</div></div><div><div class="muted">Kräfteverhältnis</div><div class="${odds < 0.4 ? 'bad' : odds < 0.55 ? 'warn' : 'good'}" style="font-size:18px;font-weight:800">${F(odds * 100, 0)} %</div></div><div><div class="muted">${esc(o.name)}</div><div class="p bad">${F(p, 0)}${o.nuclear ? ' ☢️' : ''}</div></div></div>
        <div class="war-track"><i style="left:0;width:${pos}%;background:linear-gradient(90deg,#1d6b4a,var(--good))"></i><i style="left:${pos}%;right:0;background:linear-gradient(90deg,var(--bad),#6b1d26)"></i></div>
        <div style="display:flex;justify-content:space-between" class="muted"><span>◀ Niederlage</span><b class="${w.progress >= 0 ? 'good' : 'bad'}">Frontverlauf ${FS(w.progress, 0)}</b><span>Sieg ▶</span></div>
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:12px">${acts}
          <button class="btn btn-sm btn-good" data-action="dip-act" data-id="${o.id}" data-key="frieden" ${S.capital < 10 ? 'disabled' : ''}>🕊️ Frieden anbieten (10 ⚡)</button></div>
        ${w.attrition ? `<p class="muted" style="font-size:12px;margin:8px 0 0">Feind geschwächt durch Blockade/Sabotage: −${F(w.attrition * 100, 0)} % Kampfkraft</p>` : ''}
        <p class="muted" style="font-size:12px;margin:8px 0 0">Bei +100 gewinnst du, bei −100 musst du kapitulieren. Der Gegner mobilisiert jeden Monat weiter. Offensiven wirken nur bei gutem Kräfteverhältnis.</p>
        ${nuke}</div>`;
    }

    // ── Streitkräfte & Mobilisierung ──
    const lvl = Engine.READINESS_LEVELS.map(l => `<button class="${S.readinessTarget === l.value ? 'active' : ''}" data-action="readiness" data-v="${l.value}" data-tip="<b>${l.name}</b><br>${l.desc}<br>Kosten: ${F(Math.max(0, l.value - 25) * 0.035, 2)} % BIP/Jahr<br>Kampfkraft ×${F(0.5 + l.value / 100, 2)}">${l.name.split(' ')[0]}</button>`).join('');
    const nukeLine = S.nukes > 0 ? `☢️ ~${F(S.nukes, 0)} Sprengköpfe` : S.nukeProgram ? `<span class="warn">Programm läuft – fertig in ${S.nukeProgram - S.month} Mon.</span>` : '<span class="muted">keine</span>';
    const forces = `<div class="panel"><div class="panel-title">🛡️ Streitkräfte & Mobilisierung</div>
        ${barRow('🛡️ Militärstärke', S.stats.military, { mark: c.stats.military, before: prev?.stats.military, tip: STAT_INFO.military.desc })}
        ${barRow('📯 Kriegsbereitschaft', S.readiness, { mark: S.readinessTarget, tip: 'Wie kriegsbereit deine Armee ist. Steigt nur langsam (ca. 4 pro Monat) – Vorbereitung braucht Zeit! Strich = Zielwert.' })}
        ${barRow('🎖️ Zufriedenheit Militär', S.groups.military, { before: prev?.groups.military, tip: 'Unter 15 droht ein Putsch, wenn auch die Stabilität niedrig ist!' })}
        <div class="form-row" style="margin:10px 0"><label>Bereitschaftsstufe (Erhöhen 5 ⚡, Senken 2 ⚡)</label><div class="seg">${lvl}</div></div>
        <div class="bs-line"><span>Kampfkraft (inkl. Verbündete)</span><b>${F(my, 0)}</b></div>
        <div class="bs-line"><span>Verteidigungsbudget</span><span>${F(S.spending.military, 1)} % BIP</span></div>
        <div class="bs-line"><span>Atomwaffen</span><span>${nukeLine}</span></div></div>`;

    // ── Spezialeinheit ──
    const target = Engine.byId(Engine.sfTarget(S));
    const ops = Object.entries(Engine.SF_OPS).map(([k, a]) => {
      const cd = (S.cooldowns['sf:' + k] || 0) - S.month;
      const dis = cd > 0 || S.capital < a.cost || (a.war && !S.wars.length);
      const chance = a.base !== undefined ? ` · Erfolgschance <b>${F(Engine.sfChance(S, a.base) * 100, 0)} %</b>` : '';
      const extra = k === 'festnahme' ? ` · Ziel vermutet in ${flag(target.id)} ${esc(target.name)}` : '';
      return opRow(a.icon, a.name, `${esc(a.desc)}${chance}${extra}${cd > 0 ? ` · <span class="warn">bereit in ${cd} Mon.</span>` : ''}`,
        `<button class="btn btn-sm btn-primary" data-action="sf-op" data-key="${k}" ${dis ? 'disabled' : ''}>${a.cost} ⚡</button>`);
    }).join('');
    const sf = `<div class="panel"><div class="panel-title">🥷 Spezialeinheit: ${esc(c.sf.name)} <span class="right muted">${S.sf.success}/${S.sf.missions} Einsätze erfolgreich</span></div>
        ${barRow('🥷 Einsatzqualität', S.sf.quality, { mark: c.sf.quality, tip: 'Bestimmt die Erfolgschance aller Kommandoeinsätze. Steigt durch Training, das Gesetz „Spezialkräfte ausbauen“ und ein höheres Verteidigungsbudget.' })}
        ${barRow('💣 Terrorgefahr', S.terror, { inv: true, tip: STAT_INFO.terror.desc })}
        <div class="dip-actions" style="margin-top:10px">${ops}</div></div>`;

    return `${war}<div class="grid g2" style="margin-top:14px">${forces}${sf}</div>
      <div class="panel" style="margin-top:14px"><div class="panel-title">🎯 Mögliche Gegner <span class="right muted">Kampfkraft · unser Kräfteverhältnis</span></div>${rows}
        <p class="muted" style="font-size:12px;margin:8px 0 0">Krieg erklären kannst du in der Diplomatie (nur bei Beziehung ≤ −40). Bereite dich vor: Verteidigungsbudget erhöhen, mobilisieren, Verbündete gewinnen – das dauert Monate bis Jahre.</p></div>`;
  }

  function actionCard(a) {
    const chk = Engine.canDoAction(S, a.id);
    return `<div class="card ${chk.ok ? '' : 'locked'}">
      <div class="card-head"><div class="ico">${a.icon}</div><div><h4>${esc(a.name)}</h4></div></div>
      <div class="desc">${esc(a.desc)}</div>
      ${effectChips(a.effects)}
      <div class="card-foot"><span class="cost">${a.cost} ⚡</span><span class="why">${chk.ok ? `Abklingzeit ${a.cooldown} Mon.` : esc(chk.why)}</span>
        <button class="btn btn-sm btn-primary" data-action="do-action" data-id="${a.id}" ${chk.ok ? '' : 'disabled'}>Ausführen</button></div>
    </div>`;
  }

  function policyCard(p, isRec) {
    const active = !!(p.id in S.policies);
    const chk = Engine.canEnact(S, p.id);
    const rc = Engine.repealCost(p);
    const foot = active
      ? `<span class="cost">${rc} ⚡</span><span class="why">seit ${Engine.dateStr(S, S.policies[p.id])}</span><button class="btn btn-sm btn-danger" data-action="repeal" data-id="${p.id}" ${S.capital < rc ? 'disabled' : ''}>Aufheben</button>`
      : `<span class="cost">${p.cost} ⚡</span><span class="why">${chk.ok ? '' : esc(chk.why)}</span><button class="btn btn-sm btn-good" data-action="enact" data-id="${p.id}" ${chk.ok ? '' : 'disabled'}>Beschließen</button>`;
    return `<div class="card ${active ? 'active' : isRec ? 'recommended' : chk.ok ? '' : 'locked'}">
      <div class="card-head"><div class="ico">${p.icon}</div><div>${active ? '<div class="tag">✔ In Kraft</div>' : isRec ? '<div class="tag rec">⭐ Berater-Empfehlung</div>' : ''}<h4>${esc(p.name)}</h4></div></div>
      <div class="desc">${esc(p.desc)}</div>
      ${policyChips(p)}
      <div class="hint">💡 ${esc(p.advice)}</div>
      <div class="card-foot">${foot}</div>
    </div>`;
  }

  // ─────────────────────────── Ansicht: Diplomatie ───────────────────────────
  function relColor(r) {
    if (r >= 0) { const t = r / 100; return `rgb(${Math.round(150 - 90 * t)},${Math.round(160 + 47 * t)},${Math.round(185 - 43 * t)})`; }
    const t = -r / 100; return `rgb(${Math.round(150 + 105 * t)},${Math.round(160 - 67 * t)},${Math.round(185 - 77 * t)})`;
  }
  function relWord(r) { return r >= 70 ? 'Enger Freund' : r >= 40 ? 'Freundlich' : r >= 10 ? 'Positiv' : r > -10 ? 'Neutral' : r > -40 ? 'Angespannt' : r > -70 ? 'Feindselig' : 'Erzfeind'; }
  function relBar(r) {
    const w = Math.abs(r) / 2;
    return `<div class="rel-bar"><i style="${r >= 0 ? 'left:50%' : `left:${50 - w}%`};width:${w}%;background:${relColor(r)}"></i></div>`;
  }
  function mapLegend() {
    return `<div class="map-legend"><span><i style="background:var(--gold)"></i>Dein Land</span><span><i style="background:${relColor(80)}"></i>Freunde</span>
      <span><i style="background:${relColor(0)}"></i>Neutral</span><span><i style="background:${relColor(-80)}"></i>Feinde</span><span><i style="background:#ff2040"></i>Krieg</span></div>`;
  }

  function viewDiplomacy() {
    const ids = Object.keys(S.relations).sort((a, b) => S.relations[b] - S.relations[a]);
    if (!selCountry || !S.relations[selCountry] && S.relations[selCountry] !== 0) selCountry = ids[0];
    const list = ids.map(id => {
      const o = Engine.byId(id), r = S.relations[id];
      const badges = (S.trade[id] ? '📜' : '') + (S.alliance[id] ? '🤝' : '') + (S.sanctions[id] ? '🚫' : '') + (Engine.atWarWith(S, id) ? '⚔️' : '');
      return `<div class="dip-row ${id === selCountry ? 'sel' : ''}" data-action="dip-select" data-id="${id}">${flag(id)}<span>${esc(o.name)}</span>${relBar(r)}<span class="badges">${badges || '<span class="muted">' + F(r, 0) + '</span>'}</span></div>`;
    }).join('');
    const tips = Engine.tips(S).filter(t => t.area === 'diplomatie');
    return `
      <div class="view-head"><h2>🌍 Diplomatie</h2><span class="sub">Beziehungen, Handel, Bündnisse – und im Notfall Krieg.</span></div>
      ${advisorBlock('diplomatie', tips)}
      <div class="dip-layout" style="margin-top:14px">
        <div>
          <div class="panel"><div class="panel-title">🗺️ Weltkarte</div><div class="map-wrap"><canvas data-map="1"></canvas></div>${mapLegend()}</div>
          <div class="panel" style="margin-top:14px"><div class="panel-title">🏳️ Länder <span class="right muted">📜 Handel · 🤝 Bündnis · 🚫 Sanktion · ⚔️ Krieg</span></div><div class="dip-list">${list}</div></div>
        </div>
        <div class="panel" id="dip-detail">${dipDetail(selCountry)}</div>
      </div>`;
  }

  function dipDetail(id) {
    const o = Engine.byId(id), r = S.relations[id];
    const odds = Engine.warOdds(S, id);
    const opts = Engine.dipOptions(S, id).map(a => `
      <div class="dip-act"><span style="font-size:20px">${a.icon}</span><div class="t"><b>${a.name}</b><small>${esc(a.desc)}${a.money ? ' · Kosten ' + moneyText(a.money) : ''}${a.key === 'krieg' ? ` · Kräfteverhältnis <b class="${odds < 0.4 ? 'bad' : odds < 0.55 ? 'warn' : 'good'}">${F(odds * 100, 0)} %</b>${o.nuclear ? ' · <b class="bad">Atommacht!</b>' : ''}` : ''}</small>${!a.ok ? `<small class="bad"> · ${esc(a.why)}</small>` : ''}</div>
        <button class="btn btn-sm ${a.key === 'krieg' ? 'btn-danger' : 'btn-primary'}" data-action="dip-act" data-id="${id}" data-key="${a.key}" ${a.ok ? '' : 'disabled'}>${a.cost ? a.cost + ' ⚡' : 'Los'}</button></div>`).join('');
    const tr = [S.trade[id] && '📜 Handelsabkommen', S.alliance[id] && '🤝 Bündnis', S.sanctions[id] && '🚫 Sanktionen', Engine.atWarWith(S, id) && '⚔️ Krieg'].filter(Boolean);
    const my = Engine.militaryPower(S), their = Engine.enemyPower(id);
    return `<div class="detail-head">${flag(id, 'flag flag-xl')}<div><h3>${esc(o.name)}</h3><div class="muted">${esc(o.capital)} · ${o.region} · ${o.gov === 'demokratie' ? 'Demokratie' : 'Autoritär'}</div></div></div>
      <div style="margin:14px 0 6px;display:flex;justify-content:space-between"><span>Beziehung: <b style="color:${relColor(r)}">${relWord(r)}</b></span><b style="font-family:var(--mono)">${FS(r, 0)}</b></div>
      ${relBar(r)}
      <div class="treaties" style="margin:12px 0">${tr.length ? tr.map(t => `<span class="treaty">${t}</span>`).join('') : '<span class="muted" style="font-size:12.5px">Keine Verträge</span>'}</div>
      <div class="kv-grid" style="margin-bottom:14px">
        <div><span>BIP</span><b>${FM(o.gdp)}</b></div><div><span>Einwohner</span><b>${F(o.pop, o.pop < 20 ? 1 : 0)} Mio.</b></div>
        <div><span>Kampfkraft</span><b class="${their > my ? 'bad' : 'good'}">${F(their, 0)}${o.nuclear ? ' ☢️' : ''}</b></div><div><span>Ansehen</span><b>${o.stats.reputation}</b></div>
      </div>
      <div class="panel-title">Aktionen <span class="right">⚡ ${F(S.capital, 0)} verfügbar</span></div>
      <div class="dip-actions">${opts}</div>`;
  }

  // ─────────────────────────── Ansicht: Statistik ───────────────────────────
  const CHARTS = {
    approval: { name: 'Zustimmung', color: '#f5b942', unit: '%', min: 0, max: 100, ref: 50 },
    stability: { name: 'Stabilität', color: '#4da3ff', min: 0, max: 100 },
    growth: { name: 'Wachstum', color: '#3ecf8e', unit: '%', ref: 0 },
    unemployment: { name: 'Arbeitslosigkeit', color: '#ff8a5c', unit: '%', min: 0 },
    inflation: { name: 'Inflation', color: '#c58cff', unit: '%', ref: 2 },
    debt: { name: 'Schulden', color: '#ff5d6c', unit: '%', min: 0 },
    balance: { name: 'Haushaltssaldo', color: '#ffd479', unit: '%', ref: 0 },
    gdp: { name: 'BIP (Mrd. $)', color: '#6cb8ff' },
    military: { name: 'Militärstärke', color: '#9aa7c7', min: 0, max: 100 },
  };
  function viewStats() {
    const tabs = Object.entries(CHARTS).map(([k, c]) => `<button class="btn btn-sm ${k === chartMetric ? 'active' : ''}" data-action="chart" data-m="${k}">${c.name}</button>`).join('');
    const smalls = ['approval', 'growth', 'unemployment', 'debt'].filter(k => k !== chartMetric).slice(0, 3)
      .map(k => `<div class="panel"><div class="panel-title">${CHARTS[k].name}</div><div class="chart-box mini-chart"><canvas data-chart="${k}"></canvas></div></div>`).join('');
    return `
      <div class="view-head"><h2>📊 Statistiken</h2><span class="sub">Die Entwicklung deines Landes seit Amtsantritt.</span></div>
      <div class="panel"><div class="chart-tabs">${tabs}</div><div class="chart-box"><canvas data-chart="${chartMetric}"></canvas></div></div>
      <div class="grid g3" style="margin-top:14px">${smalls}</div>`;
  }

  // ─────────────────────────── Ansicht: Nachrichten ───────────────────────────
  function viewNews() {
    const top = S.news.find(n => n.type === 'event' || n.type === 'bad' || n.type === 'good') || S.news[0];
    const others = S.news.filter(n => n !== top).slice(0, 6);
    const paperName = { DE: 'Hauptstadt-Kurier', AT: 'Wiener Morgenblatt', CH: 'Berner Tagblatt' }[S.countryId] || `${S.country.capital}er Zeitung`;
    const list = S.news.map(n => `<div class="news-item ${n.type}"><span class="when">${Engine.dateStr(S, n.month)}</span><span class="txt">${esc(n.text)}</span></div>`).join('');
    return `
      <div class="view-head"><h2>📰 Nachrichten</h2><span class="sub">Was das Land bewegt.</span></div>
      <div class="grid g-main">
        <div class="newspaper">
          <div class="np-name">${esc(paperName)}</div>
          <div class="np-date">${Engine.dateStr(S)} · Unabhängig seit 1848 · Preis: 2,50</div>
          <div class="np-head">${esc(top ? top.text : 'Ruhiger Monat im Regierungsviertel')}</div>
          <div class="np-cols">
            <p><b>Umfrage:</b> ${F(S.approval, 0)} % der Bürger sind mit der Arbeit von ${esc(S.leader.title)} ${esc(S.leader.name)} zufrieden.</p>
            <p><b>Wirtschaft:</b> Das Wachstum liegt bei ${F(S.econ.growth, 1)} %, die Arbeitslosigkeit bei ${F(S.econ.unemployment, 1)} % und die Inflation bei ${F(S.econ.inflation, 1)} %.</p>
            ${others.map(n => `<p>${esc(n.text)}</p>`).join('')}
          </div>
        </div>
        <div class="panel"><div class="panel-title">🗂️ Archiv</div><div style="max-height:560px;overflow-y:auto">${list}</div></div>
      </div>`;
  }

  // ─────────────────────────── Karte ───────────────────────────
  let mapDots = null;
  const keyToId = {};
  function prepMap() {
    if (mapDots) return;
    for (const id in WORLD_MAP.key) keyToId[WORLD_MAP.key[id]] = id;
    mapDots = [];
    WORLD_MAP.rows.forEach((row, y) => { for (let x = 0; x < row.length; x++) if (row[x] !== '.') mapDots.push({ x, y, ch: row[x] }); });
  }
  function fitCanvas(c) {
    const dpr = window.devicePixelRatio || 1, r = c.getBoundingClientRect();
    c.width = Math.max(1, Math.round(r.width * dpr)); c.height = Math.max(1, Math.round(r.height * dpr));
    const ctx = c.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { ctx, w: r.width, h: r.height };
  }
  function latLonToXY(lat, lon, w, h) {
    return [(lon + 180) / 360 * w, (WORLD_MAP.latTop - lat) / (WORLD_MAP.latTop - WORLD_MAP.latBottom) * h];
  }
  function drawMap(c, opts = {}) {
    prepMap();
    const { ctx, w, h } = fitCanvas(c);
    const cw = w / WORLD_MAP.width, chh = h / WORLD_MAP.height, rad = Math.max(0.8, Math.min(cw, chh) * 0.36);
    const t = opts.time || 0;
    for (const d of mapDots) {
      const id = keyToId[d.ch];
      let col = 'rgba(110,130,180,0.25)', r = rad;
      if (id) {
        if (opts.start) col = id === setupSel ? '#f5b942' : 'rgba(120,160,240,0.55)';
        else if (id === S.countryId) col = '#f5b942';
        else if (Engine.atWarWith(S, id)) col = `rgba(255,32,64,${0.65 + 0.35 * Math.sin(t / 200)})`;
        else col = relColor(S.relations[id]);
        if (!opts.start && id === selCountry && view === 'diplomatie') r = rad * 1.35;
      }
      ctx.fillStyle = col;
      ctx.beginPath(); ctx.arc((d.x + 0.5) * cw, (d.y + 0.5) * chh, r, 0, Math.PI * 2); ctx.fill();
    }
    // Hauptstadt-Marker
    if (!opts.start && S) {
      const [x, y] = latLonToXY(...COUNTRY_COORDS[S.countryId], w, h);
      ctx.strokeStyle = '#ffd479'; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.arc(x, y, 6, 0, Math.PI * 2); ctx.stroke();
      if (S.wars.length) for (const wr of S.wars) {
        const [ex, ey] = latLonToXY(...COUNTRY_COORDS[wr.enemy], w, h);
        ctx.strokeStyle = 'rgba(255,60,80,.8)'; ctx.setLineDash([4, 4]);
        ctx.beginPath(); ctx.moveTo(x, y); ctx.quadraticCurveTo((x + ex) / 2, Math.min(y, ey) - 40, ex, ey); ctx.stroke(); ctx.setLineDash([]);
      }
    }
    if (opts.pings) for (const p of opts.pings) {
      const [x, y] = latLonToXY(...COUNTRY_COORDS[p.id], w, h);
      const age = (t - p.t) / 2000;
      if (age < 0 || age > 1) continue;
      ctx.strokeStyle = `rgba(245,185,66,${1 - age})`; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(x, y, 4 + age * 30, 0, Math.PI * 2); ctx.stroke();
    }
  }
  function mapHit(c, ev) {
    prepMap();
    const r = c.getBoundingClientRect();
    const x = Math.floor((ev.clientX - r.left) / r.width * WORLD_MAP.width), y = Math.floor((ev.clientY - r.top) / r.height * WORLD_MAP.height);
    // kleine Toleranz für winzige Länder
    for (const [dx, dy] of [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const ch = (WORLD_MAP.rows[y + dy] || '')[x + dx];
      if (ch && keyToId[ch]) return keyToId[ch];
    }
    return null;
  }

  function startMapLoop() {
    const c = $('#start-map');
    const pings = [];
    let last = 0, lastDraw = -1e9;
    const loop = t => {
      if (t - last > 900) { pings.push({ id: pick(Object.keys(COUNTRY_COORDS)), t }); last = t; if (pings.length > 6) pings.shift(); }
      if (t - lastDraw > 40) { drawMap(c, { start: true, pings, time: t }); lastDraw = t; }
      startAnim = requestAnimationFrame(loop);
    };
    stopMapLoop();
    startAnim = requestAnimationFrame(loop);
  }
  function stopMapLoop() { if (startAnim) cancelAnimationFrame(startAnim); startAnim = null; }
  const pick = arr => arr[Math.floor(Math.random() * arr.length)];

  // ─────────────────────────── Diagramme ───────────────────────────
  function drawSpark(c, data, color) {
    if (!data || data.length < 2) return;
    const { ctx, w, h } = fitCanvas(c);
    const d = data.slice(-36), mn = Math.min(...d), mx = Math.max(...d), rng = mx - mn || 1;
    ctx.strokeStyle = color; ctx.lineWidth = 1.6; ctx.beginPath();
    d.forEach((v, i) => { const x = i / (d.length - 1) * w, y = h - 2 - (v - mn) / rng * (h - 4); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); });
    ctx.stroke();
  }

  function drawChart(c, key) {
    const cfg = CHARTS[key], data = S.history[key], months = S.history.month;
    const { ctx, w, h } = fitCanvas(c);
    const pad = { l: 46, r: 14, t: 12, b: 26 };
    let mn = cfg.min ?? Math.min(...data), mx = cfg.max ?? Math.max(...data);
    if (cfg.ref !== undefined) { mn = Math.min(mn, cfg.ref); mx = Math.max(mx, cfg.ref); }
    if (cfg.min === undefined || cfg.max === undefined) { const p = (mx - mn) * 0.12 || 1; if (cfg.min === undefined) mn -= p; if (cfg.max === undefined) mx += p; }
    const X = i => pad.l + (data.length < 2 ? 0 : i / (data.length - 1)) * (w - pad.l - pad.r);
    const Y = v => pad.t + (1 - (v - mn) / (mx - mn || 1)) * (h - pad.t - pad.b);
    ctx.font = '11px Segoe UI, system-ui, sans-serif'; ctx.fillStyle = '#8d99b8'; ctx.strokeStyle = 'rgba(160,180,230,.1)'; ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const v = mn + (mx - mn) * i / 4, y = Y(v);
      ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(w - pad.r, y); ctx.stroke();
      ctx.textAlign = 'right'; ctx.fillText(F(v, Math.abs(mx - mn) < 10 ? 1 : 0), pad.l - 6, y + 4);
    }
    ctx.textAlign = 'center';
    months.forEach((m, i) => { if (m % 12 === 0) { ctx.fillText(S.startYear + m / 12, X(i), h - 8); } });
    if (cfg.ref !== undefined) { ctx.strokeStyle = 'rgba(255,255,255,.35)'; ctx.setLineDash([5, 5]); ctx.beginPath(); ctx.moveTo(pad.l, Y(cfg.ref)); ctx.lineTo(w - pad.r, Y(cfg.ref)); ctx.stroke(); ctx.setLineDash([]); }
    // Wahltermine markieren
    ctx.strokeStyle = 'rgba(245,185,66,.25)';
    for (let m = 48; m <= months[months.length - 1]; m += 48) { const i = months.indexOf(m); if (i >= 0) { ctx.beginPath(); ctx.moveTo(X(i), pad.t); ctx.lineTo(X(i), h - pad.b); ctx.stroke(); } }
    if (data.length < 2) { ctx.fillStyle = '#8d99b8'; ctx.fillText('Noch keine Daten – spiele ein paar Monate.', w / 2, h / 2); return; }
    const grad = ctx.createLinearGradient(0, pad.t, 0, h - pad.b);
    grad.addColorStop(0, cfg.color + '55'); grad.addColorStop(1, cfg.color + '00');
    ctx.beginPath(); data.forEach((v, i) => i ? ctx.lineTo(X(i), Y(v)) : ctx.moveTo(X(i), Y(v)));
    ctx.lineTo(X(data.length - 1), h - pad.b); ctx.lineTo(X(0), h - pad.b); ctx.closePath(); ctx.fillStyle = grad; ctx.fill();
    ctx.beginPath(); data.forEach((v, i) => i ? ctx.lineTo(X(i), Y(v)) : ctx.moveTo(X(i), Y(v)));
    ctx.strokeStyle = cfg.color; ctx.lineWidth = 2.2; ctx.stroke();
    const lv = data[data.length - 1];
    ctx.fillStyle = cfg.color; ctx.beginPath(); ctx.arc(X(data.length - 1), Y(lv), 4, 0, Math.PI * 2); ctx.fill();
    ctx.textAlign = 'right'; ctx.font = 'bold 12px Segoe UI, system-ui, sans-serif';
    ctx.fillText(F(lv, key === 'gdp' ? 0 : 1) + (cfg.unit ? ' ' + cfg.unit : ''), w - pad.r, pad.t + 12);
  }

  // ─────────────────────────── Modals ───────────────────────────
  function openModal(html, opts = {}) {
    hideTip();
    $('#modal-root').innerHTML = `<div class="modal-bg" ${opts.closable ? 'data-action="modal-bg"' : ''}><div class="modal ${opts.wide ? 'modal-wide' : ''}">${html}</div></div>`;
    afterRender();
  }
  function closeModal() { $('#modal-root').innerHTML = ''; }

  const CAT_NAME = { wirtschaft: 'Wirtschaft', soziales: 'Gesellschaft', politik: 'Innenpolitik', militaer: 'Sicherheit', diplomatie: 'Außenpolitik', info: 'Meldung' };

  function showEvent(ev) {
    sfx(ev.type === 'election' ? 'event' : ev.choices.some(c => c.effects.war) ? 'war' : 'event');
    if (ev.type === 'election') return showElection(ev);
    const rec = ev.choices.length > 1 ? Engine.recommend(S, ev) : null;
    const spread = rec ? Math.max(...rec.scores) - Math.min(...rec.scores) : 0;
    const L = ev.land ? Engine.byId(ev.land) : null;
    const area = AREAS[ev.cat] || AREAS.politik;
    const choices = ev.choices.map((ch, i) => {
      const isRec = rec && spread > 1.5 && i === rec.best;
      return `<button class="choice ${isRec ? 'recommended' : ''}" data-action="choice" data-i="${i}">
        <div class="c-top"><span class="num">${i + 1}</span><span class="c-label">${esc(ch.label)}</span>${isRec ? '<span class="rec">⭐ Berater-Empfehlung</span>' : ''}</div>
        ${ch.desc ? `<div class="c-desc">${esc(ch.desc)}</div>` : ''}
        ${effectChips(ch.effects, ev.land)}
      </button>`;
    }).join('');
    const advice = rec && spread > 1.5 ? `<div class="advice-line">${area.avatar} <span><b>${area.advisor}:</b> „Ich würde zu <b>${esc(ev.choices[rec.best].label)}</b> raten – das bringt uns unterm Strich am meisten.“</span></div>` : '';
    openModal(`
      <div class="modal-head"><div class="big-ico">${ev.icon}</div><div><div class="cat">${CAT_NAME[ev.cat] || 'Ereignis'} · ${Engine.dateStr(S)}</div><h3>${esc(ev.title)}</h3></div>
        ${L ? `<div style="margin-left:auto">${flag(L.id, 'flag flag-lg')}</div>` : ''}</div>
      <div class="modal-body"><p class="story">${esc(ev.text)}</p><div class="choices">${choices}</div>${advice}</div>`);
  }

  function showElection(ev) {
    const r = ev.result;
    openModal(`
      <div class="modal-head"><div class="big-ico">🗳️</div><div><div class="cat">Wahlabend · ${Engine.dateStr(S)}</div><h3 class="${r.won ? 'good' : 'bad'}">${esc(ev.title)}</h3></div></div>
      <div class="modal-body"><p class="story">${esc(ev.text)}</p>
        <div class="vote-bars">
          <div class="vote-bar"><b>${esc(S.leader.name)}</b><div class="vb"><i data-w="${r.vote}" style="background:linear-gradient(90deg,#e8962a,var(--gold))"></i></div><span class="pct">${F(r.vote, 1)} %</span></div>
          <div class="vote-bar"><span>Opposition</span><div class="vb"><i data-w="${r.opp}" style="background:linear-gradient(90deg,#3b5ba8,#6c8fe0)"></i></div><span class="pct">${F(r.opp, 1)} %</span></div>
          <div class="vote-bar"><span class="muted">Sonstige</span><div class="vb"><i data-w="${r.others}" style="background:#4a536b"></i></div><span class="pct muted">${F(r.others, 1)} %</span></div>
        </div>
        <p class="muted" style="font-size:12.5px">Für eine weitere Amtszeit brauchst du mindestens 50 % der Stimmen.</p>
      </div>
      <div class="modal-foot"><button class="btn btn-primary" data-action="choice" data-i="0">${esc(ev.choices[0].label)}</button></div>`);
    sfx(r.won ? 'good' : 'bad');
  }

  function choose(i) {
    const msgs = Engine.resolveEvent(S, i);
    closeModal();
    sfx('click');
    msgs.forEach(m => toast(esc(m), m.startsWith('❌') ? 'bad' : m.startsWith('✅') ? 'good' : 'info', 4000));
    save();
    renderAll();
    processQueue();
  }

  function showHelp(first) {
    const steps = [
      ['Willkommen im Amt!', 'Du regierst ein echtes Land. Jeder Klick auf <b>„Nächster Monat“</b> (oder <kbd>Leertaste</kbd>) lässt einen Monat vergehen. Mit ⏩ läuft die Zeit automatisch.'],
      ['Zustimmung ist alles', 'Deine Zustimmung ergibt sich aus der Zufriedenheit von sieben <b>Bevölkerungsgruppen</b>. In Demokratien wird alle 4 Jahre gewählt – du brauchst 50 % der Stimmen.'],
      ['Politisches Kapital ⚡', 'Gesetze, Sofortmaßnahmen und Haushaltsänderungen kosten politisches Kapital. Es wächst jeden Monat – je beliebter du bist, desto schneller.'],
      ['Vier Politikfelder', '<b>Wirtschaft, Soziales, Militär und Politik</b> – jedes mit eigenen Gesetzen, Sofortmaßnahmen und einem Berater, der dir Tipps gibt. Grüne Chips sind gute, rote schlechte Folgen.'],
      ['Haushalt & Diplomatie', 'Im <b>Haushalt</b> legst du Steuern und Ausgaben fest – achte auf das Defizit! In der <b>Diplomatie</b> schließt du Handelsabkommen und Bündnisse.'],
      ['Militär & Kriege', 'Kriege brauchen <b>Vorbereitung</b>: Verteidigungsbudget, Kriegsbereitschaft (steigt nur langsam) und Verbündete. Achte auf das <b>Kräfteverhältnis</b> – Offensiven wirken nur, wenn du stärker bist. Deine <b>Spezialeinheit</b> bekämpft Terror. Atommächte lassen sich nicht einfach besiegen.'],
      ['Starke und schwache Staaten', 'Die <b>Staatskapazität</b> bestimmt, wie gut Reformen wirken. Ein Land wie Sudan kann sich nicht in wenigen Jahren in eine Schweiz verwandeln – Fortschritt braucht dort Jahrzehnte.'],
      ['Ereignisse', 'Krisen, Skandale und Chancen passieren zufällig. Deine Berater markieren die empfohlene Option mit ⭐ – du musst ihnen aber nicht folgen.'],
      ['Gefahren', 'Vorsicht vor <b>Revolution</b> (Stabilität &lt; 10), <b>Putsch</b> (unzufriedenes Militär), <b>Staatsbankrott</b> (zu hohe Schulden) und <b>Abwahl</b>. Rote Punkte in der Navigation warnen dich.'],
      ['Tastenkürzel', '<kbd>Leertaste</kbd> nächster Monat · <kbd>1</kbd>–<kbd>9</kbd> Bereiche wechseln · <kbd>1</kbd>–<kbd>4</kbd> Option im Ereignis wählen · <kbd>A</kbd> Automatik · <kbd>Esc</kbd> Menü schließen'],
    ];
    openModal(`
      <div class="modal-head"><div class="big-ico">📘</div><div><div class="cat">Anleitung</div><h3>${first ? 'Deine ersten Schritte als Staatsoberhaupt' : 'So funktioniert das Spiel'}</h3></div></div>
      <div class="modal-body"><div class="help-steps">${steps.map(([t, d], i) => `<div class="help-step"><div class="n">${i + 1}</div><div><b>${t}</b><p>${d}</p></div></div>`).join('')}</div></div>
      <div class="modal-foot"><button class="btn btn-primary" data-action="modal-close">${first ? 'Los geht’s!' : 'Schließen'}</button></div>`, { closable: true, wide: true });
  }

  function showMenu() {
    stopAuto();
    openModal(`
      <div class="modal-head"><div class="big-ico">☰</div><div><div class="cat">Menü</div><h3>Pause</h3></div></div>
      <div class="modal-body" style="display:flex;flex-direction:column;gap:10px">
        <button class="btn" data-action="modal-close">▶ Weiterspielen</button>
        <button class="btn" data-action="export">💾 Spielstand als Datei speichern</button>
        <button class="btn" data-action="import">📂 Spielstand laden</button>
        <button class="btn" data-action="help">❔ Anleitung</button>
        <button class="btn" data-action="toggle-sound">${prefs.sound ? '🔊 Ton: an' : '🔇 Ton: aus'}</button>
        <div class="form-row"><label>Tempo der Automatik</label><div class="seg">
          ${[[2600, 'Langsam'], [1600, 'Normal'], [800, 'Schnell']].map(([v, l]) => `<button class="${prefs.speed === v ? 'active' : ''}" data-action="speed" data-v="${v}">${l}</button>`).join('')}</div></div>
        <button class="btn btn-danger" data-action="to-menu">⏏ Zum Hauptmenü (Spiel wird automatisch gespeichert)</button>
      </div>`, { closable: true });
  }

  function showEnd() {
    const L = Engine.legacy(S), g = S.gameOver;
    showScreen('end');
    sfx(g.won ? 'good' : 'bad');
    $('#screen-end').innerHTML = `
      <canvas id="end-map" class="bg-map" style="opacity:.25"></canvas>
      <div class="end-card">
        <div class="end-ico">${g.icon}</div>
        <h1 class="${g.won ? 'good' : 'bad'}">${esc(g.title)}</h1>
        <p class="muted" style="font-size:15px">${esc(g.text)}</p>
        <div style="display:flex;align-items:center;justify-content:center;gap:10px;margin-top:10px">${flag(S.countryId, 'flag flag-lg')}<b>${esc(S.leader.title)} ${esc(S.leader.name)}</b> <span class="muted">· ${esc(S.country.name)} · ${Engine.dateStr(S, 0)} – ${Engine.dateStr(S)}</span></div>
        <div class="rank">${esc(L.rank)}</div>
        <div class="score">${L.score}</div><div class="muted">Vermächtnis-Punkte</div>
        <div class="end-stats">
          <div><b>${S.month}</b><small>Monate im Amt</small></div>
          <div><b>${F(L.avgAppr, 1)} %</b><small>Ø Zustimmung</small></div>
          <div><b class="${L.gdpGrowth >= 0 ? 'good' : 'bad'}">${FS(L.gdpGrowth, 1)} %</b><small>Wirtschaftswachstum</small></div>
          <div><b class="${L.debtChange <= 0 ? 'good' : 'bad'}">${FS(L.debtChange, 1)}</b><small>Schulden (Prozentpunkte)</small></div>
          <div><b class="${L.quality >= 0 ? 'good' : 'bad'}">${FS(L.quality, 0)}</b><small>Lebensqualität</small></div>
          <div><b>${Object.keys(S.policies).length}</b><small>Gesetze in Kraft</small></div>
        </div>
        <div class="panel" style="text-align:left;margin-bottom:18px"><div class="panel-title">Zustimmung im Verlauf</div><div class="chart-box mini-chart"><canvas data-chart="approval"></canvas></div></div>
        <div style="display:flex;gap:10px;justify-content:center;flex-wrap:wrap">
          ${g.won && S.mode === 'klassisch' ? '<button class="btn btn-good" data-action="end-continue">♾️ Weiterregieren (Endlosmodus)</button>' : ''}
          <button class="btn btn-primary" data-action="new-game">▶ Neues Spiel</button>
          <button class="btn" data-action="to-menu">Hauptmenü</button>
        </div>
      </div>`;
    drawMap($('#end-map'));
    document.querySelectorAll('#screen-end canvas[data-chart]').forEach(c => drawChart(c, c.dataset.chart));
  }

  function continueEndless() {
    S.gameOver = null; S.mode = 'endlos'; S.nextElection = S.month + TERM_MONTHS;
    Engine.addNews(S, 'Das Volk will mehr: Die Amtszeitbegrenzung wurde aufgehoben!', 'good');
    enterGame(); save();
  }

  // ─────────────────────────── Toasts & Tooltips ───────────────────────────
  function toast(html, type = 'info', ms = 3200, kind = '') {
    const root = $('#toast-root');
    if (kind) root.querySelectorAll(`.toast[data-kind="${kind}"]`).forEach(t => t.remove());
    const el = document.createElement('div');
    el.className = `toast ${type}`; el.innerHTML = html;
    if (kind) el.dataset.kind = kind;
    root.appendChild(el);
    while (root.children.length > 3) root.firstChild.remove();
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 300); }, ms);
  }

  function initTooltips() {
    const tip = $('#tooltip');
    document.addEventListener('mousemove', ev => {
      const t = ev.target.closest && ev.target.closest('[data-tip]');
      const canvas = ev.target.tagName === 'CANVAS' && ev.target.dataset.map !== undefined ? ev.target : null;
      let html = t && t.dataset.tip ? t.dataset.tip : '';
      if (canvas && S) {
        const id = mapHit(canvas, ev);
        if (id) {
          const o = Engine.byId(id);
          html = id === S.countryId ? `<b>${esc(o.name)}</b><br>Dein Land` :
            `<b>${esc(o.name)}</b><br>Beziehung: ${relWord(S.relations[id])} (${FS(S.relations[id], 0)})${S.trade[id] ? '<br>📜 Handelsabkommen' : ''}${S.alliance[id] ? '<br>🤝 Bündnis' : ''}${S.sanctions[id] ? '<br>🚫 Sanktionen' : ''}${Engine.atWarWith(S, id) ? '<br>⚔️ Krieg!' : ''}`;
        }
      }
      if (!html) { tip.classList.remove('show'); return; }
      tip.innerHTML = html;
      tip.classList.add('show');
      const r = tip.getBoundingClientRect();
      let x = ev.clientX + 14, y = ev.clientY + 16;
      if (x + r.width > innerWidth - 8) x = ev.clientX - r.width - 14;
      if (y + r.height > innerHeight - 8) y = ev.clientY - r.height - 12;
      tip.style.left = x + 'px'; tip.style.top = y + 'px';
    });
    document.addEventListener('mouseleave', () => tip.classList.remove('show'));
  }

  // ─────────────────────────── Eingaben ───────────────────────────
  function handleAction(el, ev) {
    const a = el.dataset.action, id = el.dataset.id;
    const result = (r, okMsg) => {
      if (!r.ok) { toast(esc(r.why), 'bad'); sfx('bad'); return; }
      sfx('good');
      if (okMsg) toast(okMsg, 'good');
      (r.msgs || []).forEach(m => toast(esc(m), m.startsWith('❌') ? 'bad' : 'good', 4000));
      save(); renderAll(); processQueue();
    };
    switch (a) {
      case 'new-game': setupFilter = 'Alle'; showSetup(); break;
      case 'continue': continueGame(); break;
      case 'import': $('#file-import').click(); break;
      case 'export': exportSave(); break;
      case 'help': showHelp(false); break;
      case 'back-start': initStart(); break;
      case 'setup-filter': setupFilter = el.dataset.f; showSetup(); break;
      case 'setup-select': setupOpts.name = $('#inp-name')?.value || setupOpts.name; setupOpts.title = $('#inp-title')?.value || setupOpts.title; setupSel = id; showSetup(); break;
      case 'setup-opt': setupOpts.name = $('#inp-name')?.value || setupOpts.name; setupOpts.title = $('#inp-title')?.value || setupOpts.title; setupOpts[el.dataset.k] = el.dataset.v; renderSetupDetail(); break;
      case 'start-game': startGame(); break;
      case 'nav': view = el.dataset.view; closeModal(); renderSidebar(); renderView(); break;
      case 'next': nextMonth(); break;
      case 'auto': toggleAuto(); break;
      case 'menu': showMenu(); break;
      case 'modal-close': closeModal(); break;
      case 'modal-bg': if (ev.target === el) closeModal(); break;
      case 'toggle-sound': prefs.sound = !prefs.sound; savePrefs(); showMenu(); break;
      case 'speed': prefs.speed = +el.dataset.v; savePrefs(); showMenu(); break;
      case 'to-menu': save(); closeModal(); stopAuto(); S = null; initStart(); break;
      case 'enact': { const p = Engine.policyById(id); result(Engine.enactPolicy(S, id), `📜 „${esc(p.name)}“ ist beschlossen!`); break; }
      case 'repeal': { const p = Engine.policyById(id); result(Engine.repealPolicy(S, id), `„${esc(p.name)}“ wurde aufgehoben.`); break; }
      case 'do-action': { const x = Engine.actionById(id); result(Engine.doAction(S, id), `${x.icon} ${esc(x.name)} durchgeführt.`); break; }
      case 'budget-apply': { const r = Engine.applyBudget(S, draft.taxes, draft.spending); if (r.ok) draft = null; result(r, `💰 Neuer Haushalt beschlossen (${r.cost} ⚡).`); break; }
      case 'budget-reset': draft = null; renderView(); break;
      case 'budget-balance': balanceProposal(); break;
      case 'dip-select': selCountry = id; renderView(); break;
      case 'dip-act': {
        if (el.dataset.key === 'krieg' && !confirm(`Willst du ${Engine.byId(id).name} wirklich den Krieg erklären?`)) return;
        const r = Engine.dipAction(S, id, el.dataset.key);
        if (r.ok) sfx(el.dataset.key === 'krieg' ? 'war' : 'good');
        if (r.ok) { toast(esc(r.msg), el.dataset.key === 'krieg' ? 'bad' : 'good'); save(); renderAll(); processQueue(); } else { toast(esc(r.why), 'bad'); }
        break;
      }
      case 'war-act': { const r = Engine.warAction(S, el.dataset.key); result(r); if (r.ok) toast(esc(r.msg), 'info'); break; }
      case 'readiness': { const r = Engine.setReadiness(S, +el.dataset.v); result(r); if (r.ok) toast(esc(r.msg), 'info', 4000); break; }
      case 'sf-op': { const r = Engine.sfOp(S, el.dataset.key); if (r.ok) toast(esc(r.msg), r.msg.startsWith('❌') ? 'bad' : 'good', 4500); result({ ok: r.ok, why: r.why }); break; }
      case 'nuke-threat': {
        if (!confirm('Mit Atomwaffen drohen? Das schadet deinem Ansehen und allen Beziehungen.')) return;
        const r = Engine.nuclearThreat(S); if (r.ok) toast(esc(r.msg), r.msg.startsWith('✅') ? 'good' : 'bad', 5000); result({ ok: r.ok, why: r.why }); break;
      }
      case 'nuke-strike': {
        const o = Engine.byId(S.wars[0].enemy);
        if (!confirm(`ATOMSCHLAG gegen ${o.name}?\n\nDeine Berater warnen eindringlich: ${o.nuclear ? 'Es droht ein nuklearer Gegenschlag und damit das Ende deines Landes.' : 'Dein Land wird weltweit geächtet – Sanktionen, Bündnisbruch, Wirtschaftseinbruch.'}`)) return;
        if (!confirm('Letzte Bestätigung: Diese Entscheidung kann nicht rückgängig gemacht werden.')) return;
        sfx('war');
        const r = Engine.nuclearStrike(S); result({ ok: r.ok, why: r.why }); break;
      }
      case 'chart': chartMetric = el.dataset.m; renderView(); break;
      case 'choice': choose(+el.dataset.i); break;
      case 'end-continue': continueEndless(); break;
    }
  }

  function init() {
    document.addEventListener('click', ev => {
      hideTip();
      const el = ev.target.closest('[data-action]');
      if (el && !el.disabled) handleAction(el, ev);
      const c = ev.target.tagName === 'CANVAS' && ev.target.dataset.map !== undefined ? ev.target : null;
      if (c && S) { const id = mapHit(c, ev); if (id && id !== S.countryId) { selCountry = id; view = 'diplomatie'; renderSidebar(); renderView(); } }
    });
    document.addEventListener('input', ev => {
      const t = ev.target;
      if (t.dataset && t.dataset.budget && draft) {
        const [kind, k] = t.dataset.budget.split(':');
        const v = +t.value;
        if (kind === 'tax') draft.taxes[k] = v; else draft.spending[k] = v;
        for (const kk in TAX_INFO) $(`#sv-tax-${kk}`).innerHTML = sliderVal('tax', kk, draft.taxes[kk], S.taxes[kk]);
        $(`#sv-spend-${k}`) && ($(`#sv-spend-${k}`).innerHTML = sliderVal('spend', k, draft.spending[k], S.spending[k]));
        $('#budget-summary').innerHTML = budgetSummary();
      }
    });
    $('#file-import').addEventListener('change', ev => { if (ev.target.files[0]) importSave(ev.target.files[0]); ev.target.value = ''; });
    document.addEventListener('keydown', ev => {
      if (ev.target.tagName === 'INPUT' || ev.target.tagName === 'SELECT') return;
      const screenGame = $('#screen-game').classList.contains('active');
      if (!screenGame || !S) return;
      const ch = $('#modal-root .choice[data-i]') ? [...document.querySelectorAll('#modal-root [data-action="choice"]')] : null;
      if (ch && ch.length) {
        const n = parseInt(ev.key, 10);
        if (n >= 1 && n <= ch.length) { ev.preventDefault(); choose(n - 1); }
        return;
      }
      if (modalOpen()) {
        if (ev.key === 'Escape') { const bg = $('#modal-root .modal-bg[data-action]'); if (bg) closeModal(); }
        if ((ev.key === 'Enter' || ev.key === ' ') && $('#modal-root [data-action="choice"]')) { ev.preventDefault(); choose(0); }
        return;
      }
      if (ev.key === ' ' || ev.key === 'Enter') { ev.preventDefault(); nextMonth(); }
      else if (ev.key === 'a' || ev.key === 'A') toggleAuto();
      else if (ev.key === 'Escape') showMenu();
      else { const n = parseInt(ev.key, 10); if (n >= 1 && n <= NAV.length) { view = NAV[n - 1].id; renderSidebar(); renderView(); } }
    });
    let rz;
    window.addEventListener('resize', () => { clearTimeout(rz); rz = setTimeout(() => { if (S && $('#screen-game').classList.contains('active')) afterRender(); }, 150); });
    initTooltips();
    initStart();
  }

  return { init, get state() { return S; } };
})();
