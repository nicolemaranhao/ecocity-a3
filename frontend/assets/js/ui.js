/* EcoCity — utilidades de interface: logo animada, ícones, gráficos SVG animados, toasts e efeitos */
const UI = (() => {
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const num = (v, d = 1) => (v == null || isNaN(v) ? '—' : Number(v).toLocaleString('pt-BR', { minimumFractionDigits: d, maximumFractionDigits: d }));
  const COR = { verde: '#2F8F3F', azul: '#1D5FA8', laranja: '#E8892B', ceu: '#4FB3E3', navy: '#163E6E', critico: '#D94848' };
  const SERV = {
    'Água': { cor: '#2E8FCB', classe: 'ceu', ico: 'gota' }, 'Energia': { cor: '#D9822B', classe: 'laranja', ico: 'sol' },
    'Resíduos': { cor: '#3E9A4E', classe: 'verde', ico: 'folha' }, 'Mobilidade': { cor: '#2B4C8C', classe: '', ico: 'onibus' },
  };
  const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  const mesTxt = (am) => (am ? `${MESES[Number(am.slice(5, 7)) - 1]}/${am.slice(2, 4)}` : '');
  const iniciais = (n) => String(n || '?').split(' ').filter(Boolean).slice(0, 2).map((p) => p[0]).join('').toUpperCase();
  const reduzido = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ------------------------------------------------------------ logo (a mesma da marca)
  function logo({ anim = false, palavra = false, classe = '' } = {}) {
    const t = (d, i) => `<path class="traco" style="--i:${i}" pathLength="600" fill="none" stroke="#fff" stroke-width="12" stroke-linecap="round" stroke-linejoin="round" d="${d}"/>`;
    return `<svg class="${anim ? 'logo-anim' : ''} ${classe}" viewBox="${palavra ? '30 30 340 430' : '30 30 340 340'}" role="img" aria-label="EcoCity">
      <rect class="ladrilho" x="36" y="36" width="160" height="160" rx="24" fill="#2F8F3F"/><rect class="ladrilho" x="204" y="36" width="160" height="160" rx="24" fill="#1D5FA8"/>
      <rect class="ladrilho" x="36" y="204" width="160" height="160" rx="24" fill="#E8892B"/><rect class="ladrilho" x="204" y="204" width="160" height="160" rx="24" fill="#4FB3E3"/>
      ${t('M62 180 C58 110 110 64 228 62 C224 138 162 182 62 180 Z', 0)}${t('M68 174 C112 132 160 98 210 72', 1)}
      ${t('M228 62 C262 96 322 120 322 152 A40 40 0 0 1 242 152 C242 124 240 94 228 62 Z', 2)}${t('M262 156 C266 168 274 174 286 176', 3)}
      <g transform="translate(0 14)">${t('M56 318 H344', 4)}${t('M78 318 A40 40 0 0 1 158 318', 5)}
      ${t('M65.4 298.8 L48.5 292.7 M85.9 272.1 L75.6 257.4 M118.0 262.0 L118.0 244.0 M150.1 272.1 L160.4 257.4 M170.6 298.8 L187.5 292.7', 6)}
      ${t('M226 318 V268 H252 V318 M260 318 V232 H294 V318 M302 318 V278 H330 V318', 7)}
      <g fill="#fff"><rect x="271" y="248" width="12" height="12" rx="3"/><rect x="271" y="270" width="12" height="12" rx="3"/><rect x="271" y="292" width="12" height="12" rx="3"/></g></g>
      ${palavra ? '<text x="200" y="446" text-anchor="middle" font-family="Plus Jakarta Sans, Inter" font-weight="800" font-size="68" letter-spacing="-2"><tspan fill="#2F8F3F">Eco</tspan><tspan fill="#163E6E">City</tspan></text>' : ''}
    </svg>`;
  }
  const marca = (href = '#/') => `<a class="marca" href="${href}">${logo()}<span><b>Eco</b><span>City</span></span></a>`;

  // ------------------------------------------------------------ ícones (traço)
  const I = {
    gota: '<path class="anima" d="M12 3c3 4 6 7 6 11a6 6 0 0 1-12 0c0-4 3-7 6-11z"/>',
    sol: '<g class="anima"><circle cx="12" cy="13" r="4"/><path d="M12 3v2M4.9 6.9l1.4 1.4M3 14h2M19 14h2M17.7 8.3l1.4-1.4M7 21h10"/></g>',
    folha: '<path class="anima" d="M5 19c0-8 5-14 15-14 0 9-6 14-15 14zM5 19 13 11"/>',
    onibus: '<g class="anima"><rect x="5" y="3" width="14" height="14" rx="3"/><path d="M5 11h14M8 17v3M16 17v3"/><circle cx="8.5" cy="14" r=".6"/><circle cx="15.5" cy="14" r=".6"/></g>',
    painel: '<rect x="3" y="3" width="7" height="9" rx="2"/><rect x="14" y="3" width="7" height="5" rx="2"/><rect x="14" y="12" width="7" height="9" rx="2"/><rect x="3" y="16" width="7" height="5" rx="2"/>',
    radar: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><path d="M12 12 18 6"/><circle cx="12" cy="12" r="1.2"/>',
    livro: '<path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z"/><path d="M4 19V5M9 7h6M9 11h6"/>',
    alvo: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5"/>',
    escudo: '<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/><path d="m9 12 2 2 4-4"/>',
    sair: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
    chat: '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/><path d="M8.5 11h.01M12 11h.01M15.5 11h.01"/>',
    enviar: '<path d="m22 2-7 20-4-9-9-4z"/><path d="M22 2 11 13"/>',
    banco: '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>',
    robo: '<rect x="4" y="8" width="16" height="12" rx="3"/><path d="M12 4v4M9 13h.01M15 13h.01M9 17h6"/><circle cx="12" cy="3" r="1"/>',
    cerebro: '<path d="M9 4a3 3 0 0 0-3 3 3 3 0 0 0-2 5 3 3 0 0 0 2 5 3 3 0 0 0 6 1V5a2 2 0 0 0-3-1zM15 4a3 3 0 0 1 3 3 3 3 0 0 1 2 5 3 3 0 0 1-2 5 3 3 0 0 1-6 1"/>',
    pessoa: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    nuvem: '<path d="M7 18a5 5 0 1 1 1-9.9A6 6 0 0 1 19.5 10 4 4 0 0 1 18 18z"/>',
    calendario: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4M8 14h2M14 14h2M8 17h2"/>',
    balanca: '<path d="M12 3v18M5 21h14M5 7h14M5 7l-3 7a3 3 0 0 0 6 0zM19 7l-3 7a3 3 0 0 0 6 0z"/>',
    mapa: '<path d="m9 4-6 2v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
    controles: '<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/>',
    trofeu: '<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0z"/><path d="M17 5h3a3 3 0 0 1-3 4M7 5H4a3 3 0 0 0 3 4"/>',
    lab: '<path d="M9 3h6M10 3v6L4 19a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2l-6-10V3"/><path d="M7 14h10"/>',
    bussola: '<circle cx="12" cy="12" r="9"/><path d="m15.5 8.5-2 5-5 2 2-5z"/>',
    sala: '<path d="M3 21V9l9-6 9 6v12"/><path d="M9 21v-6h6v6"/>',
    cofre: '<path d="M12 2v3M5 7h14l-1 13H6z"/><path d="M9 11h6M9 15h6"/>',
    fonte: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6M8 13h8M8 17h5"/>',
    sino: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0"/>',
    predio: '<path d="M4 21V5l8-3v19M12 21V9l8 3v9M8 7v.01M8 11v.01M8 15v.01M16 15v.01"/>',
    caneta: '<path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
    flecha: '<path d="M5 12h14M13 6l6 6-6 6"/>',
    usuarios: '<circle cx="9" cy="8" r="4"/><path d="M2 21a7 7 0 0 1 14 0M16 4a4 4 0 0 1 0 8M22 21a7 7 0 0 0-4-6.3"/>',
  };
  const ico = (n, cor = 'currentColor', w = 2) => `<svg viewBox="0 0 24 24" fill="none" stroke="${cor}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${I[n] || ''}</svg>`;

  // ------------------------------------------------------------ toasts e progresso
  function toast(msg, tipo = '') {
    const el = document.createElement('div');
    el.className = `toast ${tipo}`; el.innerHTML = `<span>${tipo === 'ok' ? '✓' : tipo === 'erro' ? '!' : '•'}</span>${esc(msg)}`;
    $('#toasts').append(el);
    setTimeout(() => { el.classList.add('sai'); setTimeout(() => el.remove(), 400); }, 4200);
  }
  let carregando = 0;
  function progresso(on) {
    carregando += on ? 1 : -1; const p = $('#progresso');
    if (carregando > 0) { p.style.opacity = 1; p.style.width = '70%'; }
    else { p.style.width = '100%'; setTimeout(() => { p.style.opacity = 0; p.style.width = 0; }, 350); }
  }

  // ------------------------------------------------------------ animações de entrada
  let obs;
  function revelar(raiz = document) {
    obs ||= new IntersectionObserver((ents) => ents.forEach((e) => {
      if (!e.isIntersecting) return;
      e.target.classList.add('visivel');
      e.target.dispatchEvent(new CustomEvent('visivel'));
      obs.unobserve(e.target);
    }), { threshold: 0.15, rootMargin: '0px 0px -40px 0px' });
    $$('.revelar:not(.visivel)', raiz).forEach((el) => (reduzido ? el.classList.add('visivel') : obs.observe(el)));
    $$('[data-contar]', raiz).forEach(contador);
    $$('.tilt', raiz).forEach(tilt);
  }
  function contador(el) {
    if (el._ok) return; el._ok = true;
    const alvo = Number(el.dataset.contar); const dec = Number(el.dataset.dec || 0);
    const rodar = () => {
      if (reduzido) { el.textContent = num(alvo, dec); return; }
      const t0 = performance.now(); const dur = 1600;
      const passo = (t) => { const p = Math.min(1, (t - t0) / dur); const e = 1 - (1 - p) ** 4; el.textContent = num(alvo * e, dec); if (p < 1) requestAnimationFrame(passo); };
      requestAnimationFrame(passo);
    };
    const io = new IntersectionObserver(([e]) => { if (e.isIntersecting) { rodar(); io.disconnect(); } });
    io.observe(el);
  }
  // cartões com inclinação 3D que segue o mouse
  function tilt(el) {
    if (el._tilt || reduzido || matchMedia('(hover: none)').matches) return; el._tilt = true;
    el.addEventListener('mousemove', (e) => {
      const r = el.getBoundingClientRect(); const x = (e.clientX - r.left) / r.width - 0.5; const y = (e.clientY - r.top) / r.height - 0.5;
      el.style.transform = `perspective(900px) rotateY(${x * 8}deg) rotateX(${-y * 8}deg) translateY(-4px)`;
    });
    el.addEventListener('mouseleave', () => { el.style.transform = ''; });
  }

  // ------------------------------------------------------------ gráficos SVG
  const classeCor = { EXCELENTE: COR.verde, BOM: COR.azul, REGULAR: COR.laranja, CRITICO: COR.critico };
  function medidor(valor, classe) {
    const L = 251.3; // comprimento do arco (meio círculo r=80)
    const id = 'g' + Math.random().toString(36).slice(2, 7);
    setTimeout(() => { const a = document.getElementById(id); if (a) a.style.strokeDashoffset = L * (1 - valor / 100); }, 60);
    return `<div class="medidor"><svg viewBox="0 0 200 120"><defs><linearGradient id="${id}g" x1="0" x2="1"><stop offset="0" stop-color="#D94848"/><stop offset=".45" stop-color="#E8892B"/><stop offset=".7" stop-color="#1D5FA8"/><stop offset="1" stop-color="#2F8F3F"/></linearGradient></defs>
      <path d="M20 105 A80 80 0 0 1 180 105" fill="none" stroke="#EAF0F7" stroke-width="16" stroke-linecap="round"/>
      <path id="${id}" class="arco" d="M20 105 A80 80 0 0 1 180 105" fill="none" stroke="url(#${id}g)" stroke-width="16" stroke-linecap="round" stroke-dasharray="${L}" stroke-dashoffset="${L}"/></svg>
      <div class="valor"><b data-contar="${valor}" data-dec="1">0</b><span class="classe-${classe}">${esc(classe)}</span></div></div>`;
  }
  function anel(valor, cor, rotulo, sub) {
    const C = 2 * Math.PI * 26; const id = 'a' + Math.random().toString(36).slice(2, 7);
    setTimeout(() => { const a = document.getElementById(id); if (a) a.style.strokeDashoffset = C * (1 - Math.max(0, Math.min(100, valor)) / 100); }, 80);
    return `<div class="anel"><svg viewBox="0 0 64 64"><circle cx="32" cy="32" r="26" fill="none" stroke="#EEF2F7" stroke-width="8"/>
      <circle id="${id}" class="v" cx="32" cy="32" r="26" fill="none" stroke="${cor}" stroke-width="8" stroke-linecap="round" stroke-dasharray="${C}" stroke-dashoffset="${C}"/></svg>
      <div><b data-contar="${valor}" data-dec="0">0</b><small>${esc(rotulo)}</small>${sub ? `<div style="font-size:12px;color:var(--tinta-3)">${esc(sub)}</div>` : ''}</div></div>`;
  }
  function spark(vals, cor, atraso = 0) {
    const v = vals.filter((x) => x != null); if (v.length < 2) return '';
    const W = 200, H = 46, mn = Math.min(...v), mx = Math.max(...v), r = mx - mn || 1;
    const pts = v.map((x, i) => [i * (W / (v.length - 1)), H - 4 - ((x - mn) / r) * (H - 8)]);
    const d = pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ');
    const ult = pts[pts.length - 1];
    return `<svg class="spark" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"><path d="${d} L${W},${H} L0,${H} Z" fill="${cor}" opacity=".08"/>
      <path class="l" style="--atraso:${atraso}s" pathLength="1" d="${d}" fill="none" stroke="${cor}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"/>
      <circle cx="${ult[0]}" cy="${ult[1]}" r="3.5" fill="${cor}"/></svg>`;
  }
  // escala "bonita" para o eixo Y
  function escalaY(vals, meta) {
    const v = vals.filter((x) => x != null && !isNaN(x)); if (meta != null) v.push(meta);
    let mn = Math.min(...v), mx = Math.max(...v); const folga = (mx - mn || Math.abs(mx) || 1) * 0.15;
    mn = Math.max(0, mn - folga); mx += folga;
    const passo = 10 ** Math.floor(Math.log10((mx - mn) / 4 || 1)); const k = [1, 2, 2.5, 5, 10].find((m) => (mx - mn) / (passo * m) <= 5) * passo;
    return { min: Math.floor(mn / k) * k, max: Math.ceil(mx / k) * k, passo: k };
  }
  // gráfico de linha com eixo, linha da meta, legenda e dica ao passar o mouse
  function linha(series, { altura = 260, largura = 680, rotulos = [], meta = null, unidade = '', casas = 1, min, max, origens = null, refOficial = null } = {}) {
    // refOficial = { valor, rotulo }: linha tracejada com o último dado OFICIAL (quando ele é mais antigo que o gráfico)
    const W = largura, H = altura, P = { l: 46, r: 16, t: 16, b: 30 };
    const todos = [...series.flatMap((s) => s.valores), ...(refOficial ? [refOficial.valor] : [])];
    const e = min != null && max != null ? { min, max, passo: (max - min) / 4 } : escalaY(todos, meta);
    const n = Math.max(...series.map((s) => s.valores.length));
    const x = (i) => P.l + (i * (W - P.l - P.r)) / Math.max(1, n - 1);
    const y = (v) => P.t + (1 - (v - e.min) / (e.max - e.min || 1)) * (H - P.t - P.b);
    let g = '';
    for (let v = e.min; v <= e.max + 1e-9; v += e.passo) g += `<line class="grade-l" x1="${P.l}" x2="${W - P.r}" y1="${y(v)}" y2="${y(v)}"/><text x="${P.l - 8}" y="${y(v) + 4}" text-anchor="end">${num(v, e.passo < 1 ? 1 : 0)}</text>`;
    const passoR = Math.ceil(n / 7);
    rotulos.forEach((r, i) => { if (i % passoR === 0 || i === n - 1) g += `<text x="${x(i)}" y="${H - 8}" text-anchor="middle">${esc(r)}</text>`; });
    if (refOficial) g += `<line class="of-l" x1="${P.l}" x2="${W - P.r}" y1="${y(refOficial.valor)}" y2="${y(refOficial.valor)}"/><text class="of-t" x="${P.l + 6}" y="${y(refOficial.valor) - 6}">último oficial (${esc(refOficial.rotulo)}): ${num(refOficial.valor, casas)}</text>`;
    if (meta != null) g += `<line class="meta-l" x1="${P.l}" x2="${W - P.r}" y1="${y(meta)}" y2="${y(meta)}"/><text class="meta-t" x="${W - P.r - 4}" y="${y(meta) - 6}" text-anchor="end">meta ${num(meta, casas)}</text>`;
    const caminhos = series.map((s, k) => {
      const pts = s.valores.map((v, i) => (v == null ? null : [x(i), y(v)])).filter(Boolean);
      if (!pts.length) return '';
      const d = pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ');
      const gid = `gr${Math.random().toString(36).slice(2, 7)}`;
      const ult = pts[pts.length - 1];
      return `${s.area ? `<defs><linearGradient id="${gid}" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="${s.cor}" stop-opacity=".28"/><stop offset="1" stop-color="${s.cor}" stop-opacity="0"/></linearGradient></defs><path class="area-g" d="${d} L${ult[0]},${y(e.min)} L${pts[0][0]},${y(e.min)} Z" fill="url(#${gid})"/>` : ''}
        ${s.tracejado ? `<path d="${d}" fill="none" stroke="${s.cor}" stroke-width="${s.espessura || 2}" stroke-dasharray="5 6" stroke-linecap="round" class="area-g"/>`
          : `<path class="serie" style="--atraso:${k * 0.15}s" pathLength="1" d="${d}" fill="none" stroke="${s.cor}" stroke-width="${s.espessura || 3}" stroke-linecap="round" stroke-linejoin="round"/>`}
        ${origens && k === 0 ? s.valores.map((v, i) => (v == null ? '' : `<circle class="pt-orig o-${origens[i]}" cx="${x(i)}" cy="${y(v)}" r="${origens[i] === 'ESTIMADO' ? 3.6 : 4.2}" ${origens[i] === 'ESTIMADO' ? `fill="#fff" stroke="${s.cor}"` : `fill="${s.cor}" stroke="#fff"`} stroke-width="1.8"/>`)).join('')
          : s.tracejado ? '' : `<circle class="ponto-fim" cx="${ult[0]}" cy="${ult[1]}" r="5" fill="${s.cor}" stroke="#fff" stroke-width="2.5"/>`}`;
    }).join('');
    const dados = { r: rotulos, s: series.map((s) => ({ n: s.nome || '', c: s.cor, v: s.valores })), u: unidade, d: casas, x: [...Array(n)].map((_, i) => x(i) / W), meta, o: origens };
    const leg = series.length > 1 || meta != null || origens ? `<div class="legenda">${series.map((s) => `<span><i style="background:${s.cor};${s.tracejado ? 'height:2px;' : ''}"></i>${esc(s.nome || '')}</span>`).join('')}${meta != null ? '<span><i class="tr"></i>meta</span>' : ''}${origens ? `<span class="lg-o"><b class="cheio" style="background:${series[0].cor}"></b>oficial</span><span class="lg-o"><b class="vazio" style="border-color:${series[0].cor}"></b>estimado</span>` : ''}</div>` : '';
    return `<div class="graf" data-g='${esc(JSON.stringify(dados))}'>${leg}<svg class="grafico" viewBox="0 0 ${W} ${H}">${g}${caminhos}<line class="cursor" x1="0" x2="0" y1="${P.t}" y2="${H - P.b}"/></svg><div class="dica"></div></div>`;
  }
  function ativarGraficos(raiz = document) {
    $$('.graf:not([data-ok])', raiz).forEach((el) => {
      el.dataset.ok = 1; const d = JSON.parse(el.dataset.g); const svg = $('svg', el); const dica = $('.dica', el); const cur = $('.cursor', el);
      const mover = (ev) => {
        const r = svg.getBoundingClientRect(); const fx = (ev.clientX - r.left) / r.width;
        let i = 0; d.x.forEach((v, k) => { if (Math.abs(v - fx) < Math.abs(d.x[i] - fx)) i = k; });
        const W = svg.viewBox.baseVal.width; cur.setAttribute('x1', d.x[i] * W); cur.setAttribute('x2', d.x[i] * W); cur.style.opacity = 1;
        dica.innerHTML = `<b>${esc(d.r[i] || '')}</b>${d.s.map((s) => (s.v[i] == null ? '' : `<div><i style="background:${s.c}"></i>${esc(s.n)} <b>${num(s.v[i], d.d)}</b> ${esc(d.u)}</div>`)).join('')}${d.meta != null ? `<div class="m">meta ${num(d.meta, d.d)}</div>` : ''}${d.o ? `<div class="o o-${d.o[i]}">${{ REAL: 'dado oficial', DERIVADO: 'calculado de oficial', ESTIMADO: 'estimativa' }[d.o[i]] || ''}</div>` : ''}`;
        dica.style.opacity = 1; const left = d.x[i] * r.width; dica.style.left = `${Math.min(r.width - 170, Math.max(0, left + 14))}px`;
      };
      svg.addEventListener('mousemove', mover); svg.addEventListener('touchstart', (e) => mover(e.touches[0]), { passive: true });
      svg.addEventListener('mouseleave', () => { dica.style.opacity = 0; cur.style.opacity = 0; });
    });
  }
  // barras horizontais (comparação entre cidades) com marca da meta
  function barrasH(itens, { meta = null, unidade = '', casas = 1, sentido = 'MAIOR_MELHOR', refNome = 'meta' } = {}) {
    const mx = Math.max(...itens.map((i) => i.valor), meta || 0) * 1.08 || 1;
    return `<div class="barras-h">${itens.map((it, i) => {
      const ok = meta == null ? null : sentido === 'MAIOR_MELHOR' ? it.valor >= meta : it.valor <= meta;
      return `<div class="bh ${it.destaque ? 'sel' : ''}"><span class="r">${esc(it.rotulo)}</span><span class="t"><i style="--w:${(it.valor / mx) * 100}%;--atraso:${i * 0.06}s;background:${it.cor || (ok == null ? COR.azul : ok ? COR.verde : COR.laranja)}"></i>${meta != null ? `<em style="left:${(meta / mx) * 100}%" title="${refNome} ${num(meta, casas)}"></em>` : ''}</span><b class="num">${num(it.valor, casas)}<small> ${esc(unidade)}</small></b></div>`;
    }).join('')}${meta != null ? `<div class="bh-leg"><em></em> linha = ${refNome} (${num(meta, casas)} ${esc(unidade)}) · <i style="background:${COR.verde}"></i> ${refNome === 'meta' ? 'na meta' : 'melhor que a média'} · <i style="background:${COR.laranja}"></i> ${refNome === 'meta' ? 'fora da meta' : 'pior que a média'}</div>` : ''}</div>`;
  }
  // explicações rápidas (botão "?" ao lado de nota, meta, risco, oficial/estimado)
  const EXPLICA = {
    nota: ['O que é a nota EcoCity (0 a 100)?', 'Ela resume os 8 números da cidade em um só. Cada número é comparado com a sua <b>meta</b>: se cumpre, vale 100; a cada 1% longe da meta perde 1,5 ponto. A nota da cidade é a média dos 8 (perdas de água, energia solar, reciclagem e emissões pesam um pouco mais). <b>85+</b> excelente · <b>70 a 84</b> bom · <b>55 a 69</b> regular · <b>abaixo de 55</b> crítico.'],
    notaIndicador: ['O que é a nota de um número?', 'Mostra quão perto da meta o número está: <b>100</b> = cumpriu a meta; a cada 1% longe da meta, perde 1,5 ponto (mínimo 0). Ex.: 20% acima do limite de água → nota 70.'],
    notaArea: ['O que é a nota de uma área?', 'É a média das notas dos 2 números da área (ex.: Água = consumo por pessoa + perdas). <b>Bom</b>: 85 ou mais · <b>Atenção</b>: 55 a 84 · <b>Crítico</b>: abaixo de 55.'],
    meta: ['O que é a meta?', 'É o valor-alvo de cada número. Um gestor propõe, um analista dá o parecer técnico e <b>outro</b> gestor aprova. Só gestores e analistas veem as metas.'],
    risco: ['Como o risco é calculado?', 'Junta duas coisas: as metas que a cidade <b>não</b> cumpre (cada uma soma 7) e os alertas abertos da IA (cada crítico soma 6, cada atenção soma 2). <b>Alto</b> a partir de 50 · <b>médio</b> de 30 a 49 · <b>baixo</b> abaixo de 30.'],
    origem: ['Oficial ou estimado?', '<b>Oficial do mês</b>: número publicado pela fonte (ANEEL, SPTrans) para aquele mês. <b>Oficial do ano</b>: a fonte (SNIS, SINISA, SEEG) publica o total do ano e o EcoCity divide pelos meses. <b>Estimado</b>: não existe número oficial da cidade; o EcoCity estima a partir de uma série oficial maior (ex.: energia do Estado).'],
  };
  const info = (k) => `<button type="button" class="info-btn" data-info="${k}" aria-label="${esc(EXPLICA[k]?.[0] || 'Ajuda')}">?</button>`;
  document.addEventListener?.('click', (e) => {
    const b = e.target.closest?.('[data-info]'); const aberto = document.querySelector('.info-pop');
    if (aberto && !e.target.closest('.info-pop')) aberto.remove();
    if (!b) return;
    e.preventDefault(); e.stopPropagation();
    const [t, x] = EXPLICA[b.dataset.info] || ['', '']; const p = document.createElement('div'); p.className = 'info-pop'; p.setAttribute('role', 'dialog');
    p.innerHTML = `<b>${esc(t)}</b><p>${x}</p>`; document.body.append(p);
    const r = b.getBoundingClientRect(); p.style.top = `${r.bottom + window.scrollY + 8}px`; p.style.left = `${Math.max(12, Math.min(window.innerWidth - p.offsetWidth - 12, r.left + window.scrollX - 20))}px`;
  });
  // pictograma: um ícone para cada "unidade" (ex.: 1 galão = 20 litros), com marca da meta
  function pictos(valor, porIcone, icone, { meta = null, cor = COR.azul, max = 40, menorMelhor = true } = {}) {
    const n = Math.min(max, Math.round(valor / porIcone)); const m = meta != null ? Math.round(meta / porIcone) : null;
    return `<div class="pictos">${[...Array(Math.max(n, m || 0))].map((_, i) => `<span class="${i < n ? 'cheio' : 'vazio'} ${menorMelhor && m != null && i >= m && i < n ? 'excesso' : ''} ${!menorMelhor && i >= n ? 'falta' : ''} ${m != null && i === m - 1 ? 'limite' : ''}" style="--atraso:${i * 0.03}s;--c:${cor}">${icone}</span>`).join('')}</div>`;
  }
  // waffle 10x10: "de cada 100…"
  function waffle(pct, cor = COR.verde, corResto = '#E3EAF3') {
    const k = Math.round(Math.max(0, Math.min(100, pct)));
    return `<div class="waffle">${[...Array(100)].map((_, i) => `<i style="--atraso:${(i % 10) * 0.02 + Math.floor(i / 10) * 0.03}s;background:${i < k ? cor : corResto}"></i>`).join('')}</div>`;
  }
  // colunas (meses) — pequenas e coloridas
  function colunas(vals, rotulos, cor = COR.azul, { meta = null, sentido = 'MENOR_MELHOR', casas = 1, origens = null, oficialAntes = null } = {}) {
    // oficialAntes = { valor, rotulo }: o último dado OFICIAL, quando ele é mais antigo que os meses do gráfico
    const v = vals.filter((x) => x != null); const mx = Math.max(...v, meta || 0, oficialAntes?.valor || 0) * 1.1 || 1;
    const antes = oficialAntes ? `<div class="col-of" title="Último dado oficial (${esc(oficialAntes.rotulo)}): ${num(oficialAntes.valor, casas)}"><i style="--h:${((oficialAntes.valor / mx) * 120).toFixed(1)}px;background:${cor}"></i><small>${esc(oficialAntes.rotulo)}</small><span>último oficial</span></div><div class="col-sep" aria-hidden="true"></div>` : '';
    return `<div class="colunas${oficialAntes ? ' com-of' : ''}">${antes}${vals.map((x, i) => { const ok = meta == null ? true : sentido === 'MAIOR_MELHOR' ? x >= meta : x <= meta;
      const est = origens?.[i] === 'ESTIMADO';
      return `<div title="${esc(rotulos[i])}: ${num(x, casas)}${origens ? ` · ${est ? 'estimativa' : 'oficial'}` : ''}"><i class="${est ? 'est' : ''}" style="--h:${((x / mx) * 120).toFixed(1)}px;--atraso:${i * 0.04}s;background:${ok ? cor : '#E2B07E'}"></i><small>${esc(rotulos[i])}</small></div>`; }).join('')}${meta != null ? `<em style="bottom:calc(22px + ${((meta / mx) * 120).toFixed(1)}px)"><b>meta</b></em>` : ''}</div>${origens ? `<div class="col-leg"><span><i style="background:${cor}"></i>oficial</span><span><i class="est" style="background:${cor}"></i>estimado</span></div>` : ''}`;
  }
  // "cidade de dados" em 3D (CSS puro): cada prédio é um indicador; a altura mostra quão perto da meta ele está
  function cidade3d(itens, { colunas = 4, legenda = ['altura = quão perto da meta', 'contorno = a meta'] } = {}) {
    const L = 50, G = 20, H = 96;
    const linhas = Math.ceil(itens.length / colunas);
    const W = colunas * L + (colunas - 1) * G, D = linhas * L + (linhas - 1) * G;
    return `<div class="c3d" data-c3d><div class="c3d-cena" style="width:${W + 40}px;height:${D + 40}px"><div class="c3d-base"></div>
      ${itens.map((it, k) => { const x = 20 + (k % colunas) * (L + G), y = 20 + Math.floor(k / colunas) * (L + G); const h = Math.max(6, Math.min(100, it.valor)) / 100 * H;
        return `<div class="p3" style="left:${x}px;top:${y}px;--h:${h.toFixed(1)}px;--c:${it.cor};--atraso:${k * 0.09}s" title="${esc(it.nome)}: ${esc(it.txt || '')}">
          <i class="f"></i><i class="s"></i><i class="t"></i><i class="m" style="--hm:${H}px"></i></div>`; }).join('')}</div>
      <p class="c3d-leg"><span><i class="cheio"></i>${esc(legenda[0])}</span><span><i class="meta"></i>${esc(legenda[1])}</span></p></div>`;
  }
  function ativar3d(raiz = document) {
    $$('[data-c3d]:not([data-ok])', raiz).forEach((el) => {
      el.dataset.ok = 1; if (reduzido || matchMedia('(hover: none)').matches) return;
      el.addEventListener('mousemove', (e) => { const r = el.getBoundingClientRect(); const x = (e.clientX - r.left) / r.width - 0.5; const y = (e.clientY - r.top) / r.height - 0.5; el.style.setProperty('--rz', `${-40 + x * 18}deg`); el.style.setProperty('--rx', `${58 - y * 10}deg`); });
      el.addEventListener('mouseleave', () => { el.style.removeProperty('--rz'); el.style.removeProperty('--rx'); });
    });
  }
  // rosca (partes de um todo)
  function rosca(partes, centro = '', sub = '') {
    const tot = partes.reduce((a, p) => a + p.valor, 0) || 1; const C = 2 * Math.PI * 40; let acc = 0;
    return `<div class="rosca"><svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" fill="none" stroke="#EEF2F7" stroke-width="14"/>${partes.map((p, i) => {
      const l = (p.valor / tot) * C; const el = `<circle class="fatia" style="--atraso:${i * 0.15}s;--l:${l}" cx="50" cy="50" r="40" fill="none" stroke="${p.cor}" stroke-width="14" stroke-dasharray="${l} ${C}" stroke-dashoffset="${-acc}" transform="rotate(-90 50 50)"><title>${esc(p.rotulo)}: ${Math.round((p.valor / tot) * 100)}%</title></circle>`; acc += l; return el;
    }).join('')}</svg><div class="c"><b>${esc(centro)}</b><small>${esc(sub)}</small></div></div>
    <div class="rosca-leg">${partes.map((p) => `<span><i style="background:${p.cor}"></i>${esc(p.rotulo)} <b>${Math.round((p.valor / tot) * 100)}%</b></span>`).join('')}</div>`;
  }
  function barrasRanking(lista, { borrarApos = Infinity, clicavel = false, sel = null } = {}) {
    return lista.map((c, i) => {
      const cor = classeCor[c.classificacao] || COR.azul;
      return `<div class="barra ${i >= borrarApos ? 'borrada' : ''} ${sel === c.id_municipio ? 'sel' : ''}" ${clicavel ? `data-mun="${c.id_municipio}" role="button" tabindex="0"` : ''}>
        <span class="pos">${c.posicao}º</span><span>${esc(c.municipio)}</span>
        <span class="trilho"><i style="--c1:${cor};--c2:${cor}aa;--atraso:${i * 0.08}s" data-w="${c.ies}"></i></span><b class="num">${num(c.ies)}</b></div>`;
    }).join('');
  }
  function animarBarras(raiz) { requestAnimationFrame(() => setTimeout(() => $$('.trilho i[data-w]', raiz).forEach((i) => { i.style.width = `${i.dataset.w}%`; }), 80)); }

  // ------------------------------------------------------------ texto simples com **negrito** e quebras
  const md = (t) => esc(t).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/^#{1,3} (.+)$/gm, '<b>$1</b>');
  // Markdown simples: títulos, listas, tabelas, negrito, itálico e links
  function mdc(t) {
    const inl = (x) => esc(x).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/(^|[\s(])_(.+?)_(?=[\s).,;:]|$)/g, '$1<i>$2</i>').replace(/(https?:\/\/[^\s<)]+)/g, '<a href="$1" target="_blank" rel="noopener">$1 ↗</a>');
    const L = String(t || '').split('\n'); let h = ''; let i = 0;
    while (i < L.length) {
      const l = L[i];
      if (/^\s*\|/.test(l)) { const rows = []; while (i < L.length && /^\s*\|/.test(L[i])) { if (!/^\s*\|[\s|:-]+\|\s*$/.test(L[i])) rows.push(L[i].trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim())); i++; }
        h += `<div class="md-tab"><table>${rows.map((r, k) => `<tr>${r.map((c) => (k ? `<td>${inl(c)}</td>` : `<th>${inl(c)}</th>`)).join('')}</tr>`).join('')}</table></div>`; continue; }
      if (/^\s*([-•*]|\d+\.)\s+/.test(l)) { let li = ''; while (i < L.length && /^\s*([-•*]|\d+\.)\s+/.test(L[i])) { li += `<li>${inl(L[i].replace(/^\s*([-•*]|\d+\.)\s+/, ''))}</li>`; i++; } h += `<ul>${li}</ul>`; continue; }
      const m = l.match(/^(#{1,4})\s+(.+)/); if (m) { h += `<h${Math.min(6, m[1].length + 2)}>${inl(m[2])}</h${Math.min(6, m[1].length + 2)}>`; i++; continue; }
      if (!l.trim()) { i++; continue; }
      let p = l; i++; while (i < L.length && L[i].trim() && !/^\s*(\||[-•*]\s|\d+\.\s|#)/.test(L[i])) { p += `\n${L[i]}`; i++; }
      h += `<p>${inl(p).replace(/\n/g, '<br>')}</p>`;
    }
    return h;
  }
  const paragrafos = (t) => String(t || '').split(/\n{2,}/).map((p) => `<p>${md(p).replace(/\n/g, '<br>')}</p>`).join('');

  function gaveta(html, aoFechar) {
    const f = document.createElement('div'); f.className = 'gaveta-fundo';
    const g = document.createElement('aside'); g.className = 'gaveta'; g.setAttribute('role', 'dialog');
    g.innerHTML = `<button class="fechar" aria-label="Fechar">×</button>${html}`;
    const fechar = () => { f.remove(); g.remove(); document.removeEventListener('keydown', esc_); aoFechar?.(); };
    const esc_ = (e) => e.key === 'Escape' && fechar();
    f.onclick = fechar; $('.fechar', g).onclick = fechar; document.addEventListener('keydown', esc_);
    document.body.append(f, g); revelar(g);
    return { el: g, fechar };
  }

  return { info, EXPLICA, cidade3d, ativar3d, pictos, waffle, colunas, escalaY, ativarGraficos, barrasH, rosca, mdc, $, $$, esc, num, COR, SERV, mesTxt, iniciais, logo, marca, ico, toast, progresso, revelar, contador, medidor, anel, spark, linha, barrasRanking, animarBarras, md, paragrafos, gaveta, classeCor, reduzido };
})();
