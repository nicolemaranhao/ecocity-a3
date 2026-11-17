/* EcoCity — páginas públicas: início, entrar (login com e-mail e senha) e cadastro por perfil */
const Publico = (() => {
  const { $, $$, esc, num, ico, logo, marca, toast, revelar } = UI;
  let resumo = null;
  const pegarResumo = async () => (resumo ||= await API.get('/public/resumo', { silencioso: true }).catch(() => null));

  // ============================================================== PÁGINA INICIAL
  async function inicio(app) {
    const r = await pegarResumo();
    const mun = r?.municipios || [];
    const popTotal = mun.reduce((a, m) => a + Number(m.populacao || 0), 0);
    const maxPop = Math.max(...mun.map((m) => Number(m.populacao || 0)), 1);
    const PAL = ['#3E9A4E', '#2E8FCB', '#D9822B', '#2B4C8C'];
    const og = Object.fromEntries((r?.origem || []).map((o) => [o.origem, o.n])); const totO = (og.REAL || 0) + (og.DERIVADO || 0) + (og.ESTIMADO || 0) || 1;
    const media = (c) => r?.medias?.find((x) => x.codigo === c);
    const AREAS = [['agua', 'Água', 'Quanta água cada pessoa usa e quanta se perde nos canos.', ['AGU-01', 'AGU-02']], ['energia', 'Energia', 'Quanta energia a cidade gasta e quanto já vem do sol.', ['ENE-01', 'ENE-02']],
      ['lixo', 'Lixo e reciclagem', 'Quanto lixo cada pessoa gera e quanto volta para a reciclagem.', ['RES-01', 'RES-02']], ['transporte', 'Transporte', 'Quanto as pessoas usam o ônibus e quanta poluição o transporte solta.', ['MOB-01', 'MOB-02']]];
    app.innerHTML = `<div class="pub">
    <header class="pub-topo" id="topo"><div class="wrap"><a class="marca marca-app" href="#/">${logo({ anim: true })}<span><b>Eco</b><span>City</span></span></a>
      <nav><a href="#dados">Os dados</a><a href="#como">Como funciona</a><a href="#transparencia">Oficial ou estimado</a><a href="#perfis">Para quem</a></nav>
      <div class="acoes">${API.logado ? `<a class="btn fantasma sm" href="#/app">Meu painel</a><button class="btn sm" id="pubSair">Sair da conta</button>` : '<a class="btn fantasma sm" href="#/entrar">Entrar</a><a class="btn sm" href="#/cadastro">Criar conta</a>'}</div></div></header>

    <section class="pub-hero"><div class="pub-linhas" aria-hidden="true">${Cenas.cena('cidade', { classe: 'fundo' })}</div>
      <div class="wrap">
        <div class="ph-txt">
          <span class="chapeu revelar"><i style="background:#3E9A4E"></i>8 cidades de São Paulo · dados oficiais mês a mês, 2023–2026</span>
          <h1 class="revelar" style="--atraso:.1s">Os números que cuidam da sua <span class="gira-palavra" id="giraPalavra"><span class="ativa">cidade.</span><span>água.</span><span>energia.</span><span>reciclagem.</span><span>mobilidade.</span></span></h1>
          <p class="lead revelar" style="--atraso:.2s">O EcoCity junta, mês a mês, os dados de água, energia, lixo e transporte das fontes oficiais e mostra tudo em linguagem simples. Cada número diz de onde veio e se é <b>oficial</b> ou <b>estimado</b>.</p>
          <div class="ctas revelar" style="--atraso:.3s"><a class="btn" href="#/cadastro">Criar minha conta grátis</a><a class="seta-link" href="#dados">Ver os dados</a></div>
          <dl class="ph-fatos revelar" style="--atraso:.4s"><div><dt>Cidades</dt><dd class="num" data-contar="${r?.cidades || 8}">0</dd></div><div><dt>Moradores</dt><dd class="num">${(popTotal / 1e6).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mi</dd></div>
            <div><dt>Meses de dados</dt><dd class="num" data-contar="${r?.meses || 24}">0</dd></div><div><dt>Valores no banco</dt><dd class="num">${Number(r?.medicoes || 1536).toLocaleString('pt-BR')}</dd></div></dl>
        </div>
        <div class="ph-palco revelar" style="--atraso:.25s">
          <div class="ph-foto">${Cenas.cena('cidade')}</div>
          <div class="ph-3d">${UI.cidade3d(mun.map((m, k) => ({ nome: m.nome, valor: Math.max(14, Math.sqrt(Number(m.populacao) / maxPop) * 100), cor: PAL[k % 4], txt: `${Number(m.populacao).toLocaleString('pt-BR')} moradores (IBGE)` })), { legenda: ['cada prédio é uma cidade', 'altura = moradores (IBGE)'] })}</div>
          <div class="ph-chip c1"><b>${esc(mun.find((m) => Number(m.populacao) === maxPop)?.nome || 'São Paulo')}</b><small>a maior das 8 cidades</small></div>
          <div class="ph-chip c2"><i class="o-REAL"></i><small>dado oficial</small><i class="o-ESTIMADO"></i><small>estimado</small></div>
        </div>
      </div></section>

    <div class="pub-letreiro" aria-label="Fontes oficiais"><div class="faixa">${'ANEEL,EPE,SNIS,SINISA,SPTrans,SEEG,IBGE,SP Regula,Dados abertos'.split(',').concat('ANEEL,EPE,SNIS,SINISA,SPTrans,SEEG,IBGE,SP Regula,Dados abertos'.split(',')).map((f) => `<span>${f}</span>`).join('')}</div></div>

    <section class="pub-secao" id="dados"><div class="wrap">
      <div class="pub-cab revelar"><span class="chapeu">Os dados</span><h2>Quatro áreas, oito números, em palavras simples</h2><p>Média das 8 cidades em ${esc(UI.mesTxt(r?.mes))}. Entrando, você vê os números da sua cidade e compara com as outras.</p></div>
      <div class="pub-areas">${AREAS.map(([k, t, d, cods], i) => `<article class="pub-area revelar" style="--atraso:${i * 0.08}s;--c:${UI.SERV[{ agua: 'Água', energia: 'Energia', lixo: 'Resíduos', transporte: 'Mobilidade' }[k]].cor}">
        <div class="pa-foto">${Cenas.cena(k)}</div>
        <div class="pa-txt"><span class="d-area"><i></i>${t}</span><p class="pa-desc">${d}</p>
          ${cods.map((c) => { const m_ = media(c); return m_ ? `<div class="pa-num"><b class="num">${num(m_.media, m_.media < 20 ? 2 : 0)}</b><span>${esc(m_.unidade)}</span><small>${esc(m_.simples || '')}</small></div>` : ''; }).join('')}</div></article>`).join('')}</div>
    </div></section>

    <section class="pub-secao escura" id="como"><div class="wrap">
      <div class="pub-cab revelar"><span class="chapeu">Como funciona</span><h2>Do dado oficial até você, sem ninguém digitar nada</h2>
        <p>Um robô busca os números nas fontes oficiais quando elas publicam. O banco confere, calcula os indicadores e a inteligência artificial procura o que piorou.</p></div>
      <div class="fluxo" id="fluxo">
        <svg class="trilho" viewBox="0 0 100 6" preserveAspectRatio="none"><path d="M10 3 H90" stroke="rgba(255,255,255,.12)" stroke-width="2" vector-effect="non-scaling-stroke"/>
          <path id="trilhoVivo" d="M10 3 H90" pathLength="1" stroke="url(#gtr)" stroke-width="2.5" stroke-linecap="round" vector-effect="non-scaling-stroke" fill="none"/>
          <defs><linearGradient id="gtr"><stop offset="0" stop-color="#3E9A4E"/><stop offset=".35" stop-color="#2E8FCB"/><stop offset=".7" stop-color="#D9822B"/><stop offset="1" stop-color="#7FB3E8"/></linearGradient></defs></svg>
        ${[['nuvem', 'Fontes oficiais', 'ANEEL, IBGE, EPE, SNIS, SPTrans e SEEG.', 'APIs e planilhas'], ['robo', 'Coleta automática', 'O robô baixa, confere e grava. O que não tem fonte oficial é estimado — e marcado.', 'quando a fonte publica'],
           ['banco', 'Banco de dados', 'MySQL calcula os 8 números de cada cidade, mês a mês.', '36 tabelas'], ['cerebro', 'IA de alertas', 'Avisa quando algo piora ou foge do normal.', 'todo mês'], ['pessoa', 'Você', 'Cidadãos acompanham, analistas explicam, gestores decidem.', 'no site']]
          .map(([i, t, d, q], k) => `<div class="etapa revelar" style="--atraso:${k * 0.12}s"><div class="icone">${ico(i, '#fff', 1.6)}</div><div><h3>${t}</h3><p>${d}</p><span class="quando">${q}</span></div></div>`).join('')}
      </div></div></section>

    <section class="pub-secao" id="transparencia"><div class="wrap pub-transp">
      <div class="revelar"><span class="chapeu">Transparência</span><h2>Oficial ou estimado: sempre escrito</h2>
        <p>O EcoCity mostra <b>jan/2023 a set/2026</b> e usa o <b>último dado oficial</b> de cada órgão: energia solar (ANEEL) e ônibus de São Paulo (SPTrans) até set/2026, emissões (SEEG) até 2025, água (SNIS) e lixo (SINISA) até 2024 — o governo publica esses com 1 a 2 anos de atraso. Depois do último dado oficial, o número é estimado a partir dele — e isso fica escrito em cada número.</p>
        <ul class="pt-lista"><li><span class="selo o-REAL">Oficial do mês</span> publicado pela fonte para aquele mês</li><li><span class="selo o-DERIVADO">Oficial do ano</span> total oficial do ano dividido pelos meses</li><li><span class="selo o-ESTIMADO">Estimado</span> não há número oficial da cidade</li></ul></div>
      <div class="cartao revelar pt-barra" style="--atraso:.1s"><span class="rotulo">Todos os ${Number(totO).toLocaleString('pt-BR')} valores mensais do banco hoje</span>
        <div class="or-barra grande">${['REAL', 'DERIVADO', 'ESTIMADO'].map((o) => (og[o] ? `<i class="o-${o}" style="flex:${og[o]}">${Math.round((og[o] / totO) * 100)}%</i>` : '')).join('')}</div>
        <div class="pt-leg"><span><i class="o-REAL"></i>oficial do mês</span><span><i class="o-DERIVADO"></i>oficial do ano</span><span><i class="o-ESTIMADO"></i>estimado</span></div></div>
    </div></section>

    <section class="pub-secao clara" id="perfis"><div class="wrap">
      <div class="pub-cab revelar"><span class="chapeu">Para quem</span><h2>Cada pessoa vê o que precisa</h2><p>Quem só acompanha entra na hora. Quem publica análises ou decide tem o vínculo conferido pelo administrador.</p></div>
      <div class="pub-perfis">${[['pessoa', 'Cidadão', 'Vê os números da sua cidade em linguagem simples, compara com as outras cidades, recebe alertas e dicas para economizar.', 'Cadastro simples · entra na hora'],
        ['lab', 'Analista', 'Investiga os dados, monta relatórios com o assistente e publica análises revisadas por outro especialista.', 'Comprova o vínculo · aprovado pelo admin'],
        ['bussola', 'Gestor público', 'Define metas, simula cenários, registra ações da prefeitura e mede o resultado.', 'Portaria de nomeação · aprovado pelo admin'],
        ['escudo', 'Administrador', 'Aprova cadastros e acompanha a coleta automática e a segurança.', 'Criado pelo DBA · chave individual']]
        .map(([i, t, d, c], k) => `<article class="pub-perfil revelar" style="--atraso:${k * 0.08}s"><span class="pp-ico">${ico(i, 'currentColor', 1.6)}</span><h3>${t}</h3><p>${d}</p><small>${c}</small></article>`).join('')}</div>
    </div></section>

    <section class="pub-cta"><div class="wrap revelar"><div class="pc-logo">${logo({ anim: true, classe: 'respira' })}</div><h2>Sua cidade, em números que dá para entender.</h2>
      <p>Grátis para cidadãos. E o Eco, nosso assistente, responde suas dúvidas.</p><div class="ctas"><a class="btn" href="#/cadastro">Criar minha conta</a><a class="btn fantasma" href="#/entrar">Já tenho conta</a></div></div></section>
    <footer class="pub-rodape"><div class="wrap"><a class="marca" href="#/">${logo()}<span><b>Eco</b><span>City</span></span></a><span>A3 Banco de Dados · Anhembi Morumbi · Gabriela Sant’Ana Merces Assis e Nicole Maranhão Assis</span><span>Fotos: Unsplash (licença livre)</span></div></footer>
    </div>`;

    revelar(app); UI.ativar3d(app);
    const topo = $('#topo'); const fluxo = $('#fluxo'); const trilho = $('#trilhoVivo'); const palco = $('.ph-palco');
    const aoRolar = () => {
      topo?.classList.toggle('rolado', scrollY > 30);
      if (fluxo && trilho) { const b = fluxo.getBoundingClientRect(); const p = Math.min(1, Math.max(0, (innerHeight * 0.85 - b.top) / (b.height + innerHeight * 0.3))); trilho.style.strokeDashoffset = 1 - p; trilho.style.strokeDasharray = 1; }
      if (palco && !UI.reduzido) palco.style.setProperty('--py', `${Math.min(60, scrollY * 0.12)}px`);   // profundidade ao rolar
    };
    addEventListener('scroll', aoRolar, { passive: true }); aoRolar();
    if ($('#pubSair')) $('#pubSair').onclick = () => { API.sair(); API.limpar(); Chat.desmontar(); toast('Você saiu da conta. Até logo!'); inicio(app); };
    const gp = $$('#giraPalavra span'); let k = 0;
    const t = setInterval(() => {
      if (!document.body.contains(gp[0])) return clearInterval(t);
      gp[k].className = 'saiu'; k = (k + 1) % gp.length; gp[k].className = 'ativa';
      setTimeout(() => gp.forEach((s, i) => i !== k && (s.className = '')), 700);
    }, 2400);
    $$('a[href^="#"]:not([href^="#/"])', app).forEach((a) => a.addEventListener('click', (e) => { e.preventDefault(); $(a.getAttribute('href'))?.scrollIntoView({ behavior: 'smooth' }); }));
    return () => removeEventListener('scroll', aoRolar);
  }

  // ============================================================== moldura de acesso (login/cadastro)
  const DICAS = [
    'O EcoCity mostra 8 números de água, energia, lixo e transporte de 8 cidades de SP.',
    'Os números vêm das fontes oficiais (ANEEL, SNIS, SINISA, SEEG, SPTrans, IBGE) e entram no banco por um robô de coleta.',
    'Quando a cidade não tem número oficial, o valor é estimado — e marcado como estimado.',
    'A IA avisa quando um número piora em relação ao ano passado ou foge do normal.',
    'Análises de analistas só são publicadas depois da revisão de outro especialista.',
  ];
  function moldura(app, titulo, texto, conteudo, largo = false) {
    app.innerHTML = `<div class="acesso">
      <aside class="lado-marca"><div class="bolhas"><i></i><i></i><i></i></div>
        <div style="position:relative;z-index:2" class="escuro">${marca()}</div>
        <div class="conteudo"><div style="width:120px">${logo({ anim: true })}</div><h2>${titulo}</h2><p>${texto}</p>
          <div class="dica"><small>Você sabia?</small><p id="dica">${DICAS[0]}</p></div></div></aside>
      <section class="lado-form"><a class="btn fantasma sm voltar" href="#/">← Início</a><div class="caixa-form ${largo ? 'larga' : ''}" id="caixa">${conteudo}</div></section></div>`;
    let i = 0; const d = $('#dica');
    const t = setInterval(() => { if (!document.body.contains(d)) return clearInterval(t); d.style.opacity = 0; setTimeout(() => { i = (i + 1) % DICAS.length; d.textContent = DICAS[i]; d.style.opacity = 1; }, 400); }, 5000);
  }
  const erroEm = (el, msg) => { el.innerHTML = msg ? `<div class="aviso">⚠️ ${esc(msg)}</div>` : ''; if (msg) { el.parentElement.classList.remove('treme'); void el.offsetWidth; el.parentElement.classList.add('treme'); } };
  const carregandoBtn = (b, on, txt) => { b.disabled = on; b.innerHTML = on ? '<span class="gira"></span> Aguarde...' : txt; };

  // ============================================================== ENTRAR
  function entrar(app) {
    const atual = API.usuario;
    moldura(app, 'Bem-vindo de volta', 'Só entra quem tem cadastro. Use o e-mail e a senha que você cadastrou.', `
      <h1>Entrar</h1><p class="sub">Use o e-mail e a senha do seu cadastro.</p>
      ${atual ? `<div class="conectado"><p>Você está conectado como <b>${esc(atual.nome)}</b>. Para usar outra conta, é só entrar abaixo: a conta atual é encerrada.</p>
        <div><a class="btn fantasma sm" href="#/app">Continuar como ${esc(atual.nome.split(' ')[0])}</a> <button class="btn fantasma sm" id="sairAtual">Sair desta conta</button></div></div>` : ''}
      <form id="f1" novalidate><div id="erro"></div>
        <div class="campo"><label for="email">E-mail</label><input id="email" type="email" autocomplete="username" required></div>
        <div class="campo"><label for="senha">Senha</label><input id="senha" type="password" autocomplete="current-password" required></div>
        <div class="campo" id="campoChave" hidden><label for="chave">Chave de administrador</label><input id="chave" type="password" autocomplete="off"></div>
        <button class="btn" style="width:100%" id="b1">Entrar</button>
        <p style="text-align:center;margin-top:18px;color:var(--tinta-2)">Ainda não tem conta? <a href="#/cadastro">Cadastre-se</a></p></form>`);

    if ($('#sairAtual')) $('#sairAtual').onclick = () => { API.sair(); API.limpar(); Chat.desmontar(); toast('Você saiu da conta.'); entrar(app); };
    $('#f1').onsubmit = async (e) => {
      e.preventDefault(); const b = $('#b1'); carregandoBtn(b, true);
      try {
        const r = await API.post('/auth/login', { email: $('#email').value, senha: $('#senha').value, chave_admin: $('#chave').value || undefined });
        if (r.token) return concluir(r);
        if (r.etapa === 'CHAVE') { $('#campoChave').hidden = false; erroEm($('#erro'), ''); $('#chave').focus(); carregandoBtn(b, false, 'Entrar'); }
      } catch (err) { erroEm($('#erro'), err.message); carregandoBtn(b, false, 'Entrar'); }
    };
  }

  function concluir(r) {
    if (API.logado) { API.sair(); Chat.desmontar(); }    // trocou de conta: encerra a anterior
    API.entrar(r); API.limpar();
    toast(`Olá, ${r.usuario.nome.split(' ')[0]}!`, 'ok');
    location.hash = '#/app';
  }

  // ============================================================== CADASTRO
  async function cadastro(app, perfil) {
    const r = await pegarResumo();
    const cidades = r?.municipios || [];
    if (!perfil) {
      moldura(app, 'Crie sua conta', 'Escolha como você vai usar o EcoCity. O cadastro muda conforme o perfil, para manter os dados confiáveis.', `
        <h1>Quem é você?</h1><p class="sub">Cada perfil tem um cadastro diferente.</p>
        <div class="escolha-perfil">
          ${[['cidadao', 'pessoa', 'var(--verde)', 'var(--verde-bg)', 'Cidadão', 'Quero acompanhar a minha cidade.', ['Nome, e-mail e cidade', 'Senha de 8+ caracteres'], 'Entra na hora · 1 minuto'],
             ['analista', 'lab', 'var(--ceu)', 'var(--ceu-bg)', 'Analista', 'Trabalho com dados ambientais e quero publicar análises.', ['CPF e e-mail do órgão', 'Registro no conselho (CREA, CRQ…)', 'Declaração de vínculo'], 'Aprovado pelo admin'],
             ['gestor', 'bussola', 'var(--laranja)', 'var(--laranja-bg)', 'Gestor público', 'Sou servidor e defino metas e ações da cidade.', ['CPF e e-mail do órgão', 'Portaria de nomeação', 'Cidade em que atua'], 'Aprovado pelo admin']]
            .map(([id, e, c, bg, t, d, l, tempo]) => `<a class="opcao-perfil" href="#/cadastro/${id}" style="--c:${c};--bg:${bg};text-decoration:none;color:inherit">
              <div class="avatar">${ico(e, 'currentColor', 1.6)}</div><h3>${t}</h3><p>${d}</p><ul>${l.map((x) => `<li>${x}</li>`).join('')}</ul><span class="tempo">${tempo}</span></a>`).join('')}
        </div>
        <p class="admin-aviso">Administradores não se cadastram pelo site: são criados pelo DBA, com chave individual.</p>
        <p style="text-align:center;margin-top:12px;color:var(--tinta-2)">Já tem conta? <a href="#/entrar">Entrar</a></p>`, true);
      return;
    }
    if (perfil === 'cidadao') return cadastroCidadao(app, cidades);
    if (perfil === 'analista' || perfil === 'gestor') return cadastroProfissional(app, perfil, cidades);
    location.hash = '#/cadastro';
  }

  const opcoesCidades = (cidades, vazio = 'Escolha a cidade') => `<option value="">${vazio}</option>${cidades.map((c) => `<option value="${c.id_municipio}">${esc(c.nome)}</option>`).join('')}`;
  const REGRAS_SENHA = {
    simples: [['8+ caracteres', (s) => s.length >= 8], ['uma letra', (s) => /[A-Za-z]/.test(s)], ['um número', (s) => /\d/.test(s)]],
    forte: [['12+ caracteres', (s) => s.length >= 12], ['maiúscula', (s) => /[A-Z]/.test(s)], ['minúscula', (s) => /[a-z]/.test(s)], ['número', (s) => /\d/.test(s)], ['símbolo (!@#…)', (s) => /[^A-Za-z0-9]/.test(s)]],
  };
  function campoSenha(tipo) {
    return `<div class="campo"><label for="senha">Senha <small>${tipo === 'forte' ? 'senha forte (dados sensíveis)' : ''}</small></label><input id="senha" type="password" autocomplete="new-password">
      <div class="forca">${REGRAS_SENHA[tipo].map(() => '<i></i>').join('')}</div><ul class="regras">${REGRAS_SENHA[tipo].map(([t]) => `<li>${t}</li>`).join('')}</ul></div>
      <div class="campo"><label for="senha2">Repita a senha</label><input id="senha2" type="password" autocomplete="new-password"><span class="ajuda"></span></div>`;
  }
  function ligarSenha(tipo) {
    const inp = $('#senha'); const regras = REGRAS_SENHA[tipo];
    const cores = ['#D94848', '#E8892B', '#E8892B', '#4FB3E3', '#2F8F3F', '#2F8F3F'];
    inp.oninput = () => {
      const ok = regras.map(([, f]) => f(inp.value)); const n = ok.filter(Boolean).length;
      $$('.regras li').forEach((li, i) => li.classList.toggle('ok', ok[i]));
      $$('.forca i').forEach((i, k) => (i.style.background = k < n ? cores[Math.round((n / regras.length) * 5)] : ''));
    };
    return () => regras.every(([, f]) => f(inp.value));
  }
  function marcarErro(id, msg) { const c = $(`#${id}`)?.closest('.campo'); if (!c) return; c.classList.toggle('erro', !!msg); const a = $('.ajuda', c); if (a && msg) a.textContent = msg; }

  function cadastroCidadao(app, cidades) {
    moldura(app, 'Rapidinho: 1 minuto', 'Como cidadão você entra na hora e acompanha os números, os alertas e as dicas de economia da sua cidade.', `
      <a href="#/cadastro" class="link-btn">← Trocar perfil</a><h1 style="margin-top:10px">Cadastro de cidadão</h1><p class="sub">Só o essencial. Seus dados não aparecem para outras pessoas.</p>
      <form id="fc" novalidate><div id="erro"></div>
        <div class="campo"><label for="nome">Nome completo</label><input id="nome" autocomplete="name"><span class="ajuda"></span></div>
        <div class="campo"><label for="email">E-mail</label><input id="email" type="email" autocomplete="email"><span class="ajuda"></span></div>
        <div class="linha2"><div class="campo"><label for="tel">Telefone <small>opcional</small></label><input id="tel" inputmode="tel" placeholder="(11) 91234-5678"></div>
        <div class="campo"><label for="cidade">Sua cidade</label><select id="cidade">${opcoesCidades(cidades)}</select><span class="ajuda"></span></div></div>
        ${campoSenha('simples')}
        <label class="marcar"><input type="checkbox" id="aceite"> Li e aceito que meus dados sejam usados só para o meu acesso ao EcoCity (LGPD).</label>
        <button class="btn verde" style="width:100%" id="bc">Criar minha conta</button></form>`);
    const senhaOk = ligarSenha('simples');
    $('#fc').onsubmit = async (e) => {
      e.preventDefault();
      const v = { nome: $('#nome').value.trim(), email: $('#email').value.trim(), telefone: $('#tel').value.replace(/\D/g, '') || null, id_municipio: $('#cidade').value, senha: $('#senha').value };
      marcarErro('nome', v.nome.split(' ').length < 2 ? 'Escreva nome e sobrenome.' : '');
      marcarErro('email', !/^\S+@\S+\.\S+$/.test(v.email) ? 'E-mail inválido.' : '');
      marcarErro('cidade', !v.id_municipio ? 'Escolha a cidade.' : '');
      marcarErro('senha2', $('#senha2').value !== v.senha ? 'As senhas não são iguais.' : '');
      if ($$('.campo.erro').length) return erroEm($('#erro'), 'Confira os campos marcados.');
      if (!senhaOk()) return erroEm($('#erro'), 'A senha ainda não cumpre as regras.');
      if (!$('#aceite').checked) return erroEm($('#erro'), 'É preciso aceitar o uso dos dados.');
      const b = $('#bc'); carregandoBtn(b, true);
      try {
        await API.post('/auth/cadastro/cidadao', v);
        $('#caixa').innerHTML = sucesso('Conta criada!', 'Agora é só entrar com seu e-mail e senha.', '<a class="btn verde" href="#/entrar">Entrar agora</a>');
      } catch (err) { erroEm($('#erro'), err.message); carregandoBtn(b, false, 'Criar minha conta'); }
    };
  }

  const sucesso = (t, d, extra = '') => `<div class="sucesso passo-conteudo"><svg class="check" viewBox="0 0 100 100"><circle cx="50" cy="50" r="46" fill="none" stroke="#2F8F3F" stroke-width="6"/><path d="M30 52 45 66 72 36" fill="none" stroke="#2F8F3F" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/></svg>
    <h1>${t}</h1><p class="sub">${d}</p>${extra}</div>`;

  const cpfValido = (c) => {
    c = c.replace(/\D/g, ''); if (c.length !== 11 || /^(\d)\1{10}$/.test(c)) return false;
    const dv = (n) => { let s = 0; for (let i = 0; i < n; i++) s += Number(c[i]) * (n + 1 - i); const r = (s * 10) % 11; return r === 10 ? 0 : r; };
    return dv(9) === Number(c[9]) && dv(10) === Number(c[10]);
  };
  const PESSOAIS = /@(gmail|hotmail|outlook|live|yahoo|icloud|bol|uol|terra|ig|msn|proton(mail)?)\./i;

  function cadastroProfissional(app, perfil, cidades) {
    const analista = perfil === 'analista';
    const cor = analista ? 'var(--ceu)' : 'var(--laranja)';
    const v = { perfil: perfil.toUpperCase(), aceite_termo: false };
    const PASSOS = ['Quem é você', analista ? 'Formação e registro' : 'Cargo e nomeação', 'Comprovação', 'Segurança'];
    let passo = 0;
    moldura(app, analista ? 'Analistas publicam com responsabilidade' : 'Gestores decidem pela cidade',
      analista ? 'Por isso conferimos seu vínculo e seu registro no conselho. Depois de aprovado, suas análises passam por revisão de outro especialista.'
               : 'Por isso conferimos sua portaria de nomeação e o órgão em que você trabalha. Metas que você propõe são aprovadas por outro gestor.',
      `<a href="#/cadastro" class="link-btn">← Trocar perfil</a><h1 style="margin-top:10px">Cadastro de ${analista ? 'analista' : 'gestor público'}</h1>
       <p class="sub">4 passos rápidos. Um administrador confere os dados antes de liberar o acesso.</p>
       <div class="passos" style="--c:${cor}">${PASSOS.map((p) => `<div class="p"><i></i><span>${p}</span></div>`).join('')}</div>
       <form id="fp" novalidate><div id="erro"></div><div id="corpo"></div>
       <div class="navegar"><button type="button" class="btn fantasma" id="voltar">← Voltar</button><button class="btn" id="avancar" style="--c:${analista ? 'var(--azul)' : 'var(--laranja)'}">Continuar →</button></div></form>`, true);

    const corpos = [
      () => `<div class="campo"><label for="nome">Nome completo</label><input id="nome" value="${esc(v.nome || '')}"><span class="ajuda"></span></div>
        <div class="linha2"><div class="campo"><label for="cpf">CPF <small>guardado protegido</small></label><input id="cpf" inputmode="numeric" placeholder="000.000.000-00" value="${esc(v.cpf || '')}"><span class="ajuda"></span></div>
        <div class="campo"><label for="tel">Telefone do trabalho</label><input id="tel" inputmode="tel" placeholder="(11) 3215-0000" value="${esc(v.telefone || '')}"><span class="ajuda"></span></div></div>
        <div class="campo"><label for="emi">E-mail institucional <small>do órgão (não vale Gmail etc.)</small></label><input id="emi" type="email" placeholder="nome@prefeitura.sp.gov.br" value="${esc(v.email_institucional || '')}"><span class="ajuda"></span></div>`,
      () => `<div class="linha2"><div class="campo"><label for="orgao">Órgão / instituição</label><input id="orgao" value="${esc(v.orgao || '')}"><span class="ajuda"></span></div>
        <div class="campo"><label for="cargo">Cargo</label><input id="cargo" value="${esc(v.cargo || '')}"><span class="ajuda"></span></div></div>
        <div class="linha2"><div class="campo"><label for="mat">Matrícula</label><input id="mat" value="${esc(v.matricula || '')}"><span class="ajuda"></span></div>
        <div class="campo"><label for="form">Formação</label><input id="form" placeholder="Ex.: Engenharia Ambiental (USP, 2018)" value="${esc(v.formacao || '')}"><span class="ajuda"></span></div></div>
        ${analista
          ? `<div class="campo"><label for="reg">Registro no conselho profissional</label><input id="reg" placeholder="Ex.: CREA-SP 5069990001" value="${esc(v.registro_conselho || '')}"><span class="ajuda">CREA, CRQ, CRBio, CORECON…</span></div>
             <div class="campo"><label for="cid">Cidade em que atua <small>opcional</small></label><select id="cid">${opcoesCidades(cidades, 'Todas / não se aplica')}</select></div>`
          : `<div class="campo"><label for="port">Portaria de nomeação</label><input id="port" placeholder="Ex.: Portaria nº 18/2025 (Diário Oficial)" value="${esc(v.portaria_nomeacao || '')}"><span class="ajuda">Número e data da publicação no Diário Oficial.</span></div>
             <div class="campo"><label for="cid">Cidade em que atua</label><select id="cid">${opcoesCidades(cidades)}</select><span class="ajuda"></span></div>`}`,
      () => `<div class="campo"><label for="doc">Link da declaração de vínculo <small>PDF assinado pelo órgão</small></label><input id="doc" type="url" placeholder="https://..." value="${esc(v.documento_url || '')}"><span class="ajuda">Use um link https (Drive, OneDrive, site do órgão).</span></div>
        <div class="campo"><label for="just">Por que você precisa do acesso? <small id="cont">0/50</small></label><textarea id="just" placeholder="${analista ? 'Ex.: Acompanho a reciclagem da cidade e quero publicar análises com a minha equipe…' : 'Ex.: Coordeno o plano municipal de saneamento e preciso definir metas de perdas…'}">${esc(v.justificativa || '')}</textarea><span class="ajuda"></span></div>
        <label class="marcar"><input type="checkbox" id="termo" ${v.aceite_termo ? 'checked' : ''}> Declaro que as informações são verdadeiras e aceito o termo de responsabilidade pelo uso dos dados${analista ? ' e pelas análises que publicar' : ' e pelas metas e ações que registrar'}.</label>`,
      () => `${campoSenha('forte')}`,
    ];
    let senhaOk = () => false;
    const desenhar = () => {
      $$('.passos .p').forEach((p, i) => { p.classList.toggle('feito', i < passo); p.classList.toggle('atual', i === passo); });
      $('#corpo').innerHTML = `<div class="passo-conteudo">${corpos[passo]()}</div>`; $('#erro').innerHTML = '';
      $('#voltar').style.visibility = passo ? 'visible' : 'hidden';
      $('#avancar').textContent = passo === 3 ? 'Enviar pedido ✓' : 'Continuar →';
      if ($('#cid') && v.id_municipio) $('#cid').value = v.id_municipio;
      if ($('#cpf')) $('#cpf').oninput = (e) => { const d = e.target.value.replace(/\D/g, '').slice(0, 11); e.target.value = d.replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d{1,2})$/, '$1-$2'); };
      if ($('#just')) { const at = () => { const n = $('#just').value.trim().length; $('#cont').textContent = `${n}/50`; $('#cont').style.color = n >= 50 ? 'var(--verde)' : ''; }; $('#just').oninput = at; at(); }
      if (passo === 3) senhaOk = ligarSenha('forte');
      $('#corpo input, #corpo select, #corpo textarea')?.focus();
    };
    const validar = () => {
      $$('.campo.erro').forEach((c) => c.classList.remove('erro'));
      if (passo === 0) {
        Object.assign(v, { nome: $('#nome').value.trim(), cpf: $('#cpf').value, telefone: $('#tel').value, email_institucional: $('#emi').value.trim() });
        marcarErro('nome', v.nome.split(' ').length < 2 ? 'Nome completo, por favor.' : '');
        marcarErro('cpf', !cpfValido(v.cpf) ? 'CPF inválido.' : '');
        marcarErro('tel', !/^\d{10,11}$/.test(v.telefone.replace(/\D/g, '')) ? 'DDD + número.' : '');
        marcarErro('emi', !/^\S+@\S+\.\S+$/.test(v.email_institucional) ? 'E-mail inválido.' : PESSOAIS.test(v.email_institucional) ? 'Use o e-mail do órgão, não o pessoal.' : '');
      }
      if (passo === 1) {
        Object.assign(v, { orgao: $('#orgao').value.trim(), cargo: $('#cargo').value.trim(), matricula: $('#mat').value.trim(), formacao: $('#form').value.trim(), id_municipio: $('#cid').value || null });
        ['orgao', 'cargo', 'mat', 'form'].forEach((id) => marcarErro(id, !$(`#${id}`).value.trim() ? 'Obrigatório.' : ''));
        if (analista) { v.registro_conselho = $('#reg').value.trim(); marcarErro('reg', v.registro_conselho.length < 4 ? 'Informe o registro.' : ''); }
        else { v.portaria_nomeacao = $('#port').value.trim(); marcarErro('port', v.portaria_nomeacao.length < 6 ? 'Informe a portaria.' : ''); marcarErro('cid', !v.id_municipio ? 'Escolha a cidade.' : ''); }
      }
      if (passo === 2) {
        Object.assign(v, { documento_url: $('#doc').value.trim(), justificativa: $('#just').value.trim(), aceite_termo: $('#termo').checked });
        marcarErro('doc', !/^https:\/\/\S+\.\S+/.test(v.documento_url) ? 'O link precisa começar com https://' : '');
        marcarErro('just', v.justificativa.length < 50 ? 'Escreva pelo menos 50 caracteres.' : '');
        if (!v.aceite_termo && !$$('.campo.erro').length) { erroEm($('#erro'), 'É preciso aceitar o termo de responsabilidade.'); return false; }
      }
      if (passo === 3) {
        v.senha = $('#senha').value;
        marcarErro('senha2', $('#senha2').value !== v.senha ? 'As senhas não são iguais.' : '');
        if (!senhaOk()) { erroEm($('#erro'), 'A senha precisa cumprir todas as regras.'); return false; }
      }
      if ($$('.campo.erro').length) { erroEm($('#erro'), 'Confira os campos marcados.'); return false; }
      return true;
    };
    $('#voltar').onclick = () => { if (passo) { passo--; desenhar(); } };
    $('#fp').onsubmit = async (e) => {
      e.preventDefault(); if (!validar()) return;
      if (passo < 3) { passo++; return desenhar(); }
      const b = $('#avancar'); carregandoBtn(b, true);
      try {
        await API.post('/auth/cadastro/profissional', { ...v, cpf: v.cpf.replace(/\D/g, ''), telefone: v.telefone.replace(/\D/g, '') });
        $('#caixa').innerHTML = sucesso('Pedido enviado! 📨', 'Um administrador vai conferir seus documentos. A resposta chega no seu e-mail institucional.', `
          <div class="linha-tempo"><div class="feito"><b class="bola">✓</b><span><strong>Pedido enviado</strong><small>agora</small></span></div>
          <div class="agora"><b class="bola">2</b><span><strong>Conferência pelo administrador</strong><small>vínculo, ${analista ? 'registro no conselho' : 'portaria de nomeação'} e documento</small></span></div>
          <div><b class="bola">3</b><span><strong>Acesso liberado</strong><small>você entra com seu e-mail e senha</small></span></div></div>
          <a class="btn fantasma" href="#/">Voltar ao início</a>`);
      } catch (err) {
        erroEm($('#erro'), err.message); carregandoBtn(b, false, 'Enviar pedido ✓');
        if (/CPF|e-mail|Telefone|nome/i.test(err.message)) { passo = 0; desenhar(); erroEm($('#erro'), err.message); }
      }
    };
    desenhar();
  }

  return { inicio, entrar, cadastro };
})();
