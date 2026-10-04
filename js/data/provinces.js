// Provinzen: Jedes Land wird automatisch aus seinen Kartenpunkten in Regionen aufgeteilt
// (deterministisches k-Means). In eigenen Provinzen lassen sich Industrie, Infrastruktur und Energie ausbauen.
const PROVINCES = (() => {
  const W = WORLD_MAP.width, H = WORLD_MAP.height;
  const grid = new Int16Array(W * H).fill(-1);
  const list = [], byCountry = {};
  const DIRS = ['Osten', 'Nordosten', 'Norden', 'Nordwesten', 'Westen', 'Südwesten', 'Süden', 'Südosten'];
  // Regionsnamen: Jede Provinz bekommt den Namen des nächstgelegenen Ankerpunkts (Breite, Länge)
  const NAMES = {
    DE: [['Berlin-Brandenburg', 52.5, 13.4], ['Norddeutschland', 53.5, 9.5], ['Nordrhein-Westfalen', 51.4, 7.3], ['Bayern', 48.8, 11.5], ['Baden-Württemberg', 48.6, 9.0], ['Sachsen', 51.0, 13.2], ['Hessen', 50.5, 9.0]],
    FR: [['Île-de-France', 48.8, 2.4], ['Bretagne', 48.1, -2.8], ['Aquitaine', 44.8, -0.5], ['Provence', 43.7, 5.8], ['Elsass-Lothringen', 48.6, 6.8], ['Normandie', 49.2, 0.3], ['Rhône-Alpes', 45.6, 5.0], ['Okzitanien', 43.6, 2.0]],
    GB: [['London', 51.5, -0.1], ['Schottland', 56.8, -4.2], ['Wales', 52.3, -3.7], ['Nordengland', 54.2, -1.8], ['Midlands', 52.6, -1.5], ['Nordirland', 54.6, -6.7]],
    IT: [['Latium', 41.9, 12.6], ['Lombardei', 45.6, 9.8], ['Venetien', 45.6, 12.0], ['Sizilien', 37.5, 14.2], ['Kampanien', 40.9, 14.8], ['Sardinien', 40.0, 9.0], ['Toskana', 43.4, 11.1]],
    ES: [['Madrid', 40.4, -3.7], ['Katalonien', 41.8, 1.6], ['Andalusien', 37.4, -5.0], ['Galicien', 42.8, -8.0], ['Valencia', 39.4, -0.6], ['Aragonien', 41.5, -0.9], ['Kastilien', 41.7, -4.7]],
    PL: [['Masowien', 52.2, 21.0], ['Pommern', 54.2, 17.5], ['Schlesien', 50.6, 17.5], ['Kleinpolen', 50.0, 20.5], ['Großpolen', 52.4, 16.8], ['Podlachien', 53.2, 22.9]],
    UA: [['Kiew', 50.4, 30.5], ['Charkiw', 49.9, 36.2], ['Lwiw', 49.8, 24.0], ['Odessa', 46.6, 30.6], ['Donbass', 48.0, 38.0], ['Dnipro', 48.4, 35.0], ['Krim', 45.2, 34.2], ['Saporischschja', 47.5, 35.5]],
    US: [['Washington D.C.', 38.9, -77.0], ['Neuengland', 43.0, -71.5], ['Florida', 28.0, -81.6], ['Texas', 31.0, -99.0], ['Kalifornien', 37.0, -120.0], ['Mittlerer Westen', 41.8, -89.0], ['Pazifischer Nordwesten', 46.5, -120.5], ['Rocky Mountains', 40.0, -106.0], ['Alaska', 64.0, -150.0], ['Große Ebenen', 44.0, -99.0], ['Südstaaten', 33.0, -88.0], ['Südwesten', 34.0, -111.0], ['Hawaii', 20.8, -157.0]],
    CA: [['Ontario', 45.0, -79.5], ['Québec', 49.0, -72.0], ['British Columbia', 53.7, -124.0], ['Alberta', 54.0, -114.0], ['Prärie', 52.5, -103.0], ['Atlantikprovinzen', 47.0, -63.0], ['Yukon', 63.5, -136.0], ['Nordwest-Territorien', 64.5, -119.0], ['Nunavut', 68.0, -95.0], ['Labrador', 54.0, -61.0], ['Arktische Inseln', 76.0, -90.0], ['Hudson Bay', 57.0, -88.0]],
    MX: [['Mexiko-Stadt', 19.4, -99.1], ['Baja California', 30.0, -115.0], ['Chihuahua', 28.6, -106.0], ['Nuevo León', 25.6, -100.0], ['Jalisco', 20.7, -103.4], ['Yucatán', 20.5, -89.0], ['Oaxaca', 17.0, -96.7], ['Sonora', 29.3, -110.3]],
    BR: [['Brasília', -15.8, -47.9], ['São Paulo', -23.0, -48.0], ['Rio de Janeiro', -22.5, -43.2], ['Amazonas', -4.0, -64.0], ['Pará', -4.0, -52.0], ['Nordosten', -8.0, -38.0], ['Rio Grande do Sul', -29.5, -53.0], ['Mato Grosso', -13.0, -56.0], ['Bahia', -12.5, -41.5], ['Minas Gerais', -18.5, -44.5]],
    AR: [['Buenos Aires', -34.6, -58.4], ['Córdoba', -31.4, -64.2], ['Patagonien', -44.0, -69.0], ['Feuerland', -53.0, -68.5], ['Mendoza', -34.5, -68.5], ['Nordwesten', -25.0, -65.5], ['Chaco', -26.0, -60.5], ['Pampa', -37.0, -64.0], ['Santa Cruz', -49.0, -70.0]],
    RU: [['Moskau', 55.8, 37.6], ['Sankt Petersburg', 59.9, 30.3], ['Wolga', 54.0, 48.0], ['Ural', 58.0, 60.0], ['Westsibirien', 60.0, 75.0], ['Ostsibirien', 62.0, 105.0], ['Fernost', 50.0, 135.0], ['Jakutien', 65.0, 125.0], ['Kamtschatka', 60.0, 160.0], ['Tschukotka', 67.0, 172.0], ['Nordkaukasus', 44.5, 44.0], ['Arktis', 70.0, 90.0], ['Altai', 52.0, 86.0]],
    CN: [['Peking', 39.9, 116.4], ['Shanghai', 31.2, 121.0], ['Guangdong', 23.2, 113.3], ['Sichuan', 30.5, 103.0], ['Xinjiang', 41.0, 85.0], ['Tibet', 31.5, 88.0], ['Mandschurei', 45.5, 126.0], ['Innere Mongolei', 42.5, 110.0], ['Yunnan', 25.0, 101.5], ['Hunan', 27.5, 112.0], ['Gansu', 37.0, 101.0], ['Qinghai', 35.5, 96.0]],
    IN: [['Delhi', 28.6, 77.2], ['Maharashtra', 19.0, 75.0], ['Tamil Nadu', 11.5, 78.5], ['Westbengalen', 23.0, 88.0], ['Gujarat', 22.5, 71.5], ['Rajasthan', 26.5, 73.5], ['Uttar Pradesh', 27.0, 80.5], ['Karnataka', 14.5, 76.0], ['Assam', 26.3, 92.5], ['Madhya Pradesh', 23.5, 78.5], ['Kaschmir', 34.0, 76.0], ['Odisha', 20.5, 84.5]],
    AU: [['Canberra', -35.3, 149.1], ['New South Wales', -32.5, 147.0], ['Victoria', -37.0, 144.5], ['Queensland', -22.0, 145.0], ['Westaustralien', -26.0, 121.0], ['Südaustralien', -30.0, 135.0], ['Northern Territory', -19.5, 133.5], ['Tasmanien', -42.0, 146.5], ['Kimberley', -17.0, 126.0], ['Kap York', -14.0, 143.0], ['Perth', -32.0, 116.0]],
    JP: [['Kantō (Tokio)', 35.7, 139.7], ['Kansai (Osaka)', 34.7, 135.5], ['Hokkaidō', 43.3, 142.5], ['Kyūshū', 32.8, 130.8], ['Tōhoku', 39.5, 140.8], ['Chūbu', 36.2, 137.5], ['Chūgoku', 34.8, 132.5]],
    TR: [['Ankara', 39.9, 32.9], ['Istanbul (Marmara)', 41.0, 28.9], ['Ägäis', 38.5, 27.8], ['Mittelmeerküste', 36.9, 32.5], ['Schwarzmeerküste', 41.0, 37.5], ['Ostanatolien', 39.5, 41.5], ['Südostanatolien', 37.5, 39.5]],
    IR: [['Teheran', 35.7, 51.4], ['Isfahan', 32.7, 51.7], ['Chorasan', 35.5, 59.0], ['Chuzestan', 31.3, 49.0], ['Aserbaidschan (Iran)', 38.0, 46.3], ['Fars', 29.6, 52.5], ['Belutschistan', 28.0, 60.5], ['Kerman', 30.3, 57.0]],
    SA: [['Riad', 24.7, 46.7], ['Mekka (Hedschas)', 21.5, 40.0], ['Ostprovinz', 25.5, 50.0], ['Asir', 18.5, 43.0], ['Tabuk', 28.5, 36.5], ['Rub al-Chali', 20.0, 50.0], ['Hail', 27.5, 42.0], ['Medina', 24.5, 39.6]],
    EG: [['Kairo', 30.0, 31.2], ['Alexandria (Delta)', 31.0, 30.0], ['Sinai', 29.5, 33.8], ['Oberägypten', 25.7, 32.6], ['Westliche Wüste', 26.0, 27.0], ['Rotes Meer', 25.0, 34.5], ['Neues Tal', 23.0, 30.0]],
    NG: [['Abuja', 9.1, 7.4], ['Lagos', 6.5, 3.4], ['Kano', 12.0, 8.5], ['Nigerdelta', 5.0, 6.2], ['Borno', 11.8, 13.2], ['Sokoto', 13.0, 5.2], ['Enugu', 6.5, 7.5], ['Adamawa', 9.3, 12.4]],
    ZA: [['Gauteng', -26.2, 28.0], ['Westkap', -33.5, 19.5], ['KwaZulu-Natal', -29.0, 30.8], ['Ostkap', -32.5, 26.0], ['Nordkap', -29.0, 21.0], ['Limpopo', -23.5, 29.5], ['Freistaat', -28.5, 26.5]],
    ID: [['Java', -7.0, 110.0], ['Sumatra', 0.0, 101.5], ['Borneo (Kalimantan)', 0.5, 114.0], ['Sulawesi', -2.0, 120.5], ['Papua', -4.5, 138.0], ['Molukken', -3.0, 129.0], ['Kleine Sundainseln', -8.7, 120.0], ['Bali', -8.4, 115.2]],
    KZ: [['Astana', 51.2, 71.4], ['Almaty', 43.3, 77.0], ['Westkasachstan', 49.0, 52.0], ['Atyrau', 47.0, 52.5], ['Karaganda', 48.0, 73.0], ['Ostkasachstan', 49.0, 82.0], ['Aral', 45.5, 62.0], ['Kostanai', 52.5, 63.5], ['Turkestan', 43.0, 68.5]],
    PK: [['Islamabad', 33.7, 73.0], ['Punjab', 31.0, 72.5], ['Sindh', 26.0, 68.5], ['Belutschistan', 28.5, 65.5], ['Khyber Pakhtunkhwa', 34.5, 71.5], ['Gilgit-Baltistan', 35.8, 75.0], ['Karatschi', 25.0, 67.0]],
    SD: [['Khartum', 15.6, 32.5], ['Darfur', 13.5, 24.5], ['Kordofan', 12.5, 29.5], ['Nordstaat', 19.5, 30.5], ['Rotes Meer', 19.0, 36.5], ['Blauer Nil', 11.5, 34.3], ['Kassala', 15.5, 36.0], ['Nordwüste', 20.5, 25.5]],
    ET: [['Addis Abeba', 9.0, 38.7], ['Tigray', 14.0, 39.0], ['Amhara', 11.5, 37.8], ['Somali-Region', 7.0, 44.0], ['Oromia', 7.5, 39.5], ['Afar', 12.0, 41.0], ['Südliche Völker', 6.0, 36.5]],
    DZ: [['Algier', 36.7, 3.1], ['Oran', 35.5, -0.6], ['Constantine', 36.3, 6.6], ['Sahara', 26.5, 2.5], ['Tamanrasset', 22.8, 5.5], ['Adrar', 27.0, -1.0], ['Ouargla', 31.0, 6.5], ['Illizi', 26.5, 8.5]],
    CO: [['Bogotá', 4.7, -74.1], ['Antioquia', 7.0, -75.5], ['Karibikküste', 10.0, -74.5], ['Valle del Cauca', 3.5, -76.5], ['Llanos', 4.5, -70.5], ['Amazonas', -1.0, -71.5]],
    VE: [['Caracas', 10.5, -66.9], ['Zulia', 10.0, -72.0], ['Llanos', 8.0, -67.5], ['Bolívar', 6.5, -63.0], ['Amazonas', 3.5, -65.5], ['Orinoco-Delta', 9.0, -61.5]],
    PE: [['Lima', -12.0, -77.0], ['Nordküste', -7.0, -79.0], ['Arequipa', -16.0, -72.0], ['Cusco', -13.5, -72.0], ['Amazonas (Loreto)', -4.5, -74.5], ['Ucayali', -9.5, -73.5]],
    CL: [['Santiago', -33.4, -70.6], ['Atacama', -24.0, -69.5], ['Valparaíso', -32.5, -71.3], ['Araukanien', -38.5, -72.5], ['Los Lagos', -42.0, -73.0], ['Patagonien', -48.0, -73.0], ['Magallanes', -53.0, -71.0]],
    IQ: [['Bagdad', 33.3, 44.4], ['Basra', 30.5, 47.8], ['Kurdistan', 36.2, 44.0], ['Anbar', 33.0, 41.5], ['Mossul', 36.3, 43.1], ['Nadschaf', 31.0, 44.5]],
    SE: [['Stockholm', 59.3, 18.0], ['Götaland', 57.5, 14.0], ['Norrland', 64.0, 17.5], ['Lappland', 67.5, 20.0], ['Dalarna', 61.0, 14.5], ['Schonen', 55.8, 13.5]],
    NO: [['Oslo', 59.9, 10.8], ['Westnorwegen', 60.5, 6.0], ['Trøndelag', 63.5, 10.5], ['Nordland', 66.5, 14.5], ['Finnmark', 70.0, 25.0], ['Svalbard', 78.5, 17.0], ['Troms', 69.3, 19.5]],
    FI: [['Helsinki', 60.2, 24.9], ['Lappland', 67.5, 26.0], ['Ostfinnland', 62.5, 29.0], ['Westfinnland', 62.5, 23.0], ['Oulu', 65.0, 26.0], ['Seenplatte', 61.8, 26.5]],
    KE: [['Nairobi', -1.3, 36.8], ['Mombasa (Küste)', -3.5, 39.5], ['Rift Valley', 0.5, 36.0], ['Nordkenia', 3.0, 38.5], ['Westkenia', 0.3, 34.8], ['Nordostkenia', 2.0, 40.5]],
    MA: [['Rabat', 34.0, -6.8], ['Casablanca', 33.6, -7.6], ['Marrakesch', 31.6, -8.0], ['Fès (Norden)', 34.3, -4.5], ['Souss', 29.5, -9.0], ['Ostmarokko', 32.5, -2.5]],
    TH: [['Bangkok', 13.8, 100.5], ['Nordthailand', 18.8, 99.0], ['Isan', 16.0, 103.0], ['Südthailand', 8.0, 99.5], ['Ostküste', 13.0, 101.8]],
    VN: [['Hanoi', 21.0, 105.8], ['Ho-Chi-Minh-Stadt', 10.8, 106.7], ['Zentralvietnam', 16.0, 108.0], ['Hochland', 13.0, 108.0], ['Mekong-Delta', 9.8, 105.5]],
    PH: [['Manila (Luzon)', 14.6, 121.0], ['Nordluzon', 17.0, 121.5], ['Visayas', 10.5, 123.5], ['Mindanao', 7.5, 125.0], ['Palawan', 9.8, 118.7]],
    MY: [['Kuala Lumpur', 3.1, 101.7], ['Johor', 2.0, 103.3], ['Sabah', 5.5, 117.0], ['Sarawak', 2.5, 113.0], ['Penang (Norden)', 5.5, 100.6]],
    NZ: [['Wellington', -41.3, 174.8], ['Auckland', -36.9, 174.8], ['Canterbury', -43.5, 171.5], ['Otago', -45.5, 169.5], ['Waikato', -38.0, 175.5]],
    BD: [['Dhaka', 23.8, 90.4], ['Chittagong', 22.4, 91.8], ['Rajshahi', 24.4, 88.6], ['Sylhet', 24.9, 91.9], ['Khulna', 22.8, 89.5]],
    KR: [['Seoul', 37.6, 127.0], ['Busan', 35.2, 129.0], ['Jeolla', 35.2, 126.9], ['Gangwon', 37.8, 128.3]],
    KP: [['Pjöngjang', 39.0, 125.8], ['Hamgyŏng', 41.5, 129.5], ['Kangwŏn', 38.8, 127.5], ['Ryanggang', 41.2, 128.0]],
    AE: [['Abu Dhabi', 24.0, 54.0], ['Dubai', 25.2, 55.3], ['Westregion', 23.5, 52.5]],
    AT: [['Wien', 48.2, 16.4], ['Tirol', 47.2, 11.3], ['Steiermark', 47.2, 15.2], ['Oberösterreich', 48.2, 14.0], ['Kärnten', 46.7, 14.0]],
    CH: [['Mittelland (Bern)', 47.0, 7.6], ['Zürich', 47.4, 8.6], ['Romandie', 46.4, 6.6], ['Graubünden', 46.7, 9.6], ['Tessin', 46.3, 8.9]],
    BE: [['Brüssel', 50.8, 4.4], ['Flandern', 51.0, 3.7], ['Wallonie', 50.3, 5.0]],
    NL: [['Randstad', 52.2, 4.6], ['Nordniederlande', 53.0, 6.3], ['Brabant', 51.5, 5.3]],
    DK: [['Seeland (Kopenhagen)', 55.6, 12.0], ['Jütland', 56.2, 9.2], ['Fünen', 55.3, 10.4]],
    CZ: [['Prag', 50.1, 14.4], ['Böhmen', 49.6, 13.5], ['Mähren', 49.4, 17.0]],
    HU: [['Budapest', 47.5, 19.0], ['Transdanubien', 47.0, 17.5], ['Große Tiefebene', 46.8, 20.5]],
    GR: [['Attika', 38.0, 23.7], ['Makedonien', 40.8, 22.8], ['Peloponnes', 37.5, 22.3], ['Kreta', 35.2, 24.9], ['Epirus', 39.6, 20.8]],
    PT: [['Lissabon', 38.8, -9.1], ['Norte (Porto)', 41.4, -8.3], ['Alentejo', 38.3, -7.8], ['Algarve', 37.1, -8.2]],
    IE: [['Dublin', 53.3, -6.3], ['Munster', 52.3, -8.8], ['Connacht', 53.7, -9.0], ['Ulster (Donegal)', 54.9, -7.9]],
    RO: [['Bukarest', 44.4, 26.1], ['Siebenbürgen', 46.5, 24.5], ['Moldau', 47.0, 27.0], ['Banat', 45.7, 21.5], ['Dobrudscha', 44.5, 28.5]],
  };
  const keyToId = {};
  for (const id in WORLD_MAP.key) keyToId[WORLD_MAP.key[id]] = id;
  const dots = {};
  WORLD_MAP.rows.forEach((row, y) => { for (let x = 0; x < row.length; x++) { const id = keyToId[row[x]]; if (id) (dots[id] = dots[id] || []).push([x, y]); } });
  const capXY = id => { const c = COUNTRY_COORDS[id]; return c ? [(c[1] + 180) / 360 * W, (WORLD_MAP.latTop - c[0]) / (WORLD_MAP.latTop - WORLD_MAP.latBottom) * H] : null; };
  for (const id of Object.keys(dots).sort()) {
    const pts = dots[id];
    const k = pts.length < 12 ? 1 : Math.max(2, Math.min(12, Math.round(1.5 + Math.log2(pts.length / 12))));
    // Startzentren: Hauptstadt, dann jeweils der am weitesten entfernte Punkt
    const toXY = (lat, lon) => [(lon + 180) / 360 * W, (WORLD_MAP.latTop - lat) / (WORLD_MAP.latTop - WORLD_MAP.latBottom) * H];
    const cap = NAMES[id] ? toXY(NAMES[id][0][1], NAMES[id][0][2]) : capXY(id) || pts[0];
    let cen = [pts.reduce((b, p) => Math.hypot(p[0] - cap[0], p[1] - cap[1]) < Math.hypot(b[0] - cap[0], b[1] - cap[1]) ? p : b, pts[0]).slice()];
    // Mit Regionsnamen: die Anker selbst als Startzentren (ergibt realistischere Regionen)
    if (NAMES[id] && NAMES[id].length >= k) cen = NAMES[id].slice(0, k).map(a => toXY(a[1], a[2]));
    while (cen.length < k) {
      let best = pts[0], bd = -1;
      for (const p of pts) { const d = Math.min(...cen.map(c => (c[0] - p[0]) ** 2 + (c[1] - p[1]) ** 2)); if (d > bd) { bd = d; best = p; } }
      cen.push(best.slice());
    }
    const asg = new Array(pts.length).fill(0);
    for (let it = 0; it < 10; it++) {
      pts.forEach((p, i) => { let bi = 0, bd = 1e9; cen.forEach((c, j) => { const d = (c[0] - p[0]) ** 2 + (c[1] - p[1]) ** 2; if (d < bd) { bd = d; bi = j; } }); asg[i] = bi; });
      cen = cen.map((c, j) => { let sx = 0, sy = 0, n = 0; pts.forEach((p, i) => { if (asg[i] === j) { sx += p[0]; sy += p[1]; n++; } }); return n ? [sx / n, sy / n] : c; });
    }
    // Splitter (Inseln, Exklaven) dem nächsten großen Zentrum zuschlagen
    for (;;) {
      const counts = cen.map((c, j) => asg.filter(a => a === j).length);
      const small = counts.findIndex(n => n < Math.max(3, pts.length * 0.03));
      if (small < 0 || cen.length < 2) break;
      cen.splice(small, 1);
      pts.forEach((p, i) => { let bi = 0, bd = 1e9; cen.forEach((c, j) => { const d = (c[0] - p[0]) ** 2 + (c[1] - p[1]) ** 2; if (d < bd) { bd = d; bi = j; } }); asg[i] = bi; });
      cen = cen.map((c, j) => { let sx = 0, sy = 0, n = 0; pts.forEach((p, i) => { if (asg[i] === j) { sx += p[0]; sy += p[1]; n++; } }); return n ? [sx / n, sy / n] : c; });
    }
    // Hauptstadtprovinz = Zentrum, das der Hauptstadt am nächsten liegt
    let capDot = 0; pts.forEach((p, i) => { if (Math.hypot(p[0] - cap[0], p[1] - cap[1]) < Math.hypot(pts[capDot][0] - cap[0], pts[capDot][1] - cap[1])) capDot = i; });
    const capIdx = asg[capDot];
    const mx = pts.reduce((a, p) => a + p[0], 0) / pts.length, my = pts.reduce((a, p) => a + p[1], 0) / pts.length;
    const used = {}, anchorName = {};
    const anchors = NAMES[id];
    if (anchors && k > 1) {
      const ll = c => [WORLD_MAP.latTop - c[1] / H * (WORLD_MAP.latTop - WORLD_MAP.latBottom), c[0] / W * 360 - 180];
      const pairs = [];
      cen.forEach((c, j) => { const [la, lo] = ll(c); anchors.forEach((a, ai) => pairs.push([Math.hypot(a[1] - la, (a[2] - lo) * Math.cos(la * Math.PI / 180)), j, ai])); });
      pairs.sort((a, b) => a[0] - b[0]);
      const taken = new Set([0]);
      anchorName[capIdx] = anchors[0][0];
      // nur passende Anker (≤ 10°) übernehmen
      for (const [d, j, ai] of pairs) if (d <= 10 && !anchorName[j] && !taken.has(ai)) { anchorName[j] = anchors[ai][0]; taken.add(ai); }
      // sonst: nächster Anker + Himmelsrichtung, sehr weit weg = Übersee
      cen.forEach((c, j) => {
        if (anchorName[j]) return;
        const [la, lo] = ll(c);
        let best = null, bd = 1e9;
        for (const a of anchors) { const d = Math.hypot(a[1] - la, (a[2] - lo) * Math.cos(la * Math.PI / 180)); if (d < bd) { bd = d; best = a; } }
        if (bd > 25) { anchorName[j] = 'Überseegebiete'; return; }
        const dy = la - best[1], dx = (lo - best[2]) * Math.cos(la * Math.PI / 180);
        anchorName[j] = `${best[0]} ${Math.abs(dy) > Math.abs(dx) ? (dy > 0 ? 'Nord' : 'Süd') : (dx > 0 ? 'Ost' : 'West')}`;
      });
    }
    const provs = cen.map((c, j) => {
      const n = asg.filter(a => a === j).length;
      let name;
      if (k === 1) name = 'Kernland';
      else if (j === capIdx) name = 'Hauptstadtregion';
      else {
        const dx = c[0] - mx, dy = my - c[1];
        name = Math.hypot(dx, dy) < 1.5 ? 'Zentrum' : DIRS[Math.round(((Math.atan2(dy, dx) * 180 / Math.PI + 360) % 360) / 45) % 8];
      }
      if (anchorName[j]) name = anchorName[j];
      used[name] = (used[name] || 0) + 1;
      if (used[name] > 1) name += ' ' + ['', 'I', 'II', 'III', 'IV', 'V'][used[name]];
      return { id: `${id}-${j}`, country: id, name, x: c[0], y: c[1], dots: n, capital: j === capIdx };
    });
    // Wirtschaftsanteil: Hauptstadtregion zählt doppelt, große leere Flächen weniger (Wurzel)
    const raw = provs.map(p => Math.sqrt(p.dots) * (p.capital ? 2 : 1)), sum = raw.reduce((a, b) => a + b, 0);
    provs.forEach((p, j) => { p.share = raw[j] / sum; });
    const base = list.length;
    pts.forEach((p, i) => { grid[p[1] * W + p[0]] = base + asg[i]; });
    list.push(...provs);
    byCountry[id] = provs;
  }
  return { list, byCountry, grid, at: (x, y) => (x >= 0 && y >= 0 && x < W && y < H ? list[grid[y * W + x]] || null : null), byId: id => list.find(p => p.id === id) };
})();
