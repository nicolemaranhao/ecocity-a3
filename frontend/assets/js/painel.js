/* EcoCity — área logada: menu colorido de cada perfil + páginas centradas nos DADOS
   (visão geral, uma página por área, comparar, mapa, mês a mês, alertas, economize, desafios, aprenda) */
const Painel = (() => {
  const { $, $$, esc, num, ico, toast, revelar, SERV, mesTxt, iniciais } = UI;
  const NIVEL = { CIDADAO: 1, ANALISTA: 2, GESTOR: 3, ADMIN: 4 };
  const pode = (p) => NIVEL[API.usuario?.perfil] >= NIVEL[p];
  const NOME_PERFIL = { CIDADAO: 'Cidadão', ANALISTA: 'Analista', GESTOR: 'Gestor público', ADMIN: 'Administrador' };
  const casasDe = (v) => (Math.abs(v) < 20 ? 2 : Math.abs(v) < 100 ? 1 : 0);
  const SIT = { BOM: ['verde', '✓', 'Bom'], ATENCAO: ['laranja', '!', 'Atenção'], CRITICO: ['critico', '✕', 'Crítico'] };
  const pilula = (nivel, txt) => { const [c, i, t] = SIT[nivel] || SIT.ATENCAO; return `<span class="pilula ${c}"><b>${i}</b>${esc(txt || t)}</span>`; };
  const PALETA = { verde: '#2F8F3F', azul: '#1D5FA8', laranja: '#E8892B', ceu: '#4FB3E3', navy: '#163E6E', roxo: '#7C5CD6', rosa: '#D9488B', critico: '#D94848' };

  // ------------------------------------------------------------ áreas (cada uma com sua cor e sua cena)
  const AREAS = {
    agua: { servico: 'Água', cor: 'ceu', emoji: '', titulo: 'Água', cods: ['AGU-01', 'AGU-02'], desc: 'Quanta água cada pessoa usa e quanta se perde no caminho até as casas.' },
    energia: { servico: 'Energia', cor: 'laranja', emoji: '', titulo: 'Energia', cods: ['ENE-01', 'ENE-02'], desc: 'Quanta energia a cidade usa e quanto já vem dos painéis solares.' },
    lixo: { servico: 'Resíduos', cor: 'verde', emoji: '', titulo: 'Lixo e reciclagem', cods: ['RES-01', 'RES-02'], desc: 'Quanto lixo cada pessoa gera e quanto dele volta a ser matéria-prima.' },
    transporte: { servico: 'Mobilidade', cor: 'azul', emoji: '', titulo: 'Transporte', cods: ['MOB-01', 'MOB-02'], desc: 'Quanto as pessoas usam o ônibus e quanta poluição o transporte solta no ar.' },
  };
  const icoArea = (servico) => `<span class="ic-area" style="--c:${SERV[servico]?.cor || '#1D5FA8'}">${ico(SERV[servico]?.ico || 'painel', 'currentColor', 1.7)}</span>`;
  const SELO = { REAL: 'Oficial do mês', DERIVADO: 'Oficial do ano', ESTIMADO: 'Estimado' };
  const selo = (o) => `<span class="selo o-${o}" title="${o === 'ESTIMADO' ? 'Não há número oficial da cidade para este mês; o EcoCity estima a partir de uma série oficial maior (ex.: energia do Estado de SP)' : o === 'DERIVADO' ? 'A fonte oficial publica o total do ano; o EcoCity divide pelos meses' : 'Número publicado pela fonte oficial para este mês'}">${SELO[o] || o}</span>`;
  const verMeta = () => pode('ANALISTA');   // o cidadão não tem acesso a metas nem à nota
  const refDe = (i) => (verMeta() ? i.meta : i.media8);
  const areaDe = (servico) => Object.keys(AREAS).find((k) => AREAS[k].servico === servico);

  // ------------------------------------------------------------ menu de cada perfil (criativo e colorido)
  const CIDADAO = [
    ['Sua cidade', [['painel', 'sala', 'Visão geral', 'navy'], ['mes', 'calendario', 'O que mudou no mês', 'roxo'], ['alertas', 'sino', 'Alertas', 'critico']]],
    ['Os dados', [['agua', 'gota', 'Água', 'ceu'], ['energia', 'sol', 'Energia', 'laranja'], ['lixo', 'folha', 'Lixo e reciclagem', 'verde'], ['transporte', 'onibus', 'Transporte', 'azul']]],
    ['Explorar', [['comparar', 'balanca', 'Comparar cidades', 'rosa'], ['mapa', 'mapa', 'Mapa das cidades', 'ceu'], ['aprenda', 'livro', 'Entenda os dados', 'navy']]],
    ['Na sua casa', [['economize', 'cofre', 'Economize em casa', 'verde'], ['desafios', 'trofeu', 'Desafios verdes', 'laranja']]],
  ];
  const EXPLORAR = ['Explorar', [['cidade', 'predio', 'Ver uma cidade', 'navy'], ['comparar', 'balanca', 'Comparar cidades', 'rosa'], ['mapa', 'mapa', 'Mapa das cidades', 'ceu'], ['mes', 'calendario', 'O que mudou no mês', 'roxo'], ['aprenda', 'livro', 'Entenda os dados', 'navy']]];
  const GESTOR = [
    ['Decisão', [['sala', 'sala', 'Sala de situação', 'navy'], ['conselheiro', 'bussola', 'Conselheiro IA', 'roxo'], ['simulador', 'controles', 'Simulador de metas', 'laranja'], ['acoes', 'flecha', 'Ações e resultados', 'verde'], ['metas', 'alvo', 'Metas', 'rosa']]],
    ['Dados', [['riscos', 'radar', 'Radar de riscos', 'critico'], ['laboratorio', 'lab', 'Laboratório de dados', 'azul'], ['analises', 'livro', 'Análises', 'ceu']]], EXPLORAR];
  const MENU = {
    CIDADAO,
    ANALISTA: [['Trabalho', [['laboratorio', 'lab', 'Laboratório de dados', 'azul'], ['assistente', 'robo', 'Assistente de relatórios', 'roxo'], ['analises', 'livro', 'Análises', 'ceu'], ['metas', 'alvo', 'Metas', 'rosa'], ['riscos', 'radar', 'Radar de riscos', 'critico']]], EXPLORAR],
    GESTOR, ADMIN: [...GESTOR, ['Sistema', [['admin', 'escudo', 'Administração', 'navy']]]],
  };
  const INICIO = { CIDADAO: 'painel', ANALISTA: 'laboratorio', GESTOR: 'sala', ADMIN: 'sala' };
  const corDaRota = (rota) => { for (const [, itens] of MENU[API.usuario?.perfil] || CIDADAO) for (const it of itens) if (it[0] === rota) return it[3]; return 'azul'; };

  let secaoAtual = ''; let logoAnimado = false;
  let modoNum = 'recente';   // Visão geral: números mais recentes ou últimos oficiais
  function casca(app, ativo, conteudo) {
    const u = API.usuario;
    const grupos = MENU[u.perfil] || CIDADAO;
    secaoAtual = (grupos.find(([, itens]) => itens.some((i) => i[0] === ativo)) || [''])[0];
    app.innerHTML = `<div class="casca">
      <aside class="lateral"><a class="marca marca-app" href="#/app/${INICIO[u.perfil]}">${UI.logo({ anim: !logoAnimado })}<span><b>Eco</b><span>City</span></span></a>
        <nav>${grupos.map(([g, itens]) => `<span class="secao-nav">${g}</span>${itens.map(([id, i, t]) => `<a href="#/app/${id}" class="${ativo === id ? 'ativo' : ''}" ${ativo === id ? 'aria-current="page"' : ''}>${ico(i, 'currentColor', 1.7)}<span class="tx">${t}</span>${id === 'riscos' || id === 'alertas' ? '<span class="contador" data-cont hidden></span>' : ''}</a>`).join('')}`).join('')}</nav>
        <div class="usuario"><div class="u-linha"><span class="ini">${iniciais(u.nome)}</span><div><b>${esc(u.nome.split(' ').slice(0, 2).join(' '))}</b><small>${NOME_PERFIL[u.perfil]}</small></div></div>
          <div class="u-acoes"><button class="u-sair" id="sair">${ico('sair', 'currentColor', 1.7)} Sair da conta</button><button class="u-trocar" id="trocar" title="Sair e entrar com outra conta">Trocar de conta</button></div></div></aside>
      <section class="conteudo-app pagina" id="conteudo">${conteudo}</section></div>`;
    logoAnimado = true;
    $('#sair').onclick = () => sair();
    $('#trocar').onclick = () => sair(true);
    API.pegar('/alertas').then((a) => { const n = a.filter((x) => x.severidade === 'CRITICO' && x.status === 'NOVA').length; $$('[data-cont]').forEach((c) => { c.textContent = n; c.hidden = !n; }); }).catch(() => {});
    $('.lateral nav a.ativo')?.scrollIntoView({ block: 'nearest', inline: 'center' });
  }
  // sai da conta; com trocar = true vai direto para a tela de entrar com outra conta
  function sair(trocar = false) {
    API.sair(); API.limpar(); Chat.desmontar();
    location.hash = trocar ? '#/entrar' : '#/';
    toast(trocar ? 'Você saiu. Entre com a outra conta.' : 'Você saiu da conta. Até logo!');
  }
  // cabeçalho editorial: chapéu (seção), título, linha fina e ações à direita
  const topo = (titulo, sub, direita = '', motivo = '', chapeu = '') => `<header class="cabeca ${motivo ? 'com-motivo' : ''}">
      <div class="cb-txt"><span class="chapeu">${esc(chapeu || secaoAtual)}</span><h1>${titulo}</h1>${sub ? `<p class="lead">${sub}</p>` : ''}${direita ? `<div class="cb-acoes">${direita}</div>` : ''}</div>
      ${motivo ? `<div class="cb-motivo">${motivo}</div>` : ''}<button class="btn fantasma sm sair-mob" onclick="Painel.sair()">${ico('sair', 'currentColor', 1.7)} Sair</button></header>`;
  const esqueleto = () => `<div class="carregando">${UI.logo({ anim: true })}<span>Carregando os dados…</span></div><div class="esq" style="height:44px;max-width:520px;margin-bottom:14px"></div><div class="esq" style="height:20px;max-width:680px;margin-bottom:34px"></div><div class="grade g-4">${'<div class="esq" style="height:180px"></div>'.repeat(8)}</div>`;

  // ------------------------------------------------------------ fonte de cada número (dentro do próprio dado)
  function gavetaFonte(titulo, f, mes) {
    if (!f) return;
    const T = { REAL: ['verde', 'Oficial do mês'], DERIVADO: ['azul', 'Oficial do ano'], ESTIMADO: ['laranja', 'Estimado'] };
    UI.gaveta(`<span class="chip ${T[f.origem][0]}"><i></i>${T[f.origem][1]}</span><h2>De onde vem este número?</h2>
      <p style="color:var(--tinta-2);margin-bottom:18px"><b>${esc(titulo)}</b> · ${mesTxt(mes)}. ${f.origem === 'ESTIMADO' ? 'Não existe número oficial da cidade para este mês. O EcoCity estimou a partir de uma série oficial maior e mostra a conta abaixo. Se a prefeitura ou a concessionária enviar o número, ele entra no lugar.' : f.origem === 'DERIVADO' ? 'A fonte oficial publica o total do ano. O EcoCity dividiu esse total pelos meses — o número do ano é oficial.' : 'Número publicado pela fonte oficial para este mês.'}</p>
      ${f.fontes.map((x) => `<div class="cartao fonte-item"><div class="fi-topo"><span class="sigla">${esc(x.sigla)}</span><div><b>${esc(x.fonte)}</b><small>${esc(x.orgao || '')}</small></div><span class="chip ${T[x.origem]?.[0] || 'cinza'}">${esc(x.metrica === 'POPULACAO' ? 'Oficial (IBGE)' : (T[x.origem]?.[1] || x.origem))}</span></div>
        <p><b>Usado para:</b> ${esc(x.metrica_nome)}</p>${x.referencia ? `<p class="ref">“${esc(x.referencia)}”</p>` : ''}
        <div class="fi-pe"><span>Publica: <b>${esc(String(x.frequencia || '').toLowerCase())}</b></span>${x.url ? `<a href="${esc(x.url)}" target="_blank" rel="noopener">Abrir site oficial ↗</a>` : ''}</div></div>`).join('')}`);
  }
  const ORIG = { REAL: 'oficial do mês', DERIVADO: 'oficial do ano', ESTIMADO: 'estimado' };
  // último número OFICIAL do indicador (pode ser de um mês/ano anterior ao do painel)
  const ultOfTxt = (i) => {
    const o = i.ultimoOficial;
    if (!o) return { cls: 'sem', curto: 'Sem dado oficial da cidade', longo: i.semOficial || '' };
    if (o.igualAoPainel) return { cls: 'ok', curto: 'Oficial até este mês', longo: `O número deste mês já é oficial (${o.fonte}).` };
    const MES3 = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    const quando = `em ${MES3[Number(o.mes.slice(5, 7)) - 1]}/${o.mes.slice(0, 4)}`;
    return { cls: 'antigo', curto: `Último oficial: ${num(o.valor, casasDe(o.valor))} ${quando}`, longo: `Último dado oficial: <b class="num">${num(o.valor, casasDe(o.valor))} ${esc(i.unidade)}</b> ${quando} (${esc(o.fonte)}). Os meses depois disso são estimados até a fonte publicar.` };
  };
  const ultOfLinha = (i) => { const t = ultOfTxt(i); return `<p class="ult-of u-${t.cls}">${ico('fonte')}<span>${t.longo || t.curto}</span></p>`; };
  const fonteLinha = (f, attrs) => (f ? `<button class="fonte-linha" ${attrs}>${ico('fonte')}<span><b>Fonte:</b> ${esc([...new Set(f.fontes.map((x) => x.fonte.split(' - ')[0]))].join(' + '))} · <em class="o-${f.origem}">${ORIG[f.origem]}</em></span><u>ver detalhes</u></button>` : '');
  const botaoFonte = fonteLinha;
  const mesCurto = (p) => `${mesTxt(p).slice(0, 3)}/${p.slice(2, 4)}`;
  // último dado OFICIAL quando ele não aparece nos meses do gráfico (para nunca mostrar só estimativas)
  const ofAntes = (i, janela) => { const uo = i.ultimoOficial; if (!uo || janela.some((s) => s.o !== 'ESTIMADO')) return null; return { valor: uo.valor, rotulo: mesCurto(uo.mes) }; };

  // ------------------------------------------------------------ visual de cada dado (pictogramas que qualquer pessoa entende)
  const IC = {
    galao: '<svg viewBox="0 0 24 24"><path d="M8 3h8v3l2 2v12a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V8l2-2z" fill="currentColor"/></svg>',
    raio: '<svg viewBox="0 0 24 24"><path d="M13 2 4 14h7l-1 8 9-12h-7z" fill="currentColor"/></svg>',
    sol: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="5" fill="currentColor"/><path d="M12 1v3M12 20v3M1 12h3M20 12h3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1" stroke="currentColor" stroke-width="2"/></svg>',
    saco: '<svg viewBox="0 0 24 24"><path d="M9 3h6l-1 3h-4zM7 7h10l2 13a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2z" fill="currentColor"/></svg>',
    onibus: '<svg viewBox="0 0 24 24"><rect x="4" y="3" width="16" height="15" rx="3" fill="currentColor"/><rect x="6" y="6" width="12" height="5" rx="1" fill="#fff" opacity=".8"/><circle cx="8" cy="20" r="2" fill="currentColor"/><circle cx="16" cy="20" r="2" fill="currentColor"/></svg>',
    nuvem: '<svg viewBox="0 0 24 24"><path d="M7 19a5 5 0 1 1 1-9.9A6 6 0 0 1 19.5 11 4 4 0 0 1 18 19z" fill="currentColor"/></svg>',
  };
  function visual(i) {
    const v = i.valor; const ref = refDe(i); const refTxt = verMeta() ? 'a meta' : 'a média das 8 cidades';
    const P = {
      'AGU-01': () => [UI.pictos(v, 20, IC.galao, { meta: ref, cor: '#2E8FCB' }), `Cada <b>galão</b> = 20 litros. A linha marca ${refTxt}; os <b class="t-laranja">laranja</b> passam dela.`],
      'AGU-02': () => [UI.waffle(v, '#C94A3F', '#BFDDF0'), `De cada <b>100 litros</b> tratados: <b class="t-critico">${num(v, 0)} se perdem</b> e <b class="t-ceu">${num(100 - v, 0)} chegam às casas</b>.`],
      'ENE-01': () => [UI.pictos(v, 20, IC.raio, { meta: ref, cor: '#D9822B' }), `Cada <b>raio</b> = 20 kWh por pessoa no mês. A linha marca ${refTxt}.`],
      'ENE-02': () => [UI.pictos(v, 10, IC.sol, { meta: ref, cor: '#D9822B', menorMelhor: false }), `Cada <b>sol</b> = 10 watts de painel por pessoa. ${v < ref ? `Os apagados mostram o que falta para chegar ${verMeta() ? 'à meta' : 'à média das 8 cidades'}.` : `Já está acima ${verMeta() ? 'da meta' : 'da média das 8 cidades'}.`}`],
      'RES-01': () => [UI.pictos(v * 30, 3, IC.saco, { meta: ref * 30, cor: '#3E9A4E' }), `Cada <b>saco</b> = 3 kg de lixo por pessoa no mês. A linha marca ${refTxt}.`],
      'RES-02': () => [UI.waffle(v, '#3E9A4E', '#E3E1DA'), `De cada <b>100 kg</b> de lixo: <b class="t-verde">${num(v, 1)} kg reciclados</b>, o resto vai para o aterro.`],
      'MOB-01': () => [UI.pictos(v, 1, IC.onibus, { meta: ref, cor: '#2B4C8C', menorMelhor: false }), `Cada <b>ônibus</b> = 1 viagem por pessoa no mês. ${v < ref ? `Os apagados mostram o que falta para chegar ${verMeta() ? 'à meta' : 'à média das 8 cidades'}.` : `Já está acima ${verMeta() ? 'da meta' : 'da média das 8 cidades'}.`}`],
      'MOB-02': () => [UI.pictos(v, 10, IC.nuvem, { meta: ref, cor: '#6B7686' }), `Cada <b>nuvem</b> = 10 kg de CO₂ por pessoa no mês. A linha marca ${refTxt}.`],
    }[i.codigo];
    if (!P) return '';
    const [g, leg] = P();
    return `<div class="visual">${g}<p class="vis-leg">${leg}</p></div>`;
  }

  // dados de uma cidade (cidadão: sempre a dele)
  let cidadeSel = null;
  const urlCidade = () => `/minha-cidade${API.usuario.perfil === 'CIDADAO' ? '' : `?municipio=${cidadeSel || API.usuario.municipio || 2}`}`;
  const seletorCidade = async () => {
    if (API.usuario.perfil === 'CIDADAO') return '';
    const ex = await API.pegar('/explorar');
    return `<select class="seletor claro" id="cidade" aria-label="Escolher cidade">${ex.municipios.map((m) => `<option value="${m.id_municipio}" ${m.id_municipio === Number(cidadeSel || API.usuario.municipio || 2) ? 'selected' : ''}>${esc(m.nome)}</option>`).join('')}</select>`;
  };
  const ligarSeletor = (fn) => $('#cidade')?.addEventListener('change', (e) => { cidadeSel = Number(e.target.value); fn(); });
  const ligarFontes = (d) => $$('[data-fonte]').forEach((b) => (b.onclick = () => { const i = d.indicadores.find((x) => x.codigo === b.dataset.fonte); gavetaFonte(i.simples, i.fonte, d.mes); }));
  const valorTxt = (i) => `${num(i.valor, casasDe(i.valor))}`;

  // ============================================================== VISÃO GERAL (os dados primeiro; a nota é um complemento)
  async function painel(app, _x, rota = 'painel') {
    casca(app, rota, esqueleto());
    const desenhar = async () => {
      const [d, ex] = await Promise.all([API.pegar(urlCidade()), API.pegar('/explorar')]);
      cidadeSel = d.municipio.id_municipio;
      const pos = (i) => i.posicao;   // a mesma posição calculada no servidor (sem arredondar)
      const mudancas = d.indicadores.filter((i) => i.variaMes).map((i) => { const s = i.serie; const a = s[s.length - 2]?.v; const var_ = a ? ((i.valor - a) / a) * 100 : 0; return { i, var_, melhor: i.sentido === 'MAIOR_MELHOR' ? var_ > 0 : var_ < 0 }; }).sort((a, b) => Math.abs(b.var_) - Math.abs(a.var_));
      // destaque do mês: o dado mais longe da meta
      const vm = verMeta();
      const dest = vm ? [...d.indicadores].sort((a, b) => a.score - b.score)[0] : [...d.indicadores].sort((a, b) => (b.situacao.nivel === 'CRITICO') - (a.situacao.nivel === 'CRITICO') || Math.abs(b.comparacao.pct) - Math.abs(a.comparacao.pct))[0];
      const nome = esc(d.municipio.nome);
      const cid = API.usuario.perfil === 'CIDADAO';
      $('#conteudo').innerHTML = `
        ${topo(`${nome} em números`, `Água, energia, lixo e transporte em ${esc(d.mesTxt)}. Cada número diz de onde veio e qual é o último dado oficial publicado.`, await seletorCidade(), `<div class="hero-logo">${UI.logo({ anim: true, classe: 'respira' })}<span class="hl-a">Água</span><span class="hl-e">Energia</span><span class="hl-l">Lixo</span><span class="hl-t">Transporte</span></div>`, cid ? `Olá, ${esc(API.usuario.nome.split(' ')[0])}` : 'Visão geral')}
        <dl class="fatos revelar"><div><dt>Moradores</dt><dd class="num">${Number(d.municipio.populacao).toLocaleString('pt-BR')}</dd></div><div><dt>Região</dt><dd>${esc(d.municipio.regiao_metropolitana || 'Estado de SP')}</dd></div>
          <div><dt>Mês dos dados</dt><dd>${esc(d.mesTxt)}</dd></div>${vm ? `<div><dt>Dentro da meta ${UI.info('meta')}</dt><dd><b class="num">${d.indicadores.filter((i) => i.score >= 100).length}</b> de 8 números</dd></div>` : `<div><dt>Melhor que a média</dt><dd><b class="num">${d.indicadores.filter((i) => i.situacao.nivel === 'BOM').length}</b> de 8 números</dd></div>`}</dl>

        ${(() => {
          // UMA barra: cada número da cidade em setembro, pela origem — e, se é estimado, em que oficial ele se apoia
          const CAT = { MES: ['oficial do mês', 'publicado pela fonte para este mês'], ANO: ['oficial do ano', 'total oficial do ano dividido pelos meses'],
            BASE: ['estimado a partir do oficial do ano', 'parte do último total oficial do ano'], SEM: ['estimado sem oficial', 'a cidade não publica este dado'] };
          const cat = (i) => { const o = i.fonte?.origem || i.origem; return o === 'REAL' ? 'MES' : o === 'DERIVADO' ? 'ANO' : i.ultimoOficial ? 'BASE' : 'SEM'; };
          const n = { MES: 0, ANO: 0, BASE: 0, SEM: 0 }; d.indicadores.forEach((i) => { n[cat(i)]++; });
          const ordem = ['MES', 'ANO', 'BASE', 'SEM'].filter((k) => n[k]);
                    return `<section class="origem-resumo revelar">
            <div class="or-cab"><div><span class="chapeu">De onde vêm os 8 números de ${esc(d.mesTxt)} ${UI.info('origem')}</span>
              <p>${[n.MES && `<b>${n.MES}</b> ${n.MES > 1 ? 'oficiais' : 'oficial'} do mês`, n.ANO && `<b>${n.ANO}</b> ${n.ANO > 1 ? 'oficiais' : 'oficial'} do ano`, n.BASE && `<b>${n.BASE}</b> estimado${n.BASE > 1 ? 's' : ''} a partir do último oficial do ano`, n.SEM && `<b>${n.SEM}</b> estimado${n.SEM > 1 ? 's' : ''} sem dado oficial da cidade`].filter(Boolean).join(' · ')}</p></div></div>
            <div class="or-barra unica">${ordem.map((k) => `<i class="c-${k}" style="flex:${n[k]}"><b>${n[k]}</b><span>${CAT[k][0]}</span></i>`).join('')}</div>
            <ul class="or-leg">${ordem.map((k) => `<li><i class="c-${k}"></i><b>${CAT[k][0]}</b> ${CAT[k][1]}</li>`).join('')}</ul>
            <span class="chapeu or-sub">Último dado oficial de cada número</span>
            <div class="of-grade">${d.indicadores.map((i) => { const uo = i.ultimoOficial; const k = cat(i);
              return `<article class="of-card c-${k}" style="--c:${SERV[i.servico].cor}">
                <header>${icoArea(i.servico)}<span>${esc(i.simples)}</span></header>
                ${uo ? `<b class="num">${num(uo.valor, casasDe(uo.valor))}</b><small>${esc(i.unidadeSimples || i.unidade)}</small>
                  <footer><span class="selo o-${uo.origem}">${SELO[uo.origem]}</span><em>${esc(mesCurto(uo.mes))} · ${esc(String(uo.fonte).split(' (')[0])}</em></footer>`
                : `<b class="num">—</b><small>${esc(i.unidadeSimples || i.unidade)}</small><footer><span class="selo o-ESTIMADO">Sem oficial</span><em>a cidade não publica</em></footer>`}</article>`; }).join('')}</div></section>`; })()}
        <section class="destaque revelar" style="--c:${SERV[dest.servico].cor}">
          <div class="ds-txt"><span class="chapeu"><i></i>Destaque do mês · ${esc(dest.simples)}</span><p class="ds-frase">${UI.md(dest.frase)}</p><p>${selo(dest.fonte?.origem || dest.origem)}</p><p class="ds-sub">${UI.md(dest.compara)} ${esc(vm ? dest.metaTxt : dest.mediaTxt)}</p>
            ${fonteLinha(dest.fonte, `data-fonte="${dest.codigo}"`)}<a class="seta-link" href="#/app/${areaDe(dest.servico)}">Ver a história completa</a></div>
          <div class="ds-vis">${visual(dest)}</div></section>

        <section class="meta3d revelar"><div class="m3-txt"><span class="chapeu">Entre as 8 cidades</span><h2>Cada prédio é um dos 8 números</h2>
            <p>Para cada número, as 8 cidades são colocadas em fila, da melhor para a pior. O prédio mostra o lugar da sua cidade nessa fila: <b>1º lugar = prédio inteiro</b> (até o contorno tracejado), <b>8º lugar = prédio bem baixo</b>.${vm ? ' Ao lado, se o número cumpre a meta.' : ''} Passe o mouse para girar a cidade.</p>
            <ul class="m3-lista">${d.indicadores.map((i) => `<li style="--c:${SERV[i.servico].cor}"><i></i>${esc(i.simples)}<b class="sit s-${i.situacao.nivel}">${i.posicao}º de 8${vm ? (i.score >= 100 ? ' · na meta' : ' · fora da meta') : ''}</b></li>`).join('')}</ul></div>
          ${UI.cidade3d(d.indicadores.map((i) => ({ nome: i.simples, valor: ((9 - i.posicao) / 8) * 100, cor: SERV[i.servico].cor, txt: `${valorTxt(i)} ${i.unidade} · ${i.situacao.rotulo.toLowerCase()}` })), { legenda: ['altura = lugar entre as 8 cidades', 'contorno = 1º lugar'] })}</section>

        <div class="sec-cab revelar"><h2>Os 8 números da cidade</h2><p>Toque em um número para ver o gráfico, a comparação com as outras cidades e a fonte.</p>
          <div class="modo-num" role="group" aria-label="Quais números mostrar"><button data-modo="recente" class="${modoNum === 'recente' ? 'ativo' : ''}">Mais recentes (${esc(d.mesTxt)})</button><button data-modo="oficial" class="${modoNum === 'oficial' ? 'ativo' : ''}">Últimos oficiais</button></div></div>
        <div class="grade g-4">${d.indicadores.map((i, k) => { const a = areaDe(i.servico); const uo = i.ultimoOficial; const vOf = modoNum === 'oficial';
          const valorMostrado = vOf ? (uo ? num(uo.valor, casasDe(uo.valor)) : '—') : valorTxt(i);
          const seloMostrado = vOf ? (uo ? selo(uo.origem) : '<span class="selo o-ESTIMADO">Sem oficial</span>') : selo(i.fonte?.origem || i.origem);
          const quando = vOf ? (uo ? `<span class="d-quando">${esc(uo.mesTxt)} · ${esc(uo.fonte)}</span>` : `<span class="d-quando">${esc(i.semOficial || '')}</span>`) : '';
          return `<a class="dado revelar" style="--c:${SERV[i.servico].cor};--atraso:${(k % 4) * 0.06}s" href="#/app/${a}">
          <span class="d-area"><i></i>${esc(AREAS[a].titulo)}${seloMostrado}</span>
          <b class="d-valor num">${valorMostrado}</b><span class="d-un">${esc(i.unidadeSimples)}</span>${quando}
          <span class="d-nome">${esc(i.simples)}</span>${UI.spark(i.serie.slice(-12).map((s) => s.v), SERV[i.servico].cor, 0.2 + k * 0.05)}
          <span class="d-pe"><span class="sit s-${i.situacao.nivel}">${esc(i.situacao.rotulo)}</span><span>${pos(i)}º de 8</span></span>
          <span class="d-fonte">Fonte: ${esc([...new Set(i.fonte.fontes.map((x) => x.fonte.split(' - ')[0]))].join(' + '))} · ${ORIG[i.fonte.origem]}</span>
          ${vOf ? `<span class="d-ult u-antigo">Mais recente (${esc(d.mesTxt)}): ${valorTxt(i)} · ${ORIG[i.fonte.origem]}</span>` : `<span class="d-ult u-${ultOfTxt(i).cls}">${esc(ultOfTxt(i).curto)}</span>`}</a>`; }).join('')}</div>

        <div class="grade g-2" style="margin-top:28px">
          <section class="cartao revelar"><div class="cab-c"><h3>O que mais mudou desde o mês passado</h3><a class="seta-link" href="#/app/mes">Tudo</a></div>
            ${mudancas.slice(0, 4).map(({ i, var_, melhor }) => `<div class="mud">${icoArea(i.servico)}<div><b>${esc(i.simples)}</b><small class="num">${valorTxt(i)} ${esc(i.unidade)}</small></div><span class="m-var num ${melhor ? 'ok' : 'ruim'}">${var_ >= 0 ? '+' : '−'}${num(Math.abs(var_), 1)}%<small>${melhor ? 'melhorou' : 'piorou'}</small></span></div>`).join('')}</section>
          <section class="cartao revelar" style="--atraso:.08s"><div class="cab-c"><h3>${nome} entre as 8 cidades</h3><a class="seta-link" href="#/app/comparar">Comparar</a></div>
            ${d.indicadores.map((i) => { const p = pos(i); return `<div class="pos-l"><span>${esc(i.simples)}</span><span class="trilho-pos" style="--c:${SERV[i.servico].cor}">${[...Array(8)].map((_, k) => `<i class="${k + 1 === p ? 'eu' : ''}"></i>`).join('')}</span><b class="num">${p}º</b></div>`; }).join('')}
            <small class="nota-rodape">1º = melhor resultado entre as 8 cidades.</small></section></div>

        `;
      revelar($('#conteudo')); UI.ativarGraficos($('#conteudo')); UI.ativar3d($('#conteudo')); ligarFontes(d); ligarSeletor(desenhar);
      $$('.modo-num button').forEach((b) => (b.onclick = () => { modoNum = b.dataset.modo; desenhar(); }));
    };
    await desenhar();
  }

  // ============================================================== PÁGINA DE UMA ÁREA (água, energia, lixo, transporte)
  async function area(app, chave) {
    const A = AREAS[chave];
    casca(app, chave, esqueleto());
    const desenhar = async () => {
      const [d, ex, dicas] = await Promise.all([API.pegar(urlCidade()), API.pegar('/explorar'), API.get(`/dicas/${chave}`).catch(() => null)]);
      cidadeSel = d.municipio.id_municipio;
      const its = d.indicadores.filter((i) => A.cods.includes(i.codigo));
      const nomeDe = (id) => ex.municipios.find((m) => m.id_municipio === id)?.nome;
      const alertas = d.alertas.filter((a) => a.servico === A.servico);
      $('#conteudo').innerHTML = `
        ${topo(`${A.titulo} em ${esc(d.municipio.nome)}`, `${A.desc} Dados de <b>${esc(d.mesTxt)}</b>.`, await seletorCidade(), Cenas.cena(chave), 'Os dados')}
        ${its.map((i, k) => {
          const ult = ex.serie.filter((s) => s.c === i.codigo && s.p === d.mes).sort((a, b) => (i.sentido === 'MAIOR_MELHOR' ? b.v - a.v : a.v - b.v));
          const pos = i.posicao;
          return `<section class="historia revelar" style="--c:${SERV[A.servico].cor}">
            <div class="hs-cab"><span class="hs-ico">${icoArea(i.servico)}</span><div><span class="rotulo">${k + 1} de ${its.length} · ${esc(i.nome)}</span><h2>${esc(i.simples)}</h2></div>${pilula(i.situacao.nivel, i.situacao.rotulo)}</div>
            <div class="hs-corpo">
              <div class="hs-num"><b>${valorTxt(i)}</b><span>${esc(i.unidadeSimples)} ${selo(i.fonte?.origem || i.origem)}</span>
                <p class="ih-frase">${UI.md(i.frase)}</p><p class="ih-comp">${UI.md(i.compara)}</p>
                <div class="ih-meta"><span>${esc(verMeta() ? i.metaTxt : i.mediaTxt)}${verMeta() ? ` ${UI.info('meta')}` : ''}</span>${i.tendencia ? `<span class="${i.tendencia.melhor ? 'ok' : i.tendencia.melhor === false ? 'ruim' : ''}">${i.tendencia.melhor ? '↗' : i.tendencia.melhor === false ? '↘' : '→'} ${esc(i.tendencia.texto)}</span>` : ''}<span title="Posição entre as 8 cidades: 1º = melhor resultado, 8º = pior">${pos}º lugar entre as 8 cidades (1º = melhor)</span></div></div>
              <div class="hs-vis">${visual(i)}</div></div>
            <div class="grade g-hero inv" style="margin-top:18px">
              <div class="cartao"><span class="rotulo">Mês a mês (24 meses)</span>${UI.linha([{ nome: d.municipio.nome, valores: i.serie.map((s) => s.v), cor: SERV[i.servico].cor, area: true }], { altura: 240, largura: 620, rotulos: i.serie.map((s) => mesTxt(s.p)), meta: verMeta() ? i.meta : null, unidade: i.unidade, casas: casasDe(i.valor), origens: i.serie.map((s) => s.o), refOficial: ofAntes(i, i.serie) })}${i.ultimoOficial ? '' : `<p class="sem-of">${esc(i.semOficial || 'Sem dado oficial para esta cidade.')}</p>`}</div>
              <div class="cartao"><span class="rotulo">Nas 8 cidades · ${mesTxt(d.mes)}</span>${UI.barrasH(ult.map((s) => ({ rotulo: nomeDe(s.m), valor: s.v, destaque: s.m === cidadeSel })), { meta: refDe(i), refNome: verMeta() ? 'meta' : 'média das 8', unidade: i.unidade, casas: casasDe(i.valor), sentido: i.sentido })}</div></div>
            <div class="hs-pe"><p><b>Por que importa:</b> ${esc(i.importa)}</p>${ultOfLinha(i)}${fonteLinha(i.fonte, `data-fonte="${i.codigo}"`)}</div>
          </section>`; }).join('')}
        <div class="grade g-2" style="margin-top:22px">
          <div class="cartao borda-${A.cor} revelar"><span class="rotulo">O que você pode fazer em casa</span>${dicas ? `<div class="dicas-lista">${dicas.itens.slice(0, 4).map(([t, x]) => `<div><b>${esc(t)}</b><p>${esc(x)}</p></div>`).join('')}</div><p class="calc-conta">${UI.md(dicas.conta)}</p>` : ''}
            <a class="btn sm" style="margin-top:12px" href="#/app/economize/${chave}">Calcular a economia da minha casa →</a></div>
          <div class="cartao borda-critico revelar" style="--atraso:.08s"><span class="rotulo">Alertas de ${esc(A.titulo.toLowerCase())}</span>
            ${alertas.length ? alertas.map((a) => `<div class="alerta-mini"><span>${a.bom ? '' : a.severidade === 'CRITICO' ? '' : ''}</span><div><b>${esc(a.simples)}</b><small>${UI.md(a.explicacao)}</small></div></div>`).join('') : '<p style="color:var(--tinta-2)">Nenhum alerta nesta área agora. </p>'}</div></div>`;
      revelar($('#conteudo')); UI.ativarGraficos($('#conteudo')); ligarFontes(d); ligarSeletor(desenhar);
    };
    await desenhar();
  }

  // ============================================================== COMPARAR CIDADES
  let cmp = { cod: 'AGU-01', a: null, b: null };
  async function comparar(app) {
    casca(app, 'comparar', esqueleto());
    const ex = await API.pegar('/explorar');
    const minha = API.usuario.municipio || ex.municipios[0].id_municipio;
    cmp.a ||= minha; cmp.b ||= ex.municipios.find((m) => m.id_municipio !== cmp.a).id_municipio;
    const ult = (c, m) => ex.serie.find((s) => s.c === c && s.m === m && s.p === ex.mes);
    const ano = (c, m) => ex.serie.find((s) => s.c === c && s.m === m && s.p === ex.meses[ex.meses.length - 13]);
    const nomeDe = (id) => ex.municipios.find((m) => m.id_municipio === id)?.nome;
    const opts = (sel) => ex.municipios.map((m) => `<option value="${m.id_municipio}" ${m.id_municipio === sel ? 'selected' : ''}>${esc(m.nome)}</option>`).join('');
    $('#conteudo').innerHTML = `${topo('Comparar cidades', 'Escolha um dado e veja as 8 cidades lado a lado, ou coloque duas cidades frente a frente.')}
      <div class="chips-ind revelar" id="chipsInd">${ex.indicadores.map((i) => `<button data-c="${i.codigo}" class="t-${AREAS[areaDe(i.servico)].cor} ${i.codigo === cmp.cod ? 'ativo' : ''}">${icoArea(i.servico)} ${esc(i.simples)}</button>`).join('')}</div>
      <div id="cmp8"></div>
      <h2 class="titulo-sec revelar">Frente a frente</h2>
      <div class="cartao revelar"><div class="vs-sel"><select class="seletor" id="ca">${opts(cmp.a)}</select><span class="vs">VS</span><select class="seletor" id="cb">${opts(cmp.b)}</select></div><div id="vs"></div></div>`;
    const d8 = () => {
      const i = ex.indicadores.find((x) => x.codigo === cmp.cod); const cor = SERV[i.servico].cor;
      const lista = ex.municipios.map((m) => ({ m, s: ult(i.codigo, m.id_municipio), a: ano(i.codigo, m.id_municipio) })).filter((x) => x.s).sort((x, y) => (i.sentido === 'MAIOR_MELHOR' ? y.s.v - x.s.v : x.s.v - y.s.v));
      const vm = verMeta(); const media8 = lista.reduce((a, x) => a + x.s.v, 0) / (lista.length || 1);
      const melhorQue = (v) => (i.sentido === 'MAIOR_MELHOR' ? v > media8 : v < media8);
      const naMeta = vm ? lista.filter((x) => x.s.s >= 100).length : lista.filter((x) => melhorQue(x.s.v)).length;
      $('#cmp8').innerHTML = `<div class="grade g-hero inv" style="margin-top:20px">
        <div class="cartao revelar"><span class="rotulo">${icoArea(i.servico)} ${esc(i.nome)} · ${esc(i.unidade)} · ${mesTxt(ex.mes)}</span>${UI.barrasH(lista.map((x) => ({ rotulo: x.m.nome, valor: x.s.v, destaque: x.m.id_municipio === minha })), { meta: vm ? i.meta : media8, refNome: vm ? 'meta' : 'média das 8', unidade: i.unidade, casas: casasDe(media8), sentido: i.sentido })}</div>
        <div class="cartao revelar destaque-c" style="--c:${cor}"><span class="rotulo">Em resumo</span><p class="big"><b>${esc(lista[0].m.nome)}</b> tem o melhor resultado.</p><p class="big">${vm ? (naMeta ? `<b>${naMeta}</b> de 8 cidades estão dentro da meta.` : '<b>Nenhuma</b> cidade está dentro da meta.') : `<b>${naMeta}</b> de 8 cidades estão melhores que a média.`}</p>
          <p>${i.sentido === 'MAIOR_MELHOR' ? 'Aqui, quanto <b>maior</b>, melhor.' : 'Aqui, quanto <b>menor</b>, melhor.'} ${vm ? `Meta: <b>${num(i.meta, casasDe(i.meta))} ${esc(i.unidade)}</b> ${UI.info('meta')}` : `Média das 8 cidades: <b>${num(media8, casasDe(media8))} ${esc(i.unidade)}</b>`}.</p>
          <div class="rolar-x"><table class="tabela"><caption class="cap-tab">Valores em <b>${esc(i.unidadeSimples || i.unidade)}</b></caption><thead><tr><th>Cidade</th><th>${esc(mesTxt(ex.mes))}</th><th>Mesmo mês do ano passado</th></tr></thead><tbody>${lista.map((x) => { const melhor = x.a ? (i.sentido === 'MAIOR_MELHOR' ? x.s.v > x.a.v : x.s.v < x.a.v) : null; return `<tr><td>${esc(x.m.nome)}</td><td class="num"><b>${num(x.s.v, casasDe(x.s.v))}</b></td><td class="num">${x.a ? `${num(x.a.v, casasDe(x.a.v))} <span class="${melhor ? 't-verde' : 't-critico'}">${melhor ? '↗' : '↘'}</span>` : '—'}</td></tr>`; }).join('')}</tbody></table></div></div></div>`;
      revelar($('#cmp8'));
    };
    const vs = () => {
      let pa = 0, pb = 0;
      const linhas = ex.indicadores.map((i) => { const a = ult(i.codigo, cmp.a), b = ult(i.codigo, cmp.b); if (!a || !b) return ''; const ganhaA = i.sentido === 'MAIOR_MELHOR' ? a.v > b.v : a.v < b.v; if (ganhaA) pa++; else pb++;
        const mx = Math.max(a.v, b.v) || 1;
        return `<div class="vs-l"><div class="vs-a ${ganhaA ? 'ganha' : ''}"><b>${num(a.v, casasDe(a.v))}</b><span class="bar"><i style="width:${(a.v / mx) * 100}%"></i></span></div>
          <div class="vs-m">${icoArea(i.servico)}<small>${esc(i.simples)}<em>${esc(i.unidadeSimples || i.unidade)}</em></small></div>
          <div class="vs-b ${!ganhaA ? 'ganha' : ''}"><span class="bar"><i style="width:${(b.v / mx) * 100}%"></i></span><b>${num(b.v, casasDe(b.v))}</b></div></div>`; }).join('');
      $('#vs').innerHTML = `<div class="placar"><div><b>${esc(nomeDe(cmp.a))}</b><span>${pa}</span></div><small>dados em que cada cidade está melhor</small><div><span>${pb}</span><b>${esc(nomeDe(cmp.b))}</b></div></div>
        <p class="vs-ajuda">Cada linha é um dos 8 números, no mês de <b>${esc(mesTxt(ex.mes))}</b>. O número de cada lado é o valor da cidade (a unidade está embaixo do nome do dado). O tamanho da barra mostra o tamanho do número. A barra <b>colorida</b> é de quem está melhor naquele número (às vezes o melhor é o menor, como no lixo); a cinza, de quem está pior. O placar acima conta em quantos números cada cidade ganha.</p>${linhas}`;
    };
    $$('#chipsInd button').forEach((b) => (b.onclick = () => { cmp.cod = b.dataset.c; $$('#chipsInd button').forEach((x) => x.classList.toggle('ativo', x === b)); d8(); }));
    $('#ca').onchange = (e) => { cmp.a = Number(e.target.value); vs(); }; $('#cb').onchange = (e) => { cmp.b = Number(e.target.value); vs(); };
    revelar($('#conteudo')); d8(); vs();
  }

  // ============================================================== MAPA DAS CIDADES
  let mapaCod = 'AGU-01';
  async function mapa(app) {
    casca(app, 'mapa', esqueleto());
    const ex = await API.pegar('/explorar');
    const W = 760, H = 460; const lon = ex.municipios.map((m) => Number(m.longitude)), lat = ex.municipios.map((m) => Number(m.latitude));
    const x = (v) => 70 + ((v - Math.min(...lon)) / (Math.max(...lon) - Math.min(...lon))) * (W - 160);
    const y = (v) => 50 + ((Math.max(...lat) - v) / (Math.max(...lat) - Math.min(...lat))) * (H - 140);
    const minha = API.usuario.municipio;
    const AJUSTE = { 'Guarulhos': [40, -42], 'Santo André': [26, 30], 'São Paulo': [-46, -6], 'Santos': [10, 10] };   // afasta as cidades vizinhas para não se sobreporem
    const px = (m) => x(m.longitude) + (AJUSTE[m.nome]?.[0] || 0); const py = (m) => y(m.latitude) + (AJUSTE[m.nome]?.[1] || 0);
    $('#conteudo').innerHTML = `${topo('Mapa das cidades', `Onde fica cada cidade e como está cada dado. O tamanho da bolha mostra o valor; a cor mostra se está ${verMeta() ? 'na meta' : 'melhor ou pior que a média das 8 cidades'}.`)}
      <div class="chips-ind revelar" id="chipsInd">${ex.indicadores.map((i) => `<button data-c="${i.codigo}" class="t-${AREAS[areaDe(i.servico)].cor} ${i.codigo === mapaCod ? 'ativo' : ''}">${icoArea(i.servico)} ${esc(i.simples)}</button>`).join('')}</div>
      <div class="grade g-hero inv" style="margin-top:20px"><div class="cartao mapa-c revelar"><div id="mapaSvg"></div></div><div class="cartao revelar" id="mapaInfo"></div></div>`;
    const desenhar = (sel = minha || ex.municipios[0].id_municipio) => {
      const i = ex.indicadores.find((k) => k.codigo === mapaCod);
      const vals = ex.municipios.map((m) => ex.serie.find((s) => s.c === mapaCod && s.m === m.id_municipio && s.p === ex.mes));
      const mx = Math.max(...vals.map((v) => v?.v || 0)) || 1;
      const vm = verMeta(); const okVals = vals.filter(Boolean); const media8 = okVals.reduce((a, v) => a + v.v, 0) / (okVals.length || 1);
      const bom = (k, v) => (vm ? v.s >= 100 : (k.sentido === 'MAIOR_MELHOR' ? v.v > media8 : v.v < media8));
      $('#mapaSvg').innerHTML = `<svg viewBox="0 0 ${W} ${H}" class="mapa-svg"><defs><linearGradient id="terra" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F4F2EC"/><stop offset="1" stop-color="#ECE8DE"/></linearGradient><linearGradient id="mar" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#E1EDF5"/><stop offset="1" stop-color="#B9D5E8"/></linearGradient></defs>
        <rect width="${W}" height="${H}" rx="22" fill="url(#terra)"/>
        <path d="M0 ${H} L0 ${y(-24.25)} C ${x(-47.2)} ${y(-24.4)} ${x(-46.6)} ${y(-24.1)} ${x(-46.25)} ${y(-24.02)} S ${x(-45.6)} ${y(-23.75)} ${W} ${y(-23.45)} L ${W} ${H} Z" fill="url(#mar)"/>
        <g class="ondas-mapa">${[0, 1, 2].map((k) => `<path d="M${W - 260 + k * 60} ${H - 60 + k * 14} q15 -8 30 0 t30 0" stroke="#fff" stroke-width="2" fill="none" opacity=".7"/>`).join('')}</g>
        <text x="${W - 200}" y="${H - 18}" class="mar-t">Oceano Atlântico</text>
        <path d="M${x(-47.81)} ${y(-21.18)} Q ${x(-47.5)} ${y(-22.3)} ${x(-47.06)} ${y(-22.91)} T ${x(-46.63)} ${y(-23.55)}" stroke="#8193AB" stroke-width="2" stroke-dasharray="4 6" fill="none" opacity=".5"/>
        ${ex.municipios.map((m, k) => { const v = vals[k]; if (!v) return ''; const r = 12 + Math.sqrt(v.v / mx) * 24; const ok = bom(i, v);
          return `<g class="bolha ${m.id_municipio === sel ? 'sel' : ''} ${ok ? 'ok' : 'fora'}" data-m="${m.id_municipio}" tabindex="0" role="button" aria-label="${esc(m.nome)}: ${num(v.v, casasDe(v.v))}" style="--atraso:${k * 0.08}s">
            <circle class="pulso" cx="${px(m)}" cy="${py(m)}" r="${r}"/><circle class="b" cx="${px(m)}" cy="${py(m)}" r="${r}"/>
            <text x="${px(m)}" y="${py(m) + 4}" text-anchor="middle" class="bv">${num(v.v, casasDe(v.v) > 1 ? 1 : 0)}</text>
            <text x="${px(m)}" y="${py(m) + r + 16}" text-anchor="middle" class="bn">${esc(m.nome)}${m.id_municipio === minha ? ' ★' : ''}</text></g>`; }).join('')}</svg>
        <div class="leg-mapa"><span><i class="ok"></i>${vm ? 'dentro da meta' : 'melhor que a média'}</span><span><i class="fora"></i>${vm ? 'fora da meta' : 'pior que a média'}</span><span>valor em ${esc(i.unidade)}${minha ? ' · ★ sua cidade' : ''}</span></div>`;
      const m = ex.municipios.find((k) => k.id_municipio === Number(sel));
      const linhas = ex.indicadores.map((k) => ({ k, s: ex.serie.find((s) => s.c === k.codigo && s.m === m.id_municipio && s.p === ex.mes) }));
      const okInd = (k, sv) => { if (vm) return sv.s >= 100; const vs = ex.serie.filter((x) => x.c === k.codigo && x.p === ex.mes).map((x) => x.v); const md = vs.reduce((a, b) => a + b, 0) / vs.length; return k.sentido === 'MAIOR_MELHOR' ? sv.v > md : sv.v < md; };
      $('#mapaInfo').innerHTML = `<span class="rotulo">${esc(m.nome)}</span><p style="color:var(--tinta-2);margin-bottom:12px">${Number(m.populacao).toLocaleString('pt-BR')} moradores · ${num(m.area_km2, 0)} km² · ${esc(m.regiao_metropolitana || '')}</p>
        ${linhas.map(({ k, s }) => `<div class="info-l ${k.codigo === mapaCod ? 'sel' : ''}"><span>${icoArea(k.servico)} ${esc(k.simples)}</span><b>${s ? num(s.v, casasDe(s.v)) : '—'} <small>${esc(k.unidade)}</small></b>${s ? `<em class="${okInd(k, s) ? 'ok' : 'fora'}" title="${okInd(k, s) ? (vm ? 'na meta' : 'melhor que a média') : (vm ? 'fora da meta' : 'pior que a média')}">${okInd(k, s) ? '✓' : '✕'}</em>` : ''}</div>`).join('')}
        ${API.usuario.perfil === 'CIDADAO' ? '' : `<a class="btn sm" style="margin-top:14px" href="#/app/cidade" onclick="Painel.verCidade(${m.id_municipio})">Ver ${esc(m.nome)} →</a>`}`;
      $$('.bolha').forEach((b) => { const ir = () => desenhar(b.dataset.m); b.onclick = ir; b.onkeydown = (e) => e.key === 'Enter' && ir(); });
    };
    $$('#chipsInd button').forEach((b) => (b.onclick = () => { mapaCod = b.dataset.c; $$('#chipsInd button').forEach((x) => x.classList.toggle('ativo', x === b)); desenhar(); }));
    revelar($('#conteudo')); desenhar();
  }

  // ============================================================== O QUE MUDOU NO MÊS
  async function mes(app) {
    casca(app, 'mes', esqueleto());
    const desenhar = async () => {
      const d = await API.pegar(urlCidade());
      cidadeSel = d.municipio.id_municipio;
      const linhas = d.indicadores.map((i) => { const s = i.serie; const ant = s[s.length - 2]; const ano = s[s.length - 13];
        const vm = ant ? ((i.valor - ant.v) / ant.v) * 100 : 0; const va = ano ? ((i.valor - ano.v) / ano.v) * 100 : 0; const bom = (v) => (i.sentido === 'MAIOR_MELHOR' ? v > 0 : v < 0);
        return { i, ant, ano, vm, va, bomM: bom(vm), bomA: bom(va) }; });
      const mensais = linhas.filter((l) => l.i.variaMes);
      const melhorou = mensais.filter((l) => l.bomM && Math.abs(l.vm) >= 0.5).length; const piorou = mensais.filter((l) => !l.bomM && Math.abs(l.vm) >= 0.5).length;
      const caixaVar = (rot, v, ok, era, mensal = true) => (!mensal ? `<div class="neutro"><small>${rot}</small><b>não muda</b><span>vem de um total anual</span></div>`
        : Math.abs(v) < 0.05 ? `<div class="neutro"><small>${rot}</small><b>= igual</b><span>era ${era}</span></div>`
        : `<div class="${ok ? 'ok' : 'ruim'}"><small>${rot}</small><b>${v >= 0 ? '▲' : '▼'} ${num(Math.abs(v), 1)}%</b><span>era ${era}</span></div>`);
      $('#conteudo').innerHTML = `${topo(`O que mudou em ${esc(d.mesTxt)}`, `Cada dado de ${esc(d.municipio.nome)} comparado com o mês anterior e com o mesmo mês do ano passado.`, await seletorCidade())}
        <div class="grade g-3"><div class="cartao kpi-r verde revelar"><b data-contar="${melhorou}">0</b><div><strong>melhoraram</strong><small>em relação ao mês passado</small></div></div>
          <div class="cartao kpi-r critico revelar" style="--atraso:.06s"><b data-contar="${piorou}">0</b><div><strong>pioraram</strong><small>em relação ao mês passado</small></div></div>
          <div class="cartao kpi-r laranja revelar" style="--atraso:.12s"><b data-contar="${linhas.length - melhorou - piorou}">0</b><div><strong>ficaram iguais</strong><small>variação menor que 0,5% ou dado anual</small></div></div></div>
        <p class="nota-rodape revelar">Água, lixo e poluição só têm número oficial por <b>ano</b>: o total do ano é dividido pelos meses. Por isso eles “não mudam” de um mês para o outro — compare com o ano passado.</p>
        <div class="grade g-2" style="margin-top:20px">${linhas.map((l, k) => { const a = AREAS[areaDe(l.i.servico)]; return `<article class="cartao mes-c borda-${a.cor} revelar" style="--atraso:${(k % 2) * 0.06}s">
          <header><span class="dt-ico">${icoArea(l.i.servico)}</span><div><h3>${esc(l.i.simples)}</h3><small>${esc(l.i.unidade)} ${selo(l.i.fonte?.origem || l.i.origem)}</small></div><b class="mv">${valorTxt(l.i)}</b></header>
          <div class="mes-cmp">${caixaVar('vs mês passado', l.vm, l.bomM, l.ant ? num(l.ant.v, casasDe(l.ant.v)) : '—', l.i.variaMes)}
            ${caixaVar('vs há 1 ano', l.va, l.bomA, l.ano ? num(l.ano.v, casasDe(l.ano.v)) : '—')}</div>
          ${UI.colunas(l.i.serie.slice(-12).map((s) => s.v), l.i.serie.slice(-12).map((s) => mesTxt(s.p).slice(0, 3)), SERV[l.i.servico].cor, { meta: verMeta() ? l.i.meta : null, sentido: l.i.sentido, casas: casasDe(l.i.valor), origens: l.i.serie.slice(-12).map((s) => s.o), oficialAntes: ofAntes(l.i, l.i.serie.slice(-12)) })}
          ${l.i.ultimoOficial ? `<p class="ult-of u-of">${ico('fonte')}<span>Último dado oficial: <b>${num(l.i.ultimoOficial.valor, casasDe(l.i.ultimoOficial.valor))} ${esc(l.i.unidade)}</b> em ${esc(l.i.ultimoOficial.mesTxt)} (${esc(l.i.ultimoOficial.fonte)})</span></p>` : `<p class="sem-of">${esc(l.i.semOficial || 'Sem dado oficial para esta cidade.')}</p>`}
          ${fonteLinha(l.i.fonte, `data-fonte="${l.i.codigo}"`)}</article>`; }).join('')}</div>`;
      revelar($('#conteudo')); ligarFontes(d); ligarSeletor(desenhar);
    };
    await desenhar();
  }

  // ============================================================== ALERTAS (só da cidade do cidadão)
  async function alertas(app) {
    casca(app, 'alertas', esqueleto());
    const d = await API.pegar('/minha-cidade');
    const ruins = d.alertas.filter((a) => !a.bom); const boas = d.alertas.filter((a) => a.bom);
    const nivel = d.risco?.nivel || 'MEDIO';
    const TXT = { ALTO: ['critico', 'Risco alto', 'Vários números estão piores que nas outras cidades ou piorando. Vale a atenção da prefeitura e de todos.'], MEDIO: ['laranja', 'Risco médio', 'Alguns números estão piores que nas outras cidades ou piorando. Nada urgente, mas precisa de cuidado.'], BAIXO: ['verde', 'Risco baixo', 'A cidade está no caminho certo na maioria das áreas.'] }[nivel];
    const card = (a, i) => `<article class="alerta-s ${a.bom ? 'bom' : a.severidade} revelar" style="--atraso:${Math.min(i, 6) * 0.06}s">
      <span class="as-ico">${icoArea(a.servico)}</span><div><h3>${esc(a.simples)}</h3><p>${UI.md(a.explicacao)}</p>${a.importa ? `<p class="as-imp"><b>Por que importa:</b> ${esc(a.importa)}</p>` : ''}
      <div class="as-links"><a href="#/app/${areaDe(a.servico)}">Ver os dados →</a>${!a.bom ? `<a href="#/app/economize/${areaDe(a.servico)}">O que eu posso fazer em casa →</a>` : ''}</div></div></article>`;
    $('#conteudo').innerHTML = `
      ${topo(`Alertas de ${esc(d.municipio.nome)}`, `Todo mês uma inteligência artificial confere os números da sua cidade e avisa quando algo piora, fica pior que nas outras cidades ou foge do normal. Dados de ${esc(d.mesTxt)}.`)}
      <section class="risco-hero ${TXT[0]} revelar"><div class="rh-radar">${ico('radar', '#fff', 1.6)}</div><div><span class="rotulo">Situação geral</span><h2>${TXT[1]}</h2><p>${TXT[2]}</p></div>
        <div class="rh-areas">${d.areas.map((a) => `<div><small>${esc(a.servico)}</small>${pilula(a.nivel)}</div>`).join('')}</div></section>
      <h2 class="titulo-sec revelar">Pontos de atenção <span class="cont">${ruins.length}</span></h2>
      <div class="grade">${ruins.length ? ruins.map(card).join('') : '<div class="cartao">Nenhum ponto de atenção agora. </div>'}</div>
      ${boas.length ? `<h2 class="titulo-sec revelar">Boas notícias</h2><div class="grade">${boas.map(card).join('')}</div>` : ''}
      <p class="nota-rodape revelar">Os alertas mostram só a sua cidade. A IA compara cada número com o mesmo mês do ano passado, com as outras cidades e com a previsão para os próximos 3 meses.</p>`;
    revelar($('#conteudo'));
  }

  // ============================================================== ECONOMIZE EM CASA (calculadoras)
  async function economize(app, tema) {
    casca(app, 'economize', esqueleto());
    const d = await API.pegar(urlCidade());
    const ind = (c) => d.indicadores.find((i) => i.codigo === c);
    let aba = ['agua', 'energia', 'lixo', 'transporte'].includes(tema) ? tema : 'agua';
    const ABAS = [['agua', '', 'Água'], ['energia', '', 'Energia'], ['lixo', '', 'Lixo'], ['transporte', '', 'Transporte']];
    $('#conteudo').innerHTML = `
      ${topo('Economize em casa', 'Mexa nos controles e veja quanto sua casa gasta e quanto dá para economizar. Os valores em reais são aproximados.')}
      <div class="abas grandes" id="abasE">${ABAS.map(([k, e, t]) => `<button data-a="${k}" class="t-${AREAS[k].cor} ${k === aba ? 'ativo' : ''}">${e} ${t}</button>`).join('')}</div>
      <div id="calc" style="margin-top:22px"></div>`;
    const R = (v, d_ = 0) => `R$ ${num(v, d_)}`;
    const ctl = (id, rot, min, max, val, passo = 1, suf = '') => `<label class="ctl"><span>${rot}<b id="v-${id}">${val}${suf}</b></span><input type="range" id="${id}" min="${min}" max="${max}" step="${passo}" value="${val}" data-suf="${suf}"></label>`;
    const sw = (id, rot, on = false) => `<label class="sw"><input type="checkbox" id="${id}" ${on ? 'checked' : ''}><i></i>${rot}</label>`;
    const CALC = {
      agua: {
        form: `${ctl('p', 'Pessoas na casa', 1, 8, 3)}${ctl('b', 'Minutos de banho (cada pessoa)', 2, 30, 12, 1, ' min')}${ctl('l', 'Lavagens de louça por dia', 0, 4, 2)}${ctl('c', 'Lavar calçada/quintal com mangueira (vezes por semana)', 0, 7, 1)}${ctl('m', 'Máquina de lavar roupa (vezes por semana)', 0, 10, 3)}
          ${sw('t', 'Deixo a torneira aberta ao escovar os dentes', true)}${sw('v', 'Descarga de válvula (parede) em vez de caixa acoplada')}`,
        conta(v) {
          const dia = v.p * (v.b * 9 + (v.t ? 24 : 2) + 5 * (v.v ? 12 : 6) + 10) + v.l * 117 + (v.c * 280 + v.m * 135) / 7;
          const eco = v.p * (Math.max(0, v.b - 5) * 9 + (v.t ? 22 : 0) + (v.v ? 30 : 0)) + v.l * 97 + (v.c * 280 * 0.85) / 7;
          const pp = dia / v.p; const cid = ind('AGU-01');
          return { grande: `${num(dia * 30 / 1000, 1)} m³`, sub: `por mês · ${num(pp, 0)} litros por pessoa por dia`, valor: R(dia * 30 / 1000 * 12), comp: [['Sua casa', pp], [`Média de ${d.municipio.nome}`, cid?.valor || 0], ['Média das 8 cidades', cid?.media8 || 0]], unid: 'L/pessoa/dia',
            eco: `${num(eco * 30 / 1000, 1)} m³ por mês`, ecoR: R(eco * 30 / 1000 * 12), dicas: [['Banho de 5 minutos', `${num(v.p * Math.max(0, v.b - 5) * 9 * 30, 0)} L/mês`], ['Torneira fechada ao escovar', v.t ? `${num(v.p * 22 * 30, 0)} L/mês` : 'você já faz ✓'], ['Ensaboar a louça com a torneira fechada', `${num(v.l * 97 * 30, 0)} L/mês`], ['Vassoura e balde no lugar da mangueira', `${num(v.c * 280 * 0.85 * 30 / 7, 0)} L/mês`]] };
        } },
      energia: {
        form: `${ctl('p', 'Pessoas na casa', 1, 8, 3)}${ctl('b', 'Minutos de banho (cada pessoa)', 2, 30, 10, 1, ' min')}${ctl('a', 'Horas de ar-condicionado por dia', 0, 12, 0)}${ctl('i', 'Lâmpadas antigas (incandescentes/fluorescentes)', 0, 20, 4)}
          ${sw('w', 'Chuveiro sempre no modo inverno', true)}${sw('g', 'Geladeira com mais de 10 anos')}${sw('s', 'Deixo aparelhos em espera (stand-by)', true)}`,
        conta(v) {
          const ch = v.p * v.b * 30 / 60 * (v.w ? 5.5 : 3.5); const ar = v.a * 30 * 0.9; const la = v.i * 0.04 * 5 * 30; const ge = v.g ? 60 : 30; const sb = v.s ? 12 : 2; const outros = 60;
          const tot = ch + ar + la + ge + sb + outros;
          const eco = (v.w ? ch * (2 / 5.5) : 0) + v.p * Math.max(0, v.b - 6) * 30 / 60 * 3.5 * (v.w ? 1 : 0.95) + la * 0.8 + (v.g ? 25 : 0) + (v.s ? 10 : 0) + (v.a ? ar * 0.15 : 0);
          return { grande: `${num(tot, 0)} kWh`, sub: `por mês · ${num(tot / v.p, 0)} kWh por pessoa`, valor: R(tot * 0.85), comp: [['Chuveiro', ch], ['Ar-condicionado', ar], ['Geladeira', ge], ['Lâmpadas', la], ['Stand-by', sb], ['Outros', outros]], unid: 'kWh/mês',
            eco: `${num(Math.min(eco, tot * 0.6), 0)} kWh por mês`, ecoR: R(Math.min(eco, tot * 0.6) * 0.85), dicas: [['Chuveiro no modo verão', v.w ? `${num(ch * (2 / 5.5), 0)} kWh/mês` : 'você já faz ✓'], ['Banho de até 6 minutos', `${num(v.p * Math.max(0, v.b - 6) * 30 / 60 * 3.5, 0)} kWh/mês`], ['Trocar lâmpadas por LED', `${num(la * 0.8, 0)} kWh/mês`], ['Tirar aparelhos da tomada', v.s ? '10 kWh/mês' : 'você já faz ✓'], ['Ar-condicionado em 23 °C', v.a ? `${num(ar * 0.15, 0)} kWh/mês` : '—']] };
        } },
      lixo: {
        form: `${ctl('p', 'Pessoas na casa', 1, 8, 3)}${sw('r', 'Separamos os recicláveis (seco)')}${sw('c', 'Fazemos compostagem dos restos de comida')}${sw('d', 'Evitamos descartáveis (sacolas, copos)')}`,
        conta(v) {
          const pc = ind('RES-01')?.valor || 0.9; const tot = pc * v.p * 30; const rec = v.r ? tot * 0.3 : 0; const comp = v.c ? tot * 0.45 : 0; const desc = v.d ? tot * 0.05 : 0;
          const aterro = Math.max(0, tot - rec - comp - desc);
          return { grande: `${num(aterro, 0)} kg`, sub: `por mês vão para o aterro (de ${num(tot, 0)} kg gerados)`, valor: null, comp: [['Aterro', aterro], ['Reciclado', rec], ['Compostado', comp]], unid: 'kg/mês',
            eco: `${num(tot * 0.8 - rec - comp - desc, 0)} kg a menos no aterro por mês`, ecoR: null, dicas: [['Separar os recicláveis', v.r ? 'você já faz ✓' : `${num(tot * 0.3, 0)} kg/mês`], ['Compostar restos de comida', v.c ? 'você já faz ✓' : `${num(tot * 0.45, 0)} kg/mês`], ['Evitar descartáveis', v.d ? 'você já faz ✓' : `${num(tot * 0.05, 0)} kg/mês`]] };
        } },
      transporte: {
        form: `${ctl('k', 'Km de carro por dia', 0, 80, 20, 1, ' km')}${ctl('d', 'Dias por semana', 1, 7, 5)}${ctl('o', 'Quantos desses km dá para trocar por ônibus, bike ou a pé', 0, 80, 10, 1, ' km')}`,
        conta(v) {
          const km = v.k * v.d * 4.3; const co2 = km * 0.12; const comb = (km / 11) * 6.2; const tr = Math.min(v.o, v.k) * v.d * 4.3;
          return { grande: `${num(co2, 0)} kg de CO₂`, sub: `por mês · ${num(km, 0)} km de carro`, valor: R(comb), comp: [['Seu carro', co2], ['Mesma distância de ônibus', km * 0.04], ['Média por morador da cidade', ind('MOB-02')?.valor || 0]], unid: 'kg CO₂/mês',
            eco: `${num(tr * 0.08, 0)} kg de CO₂ a menos por mês`, ecoR: R((tr / 11) * 6.2 - tr * 0.2), dicas: [['Trocar parte do trajeto', `${num(tr, 0)} km/mês fora do carro`], ['Carona com mais 2 pessoas', 'divide o gasto por 3'], ['Pneus calibrados', 'até 3% menos combustível']] };
        } },
    };
    const desenhar = () => {
      const c = CALC[aba];
      $('#calc').innerHTML = `<div class="calc t-${AREAS[aba].cor}"><div class="cartao calc-form">${Cenas.cena(aba, { classe: 'mini' })}${c.form}</div><div class="cartao calc-res" id="res"></div></div>
        <div class="cartao dicas-e revelar" style="margin-top:20px"><span class="rotulo">Mais dicas</span><div id="dicas"></div></div>`;
      const atualizar = () => {
        const v = {}; $$('#calc input').forEach((i) => { v[i.id] = i.type === 'checkbox' ? i.checked : Number(i.value); if (i.type === 'range') $(`#v-${i.id}`).textContent = i.value + (i.dataset.suf || ''); });
        const r = c.conta(v); const mx = Math.max(...r.comp.map((x) => x[1])) || 1;
        $('#res').innerHTML = `<span class="rotulo">Sua casa</span><div class="calc-grande">${r.grande}</div><p class="calc-sub">${r.sub}</p>${r.valor ? `<div class="calc-valor">≈ ${r.valor} <small>por mês</small></div>` : ''}
          <div class="calc-comp">${r.comp.map(([t, val], i) => `<div><span>${esc(t)}</span><span class="t"><i style="width:${(val / mx) * 100}%;background:${['#1D5FA8', '#4FB3E3', '#2F8F3F', '#E8892B', '#8193AB', '#163E6E'][i]}"></i></span><b>${num(val, val < 10 ? 1 : 0)}</b></div>`).join('')}<small>${esc(r.unid)}</small></div>
          <div class="calc-eco"><span>Dá para economizar</span><b>${r.eco}</b>${r.ecoR ? `<em>≈ ${r.ecoR} por mês</em>` : ''}</div>
          <div class="calc-dicas">${r.dicas.map(([t, g]) => `<div><span>${esc(t)}</span><b>${esc(g)}</b></div>`).join('')}</div>`;
      };
      $$('#calc input').forEach((i) => (i.oninput = atualizar)); atualizar();
      API.get(`/dicas/${aba}`).then((r) => { const el = $('#dicas'); if (el) el.innerHTML = `<div class="dicas-lista">${r.itens.map(([t, x]) => `<div><b>${esc(t)}</b><p>${esc(x)}</p></div>`).join('')}</div><p class="calc-conta">${UI.md(r.conta)}</p>`; }).catch(() => {});
      revelar($('#calc'));
    };
    $$('#abasE button').forEach((b) => (b.onclick = () => { aba = b.dataset.a; $$('#abasE button').forEach((x) => x.classList.toggle('ativo', x === b)); history.replaceState(null, '', `#/app/economize/${aba}`); desenhar(); }));
    desenhar();
  }

  // ============================================================== DESAFIOS VERDES (gamificação; guardado só neste navegador)
  const DESAFIOS = [
    ['agua', '', 'Banho de 5 minutos por 7 dias', 'Economiza ~90 litros por banho', 600], ['agua', '', 'Torneira fechada ao escovar os dentes', '~12 litros por escovação', 300],
    ['agua', '', 'Fazer o teste do vazamento no relógio d\'água', 'Uma descarga vazando perde até 140 L/dia', 200],
    ['energia', '', 'Trocar 3 lâmpadas antigas por LED', '~85% menos energia em cada uma', 400], ['energia', '', 'Tirar da tomada o que fica em espera', 'Até 12% da conta de luz', 250],
    ['energia', '', 'Chuveiro no modo verão nos dias quentes', '~30% menos no chuveiro', 350],
    ['lixo', '', 'Separar o lixo seco do úmido por 1 semana', 'Ajuda as cooperativas e o aterro', 400], ['lixo', '', 'Ir ao mercado só com sacola retornável', 'Menos plástico no lixo', 200],
    ['lixo', '', 'Começar uma composteira', 'Metade do lixo de casa é orgânico', 500],
    ['transporte', '', 'Ir de ônibus ou metrô 3 vezes na semana', '~1/3 do CO₂ do carro', 450], ['transporte', '', 'Fazer trajetos de até 3 km a pé ou de bike', 'Zero emissão', 300],
    ['transporte', '', 'Oferecer ou pegar carona', 'Divide combustível e poluição', 250],
  ];
  const lerFeitos = () => { try { return JSON.parse(localStorage.getItem('eco.desafios') || '[]'); } catch { return []; } };
  const gravarFeitos = (v) => { try { localStorage.setItem('eco.desafios', JSON.stringify(v)); } catch { /* sem armazenamento */ } };
  async function desafios(app) {
    casca(app, 'desafios', esqueleto());
    let feitos = lerFeitos();
    const desenhar = () => {
      const pts = DESAFIOS.reduce((a, d, k) => a + (feitos.includes(k) ? d[4] : 0), 0); const tot = DESAFIOS.reduce((a, d) => a + d[4], 0);
      const nivel = pts >= tot * 0.75 ? ['', 'Guardião do planeta'] : pts >= tot * 0.4 ? ['', 'Cidadão verde'] : pts > 0 ? ['', 'Começando bem'] : ['', 'Semente'];
      $('#conteudo').innerHTML = `${topo('Desafios verdes', 'Pequenas mudanças em casa que, somadas, mudam os números da cidade. Marque o que você já fez e suba de nível!')}
        <section class="placar-d revelar"><div class="pd-nivel"><span>${nivel[0]}</span><div><small>seu nível</small><b>${nivel[1]}</b></div></div>
          <div class="pd-barra"><div><b data-contar="${pts}">0</b> de ${tot} pontos</div><span class="trilho-d"><i style="width:${(pts / tot) * 100}%"></i></span><small>${feitos.length} de ${DESAFIOS.length} desafios concluídos</small></div></section>
        ${Object.keys(AREAS).map((a) => `<h2 class="titulo-sec revelar">${AREAS[a].emoji} ${AREAS[a].titulo}</h2><div class="grade g-3">${DESAFIOS.map((d, k) => [d, k]).filter(([d]) => d[0] === a).map(([d, k]) => `<button class="desafio t-${AREAS[a].cor} ${feitos.includes(k) ? 'feito' : ''} revelar" data-k="${k}">
          ${icoArea(AREAS[a].servico)}<b>${esc(d[2])}</b><small>${esc(d[3])}</small><span class="ds-p">+${d[4]} pts</span><span class="ds-check">${feitos.includes(k) ? '✓ feito' : 'marcar como feito'}</span></button>`).join('')}</div>`).join('')}
        <p class="nota-rodape">Seu progresso fica guardado só neste navegador.</p>`;
      revelar($('#conteudo'));
      $$('[data-k]').forEach((b) => (b.onclick = () => { const k = Number(b.dataset.k); const novo = !feitos.includes(k); feitos = novo ? [...feitos, k] : feitos.filter((x) => x !== k); gravarFeitos(feitos); if (novo) { toast(`+${DESAFIOS[k][4]} pontos`, 'ok'); } setTimeout(desenhar, novo ? 500 : 0); }));
    };
    desenhar();
  }
  function confete(el) {
    if (UI.reduzido) return;
    const r = el.getBoundingClientRect();
    for (let i = 0; i < 28; i++) {
      const c = document.createElement('i'); c.className = 'confete';
      c.style.cssText = `left:${r.left + r.width / 2}px;top:${r.top + r.height / 2}px;background:${['#2F8F3F', '#1D5FA8', '#E8892B', '#4FB3E3', '#F2C94C'][i % 5]};--dx:${(Math.random() - 0.5) * 320}px;--dy:${-80 - Math.random() * 220}px;--r:${Math.random() * 720}deg`;
      document.body.append(c); setTimeout(() => c.remove(), 1300);
    }
  }

  // contas de cada número, em linguagem simples: [peças da conta], resultado e um exemplo com números redondos
  const CONTA = {
    'AGU-01': { pecas: [['Água consumida no mês', 'em litros (m³ × 1.000)'], ['÷', ''], ['Moradores', 'IBGE'], ['÷', ''], ['Dias do mês', '30 ou 31']], res: 'litros por pessoa por dia',
      ex: 'Cidade com 1 milhão de moradores que consumiu 6 bilhões de litros em 30 dias: 6.000.000.000 ÷ 1.000.000 ÷ 30 = <b>200 litros</b> por pessoa por dia.' },
    'AGU-02': { pecas: [['Água tratada − água que chegou às casas', 'o que se perdeu'], ['÷', ''], ['Água tratada', ''], ['× 100', '']], res: '% de água perdida',
      ex: 'A empresa tratou 100 litros e só 75 chegaram aos hidrômetros: (100 − 75) ÷ 100 × 100 = <b>25%</b> perdidos em vazamentos e ligações irregulares.' },
    'ENE-01': { pecas: [['Energia elétrica consumida no mês', 'em kWh (MWh × 1.000)'], ['÷', ''], ['Moradores', 'IBGE']], res: 'kWh por pessoa por mês',
      ex: 'Cidade com 1 milhão de moradores que gastou 240 milhões de kWh no mês: 240.000.000 ÷ 1.000.000 = <b>240 kWh</b> por pessoa. Inclui casas, comércio e indústria.' },
    'ENE-02': { pecas: [['Potência dos painéis solares instalados', 'em watts (kW × 1.000)'], ['÷', ''], ['Moradores', 'IBGE']], res: 'watts de painel solar por pessoa',
      ex: 'Cidade com 1 milhão de moradores e 120 mil kW de painéis em telhados: 120.000.000 ÷ 1.000.000 = <b>120 watts</b> por pessoa (mais ou menos um quarto de painel por morador).' },
    'RES-01': { pecas: [['Lixo coletado no mês', 'em kg (t × 1.000)'], ['÷', ''], ['Moradores', 'IBGE'], ['÷', ''], ['Dias do mês', '30 ou 31']], res: 'kg de lixo por pessoa por dia',
      ex: 'Cidade com 1 milhão de moradores que coletou 30 mil toneladas em 30 dias: 30.000.000 ÷ 1.000.000 ÷ 30 = <b>1 kg</b> por pessoa por dia.' },
    'RES-02': { pecas: [['Lixo recuperado pela coleta seletiva', 'em toneladas'], ['÷', ''], ['Lixo coletado', 'em toneladas'], ['× 100', '']], res: '% do lixo que foi reciclado',
      ex: 'De 1.000 toneladas coletadas, 60 foram para a reciclagem: 60 ÷ 1.000 × 100 = <b>6%</b>.' },
    'MOB-01': { pecas: [['Passageiros de ônibus no mês', 'viagens'], ['÷', ''], ['Moradores', 'IBGE']], res: 'viagens de ônibus por pessoa por mês',
      ex: 'Cidade com 1 milhão de moradores e 9 milhões de viagens no mês: 9.000.000 ÷ 1.000.000 = <b>9 viagens</b> por pessoa (quem não usa ônibus também entra na divisão).' },
    'MOB-02': { pecas: [['CO₂ do transporte no mês', 'em kg (t × 1.000)'], ['÷', ''], ['Moradores', 'IBGE']], res: 'kg de CO₂ por pessoa por mês',
      ex: 'Cidade com 1 milhão de moradores cujo transporte (carros, ônibus, caminhões, aviões) emitiu 100 mil toneladas no mês: 100.000.000 ÷ 1.000.000 = <b>100 kg</b> por pessoa.' },
  };
  const contaHtml = (i) => { const c = CONTA[i.codigo]; if (!c) return `<code>${esc(i.formula)}</code>`;
    return `<div class="conta">${c.pecas.map(([t, sub]) => (['÷', '× 100'].includes(t) ? `<span class="op">${t}</span>` : `<span class="pc"><b>${esc(t)}</b>${sub ? `<small>${esc(sub)}</small>` : ''}</span>`)).join('')}<span class="op">=</span><span class="pc res"><b>${esc(c.res)}</b></span></div>
      <p class="conta-ex"><span>Exemplo</span>${c.ex}</p>`; };

  // ============================================================== ENTENDA OS DADOS (glossário visual)
  async function aprenda(app) {
    casca(app, 'aprenda', esqueleto());
    const ex = await API.pegar('/explorar');
    $('#conteudo').innerHTML = `${topo('Entenda os dados', `O que cada número mede, como é calculado${verMeta() ? ', qual é a meta' : ''} e por que ele importa. Sem complicação.`)}
      <div class="grade g-3">
        <div class="cartao aprenda-tipo borda-verde revelar"><span class="chip verde"><i></i>Oficial do mês</span><p>Número publicado pela fonte oficial (ANEEL, SPTrans…) para aquele mês.</p></div>
        <div class="cartao aprenda-tipo borda-azul revelar" style="--atraso:.06s"><span class="chip azul"><i></i>Oficial do ano</span><p>A fonte (SNIS, SINISA, SEEG…) publica o total do ano. O EcoCity divide esse total oficial pelos meses.</p></div>
        <div class="cartao aprenda-tipo borda-laranja revelar" style="--atraso:.12s"><span class="chip laranja"><i></i>Estimado</span><p>Não existe número oficial da cidade. O EcoCity estima a partir de uma série oficial maior (ex.: energia do Estado de SP) e troca quando a cidade enviar o dado.</p></div></div>
      ${Object.keys(AREAS).map((a) => `<h2 class="titulo-sec revelar">${AREAS[a].emoji} ${AREAS[a].titulo}</h2><div class="grade g-2">${ex.indicadores.filter((i) => i.servico === AREAS[a].servico).map((i) => `<article class="cartao aprenda-c t-${AREAS[a].cor} revelar">
        <header><span class="dt-ico">${icoArea(i.servico)}</span><div><h3>${esc(i.simples)}</h3><small>${esc(i.nome)} · ${esc(i.unidade)}</small></div><span class="ods">${esc(i.ods || '')}</span></header>
        <p>${esc(i.descricao || '')}</p>
        <div class="ap-l"><b>Como é calculado</b>${contaHtml(i)}</div>
        ${verMeta() ? `<div class="ap-l"><b>Meta ${UI.info('meta')}</b><span>${i.sentido === 'MAIOR_MELHOR' ? 'pelo menos' : 'no máximo'} <b>${num(i.meta, casasDe(i.meta))} ${esc(i.unidade)}</b> · ${i.sentido === 'MAIOR_MELHOR' ? 'quanto maior, melhor' : 'quanto menor, melhor'}</span></div>` : `<div class="ap-l"><b>Como ler</b><span>${i.sentido === 'MAIOR_MELHOR' ? 'quanto <b>maior</b>, melhor' : 'quanto <b>menor</b>, melhor'}</span></div>`}
        <p class="ih-imp">${esc(i.importa || '')}</p>
        <a class="link-btn" href="#/app/${a === 'agua' || a === 'energia' || a === 'lixo' || a === 'transporte' ? (API.usuario.perfil === 'CIDADAO' ? a : 'comparar') : 'comparar'}">Ver os números →</a></article>`).join('')}</div>`).join('')}
      ${`<section class="nota-complemento revelar" style="margin-top:28px"><div><span class="rotulo">Como comparamos</span><h3>Sua cidade × as outras 7 cidades</h3><p>Cada número da sua cidade é comparado com a <b>média das 8 cidades</b> no mesmo mês: <b>melhor que a média</b>, <b>na média</b> (diferença menor que 5%) ou <b>pior que a média</b>. E também com o mesmo mês do ano passado.</p></div><div class="ods-g"><small>ODS 6 · 7 · 11 · 12 · 13</small></div></section>`}`;
    revelar($('#conteudo'));
  }

  const verCidade = (id) => { cidadeSel = id; };
  return { icoArea, painel, area, comparar, mapa, mes, alertas, economize, desafios, aprenda, casca, topo, esqueleto, sair, pode, pilula, gavetaFonte, botaoFonte, fonteLinha, INICIO, casasDe, verCidade, AREAS, PALETA, contaHtml };
})();
