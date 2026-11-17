/* EcoCity — painel com 4 perfis (cidadão, analista, gestor, admin).
   Com a API no ar: login + dados ao vivo do MySQL. Sem API: modo demonstração
   com o retrato do banco (data.js); o Copiloto roda no navegador com o mesmo motor. */
(() => {
  'use strict';
  const API = window.ECOCITY_API || null;
  const SNAP = window.ECOCITY_SNAPSHOT || null;
  const C = window.Copiloto;
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const num = (v, c = 1) => (v == null || isNaN(v) ? '—' : Number(v).toLocaleString('pt-BR', { minimumFractionDigits: c, maximumFractionDigits: c }));
  const casas = (cod) => (cod === 'RES-01' ? 2 : ['AGU-01', 'ENE-01', 'ENE-02', 'MOB-02'].includes(cod) ? 0 : 1);
  const fmt = (cod, v) => num(v, casas(cod));
  const rot = (am) => C.rotulo(am);
  const rotLongo = (am) => { const t = C.rotuloLongo(am); return t[0].toUpperCase() + t.slice(1); };
  const guardar = (k, v) => { try { localStorage.setItem('ecocity.' + k, JSON.stringify(v)); } catch { /* sem armazenamento */ } };
  const ler = (k, p) => { try { const v = localStorage.getItem('ecocity.' + k); return v == null ? p : JSON.parse(v); } catch { return p; } };
  const COR_SERV = { 'Água': 'var(--agua)', 'Energia': 'var(--energia)', 'Resíduos': 'var(--residuos)', 'Mobilidade': 'var(--mobilidade)' };
  const CORES_CID = ['#5EE1F0', '#A78BFA', '#F5A524', '#3DD598', '#FF6B87', '#7EA2FF', '#F472B6', '#C3E66E'];
  const ORIGEM_NOME = { REAL: 'Oficial', DERIVADO: 'Calculado de oficial', ESTIMADO: 'Estimado' };
  const ROT = { AGUARDANDO_AVALIACAO: 'aguardando avaliação', EM_EXECUCAO: 'em execução', CONCLUIDA: 'concluída', PLANEJADA: 'planejada', CANCELADA: 'cancelada',
    MELHOROU: 'melhorou', PIOROU: 'piorou', ESTAVEL: 'estável', EM_ANALISE: 'em análise', NOVA: 'nova', VALIDADA: 'validada', DESCARTADA: 'descartada' };
  const rotulo = (k) => ROT[k] || String(k).toLowerCase().replace(/_/g, ' ');
  const selo = (o, txt) => `<span class="origem ${o}">${esc(txt || ORIGEM_NOME[o])}</span>`;
  const ICONE = {
    'Água': '<path d="M12 3c3.5 4.4 6 7.7 6 11a6 6 0 0 1-12 0c0-3.3 2.5-6.6 6-11z"/>',
    'Energia': '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
    'Resíduos': '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
    'Mobilidade': '<rect x="4" y="4" width="16" height="13" rx="3"/><path d="M4 11h16M8 21v-2M16 21v-2"/>',
  };
  const icone = (serv, cor) => `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="${cor}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONE[serv] || ''}</svg>`;

  let D = null;                       // dados carregados
  let sessao = { perfil: null, nome: null, id: null, token: null };
  const DEMO = { ANALISTA: { id: 4, nome: 'Rafael Nunes', email: 'rafael.nunes@ecocity.local' },
                 GESTOR: { id: 2, nome: 'Marina Duarte', email: 'marina.duarte@ecocity.local' },
                 ADMIN: { id: 1, nome: 'Administrador EcoCity', email: 'admin@ecocity.local' } };

  // ------------------------------------------------------------ utilidades
  function toast(msg) {
    const t = $('#toast'); t.textContent = msg; t.hidden = false;
    clearTimeout(toast.t); toast.t = setTimeout(() => { t.hidden = true; }, 3600);
  }
  async function api(caminho, opt = {}) {
    const r = await fetch(API + caminho, { ...opt, headers: { 'Content-Type': 'application/json', ...(sessao.token ? { Authorization: 'Bearer ' + sessao.token } : {}) } });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.erro || `Erro ${r.status}`);
    return j;
  }
  function md(texto) {      // Markdown simples -> HTML (títulos, listas, tabelas, negrito, itálico)
    const inl = (s) => esc(s).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/(^|[\s(])_(.+?)_(?=[\s).,;]|$)/g, '$1<em>$2</em>');
    const linhas = String(texto || '').split('\n'); const out = []; let i = 0;
    while (i < linhas.length) {
      const l = linhas[i];
      if (/^###\s/.test(l)) { out.push(`<h3>${inl(l.slice(4))}</h3>`); i++; }
      else if (/^##\s/.test(l)) { out.push(`<h2>${inl(l.slice(3))}</h2>`); i++; }
      else if (/^\|/.test(l)) {
        const rows = []; while (i < linhas.length && /^\|/.test(linhas[i])) { rows.push(linhas[i]); i++; }
        const cel = (r) => r.split('|').slice(1, -1).map((c) => c.trim());
        out.push(`<div class="scroll-x"><table><thead><tr>${cel(rows[0]).map((c) => `<th>${inl(c)}</th>`).join('')}</tr></thead><tbody>${rows.slice(2).map((r) => `<tr>${cel(r).map((c) => `<td>${inl(c)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`);
      } else if (/^- /.test(l)) {
        const it = []; while (i < linhas.length && /^- /.test(linhas[i])) { it.push(`<li>${inl(linhas[i].slice(2))}</li>`); i++; }
        out.push(`<ul>${it.join('')}</ul>`);
      } else if (/^\d+\.\s/.test(l)) {
        const it = []; while (i < linhas.length && /^\d+\.\s/.test(linhas[i])) { it.push(`<li>${inl(linhas[i].replace(/^\d+\.\s/, ''))}</li>`); i++; }
        out.push(`<ol>${it.join('')}</ol>`);
      } else if (l.trim()) { out.push(`<p>${inl(l)}</p>`); i++; } else i++;
    }
    return `<div class="md">${out.join('')}</div>`;
  }
  const marca = (txt) => `<svg width="34" height="34" viewBox="0 0 40 40" aria-hidden="true">
      <circle cx="20" cy="20" r="15" fill="none" stroke="var(--agua)" stroke-width="5" stroke-dasharray="20 74.2" stroke-linecap="round"/>
      <circle cx="20" cy="20" r="15" fill="none" stroke="var(--energia)" stroke-width="5" stroke-dasharray="20 74.2" stroke-dashoffset="-23.5" stroke-linecap="round"/>
      <circle cx="20" cy="20" r="15" fill="none" stroke="var(--residuos)" stroke-width="5" stroke-dasharray="20 74.2" stroke-dashoffset="-47" stroke-linecap="round"/>
      <circle cx="20" cy="20" r="15" fill="none" stroke="var(--mobilidade)" stroke-width="5" stroke-dasharray="20 74.2" stroke-dashoffset="-70.5" stroke-linecap="round"/></svg>
      <span><b>EcoCity</b><small>${esc(txt)}</small></span>`;

  // ------------------------------------------------------------ preparo dos dados
  function preparar(d) {
    d.mun = Object.fromEntries((d.municipios || []).map((m) => [m.id_municipio, m]));
    d.ind = Object.fromEntries((d.indicadores || []).map((i) => [i.codigo, i]));
    d.meses = d.meses || [];
    if (d.serie) {
      d.linhas = d.serie.map((r) => {
        const i = d.ind[r.c], m = d.mun[r.m];
        return { id_municipio: r.m, municipio: m.nome, codigo: r.c, indicador: i.nome, servico: i.servico, ano_mes: r.p, valor: +r.v,
                 meta: +i.meta, unidade: i.unidade, sentido: i.sentido, score: +r.s, atingiu_meta: +r.a, origem: r.o };
      });
      d.iesL = d.ies.map((r) => ({ id_municipio: r.m, municipio: d.mun[r.m].nome, ano_mes: r.p, ies: +r.ies, ofi: r.ofi, der: r.der, est: r.est }));
    }
    d.relatorios = d.relatorios || []; d.perguntas = d.perguntas || []; d.alertas = d.alertas || []; d.acoes = d.acoes || [];
    return d;
  }
  const baseCopiloto = () => ({ vw_indicador_desempenho: D.linhas, vw_ies_municipio_mensal: D.iesL, vw_ies_ranking: D.ranking,
                                vw_origem_dados: D.origemDados, vw_acoes_resultados: D.acoes });
  const ctxCopiloto = () => ({ municipios: D.municipios.map((m) => m.nome), ultimoMes: D.ultimoMes,
                               indicadores: Object.fromEntries(D.indicadores.map((i) => [i.codigo, i])) });

  // ------------------------------------------------------------ gráficos (SVG)
  function grafLinhas({ series, rotulos, meta, unidade, cor = {} }) {
    const W = 900, H = 320, L = 58, R = 36, T = 16, B = 38;
    const ys = series.flatMap((s) => s.pontos.map((p) => p.y)).concat(meta != null ? [meta] : []);
    if (!ys.length) return '<p class="sub">Sem dados para esse filtro.</p>';
    let lo = Math.min(...ys), hi = Math.max(...ys); const pad = (hi - lo) * 0.12 || hi * 0.1 || 1; lo = Math.max(0, lo - pad); hi += pad;
    const passo = escalaPasso((hi - lo) / 5); lo = Math.floor(lo / passo) * passo; hi = Math.ceil(hi / passo) * passo;
    const n = rotulos.length, x = (i) => L + (n === 1 ? (W - L - R) / 2 : (i * (W - L - R)) / (n - 1)), y = (v) => T + (H - T - B) * (1 - (v - lo) / (hi - lo || 1));
    let g = '';
    for (let v = lo; v <= hi + 1e-9; v += passo) g += `<line x1="${L}" x2="${W - R}" y1="${y(v)}" y2="${y(v)}" stroke="${cor.grade}" stroke-width="1"/><text x="${L - 8}" y="${y(v) + 4}" text-anchor="end" fill="${cor.texto}">${num(v, passo < 1 ? 2 : 0)}</text>`;
    const cada = Math.ceil(n / 12);
    rotulos.forEach((r, i) => { if (i % cada === 0 || i === n - 1) g += `<text x="${x(i)}" y="${H - 12}" text-anchor="middle" fill="${cor.texto}">${esc(rot(r))}</text>`; });
    if (meta != null) g += `<line x1="${L}" x2="${W - R}" y1="${y(meta)}" y2="${y(meta)}" stroke="${cor.meta}" stroke-width="1.5" stroke-dasharray="6 5"/><text x="${W - R}" y="${y(meta) - 6}" text-anchor="end" fill="${cor.meta}">meta ${num(meta, meta < 10 ? 2 : 0)}</text>`;
    for (const s of series) {
      const pts = s.pontos.map((p) => `${x(p.i)},${y(p.y)}`).join(' ');
      g += `<polyline points="${pts}" fill="none" stroke="${s.cor}" stroke-width="2.2" stroke-linejoin="round"/>`;
      for (const p of s.pontos) {
        const cx = x(p.i), cy = y(p.y), tip = `<title>${esc(s.nome)} · ${rot(rotulos[p.i])}: ${num(p.y, 2)} ${esc(unidade || '')} (${ORIGEM_NOME[p.o]})</title>`;
        g += p.o === 'ESTIMADO' ? `<circle cx="${cx}" cy="${cy}" r="3.6" fill="${cor.fundo}" stroke="${s.cor}" stroke-width="1.8">${tip}</circle>`
          : p.o === 'DERIVADO' ? `<rect x="${cx - 3.5}" y="${cy - 3.5}" width="7" height="7" fill="${s.cor}">${tip}</rect>`
            : `<circle cx="${cx}" cy="${cy}" r="4.2" fill="${s.cor}">${tip}</circle>`;
      }
    }
    return `<svg class="grafico" viewBox="0 0 ${W} ${H}" role="img" aria-label="Gráfico de linhas mês a mês">${g}</svg>`;
  }
  function escalaPasso(bruto) { const p = Math.pow(10, Math.floor(Math.log10(bruto || 1))); const f = bruto / p; return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p; }
  function faisca(vals, corLinha, w = 120, h = 28) {
    if (vals.length < 2) return '';
    const lo = Math.min(...vals), hi = Math.max(...vals), x = (i) => 2 + (i * (w - 4)) / (vals.length - 1), y = (v) => h - 3 - ((v - lo) / (hi - lo || 1)) * (h - 6);
    const pts = vals.map((v, i) => `${x(i)},${y(v)}`).join(' ');
    return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true"><polyline points="${pts}" fill="none" stroke="${corLinha}" stroke-width="1.8"/><circle cx="${x(vals.length - 1)}" cy="${y(vals[vals.length - 1])}" r="2.8" fill="${corLinha}"/></svg>`;
  }
  function corScore(s, alfa = 1) {     // vermelho -> âmbar -> verde
    const t = Math.max(0, Math.min(1, s / 100));
    const a = [255, 107, 135], b = [245, 165, 36], c = [61, 213, 152];
    const [p, q, u] = t < 0.7 ? [a, b, t / 0.7] : [b, c, (t - 0.7) / 0.3];
    return `rgba(${p.map((v, k) => Math.round(v + (q[k] - v) * u)).join(',')},${alfa})`;
  }
  const classeIES = (v) => (v >= 85 ? ['Excelente', 'ok'] : v >= 70 ? ['Boa', 'ok'] : v >= 55 ? ['Regular', 'warn'] : ['Crítica', 'bad']);

  // ------------------------------------------------------------ navegação
  const VIEWS = { PORTAL: 'v-portal', CIDADAO: 'v-cidadao', ANALISTA: 'v-analista', GESTOR: 'v-gestor', ADMIN: 'v-admin' };
  function mostrar(qual) {
    Object.entries(VIEWS).forEach(([k, id]) => { $('#' + id).hidden = k !== qual; });
    $$('[data-usuario]').forEach((e) => { e.textContent = sessao.nome ? `${sessao.nome} · ${sessao.perfil.toLowerCase()}` : ''; });
    window.scrollTo(0, 0);
    if (qual === 'CIDADAO') renderCidadao();
    if (qual === 'ANALISTA') renderAnalista();
    if (qual === 'GESTOR') renderGestor();
    if (qual === 'ADMIN') renderAdmin();
  }
  async function entrar(perfil) {
    if (perfil === 'CIDADAO') {
      if (API) { try { D = preparar(await api('/public/cidadao')); } catch (e) { toast(e.message); return; } }
      else D = preparar(SNAP);
      return mostrar('CIDADAO');
    }
    if (!API) {
      sessao = { perfil, ...DEMO[perfil], token: null };
      D = preparar(SNAP);
      return mostrar(perfil);
    }
    abrirLogin(perfil);
  }
  function abrirLogin(perfil) {
    const nomes = { ANALISTA: 'Laboratório de dados', GESTOR: 'Sala de situação', ADMIN: 'Central do sistema' };
    $('#loginTitulo').textContent = 'Entrar · ' + nomes[perfil];
    $('#loginEmail').value = DEMO[perfil].email; $('#loginSenha').value = '';
    $('#loginDica').textContent = 'Usuário de demonstração já preenchido. Senha: EcoCity@2026';
    passe = null; etapaLogin(null);
    $('#loginErro').textContent = ''; $('#loginFundo').hidden = false; $('#loginSenha').focus();
  }
  $('#loginCancelar').addEventListener('click', () => { $('#loginFundo').hidden = true; passe = null; etapaLogin(null); });
  // Login em 2 etapas: 1) e-mail e senha  2) código de 6 dígitos do aplicativo autenticador
  let passe = null, etapa = null;
  function etapaLogin(qual, dica, pedeChave = false) {
    etapa = qual;
    $('#loginChaveBox').hidden = !pedeChave; $('#loginChave').required = pedeChave; $('#loginChave').value = '';
    $('#loginSenhaBox').hidden = !!qual; $('#loginSenha').required = !qual;
    $('#loginCodigoBox').hidden = !qual; $('#loginCodigo').required = !!qual; $('#loginCodigo').value = '';
    $('#loginEmail').readOnly = !!qual;
    if (dica) $('#loginDica').textContent = dica;
    if (qual) $('#loginCodigo').focus();
  }
  async function concluirLogin(r) {
    sessao = { perfil: r.usuario.perfil, nome: r.usuario.nome, id: r.usuario.id, token: r.token };
    passe = null; etapaLogin(null);
    if (sessao.perfil === 'CIDADAO') { $('#loginFundo').hidden = true; return entrar('CIDADAO'); }
    D = preparar(await api(sessao.perfil === 'ADMIN' ? '/admin' : '/dados'));
    $('#loginFundo').hidden = true;
    mostrar(sessao.perfil);
  }
  $('#loginForm').addEventListener('submit', async (ev) => {
    ev.preventDefault(); $('#loginErro').textContent = '';
    try {
      if (etapa === 'CODIGO') return concluirLogin(await api('/auth/mfa', { method: 'POST', body: JSON.stringify({ passe, codigo: $('#loginCodigo').value, chave_admin: $('#loginChave').value || undefined }) }));
      if (etapa === 'CONFIGURAR') return concluirLogin(await api('/auth/mfa/ativar', { method: 'POST', body: JSON.stringify({ passe, codigo: $('#loginCodigo').value, chave_admin: $('#loginChave').value || undefined }) }));
      const r = await api('/auth/login', { method: 'POST', body: JSON.stringify({ email: $('#loginEmail').value, senha: $('#loginSenha').value }) });
      if (r.etapa === 'CODIGO') { passe = r.passe; return etapaLogin('CODIGO', r.pede_chave_admin
          ? 'Senha conferida. Digite o código do aplicativo e a sua chave de administrador. (Demonstração: código em "npm run codigo"; chave ADM-EcoCity-2026)'
          : 'Senha conferida. Abra o aplicativo autenticador e digite o código. (Demonstração: código em "npm run codigo")', !!r.pede_chave_admin); }
      if (r.etapa === 'CONFIGURAR') {
        passe = r.passe;
        const c = await api('/auth/mfa/configurar', { method: 'POST', body: JSON.stringify({ passe }) });
        return etapaLogin('CONFIGURAR', `Primeiro acesso: no aplicativo autenticador, adicione a chave ${c.segredo} e digite o código gerado.`, !!r.pede_chave_admin);
      }
      return concluirLogin(r);
    } catch (e) { $('#loginErro').textContent = e.message; }
  });
  async function recarregar() { if (API && sessao.token) D = preparar(await api(sessao.perfil === 'ADMIN' ? '/admin' : '/dados')); }
  document.addEventListener('click', (ev) => {
    const porta = ev.target.closest('[data-ir]'); if (porta) return entrar(porta.dataset.ir);
    if (ev.target.closest('[data-sair]')) { sessao = { perfil: null }; mostrar('PORTAL'); history.replaceState(null, '', location.pathname); }
    if (ev.target.closest('[data-tema]')) {
      const escuro = document.documentElement.dataset.theme ? document.documentElement.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
      document.documentElement.dataset.theme = escuro ? 'light' : 'dark'; guardar('tema', document.documentElement.dataset.theme); pintarTema();
    }
  });
  function pintarTema() {
    const sol = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4.5"/><path d="M12 2v2.5M12 19.5V22M4.2 4.2l1.8 1.8M18 18l1.8 1.8M2 12h2.5M19.5 12H22M4.2 19.8 6 18M18 6l1.8-1.8"/></svg>';
    $$('[data-tema]').forEach((b) => { b.innerHTML = sol; });
  }

  // ============================================================ PORTAL
  function renderPortal() {
    $('#marcaPortal').innerHTML = marca('Cidades Inteligentes · SP');
    $$('[data-marca]').forEach((e) => { e.innerHTML = marca(e.dataset.marca); e.classList.add('marca'); });
    const d = SNAP;
    $('#modoPortal').textContent = API ? 'Conectado ao banco MySQL' : `Modo demonstração · retrato do banco de ${new Date(d.geradoEm).toLocaleDateString('pt-BR')}`;
    if (d && d.origemDados) {
      const t = d.origemDados.reduce((a, r) => ({ r: a.r + +r.registros_reais, d: a.d + +r.registros_derivados, e: a.e + +r.registros_estimados }), { r: 0, d: 0, e: 0 });
      $('#faixaPortal').innerHTML = `<span><b>8</b>cidades</span><span><b>${d.meses.length}</b>meses (${rot(d.meses[0])} a ${rot(d.meses[d.meses.length - 1])})</span>
        <span><b>${(t.r + t.d + t.e).toLocaleString('pt-BR')}</b>medições mensais</span>
        <span class="selos-legenda">${selo('REAL', `${t.r} oficiais`)}${selo('DERIVADO', `${t.d} calculadas de oficial`)}${selo('ESTIMADO', `${t.e} estimadas`)}</span>`;
    }
    if (!API) { $('#aviso').hidden = false; $('#avisoTxt').textContent = 'Modo demonstração: os dados são um retrato do banco. Ações, aprovações e perguntas feitas aqui ficam só nesta tela.'; }
  }

  // ============================================================ CIDADÃO
  let cidId = ler('cidade', 1);
  function renderCidadao() {
    if (!D.mun[cidId]) cidId = 1;
    $('#cidChips').innerHTML = D.municipios.map((m) => `<button type="button" data-cid="${m.id_municipio}" aria-pressed="${m.id_municipio === cidId}">${esc(m.nome)}</button>`).join('');
    const m = D.mun[cidId];
    const linhas = (D.painelCidadao || []).filter((r) => r.municipio === m.nome);
    const rk = D.ranking.find((r) => r.id_municipio === cidId);
    const mes = linhas[0]?.ano_mes || D.ultimoMes;
    $('#cidTitulo').textContent = `Como está ${m.nome}?`;
    const [cl, tom] = classeIES(rk.ies);
    const iesHist = (D.iesCidadao || D.ies.map((r) => ({ id_municipio: r.m, ano_mes: r.p, ies: r.ies }))).filter((r) => r.id_municipio === cidId).slice(-13);
    const lo = Math.min(...iesHist.map((r) => +r.ies)) - 4, hi = Math.max(...iesHist.map((r) => +r.ies));
    const circ = 2 * Math.PI * 62, corTom = { ok: 'var(--ok)', warn: 'var(--warn)', bad: 'var(--bad)' }[tom];
    const ordem = ['Água', 'Energia', 'Resíduos', 'Mobilidade'];
    linhas.sort((a, b) => ordem.indexOf(a.servico) - ordem.indexOf(b.servico) || a.codigo.localeCompare(b.codigo));
    const corSinal = { VERDE: ['ok', 'var(--ok)'], AMARELO: ['warn', 'var(--warn)'], VERMELHO: ['bad', 'var(--bad)'] };
    const origemDe = (t) => (t === 'Dado oficial' ? 'REAL' : t.startsWith('Calculado') ? 'DERIVADO' : 'ESTIMADO');
    const ind = D.ind;
    $('#cidConteudo').innerHTML = `
      <div class="cid-nota fade">
        <svg class="anel" viewBox="0 0 150 150" role="img" aria-label="Nota ${num(rk.ies, 0)} de 100">
          <circle cx="75" cy="75" r="62" fill="none" stroke="var(--c-soft)" stroke-width="14"/>
          <circle cx="75" cy="75" r="62" fill="none" stroke="${corTom}" stroke-width="14" stroke-linecap="round" stroke-dasharray="${(circ * rk.ies) / 100} ${circ}" transform="rotate(-90 75 75)"/>
          <text x="75" y="78" text-anchor="middle" font-family="Baloo 2, sans-serif" font-size="46" font-weight="700" fill="var(--c-fg)">${num(rk.ies, 0)}</text>
          <text x="75" y="102" text-anchor="middle" font-size="13" fill="var(--c-fg-2)">de 100</text>
        </svg>
        <div>
          <span class="pill ${tom}">Situação ${cl.toLowerCase()}</span>
          <h2 style="margin-top:8px">${esc(m.nome)} está em ${rk.posicao}º lugar entre as 8 cidades em ${esc(rotLongo(mes).toLowerCase())}.</h2>
          <p>A nota junta 8 sinais de água, energia, lixo e transporte. Quanto mais perto de 100, mais a cidade cuida dos recursos de todos.
          ${rk.variacao_12m != null ? `Em relação ao mesmo mês do ano passado, a nota ${rk.variacao_12m >= 0 ? 'subiu' : 'caiu'} ${num(Math.abs(rk.variacao_12m), 1)} ponto${Math.abs(rk.variacao_12m) >= 2 ? 's' : ''}.` : ''}</p>
          <div class="cid-meses" aria-hidden="true">${iesHist.map((r) => `<span style="height:${18 + ((+r.ies - lo) / (hi - lo || 1)) * 82}%" title="${rot(r.ano_mes)}: ${num(r.ies, 0)}"></span>`).join('')}</div>
          <p class="cid-meses-leg">A nota mês a mês, de ${rot(iesHist[0].ano_mes)} até ${rot(iesHist[iesHist.length - 1].ano_mes)}</p>
        </div>
      </div>
      <div class="cid-grade">${linhas.map((r) => {
        const i = ind[r.codigo], cor = COR_SERV[r.servico], [pt, pc] = corSinal[r.sinal];
        const max = Math.max(+r.valor, +r.meta) * 1.3, o = origemDe(r.origem_do_dado);
        const frase = C.IND[r.codigo].simples(fmt(r.codigo, r.valor)).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
        const seta = r.comparacao.startsWith('Melhor') ? '↑ ' : r.comparacao.startsWith('Pior') ? '↓ ' : '';
        return `<article class="cid-card fade" style="--cor:${cor}">
          <div class="topo"><span class="serv">${icone(r.servico, cor)}${esc(r.servico)} · ${esc(i.nome)}</span><span class="pill ${pt}">${esc(r.situacao)}</span></div>
          <p class="frase">${frase}</p>
          <div><div class="regua" role="img" aria-label="Valor ${fmt(r.codigo, r.valor)}, ideal ${C.IND[r.codigo].ideal}">
            <span class="val" style="width:${(100 * r.valor) / max}%;background:${pc}"></span><span class="ideal" style="left:${(100 * r.meta) / max}%"></span></div>
            <div class="regua-leg"><span>Agora: ${fmt(r.codigo, r.valor)} ${esc(r.unidade)}</span><span>Ideal: ${esc(C.IND[r.codigo].ideal)}</span></div></div>
          <div class="rodape"><span>${seta}${esc(r.comparacao)}</span>${selo(o, r.origem_do_dado)}</div>
          <details><summary>Como você pode ajudar</summary><p>${esc(C.IND[r.codigo].dica)}</p></details>
        </article>`;
      }).join('')}</div>`;
    const rels = (D.relatoriosPublicos || D.relatorios.filter((r) => r.status === 'APROVADO' && r.publico === 'CIDADAO'))
      .filter((r) => String(r.municipios).split(', ').includes(m.nome));
    $('#cidRelatorios').innerHTML = rels.length ? rels.map((r) => `<article class="cid-rel"><p class="meta">Aprovado por ${esc(r.aprovado_por || r.revisado_por)} em ${esc(String(r.revisado_em).slice(0, 10).split('-').reverse().join('/'))} · ${num(r.pct_dados_oficiais, 0)}% com base em dados oficiais</p><h3 style="font-family:var(--f-round);font-size:22px;margin-bottom:8px">${esc(r.titulo)}</h3>${md(r.conteudo)}</article>`).join('')
      : `<div class="cid-rel"><p>Ainda não há relatório aprovado para ${esc(m.nome)}. Quando um gestor aprovar um texto do Copiloto sobre a cidade, ele aparece aqui.</p></div>`;
    $('#cidPe').textContent = `Dados de ${rotLongo(mes).toLowerCase()} (último mês disponível). Fontes: IBGE, ANEEL, SPTrans, EPE, SNIS/SINISA, SEEG e Prefeitura de São Paulo (SP Regula). Nenhum dado pessoal é exibido.`;
  }
  $('#cidChips').addEventListener('click', (ev) => { const b = ev.target.closest('[data-cid]'); if (!b) return; cidId = +b.dataset.cid; guardar('cidade', cidId); renderCidadao(); });

  // ============================================================ ANALISTA
  const ana = { aba: ler('aba', 'explorar'), cod: 'ENE-02', cids: [1, 2, 3, 7], de: null, ate: null, qCod: 'AGU-02', respostas: [], ultimoRel: null };
  const corCid = (id) => CORES_CID[(id - 1) % CORES_CID.length];
  const CORES_ANA = { grade: '#1A2846', texto: '#93A6C6', meta: '#E3B341', fundo: '#0D1729' };
  const optMeses = (sel) => D.meses.map((m) => `<option value="${m}"${m === sel ? ' selected' : ''}>${rot(m)}</option>`).join('');
  const optInd = (sel) => ['Água', 'Energia', 'Resíduos', 'Mobilidade'].map((s) => `<optgroup label="${s}">${D.indicadores.filter((i) => i.servico === s).map((i) => `<option value="${i.codigo}"${i.codigo === sel ? ' selected' : ''}>${i.codigo} · ${esc(i.nome)}</option>`).join('')}</optgroup>`).join('');
  const chipsCid = (ids, attr = 'data-chip') => D.municipios.map((m) => `<button type="button" ${attr}="${m.id_municipio}" aria-pressed="${ids.includes(m.id_municipio)}" style="--chip:${corCid(m.id_municipio)}"><i></i>${esc(m.nome)}</button>`).join('');

  function renderAnalista() {
    ana.de = ana.de || D.meses[Math.max(0, D.meses.length - 12)]; ana.ate = ana.ate || D.ultimoMes;
    $$('#anaNav button').forEach((b) => b.setAttribute('aria-current', String(b.dataset.aba === ana.aba)));
    const f = { explorar: abaExplorar, comparar: abaComparar, copiloto: abaCopiloto, relatorios: abaRelatorios, ia: abaIA, qualidade: abaQualidade }[ana.aba];
    $('#anaAbas').innerHTML = `<div class="ana-sec fade">${f()}</div>`;
  }
  $('#anaNav').addEventListener('click', (ev) => { const b = ev.target.closest('[data-aba]'); if (!b) return; ana.aba = b.dataset.aba; guardar('aba', ana.aba); renderAnalista(); });

  function abaExplorar() {
    const i = D.ind[ana.cod], meses = D.meses.filter((m) => m >= ana.de && m <= ana.ate);
    const series = ana.cids.map((id) => ({ nome: D.mun[id].nome, cor: corCid(id),
      pontos: D.linhas.filter((r) => r.id_municipio === id && r.codigo === ana.cod && r.ano_mes >= ana.de && r.ano_mes <= ana.ate).map((r) => ({ i: meses.indexOf(r.ano_mes), y: r.valor, o: r.origem })) }));
    const tab = meses.map((mes) => `<tr><td>${rot(mes)}</td>${ana.cids.map((id) => { const r = D.linhas.find((x) => x.id_municipio === id && x.codigo === ana.cod && x.ano_mes === mes);
      return `<td class="r" title="${r ? ORIGEM_NOME[r.origem] : ''}">${r ? `${fmt(ana.cod, r.valor)} <span class="origem ${r.origem}" style="padding:0 5px;border:0"></span>` : '—'}</td>`; }).join('')}</tr>`).join('');
    return `<div class="ana-painel">
      <div><h2>Explorar séries mensais</h2><p class="sub">${esc(i.descricao)}. Meta: ${i.sentido === 'MAIOR_MELHOR' ? 'no mínimo' : 'no máximo'} ${fmt(ana.cod, i.meta)} ${esc(i.unidade)} · ${esc(i.ods)}</p></div>
      <div class="ana-filtros">
        <label class="campo" for="fInd">indicador<select id="fInd" data-f="cod">${optInd(ana.cod)}</select></label>
        <label class="campo" for="fDe">de<select id="fDe" data-f="de">${optMeses(ana.de)}</select></label>
        <label class="campo" for="fAte">até<select id="fAte" data-f="ate">${optMeses(ana.ate)}</select></label>
      </div>
      <div class="chips" id="fCids">${chipsCid(ana.cids)}</div>
      <div class="scroll-x">${grafLinhas({ series, rotulos: meses, meta: +i.meta, unidade: i.unidade, cor: CORES_ANA })}</div>
      <div class="legenda-g"><span>${selo('REAL')} ponto cheio</span><span>${selo('DERIVADO')} quadrado</span><span>${selo('ESTIMADO')} ponto vazado</span><span style="color:#E3B341">- - - meta</span></div>
    </div>
    <div class="ana-painel"><div style="display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;align-items:center"><h2>Tabela</h2><button type="button" class="btn" id="btnCsv">Copiar como CSV</button></div>
      <div class="scroll-x"><table><thead><tr><th>Mês</th>${ana.cids.map((id) => `<th class="r">${esc(D.mun[id].nome)}</th>`).join('')}</tr></thead><tbody>${tab}</tbody></table></div></div>`;
  }
  function abaComparar() {
    const i = D.ind[ana.qCod], ult = D.ultimoMes;
    const cols = `160px repeat(${D.meses.length}, minmax(26px, 1fr))`;
    let h = `<div class="mapa-calor" style="grid-template-columns:${cols}"><span></span>${D.meses.map((m, k) => `<span class="h">${k % 3 === 0 ? rot(m).replace('/20', '/') : ''}</span>`).join('')}`;
    for (const m of D.municipios) {
      h += `<span class="n">${esc(m.nome)}</span>` + D.meses.map((mes) => { const r = D.linhas.find((x) => x.id_municipio === m.id_municipio && x.codigo === ana.qCod && x.ano_mes === mes);
        return r ? `<span class="c" style="background:${corScore(r.score)};${r.origem === 'ESTIMADO' ? 'opacity:.72' : ''}" title="${esc(m.nome)} · ${rot(mes)}: ${fmt(ana.qCod, r.valor)} ${esc(i.unidade)} · ${ORIGEM_NOME[r.origem]}"></span>` : '<span></span>'; }).join('');
    }
    h += '</div>';
    const piv = D.municipios.map((m) => `<tr><td>${esc(m.nome)}</td>${D.indicadores.map((ix) => { const r = D.linhas.find((x) => x.id_municipio === m.id_municipio && x.codigo === ix.codigo && x.ano_mes === ult);
      return `<td class="r" style="color:${r.atingiu_meta ? 'var(--ok)' : 'var(--bad)'}">${fmt(ix.codigo, r.valor)}</td>`; }).join('')}</tr>`).join('');
    return `<div class="ana-painel"><div><h2>Mapa de calor: ${esc(i.nome)}</h2><p class="sub">Cada quadrado é um mês. Verde = na meta; vermelho = longe da meta. Quadrados mais apagados usam dado estimado. Passe o mouse para ver o valor.</p></div>
      <label class="campo" for="fQCod" style="max-width:420px">indicador<select id="fQCod" data-f="qCod">${optInd(ana.qCod)}</select></label>
      <div class="scroll-x">${h}</div></div>
      <div class="ana-painel"><div><h2>Visão integrada · ${rot(ult)}</h2><p class="sub">Os 8 indicadores lado a lado. Verde = dentro da meta.</p></div>
      <div class="scroll-x"><table><thead><tr><th>Cidade</th>${D.indicadores.map((ix) => `<th class="r" title="${esc(ix.nome)}">${ix.codigo}<br><span style="text-transform:none;letter-spacing:0">${esc(ix.unidade)}</span></th>`).join('')}</tr></thead><tbody>${piv}</tbody></table></div></div>`;
  }
  const EXEMPLOS = ['Qual cidade tem o maior consumo de água?', 'Como evoluiu a energia solar em Sorocaba nos últimos 12 meses?', 'O que está fora da meta em Guarulhos?',
    'Qual cidade recicla mais em março de 2026?', 'Quais dados são oficiais?', 'Quais ações funcionaram?', 'Apague a tabela de usuários'];
  function cartaoResposta(r) {
    const cols = r.linhas && r.linhas[0] ? Object.keys(r.linhas[0]) : [];
    return `<div class="resposta ${r.situacao}">
      <div style="display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap"><span class="q">${esc(r.pergunta)}</span><span class="pill ${r.situacao === 'RESPONDIDA' ? 'ok' : r.situacao === 'BLOQUEADA' ? 'bad' : 'warn'}">${r.situacao.replace('_', ' ').toLowerCase()}</span></div>
      <div class="txt">${md(r.texto)}</div>
      ${cols.length ? `<div class="scroll-x"><table><thead><tr>${cols.map((c) => `<th>${esc(c)}</th>`).join('')}</tr></thead><tbody>${r.linhas.slice(0, 12).map((l) => `<tr>${cols.map((c) => `<td>${c === 'origem' ? selo(l[c]) : esc(typeof l[c] === 'number' ? num(l[c], Number.isInteger(l[c]) ? 0 : 2) : l[c])}</td>`).join('')}</tr>`).join('')}</tbody></table></div>${r.linhas.length > 12 ? `<span class="info">+ ${r.linhas.length - 12} linhas</span>` : ''}` : ''}
      ${r.sql ? `<pre>${esc(r.sql)}</pre>` : ''}
      <span class="info">${r.situacao === 'BLOQUEADA' ? 'Nada foi executado no banco.' : 'Executado com o usuário ecocity_ia (só pode ler as views de indicadores)'} · ${esc(r.modelo || C.MODELO_LOCAL)}${r.tempo_ms != null ? ` · ${r.tempo_ms} ms` : ''}</span></div>`;
  }
  function abaCopiloto() {
    const hist = D.perguntas.slice(0, 10);
    return `<div class="ana-painel"><div><h2>Pergunte ao Copiloto</h2><p class="sub">Escreva em português. O Copiloto transforma a pergunta numa consulta SQL de leitura, roda no banco com um usuário que não pode alterar nada e responde com os números encontrados.</p></div>
      <form class="cop-entrada" id="copForm"><input id="copPergunta" placeholder="Ex.: Qual cidade gera mais lixo por pessoa?" autocomplete="off" aria-label="Pergunta"><button class="btn primario" type="submit">Perguntar</button></form>
      <div class="exemplos">${EXEMPLOS.map((e) => `<button type="button" data-ex="${esc(e)}">${esc(e)}</button>`).join('')}</div>
      <div id="copRespostas" style="display:grid;gap:12px">${ana.respostas.map(cartaoResposta).join('')}</div></div>
      <div class="ana-painel"><div><h2>Histórico do banco (tabela pergunta_ia)</h2><p class="sub">Toda pergunta fica registrada, inclusive as bloqueadas.</p></div>
      <div class="scroll-x"><table><thead><tr><th>Quando</th><th>Quem</th><th>Pergunta</th><th>Situação</th><th class="r">Linhas</th></tr></thead><tbody>${hist.map((p) => `<tr><td class="num">${esc(p.criada_em)}</td><td>${esc(p.usuario)}</td><td>${esc(p.pergunta)}${p.motivo_bloqueio ? `<br><small style="color:var(--bad)">${esc(p.motivo_bloqueio)}</small>` : ''}</td><td><span class="pill ${p.situacao === 'RESPONDIDA' ? 'ok' : 'bad'}">${esc(p.situacao.toLowerCase())}</span></td><td class="r">${p.linhas_retornadas}</td></tr>`).join('')}</tbody></table></div></div>`;
  }
  async function perguntar(pergunta) {
    let r;
    if (API) {
      try { r = await api('/copiloto/perguntar', { method: 'POST', body: JSON.stringify({ pergunta }) }); } catch (e) { return toast(e.message); }
      recarregar().then(() => { if (ana.aba === 'copiloto' && !$('#v-analista').hidden) renderAnalista(); });
    } else {
      const t0 = performance.now(), ctx = ctxCopiloto(), plano = C.interpretar(pergunta, ctx);
      const linhas = plano.situacao === 'RESPONDIDA' ? C.executarLocal(plano, baseCopiloto()) : [];
      r = { situacao: plano.situacao, texto: C.responder(plano, linhas, ctx), sql: plano.sql, linhas, modelo: C.MODELO_LOCAL, tempo_ms: Math.round(performance.now() - t0) };
      D.perguntas.unshift({ pergunta, situacao: plano.situacao, motivo_bloqueio: plano.situacao === 'BLOQUEADA' ? plano.motivo : null, linhas_retornadas: linhas.length, usuario: sessao.nome, criada_em: new Date().toISOString().slice(0, 16).replace('T', ' ') });
    }
    ana.respostas.unshift({ pergunta, ...r }); ana.respostas = ana.respostas.slice(0, 6);
    renderAnalista();
  }

  // ---- relatórios (formulário compartilhado entre analista e gestor)
  const relF = { cids: [2, 7], de: null, ate: null, publico: 'GESTOR' };
  function formRelatorio(pref) {
    relF.de = relF.de || D.meses[Math.max(0, D.meses.length - 12)]; relF.ate = relF.ate || D.ultimoMes;
    return `<form id="${pref}RelForm" class="rel-form" style="display:grid;gap:12px">
      <div class="chips" data-relchips>${chipsCid(relF.cids, 'data-relcid')}</div>
      <div class="ana-filtros">
        <label class="campo" for="${pref}RelDe">de<select id="${pref}RelDe" data-rel="de">${optMeses(relF.de)}</select></label>
        <label class="campo" for="${pref}RelAte">até<select id="${pref}RelAte" data-rel="ate">${optMeses(relF.ate)}</select></label>
        <label class="campo" for="${pref}RelPub">para quem<select id="${pref}RelPub" data-rel="publico"><option value="GESTOR"${relF.publico === 'GESTOR' ? ' selected' : ''}>Gestores (técnico)</option><option value="CIDADAO"${relF.publico === 'CIDADAO' ? ' selected' : ''}>Cidadãos (linguagem simples)</option></select></label>
        <button class="btn primario" type="submit">Gerar relatório</button>
      </div></form>`;
  }
  async function gerarRelatorio() {
    if (!relF.cids.length) return toast('Escolha pelo menos uma cidade.');
    if (relF.ate < relF.de) return toast('O mês final precisa ser depois do inicial.');
    let rel;
    if (API) {
      try { rel = await api('/copiloto/relatorios', { method: 'POST', body: JSON.stringify({ municipios: relF.cids, inicio: relF.de, fim: relF.ate, publico: relF.publico }) }); }
      catch (e) { return toast(e.message); }
      await recarregar();
    } else {
      const nomes = relF.cids.map((id) => D.mun[id].nome);
      rel = C.gerarRelatorio({ linhas: D.linhas.filter((r) => relF.cids.includes(r.id_municipio) && r.ano_mes >= relF.de && r.ano_mes <= relF.ate),
        ies: D.iesL.filter((r) => relF.cids.includes(r.id_municipio) && r.ano_mes >= relF.de && r.ano_mes <= relF.ate), publico: relF.publico, acoes: D.acoes });
      rel.id_relatorio = Math.max(0, ...D.relatorios.map((r) => r.id_relatorio)) + 1;
      D.relatorios.unshift({ id_relatorio: rel.id_relatorio, titulo: rel.titulo, tipo: rel.tipo, publico: rel.publico, de: rel.inicio, ate: rel.fim,
        municipios: nomes.sort().join(', '), conteudo: rel.conteudo, pct_dados_oficiais: rel.pctOficial, modelo: rel.modelo, status: 'RASCUNHO',
        solicitado_por: sessao.nome, criado_em: new Date().toISOString().slice(0, 16).replace('T', ' ') });
    }
    ana.ultimoRel = rel.id_relatorio;
    toast('Relatório criado e enviado para aprovação de um gestor.');
    sessao.perfil === 'GESTOR' ? renderGestor() : renderAnalista();
  }
  const itemRel = (r, aberto, revisar) => `<details class="rel-item"${aberto ? ' open' : ''}><summary class="linha" style="list-style:none;cursor:pointer">
      <span><span class="t">${esc(r.titulo)}</span><br><span class="m">Pedido por ${esc(r.solicitado_por)} em ${esc(r.criado_em)} · ${num(r.pct_dados_oficiais, 0)}% base oficial · ${esc(r.modelo)}${r.revisado_por ? ` · revisado por ${esc(r.revisado_por)}` : ''}</span></span>
      <span class="pill st-${r.status}">${r.status === 'RASCUNHO' ? 'aguardando aprovação' : r.status.toLowerCase()}</span></summary>
      <div style="margin-top:10px;display:grid;gap:10px">${r.comentario_revisao ? `<p class="m">Comentário da revisão: ${esc(r.comentario_revisao)}</p>` : ''}${md(r.conteudo)}
      ${revisar && r.status === 'RASCUNHO' ? `<div class="form-grade" style="align-items:end"><label class="campo" for="com${r.id_relatorio}">comentário da revisão<input id="com${r.id_relatorio}" placeholder="Opcional"></label>
        <div style="display:flex;gap:8px;flex-wrap:wrap"><button type="button" class="btn primario" data-revisar="${r.id_relatorio}" data-decisao="APROVADO">Aprovar e publicar</button><button type="button" class="btn" data-revisar="${r.id_relatorio}" data-decisao="REJEITADO">Rejeitar</button></div></div>` : ''}</div></details>`;
  function abaRelatorios() {
    return `<div class="ana-painel"><div><h2>Pedir um relatório ao Copiloto</h2><p class="sub">Escolha as cidades, o intervalo de meses e para quem é o texto. O relatório usa só os números do banco e vai para a fila de aprovação dos gestores.</p></div>${formRelatorio('ana')}</div>
      <div class="ana-painel"><h2>Relatórios (tabela relatorio_ia)</h2><div class="rel-lista">${D.relatorios.map((r) => itemRel(r, r.id_relatorio === ana.ultimoRel, false)).join('')}</div></div>`;
  }
  function abaIA() {
    return `<div class="ana-painel"><div><h2>Análises automáticas</h2><p class="sub">Geradas pelo módulo de IA (comparação com o mesmo mês do ano anterior, previsão e mudanças bruscas) e pelos alertas do banco. Valide ou descarte cada uma.</p></div>
      <div style="display:grid;gap:10px">${D.alertas.map((a) => `<div class="insight ${a.severidade}"><div style="display:flex;gap:8px;justify-content:space-between;flex-wrap:wrap"><b>${esc(a.titulo)}</b><span class="pill ${a.status === 'VALIDADA' ? 'ok' : a.status === 'DESCARTADA' ? 'neutro' : 'warn'}">${esc(rotulo(a.status))}</span></div>
        <p style="font-size:14px">${esc(a.descricao)}</p><small>${esc(a.tipo.replace('_', ' ').toLowerCase())} · ${esc(a.municipio)} · ${esc(a.indicador)} · confiança ${num(a.confianca, 0)}% · ${esc(a.modelo_versao)}</small>
        ${['NOVA', 'EM_ANALISE'].includes(a.status) ? `<div class="acoes-i"><button type="button" class="btn" data-alerta="${a.id_analise}" data-st="VALIDADA">Validar</button><button type="button" class="btn" data-alerta="${a.id_analise}" data-st="DESCARTADA">Descartar</button></div>` : ''}</div>`).join('')}</div></div>`;
  }
  function pilhaOrigem(r) {
    const t = +r.registros_reais + +r.registros_derivados + +r.registros_estimados;
    return `<div class="pilha" title="${r.registros_reais} oficiais · ${r.registros_derivados} calculados · ${r.registros_estimados} estimados"><span style="width:${(100 * r.registros_reais) / t}%;background:var(--o-real)"></span><span style="width:${(100 * r.registros_derivados) / t}%;background:var(--o-der)"></span><span style="width:${(100 * r.registros_estimados) / t}%;background:var(--o-est);opacity:.55"></span></div>`;
  }
  function abaQualidade() {
    return `<div class="ana-painel"><div><h2>Origem dos dados por métrica</h2><p class="sub">Quanto de cada métrica é oficial do mês, calculado a partir de um total oficial ou estimado pela equipe.</p></div>
      <div class="legenda-g">${selo('REAL')}${selo('DERIVADO')}${selo('ESTIMADO')}</div>
      <div class="scroll-x"><table><thead><tr><th>Serviço</th><th>Métrica</th><th>Composição</th><th class="r">Base oficial</th><th>Último mês oficial</th></tr></thead><tbody>${D.origemDados.map((r) => `<tr><td>${esc(r.servico)}</td><td><code>${esc(r.metrica)}</code></td><td style="min-width:160px">${pilhaOrigem(r)}</td><td class="r">${num(r.pct_base_oficial, 0)}%</td><td>${r.ultimo_mes_oficial ? rot(r.ultimo_mes_oficial) : '—'}</td></tr>`).join('')}</tbody></table></div></div>
      ${D.fontes ? `<div class="ana-painel"><h2>Fontes</h2><div class="scroll-x"><table><thead><tr><th>Fonte</th><th>Órgão</th><th>Publica</th><th class="r">Registros</th><th>Último mês oficial</th></tr></thead><tbody>${D.fontes.map((f) => `<tr><td>${esc(f.fonte)}</td><td>${esc(f.orgao)}</td><td>${esc(f.frequencia.toLowerCase())}</td><td class="r">${f.total_registros}</td><td>${f.ultimo_mes_oficial ? rot(f.ultimo_mes_oficial.slice(0, 7)) : 'nenhum mês oficial'}</td></tr>`).join('')}</tbody></table></div></div>` : ''}`;
  }

  // ---- eventos do laboratório e do gestor (delegação)
  document.addEventListener('change', (ev) => {
    const t = ev.target;
    if (t.dataset.f) { ana[t.dataset.f] = t.value; if (ana.ate < ana.de) [ana.de, ana.ate] = [ana.ate, ana.de]; renderAnalista(); }
    if (t.dataset.rel) relF[t.dataset.rel] = t.value;
  });
  document.addEventListener('click', async (ev) => {
    const ch = ev.target.closest('[data-chip]');
    if (ch) { const id = +ch.dataset.chip; ana.cids = ana.cids.includes(id) ? ana.cids.filter((x) => x !== id) : [...ana.cids, id].sort((a, b) => a - b); if (!ana.cids.length) ana.cids = [id]; return renderAnalista(); }
    const rc = ev.target.closest('[data-relcid]');
    if (rc) { const id = +rc.dataset.relcid; relF.cids = relF.cids.includes(id) ? relF.cids.filter((x) => x !== id) : [...relF.cids, id]; rc.setAttribute('aria-pressed', String(relF.cids.includes(id))); return; }
    const ex = ev.target.closest('[data-ex]'); if (ex) return perguntar(ex.dataset.ex);
    if (ev.target.id === 'btnCsv') {
      const meses = D.meses.filter((m) => m >= ana.de && m <= ana.ate);
      const csv = ['mes;' + ana.cids.map((id) => D.mun[id].nome).join(';')].concat(meses.map((m) => m + ';' + ana.cids.map((id) => { const r = D.linhas.find((x) => x.id_municipio === id && x.codigo === ana.cod && x.ano_mes === m); return r ? String(r.valor).replace('.', ',') : ''; }).join(';'))).join('\n');
      try { await navigator.clipboard.writeText(csv); toast('Tabela copiada. Cole no Excel ou no Google Planilhas.'); } catch { toast('Não foi possível copiar automaticamente.'); }
      return;
    }
    const al = ev.target.closest('[data-alerta]');
    if (al) {
      const id = +al.dataset.alerta, st = al.dataset.st;
      if (API) { try { await api('/alertas/' + id, { method: 'PATCH', body: JSON.stringify({ status: st }) }); await recarregar(); } catch (e) { return toast(e.message); } }
      else D.alertas.find((a) => a.id_analise === id).status = st;
      toast(st === 'VALIDADA' ? 'Análise validada.' : 'Análise descartada.');
      return sessao.perfil === 'GESTOR' ? renderGestor() : renderAnalista();
    }
    const rv = ev.target.closest('[data-revisar]');
    if (rv) {
      const id = +rv.dataset.revisar, decisao = rv.dataset.decisao, comentario = ($('#com' + id) || {}).value || null;
      if (API) { try { await api('/copiloto/relatorios/' + id, { method: 'PATCH', body: JSON.stringify({ decisao, comentario }) }); await recarregar(); } catch (e) { return toast(e.message); } }
      else {
        const r = D.relatorios.find((x) => x.id_relatorio === id);
        if (r.solicitado_por === sessao.nome) return toast('Quem pediu o relatório não pode aprová-lo. Outra pessoa precisa revisar.');
        Object.assign(r, { status: decisao, revisado_por: sessao.nome, comentario_revisao: comentario, revisado_em: new Date().toISOString().slice(0, 16).replace('T', ' '), aprovado_por: sessao.nome });
      }
      toast(decisao === 'APROVADO' ? 'Relatório aprovado. Se for para cidadãos, já aparece no painel público.' : 'Relatório rejeitado.');
      return renderGestor();
    }
  });
  document.addEventListener('submit', (ev) => {
    if (ev.target.id === 'copForm') { ev.preventDefault(); const q = $('#copPergunta').value.trim(); if (q) perguntar(q); }
    if (ev.target.classList.contains('rel-form')) { ev.preventDefault(); gerarRelatorio(); }
    if (ev.target.id === 'acaoForm') { ev.preventDefault(); novaAcao(new FormData(ev.target)); }
  });

  // ============================================================ GESTOR
  let gesIdx = null;
  const CORES_GES = () => ({ grade: 'var(--g-line)', texto: 'var(--g-fg-2)', meta: 'var(--g-gold)', fundo: 'var(--g-surface)' });
  function iesMes(mes) { return D.iesL.filter((r) => r.ano_mes === mes); }
  function renderGestor() {
    const ult = D.meses.length - 1; if (gesIdx == null || gesIdx > ult) gesIdx = ult;
    const sl = $('#gesMes'); sl.max = ult; sl.value = gesIdx;
    const mes = D.meses[gesIdx], antes = D.meses[gesIdx - 1], ano = D.meses[gesIdx - 12];
    $('#gesMesOut').textContent = rot(mes);
    $('#gesTitulo').textContent = `Situação das 8 cidades · ${rotLongo(mes).toLowerCase()}`;
    const pop = Object.fromEntries(D.municipios.map((m) => [m.id_municipio, m.populacao]));
    const pond = (rows) => rows.reduce((a, r) => a + r.ies * pop[r.id_municipio], 0) / rows.reduce((a, r) => a + pop[r.id_municipio], 0);
    const agora = iesMes(mes), iMed = pond(agora), iAno = ano ? pond(iesMes(ano)) : null;
    const lm = D.linhas.filter((r) => r.ano_mes === mes), metas = lm.filter((r) => r.atingiu_meta).length;
    const crit = agora.filter((r) => r.ies < 55).length, aval = D.acoes.filter((a) => a.efeito !== 'AGUARDANDO_AVALIACAO'), boas = aval.filter((a) => a.efeito === 'MELHOROU').length;
    const baseOf = Math.round((100 * lm.filter((r) => r.origem !== 'ESTIMADO').length) / lm.length);
    $('#gesKpis').innerHTML = `
      <div class="kpi"><span class="r">Índice EcoCity (média ponderada)</span><span class="v num">${num(iMed, 1)}</span><span class="d">${iAno != null ? `${iMed - iAno >= 0 ? '▲' : '▼'} ${num(Math.abs(iMed - iAno), 1)} contra ${rot(ano)}` : 'sem mês de comparação'}</span></div>
      <div class="kpi"><span class="r">Metas cumpridas no mês</span><span class="v num">${metas}<span style="font-size:18px;opacity:.7">/${lm.length}</span></span><span class="d">${Math.round((100 * metas) / lm.length)}% dos indicadores das 8 cidades</span></div>
      <div class="kpi"><span class="r">Cidades em situação crítica</span><span class="v num">${crit}</span><span class="d">índice abaixo de 55 pontos</span></div>
      <div class="kpi"><span class="r">Ações que deram resultado</span><span class="v num">${boas}<span style="font-size:18px;opacity:.7">/${aval.length}</span></span><span class="d">avaliadas com antes × depois · base oficial do mês: ${baseOf}%</span></div>`;

    const rank = agora.slice().sort((a, b) => b.ies - a.ies);
    const linhaRank = (r, k) => {
      const p = D.iesL.find((x) => x.id_municipio === r.id_municipio && x.ano_mes === antes), q = D.iesL.find((x) => x.id_municipio === r.id_municipio && x.ano_mes === ano);
      const v = (x) => (x == null ? '<span style="color:var(--g-fg-2)">—</span>' : `<span class="${x >= 0 ? 'var-up' : 'var-down'}">${x >= 0 ? '+' : ''}${num(x, 1)}</span>`);
      const [cl, tom] = classeIES(r.ies);
      const hist = D.iesL.filter((x) => x.id_municipio === r.id_municipio && x.ano_mes <= mes).map((x) => x.ies);
      return `<tr><td class="num">${k + 1}º</td><td><b>${esc(r.municipio)}</b><br><span class="pill ${tom}" style="margin-top:2px">${cl}</span></td>
        <td style="min-width:150px"><div style="display:flex;gap:8px;align-items:center"><div class="barra-ies" style="flex:1"><span style="width:${r.ies}%;background:${corScore(r.ies)}"></span></div><b class="num">${num(r.ies, 1)}</b></div></td>
        <td class="r">${v(p ? r.ies - p.ies : null)}</td><td class="r">${v(q ? r.ies - q.ies : null)}</td><td>${faisca(hist, 'var(--g-deep)')}</td>
        <td><span title="indicadores oficiais / calculados / estimados" class="num" style="font-size:12.5px;color:var(--g-fg-2)">${r.ofi}·${r.der}·${r.est}</span></td></tr>`;
    };
    const ordemInd = D.indicadores.map((i) => i.codigo);
    const matriz = `<div class="matriz" style="grid-template-columns:150px repeat(${ordemInd.length}, minmax(56px, 1fr))"><span></span>${D.indicadores.map((i) => `<span class="h" title="${esc(i.nome)}">${esc(i.nome.replace(' per capita', '').replace('Geração distribuída por habitante', 'Energia solar').replace('Perdas na distribuição de água', 'Perdas de água').replace('Emissões do transporte', 'CO₂ transporte').replace('Uso do transporte público', 'Ônibus'))}</span>`).join('')}
      ${D.municipios.map((m) => `<span class="n">${esc(m.nome)}</span>${ordemInd.map((c) => { const r = lm.find((x) => x.id_municipio === m.id_municipio && x.codigo === c);
        return `<span class="c" style="background:${corScore(r.score, 0.28)};border:1px solid ${corScore(r.score, 0.6)}" title="${esc(m.nome)} · ${esc(r.indicador)}: ${fmt(c, r.valor)} ${esc(r.unidade)} (meta ${fmt(c, r.meta)}) · ${ORIGEM_NOME[r.origem]}">${fmt(c, r.valor)}</span>`; }).join('')}`).join('')}</div>`;
    const pend = D.relatorios.filter((r) => r.status === 'RASCUNHO');
    const crits = D.alertas.filter((a) => ['NOVA', 'EM_ANALISE'].includes(a.status)).slice(0, 5);
    $('#gesGrade').innerHTML = `
      <section class="ges-bloco fade"><div><h2>Ranking do mês</h2><p class="sub">Índice EcoCity de 0 a 100 (8 indicadores com pesos). Variação contra o mês anterior e contra o mesmo mês do ano passado.</p></div>
        <div class="scroll-x"><table><thead><tr><th>#</th><th>Cidade</th><th>Índice</th><th class="r">No mês</th><th class="r">12 meses</th><th>Tendência</th><th>Base*</th></tr></thead><tbody>${rank.map(linhaRank).join('')}</tbody></table></div>
        <p class="sub" style="font-size:12.5px">* Quantos dos 8 indicadores do mês são oficiais · calculados de oficial · estimados.</p></section>
      <section class="ges-bloco fade"><div><h2>Relatórios da IA para aprovar</h2><p class="sub">O Copiloto escreve; um gestor revisa. Quem pediu o relatório não pode aprovar o próprio pedido (regra no banco).</p></div>
        <div class="rel-lista">${pend.length ? pend.map((r) => itemRel(r, false, true)).join('') : '<p class="sub">Nenhum relatório aguardando aprovação.</p>'}</div>
        <details class="rel-item"><summary style="cursor:pointer;font-weight:700">Pedir um novo relatório ao Copiloto</summary><div style="margin-top:10px">${formRelatorio('ges')}</div></details></section>
      <section class="ges-bloco largo fade"><div><h2>Matriz de metas · ${rot(mes)}</h2><p class="sub">Cada célula é o valor do indicador no mês. Verde = dentro da meta; âmbar = perto; vermelho = longe. Passe o mouse para ver a meta e a origem do dado.</p></div><div class="scroll-x">${matriz}</div></section>
      <section class="ges-bloco fade"><div><h2>Ações e resultados</h2><p class="sub">Antes = mês anterior ao início da ação; depois = último mês avaliado. Ações ilustrativas.</p></div>
        ${D.acoes.map((a) => `<div class="acao-card"><div style="display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap"><b>${esc(a.titulo)}</b><span class="pill ${a.efeito === 'MELHOROU' ? 'ok' : a.efeito === 'PIOROU' ? 'bad' : 'neutro'}">${esc(rotulo(a.efeito))}</span></div>
          <span class="sub" style="font-size:13px">${esc(a.municipio)} · ${esc(a.indicador_nome)} · R$ ${num(a.orcamento / 1e6, 1)} mi · ${esc(rotulo(a.status))}</span>
          ${a.valor_antes != null ? `<div class="ab"><span>antes <b>${fmt(a.indicador_alvo, a.valor_antes)}</b></span><span>→ depois <b>${fmt(a.indicador_alvo, a.valor_depois)}</b></span><span class="${(a.efeito === 'MELHOROU') ? 'var-up' : 'var-down'}">${a.variacao_pct >= 0 ? '+' : ''}${num(a.variacao_pct, 1)}%</span></div>` : ''}</div>`).join('')}
        <details class="rel-item"><summary style="cursor:pointer;font-weight:700">Registrar nova ação</summary>
          <form id="acaoForm" class="form-grade" style="margin-top:10px">
            <label class="campo" for="aTit">Título<input id="aTit" name="titulo" required></label>
            <label class="campo" for="aMun">Cidade<select id="aMun" name="id_municipio">${D.municipios.map((m) => `<option value="${m.id_municipio}">${esc(m.nome)}</option>`).join('')}</select></label>
            <label class="campo" for="aInd">Indicador-alvo<select id="aInd" name="codigo">${D.indicadores.map((i) => `<option value="${i.codigo}">${esc(i.nome)}</option>`).join('')}</select></label>
            <label class="campo" for="aOrc">Orçamento (R$)<input id="aOrc" name="orcamento" type="number" min="0" step="1000" value="500000"></label>
            <label class="campo" for="aIni">Início<input id="aIni" name="data_inicio" type="date" value="2026-11-01" required></label>
            <label class="campo" for="aFim">Fim previsto<input id="aFim" name="data_fim_prevista" type="date" value="2027-10-31" required></label>
            <label class="campo" for="aDesc" style="grid-column:1/-1">Descrição<textarea id="aDesc" name="descricao" rows="2" required>Descreva o que será feito.</textarea></label>
            <div><button class="btn primario" type="submit">Registrar ação</button></div></form></details></section>
      <section class="ges-bloco fade"><div><h2>Alertas que pedem atenção</h2><p class="sub">Gerados por regras do banco (indicador mais de 40% longe da meta) e pelo módulo de IA.</p></div>
        ${crits.map((a) => `<div class="insight ${a.severidade}"><b>${esc(a.titulo)}</b><p style="font-size:14px">${esc(a.descricao)}</p><small>${esc(a.municipio)} · ${esc(a.modelo_versao)}</small></div>`).join('') || '<p class="sub">Nenhum alerta aberto.</p>'}</section>`;
  }
  $('#gesMes').addEventListener('input', (ev) => { gesIdx = +ev.target.value; renderGestor(); });
  async function novaAcao(fd) {
    const ind = D.indicadores.find((i) => i.codigo === fd.get('codigo'));
    const corpo = { titulo: fd.get('titulo'), descricao: fd.get('descricao'), id_municipio: +fd.get('id_municipio'), id_indicador_alvo: ind.id_indicador,
                    data_inicio: fd.get('data_inicio'), data_fim_prevista: fd.get('data_fim_prevista'), orcamento: +fd.get('orcamento') };
    if (corpo.data_fim_prevista < corpo.data_inicio) return toast('O fim previsto precisa ser depois do início.');
    if (API) { try { await api('/acoes', { method: 'POST', body: JSON.stringify(corpo) }); await recarregar(); } catch (e) { return toast(e.message); } }
    else D.acoes.push({ ...corpo, municipio: D.mun[corpo.id_municipio].nome, indicador_alvo: ind.codigo, indicador_nome: ind.nome, status: 'PLANEJADA', efeito: 'AGUARDANDO_AVALIACAO' });
    toast('Ação registrada.'); renderGestor();
  }

  // ============================================================ ADMIN
  const PAPEIS = [
    ['r_cidadao', 'Painel público, ranking, origem dos dados e relatórios aprovados', 'Só views públicas; nenhum dado pessoal'],
    ['r_analista', 'Camada analítica, DW, valida análises da IA, pede relatórios e faz perguntas ao Copiloto', 'Leitura + INSERT em ações e perguntas'],
    ['r_gestor', 'Tudo do analista + ações, resultados e aprovação de relatórios', 'EXECUTE sp_registrar_resultado / sp_revisar_relatorio'],
    ['r_etl', 'Carga do staging e execução do pipeline mensal', 'INSERT staging · EXECUTE sp_pipeline_mensal'],
    ['r_bi', 'Leitura do Data Warehouse (dimensões e fatos)', 'Só SELECT nas tabelas dim_* e fato_*'],
    ['r_ia', 'Executa o SQL gerado pelo Copiloto', 'Só SELECT em 7 views de indicadores; sem tabelas'],
    ['r_dba', 'Administração completa do schema', 'ALL PRIVILEGES (uso restrito)'],
  ];
  function renderAdmin() {
    const banco = D.banco || [], tot = banco.reduce((a, t) => a + (t.linhas || 0), 0);
    const bloqueadas = (D.copilotoUso || []).find((u) => u.situacao === 'BLOQUEADA')?.perguntas || D.perguntas.filter((p) => p.situacao === 'BLOQUEADA').length;
    const ultLote = (D.lotes || [])[0];
    const camadas = ['Staging', 'Core', 'Copiloto', 'Data Warehouse'];
    const maxL = Math.max(...banco.map((t) => t.linhas || 0), 1);
    $('#admConteudo').innerHTML = `
      <div class="adm-status fade">
        <div><span class="r">tabelas</span><span class="v">${banco.length}</span></div>
        <div><span class="r">linhas no banco</span><span class="v num">${tot.toLocaleString('pt-BR')}</span></div>
        <div><span class="r">medições mensais</span><span class="v num">${(banco.find((t) => t.tabela === 'dado') || {}).linhas?.toLocaleString('pt-BR') ?? '—'}</span></div>
        <div><span class="r">último lote</span><span class="v ${ultLote && ultLote.status !== 'SUCESSO' ? 'amber' : ''}">${ultLote ? esc(ultLote.status.toLowerCase()) : '—'}</span></div>
        <div><span class="r">perguntas bloqueadas</span><span class="v amber">${bloqueadas}</span></div>
      </div>
      <div class="adm-grade">
        <section class="adm-bloco largo"><h2>Camadas do banco</h2><p class="sub">Staging recebe o dado bruto; o Core guarda tudo validado em 3FN; o Data Warehouse (estrela) alimenta os painéis; o Copiloto guarda relatórios e perguntas.</p>
          <div class="camadas">${camadas.map((c) => `<div class="camada"><h3>${c}</h3>${banco.filter((t) => t.camada === c).map((t) => `<div class="t"><b title="${t.tabela}">${t.tabela}</b><span class="num">${t.linhas ?? '—'}</span></div><div style="height:3px;background:#2A2D33;border-radius:2px"><div style="height:3px;width:${Math.max(2, (100 * Math.log10((t.linhas || 0) + 1)) / Math.log10(maxL + 1))}%;background:var(--d-teal);border-radius:2px"></div></div>`).join('')}</div>`).join('')}</div></section>
        <section class="adm-bloco"><h2>Cargas de dados (ETL)</h2><div class="scroll-x"><table><thead><tr><th>Lote</th><th>Fonte</th><th>Status</th><th class="r">Lidos</th><th class="r">Rejeit.</th></tr></thead><tbody>${(D.lotes || []).map((l) => `<tr><td class="num">#${l.id_lote}</td><td>${esc(l.fonte)}<br><small style="color:var(--d-fg-3)">${esc(l.mensagem || '')}</small></td><td><span class="pill ${l.status === 'SUCESSO' ? 'ok' : l.status === 'FALHA' ? 'bad' : 'warn'}">${esc(l.status.toLowerCase())}</span></td><td class="r">${l.registros_lidos}</td><td class="r">${l.registros_rejeitados}</td></tr>`).join('')}</tbody></table></div>
          <h2 style="margin-top:6px">Linhas recusadas no staging</h2><div class="scroll-x"><table><thead><tr><th>Métrica</th><th>Município</th><th>Data</th><th>Valor</th><th>Motivo</th></tr></thead><tbody>${(D.rejeitados || []).map((r) => `<tr><td><code>${esc(r.codigo_metrica)}</code></td><td>${esc(r.nome_municipio)}</td><td>${esc(r.data_texto)}</td><td>${esc(r.valor_texto)}</td><td style="color:var(--bad)">${esc(r.erro)}</td></tr>`).join('')}</tbody></table></div></section>
        <section class="adm-bloco"><h2>Fontes de dados</h2><div class="scroll-x"><table><thead><tr><th>Fonte</th><th>Tipo</th><th>Publica</th><th>Confiança</th><th>Último oficial</th></tr></thead><tbody>${(D.fontes || []).map((f) => `<tr><td>${esc(f.fonte)}<br><small style="color:var(--d-fg-3)">${esc(f.orgao)} · ${esc(f.servico)}</small></td><td><code style="white-space:nowrap">${esc(f.tipo_integracao.toLowerCase().replace('_', ' '))}</code></td><td>${esc(f.frequencia.toLowerCase())}</td><td class="estrelas" aria-label="${f.confiabilidade} de 5">${'★'.repeat(f.confiabilidade)}${'☆'.repeat(5 - f.confiabilidade)}</td><td>${f.ultimo_mes_oficial ? rot(f.ultimo_mes_oficial.slice(0, 7)) : '—'}</td></tr>`).join('')}</tbody></table></div>
          <h2 style="margin-top:6px">Transparência</h2><div class="scroll-x"><table><tbody>${(D.origemDados || []).map((r) => `<tr><td><code>${esc(r.metrica)}</code></td><td style="min-width:150px">${pilhaOrigem(r)}</td><td class="r">${num(r.pct_base_oficial, 0)}%</td></tr>`).join('')}</tbody></table></div></section>
        <section class="adm-bloco"><h2>Usuários e perfis</h2><div class="scroll-x"><table><thead><tr><th>Nome</th><th>Perfil</th><th>Cidade</th><th>Último acesso</th></tr></thead><tbody>${(D.usuarios || []).map((u) => `<tr><td>${esc(u.nome)}<br><small style="color:var(--d-fg-3)">${esc(u.email)}</small></td><td><code>${esc(u.perfil)}</code></td><td>${esc(u.municipio || 'todas')}</td><td class="num">${esc(u.ultimo_acesso || 'nunca')}</td></tr>`).join('')}</tbody></table></div>
          <p class="sub">Senhas guardadas só como hash bcrypt; a API nunca devolve a coluna senha_hash.</p></section>
        <section class="adm-bloco"><h2>Papéis de segurança do MySQL</h2><div class="scroll-x"><table class="papeis"><thead><tr><th>Papel</th><th>Para quê</th><th>Limite</th></tr></thead><tbody>${PAPEIS.map((p) => `<tr><td><code>${p[0]}</code></td><td>${esc(p[1])}</td><td>${esc(p[2])}</td></tr>`).join('')}</tbody></table></div>
          <p class="sub">Usuários do banco: ecocity_api (r_gestor + r_cidadao), ecocity_ia (r_ia, máx. 600 consultas/hora), ecocity_etl, ecocity_bi e ecocity_dba. Bloqueio após 5 senhas erradas.</p></section>
        <section class="adm-bloco largo"><h2>Copiloto: segurança das perguntas</h2><p class="sub">Toda pergunta vira SQL validado (só SELECT, só views liberadas, LIMIT 200, 3 s de tempo máximo) e roda com o usuário ecocity_ia. Pedidos de alteração ou de dados pessoais são barrados antes do banco.</p>
          <div class="scroll-x"><table><thead><tr><th>Quando</th><th>Quem</th><th>Pergunta</th><th>Situação</th><th>SQL gerado / motivo</th></tr></thead><tbody>${D.perguntas.slice(0, 12).map((p) => `<tr><td class="num">${esc(p.criada_em)}</td><td>${esc(p.usuario)}</td><td>${esc(p.pergunta)}</td><td><span class="pill ${p.situacao === 'RESPONDIDA' ? 'ok' : 'bad'}">${esc(p.situacao.toLowerCase())}</span></td><td>${p.situacao === 'BLOQUEADA' ? `<span style="color:var(--bad)">${esc(p.motivo_bloqueio)}</span>` : `<code>${esc((p.sql_gerado || '').replace('/*+ MAX_EXECUTION_TIME(3000) */ ', ''))}</code>`}</td></tr>`).join('')}</tbody></table></div></section>
        <section class="adm-bloco largo"><h2>Auditoria (últimos eventos)</h2><div class="scroll-x"><table><thead><tr><th>Quando</th><th>Usuário do banco</th><th>Tabela</th><th>Operação</th><th>Antes</th><th>Depois</th></tr></thead><tbody>${(D.auditoria || []).map((a) => `<tr><td class="num">${esc(a.ocorrido_em)}</td><td><code>${esc(a.usuario_bd)}</code></td><td>${esc(a.tabela)} #${a.id_registro}</td><td>${esc(a.operacao)}</td><td><code>${esc(typeof a.dados_antigos === 'string' ? a.dados_antigos : JSON.stringify(a.dados_antigos))}</code></td><td><code>${esc(typeof a.dados_novos === 'string' ? a.dados_novos : JSON.stringify(a.dados_novos))}</code></td></tr>`).join('') || '<tr><td colspan="6">Sem eventos.</td></tr>'}</tbody></table></div></section>
      </div>`;
  }

  // ============================================================ início
  try { const t = ler('tema', null); if (t) document.documentElement.dataset.theme = t; } catch { /* ok */ }
  pintarTema();
  renderPortal();
  const destino = { '#cidadao': 'CIDADAO', '#analista': 'ANALISTA', '#gestor': 'GESTOR', '#admin': 'ADMIN' }[location.hash];
  if (destino && (!API || destino === 'CIDADAO')) entrar(destino);
})();
