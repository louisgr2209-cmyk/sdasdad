// ════════════════════════════════════════════════════════════════════
//  Benutzeroberfläche
// ════════════════════════════════════════════════════════════════════
const UI = (() => {
  let S = null;                 // aktueller Spielzustand
  let view = 'overview';
  let selCountry = null;        // ausgewähltes Land in der Diplomatie
  let chartMetric = 'approval';
  let autoTimer = null;
  let prev = null;              // Werte vor dem letzten Monat (für Trends)
  let setupSel = 'DE', setupFilter = 'Alle';
  let dipTab = 'konflikte';
  let govFilter = 'alle';
  let selConflict = null;
  let mapMode = 'konflikte';
  const projAmt = {};
  let mapAnim = null;
  let neg = null; // laufende Vertragsverhandlung
  let setupOpts = { name: '', title: 'Präsident', difficulty: 'normal', mode: 'klassisch' };
  let startAnim = null;
  const prefs = loadPrefs();

  const $ = sel => document.querySelector(sel);
  const esc = str => String(str ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const F = Engine.fmt, FS = Engine.fmtSigned, FM = Engine.fmtMoney;
  const flag = (id, cls = 'flag') => `<img class="${cls}" src="assets/flags/${id.toLowerCase()}.svg" alt="${id}">`;
  const SAVE_KEY = 'praesident.save.v1';

  const NAV = [
    { id: 'overview', icon: '🧭', name: 'Übersicht' },
    { id: 'regierung', icon: '🏛️', name: 'Regierung' },
    { id: 'finanzen', icon: '💰', name: 'Finanzen' },
    { id: 'welt', icon: '🌍', name: 'Welt' },
    { id: 'militaer', icon: '🛡️', name: 'Militär' },
    { id: 'chronik', icon: '📊', name: 'Chronik' },
  ];
  const NAV_OF_AREA = { wirtschaft: 'regierung', soziales: 'regierung', politik: 'regierung', militaer: 'militaer', diplomatie: 'welt' };
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
    view = 'overview'; selCountry = null; prev = null;
    enterGame();
    save();
    if (!prefs.tutorialSeen) { prefs.tutorialSeen = true; savePrefs(); showHelp(true); }
  }
  function enterGame() {
    showScreen('game');
    startGameMapLoop();
    renderAll();
    processQueue();
  }
  function hasSave() { try { return !!localStorage.getItem(SAVE_KEY); } catch { return false; } }
  function save() { try { if (S && !S.gameOver) localStorage.setItem(SAVE_KEY, Engine.serialize(S)); } catch { } }
  function continueGame() {
    try { S = Engine.deserialize(localStorage.getItem(SAVE_KEY)); view = 'overview'; enterGame(); }
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
      try { S = Engine.deserialize(r.result); view = 'overview'; closeModal(); enterGame(); save(); toast('Spielstand geladen.', 'good'); }
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
    const cls = (v, inv) => Math.abs(v) < 0.05 ? 'muted' : (v > 0) !== !!inv ? 'good' : 'bad';
    const cab = (S.cabinet || []).slice(0, 3).map(c => `<div class="cab-line">${Engine.AUTO_AREAS[c.area]?.icon || '🧑‍💼'} ${esc(c.text)}</div>`).join('');
    const more = (S.cabinet || []).length > 3 ? `<div class="muted" style="font-size:12px">… und ${(S.cabinet.length - 3)} weitere Entscheidungen (Übersicht)</div>` : '';
    toast(`<div class="t-title">📅 ${Engine.dateStr(S)}</div><div class="month-sum">
      <span>Zustimmung</span><span class="${cls(r.approval)}">${FS(r.approval, 1)} %</span>
      <span>Staatskonto</span><span class="${cls(r.treasury)}">${r.treasury >= 0 ? '+' : '−'}${FM(Math.abs(r.treasury))}</span></div>
      ${cab ? `<div class="cab-box">${cab}${more}</div>` : ''}`, 'info', cab ? 4200 : 2200, 'month');
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
    const flow = (b.discretionary + Math.max(0, b.balance)) * S.econ.gdp / 1200;
    const stat = (cls, l, v, tip, nav) => `<div class="tb-stat ${cls}" data-tip="${esc(tip)}" ${nav ? `data-action="nav" data-view="${nav}"` : ''}><div class="l">${l}</div><div class="v">${v}</div></div>`;
    const apCls = S.approval >= 50 ? 'good' : S.approval >= 40 ? 'warn' : 'bad';
    const stCls = S.stats.stability >= 50 ? 'good' : S.stats.stability >= 30 ? 'warn' : 'bad';
    $('#topbar').innerHTML = `
      <div class="tb-country">${flag(S.countryId, 'flag flag-lg')}<div><div class="name">${esc(S.country.name)}</div><div class="leader">${esc(S.leader.title)} ${esc(S.leader.name)}</div></div></div>
      <div class="tb-date"><div class="d">${Engine.dateStr(S)}</div><div class="e ${toE <= 6 ? 'warn' : ''}">${elText}</div></div>
      <div class="tb-stats">
        ${stat('', '👍 Zustimmung', `<span class="${apCls}">${F(S.approval, 1)}<small>%</small></span>`, STAT_INFO.approval.desc)}
        ${stat('capital', '🏦 Staatskonto', `${FM(S.treasury)}`, `Dein frei verfügbares Geld. Pro Monat fließen ${FM(flow)} aus dem Verfügungsfonds und Überschüssen hinzu.`, 'finanzen')}
        ${stat('', '📈 Wachstum', `<span class="${S.econ.growth >= 1 ? 'good' : S.econ.growth >= 0 ? 'warn' : 'bad'}">${F(S.econ.growth, 1)}<small>%</small></span>`, STAT_INFO.growth.desc)}
        ${stat('', '🏛️ Stabilität', `<span class="${stCls}">${F(S.stats.stability, 0)}</span>`, STAT_INFO.stability.desc)}
      </div>
      <div class="tb-actions">
        <button class="btn btn-icon btn-auto ${autoTimer ? 'on' : ''}" data-action="auto" data-tip="Zeit automatisch laufen lassen. Pausiert bei wichtigen Ereignissen. <kbd>A</kbd>">${autoTimer ? '⏸' : '⏩'}</button>
        <button class="btn btn-primary btn-next" data-action="next" data-tip="Nächster Monat <kbd>Leertaste</kbd>">Nächster Monat ▶</button>
      </div>`;
  }

  function renderSidebar() {
    const tips = Engine.tips(S);
    const danger = new Set(tips.filter(t => t.level === 'danger').map(t => NAV_OF_AREA[t.area]));
    if (S.wars.length) danger.add('militaer');
    const autoOn = Object.values(S.auto || {}).filter(Boolean).length, autoAll = Object.keys(Engine.AUTO_AREAS).length;
    $('#sidebar').innerHTML = NAV.map((n, i) => `
      <div class="nav-item ${view === n.id ? 'active' : ''}" data-action="nav" data-view="${n.id}">
        <span class="ico">${n.icon}</span><span class="lbl">${n.name}</span><span class="key">${i + 1}</span>
        ${danger.has(n.id) ? '<span class="alert pulse"></span>' : ''}
      </div>`).join('') + `
      <div class="side-foot">
        <div class="auto-badge" data-action="nav" data-view="regierung" data-tip="Deine Minister kümmern sich automatisch um ihre Bereiche. Einstellbar unter Regierung.">🤖 <span class="lbl">Autopilot ${autoOn}/${autoAll}</span></div>
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
    const fn = { overview: viewOverview, regierung: viewGovernment, finanzen: viewFinance, welt: viewWorld, militaer: viewMilitary, chronik: viewChronik }[view] || viewOverview;
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

  function shortMoney(mrd) { return mrd >= 1000 ? F(mrd / 1000, 1) + ' Bio' : mrd >= 10 ? F(mrd, 0) + ' Mrd' : mrd >= 1 ? F(mrd, 1) + ' Mrd' : F(mrd * 1000, 0) + ' Mio'; }
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
    if (eff.money) out.push(chip((eff.money > 0 ? '💸 ' : '💰 +') + FM(Math.abs(eff.money) * S.econ.gdp / 100), eff.money > 0 ? 'bad' : 'good'));
    if (eff.capital) out.push(chip('💸 ' + FM(-eff.capital * 0.01 * S.econ.gdp / 100), 'bad'));
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
    if (eff.warEnd) out.push(chip({ sieg: '🏆 Sieg', frieden: '🕊️ Waffenstillstand', niederlage: '🏳️ Kapitulation' }[eff.warEnd], eff.warEnd === 'niederlage' ? 'bad' : 'good'));
    if (eff.nukeDamage) out.push(chip('☢️ Nuklearer Schaden', 'bad'));
    if (eff.doom) out.push(chip('💀 Atomkrieg – Spielende', 'bad'));
    if (eff.ostracize) out.push(chip('🌍 Weltweite Ächtung', 'bad'));
    if (eff.pact && L) out.push(chip(`🤞 Nichtangriffspakt mit ${L.name}`, 'good'));
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
    if (p.upkeep) out.push(chip((p.upkeep > 0 ? '💸 ' : '💰 +') + `${FM(Math.abs(p.upkeep) * S.econ.gdp / 100)}/Jahr`, p.upkeep > 0 ? 'bad' : 'good'));
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

  function mood(v) { return v >= 65 ? '😄' : v >= 50 ? '🙂' : v >= 35 ? '😐' : v >= 20 ? '🙁' : '😠'; }

  function viewOverview() {
    const e = S.econ, b = S.budget, c = S.country, st = S.stats;
    const toE = S.nextElection - S.month, demo = c.gov === 'demokratie';
    const est = Engine.clamp(S.approval * 0.85 + 9 + S.campaign, 0, 100);
    const lvl = (good, warn) => good ? 'good' : warn ? 'warn' : 'bad';
    const war = S.wars[0];
    const lights = [
      ['📈', 'Wirtschaft', lvl(e.growth >= c.potential - 0.3 && e.unemployment <= c.unemployment + 1, e.growth >= 0), `Wachstum ${F(e.growth, 1)} % · Arbeitslose ${F(e.unemployment, 1)} %`, 'regierung'],
      ['💰', 'Finanzen', lvl(b.balance >= -2, b.balance >= -5), `Konto ${FM(S.treasury)} · ${b.balance >= 0 ? 'Überschuss' : 'Defizit'} ${F(Math.abs(b.balance), 1)} %`, 'finanzen'],
      ['👥', 'Gesellschaft', lvl(S.approval >= 50 && st.stability >= 50, S.approval >= 38 && st.stability >= 30), `Zustimmung ${F(S.approval, 0)} % · Stabilität ${F(st.stability, 0)}`, 'regierung'],
      ['🛡️', 'Sicherheit', war ? 'bad' : lvl(S.terror < 40 && st.security >= 50, S.terror < 65), war ? `Krieg gegen ${Engine.byId(war.enemy).name} (Front ${FS(war.progress, 0)})` : `Terrorgefahr ${F(S.terror, 0)} · Sicherheit ${F(st.security, 0)}`, 'militaer'],
      ['🌍', 'Ausland', lvl(st.reputation >= 55, st.reputation >= 35), `Ansehen ${F(st.reputation, 0)} · ${S.conflicts.length} Krisenherde weltweit`, 'welt'],
      ['🗳️', demo ? 'Nächste Wahl' : 'Machtprobe', S.mode === 'klassisch' && S.terms >= 3 ? 'good' : demo ? lvl(est >= 53, est >= 48) : lvl(st.stability >= 45 && S.groups.military >= 40, st.stability >= 30 && S.groups.military >= 30),
        `in ${toE} Monaten · ${demo ? `Prognose ${F(est, 0)} %` : `Militär ${F(S.groups.military, 0)} %`}`, 'regierung'],
    ].map(([ic, name, l, txt, nav]) => `<div class="light ${l}" data-action="nav" data-view="${nav}"><span class="dot"></span><span class="li-ico">${ic}</span><div><b>${name}</b><small>${esc(txt)}</small></div></div>`).join('');
    const cab = (S.cabinet || []).length ? S.cabinet.map(x => `<div class="cab-line">${Engine.AUTO_AREAS[x.area]?.icon || '🧑‍💼'} ${esc(x.text)}</div>`).join('')
      : '<div class="muted" style="font-size:13px">Diesen Monat keine Entscheidungen. Schalte unter „Regierung“ den Autopiloten deiner Minister ein oder aus.</div>';
    const tips = Engine.tips(S).filter(t => t.level === 'danger' || t.level === 'warn').slice(0, 3);
    const important = tips.length ? adviceList(tips, 3) : '<div class="tip good"><span class="ti">✅</span><span>Keine akuten Probleme.</span></div>';
    const groups = Object.keys(GROUPS).map(g => `<div class="gpill" data-tip="<b>${GROUPS[g].name}</b> (${Math.round(GROUPS[g].weight * 100)} % der Wähler)<br>Wichtig: ${GROUPS[g].likes}">
      <span class="gi">${GROUPS[g].icon}</span><span class="gn">${GROUPS[g].name}</span><span class="gm">${mood(S.groups[g])}</span><span class="gv ${S.groups[g] >= 50 ? 'good' : S.groups[g] >= 35 ? 'warn' : 'bad'}">${F(S.groups[g], 0)}</span></div>`).join('');
    const confl = S.conflicts.slice().sort((a, b) => b.intensity - a.intensity).slice(0, 5).map(k => `<div class="conf-chip" data-action="conflict-open" data-id="${k.id}">
      <span>${k.type === 'war' ? '⚔️' : k.type === 'civil' ? '🔥' : '⚠️'}</span><span class="cn">${esc(k.name)}</span><span class="ci" style="--w:${k.intensity}%"></span></div>`).join('');
    return `
      <div class="view-head"><h2>🧭 Übersicht</h2><span class="sub">${esc(S.leader.title)} ${esc(S.leader.name)} · ${Engine.dateStr(S)}</span></div>
      <div class="grid g-main">
        <div class="panel">${mapPanelHead()}<div class="map-wrap"><canvas data-map="1"></canvas></div>${mapLegend()}
          ${confl ? `<div class="conf-row">${confl}</div>` : ''}</div>
        <div class="grid" style="align-content:start">
          <div class="panel"><div class="panel-title">🚦 Lage der Nation</div><div class="lights">${lights}</div></div>
          <div class="panel"><div class="panel-title">⚠️ Wichtig</div>${important}</div>
        </div>
      </div>
      <div class="grid g2" style="margin-top:14px">
        <div class="panel"><div class="panel-title">👥 Bevölkerung <span class="right muted">Zufriedenheit</span></div><div class="gpills">${groups}</div></div>
        <div class="panel"><div class="panel-title">🧑‍💼 Kabinettsbericht <span class="right muted">${Engine.dateStr(S)}</span></div><div class="cab-box">${cab}</div></div>
      </div>`;
  }

  // ─────────────────────────── Ansicht: Haushalt ───────────────────────────
  function viewFinance() {
    const b = S.budget, gdp = S.econ.gdp;
    const flow = (b.discretionary + Math.max(0, b.balance)) * gdp / 1200;
    const newDebt = Math.max(0, -b.balance) * gdp / 1200;
    const taxRows = Object.keys(TAX_INFO).map(k => sliderRow('tax', k, TAX_INFO[k], S.taxes[k], S.country.taxes[k], TAX_INFO[k].min, TAX_INFO[k].max, 0.5)).join('');
    const spRows = Object.keys(SPEND_INFO).map(k => sliderRow('spend', k, SPEND_INFO[k], S.spending[k], S.country.spending[k], 0, SPEND_INFO[k].max, 0.1)).join('');
    const fb = (op, label, amt, tip) => `<button class="btn btn-sm" data-action="fin" data-op="${op}" data-amt="${amt}" ${amt <= 0 ? 'disabled' : ''} data-tip="${esc(tip)}">${label}</button>`;
    const projects = Object.entries(Engine.PROJECTS).map(([id, p]) => {
      const x = projAmt[id] ?? 0.5;
      const seg = Engine.PROJECT_AMOUNTS.map(a => `<button class="${a === x ? 'active' : ''}" data-action="proj-amt" data-id="${id}" data-v="${a}">${shortMoney(a * gdp / 100)}</button>`).join('');
      const tired = Engine.recentUses(S, 'proj:' + id, 12);
      return `<div class="card compact">
        <div class="card-head"><div class="ico">${p.icon}</div><div><h4>${p.name}</h4>${tired ? `<div class="tag" style="color:var(--warn)">Wirkung ${Math.round(Engine.fatigue(S, 'proj:' + id, 12, 0.7) * 100)} % (kürzlich genutzt)</div>` : ''}</div></div>
        <div class="desc">${esc(p.desc)}</div>
        <div class="seg seg-sm">${seg}</div>
        ${effectChips(Engine.projectEffects(S, id, x))}
        <div class="card-foot"><span class="cost">${FM(x * gdp / 100)}</span><button class="btn btn-sm btn-primary" data-action="proj-run" data-id="${id}">Investieren</button></div></div>`;
    }).join('');
    return `
      <div class="view-head"><h2>💰 Finanzen</h2><span class="sub">Dein Staatskonto: Was übrig bleibt, landet hier – und du entscheidest, was damit passiert.</span></div>
      <div class="grid g2">
        <div class="panel konto">
          <div class="panel-title">🏦 Staatskonto</div>
          <div class="konto-big">${FM(S.treasury)}</div>
          <div class="konto-flow good">▲ +${FM(flow)} pro Monat${newDebt > 0 ? ` <span class="bad" style="margin-left:10px">· Neuverschuldung ${FM(newDebt)}/Monat</span>` : ''}</div>
          ${sliderRow('disc', 'x', { icon: '💼', name: 'Verfügungsfonds', hint: 'Anteil des Haushalts, der jedes Jahr auf dein Konto fließt' }, S.discretionary, 0.5, 0, 3, 0.1)}
          <div class="bs-line"><span>🧾 Staatsschulden</span><span>${F(S.econ.debt, 0)} % BIP · ${FM(S.econ.debt * gdp / 100)}</span></div>
          <div class="bs-line"><span>🏦 Zinsen pro Jahr</span><span>${FM(b.interest * gdp / 100)} (${F(b.rate, 1)} %)</span></div>
          <div class="bs-line"><span>📈 Staatsfonds</span><span>${FM(S.fund)} · Rendite ${FS(S.fundRate, 1)} %</span></div>
          <div class="bs-line"><span>⭐ Kreditrating</span><b>${Engine.creditRating(S)}</b></div>
          <div class="fin-actions">
            <div><label>Schulden tilgen</label>${fb('tilgen', '25 %', S.treasury * 0.25, 'Ein Viertel des Kontos in die Schuldentilgung')} ${fb('tilgen', '50 %', S.treasury * 0.5, 'Die Hälfte des Kontos')} ${fb('tilgen', 'Alles', S.treasury, 'Das ganze Konto')}</div>
            <div><label>Kredit aufnehmen</label>${fb('kredit', FM(gdp * 0.005), gdp * 0.005, 'Neue Schulden – das Geld landet sofort auf dem Konto')} ${fb('kredit', FM(gdp * 0.01), gdp * 0.01, '')} ${fb('kredit', FM(gdp * 0.03), gdp * 0.03, '')}</div>
            <div><label>Staatsfonds</label>${fb('fonds_ein', 'Hälfte anlegen', S.treasury * 0.5, 'Geld anlegen – bringt schwankende Rendite')} ${fb('fonds_aus', 'Alles abheben', S.fund, 'Fondsvermögen zurück aufs Konto')}</div>
          </div>
        </div>
        <div class="panel">
          <div class="panel-title">📊 Haushalt pro Jahr</div>
          <div class="bs-line"><span>Einnahmen</span><span>${FM(b.revenue * gdp / 100)}</span></div>
          <div class="bs-line"><span>Ausgaben</span><span>${FM(b.expenses * gdp / 100)}</span></div>
          <div class="bs-line sub"><span>davon Zinsen</span><span>${FM(b.interest * gdp / 100)}</span></div>
          <div class="bs-line sub"><span>davon Verfügungsfonds → dein Konto</span><span>${FM(b.discretionary * gdp / 100)}</span></div>
          <div class="bs-line sub"><span>davon Gesetze & Programme</span><span>${FM(b.policyCost * gdp / 100)}</span></div>
          ${b.warCost ? `<div class="bs-line sub"><span>davon Krieg, Mobilisierung, Missionen</span><span>${FM(b.warCost * gdp / 100)}</span></div>` : ''}
          <div class="balance-big ${b.balance >= 0 ? 'pos' : 'neg'}"><div class="muted" style="font-size:12px">${b.balance >= 0 ? 'Überschuss' : 'Defizit'} pro Jahr</div><div class="v">${FM(b.balance * gdp / 100)}</div><div style="font-size:12px">${FS(b.balance, 1)} % des BIP</div></div>
          ${autoToggle('finanzen')}
        </div>
      </div>
      <div class="section-title">🏗️ Sonderprojekte <span class="count">Investiere Geld vom Konto direkt dort, wo du willst</span></div>
      <div class="cards">${projects}</div>
      <details class="panel" style="margin-top:18px" ${S.auto.finanzen ? '' : 'open'}><summary class="panel-title" style="cursor:pointer;margin:0">⚙️ Steuern & Ausgaben im Detail <span class="right muted">Änderungen gelten sofort${S.auto.finanzen ? ' · Der Finanzminister passt sie automatisch an' : ''}</span></summary>
        <div class="grid g2" style="margin-top:12px"><div>${taxRows}</div><div>${spRows}</div></div>
      </details>`;
  }

  function autoToggle(key) {
    const a = Engine.AUTO_AREAS[key], on = !!S.auto[key];
    return `<button class="auto-toggle ${on ? 'on' : ''}" data-action="auto-toggle" data-k="${key}" data-tip="${esc(a.desc)}"><span class="sw"></span>${a.icon} ${a.name}: <b>${on ? 'Minister kümmert sich' : 'Du entscheidest'}</b></button>`;
  }

  function sliderRow(kind, k, info, val, start, min, max, step) {
    return `<div class="slider-row">
      <div><div class="sl-name">${info.icon} ${info.name}</div><div class="sl-hint">${info.hint}</div></div>
      <input type="range" min="${min}" max="${max}" step="${step}" value="${val}" data-budget="${kind}:${k}">
      <div class="sl-val" id="sv-${kind}-${k}">${sliderVal(kind, k, val, start)}</div></div>`;
  }

  function sliderVal(kind, k, val, start) {
    const amount = kind === 'tax' ? FM(S.budget.taxItems[k] * S.econ.gdp / 100) : FM(val * S.econ.gdp / 100);
    if (kind === 'disc') return `<b>${F(val, 1)} %</b><small>${amount}/Jahr</small>`;
    const d = val - start;
    return `<b>${F(val, 1)} %</b>${Math.abs(d) > 0.001 ? ` <span class="muted" style="font-size:11px">(Start ${FS(d, 1)})</span>` : ''}<small>${amount}/Jahr</small>`;
  }







  // ─────────────────────────── Ansicht: Fachbereiche ───────────────────────────
  function advisorBlock(area, tips, idle) {
    const a = AREAS[area];
    const body = tips.length ? adviceList(tips, 4) : `<div>${esc(idle || ADVISOR_IDLE[area])}</div>`;
    return `<div class="panel advisor"><div class="avatar">${a.avatar}</div><div class="bubble"><div class="who"><b>${a.advisor}</b> · ${a.role}</div>${body}</div></div>`;
  }

  function viewGovernment() {
    const filters = [['alle', 'Alle'], ['wirtschaft', '📈 Wirtschaft'], ['soziales', '🤝 Soziales'], ['militaer', '🛡️ Sicherheit'], ['politik', '🏛️ Politik']]
      .map(([k, l]) => `<button class="btn btn-sm ${govFilter === k ? 'active' : ''}" data-action="gov-filter" data-k="${k}">${l}</button>`).join('');
    const inArea = x => govFilter === 'alle' || x.area === govFilter;
    const actions = ACTIONS.filter(inArea).map(actionCard).join('');
    const recs = new Set(['wirtschaft', 'soziales', 'militaer', 'politik'].flatMap(a => Engine.recommendedPolicies(S, a, 1)));
    const rank = p => (p.id in S.policies) ? 0 : recs.has(p.id) ? 1 : Engine.canEnact(S, p.id).ok ? 2 : 3;
    const pols = POLICIES.filter(inArea).sort((x, y) => rank(x) - rank(y)).map(p => policyCard(p, recs.has(p.id))).join('');
    const activeCount = POLICIES.filter(p => inArea(p) && (p.id in S.policies)).length;
    const toggles = Object.keys(Engine.AUTO_AREAS).map(autoToggle).join('');
    return `
      <div class="view-head"><h2>🏛️ Regierung</h2><span class="sub">Entscheide selbst – oder lass deine Minister arbeiten.</span></div>
      <div class="panel"><div class="panel-title">🤖 Minister-Autopilot <span class="right"><button class="btn btn-sm" data-action="auto-all" data-v="1">Alle an</button> <button class="btn btn-sm" data-action="auto-all" data-v="0">Alle aus</button></span></div>
        <div class="auto-grid">${toggles}</div>
        <p class="muted" style="font-size:12px;margin:10px 0 0">Eingeschaltete Minister beschließen sinnvolle Gesetze, halten den Haushalt im Rahmen und entscheiden kleine Ereignisse. Was sie getan haben, steht im Kabinettsbericht. Große Entscheidungen (Kriege, Wahlen, Krisen) triffst immer du.</p></div>
      <div class="chart-tabs" style="margin-top:16px">${filters}</div>
      <div class="section-title">⚡ Sofortmaßnahmen <span class="count">sofort wirksam · bezahlt vom Staatskonto · Wiederholungen wirken schwächer</span></div>
      <div class="cards">${actions || '<span class="muted">Keine Maßnahmen in diesem Bereich.</span>'}</div>
      <div class="section-title">📜 Gesetze <span class="count">${activeCount} in Kraft · wirken dauerhaft</span></div>
      <div class="cards">${pols}</div>`;
  }

  function viewMilitary() {
    const tips = Engine.tips(S).filter(t => t.area === 'militaer');
    return `
      <div class="view-head"><h2>🛡️ Militär</h2><span class="sub">Streitkräfte, Spezialeinheit, Kriege.</span></div>
      ${tips.length ? advisorBlock('militaer', tips) : ''}
      <div style="margin-top:4px">${autoToggle('militaer')}</div>
      ${warPanel()}`;
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
        <span class="${odds < 0.4 ? 'bad' : odds < 0.55 ? 'warn' : 'good'}">${F(p, 0)}${Engine.hasNukes(S, o.id) ? ' ☢️' : ''} · ${F(odds * 100, 0)} %</span></div>`;
    }).join('');

    // ── Aktiver Krieg ──
    let war = '';
    if (S.wars.length) {
      const w = S.wars[0], o = Engine.byId(w.enemy), p = Engine.enemyPower(w.enemy, w), odds = Engine.warOdds(S, w.enemy);
      const pos = (w.progress + 100) / 2;
      const acts = Object.entries(Engine.WAR_ACTIONS).map(([k, a]) => {
        const dis = !!(a.minSize && c.milSize < a.minSize);
        return `<button class="btn btn-sm" data-action="war-act" data-key="${k}" ${dis ? 'disabled' : ''} data-tip="${esc(a.desc)}${a.money ? ' · Kosten ' + moneyText(a.money) : ''}">${a.icon} ${a.name}${a.money ? ' · ' + FM(a.money * S.econ.gdp / 100) : ''}</button>`;
      }).join('');
      const nuke = S.nukes > 0 ? `<div class="panel" style="margin-top:12px;border-color:rgba(255,93,108,.6);background:rgba(255,93,108,.06)">
          <div class="panel-title" style="color:var(--bad)">☢️ Atomare Optionen <span class="right muted">Arsenal: ~${F(S.nukes, 0)} Sprengköpfe</span></div>
          <p class="muted" style="font-size:12.5px;margin:0 0 10px">${Engine.hasNukes(S, o.id) ? `<b class="bad">${esc(o.name)} ist selbst Atommacht.</b> Ein Atomschlag löst eine nukleare Krise aus – nur mit kühlem Kopf (Deeskalation, UN-Vermittlung) lässt sich ein Atomkrieg noch verhindern.` : 'Ein Atomschlag beendet den Krieg sofort – aber dein Land wird weltweit geächtet: Sanktionen, zerbrochene Bündnisse, Wirtschaftseinbruch und Massenproteste.'}</p>
          <div style="display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn btn-sm" data-action="nuke-threat" data-tip="Drohung mit Atomwaffen: Der Gegner lenkt vielleicht ein. Ansehen −12, alle Beziehungen −8.">⚠️ Nukleare Drohung</button>
            <button class="btn btn-sm btn-danger" data-action="nuke-strike">☢️ Atomschlag befehlen</button>
          </div></div>` : '';
      war = `<div class="panel war-panel" style="margin-top:14px"><div class="panel-title">⚔️ Krieg gegen ${flag(o.id)} ${esc(o.name)} <span class="right">${w.months} Monate</span></div>
        <div class="power-cmp"><div><div class="muted">Wir</div><div class="p good">${F(my, 0)}</div></div><div><div class="muted">Kräfteverhältnis</div><div class="${odds < 0.4 ? 'bad' : odds < 0.55 ? 'warn' : 'good'}" style="font-size:18px;font-weight:800">${F(odds * 100, 0)} %</div></div><div><div class="muted">${esc(o.name)}</div><div class="p bad">${F(p, 0)}${Engine.hasNukes(S, o.id) ? ' ☢️' : ''}</div></div></div>
        <div class="war-track"><i style="left:0;width:${pos}%;background:linear-gradient(90deg,#1d6b4a,var(--good))"></i><i style="left:${pos}%;right:0;background:linear-gradient(90deg,var(--bad),#6b1d26)"></i></div>
        <div style="display:flex;justify-content:space-between" class="muted"><span>◀ Niederlage</span><b class="${w.progress >= 0 ? 'good' : 'bad'}">Frontverlauf ${FS(w.progress, 0)}</b><span>Sieg ▶</span></div>
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:12px">${acts}
          <button class="btn btn-sm btn-good" data-action="dip-act" data-id="${o.id}" data-key="frieden">🕊️ Frieden anbieten</button></div>
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
        <div class="form-row" style="margin:10px 0"><label>Bereitschaftsstufe</label><div class="seg">${lvl}</div></div>
        <div class="bs-line"><span>Kampfkraft (inkl. Verbündete)</span><b>${F(my, 0)}</b></div>
        <div class="bs-line"><span>Verteidigungsbudget</span><span>${F(S.spending.military, 1)} % BIP</span></div>
        <div class="bs-line"><span>Atomwaffen</span><span>${nukeLine}</span></div></div>`;

    // ── Spezialeinheit ──
    const target = Engine.byId(Engine.sfTarget(S));
    const ops = Object.entries(Engine.SF_OPS).map(([k, a]) => {
      const dis = !!(a.war && !S.wars.length);
      const chance = a.base !== undefined ? ` · Erfolgschance <b>${F(Engine.sfChance(S, a.base) * 100, 0)} %</b>` : '';
      const extra = k === 'festnahme' ? ` · Ziel vermutet in ${flag(target.id)} ${esc(target.name)}` : '';
      return opRow(a.icon, a.name, `${esc(a.desc)}${chance}${extra}`,
        `<button class="btn btn-sm btn-primary" data-action="sf-op" data-key="${k}" ${dis ? 'disabled' : ''}>Los</button>`);
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
    const f = Engine.fatigue(S, 'act:' + a.id, a.cooldown);
    const money = a.effects.money || 0;
    return `<div class="card compact ${chk.ok ? '' : 'locked'}" data-tip="${esc(a.desc)}">
      <div class="card-head"><div class="ico">${a.icon}</div><div><h4>${esc(a.name)}</h4>${f < 1 ? `<div class="tag" style="color:var(--warn)">Wirkung ${Math.round(f * 100)} % (kürzlich genutzt)</div>` : ''}</div></div>
      ${effectChips(a.effects)}
      <div class="card-foot"><span class="cost">${money > 0 ? FM(money * S.econ.gdp / 100) : money < 0 ? '+' + FM(-money * S.econ.gdp / 100) : 'kostenlos'}</span><span class="why">${chk.ok ? '' : esc(chk.why)}</span>
        <button class="btn btn-sm btn-primary" data-action="do-action" data-id="${a.id}" ${chk.ok ? '' : 'disabled'}>Ausführen</button></div>
    </div>`;
  }

  function policyCard(p, isRec) {
    const active = p.id in S.policies;
    const chk = Engine.canEnact(S, p.id);
    const impl = Engine.implCost(p) * S.econ.gdp / 100;
    const foot = active
      ? `<span class="why">seit ${Engine.dateStr(S, S.policies[p.id])}</span><button class="btn btn-sm btn-danger" data-action="repeal" data-id="${p.id}">Aufheben</button>`
      : `<span class="cost" data-tip="Einmalige Einführungskosten">${FM(impl)}</span><span class="why">${chk.ok ? '' : esc(chk.why)}</span><button class="btn btn-sm btn-good" data-action="enact" data-id="${p.id}" ${chk.ok ? '' : 'disabled'}>Beschließen</button>`;
    return `<div class="card compact ${active ? 'active' : isRec ? 'recommended' : chk.ok ? '' : 'locked'}" data-tip="${esc(p.desc)}<br><br>💡 ${esc(p.advice)}">
      <div class="card-head"><div class="ico">${p.icon}</div><div>${active ? '<div class="tag">✔ In Kraft</div>' : isRec ? '<div class="tag rec">⭐ Empfohlen</div>' : ''}<h4>${esc(p.name)}</h4></div></div>
      ${policyChips(p)}
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
    if (mapMode === 'buendnisse') return `<div class="map-legend"><span><i style="background:var(--gold)"></i>Dein Land / dein Bündnis</span><span><i style="background:#4da3ff"></i>NATO</span><span><i style="background:#9db9ff"></i>EU</span><span><i style="background:#ff7a59"></i>BRICS</span><span><i style="background:#2ec4b6"></i>Pazifik / USMCA</span><span>— Linien: unsere Bündnisse</span></div>`;
    if (mapMode === 'beziehungen') return `<div class="map-legend"><span><i style="background:var(--gold)"></i>Dein Land</span><span><i style="background:${relColor(80)}"></i>Freunde</span>
      <span><i style="background:${relColor(0)}"></i>Neutral</span><span><i style="background:${relColor(-80)}"></i>Feinde</span><span><i style="background:#ff2040"></i>Krieg</span></div>`;
    return `<div class="map-legend"><span><i style="background:var(--gold)"></i>Dein Land</span><span><i style="background:#ff4d5e"></i>Krieg</span><span><i style="background:#ff9f43"></i>Bürgerkrieg</span><span>⚠️ Krisenherd (Größe = Intensität)</span><span>🪖 Friedenstruppe</span><span>Klicke auf Marker oder Länder</span></div>`;
  }

  function mapPanelHead() {
    const modes = [['konflikte', '⚔️ Konflikte'], ['beziehungen', '🤝 Beziehungen'], ['buendnisse', '🛡️ Bündnisse']]
      .map(([k, l]) => `<button class="${mapMode === k ? 'active' : ''}" data-action="map-mode" data-k="${k}">${l}</button>`).join('');
    return `<div class="panel-title">🌍 Weltlage <span class="right"><span class="seg seg-sm">${modes}</span></span></div>`;
  }

  function viewWorld() {
    const tips = Engine.tips(S).filter(t => t.area === 'diplomatie');
    const tabs = [['konflikte', `⚔️ Konflikte (${S.conflicts.length})`], ['laender', '🏳️ Länder & Verträge'], ['buendnisse', '🤝 Bündnisse'], ['abruestung', '☮️ Abrüstung']]
      .map(([k, l]) => `<button class="btn ${dipTab === k ? 'active' : ''}" data-action="dip-tab" data-t="${k}">${l}</button>`).join('');
    const body = dipTab === 'buendnisse' ? viewBlocs() : dipTab === 'abruestung' ? viewDisarm() : dipTab === 'laender' ? viewCountries() : viewConflicts();
    return `
      <div class="view-head"><h2>🌍 Welt</h2><span class="sub">Konflikte, Verträge, Bündnisse – klicke auf die Karte.</span></div>
      <div class="panel">${mapPanelHead()}<div class="map-wrap"><canvas data-map="1"></canvas></div>${mapLegend()}</div>
      ${tips.length ? `<div style="margin-top:14px">${advisorBlock('diplomatie', tips)}</div>` : ''}
      <div style="margin-top:14px">${autoToggle('diplomatie')}</div>
      <div class="chart-tabs" style="margin-top:14px">${tabs}</div>
      ${body}`;
  }

  function conflictIcon(k) { return k.type === 'war' ? '⚔️' : k.type === 'civil' ? '🔥' : '⚠️'; }
  function conflictKind(k) { return k.type === 'war' ? 'Krieg zwischen Staaten' : k.type === 'civil' ? 'Bürgerkrieg' : Engine.HOTSPOTS[k.key].kind; }

  function viewConflicts() {
    if (!S.conflicts.length) return '<div class="panel"><div class="tip good"><span class="ti">🕊️</span><span>Die Welt ist gerade friedlich. Kein Konflikt weit und breit.</span></div></div>';
    if (!S.conflicts.some(k => k.id === selConflict)) selConflict = S.conflicts.slice().sort((a, b) => b.intensity - a.intensity)[0].id;
    const list = S.conflicts.slice().sort((a, b) => b.intensity - a.intensity).map(k => `
      <div class="dip-row ${k.id === selConflict ? 'sel' : ''}" data-action="conflict-sel" data-id="${k.id}" style="grid-template-columns:28px 1fr 110px 40px">
        <span style="font-size:18px">${conflictIcon(k)}</span><span>${esc(k.name)}<br><small class="muted">${conflictKind(k)}</small></span>
        <div class="bar"><i style="width:${k.intensity}%;background:${k.intensity > 66 ? 'var(--bad)' : k.intensity > 33 ? 'var(--warn)' : 'var(--good)'}"></i></div>
        <span class="badges">${k.peacekeepers ? '🪖' : ''}</span></div>`).join('');
    const k = S.conflicts.find(x => x.id === selConflict);
    const sides = k.type === 'war' ? `<div class="power-cmp" style="margin:12px 0"><div>${flag(k.a, 'flag flag-lg')}<div><b>${esc(Engine.byId(k.a).name)}</b></div><div class="muted">Beziehung ${FS(S.relations[k.a], 0)}</div></div><div class="muted">vs.</div><div>${flag(k.b, 'flag flag-lg')}<div><b>${esc(Engine.byId(k.b).name)}</b></div><div class="muted">Beziehung ${FS(S.relations[k.b], 0)}</div></div></div>
        <div class="war-track"><i style="left:0;width:${(k.progress + 100) / 2}%;background:linear-gradient(90deg,#3b5ba8,#6c8fe0)"></i><i style="left:${(k.progress + 100) / 2}%;right:0;background:linear-gradient(90deg,#a85b3b,#e08f6c)"></i></div>`
      : k.type === 'civil' ? `<div style="margin:12px 0">${flag(k.a, 'flag flag-lg')} <b>${esc(Engine.byId(k.a).name)}</b></div>` : '';
    const opts = Engine.conflictOptions(S, k).map(o => opRow(o.icon, o.name, `${esc(o.desc)}${o.why ? ` · <span class="bad">${esc(o.why)}</span>` : ''}`,
      `<button class="btn btn-sm ${o.danger ? 'btn-danger' : 'btn-primary'}" data-action="intervene" data-id="${k.id}" data-key="${o.key}" ${o.ok ? '' : 'disabled'}>${o.money ? FM(o.money * S.econ.gdp / 100) : 'Los'}</button>`)).join('');
    return `<div class="dip-layout">
      <div class="panel"><div class="panel-title">⚔️ Krisenherde & Kriege <span class="right muted">Intensität</span></div><div class="dip-list">${list}</div></div>
      <div class="panel"><div class="detail-head"><div class="big-ico" style="font-size:30px;width:56px;height:56px;display:grid;place-items:center;background:var(--panel3);border-radius:14px">${conflictIcon(k)}</div><div><h3>${esc(k.name)}</h3><div class="muted">${conflictKind(k)} · seit ${k.months} Mon.</div></div></div>
        ${sides}
        <div class="bs-line" style="margin-top:8px"><span>Intensität</span><b class="${k.intensity > 66 ? 'bad' : k.intensity > 33 ? 'warn' : 'good'}">${F(k.intensity, 0)} / 100</b></div>
        ${k.peacekeepers ? '<div class="bs-line"><span>🪖 Unsere Friedenstruppe</span><span class="good">vor Ort</span></div>' : ''}
        <div class="panel-title" style="margin-top:12px">Eingreifen</div><div class="dip-actions">${opts}</div></div>
    </div>`;
  }

  function treatyBadges(id) {
    const p = S.pacts[id] || {};
    return (S.trade[id] ? '📜' : '') + (S.alliance[id] ? '🛡️' : '') + (p.nichtangriff ? '🤞' : '') + (p.forschung ? '🔬' : '') + (p.energie ? '⚡' : '') + (p.ruestung ? '🕊️' : '')
      + (S.sanctions[id] ? '🚫' : '') + (Engine.atWarWith(S, id) ? '⚔️' : '') + (Engine.hasNukes(S, id) ? '☢️' : '');
  }

  function viewCountries() {
    const ids = Object.keys(S.relations).sort((a, b) => S.relations[b] - S.relations[a]);
    if (!selCountry || S.relations[selCountry] === undefined) selCountry = ids[0];
    const list = ids.map(id => {
      const o = Engine.byId(id), r = S.relations[id];
      return `<div class="dip-row ${id === selCountry ? 'sel' : ''}" data-action="dip-select" data-id="${id}">${flag(id)}<span>${esc(o.name)}</span>${relBar(r)}<span class="badges">${treatyBadges(id) || '<span class="muted">' + F(r, 0) + '</span>'}</span></div>`;
    }).join('');
    return `<div class="dip-layout">
        <div>
          <div class="panel"><div class="panel-title">🗺️ Weltkarte</div><div class="map-wrap"><canvas data-map="1"></canvas></div>${mapLegend()}</div>
          <div class="panel" style="margin-top:14px"><div class="panel-title">🏳️ Länder <span class="right muted">📜 Handel · 🛡️ Bündnis · 🤞 Nichtangriff · 🔬 Forschung · ⚡ Energie · 🕊️ Rüstungskontrolle · ☢️ Atommacht</span></div><div class="dip-list">${list}</div></div>
        </div>
        <div class="panel" id="dip-detail">${dipDetail(selCountry)}</div>
      </div>`;
  }

  function dipDetail(id) {
    const o = Engine.byId(id), r = S.relations[id];
    const odds = Engine.warOdds(S, id);
    const nuc = Engine.hasNukes(S, id);
    const opts = Engine.dipOptions(S, id).map(a => `
      <div class="dip-act"><span style="font-size:20px">${a.icon}</span><div class="t"><b>${a.name}</b><small>${esc(a.desc)}${a.money ? ' · Kosten ' + moneyText(a.money) : ''}${a.key === 'krieg' ? ` · Kräfteverhältnis <b class="${odds < 0.4 ? 'bad' : odds < 0.55 ? 'warn' : 'good'}">${F(odds * 100, 0)} %</b>${nuc ? ' · <b class="bad">Atommacht!</b>' : ''}${S.pacts[id]?.nichtangriff ? ' · <b class="bad">Bricht den Nichtangriffspakt!</b>' : ''}` : ''}</small>${!a.ok ? `<small class="bad"> · ${esc(a.why)}</small>` : ''}</div>
        <button class="btn btn-sm ${a.key === 'krieg' ? 'btn-danger' : 'btn-primary'}" data-action="dip-act" data-id="${id}" data-key="${a.key}" ${a.ok ? '' : 'disabled'}>${a.money ? FM(a.money * S.econ.gdp / 100) : 'Los'}</button></div>`).join('');
    const active = Object.keys(Engine.TREATIES).filter(t => Engine.hasTreaty(S, id, t));
    const tr = active.map(t => `<span class="treaty">${Engine.TREATIES[t].icon} ${Engine.TREATIES[t].name} <a class="x" data-action="treaty-cancel" data-id="${id}" data-t="${t}" data-tip="Vertrag kündigen (verschlechtert die Beziehung)">✕</a></span>`);
    if (S.sanctions[id]) tr.push('<span class="treaty">🚫 Sanktionen</span>');
    if (Engine.atWarWith(S, id)) tr.push('<span class="treaty">⚔️ Krieg</span>');
    const blocs = o.blocs.map(b => Engine.BLOCS[b] ? `${Engine.BLOCS[b].icon} ${Engine.BLOCS[b].name}` : b).join(', ');
    const my = Engine.militaryPower(S), their = Engine.enemyPower(id);
    return `<div class="detail-head">${flag(id, 'flag flag-xl')}<div><h3>${esc(o.name)}</h3><div class="muted">${esc(o.capital)} · ${o.region} · ${o.gov === 'demokratie' ? 'Demokratie' : 'Autoritär'}</div></div></div>
      <div style="margin:14px 0 6px;display:flex;justify-content:space-between"><span>Beziehung: <b style="color:${relColor(r)}">${relWord(r)}</b></span><b style="font-family:var(--mono)">${FS(r, 0)}</b></div>
      ${relBar(r)}
      <div class="treaties" style="margin:12px 0">${tr.length ? tr.join('') : '<span class="muted" style="font-size:12.5px">Keine Verträge</span>'}</div>
      <div class="kv-grid" style="margin-bottom:14px">
        <div><span>BIP</span><b>${FM(o.gdp)}</b></div><div><span>Einwohner</span><b>${F(o.pop, o.pop < 20 ? 1 : 0)} Mio.</b></div>
        <div><span>Kampfkraft</span><b class="${their > my ? 'bad' : 'good'}">${F(their, 0)}</b></div><div><span>Atomwaffen</span><b>${nuc ? '☢️ ~' + F(S.worldNukes[id], 0) : 'keine'}</b></div>
        <div style="grid-column:1/-1"><span>Bündnisse</span><b>${blocs || '–'}</b></div>
      </div>
      ${Engine.atWarWith(S, id) ? '' : `<button class="btn btn-primary" style="width:100%;margin-bottom:12px" data-action="neg-open" data-id="${id}">📝 Vertrag aushandeln</button>`}
      <div class="panel-title">Aktionen</div>
      <div class="dip-actions">${opts}</div>`;
  }

  // ── Verhandlungsfenster ──
  function showNegotiation() {
    const o = Engine.byId(neg.id);
    const types = Object.entries(Engine.TREATIES).map(([k, t]) => {
      const has = Engine.hasTreaty(S, neg.id, k), bl = has ? 'Besteht bereits' : Engine.treatyBlocked(S, neg.id, k);
      return `<button class="choice ${neg.type === k ? 'recommended' : ''}" data-action="neg-type" data-t="${k}" ${bl ? 'disabled style="opacity:.45;cursor:not-allowed"' : ''}>
        <div class="c-top"><span style="font-size:18px">${t.icon}</span><span class="c-label">${k === 'beitritt' && S.ownBloc ? 'Beitritt zum ' + esc(S.ownBloc.name) : t.name}</span></div>
        <div class="c-desc">${esc(t.desc)}${bl ? ` · <b>${esc(bl)}</b>` : ''}</div></button>`;
    }).join('');
    const moneyBtns = Engine.MONEY_OFFERS.map((m, i) => `<button class="${neg.money === i ? 'active' : ''}" data-action="neg-money" data-v="${i}">${i === 0 ? 'Nichts' : F(m, 2) + ' % BIP'}</button>`).join('');
    const p = neg.type ? Engine.negotiationChance(S, neg.id, neg.type, neg) : 0;
    const cost = neg.type ? Engine.TREATIES[neg.type].cost : 0;
    const pc = p >= 0.6 ? 'var(--good)' : p >= 0.35 ? 'var(--warn)' : 'var(--bad)';
    openModal(`
      <div class="modal-head"><div class="big-ico">📝</div><div><div class="cat">Verhandlung · Beziehung ${FS(S.relations[neg.id], 0)}</div><h3>Vertrag mit ${esc(o.name)}</h3></div><div style="margin-left:auto">${flag(o.id, 'flag flag-lg')}</div></div>
      <div class="modal-body">
        <div class="panel-title">1. Welchen Vertrag willst du?</div>
        <div class="choices" style="max-height:290px;overflow-y:auto;padding-right:4px">${types}</div>
        <div class="panel-title" style="margin-top:16px">2. Was bietest du an?</div>
        <div class="form-row"><label>Finanzielle Unterstützung (nur bei Annahme fällig${neg.money ? ' · ' + moneyText(Engine.MONEY_OFFERS[neg.money]) : ''})</label><div class="seg">${moneyBtns}</div></div>
        <div style="display:flex;gap:8px;margin-top:10px;flex-wrap:wrap">
          <button class="btn btn-sm ${neg.concession ? 'btn-good' : ''}" data-action="neg-toggle" data-k="concession" data-tip="Politische Zugeständnisse und Marktöffnung. Bei Annahme: Arbeiter & Konservative leicht verärgert.">${neg.concession ? '☑' : '☐'} Politische Zugeständnisse</button>
          <button class="btn btn-sm ${neg.tech ? 'btn-good' : ''}" data-action="neg-toggle" data-k="tech" data-tip="Teilen von Technologie und Know-how. Bei Annahme: Unternehmer leicht verärgert.">${neg.tech ? '☑' : '☐'} Technologietransfer</button>
        </div>
        <div class="panel-title" style="margin-top:16px">3. Chance auf Zustimmung</div>
        ${neg.type ? `<div class="bar" style="height:14px"><i style="width:${p * 100}%;background:${pc}"></i></div>
          <div style="display:flex;justify-content:space-between;margin-top:6px"><b style="color:${pc};font-size:18px;font-family:var(--mono)">${F(p * 100, 0)} %</b><span class="muted" style="font-size:12.5px">Bei Ablehnung: Beziehung −3, erst nach 4 Monaten erneut möglich</span></div>`
        : '<p class="muted">Wähle zuerst einen Vertrag.</p>'}
      </div>
      <div class="modal-foot"><button class="btn" data-action="modal-close">Abbrechen</button>
        <button class="btn btn-primary" data-action="neg-send" ${!neg.type ? 'disabled' : ''}>Angebot senden</button></div>`, { closable: true, wide: true, update: neg.open });
    neg.open = true;
  }

  // ── Bündnisse ──
  function viewBlocs() {
    const cards = Object.entries(Engine.BLOCS).map(([k, b]) => {
      const st = Engine.blocStatus(S, k);
      const members = st.members.map(id => `<span data-tip="${esc(Engine.byId(id).name)}">${flag(id)}</span>`).join(' ');
      const btn = st.member
        ? `<button class="btn btn-sm btn-danger" data-action="bloc-leave" data-k="${k}" >Austreten</button>`
        : `<button class="btn btn-sm btn-good" data-action="bloc-join" data-k="${k}" ${st.why ? 'disabled' : ''}>Beitritt beantragen</button>`;
      return `<div class="card ${st.member ? 'active' : st.why ? 'locked' : ''}">
        <div class="card-head"><div class="ico">${b.icon}</div><div>${st.member ? '<div class="tag">✔ Mitglied</div>' : ''}<h4>${b.name}</h4><div class="muted" style="font-size:12px">${b.kind}</div></div></div>
        <div class="desc">${esc(b.desc)}</div>
        <div style="display:flex;gap:4px;flex-wrap:wrap">${members || '<span class="muted">keine Mitglieder</span>'}</div>
        <div class="card-foot"><span class="why">${st.member ? '' : st.why ? `<span class="bad">${esc(st.why)}</span>` : `Aufnahmechance <b>${F(st.chance * 100, 0)} %</b>`}</span>${btn}</div></div>`;
    }).join('');
    const ob = S.ownBloc;
    const own = ob ? `<div class="card active">
        <div class="card-head"><div class="ico">🏳️</div><div><div class="tag">Dein Bündnis</div><h4>${esc(ob.name)}</h4><div class="muted" style="font-size:12px">gegründet ${Engine.dateStr(S, ob.founded)}</div></div></div>
        <div class="desc">Militärischer Beistand und Freihandel unter allen Mitgliedern. Jedes Mitglied steigert Sicherheit und Ansehen.</div>
        <div style="display:flex;gap:6px;flex-wrap:wrap">${ob.members.length ? ob.members.map(id => `<span class="treaty">${flag(id)} ${esc(Engine.byId(id).name)}</span>`).join('') : '<span class="muted">Noch keine Mitglieder – lade Länder über „Vertrag aushandeln“ ein.</span>'}</div>
        <div class="card-foot"><span class="why">${ob.members.length} Mitglieder</span><button class="btn btn-sm btn-danger" data-action="bloc-dissolve">Auflösen</button></div></div>`
      : `<div class="card">
        <div class="card-head"><div class="ico">🏳️</div><div><h4>Eigenes Bündnis gründen</h4><div class="muted" style="font-size:12px">Benötigt Ansehen ≥ 30</div></div></div>
        <div class="desc">Schmiede deine eigene Allianz! Danach lädst du Länder einzeln per Vertragsverhandlung („Beitritt zu deinem Bündnis“) ein.</div>
        <div class="form-row"><label>Name des Bündnisses</label><input type="text" id="inp-bloc" maxlength="40" placeholder="${esc(S.country.name)}-Pakt"></div>
        <div class="card-foot"><span></span><button class="btn btn-sm btn-primary" data-action="bloc-found" ${S.stats.reputation < 30 ? 'disabled' : ''}>Gründen</button></div></div>`;
    return `<div class="cards">${cards}${own}</div>
      <p class="muted" style="font-size:12.5px;margin-top:12px">Militärbündnisse wie die NATO verpflichten zum Beistand und verbessern deine Kampfkraft im Krieg. Gegnerische Blöcke (NATO ↔ BRICS) reagieren verärgert auf einen Beitritt.</p>`;
  }

  // ── Atomwaffenfreie Welt ──
  function viewDisarm() {
    const d = S.disarm, holders = Engine.nuclearHolders(S);
    const totalNow = Object.values(S.worldNukes).reduce((a, b) => a + b, 0) + (S.nukes || 0);
    const signed = holders.filter(id => d.signed[id]).length;
    const rows = holders.map(id => {
      const self = id === S.countryId, o = Engine.byId(id);
      const count = self ? S.nukes : S.worldNukes[id];
      let action;
      if (d.signed[id]) action = '<span class="good">✔ unterzeichnet</span>';
      else if (!d.active) action = '<span class="muted">–</span>';
      else if (self) action = `<button class="btn btn-sm btn-good" data-action="disarm-pledge" data-tip="Wir verpflichten uns selbst – das erhöht unsere Glaubwürdigkeit stark. Militär & Konservative 😠">Selbst unterzeichnen</button>`;
      else action = `<span class="muted" style="font-size:12px;margin-right:8px">Chance ${F(Engine.disarmChance(S, id) * 100, 0)} %</span><button class="btn btn-sm btn-primary" data-action="disarm-persuade" data-id="${id}" >Überzeugen</button>`;
      return `<div class="dip-act">${flag(id)}<div class="t"><b>${esc(o.name)}${self ? ' (wir)' : ''}</b><small>☢️ ~${F(count, 0)} Sprengköpfe${S.pacts[id]?.ruestung ? ' · 🕊️ Rüstungskontrollvertrag' : ''}</small></div>${action}</div>`;
    }).join('');
    const status = d.done ? '<div class="tip good"><span class="ti">🏅</span><span><b>Die Welt ist frei von Atomwaffen.</b> Ein historischer Erfolg.</span></div>'
      : d.dismantling ? `<div class="tip good"><span class="ti">🕊️</span><span><b>Abrüstung läuft:</b> Alle Atommächte haben unterzeichnet. Noch ~${F(totalNow, 0)} Sprengköpfe weltweit.</span></div>`
      : d.active ? `<div class="tip info"><span class="ti">📋</span><span>Die Initiative läuft: <b>${signed} von ${holders.length}</b> Atommächten haben unterzeichnet. Sobald alle unterschrieben haben, beginnt der Abbau.</span></div>`
      : `<div class="tip"><span class="ti">☮️</span><span>Starte eine weltweite Initiative zur Abschaffung aller Atomwaffen. Gute Beziehungen, hohes Ansehen und Rüstungskontrollverträge erhöhen die Chancen. Besitzt du selbst Atomwaffen, musst du mit gutem Beispiel vorangehen.</span></div>`;
    return `<div class="grid g2">
      <div class="panel"><div class="panel-title">☮️ Initiative für eine atomwaffenfreie Welt</div>${status}
        ${!d.active && !d.done ? `<button class="btn btn-primary" style="width:100%;margin-top:6px" data-action="disarm-start" ${S.stats.reputation < 45 || S.nukeUsed ? 'disabled' : ''}>Initiative starten${S.stats.reputation < 45 ? ' (Ansehen ≥ 45 nötig)' : ''}</button>` : ''}
        <div class="bs-line" style="margin-top:12px"><span>Atomsprengköpfe weltweit</span><b>~${F(totalNow, 0)}</b></div>
        <div class="bs-line"><span>Unser Ansehen</span><b>${F(S.stats.reputation, 0)}</b></div>
        <p class="muted" style="font-size:12px">Unterzeichner können wieder abspringen, wenn die Beziehung stark sinkt oder du mit ihnen Krieg führst. Erst wenn alle unterschrieben haben, wird abgerüstet.</p></div>
      <div class="panel"><div class="panel-title">☢️ Atommächte <span class="right muted">${signed}/${holders.length} unterzeichnet</span></div>
        <div class="dip-actions">${rows || '<span class="muted">Es gibt keine Atomwaffen mehr.</span>'}</div></div>
    </div>`;
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
  function viewChronik() {
    const tabs = Object.entries(CHARTS).map(([k, c]) => `<button class="btn btn-sm ${k === chartMetric ? 'active' : ''}" data-action="chart" data-m="${k}">${c.name}</button>`).join('');
    const list = S.news.slice(0, 60).map(n => `<div class="news-item ${n.type}"><span class="when">${Engine.dateStr(S, n.month)}</span><span class="txt">${esc(n.text)}</span></div>`).join('');
    return `
      <div class="view-head"><h2>📊 Chronik</h2><span class="sub">Entwicklung und Nachrichten seit deinem Amtsantritt.</span></div>
      <div class="grid g-main">
        <div class="panel"><div class="chart-tabs">${tabs}</div><div class="chart-box"><canvas data-chart="${chartMetric}"></canvas></div></div>
        <div class="panel"><div class="panel-title">📰 Nachrichten</div><div style="max-height:420px;overflow-y:auto">${list}</div></div>
      </div>`;
  }

  // ─────────────────────────── Ansicht: Nachrichten ───────────────────────────


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
  function blocColor(id) {
    if (S.ownBloc && S.ownBloc.members.includes(id)) return 'rgba(245,185,66,.75)';
    const b = Engine.byId(id).blocs;
    if (b.includes('NATO')) return '#4da3ff';
    if (b.includes('BRICS')) return '#ff7a59';
    if (b.includes('EU')) return '#9db9ff';
    if (b.includes('PAZ') || b.includes('NA')) return '#2ec4b6';
    return 'rgba(150,160,185,.45)';
  }
  function conflictStateOf(id) {
    for (const k of S.conflicts) {
      if (k.type === 'war' && (k.a === id || k.b === id)) return 'war';
      if (k.type === 'civil' && k.a === id) return 'civil';
    }
    return null;
  }
  const mapCache = {};
  function baseLayer(w, h, opts) {
    const key = [opts.start ? 'start' : mapMode, w, h, opts.start ? setupSel : '', S ? S.month : '', S ? Object.keys(S.policies).length : '', selCountry, view, S ? S.conflicts.map(k => k.id).join() + S.wars.length + JSON.stringify(S.ownBloc && S.ownBloc.members) + S.blocs.join() : ''].join('|');
    const dpr = window.devicePixelRatio || 1;
    if (mapCache.key === key && mapCache.canvas) return mapCache.canvas;
    const cv = document.createElement('canvas'); cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);
    const ctx = cv.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const cw = w / WORLD_MAP.width, chh = h / WORLD_MAP.height, rad = Math.max(0.8, Math.min(cw, chh) * 0.36);
    for (const d of mapDots) {
      const id = keyToId[d.ch];
      let col = 'rgba(110,130,180,0.22)', r = rad;
      if (id) {
        if (opts.start) col = id === setupSel ? '#f5b942' : 'rgba(120,160,240,0.55)';
        else if (id === S.countryId) col = '#f5b942';
        else if (Engine.atWarWith(S, id)) col = '#ff2040';
        else if (mapMode === 'beziehungen') col = relColor(S.relations[id]);
        else if (mapMode === 'buendnisse') col = blocColor(id);
        else { const cs = conflictStateOf(id); col = cs === 'war' ? '#ff4d5e' : cs === 'civil' ? '#ff9f43' : S.alliance[id] ? 'rgba(120,170,255,.55)' : 'rgba(140,155,195,.42)'; }
        if (!opts.start && id === selCountry && view === 'welt' && dipTab === 'laender') r = rad * 1.35;
      }
      ctx.fillStyle = col;
      ctx.beginPath(); ctx.arc((d.x + 0.5) * cw, (d.y + 0.5) * chh, r, 0, Math.PI * 2); ctx.fill();
    }
    mapCache.key = key; mapCache.canvas = cv;
    return cv;
  }
  function arc(ctx, x, y, ex, ey, color, dash, width = 1.5) {
    ctx.strokeStyle = color; ctx.lineWidth = width; ctx.setLineDash(dash || []);
    ctx.beginPath(); ctx.moveTo(x, y); ctx.quadraticCurveTo((x + ex) / 2, Math.min(y, ey) - Math.max(20, Math.abs(ex - x) * 0.15), ex, ey); ctx.stroke(); ctx.setLineDash([]);
  }
  let placedLabels = [];
  function label(ctx, text, x, y, color = '#e7ecf7', alt = null) {
    ctx.font = '600 11px Segoe UI, system-ui, sans-serif'; ctx.textAlign = 'center';
    const w = ctx.measureText(text).width + 6;
    const free = yy => !placedLabels.some(r => Math.abs(r.x - x) < (r.w + w) / 2 && Math.abs(r.y - yy) < 14);
    if (!free(y)) { if (alt !== null && free(alt)) y = alt; else return; }
    placedLabels.push({ x, y, w });
    ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(5,8,18,.85)'; ctx.strokeText(text, x, y);
    ctx.fillStyle = color; ctx.fillText(text, x, y);
  }
  function drawMap(c, opts = {}) {
    prepMap();
    const { ctx, w, h } = fitCanvas(c);
    const t = opts.time || performance.now();
    ctx.drawImage(baseLayer(w, h, opts), 0, 0, w, h);
    if (opts.pings) for (const p of opts.pings) {
      const [x, y] = latLonToXY(...COUNTRY_COORDS[p.id], w, h);
      const age = (t - p.t) / 2000;
      if (age < 0 || age > 1) continue;
      ctx.strokeStyle = `rgba(245,185,66,${1 - age})`; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(x, y, 4 + age * 30, 0, Math.PI * 2); ctx.stroke();
    }
    if (opts.start || !S) return;
    const xy = id => latLonToXY(...COUNTRY_COORDS[id], w, h);
    placedLabels = [];
    const [px, py] = xy(S.countryId);
    // Bündnislinien
    if (mapMode === 'buendnisse') for (const id in S.alliance) if (S.alliance[id]) { const [x, y] = xy(id); arc(ctx, px, py, x, y, 'rgba(245,185,66,.45)', null, 1.2); }
    if (mapMode === 'beziehungen') for (const id in S.trade) if (S.trade[id]) { const [x, y] = xy(id); arc(ctx, px, py, x, y, 'rgba(62,207,142,.35)', [2, 4], 1); }
    // Konflikte
    const pulse = 0.5 + 0.5 * Math.sin(t / 300);
    for (const k of S.conflicts) {
      const [lat, lon] = Engine.conflictPos(k);
      const [x, y] = latLonToXY(lat, lon, w, h);
      const sel = view === 'welt' && dipTab === 'konflikte' && k.id === selConflict;
      if (k.type === 'war') {
        const [ax, ay] = xy(k.a), [bx, by] = xy(k.b);
        arc(ctx, ax, ay, bx, by, `rgba(255,77,94,${0.55 + 0.4 * pulse})`, [5, 4], sel ? 2.5 : 1.8);
      }
      const r = 5 + k.intensity / 9;
      ctx.fillStyle = k.type === 'civil' ? `rgba(255,159,67,${0.18 + 0.12 * pulse})` : `rgba(255,77,94,${0.16 + 0.14 * pulse})`;
      ctx.beginPath(); ctx.arc(x, y, r + 4 * pulse, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = sel ? '#ffffff' : k.type === 'civil' ? '#ff9f43' : '#ff4d5e'; ctx.lineWidth = sel ? 2.2 : 1.4;
      ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.stroke();
      if (k.peacekeepers) { ctx.strokeStyle = '#6cb8ff'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(x, y, r + 5, 0, Math.PI * 2); ctx.stroke(); }
      ctx.font = '13px Segoe UI Emoji, Apple Color Emoji, sans-serif'; ctx.textAlign = 'center'; ctx.fillStyle = '#fff';
      ctx.fillText(k.peacekeepers ? '🪖' : k.type === 'war' ? '⚔️' : k.type === 'civil' ? '🔥' : '⚠️', x, y + 5);
      if (w > 520 && (k.intensity > 35 || sel)) label(ctx, k.name.replace(/^Krieg /, ''), x, y - r - 6, sel ? '#ffd479' : '#ffd0d5', y + r + 15);
    }
    // Eigene Kriege
    for (const wr of S.wars) { const [ex, ey] = xy(wr.enemy); arc(ctx, px, py, ex, ey, `rgba(255,32,64,${0.6 + 0.4 * pulse})`, [6, 4], 2.4); label(ctx, '⚔️ Unser Krieg', (px + ex) / 2, Math.min(py, ey) - 20, '#ff8a95'); }
    // Hauptstadt
    ctx.strokeStyle = '#ffd479'; ctx.lineWidth = 1.6;
    ctx.beginPath(); ctx.arc(px, py, 6 + 2 * pulse, 0, Math.PI * 2); ctx.stroke();
  }
  function conflictHit(c, ev) {
    if (!S || !S.conflicts) return null;
    const r = c.getBoundingClientRect(), mx = ev.clientX - r.left, my = ev.clientY - r.top;
    let best = null, bd = 1e9;
    for (const k of S.conflicts) {
      const [x, y] = latLonToXY(...Engine.conflictPos(k), r.width, r.height);
      const d = Math.hypot(x - mx, y - my);
      if (d < 7 + k.intensity / 9 && d < bd) { best = k; bd = d; }
    }
    return best;
  }
  function startGameMapLoop() {
    if (mapAnim) return;
    let last = 0;
    const loop = t => {
      mapAnim = requestAnimationFrame(loop);
      if (t - last < 70) return;
      last = t;
      if (!$('#screen-game').classList.contains('active')) return;
      document.querySelectorAll('#view canvas[data-map]').forEach(c => drawMap(c, { time: t }));
    };
    mapAnim = requestAnimationFrame(loop);
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
    const existing = $('#modal-root .modal');
    if (opts.update && existing) { const sc = existing.scrollTop; existing.innerHTML = html; existing.scrollTop = sc; return; }
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
      ['Staatskonto 🏦', 'Was im Haushalt übrig bleibt, landet auf deinem Konto. Damit bezahlst du Gesetze, Maßnahmen und Sonderprojekte – oder tilgst Schulden. Ist das Konto leer, macht der Staat automatisch neue Schulden.'],
      ['Minister-Autopilot 🤖', 'Deine Minister kümmern sich auf Wunsch selbst um Finanzen, Wirtschaft, Soziales, Militär, Diplomatie und kleine Ereignisse. Du greifst ein, wann du willst. Einstellbar unter <b>Regierung</b>.'],
      ['Entscheiden', 'Unter <b>Regierung</b> beschließt du Gesetze und Sofortmaßnahmen – ohne Wartezeit. Wiederholst du dieselbe Maßnahme schnell, wirkt sie schwächer. Grüne Chips sind gute, rote schlechte Folgen.'],
      ['Die Welt', 'Die Karte zeigt Kriege ⚔️, Bürgerkriege 🔥 und Krisenherde ⚠️. Klicke darauf, um zu vermitteln, zu helfen, Friedenstruppen zu schicken oder einzugreifen.'],
      ['Militär & Kriege', 'Kriege brauchen <b>Vorbereitung</b>: Verteidigungsbudget, Kriegsbereitschaft (steigt nur langsam) und Verbündete. Achte auf das <b>Kräfteverhältnis</b> – Offensiven wirken nur, wenn du stärker bist. Deine <b>Spezialeinheit</b> bekämpft Terror. Atommächte lassen sich nicht einfach besiegen.'],
      ['Starke und schwache Staaten', 'Die <b>Staatskapazität</b> bestimmt, wie gut Reformen wirken. Ein Land wie Sudan kann sich nicht in wenigen Jahren in eine Schweiz verwandeln – Fortschritt braucht dort Jahrzehnte.'],
      ['Ereignisse', 'Krisen, Skandale und Chancen passieren zufällig. Deine Berater markieren die empfohlene Option mit ⭐ – du musst ihnen aber nicht folgen.'],
      ['Gefahren', 'Vorsicht vor <b>Revolution</b> (Stabilität &lt; 10), <b>Putsch</b> (unzufriedenes Militär), <b>Staatsbankrott</b> (zu hohe Schulden) und <b>Abwahl</b>. Rote Punkte in der Navigation warnen dich.'],
      ['Tastenkürzel', '<kbd>Leertaste</kbd> nächster Monat · <kbd>1</kbd>–<kbd>6</kbd> Bereiche wechseln · <kbd>1</kbd>–<kbd>4</kbd> Option im Ereignis wählen · <kbd>A</kbd> Automatik · <kbd>Esc</kbd> Menü schließen'],
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
      const kHit = canvas && S ? conflictHit(canvas, ev) : null;
      if (kHit) html = `<b>${conflictIcon(kHit)} ${esc(kHit.name)}</b><br>${conflictKind(kHit)}<br>Intensität ${F(kHit.intensity, 0)}/100${kHit.peacekeepers ? '<br>🪖 Unsere Friedenstruppe vor Ort' : ''}<br><i>Klicken zum Eingreifen</i>`;
      else if (canvas && S) {
        const id = mapHit(canvas, ev);
        if (id) {
          const o = Engine.byId(id);
          html = id === S.countryId ? `<b>${esc(o.name)}</b><br>Dein Land` :
            `<b>${esc(o.name)}</b><br>Beziehung: ${relWord(S.relations[id])} (${FS(S.relations[id], 0)})${S.trade[id] ? '<br>📜 Handelsabkommen' : ''}${S.alliance[id] ? '<br>🛡️ Bündnis' : ''}${S.pacts[id]?.nichtangriff ? '<br>🤞 Nichtangriffspakt' : ''}${Engine.hasNukes(S, id) ? '<br>☢️ Atommacht' : ''}${S.sanctions[id] ? '<br>🚫 Sanktionen' : ''}${Engine.atWarWith(S, id) ? '<br>⚔️ Krieg!' : ''}`;
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
      case 'fin': { const r = Engine.financeOp(S, el.dataset.op, +el.dataset.amt); result(r, r.msg ? esc(r.msg) : ''); break; }
      case 'proj-amt': projAmt[id] = +el.dataset.v; renderView(); break;
      case 'proj-run': { const r = Engine.runProject(S, id, projAmt[id] ?? 0.5); result(r, r.msg ? esc(r.msg) : ''); break; }
      case 'auto-toggle': S.auto[el.dataset.k] = !S.auto[el.dataset.k]; save(); renderAll(); break;
      case 'auto-all': for (const k in Engine.AUTO_AREAS) S.auto[k] = el.dataset.v === '1'; save(); renderAll(); break;
      case 'gov-filter': govFilter = el.dataset.k; renderView(); break;
      case 'map-mode': mapMode = el.dataset.k; renderView(); break;
      case 'conflict-open': selConflict = id; dipTab = 'konflikte'; view = 'welt'; renderSidebar(); renderView(); break;
      case 'conflict-sel': selConflict = id; renderView(); break;
      case 'intervene': {
        if (el.dataset.key.startsWith('eingreifen') && !confirm('Wirklich militärisch eingreifen? Das bedeutet Krieg.')) return;
        const r = Engine.intervene(S, id, el.dataset.key);
        if (r.ok && r.msg) toast(esc(r.msg), r.msg.startsWith('❌') ? 'bad' : 'good', 4000);
        result({ ok: r.ok, why: r.why }); break;
      }
      case 'dip-select': selCountry = id; dipTab = 'laender'; renderView(); break;
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
        if (!confirm(`ATOMSCHLAG gegen ${o.name}?\n\nDeine Berater warnen eindringlich: ${Engine.hasNukes(S, o.id) ? 'Es droht eine nukleare Krise mit möglichem Gegenschlag.' : 'Dein Land wird weltweit geächtet – Sanktionen, Bündnisbruch, Wirtschaftseinbruch.'}`)) return;
        if (!confirm('Letzte Bestätigung: Diese Entscheidung kann nicht rückgängig gemacht werden.')) return;
        sfx('war');
        const r = Engine.nuclearStrike(S); result({ ok: r.ok, why: r.why }); break;
      }
      case 'dip-tab': dipTab = el.dataset.t; renderView(); break;
      case 'neg-open': neg = { id, type: null, money: 0, concession: false, tech: false }; showNegotiation(); break;
      case 'neg-type': neg.type = el.dataset.t; showNegotiation(); break;
      case 'neg-money': neg.money = +el.dataset.v; showNegotiation(); break;
      case 'neg-toggle': neg[el.dataset.k] = !neg[el.dataset.k]; showNegotiation(); break;
      case 'neg-send': {
        const r = Engine.negotiate(S, neg.id, neg.type, neg);
        if (!r.ok) { toast(esc(r.why), 'bad'); break; }
        closeModal(); sfx(r.accepted ? 'good' : 'bad'); toast(esc(r.msg), r.accepted ? 'good' : 'bad', 4500);
        save(); renderAll(); break;
      }
      case 'treaty-cancel': {
        if (!confirm(`${Engine.TREATIES[el.dataset.t].name} mit ${Engine.byId(id).name} wirklich kündigen?`)) return;
        result(Engine.cancelTreaty(S, id, el.dataset.t)); break;
      }
      case 'bloc-join': { const r = Engine.joinBloc(S, el.dataset.k); if (r.ok) toast(esc(r.msg), r.msg.startsWith('✅') ? 'good' : 'bad', 4500); result({ ok: r.ok, why: r.why }); break; }
      case 'bloc-leave': {
        if (!confirm(`Wirklich aus der ${Engine.BLOCS[el.dataset.k].name} austreten?`)) return;
        const r = Engine.leaveBloc(S, el.dataset.k); if (r.ok) toast(esc(r.msg), 'bad'); result({ ok: r.ok, why: r.why }); break;
      }
      case 'bloc-found': { const r = Engine.foundBloc(S, $('#inp-bloc')?.value); if (r.ok) toast(esc(r.msg), 'good', 4500); result({ ok: r.ok, why: r.why }); break; }
      case 'bloc-dissolve': { if (!confirm('Dein Bündnis wirklich auflösen?')) return; result(Engine.dissolveBloc(S)); break; }
      case 'disarm-start': { const r = Engine.startDisarm(S); if (r.ok) toast(esc(r.msg), 'good', 4500); result({ ok: r.ok, why: r.why }); break; }
      case 'disarm-persuade': { const r = Engine.persuadeDisarm(S, id); if (r.ok) toast(esc(r.msg), r.msg.startsWith('✅') ? 'good' : 'bad', 4000); result({ ok: r.ok, why: r.why }); break; }
      case 'disarm-pledge': { const r = Engine.pledgeDisarm(S); if (r.ok) toast(esc(r.msg), 'good'); result({ ok: r.ok, why: r.why }); break; }
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
      if (c && S) {
        const k = conflictHit(c, ev);
        if (k) { selConflict = k.id; dipTab = 'konflikte'; view = 'welt'; renderSidebar(); renderView(); return; }
        const id = mapHit(c, ev);
        if (id && id !== S.countryId) { selCountry = id; dipTab = 'laender'; view = 'welt'; renderSidebar(); renderView(); }
      }
    });
    document.addEventListener('input', ev => {
      const t = ev.target;
      if (t.dataset && t.dataset.budget && S) {
        const [kind, k] = t.dataset.budget.split(':');
        if (kind === 'tax') S.taxes[k] = +t.value; else if (kind === 'disc') S.discretionary = +t.value; else S.spending[k] = +t.value;
        S.budget = Engine.computeBudget(S);
        if (kind === 'tax') for (const kk in TAX_INFO) $(`#sv-tax-${kk}`).innerHTML = sliderVal('tax', kk, S.taxes[kk], S.country.taxes[kk]);
        if (kind === 'disc') $('#sv-disc-x').innerHTML = sliderVal('disc', 'x', S.discretionary, 0.5);
        if (kind === 'spend') $(`#sv-spend-${k}`).innerHTML = sliderVal('spend', k, S.spending[k], S.country.spending[k]);
      }
    });
    document.addEventListener('change', ev => {
      if (ev.target.dataset && ev.target.dataset.budget && S) { save(); renderTopbar(); const sc = $('#view').scrollTop; renderView(); $('#view').scrollTop = sc; }
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
