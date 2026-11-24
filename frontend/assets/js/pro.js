/* EcoCity — páginas profissionais: analista (laboratório, assistente, análises, metas), gestor (sala de situação,
   conselheiro, ações), radar de riscos das 8 cidades e administração */
const Pro = (() => {
  const { $, $$, esc, num, ico, toast, revelar, SERV, mesTxt, iniciais } = UI;
  const { casca, topo, esqueleto, pode, pilula, gavetaFonte, casasDe, contaHtml } = Painel;
  const COR_CID = ['#1D5FA8', '#2F8F3F', '#E8892B', '#4FB3E3', '#163E6E', '#C2410C', '#7C3AED', '#0F766E'];

  // ============================================================== LABORATÓRIO DE DADOS (analista)
  const lab = { cod: 'AGU-01', cids: null, meses: 12 };
  async function laboratorio(app) {
    casca(app, 'laboratorio', esqueleto());
    const d = await API.pegar('/laboratorio');
    lab.cids ||= d.municipios.map((m) => m.id_municipio);
    const grupos = [...new Set(d.indicadores.map((i) => i.servico))];
    $('#conteudo').innerHTML = `
      ${topo('Laboratório de dados ', 'Escolha o indicador, as cidades e o período. Clique em qualquer valor da tabela para ver a fonte.',
        '<button class="btn fantasma sm" id="csv" title="Planilha com uma linha por cidade e mês">Baixar planilha (CSV)</button><button class="btn verde sm" id="pedir">Pedir relatório</button>')}
      <div class="lab-ajuda revelar"><div><b>O que tem aqui</b><p>Os valores mensais do indicador escolhido para cada cidade, com a meta e a origem de cada número (oficial do mês, oficial do ano ou estimado).</p></div>
        <div><b>Baixar planilha (CSV)</b><p>Abre no Excel. Cada linha é <b>uma cidade em um mês</b>, com as colunas: mês, cidade, código e nome do indicador, valor, unidade, meta e origem.</p></div>
        <div><b>Pedir relatório</b><p>O assistente escreve um relatório em texto sobre o indicador, as cidades e o período escolhidos.</p></div></div>
      <div class="cartao lab-filtros revelar">
        <label class="lf"><span>Indicador</span><select class="seletor" id="fInd">${grupos.map((g) => `<optgroup label="${esc(g)}">${d.indicadores.filter((i) => i.servico === g).map((i) => `<option value="${i.codigo}" ${i.codigo === lab.cod ? 'selected' : ''}>${esc(i.nome)}</option>`).join('')}</optgroup>`).join('')}</select></label>
        <label class="lf"><span>Período</span><select class="seletor" id="fPer">${[[6, '6 meses'], [12, '12 meses'], [24, '24 meses']].map(([v, t]) => `<option value="${v}" ${v === lab.meses ? 'selected' : ''}>Últimos ${t}</option>`).join('')}</select></label>
        <div class="lf largo"><span>Cidades <button class="link-btn" id="todas">todas</button> · <button class="link-btn" id="nenhuma">nenhuma</button></span><div class="chips-cid" id="fCid">${d.municipios.map((m, i) => `<button data-id="${m.id_municipio}" style="--c:${COR_CID[i % 8]}" class="${lab.cids.includes(m.id_municipio) ? 'ativo' : ''}"><i></i>${esc(m.nome)}</button>`).join('')}</div></div>
      </div>
      <div id="labRes"></div>`;
    const corDe = (id) => COR_CID[d.municipios.findIndex((m) => m.id_municipio === id) % 8];
    const nomeDe = (id) => d.municipios.find((m) => m.id_municipio === id)?.nome;
    const desenhar = () => {
      const ind = d.indicadores.find((i) => i.codigo === lab.cod);
      const meses = d.meses.slice(-lab.meses);
      const linhas = d.serie.filter((s) => s.c === lab.cod && lab.cids.includes(s.m) && meses.includes(s.p));
      if (!lab.cids.length) { $('#labRes').innerHTML = '<div class="cartao" style="margin-top:20px">Escolha pelo menos uma cidade.</div>'; return; }
      const campo = 'v';
      const ult = linhas.filter((l) => l.p === meses[meses.length - 1]);
      const ordem = [...ult].sort((a, b) => (ind.sentido === 'MAIOR_MELHOR' ? b.v - a.v : a.v - b.v));
      const naMeta = (v) => (ind.sentido === 'MAIOR_MELHOR' ? v >= Number(ind.meta) : v <= Number(ind.meta));
      const media = ult.reduce((a, b) => a + b.v, 0) / (ult.length || 1);
      const pctMeta = Math.round((ult.filter((l) => naMeta(l.v)).length / (ult.length || 1)) * 100);
      const pctOf = Math.round((linhas.filter((l) => l.o !== 'ESTIMADO').length / (linhas.length || 1)) * 100);
      const pctM = Math.round((linhas.filter((l) => l.o === 'REAL').length / (linhas.length || 1)) * 100); const pctA = pctOf - pctM;
      const ini = linhas.filter((l) => l.p === meses[0]); const mediaIni = ini.reduce((a, b) => a + b.v, 0) / (ini.length || 1);
      const varP = mediaIni ? ((media - mediaIni) / mediaIni) * 100 : 0; const melhorou = ind.sentido === 'MAIOR_MELHOR' ? varP > 0 : varP < 0;
      const cs = casasDe(media);
      $('#labRes').innerHTML = `
        <div class="grade g-4" style="margin-top:20px">
          <div class="cartao kpi revelar"><small>Média no último mês</small><b>${num(media, cs)}</b><span>${esc(ind.unidade)} · meta ${num(ind.meta, casasDe(ind.meta))}</span></div>
          <div class="cartao kpi revelar" style="--atraso:.05s"><small>Variação no período</small><b class="${melhorou ? 'ok' : 'ruim'}">${varP >= 0 ? '+' : ''}${num(varP, 1)}%</b><span>${melhorou ? 'melhorou' : 'piorou'} (média das cidades)</span></div>
          <div class="cartao kpi revelar" style="--atraso:.1s"><small>Cidades na meta</small><b>${pctMeta}%</b><span>${ult.filter((l) => naMeta(l.v)).length} de ${ult.length} no último mês</span></div>
          <div class="cartao kpi revelar" style="--atraso:.15s"><small>Dados oficiais</small><b>${pctOf}%</b><span>dos valores da seleção: ${pctM}% oficial do mês · ${pctA}% oficial do ano</span></div></div>
        <div class="grade g-hero inv" style="margin-top:20px">
          <div class="cartao revelar"><span class="rotulo">${esc(ind.nome)} · ${esc(ind.unidade)} · mês a mês</span>
            ${UI.linha(lab.cids.map((id) => ({ nome: nomeDe(id), cor: corDe(id), valores: meses.map((m) => linhas.find((l) => l.m === id && l.p === m)?.[campo] ?? null) })), { altura: 300, rotulos: meses.map(mesTxt), meta: Number(ind.meta), unidade: ind.unidade, casas: cs })}
            <div class="def"><b>Como é calculado</b>${contaHtml(ind)}<p>${ind.sentido === 'MAIOR_MELHOR' ? 'Quanto <b>maior</b>, melhor' : 'Quanto <b>menor</b>, melhor'} · meta ${num(ind.meta, casasDe(ind.meta))} ${esc(ind.unidade)} ${UI.info('meta')}</p></div></div>
          <div class="cartao revelar" style="--atraso:.1s"><span class="rotulo">Ranking em ${mesTxt(meses[meses.length - 1])}</span>
            ${UI.barrasH(ordem.map((l) => ({ rotulo: nomeDe(l.m), valor: l.v })), { meta: Number(ind.meta), unidade: ind.unidade, casas: cs, sentido: ind.sentido })}</div></div>
        <div class="cartao revelar" style="margin-top:20px"><div style="display:flex;justify-content:space-between;flex-wrap:wrap;gap:10px;align-items:center"><span class="rotulo" style="margin:0">Tabela mês a mês · ${esc(ind.nome)} em ${esc(ind.unidade)}</span>
          <span class="leg-orig"><i class="o-REAL"></i>oficial do mês <i class="o-DERIVADO"></i>oficial do ano <i class="o-ESTIMADO"></i>estimado · clique no valor para ver a fonte</span></div>
          <div class="rolar-x"><table class="tabela lab-tab"><thead><tr><th>Mês</th>${lab.cids.map((id) => `<th>${esc(nomeDe(id))}</th>`).join('')}</tr></thead><tbody>
          ${[...meses].reverse().map((m) => `<tr><td><b>${mesTxt(m)}</b></td>${lab.cids.map((id) => { const l = linhas.find((x) => x.m === id && x.p === m); return l ? `<td><button class="cel-v o-${l.o} ${naMeta(l.v) ? 'ok' : ''}" data-m="${id}" data-p="${m}" title="${l.o === 'ESTIMADO' ? 'estimado' : l.o === 'DERIVADO' ? 'oficial do ano' : 'oficial do mês'} · ${naMeta(l.v) ? 'dentro da meta' : 'fora da meta'}">${num(l.v, cs)}</button></td>` : '<td>—</td>'; }).join('')}</tr>`).join('')}
          </tbody></table></div></div>`;
      revelar($('#labRes')); UI.ativarGraficos($('#labRes'));
      $$('.cel-v').forEach((b) => (b.onclick = async () => {
        try { const f = await API.get(`/fontes/valor?municipio=${b.dataset.m}&codigo=${lab.cod}&mes=${b.dataset.p}`); gavetaFonte(`${ind.nome} em ${nomeDe(Number(b.dataset.m))}`, f, b.dataset.p); } catch (e) { toast(e.message, 'erro'); }
      }));
      $('#csv').onclick = () => {
        const ORIG = { REAL: 'oficial do mês', DERIVADO: 'oficial do ano', ESTIMADO: 'estimado' };
        const cab = ['mes', 'cidade', 'codigo', 'indicador', 'valor', 'unidade', 'meta', 'dentro_da_meta', 'origem'];
        const csv = [cab.join(';'), ...linhas.map((l) => [l.p, nomeDe(l.m), lab.cod, ind.nome, String(l.v).replace('.', ','), ind.unidade, String(ind.meta).replace('.', ','), naMeta(l.v) ? 'sim' : 'não', ORIG[l.o]].join(';'))].join('\n');
        const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([`﻿${csv}`], { type: 'text/csv' })); a.download = `ecocity_${lab.cod}_${meses[0]}_${meses[meses.length - 1]}.csv`; a.click();
      };
      $('#pedir').onclick = () => { sessionStorage.setItem('eco.pergunta', `Relatório de ${ind.nome.toLowerCase()} ${lab.cids.length === d.municipios.length ? 'nas 8 cidades' : `em ${lab.cids.map(nomeDe).join(', ')}`} nos últimos ${lab.meses} meses`); location.hash = '#/app/assistente'; };
    };
    $('#fInd').onchange = (e) => { lab.cod = e.target.value; desenhar(); };
    $('#fPer').onchange = (e) => { lab.meses = Number(e.target.value); desenhar(); };
    $$('#fCid button').forEach((b) => (b.onclick = () => { const id = Number(b.dataset.id); lab.cids = lab.cids.includes(id) ? lab.cids.filter((x) => x !== id) : [...lab.cids, id]; b.classList.toggle('ativo'); desenhar(); }));
    $('#todas').onclick = () => { lab.cids = d.municipios.map((m) => m.id_municipio); $$('#fCid button').forEach((b) => b.classList.add('ativo')); desenhar(); };
    $('#nenhuma').onclick = () => { lab.cids = []; $$('#fCid button').forEach((b) => b.classList.remove('ativo')); desenhar(); };
    revelar($('#conteudo')); desenhar();
  }

  // ============================================================== ASSISTENTE DE RELATÓRIOS (analista)
  async function assistente(app) {
    casca(app, 'assistente', '');
    const MODELOS = [['', 'Relatório de uma cidade', 'Relatório geral de Campinas nos últimos 12 meses'], ['', 'Comparar cidades', 'Compare a reciclagem das 8 cidades'],
      ['', 'Evolução de um indicador', 'Evolução do consumo de água em Santos e Sorocaba em 2026'], ['', 'Fonte de um dado', 'Fonte das perdas de água em Guarulhos'],
      ['', 'Qualidade dos dados', 'Qual o % de dados oficiais por área?'], ['', 'Relatório temático', 'Relatório de energia solar nas 8 cidades nos últimos 24 meses']];
    $('#conteudo').innerHTML = `${topo('Assistente de relatórios ', 'Peça um relatório, uma comparação ou a fonte de um dado. O assistente usa só os números do banco e monta um rascunho que você revisa e publica.')}
      <div class="chat-layout"><aside class="chat-lado revelar"><span class="rotulo">Comece por um modelo</span>${MODELOS.map(([e, t, q]) => `<button class="modelo" data-q="${esc(q)}"><span>${e}</span><div><b>${t}</b><small>${esc(q)}</small></div></button>`).join('')}
        <p class="dica-lado">Diga sempre <b>tema</b>, <b>cidades</b> e <b>período</b>. O rascunho vira uma análise com um clique e passa pela revisão de outro analista.</p></aside>
        <div class="cartao chat-area" id="chatArea"></div></div>`;
    const q = sessionStorage.getItem('eco.pergunta'); sessionStorage.removeItem('eco.pergunta');
    const c = Chat.pagina($('#chatArea'), { placeholder: 'Ex.: Relatório de reciclagem em Sorocaba nos últimos 12 meses', pergunta: q });
    $$('[data-q]').forEach((b) => (b.onclick = () => c.enviar(b.dataset.q)));
    revelar($('#conteudo'));
  }

  // ============================================================== RADAR DE RISCOS (todas as cidades)
  async function riscos(app) {
    casca(app, 'riscos', esqueleto());
    const [r, alertas] = await Promise.all([API.pegar('/riscos'), API.pegar('/alertas')]);
    const ordemAreas = Object.keys(SERV);
    const RG = { ALTO: ['critico', 'Risco alto'], MEDIO: ['laranja', 'Risco médio'], BAIXO: ['verde', 'Risco baixo'] };
    const conta = (n) => r.cidades.filter((c) => c.nivel === n).length;
    let filtro = 'TODOS'; let cidadeF = '';
    $('#conteudo').innerHTML = `
      ${topo('Radar de riscos ', `A IA confere todo mês os 8 indicadores das 8 cidades. Dados de ${mesTxt(r.mes)}.`)}
      <div class="grade g-3">${[['ALTO', 'Risco alto', 'cidades precisam de ação'], ['MEDIO', 'Risco médio', 'cidades pedem atenção'], ['BAIXO', 'Risco baixo', 'cidades no caminho certo']].map(([n, t, s], i) => `<div class="cartao kpi-r ${RG[n][0]} revelar" style="--atraso:${i * 0.08}s"><b data-contar="${conta(n)}">0</b><div><strong>${t}</strong><small>${s}</small></div></div>`).join('')}</div>
      <div class="cartao revelar" style="margin-top:20px">
        <div class="matriz-cab"><div><span class="rotulo" style="margin:0">Situação de cada cidade por área</span><p>Cada área tem 2 números e cada número tem uma meta. O quadro mostra quantas metas a cidade cumpre na área. Clique na cidade para ver os alertas.</p></div>
          <div class="legenda-m">${pilula('BOM', 'Bom · cumpre as 2 metas')}${pilula('ATENCAO', 'Atenção · cumpre 1')}${pilula('CRITICO', 'Crítico · não cumpre nenhuma')}</div></div>
        <div class="matriz" role="table">
          <div class="mz-l cab" role="row"><span role="columnheader">Cidade</span>${ordemAreas.map((a) => `<span role="columnheader">${ico(SERV[a].ico)} ${a}</span>`).join('')}<span role="columnheader">Situação geral</span></div>
          ${r.cidades.map((c, i) => `<button class="mz-l revelar" role="row" style="--atraso:${i * 0.04}s" data-cid="${esc(c.municipio)}"><span class="mz-cid" role="cell"><b>${esc(c.municipio)}</b><small>${c.metas_cumpridas} de ${c.metas_total} metas cumpridas</small></span>
            ${ordemAreas.map((a) => { const x = c.areas.find((y) => y.servico === a) || { nivel: 'CRITICO', metas: '0/2' }; return `<span role="cell" class="mz-c" data-area="${a}" title="${a}: ${x.metas.replace('/', ' de ')} metas cumpridas">${pilula(x.nivel)}<small>${x.metas.replace('/', ' de ')} metas</small></span>`; }).join('')}
            <span role="cell" class="mz-g"><span class="chip ${RG[c.nivel][0]}"><i></i>${RG[c.nivel][1]}</span><small>${c.criticos} crítico${c.criticos === 1 ? '' : 's'} · ${c.atencao} atenção</small></span></button>`).join('')}
        </div>
        <p class="nota-rodape">${UI.info('risco')} Risco geral = cada meta não cumprida soma 7 pontos + alertas abertos da IA (crítico soma 6, atenção soma 2). Alto a partir de 50, médio a partir de 30.</p></div>
      <div style="display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;margin:34px 0 16px"><h2 style="font-size:22px;color:var(--navy)">Alertas da IA</h2>
        <div class="filtros" id="filtros">${[['TODOS', 'Todos'], ['CRITICO', 'Críticos'], ['ATENCAO', 'Atenção']].map(([k, t]) => `<button class="filtro ${k === filtro ? 'ativo' : ''}" data-f="${k}">${t}</button>`).join('')}
          <select class="seletor" id="fcid" style="padding:7px 14px"><option value="">Todas as cidades</option>${r.cidades.map((c) => `<option>${esc(c.municipio)}</option>`).join('')}</select></div></div>
      <div class="grade" id="lista"></div>`;
    const TIPO = { ALERTA_META: 'Fora da meta', TENDENCIA: 'Tendência', PREVISAO: 'Previsão', ANOMALIA: 'Fora do padrão', CORRELACAO: 'Relação entre dados' };
    const lista = () => {
      const l = alertas.filter((a) => (filtro === 'TODOS' || a.severidade === filtro) && (!cidadeF || a.municipio === cidadeF));
      $('#lista').innerHTML = l.length ? l.map((a, i) => `<article class="alerta ${a.severidade} revelar" style="--atraso:${Math.min(i, 8) * 0.05}s"><span class="faixa"></span>
        <div><h4>${esc(a.titulo)}</h4><p>${esc(a.descricao)}</p><div class="meta-a"><span class="chip cinza">${esc(a.municipio)}</span><span class="chip ${SERV[a.servico]?.classe || ''}"><i></i>${esc(a.servico)}</span><span class="chip cinza">${TIPO[a.tipo] || a.tipo}</span>
          <span class="chip cinza">confiança ${num(a.confianca, 0)}%</span><span class="chip ${a.status === 'VALIDADA' ? 'verde' : 'cinza'}">${a.status === 'NOVA' ? 'novo' : a.status.toLowerCase().replace('_', ' ')}</span></div></div>
        ${pode('ANALISTA') && a.status !== 'VALIDADA' ? `<div class="acoes-a"><button class="btn verde sm" data-v="${a.id_analise}">Validar</button><button class="btn fantasma sm" data-d="${a.id_analise}">Descartar</button></div>` : '<span></span>'}</article>`).join('')
        : '<div class="cartao" style="text-align:center;color:var(--tinta-2)">Nenhum alerta com esse filtro. </div>';
      revelar($('#lista'));
      const mudar = async (id, status) => { try { await API.patch(`/alertas/${id}`, { status }); const a = alertas.find((x) => x.id_analise === Number(id)); if (status === 'DESCARTADA') alertas.splice(alertas.indexOf(a), 1); else a.status = status; API.limpar('/alertas'); toast(status === 'VALIDADA' ? 'Alerta validado' : 'Alerta descartado', 'ok'); lista(); } catch (e) { toast(e.message, 'erro'); } };
      $$('[data-v]').forEach((b) => (b.onclick = () => mudar(b.dataset.v, 'VALIDADA')));
      $$('[data-d]').forEach((b) => (b.onclick = () => mudar(b.dataset.d, 'DESCARTADA')));
    };
    $$('#filtros [data-f]').forEach((b) => (b.onclick = () => { filtro = b.dataset.f; $$('#filtros [data-f]').forEach((x) => x.classList.toggle('ativo', x === b)); lista(); }));
    $('#fcid').onchange = (e) => { cidadeF = e.target.value; lista(); };
    $$('[data-cid]').forEach((b) => (b.onclick = () => { cidadeF = b.dataset.cid; $('#fcid').value = cidadeF; lista(); $('#lista').scrollIntoView({ behavior: 'smooth', block: 'start' }); }));
    revelar($('#conteudo')); lista();
  }

  // ============================================================== SALA DE SITUAÇÃO (gestor)
  let salaCid = '';
  async function sala(app) {
    casca(app, 'sala', esqueleto());
    salaCid ||= API.usuario.municipio ? String(API.usuario.municipio) : '';
    const [lst] = await Promise.all([API.pegar('/laboratorio')]);
    const desenhar = async () => {
      const d = await API.pegar(`/sala${salaCid ? `?municipio=${salaCid}` : ''}`);
      const meses = [...new Set(d.tendencia.map((t) => t.ano_mes))];
      const k = d.kpis;
      $('#conteudo').innerHTML = `
        ${topo(`Sala de situação `, `${salaCid ? esc(lst.municipios.find((m) => String(m.id_municipio) === salaCid)?.nome) : 'As 8 cidades'} · ${esc(d.mesTxt)}. O que está acontecendo, onde agir e o que já funcionou.`,
          `<select class="seletor" id="sCid"><option value="">Todas as cidades</option>${lst.municipios.map((m) => `<option value="${m.id_municipio}" ${String(m.id_municipio) === salaCid ? 'selected' : ''}>${esc(m.nome)}</option>`).join('')}</select>`)}
        <div class="grade g-4">
          <div class="cartao kpi revelar" style="--atraso:.05s"><small>Metas cumpridas ${UI.info('meta')}</small><b>${k.pct_metas}%</b><span>dos números ${salaCid ? 'da cidade' : 'das 8 cidades'} no mês</span></div>
          <div class="cartao kpi revelar" style="--atraso:.1s"><small>Alertas críticos</small><b class="${k.criticos ? 'ruim' : 'ok'}" data-contar="${k.criticos}">0</b><span>abertos</span></div>
          <div class="cartao kpi revelar" style="--atraso:.15s"><small>Ações em andamento</small><b data-contar="${k.acoes_andamento}">0</b><span>planejadas ou em execução</span></div>
          <div class="cartao kpi revelar" style="--atraso:.2s"><small>Dados oficiais</small><b>${k.pct_mes + k.pct_ano}%</b><span>no mês: ${k.pct_mes}% do mês · ${k.pct_ano}% do ano<br>último oficial: ${k.ult_mes}% do mês · ${k.ult_ano}% do ano</span></div></div>
        <div class="grade g-hero inv" style="margin-top:20px">
          <div class="cartao revelar"><div class="cab-c"><span class="rotulo" style="margin:0">Onde agir primeiro</span><small>ordem: quanto falta para a meta × importância do número × população ${UI.info('meta')}</small></div>
            <ol class="prio">${d.prioridades.map((p, i) => `<li class="revelar" style="--atraso:${i * 0.05}s"><span class="n">${i + 1}</span><div class="pd"><b>${esc(p.indicador)}</b> <span class="chip cinza">${esc(p.municipio)}</span>
              <p>${UI.md(p.frase || '')}</p><div class="dist"><i style="width:${Math.min(100, p.distancia_pct)}%"></i></div><small>${num(p.distancia_pct, 0)}% longe da meta · hoje ${num(p.valor, casasDe(p.valor))} ${esc(p.unidade)} · meta ${num(p.meta, casasDe(p.meta))} · ${p.origem === 'ESTIMADO' ? 'estimado' : 'oficial'}</small></div>
              <div class="pa"><button class="btn sm" data-sim="${esc(`E se ${String(p.simples || p.indicador).toLowerCase()} de ${p.municipio} melhorar 10%?`)}">Simular</button><button class="btn fantasma sm" data-sim="${esc(`Que ações melhoram ${p.indicador.toLowerCase()} em ${p.municipio}?`)}">Opções</button></div></li>`).join('') || '<li>Todos os indicadores estão na meta. </li>'}</ol></div>
          <div class="cartao revelar" style="--atraso:.1s"><span class="rotulo">Metas cumpridas por indicador</span>
            ${UI.barrasH(d.metasInd.map((m) => ({ rotulo: m.simples, valor: (m.atingiram / m.total) * 100, cor: SERV[m.servico]?.cor })), { unidade: '%', casas: 0 })}</div></div>
        <div class="grade g-2" style="margin-top:20px">
          <div class="cartao revelar"><span class="rotulo">Metas cumpridas por área, mês a mês (8 cidades)</span>
            ${UI.linha(Object.keys(SERV).map((sv) => ({ nome: sv, cor: SERV[sv].cor, valores: meses.map((m) => { const t = d.tendencia.find((x) => x.ano_mes === m && x.servico === sv); return t ? Number(t.pct_metas_atingidas) : null; }) })), { altura: 300, largura: 560, rotulos: meses.map(mesTxt), unidade: '% das metas', casas: 0, min: 0, max: 100 })}
            <p class="def">De todas as metas de cada área nas 8 cidades, quantas % estavam cumpridas em cada mês.</p></div>
          <div class="cartao revelar" style="--atraso:.1s"><span class="rotulo">Metas cumpridas por cidade (de 8)</span>${UI.barrasH([...d.ranking].sort((a, b) => Number(b.metas_atingidas) - Number(a.metas_atingidas)).map((r) => ({ rotulo: r.municipio, valor: Number(r.metas_atingidas), destaque: String(r.id_municipio) === salaCid })), { casas: 0, unidade: 'de 8' })}
            <p class="def">Cada cidade tem 8 números e cada número tem uma meta aprovada. A barra mostra quantas dessas 8 metas a cidade cumpre hoje.</p></div></div>
        <div class="grade g-2" style="margin-top:20px">
          <div class="cartao revelar"><div class="cab-c"><span class="rotulo" style="margin:0">Ações e resultados</span><a class="link-btn" href="#/app/acoes">ver todas →</a></div>
            <div class="lista-acoes">${d.acoes.slice(0, 5).map((a) => `<div class="la"><span class="chip ${a.efeito === 'MELHOROU' ? 'verde' : a.efeito === 'PIOROU' ? 'critico' : 'cinza'}">${a.efeito === 'MELHOROU' ? `melhorou ${num(Math.abs(a.variacao_pct), 0)}%` : a.efeito === 'PIOROU' ? 'não melhorou' : a.status === 'PLANEJADA' ? 'planejada' : 'em execução'}</span><b>${esc(a.titulo)}</b><small>${esc(a.municipio)} · ${esc(a.indicador_nome)} · R$ ${num(a.orcamento / 1e6, 1)} mi</small></div>`).join('') || '<p>Nenhuma ação registrada.</p>'}</div></div>
          <div class="cartao revelar" style="--atraso:.1s"><div class="cab-c"><span class="rotulo" style="margin:0">Alertas críticos recentes</span><a class="link-btn" href="#/app/riscos">radar →</a></div>
            ${d.alertas.map((a) => `<div class="alerta-mini"><span></span><div><b>${esc(a.titulo)}</b><small>${esc(a.municipio)} · ${esc(a.servico)}</small></div></div>`).join('') || '<p>Nenhum alerta crítico. </p>'}</div></div>`;
      revelar($('#conteudo')); UI.animarBarras?.($('#conteudo')); UI.ativarGraficos($('#conteudo'));
      $('#sCid').onchange = (e) => { salaCid = e.target.value; desenhar(); };
      $$('[data-sim]').forEach((b) => (b.onclick = () => { sessionStorage.setItem('eco.pergunta', b.dataset.sim); location.hash = '#/app/conselheiro'; }));
    };
    await desenhar();
  }

  // ============================================================== CONSELHEIRO IA (gestor)
  async function conselheiro(app) {
    casca(app, 'conselheiro', '');
    const lst = await API.pegar('/laboratorio');
    const TEMAS = lst.indicadores.map((i) => [i.codigo, i.nome]);
    $('#conteudo').innerHTML = `${topo('Conselheiro IA ', 'Converse para decidir: diagnóstico, onde agir primeiro, simulações "e se", opções de ação com custo e prazo, o que já funcionou e metas realistas. Ele lembra da cidade e do tema.', '<button class="btn fantasma sm" id="nova">Nova conversa</button>')}
      <div class="chat-layout"><aside class="chat-lado revelar">
        <span class="rotulo">Assunto da conversa</span>
        <label class="lf"><span>Cidade</span><select class="seletor" id="cCid"><option value="">Todas</option>${lst.municipios.map((m) => `<option>${esc(m.nome)}</option>`).join('')}</select></label>
        <label class="lf"><span>Tema</span><select class="seletor" id="cTema"><option value="">Qualquer</option>${TEMAS.map(([c, n]) => `<option value="${c}">${esc(n)}</option>`).join('')}</select></label>
        <span class="rotulo" style="margin-top:14px">Perguntas que ajudam a decidir</span>
        ${[['', 'Onde devo agir primeiro?'], ['', 'E se melhorar 10%?'], ['', 'Que ações melhoram isso?'], ['', 'O que funcionou nas ações já feitas?'], ['', 'Quais os riscos dessa cidade?'], ['', 'Qual meta realista para essa cidade?']].map(([e, q]) => `<button class="modelo curto" data-q="${esc(q)}"><span>${e}</span><b>${esc(q)}</b></button>`).join('')}
        <p class="dica-lado">As simulações comparam os valores com as metas aprovadas. Os efeitos das ações são faixas de referência: confirme com a equipe técnica.</p></aside>
        <div class="cartao chat-area" id="chatArea"></div></div>`;
    const q = sessionStorage.getItem('eco.pergunta'); sessionStorage.removeItem('eco.pergunta');
    const sincronizar = (c) => { if ($('#cCid')) $('#cCid').value = c.cidade || ''; if ($('#cTema')) $('#cTema').value = c.codigo || ''; };
    const c = Chat.pagina($('#chatArea'), { placeholder: 'Ex.: E se as perdas de água de Guarulhos caírem para 20%?', aoContexto: sincronizar, pergunta: q });
    $('#cCid').onchange = (e) => c.definirContexto({ cidade: e.target.value || null });
    $('#cTema').onchange = (e) => c.definirContexto({ codigo: e.target.value || null });
    $$('[data-q]').forEach((b) => (b.onclick = () => {
      const cid = $('#cCid').value; let t = b.dataset.q;
      if (cid) t = t.replace('dessa cidade', cid).replace('essa cidade', cid).replace('agir primeiro?', `agir primeiro em ${cid}?`);
      c.enviar(t);
    }));
    $('#nova').onclick = () => c.limpar();
    revelar($('#conteudo'));
  }

  // ============================================================== SIMULADOR DE METAS (gestor)
  let simCid = null;
  async function simulador(app) {
    casca(app, 'simulador', esqueleto());
    const ex = await API.pegar('/explorar');
    simCid ||= API.usuario.municipio || ex.municipios[0].id_municipio;
    const naMeta = (v, meta, sentido) => (sentido === 'MAIOR_MELHOR' ? v >= meta : v <= meta);
    const falta = (v, meta, sentido) => Math.max(0, sentido === 'MAIOR_MELHOR' ? ((meta - v) / meta) * 100 : ((v - meta) / meta) * 100);
    const lugar = (cod, v, sentido) => ex.serie.filter((s) => s.c === cod && s.p === ex.mes && s.m !== Number(simCid)).filter((s) => (sentido === 'MAIOR_MELHOR' ? s.v > v : s.v < v)).length + 1;
    const desenhar = () => {
      const atual = Object.fromEntries(ex.indicadores.map((i) => [i.codigo, ex.serie.find((s) => s.c === i.codigo && s.m === Number(simCid) && s.p === ex.mes)?.v]));
      $('#conteudo').innerHTML = `${topo('Simulador de metas', 'Mexa nos controles e veja, na hora, quantas metas a cidade passaria a cumprir e em que lugar ficaria entre as 8 cidades em cada número.',
        `<select class="seletor claro" id="sCid">${ex.municipios.map((m) => `<option value="${m.id_municipio}" ${m.id_municipio === Number(simCid) ? 'selected' : ''}>${esc(m.nome)}</option>`).join('')}</select>`)}
        <div class="grade g-hero inv"><div class="cartao revelar"><span class="rotulo">Valores do cenário (${mesTxt(ex.mes)} → meta)</span><div class="sim-ctl">${ex.indicadores.map((i) => {
          const v = atual[i.codigo]; const lo = Math.min(v, i.meta) * 0.5; const hi = Math.max(v, i.meta) * 1.3; const passo = (hi - lo) / 200;
          return `<label class="sim-l t-${Painel.AREAS[Object.keys(Painel.AREAS).find((k) => Painel.AREAS[k].servico === i.servico)].cor}"><span class="sl-n">${Painel.icoArea(i.servico)} ${esc(i.simples)}<small>hoje ${num(v, casasDe(v))} · meta ${num(i.meta, casasDe(i.meta))} ${esc(i.unidade)}</small></span>
            <input type="range" data-c="${i.codigo}" min="${lo}" max="${hi}" step="any" value="${v}"><b id="sv-${i.codigo}"></b><em id="ss-${i.codigo}"></em></label>`; }).join('')}</div>
          <div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:14px"><button class="btn fantasma sm" id="zerar">Voltar aos valores de hoje</button><button class="btn sm" id="tudoMeta">Colocar tudo na meta</button></div></div>
          <div class="cartao sim-res revelar" id="simRes"></div></div>`;
      const calc = () => {
        const val = {}; $$('.sim-l input').forEach((i) => { val[i.dataset.c] = Number(i.value); });
        let metas = 0, metasHoje = 0, subiu = 0; const mud = [];
        ex.indicadores.forEach((i) => { const v = val[i.codigo], v0 = atual[i.codigo]; const ok = naMeta(v, i.meta, i.sentido); if (ok) metas++; if (naMeta(v0, i.meta, i.sentido)) metasHoje++;
          const l = lugar(i.codigo, v, i.sentido), l0 = lugar(i.codigo, v0, i.sentido); if (l < l0) subiu++;
          if (Math.abs(v - v0) / (v0 || 1) > 0.005) mud.push(`<li><b>${esc(i.simples)}</b>: ${num(v0, casasDe(v0))} → ${num(v, casasDe(v))} ${esc(i.unidade)} · ${l0}º → ${l}º lugar</li>`);
          $(`#sv-${i.codigo}`).textContent = num(v, casasDe(v)); const e = $(`#ss-${i.codigo}`); e.textContent = ok ? '✓ na meta' : `falta ${num(falta(v, i.meta, i.sentido), 0)}%`; e.className = ok ? 'ok' : falta(v, i.meta, i.sentido) <= 15 ? 'med' : 'ruim'; });
        $('#simRes').innerHTML = `<span class="rotulo">Resultado do cenário</span>
          <div class="sim-grande"><div><small>Metas cumpridas</small><b>${metasHoje} → <span>${metas}</span></b><small>de 8</small></div><div><small>Números em que sobe no ranking</small><b><span>${subiu}</span></b><small>de 8</small></div></div>
          ${mud.length ? `<ul class="sim-mud">${mud.join('')}</ul>` : '<p class="def">Mexa em um controle para ver o efeito.</p>'}
          <button class="btn verde" id="perg" style="width:100%;margin-top:14px">Perguntar ao conselheiro como chegar lá →</button>`;
        $('#perg').onclick = () => { const mud = ex.indicadores.filter((i) => Math.abs(val[i.codigo] - atual[i.codigo]) / atual[i.codigo] > 0.02); const nomeC = ex.municipios.find((m) => m.id_municipio === Number(simCid)).nome;
          sessionStorage.setItem('eco.pergunta', mud.length ? `Que ações melhoram ${mud[0].nome.toLowerCase()} em ${nomeC}?` : `Onde devo agir primeiro em ${nomeC}?`); location.hash = '#/app/conselheiro'; };
      };
      $$('.sim-l input').forEach((i) => (i.oninput = calc));
      $('#zerar').onclick = () => { $$('.sim-l input').forEach((i) => { i.value = atual[i.dataset.c]; }); calc(); };
      $('#tudoMeta').onclick = () => { $$('.sim-l input').forEach((i) => { const ind = ex.indicadores.find((k) => k.codigo === i.dataset.c); const ok = ind.sentido === 'MAIOR_MELHOR' ? atual[ind.codigo] >= ind.meta : atual[ind.codigo] <= ind.meta; if (!ok) i.value = ind.meta; }); calc(); };
      $('#sCid').onchange = (e) => { simCid = Number(e.target.value); desenhar(); };
      revelar($('#conteudo')); calc();
    };
    desenhar();
  }

  // ============================================================== AÇÕES E RESULTADOS (gestor)
  async function acoes(app) {
    casca(app, 'acoes', esqueleto());
    const [d, lst] = await Promise.all([API.pegar('/sala'), API.pegar('/laboratorio')]);
    const ST = { PLANEJADA: ['cinza', 'Planejada'], EM_EXECUCAO: ['ceu', 'Em execução'], CONCLUIDA: ['verde', 'Concluída'], CANCELADA: ['critico', 'Cancelada'] };
    const total = d.acoes.reduce((a, b) => a + Number(b.orcamento), 0);
    $('#conteudo').innerHTML = `
      ${topo('Ações e resultados ', 'Cada ação da prefeitura fica ligada ao indicador que quer melhorar. Depois, o banco compara o antes e o depois.', pode('GESTOR') ? '<button class="btn laranja" id="nova">+ Registrar ação</button>' : '')}
      <div class="grade g-4">${[['Ações registradas', d.acoes.length], ['Melhoraram o indicador', d.acoes.filter((a) => a.efeito === 'MELHOROU').length], ['Aguardando avaliação', d.acoes.filter((a) => a.efeito === 'AGUARDANDO_AVALIACAO').length]].map(([t, v], i) => `<div class="cartao kpi revelar" style="--atraso:${i * 0.05}s"><small>${t}</small><b data-contar="${v}">0</b></div>`).join('')}
        <div class="cartao kpi revelar" style="--atraso:.15s"><small>Investimento total</small><b>R$ ${num(total / 1e6, 1)} mi</b></div></div>
      <div class="grade g-2" style="margin-top:20px">${d.acoes.map((a, i) => `<article class="cartao acao-c revelar" style="--atraso:${(i % 2) * 0.08}s">
        <header><span class="chip ${ST[a.status]?.[0]}"><i></i>${ST[a.status]?.[1] || a.status}</span><span class="chip cinza">${esc(a.municipio)}</span></header>
        <h3>${esc(a.titulo)}</h3><p>${esc(a.descricao)}</p>
        <div class="ac-info"><span>Indicador: <b>${esc(a.indicador_nome)}</b></span><span>Orçamento: <b>R$ ${num(a.orcamento / 1e6, 1)} mi</b></span><span>Prazo: <b>${mesTxt(String(a.data_inicio).slice(0, 7))} a ${mesTxt(String(a.data_fim_prevista).slice(0, 7))}</b></span></div>
        ${a.valor_antes != null ? `<div class="antes-depois"><div><small>Antes</small><b>${num(a.valor_antes, casasDe(a.valor_antes))}</b></div><span class="seta ${a.efeito === 'MELHOROU' ? 'ok' : 'ruim'}">→</span><div><small>Depois</small><b>${num(a.valor_depois, casasDe(a.valor_depois))}</b></div><span class="chip ${a.efeito === 'MELHOROU' ? 'verde' : 'critico'}">${a.efeito === 'MELHOROU' ? 'melhorou' : 'piorou'} ${num(Math.abs(a.variacao_pct), 1)}%</span></div>`
          : `<div class="antes-depois vazio">Ainda sem avaliação.${pode('GESTOR') && a.status !== 'PLANEJADA' ? ` <button class="link-btn" data-av="${a.id_acao}">Registrar resultado</button>` : ''}</div>`}
        <button class="link-btn" data-sim="${esc(`Que ações melhoram ${a.indicador_nome.toLowerCase()} em ${a.municipio}?`)}">Perguntar ao conselheiro →</button></article>`).join('')}</div>`;
    revelar($('#conteudo'));
    $$('[data-sim]').forEach((b) => (b.onclick = () => { sessionStorage.setItem('eco.pergunta', b.dataset.sim); location.hash = '#/app/conselheiro'; }));
    const recarregar = () => { API.limpar('/sala'); acoes(app); };
    $$('[data-av]').forEach((b) => (b.onclick = async () => {
      try { await API.post(`/acoes/${b.dataset.av}/resultado`, { data_avaliacao: new Date().toISOString().slice(0, 10), observacao: 'Avaliação registrada pelo painel.' }); toast('Resultado calculado pelo banco', 'ok'); recarregar(); } catch (e) { toast(e.message, 'erro'); }
    }));
    $('#nova')?.addEventListener('click', () => {
      const g = UI.gaveta(`<span class="chip laranja"><i></i>Nova ação</span><h2>Registrar ação</h2><p style="color:var(--tinta-2);margin-bottom:18px">Ligue a ação ao indicador que ela quer melhorar. Quando ela terminar, registre o resultado: o banco compara antes e depois.</p>
        <form id="fa" novalidate><div id="erro"></div>
        <div class="campo"><label>Título</label><input id="at" maxlength="150" placeholder="Ex.: Caça-vazamentos com sensores acústicos"></div>
        <div class="campo"><label>Descrição</label><textarea id="ad" placeholder="O que será feito, onde e por quem"></textarea></div>
        <div class="linha2"><div class="campo"><label>Cidade</label><select id="am">${lst.municipios.map((m) => `<option value="${m.id_municipio}">${esc(m.nome)}</option>`).join('')}</select></div>
          <div class="campo"><label>Indicador-alvo</label><select id="ai">${lst.indicadores.map((i) => `<option value="${i.id_indicador}">${esc(i.nome)}</option>`).join('')}</select></div></div>
        <div class="linha2"><div class="campo"><label>Início</label><input type="date" id="a1"></div><div class="campo"><label>Fim previsto</label><input type="date" id="a2"></div></div>
        <div class="campo"><label>Orçamento (R$)</label><input type="number" id="ao" min="0" step="1000"></div>
        <button class="btn laranja">Registrar ação</button></form>`);
      $('#fa', g.el).onsubmit = async (e) => {
        e.preventDefault();
        try { await API.post('/acoes', { titulo: $('#at', g.el).value, descricao: $('#ad', g.el).value, id_municipio: Number($('#am', g.el).value), id_indicador_alvo: Number($('#ai', g.el).value), data_inicio: $('#a1', g.el).value, data_fim_prevista: $('#a2', g.el).value, orcamento: Number($('#ao', g.el).value || 0) }); toast('Ação registrada', 'ok'); g.fechar(); recarregar(); }
        catch (err) { $('#erro', g.el).innerHTML = `<div class="aviso">${esc(err.message)}</div>`; }
      };
    });
  }

  // ============================================================== ANÁLISES DOS ANALISTAS
  async function analises(app) {
    casca(app, 'analises', esqueleto());
    const [pub, meu, base] = await Promise.all([API.pegar('/publicas/analises'), pode('ANALISTA') ? API.pegar('/analises') : null, API.pegar('/cidadao')]);
    let aba = 'pub';
    const conf = { ALTA: 'verde', MEDIA: 'ceu', BAIXA: 'laranja' };
    $('#conteudo').innerHTML = `
      ${topo('Análises de especialistas ', 'Analistas com vínculo comprovado explicam o que os números mostram. Cada análise é revisada por outro especialista antes de ser publicada.',
        pode('ANALISTA') ? '<button class="btn verde" id="nova">+ Nova análise</button>' : '')}
      ${meu ? `<div class="abas" id="abas"><button data-a="pub" class="ativo">Publicadas<span class="n">${pub.length}</span></button><button data-a="minhas">Minhas<span class="n">${meu.minhas.length}</span></button><button data-a="fila">Para revisar<span class="n">${meu.fila_revisao.length}</span></button></div>` : ''}
      <div id="lista" style="margin-top:22px"></div>`;
    const cartaoPub = (a, i) => `<button class="cartao hover analise-c revelar tilt" style="--atraso:${(i % 3) * 0.08}s" data-pub="${a.id_analise_pub}">
      <div style="display:flex;gap:8px;flex-wrap:wrap"><span class="chip ${SERV[a.servico]?.classe || ''}"><i></i>${esc(a.servico)}</span><span class="chip ${conf[a.nivel_confianca]}">confiança ${esc(String(a.nivel_confianca).toLowerCase())}</span></div>
      <h3>${esc(a.titulo)}</h3><p>${esc(a.resumo)}</p>
      <div style="font-size:13px;color:var(--tinta-3)">${esc(a.municipios)} · ${mesTxt(a.de)} a ${mesTxt(a.ate)} · ${num(a.pct_base_oficial, 0)}% base oficial</div>
      <div class="autor"><span class="ini" style="background:${['#1D5FA8', '#2F8F3F', '#E8892B', '#4FB3E3'][a.autor.length % 4]}">${iniciais(a.autor)}</span><div><b>${esc(a.autor)}</b><div style="font-size:12px;color:var(--tinta-3)">revisada por ${esc(a.revisado_por || '—')} · ${a.comentarios}</div></div></div></button>`;
    const desenhar = () => {
      let html = '';
      if (aba === 'pub') html = pub.length ? `<div class="feed">${pub.map(cartaoPub).join('')}</div>` : '<div class="cartao">Ainda não há análises publicadas.</div>';
      if (aba === 'minhas') html = meu.minhas.length ? `<div class="cartao rolar-x"><table class="tabela"><thead><tr><th>Título</th><th>Status</th><th>Criada</th><th></th></tr></thead><tbody>${meu.minhas.map((a) => `<tr><td><b>${esc(a.titulo)}</b>${a.parecer_revisao ? `<div style="font-size:13px;color:var(--tinta-2)">Parecer: ${esc(a.parecer_revisao)}</div>` : ''}</td>
          <td><span class="chip ${{ PUBLICADA: 'verde', EM_REVISAO: 'ceu', DEVOLVIDA: 'laranja', RASCUNHO: 'cinza' }[a.status]}">${esc(a.status.replace('_', ' ').toLowerCase())}</span></td><td>${esc(a.criada_em)}</td>
          <td>${['RASCUNHO', 'DEVOLVIDA'].includes(a.status) ? `<button class="btn sm" data-enviar="${a.id_analise_pub}">Enviar p/ revisão</button>` : ''}</td></tr>`).join('')}</tbody></table></div>` : '<div class="cartao">Você ainda não escreveu análises. Clique em <b>+ Nova análise</b>.</div>';
      if (aba === 'fila') html = meu.fila_revisao.length ? `<div class="feed">${meu.fila_revisao.map((a, i) => `<button class="cartao hover analise-c revelar" style="--atraso:${i * 0.06}s" data-rev="${a.id_analise_pub}">
          <span class="chip ceu"><i></i>aguardando há ${a.dias_na_fila} dias</span><h3>${esc(a.titulo)}</h3><p>${esc(a.resumo)}</p><div style="font-size:13px;color:var(--tinta-3)">por ${esc(a.autor)} · ${esc(a.servico)}</div></button>`).join('')}</div>` : '<div class="cartao">Nada para revisar agora. </div>';
      $('#lista').innerHTML = html; revelar($('#lista'));
      $$('[data-pub]').forEach((b) => (b.onclick = () => abrirPublicada(b.dataset.pub)));
      $$('[data-rev]').forEach((b) => (b.onclick = () => abrirRevisao(b.dataset.rev)));
      $$('[data-enviar]').forEach((b) => (b.onclick = async () => { try { await API.post(`/analises/${b.dataset.enviar}/enviar`); toast('Enviada para revisão!', 'ok'); API.limpar('/analises'); API.limpar('/publicas'); analises(app); } catch (e) { toast(e.message, 'erro'); } }));
    };
    $$('#abas button').forEach((b) => (b.onclick = () => { aba = b.dataset.a; $$('#abas button').forEach((x) => x.classList.toggle('ativo', x === b)); desenhar(); }));
    $('#nova')?.addEventListener('click', () => novaAnalise(base, () => { API.limpar('/analises'); analises(app); }));
    revelar($('#conteudo')); desenhar();
  }

  async function abrirPublicada(id) {
    const g = UI.gaveta('<div class="esq" style="height:400px;margin-top:60px"></div>');
    try {
      const a = await API.get(`/publicas/analises/${id}`);
      g.el.innerHTML = `<button class="fechar" aria-label="Fechar">×</button><span class="chip ${SERV[a.servico]?.classe || ''}"><i></i>${esc(a.servico)}</span>
        <h2>${esc(a.titulo)}</h2><p style="color:var(--tinta-2);font-size:17px;margin-bottom:18px">${esc(a.resumo)}</p>
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:22px"><span class="chip cinza">${a.municipios.map((m) => esc(m.nome)).join(', ')}</span><span class="chip cinza">${mesTxt(a.de)} a ${mesTxt(a.ate)}</span><span class="chip verde">${num(a.pct_base_oficial, 0)}% base oficial</span><span class="chip cinza">versão ${a.versao}</span></div>
        <div class="cartao texto-longo">${UI.paragrafos(a.conteudo)}</div>
        ${a.evidencias.length ? `<h3 style="margin:24px 0 10px;color:var(--navy)">Evidências</h3><div class="grade">${a.evidencias.map((e) => `<div class="cartao" style="padding:16px"><span class="chip cinza">${esc(e.tipo)}</span> ${e.indicador ? `<span class="chip">${esc(e.indicador)}</span>` : ''} ${e.municipio ? `<span class="chip cinza">${esc(e.municipio)}</span>` : ''}<p style="margin-top:8px">${esc(e.descricao)}</p>${e.url ? `<a href="${esc(e.url)}" target="_blank" rel="noopener">abrir fonte ↗</a>` : ''}</div>`).join('')}</div>` : ''}
        <p style="margin-top:18px;color:var(--tinta-2);font-size:14px">Escrita por <b>${esc(a.autor)}</b> · revisada por <b>${esc(a.revisor || '—')}</b> · publicada em ${esc(a.publicada_em)}</p>
        <h3 style="margin:26px 0 6px;color:var(--navy)">Comentários (${a.comentarios.length})</h3>
        <div>${a.comentarios.map((c) => `<div class="comentario"><span class="ini">${iniciais(c.autor)}</span><div><b>${esc(c.autor)}</b> <small>${esc(c.criado_em)}</small><p>${esc(c.texto)}</p></div></div>`).join('') || '<p style="color:var(--tinta-3)">Seja o primeiro a comentar.</p>'}</div>
        ${pode('ANALISTA') ? `<form id="fcom" style="margin-top:14px;display:flex;gap:10px"><input class="seletor" style="flex:1;border-radius:14px" id="txcom" placeholder="Escreva um comentário técnico…"><button class="btn sm">Enviar</button></form>` : ''}`;
      g.el.querySelector('.fechar').onclick = g.fechar;
      $('#fcom', g.el)?.addEventListener('submit', async (e) => {
        e.preventDefault();
        try { await API.post(`/analises/${id}/comentarios`, { texto: $('#txcom', g.el).value }); toast('Comentário publicado', 'ok'); API.limpar('/publicas'); g.fechar(); abrirPublicada(id); } catch (err) { toast(err.message, 'erro'); }
      });
    } catch (e) { g.fechar(); toast(e.message, 'erro'); }
  }

  async function abrirRevisao(id) {
    const g = UI.gaveta('<div class="esq" style="height:400px;margin-top:60px"></div>');
    try {
      const a = await API.get(`/analises/${id}`);
      g.el.innerHTML = `<button class="fechar">×</button><span class="chip ceu"><i></i>Revisão por pares</span><h2>${esc(a.titulo)}</h2><p style="color:var(--tinta-2);margin-bottom:16px">por ${esc(a.autor)} · ${esc(a.servico)}</p>
        <div class="cartao texto-longo">${UI.paragrafos(a.conteudo)}</div>
        <form id="frev" class="cartao" style="margin-top:20px"><span class="rotulo">Seu parecer</span><div class="campo"><textarea id="par" placeholder="Mínimo de 20 caracteres: os números conferem? A conclusão é coerente?"></textarea></div>
          <div style="display:flex;gap:10px;flex-wrap:wrap"><button class="btn verde" data-d="PUBLICADA">Publicar</button><button class="btn laranja" data-d="DEVOLVIDA">Devolver ao autor</button></div></form>`;
      g.el.querySelector('.fechar').onclick = g.fechar;
      $$('#frev [data-d]', g.el).forEach((b) => (b.onclick = async (e) => {
        e.preventDefault();
        try { await API.post(`/analises/${id}/revisao`, { decisao: b.dataset.d, parecer: $('#par', g.el).value }); toast(b.dataset.d === 'PUBLICADA' ? 'Análise publicada!' : 'Devolvida ao autor', 'ok'); API.limpar('/analises'); API.limpar('/publicas'); g.fechar(); location.hash = '#/app/analises'; Router.ir(); } catch (err) { toast(err.message, 'erro'); }
      }));
    } catch (e) { g.fechar(); toast(e.message, 'erro'); }
  }

  function novaAnalise(base, aoSalvar, pre = {}) {
    const ult = base.ultimoMes;
    const g = UI.gaveta(`<span class="chip verde"><i></i>Nova análise</span><h2>Compartilhe o que os dados mostram</h2>
      <p style="color:var(--tinta-2);margin-bottom:20px">Fica como rascunho até você enviar para revisão. Outro especialista revisa antes de publicar.</p>
      <form id="fan" novalidate><div id="erro"></div>
        <div class="campo"><label for="t">Título</label><input id="t" maxlength="150" placeholder="Ex.: Reciclagem em Sorocaba cresce, mas ainda longe da meta" value="${esc(pre.titulo || '')}"></div>
        <div class="campo"><label for="r">Resumo <small>1 ou 2 frases</small></label><input id="r" maxlength="300" value="${esc(pre.resumo || '')}"></div>
        <div class="linha2"><div class="campo"><label for="s">Área</label><select id="s">${base.servicos.map((s) => `<option value="${s.id_servico}" ${pre.servico === s.nome ? 'selected' : ''}>${esc(s.nome)}</option>`).join('')}</select></div>
          <div class="campo"><label>Período</label><div style="display:flex;gap:8px"><input type="month" id="de" value="${pre.de || `${ult.slice(0, 4) - 1}-${ult.slice(5)}`}"><input type="month" id="ate" value="${pre.ate || ult}"></div></div></div>
        <div class="campo"><label>Cidades analisadas</label><div style="display:flex;flex-wrap:wrap;gap:8px" id="cids">${base.municipios.map((m) => `<label class="chip cinza" style="cursor:pointer"><input type="checkbox" value="${m.id_municipio}" style="accent-color:var(--azul)" ${(pre.municipios || []).includes(m.id_municipio) ? 'checked' : ''}> ${esc(m.nome)}</label>`).join('')}</div></div>
        <div class="campo"><label for="c">Análise <small>use os números do painel e diga se são oficiais ou estimados</small></label><textarea id="c" style="min-height:260px">${esc(pre.conteudo || '')}</textarea></div>
        <div class="campo"><label>Evidência <small>opcional</small></label><div class="linha2"><select id="ei"><option value="">Indicador…</option>${base.indicadores.map((i) => `<option value="${i.codigo}" ${pre.evidencias?.[0]?.codigo_indicador === i.codigo ? 'selected' : ''}>${esc(i.codigo)} · ${esc(i.nome)}</option>`).join('')}</select><input id="ed" placeholder="O que esse dado comprova?" value="${esc(pre.evidencias?.[0]?.descricao || '')}"></div></div>
        <div style="display:flex;gap:10px;flex-wrap:wrap"><button class="btn fantasma" data-acao="salvar">Salvar rascunho</button><button class="btn verde" data-acao="enviar">Salvar e enviar para revisão</button></div></form>`);
    $$('#fan [data-acao]', g.el).forEach((b) => (b.onclick = async (e) => {
      e.preventDefault();
      const cids = $$('#cids input:checked', g.el).map((i) => Number(i.value));
      const corpo = { titulo: $('#t', g.el).value.trim(), resumo: $('#r', g.el).value.trim(), conteudo: $('#c', g.el).value.trim(), id_servico: Number($('#s', g.el).value),
        periodo_inicio: `${$('#de', g.el).value}-01`, periodo_fim: `${$('#ate', g.el).value}-01`, municipios: cids,
        evidencias: $('#ei', g.el).value && $('#ed', g.el).value.trim() ? [{ tipo: 'INDICADOR', codigo_indicador: $('#ei', g.el).value, id_municipio: cids[0] ?? null, descricao: $('#ed', g.el).value.trim() }] : [] };
      const erro = !corpo.titulo ? 'Dê um título.' : !corpo.resumo ? 'Escreva um resumo.' : corpo.conteudo.length < 80 ? 'A análise precisa de pelo menos 80 caracteres.' : !cids.length ? 'Escolha pelo menos uma cidade.' : '';
      if (erro) { $('#erro', g.el).innerHTML = `<div class="aviso">${erro}</div>`; return; }
      try {
        const r = await API.post('/analises', corpo);
        if (b.dataset.acao === 'enviar') await API.post(`/analises/${r.id_analise_pub}/enviar`);
        toast(b.dataset.acao === 'enviar' ? 'Enviada para revisão!' : 'Rascunho salvo', 'ok'); g.fechar(); aoSalvar();
      } catch (err) { $('#erro', g.el).innerHTML = `<div class="aviso">${esc(err.message)}</div>`; }
    }));
  }

  // ============================================================== METAS
  async function metas(app) {
    casca(app, 'metas', esqueleto());
    const [m, base] = await Promise.all([API.pegar('/metas'), API.pegar('/cidadao')]);
    const COR = { PROPOSTA: 'ceu', PARECER_EMITIDO: 'laranja', APROVADA: 'verde', REJEITADA: 'critico', SUBSTITUIDA: 'cinza' };
    const NOME = { PROPOSTA: 'aguardando parecer', PARECER_EMITIDO: 'aguardando aprovação', APROVADA: 'aprovada', REJEITADA: 'rejeitada', SUBSTITUIDA: 'substituída' };
    const cs = (v) => (Number(v) < 20 ? 2 : 0);
    const mesAno = (d) => (d ? mesTxt(String(d).slice(0, 7)) : '—');
    const variacao = (x) => (x.linha_base ? ((Number(x.valor) - Number(x.linha_base)) / Number(x.linha_base)) * 100 : null);
    $('#conteudo').innerHTML = `
      ${topo('Metas ', 'Cada meta diz <b>o que</b> queremos alcançar, <b>até quando</b> e <b>como</b> (os projetos). Fluxo com 3 pessoas: o gestor propõe → um analista dá o parecer técnico → <b>outro</b> gestor aprova. O banco impede atalhos.', pode('GESTOR') ? '<button class="btn laranja" id="nova">+ Propor meta</button>' : '')}
      <div class="grade g-4" style="margin-bottom:20px">${['PROPOSTA', 'PARECER_EMITIDO', 'APROVADA', 'REJEITADA'].map((st, i) => `<div class="cartao hover revelar" style="--atraso:${i * 0.06}s"><span class="chip ${COR[st]}"><i></i>${NOME[st]}</span><b style="display:block;font:800 34px var(--f-titulo);color:var(--navy);margin-top:10px" data-contar="${m.filter((x) => x.status === st).length}">0</b></div>`).join('')}</div>
      <div class="metas-lista">${m.map((x, k) => `<button class="meta-c cartao revelar" style="--atraso:${Math.min(k, 8) * 0.04}s" data-ver="${x.id_meta}">
          <div class="mc-topo"><span class="chip ${COR[x.status]}"><i></i>${NOME[x.status]}</span><small>${esc(x.indicador)} · ${esc(x.abrangencia)}</small></div>
          <b class="mc-frase">${esc(x.descricao || `${x.indicador}: ${x.sentido === 'MAIOR_MELHOR' ? 'pelo menos' : 'no máximo'} ${num(x.valor, cs(x.valor))} ${x.unidade}`)}</b>
          <div class="mc-nums"><span>hoje <b>${x.valor_atual != null ? num(x.valor_atual, cs(x.valor_atual)) : '—'}</b></span><span>meta <b>${num(x.valor, cs(x.valor))}</b> ${esc(x.unidade)}</span><span>prazo <b>${mesAno(x.prazo)}</b></span>
            ${x.cidades_cumprem != null ? `<span>${x.cidades_cumprem} de 8 cidades já cumprem</span>` : x.cumpre_hoje != null ? `<span class="${x.cumpre_hoje ? 't-verde' : 't-critico'}">${x.cumpre_hoje ? 'já cumpre' : 'ainda não cumpre'}</span>` : ''}</div>
          <span class="mc-ver">Ver detalhes${x.status === 'PROPOSTA' && pode('ANALISTA') ? ' e dar parecer' : x.status === 'PARECER_EMITIDO' && pode('GESTOR') ? ' e decidir' : ''} →</span></button>`).join('')}</div>`;
    revelar($('#conteudo'));
    const recarregar = () => { API.limpar('/metas'); metas(app); };

    const detalhe = (x) => {
      const v = variacao(x); const passos = String(x.como_atingir || '').split('\n').map((t) => t.trim()).filter(Boolean);
      const vals = [x.linha_base, x.valor_atual, x.valor].filter((y) => y != null).map(Number); const lo = Math.min(...vals) * 0.9, hi = Math.max(...vals) * 1.05;
      const pos = (y) => `${((Number(y) - lo) / (hi - lo || 1)) * 100}%`;
      const g = UI.gaveta(`<span class="chip ${COR[x.status]}"><i></i>${NOME[x.status]}</span>
        <h2 style="margin-top:10px">${esc(x.descricao || x.indicador)}</h2>
        <p class="md-sub">${esc(x.indicador)} (${esc(x.codigo)}) · ${esc(x.abrangencia)} · ${x.sentido === 'MAIOR_MELHOR' ? 'quanto maior, melhor' : 'quanto menor, melhor'}</p>
        <div class="md-nums"><div><small>Ponto de partida</small><b>${x.linha_base != null ? num(x.linha_base, cs(x.linha_base)) : '—'}</b><span>${esc(x.unidade)} · ${String(x.vigencia_inicio) > String(x.criada_em) ? `quando foi proposta (${mesAno(x.criada_em)})` : mesAno(x.vigencia_inicio)}</span></div>
          <div><small>Hoje</small><b>${x.valor_atual != null ? num(x.valor_atual, cs(x.valor_atual)) : '—'}</b><span>${esc(x.unidade)}${x.id_municipio ? '' : ' · média das 8 cidades'}</span></div>
          <div class="alvo"><small>Meta</small><b>${num(x.valor, cs(x.valor))}</b><span>${esc(x.unidade)}${v != null ? ` · ${v >= 0 ? '+' : ''}${num(v, 0)}% em relação ao ponto de partida` : ''}</span></div>
          <div><small>Prazo</small><b>${mesAno(x.prazo)}</b><span>começa a valer em ${mesAno(x.vigencia_inicio)}</span></div></div>
        ${x.linha_base != null && x.valor_atual != null ? `<div class="md-regua"><i class="trilho"></i>${Math.abs(Number(x.linha_base) - Number(x.valor_atual)) / (hi - lo || 1) < 0.08 ? `<em class="hoje" style="left:${pos(x.valor_atual)}"><span>partida e hoje</span></em>` : `<em style="left:${pos(x.linha_base)}" title="ponto de partida"><span>partida</span></em><em class="hoje" style="left:${pos(x.valor_atual)}"><span>hoje</span></em>`}<em class="meta" style="left:${pos(x.valor)}"><span>meta</span></em></div>` : ''}
        ${x.cidades_cumprem != null ? `<p class="md-info"><b>${x.cidades_cumprem} de 8 cidades</b> já cumprem esta meta hoje.</p>` : ''}
        <h3 class="md-t">Como vamos atingir (projetos)</h3>
        ${passos.length ? `<ol class="md-passos">${passos.map((t) => `<li>${esc(t)}</li>`).join('')}</ol>` : '<p class="md-info">O gestor não descreveu os projetos desta meta.</p>'}
        <h3 class="md-t">Por que este valor</h3><p>${esc(x.justificativa)}</p>
        <p class="md-info"><b>Referência técnica:</b> ${esc(x.referencia)}</p>
        <h3 class="md-t">Quem participou</h3>
        <ul class="md-hist"><li><b>Proposta:</b> ${esc(x.proposta_por)} · ${mesAno(x.criada_em)}</li>
          ${x.parecer_por ? `<li><b>Parecer ${x.parecer_favoravel ? 'favorável' : 'desfavorável'}:</b> ${esc(x.parecer_por)} — “${esc(x.parecer || '')}”</li>` : '<li><b>Parecer:</b> aguardando um analista da área</li>'}
          ${x.aprovada_por ? `<li><b>${x.status === 'REJEITADA' ? 'Rejeitada' : 'Aprovada'} por:</b> ${esc(x.aprovada_por)} · ${mesAno(x.decidida_em)}</li>` : ''}</ul>
        ${x.status === 'PROPOSTA' && pode('ANALISTA') ? `<form id="fp" class="cartao md-form"><h3 class="md-t" style="margin-top:0">Seu parecer técnico</h3>
            <p class="md-info">Antes de opinar, confira: o valor é realista para a cidade? O prazo é suficiente? Os projetos atacam a causa do problema? A referência técnica faz sentido?</p>
            <div class="campo"><label>Parecer (mín. 30 caracteres)</label><textarea id="tp" placeholder="Ex.: A série oficial mostra queda de 2 pontos por ano; com os projetos listados, 22% até 2028 é alcançável."></textarea></div>
            <div style="display:flex;gap:10px"><button class="btn verde" data-f="1">Favorável</button><button class="btn laranja" data-f="0">Desfavorável</button></div></form>` : ''}
        ${x.status === 'PARECER_EMITIDO' && pode('GESTOR') ? `<div class="md-acoes"><button class="btn verde" data-dec="1">Aprovar meta</button><button class="btn fantasma" data-dec="0">Rejeitar</button></div>` : ''}`);
      $$('#fp [data-f]', g.el).forEach((b) => (b.onclick = async (e) => { e.preventDefault(); try { await API.post(`/metas/${x.id_meta}/parecer`, { favoravel: b.dataset.f === '1', parecer: $('#tp', g.el).value }); toast('Parecer registrado', 'ok'); g.fechar(); recarregar(); } catch (err) { toast(err.message, 'erro'); } }));
      $$('[data-dec]', g.el).forEach((b) => (b.onclick = async () => { try { await API.post(`/metas/${x.id_meta}/decisao`, { aprovar: b.dataset.dec === '1' }); toast(b.dataset.dec === '1' ? 'Meta aprovada' : 'Meta rejeitada', 'ok'); g.fechar(); recarregar(); } catch (err) { toast(err.message, 'erro'); } }));
    };
    $$('[data-ver]').forEach((b) => (b.onclick = () => detalhe(m.find((x) => String(x.id_meta) === b.dataset.ver))));

    $('#nova')?.addEventListener('click', () => {
      const g = UI.gaveta(`<span class="chip laranja"><i></i>Nova meta</span><h2>Propor meta</h2>
        <p class="md-info">Uma boa meta é <b>específica</b> (um número e uma cidade), <b>realista</b> (veja quanto as outras cidades já conseguem), tem <b>prazo</b> e diz <b>quais projetos</b> vão levar até ela.</p>
        <form id="fm" novalidate><div id="erro"></div>
        <div class="campo"><label>Indicador</label><select id="mi">${base.indicadores.map((i) => `<option value="${i.codigo}">${esc(i.nome)} (${esc(i.unidade)})</option>`).join('')}</select></div>
        <div class="linha2"><div class="campo"><label>Cidade</label><select id="mc"><option value="">Todas as cidades</option>${base.municipios.map((c) => `<option value="${c.id_municipio}">${esc(c.nome)}</option>`).join('')}</select></div>
          <div class="campo"><label>Valor da meta</label><input id="mv" type="number" step="0.01"></div></div>
        <p class="md-info" id="hoje"></p>
        <div class="linha2"><div class="campo"><label>Começa a valer em</label><input id="md" type="month" value="${base.ultimoMes}"></div>
          <div class="campo"><label>Prazo para atingir</label><input id="mp" type="month"></div></div>
        <div class="campo"><label>A meta em uma frase</label><input id="mf" placeholder="Ex.: Reduzir de 192 para 182 litros por pessoa por dia até dez/2027"></div>
        <div class="campo"><label>Como atingir: projetos e ações (um por linha)</label><textarea id="mca" rows="5" placeholder="Ex.:&#10;Trocar hidrômetros antigos&#10;Caça-vazamento nos bairros com mais perdas"></textarea></div>
        <div class="campo"><label>Por que este valor (justificativa)</label><textarea id="mj"></textarea></div><div class="campo"><label>Referência técnica</label><input id="mr" placeholder="Ex.: SNIS, Portaria MDR 490/2021, ODS 6.4"></div>
        <button class="btn laranja">Enviar proposta</button></form>`);
      const mostrarHoje = () => { const cod = $('#mi', g.el).value; const cid = Number($('#mc', g.el).value) || null; const ind = base.indicadores.find((i) => i.codigo === cod);
        const vs = (base.serie12 || []).filter((x) => x.c === cod && x.p === base.ultimoMes && (!cid || x.m === cid)).map((x) => Number(x.v));
        $('#hoje', g.el).innerHTML = vs.length ? `Hoje (${esc(mesTxt(base.ultimoMes))}): <b>${num(vs.reduce((a, b) => a + b, 0) / vs.length, 1)} ${esc(ind?.unidade || '')}</b>${cid ? '' : ' (média das 8 cidades)'}. Use como ponto de partida.` : ''; };
      $('#mi', g.el).onchange = mostrarHoje; $('#mc', g.el).onchange = mostrarHoje; mostrarHoje();
      $('#fm', g.el).onsubmit = async (e) => {
        e.preventDefault();
        try { await API.post('/metas', { codigo_indicador: $('#mi', g.el).value, id_municipio: $('#mc', g.el).value || null, valor: $('#mv', g.el).value, vigencia_inicio: `${$('#md', g.el).value}-01`,
          prazo: $('#mp', g.el).value ? `${$('#mp', g.el).value}-01` : null, descricao: $('#mf', g.el).value, como_atingir: $('#mca', g.el).value, justificativa: $('#mj', g.el).value, referencia: $('#mr', g.el).value });
        toast('Meta proposta! Agora um analista dá o parecer.', 'ok'); g.fechar(); recarregar(); }
        catch (err) { $('#erro', g.el).innerHTML = `<div class="aviso">${esc(err.message)}</div>`; }
      };
    });
  }

  // ============================================================== ADMINISTRAÇÃO
  async function admin(app) {
    casca(app, 'admin', esqueleto());
    const [col, cad, ac] = await Promise.all([API.get('/admin/coleta'), API.get('/cadastros'), API.get('/acessos')]);
    const pend = cad.filter((c) => c.status === 'EM_ANALISE');
    const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
    const ult = col.historico[0];
    $('#conteudo').innerHTML = `
      ${topo('Administração ', 'Coleta automática dos dados, aprovação de cadastros e segurança do login.')}
      <div class="grade g-2">
        <div class="cartao revelar"><span class="rotulo">Robô de coleta das fontes oficiais</span>
          <p style="color:var(--tinta-2);font-size:14px;margin:4px 0 14px">Confere os sites dos órgãos públicos e grava no banco só o que é novo ou foi revisado. Robô <b>${col.automatica ? `ligado — a cada ${col.intervalo_horas} h` : 'desligado'}</b> · modo <b>${esc(col.modo)}</b>${col.proxima ? ` · próxima conferência ${new Date(col.proxima).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}` : ''}.</p>
          <div class="rolar-x"><table class="tabela"><thead><tr><th>Fonte</th><th>Última conferência</th><th>O que o site publicou</th></tr></thead><tbody>
          ${col.fontes.map((f) => `<tr><td><b style="font-size:14px">${esc(f.fonte)}</b><div style="font-size:12px;color:var(--tinta-3)">publica: ${esc(String(f.frequencia).toLowerCase())}${f.ultima_novidade ? ` · última novidade ${esc(f.ultima_novidade)}` : ''}</div></td>
            <td>${f.verificado_em ? `<span class="chip ${f.status === 'FALHA' ? 'critico' : f.status === 'OK' ? 'verde' : 'cinza'}">${esc(f.status === 'OK' ? 'atualizou' : f.status === 'FALHA' ? 'falhou' : 'sem novidade')}</span><div style="font-size:12px;color:var(--tinta-3);margin-top:4px">${esc(f.verificado_em)}</div>` : '<span class="chip cinza">nunca</span>'}</td>
            <td style="font-size:12px;color:var(--tinta-2);max-width:340px">${esc(f.mensagem || '—')}</td></tr>`).join('')}</tbody></table></div>
          <form id="fcol" style="display:flex;gap:12px;margin-top:16px;flex-wrap:wrap;align-items:center"><button class="btn verde sm" id="bcol">▶ Conferir as fontes agora</button>
            <label style="font-size:13px;display:flex;gap:6px;align-items:center"><input type="checkbox" id="forcar"> baixar tudo de novo</label></form>
          <div id="exec" style="margin-top:16px">${col.atual ? execucao(col.atual) : ult ? execucao(ult) : '<p style="color:var(--tinta-3)">Nenhuma execução desde que o servidor ligou.</p>'}</div></div>
        <div class="cartao revelar" style="--atraso:.1s"><span class="rotulo">De onde vem cada mês</span>
          ${col.meses.map((m, i) => { const t = m.oficiais + m.derivados + m.estimados || 1; return `<div style="margin-bottom:14px"><div style="display:flex;justify-content:space-between;font-size:14px;font-weight:600"><span>${mesTxt(m.mes)}</span><span style="color:var(--tinta-3)">${t} valores</span></div>
            <div style="display:flex;height:12px;border-radius:8px;overflow:hidden;margin-top:6px;background:#EEF2F7"><i class="cresce" style="--atraso:${i * 0.08}s;width:${(m.oficiais / t) * 100}%;background:var(--verde)"></i><i class="cresce" style="width:${(m.derivados / t) * 100}%;background:var(--azul)"></i><i class="cresce" style="width:${(m.estimados / t) * 100}%;background:var(--laranja)"></i></div></div>`; }).join('')}
          <div style="display:flex;gap:14px;font-size:13px;color:var(--tinta-2);flex-wrap:wrap"><span><b style="color:var(--verde)">■</b> oficial do mês</span><span><b style="color:var(--azul)">■</b> oficial do ano</span><span><b style="color:var(--laranja)">■</b> estimado</span></div>
          <span class="rotulo" style="margin-top:20px">Últimos lotes de carga</span><div class="rolar-x"><table class="tabela"><tbody>${col.lotes.slice(0, 6).map((l) => `<tr><td>#${l.id_lote}</td><td>${esc(l.fonte)}<div style="font-size:12px;color:var(--tinta-3)">${esc(l.mensagem || '')}</div></td><td><span class="chip ${l.status === 'SUCESSO' ? 'verde' : l.status === 'FALHA' ? 'critico' : 'laranja'}">${esc(l.status.toLowerCase())}</span></td></tr>`).join('')}</tbody></table></div></div>
      </div>
      <div class="cartao revelar" style="margin-top:20px"><div style="display:flex;justify-content:space-between;flex-wrap:wrap;gap:10px"><span class="rotulo">Cadastros de analistas e gestores</span><span class="chip ${pend.length ? 'laranja' : 'verde'}">${pend.length} aguardando</span></div>
        <div class="rolar-x"><table class="tabela"><thead><tr><th>Pessoa</th><th>Perfil</th><th>Órgão e cargo</th><th>Documentos</th><th>Status</th><th></th></tr></thead><tbody>
        ${cad.map((c) => `<tr><td><b>${esc(c.nome)}</b><div style="font-size:12px;color:var(--tinta-3)">${esc(c.email_institucional)}${c.cidade_atuacao ? ` · ${esc(c.cidade_atuacao)}` : ''}</div></td><td><span class="chip ${c.perfil_pedido === 'ANALISTA' ? 'ceu' : 'laranja'}">${esc(c.perfil_pedido.toLowerCase())}</span></td>
          <td style="font-size:13px">${esc(c.orgao)}<br>${esc(c.cargo)}</td><td style="font-size:13px">${esc(c.registro_conselho || c.portaria_nomeacao || '—')}${c.documento_url ? `<br><a href="${esc(c.documento_url)}" target="_blank" rel="noopener">documento ↗</a>` : ''}</td>
          <td><span class="chip ${{ APROVADO: 'verde', EM_ANALISE: 'laranja', RECUSADO: 'critico', SUSPENSO: 'cinza' }[c.status]}">${esc(c.status.replace('_', ' ').toLowerCase())}</span>${c.status === 'EM_ANALISE' ? `<div style="font-size:12px;color:var(--tinta-3)">há ${c.dias_aguardando} dias</div>` : ''}</td>
          <td>${c.status === 'EM_ANALISE' ? `<button class="btn verde sm" data-ap="${c.id_usuario}">Aprovar</button> <button class="btn fantasma sm" data-rc="${c.id_usuario}">Recusar</button>` : ''}</td></tr>`).join('')}</tbody></table></div></div>
      <div class="grade g-2" style="margin-top:20px"><div class="cartao revelar"><span class="rotulo">Tentativas de login</span><div style="display:flex;gap:8px;flex-wrap:wrap">${ac.resumo.map((r) => `<span class="chip ${r.resultado === 'SUCESSO' ? 'verde' : 'laranja'}">${esc(r.resultado.toLowerCase().replace(/_/g, ' '))}: <b>${r.tentativas}</b></span>`).join('')}</div>
        <p style="margin-top:14px;color:var(--tinta-2);font-size:14px">O banco bloqueia a conta por 15 minutos depois de 5 erros seguidos. Contas bloqueadas agora: <b>${ac.bloqueados.length}</b>.</p></div>
        <div class="cartao revelar" style="--atraso:.1s"><span class="rotulo">Últimos acessos</span><div class="rolar-x"><table class="tabela"><tbody>${ac.ultimos.slice(0, 6).map((a) => `<tr><td style="font-size:13px">${esc(a.email_tentado)}</td><td><span class="chip ${a.resultado === 'SUCESSO' ? 'verde' : 'laranja'}">${esc(a.resultado.toLowerCase().replace(/_/g, ' '))}</span></td><td style="font-size:12px;color:var(--tinta-3)">${esc(a.ocorrido_em)}</td></tr>`).join('')}</tbody></table></div></div></div>`;
    revelar($('#conteudo'));
    const acompanhar = async () => {
      const b = $('#bcol'); b.disabled = true; b.innerHTML = '<span class="gira"></span> Conferindo…';
      for (;;) {
        await new Promise((ok) => setTimeout(ok, 3000));
        if (!document.body.contains(b)) return;              // saiu da página
        const st = await API.get('/admin/coleta', { silencioso: true }).catch(() => null);
        if (!st) continue;
        if (st.atual) { $('#exec').innerHTML = execucao(st.atual); continue; }
        const r = st.historico[0];
        if (r) { $('#exec').innerHTML = execucao(r); toast(`Coleta: ${r.status.toLowerCase()} — ${r.resumo || ''}`, r.status === 'FALHA' ? 'erro' : 'ok'); }
        API.limpar(); b.disabled = false; b.textContent = '▶ Conferir as fontes agora';
        return admin(app);
      }
    };
    $('#fcol').onsubmit = async (e) => {
      e.preventDefault();
      try { await API.post('/admin/coleta', { forcar: $('#forcar').checked }); $('#exec').innerHTML = '<div class="esq" style="height:120px"></div>'; acompanhar(); }
      catch (err) { toast(err.message, 'erro'); }
    };
    if (col.rodando) acompanhar();
    const decidir = async (idU, decisao) => {
      const motivo = prompt(decisao === 'APROVADO' ? 'Motivo da aprovação (o que você conferiu?)' : 'Motivo da recusa'); if (!motivo) return;
      try { await API.patch(`/cadastros/${idU}`, { decisao, motivo, valido_ate: decisao === 'APROVADO' ? new Date(Date.now() + 365 * 864e5).toISOString().slice(0, 10) : null }); toast(decisao === 'APROVADO' ? 'Cadastro aprovado' : 'Cadastro recusado', 'ok'); admin(app); } catch (err) { toast(err.message, 'erro'); }
    };
    $$('[data-ap]').forEach((b) => (b.onclick = () => decidir(b.dataset.ap, 'APROVADO')));
    $$('[data-rc]').forEach((b) => (b.onclick = () => decidir(b.dataset.rc, 'RECUSADO')));
  }
  const execucao = (r) => `<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;flex-wrap:wrap;gap:8px"><b>${r.fim ? `Conferência de ${new Date(r.inicio).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}` : esc(r.agora || 'Começando…')} · ${esc(r.origem)}</b><span class="chip ${!r.fim ? 'ceu' : r.status === 'SUCESSO' ? 'verde' : r.status === 'FALHA' ? 'critico' : 'laranja'}">${esc(r.fim ? r.status.toLowerCase() : 'rodando')}</span></div>
    ${r.resumo ? `<p style="font-size:14px;margin-bottom:10px">${esc(r.resumo)}</p>` : ''}
    <div class="passos-coleta">${r.etapas.map((e, i) => `<div class="passo-c ${e.ok ? 'ok' : 'falha'}" style="--atraso:${i * 0.12}s"><span class="b">${e.ok ? '✓' : '!'}</span><div><b>${esc(e.nome)}</b><small>${esc(e.detalhe)}</small></div></div>`).join('')}</div>`;

  // rascunho do assistente -> formulário de nova análise já preenchido
  async function novaAnaliseDoRascunho(r) {
    const base = await API.pegar('/cidadao');
    if (!location.hash.startsWith('#/app/analises')) location.hash = '#/app/analises';
    setTimeout(() => novaAnalise(base, () => { API.limpar('/analises'); Router.ir(); }, r), 400);
  }

  return { simulador, laboratorio, assistente, riscos, sala, conselheiro, acoes, analises, metas, admin, novaAnaliseDoRascunho };
})();
