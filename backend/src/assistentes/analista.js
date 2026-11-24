// Assistente do ANALISTA: monta rascunhos de relatório, compara cidades, mostra séries e fontes de dados específicos.
const E = require('./entender');
const L = require('../linguagem');
const fontes = require('../fontes');
const copiloto = require('../copiloto_servico');
const { consulta: query } = require('../db');

const SUG = ['Relatório de reciclagem em Sorocaba nos últimos 12 meses', 'Compare as perdas de água das 8 cidades',
  'Fonte do consumo de água em Campinas', 'Evolução da energia solar em Guarulhos em 2026'];
const n = L.n;
const casas = (v) => (Math.abs(v) < 20 ? 2 : 1);

async function dados(codigos, ids, de, ate) {
  return query(`SELECT id_municipio, municipio, codigo, indicador, servico, ano_mes, ROUND(valor,4) AS valor, meta, unidade, sentido, score, atingiu_meta, origem
                FROM vw_indicador_desempenho WHERE codigo IN (?) ${ids.length ? 'AND id_municipio IN (?)' : ''} AND ano_mes BETWEEN ? AND ?
                ORDER BY municipio, codigo, periodo`, ids.length ? [codigos, ids, de, ate] : [codigos, de, ate]);
}

function estat(s) {
  const v = s.map((x) => Number(x.valor)); const a = v[0], b = v[v.length - 1];
  return { inicio: a, fim: b, var_pct: a ? ((b - a) / a) * 100 : 0, media: v.reduce((x, y) => x + y, 0) / v.length, min: Math.min(...v), max: Math.max(...v),
    meses_meta: s.filter((x) => x.atingiu_meta).length, meses: s.length, pct_oficial: Math.round((s.filter((x) => x.origem !== 'ESTIMADO').length / s.length) * 100) };
}
const melhorou = (e, sentido) => (sentido === 'MAIOR_MELHOR' ? e.var_pct > 0 : e.var_pct < 0);

// ------------------------------------------------------------- rascunho de relatório
async function relatorio(codigos, cids, per) {
  const ids = cids.map((c) => c.id_municipio);
  const linhas = await dados(codigos, ids, per.de, per.ate);
  if (!linhas.length) return { texto: 'Não encontrei dados nesse período. Tente "últimos 12 meses" ou um ano entre 2023 e 2026.', sugestoes: SUG };
  const grupos = {}; for (const l of linhas) (grupos[`${l.municipio}|${l.codigo}`] ||= []).push(l);
  const blocos = Object.values(grupos).map((s) => ({ s, u: s[s.length - 1], e: estat(s) }));
  const ind0 = blocos[0].u; const nomesInd = [...new Set(blocos.map((b) => b.u.indicador))];
  const nomesCid = [...new Set(blocos.map((b) => b.u.municipio))];
  const pctOf = Math.round(blocos.reduce((a, b) => a + b.e.pct_oficial, 0) / blocos.length);
  const ondeTxt = nomesCid.length === 1 ? `em ${nomesCid[0]}` : nomesCid.length <= 3 ? `em ${nomesCid.join(', ')}` : `nas ${nomesCid.length} cidades`;
  const servicos = [...new Set(blocos.map((b) => b.u.servico))];
  const tema = nomesInd.length === 1 ? nomesInd[0] : servicos.length === 1 ? servicos[0] : 'Panorama de sustentabilidade';
  const titulo = `${tema} ${ondeTxt} (${L.mesLongo(per.de)} a ${L.mesLongo(per.ate)})`;

  const md = [];
  const destaques = blocos.map((b) => `- **${b.u.municipio} · ${b.u.indicador}:** ${n(b.e.inicio, casas(b.e.inicio))} → **${n(b.e.fim, casas(b.e.fim))} ${b.u.unidade}** (${b.e.var_pct >= 0 ? '+' : ''}${n(b.e.var_pct, 1)}%, ${melhorou(b.e, b.u.sentido) ? 'melhora' : 'piora'}). Meta: ${n(b.u.meta, casas(b.u.meta))}. Cumpriu a meta em ${b.e.meses_meta} de ${b.e.meses} meses.`);
  const melhor = [...blocos].sort((a, b) => b.u.score - a.u.score)[0]; const pior = [...blocos].sort((a, b) => a.u.score - b.u.score)[0];
  const naMeta = blocos.filter((b) => b.u.atingiu_meta).length;
  const resumo = blocos.length === 1
    ? `${blocos[0].u.indicador} em ${blocos[0].u.municipio} ${melhorou(blocos[0].e, blocos[0].u.sentido) ? 'melhorou' : 'piorou'} ${n(Math.abs(blocos[0].e.var_pct), 1)}% no período e ${blocos[0].u.atingiu_meta ? 'está dentro' : 'segue fora'} da meta (${n(blocos[0].u.meta, casas(blocos[0].u.meta))} ${blocos[0].u.unidade}).`
    : nomesCid.length === 1
      ? `Em ${nomesCid[0]}, o ponto forte é ${melhor.u.indicador.toLowerCase()} e o ponto fraco é ${pior.u.indicador.toLowerCase()}. ${naMeta} de ${blocos.length} indicadores estão na meta no último mês.`
      : `Melhor desempenho: ${melhor.u.municipio} (${melhor.u.indicador}). Maior atenção: ${pior.u.municipio} (${pior.u.indicador}). ${naMeta} de ${blocos.length} séries estão na meta no último mês.`;

  md.push('## Resumo', resumo, '', '## O que os dados mostram', ...destaques, '');
  if (blocos.length > 1) {
    md.push('## Comparação no último mês');
    for (const cod of codigos) {
      const b = blocos.filter((x) => x.u.codigo === cod).sort((x, y) => (x.u.sentido === 'MAIOR_MELHOR' ? y.e.fim - x.e.fim : x.e.fim - y.e.fim));
      if (b.length > 1) md.push(`**${b[0].u.indicador}** (melhor → pior): ${b.map((x, i) => `${i + 1}º ${x.u.municipio} ${n(x.e.fim, casas(x.e.fim))}`).join(' · ')}`);
    }
    md.push('');
  }
  const alertas = await query(`SELECT a.titulo, a.severidade, m.nome AS municipio FROM analise_ia a JOIN municipio m USING (id_municipio) JOIN indicador i USING (id_indicador)
                               WHERE i.codigo IN (?) ${ids.length ? 'AND a.id_municipio IN (?)' : ''} AND a.status IN ('NOVA','EM_ANALISE','VALIDADA')
                               ORDER BY FIELD(a.severidade,'CRITICO','ATENCAO','INFO') LIMIT 5`, ids.length ? [codigos, ids] : [codigos]);
  if (alertas.length) md.push('## Pontos de atenção (IA)', ...alertas.map((a) => `- ${a.severidade === 'CRITICO' ? '🔴' : '🟠'} ${a.titulo}`), '');
  const acoes = await query('SELECT titulo, municipio, efeito, variacao_pct FROM vw_acoes_resultados WHERE indicador_alvo IN (?)', [codigos]);
  if (acoes.length) md.push('## Ações já registradas', ...acoes.map((a) => `- ${a.titulo} (${a.municipio}): ${a.efeito === 'AGUARDANDO_AVALIACAO' ? 'aguardando avaliação' : `${a.efeito.toLowerCase()} ${a.variacao_pct != null ? `${n(a.variacao_pct, 1)}%` : ''}`}`), '');

  // fontes do último mês de cada cidade
  const fl = new Map();
  for (const id of [...new Set(blocos.map((b) => b.u.id_municipio))]) {
    const f = await fontes.dosIndicadores(id, per.ate);
    for (const c of codigos) for (const x of f[c]?.fontes || []) if (!fl.has(x.fonte)) fl.set(x.fonte, x);
  }
  md.push('## Qualidade e fontes dos dados', `${pctOf}% dos valores do período têm base oficial (oficial ou calculado de oficial); o restante é estimativa do EcoCity e deve ser lido como tendência.`,
    ...[...fl.values()].map((f) => `- **${f.fonte}** (${f.orgao}) — ${f.frequencia.toLowerCase()} · ${f.url}`), '');
  md.push('## Sugestões para aprofundar', '- Conferir se a tendência se repete no mesmo período do ano anterior (sazonalidade).', '- Verificar se há dado oficial novo publicado pela fonte que substitua estimativas.', blocos.some((b) => !b.u.atingiu_meta) ? '- Discutir com o gestor ações para as séries fora da meta.' : '- Registrar o que explica o bom desempenho para replicar em outras cidades.');

  let conteudo = md.join('\n');
  let modelo = 'assistente-local-v1';
  if (copiloto.temIA()) {
    try {
      conteudo = await copiloto.chamarIA('Você é um analista de dados ambientais. Reescreva o rascunho em português do Brasil, em Markdown, mantendo as seções e TODOS os números exatamente como estão. Não invente dados. Deixe claro o que é estimado.', conteudo, 2200);
      modelo = copiloto.MODELO_IA;
    } catch { /* mantém o texto local */ }
  }
  const tabela = blocos.map((b) => ({ cidade: b.u.municipio, indicador: b.u.codigo, inicio: b.e.inicio, fim: b.e.fim, 'var %': Math.round(b.e.var_pct * 10) / 10, meta: Number(b.u.meta), '% oficial': b.e.pct_oficial }));
  return {
    texto: `Pronto! Montei um **rascunho de relatório** com ${blocos.length} série${blocos.length > 1 ? 's' : ''} (${per.txt}). Revise, complemente com sua interpretação e envie para revisão.`,
    rascunho: { titulo: titulo.slice(0, 150), resumo: resumo.slice(0, 300), conteudo, id_servico: null, servico: ind0.servico, de: per.de, ate: per.ate,
      municipios: [...new Set(blocos.map((b) => b.u.id_municipio))], evidencias: blocos.slice(0, 3).map((b) => ({ codigo_indicador: b.u.codigo, id_municipio: b.u.id_municipio, descricao: `${b.u.indicador} em ${b.u.municipio}: ${n(b.e.fim, casas(b.e.fim))} ${b.u.unidade} em ${L.mesLongo(per.ate)}` })), modelo },
    tabela, fontes: [...fl.values()].map((f) => ({ fonte: f.fonte, url: f.url })),
    sugestoes: ['Compare com as outras cidades', 'Quais as fontes desses dados?', 'Relatório dos últimos 24 meses'],
  };
}

// ------------------------------------------------------------- comparação entre cidades
async function comparar(codigos, cids, per) {
  const cod = codigos[0];
  const ult = await query(`SELECT municipio, ROUND(valor,3) AS valor, meta, unidade, sentido, score, origem FROM vw_indicador_desempenho WHERE codigo = ? AND ano_mes = ? ${cids.length > 1 ? 'AND id_municipio IN (?)' : ''}`,
    cids.length > 1 ? [cod, per.ate, cids.map((c) => c.id_municipio)] : [cod, per.ate]);
  const ant = await query('SELECT municipio, valor FROM vw_indicador_desempenho WHERE codigo = ? AND ano_mes = ?', [cod, E.somar(per.ate, -12)]);
  const s = ult[0]?.sentido; ult.sort((a, b) => (s === 'MAIOR_MELHOR' ? b.valor - a.valor : a.valor - b.valor));
  const [ind] = await query('SELECT nome FROM indicador WHERE codigo = ?', [cod]);
  const tabela = ult.map((u, i) => { const a = ant.find((x) => x.municipio === u.municipio); return { pos: `${i + 1}º`, cidade: u.municipio, valor: Number(u.valor), 'há 12 meses': a ? Number(a.valor) : null, 'na meta': u.score >= 100 ? 'sim' : 'não', origem: L.ORIGEM[u.origem].curto }; });
  const naMeta = ult.filter((u) => u.score >= 100).length;
  return { texto: `**${ind.nome}** em ${L.mesLongo(per.ate)} (${ult[0]?.unidade}; meta ${n(ult[0]?.meta, casas(ult[0]?.meta))}). Melhor: **${ult[0]?.municipio}**; pior: **${ult[ult.length - 1]?.municipio}**. ${naMeta} de ${ult.length} cidades estão na meta. ${ult.filter((u) => u.origem === 'ESTIMADO').length} valores são estimativas.`,
    tabela, sugestoes: [`Relatório de ${ind.nome.toLowerCase()} nas 8 cidades`, `Fonte de ${ind.nome.toLowerCase()} em ${ult[0]?.municipio}`] };
}

// ------------------------------------------------------------- fonte de um dado específico
async function fonteDe(codigos, cids, per) {
  const cid = cids[0] || (await E.todasCidades()).find((c) => c.nome === 'São Paulo');
  const f = await fontes.dosIndicadores(cid.id_municipio, per.ate);
  const txt = (codigos.length ? codigos : Object.keys(f)).map((c) => {
    const x = f[c]; const ref = x.fontes.map((y) => `  - **${y.metrica_nome}:** ${y.fonte} (${y.sigla}) · ${L.ORIGEM[y.origem]?.curto || y.origem}\n    _${y.referencia || ''}_`).join('\n');
    return `**${c}** — ${x.origemTxt}\n${ref}`;
  }).join('\n\n');
  return { texto: `Fontes em **${cid.nome}**, ${L.mesLongo(per.ate)}:\n\n${txt}`, fontes: Object.values(f).flatMap((x) => x.fontes).filter((y, k, a) => a.findIndex((z) => z.fonte === y.fonte) === k).map((y) => ({ fonte: y.fonte, url: y.url })),
    sugestoes: ['Qual o % de dados oficiais por área?', `Relatório de ${cid.nome} nos últimos 12 meses`] };
}

// ------------------------------------------------------------- série
async function serie(codigos, cids, per) {
  const linhas = await dados([codigos[0]], cids.map((c) => c.id_municipio), per.de, per.ate);
  if (!linhas.length) return { texto: 'Sem dados para esse filtro.', sugestoes: SUG };
  const cidsN = [...new Set(linhas.map((l) => l.municipio))].slice(0, 3);
  const meses = [...new Set(linhas.map((l) => l.ano_mes))];
  const tabela = meses.map((m) => ({ mes: m, ...Object.fromEntries(cidsN.map((c) => { const x = linhas.find((l) => l.municipio === c && l.ano_mes === m); return [c, x ? Number(x.valor) : null]; })) }));
  const e = estat(linhas.filter((l) => l.municipio === cidsN[0]));
  return { texto: `**${linhas[0].indicador}** (${linhas[0].unidade}), ${per.txt}. Em ${cidsN[0]}: média ${n(e.media, casas(e.media))}, mínimo ${n(e.min, casas(e.min))}, máximo ${n(e.max, casas(e.max))}, variação ${e.var_pct >= 0 ? '+' : ''}${n(e.var_pct, 1)}%. ${e.pct_oficial}% com base oficial.`,
    tabela, grafico: { rotulos: meses, series: cidsN.map((c) => ({ nome: c, valores: tabela.map((t) => t[c]) })), meta: Number(linhas[0].meta) },
    sugestoes: [`Relatório de ${linhas[0].indicador.toLowerCase()} em ${cidsN[0]}`, 'Compare com as outras cidades'] };
}

async function qualidade() {
  const r = await query(`SELECT servico, SUM(registros_reais) AS reais, SUM(registros_derivados) AS derivados, SUM(registros_estimados) AS estimados FROM vw_origem_dados GROUP BY servico`);
  return { texto: `Base oficial por área (todos os meses):\n${r.map((x) => { const t = Number(x.reais) + Number(x.derivados) + Number(x.estimados); return `• **${x.servico}:** ${Math.round(((Number(x.reais) + Number(x.derivados)) / t) * 100)}% oficial ou calculado de oficial`; }).join('\n')}\n\nA maior parte das estimativas vem de fontes que só publicam dados **anuais** (SNIS/SINISA, SEEG).`,
    sugestoes: ['Fonte do consumo de água em Campinas', ...SUG.slice(0, 1)] };
}

async function responder(pergunta, usuario) {
  const t = E.norm(pergunta).trim();
  if (!t || /^(oi|ola|bom dia|boa tarde|boa noite|ajuda|o que voce faz)/.test(t))
    return { texto: 'Oi! Sou o **Eco Analista** 🔬. Eu monto **rascunhos de relatório** com os números do banco, **comparo cidades**, mostro **séries** e explico **a fonte de cada dado**. Diga o tema, as cidades e o período.', sugestoes: SUG };
  const [{ m: ultimo }] = await query("SELECT DATE_FORMAT(MAX(periodo), '%Y-%m') AS m FROM indicador_valor");
  const per = E.periodo(t, ultimo);
  const cids = await E.cidades(t);
  let cods = E.indicadores(t);
  if (/(qualidade|% de dados oficiais|percentual oficial|quanto e estimado)/.test(t)) return qualidade();
  if (/(fonte|origem|de onde|referencia)/.test(t)) return fonteDe(cods, cids, per);
  if (!cods.length && /(relatorio|rascunho|resumo geral|panorama)/.test(t)) cods = ['AGU-01', 'AGU-02', 'ENE-01', 'ENE-02', 'RES-01', 'RES-02', 'MOB-01', 'MOB-02'];
  if (cods.length) {
    if (/(compar|ranking|melhor|pior|todas as cidades|8 cidades)/.test(t) && !/(relatorio|rascunho)/.test(t)) return comparar(cods, cids, per);
    if (/(evolu|serie|mes a mes|historico|grafico)/.test(t) && !/(relatorio|rascunho)/.test(t)) return serie(cods, cids.length ? cids : [], per);
    return relatorio(cods, cids, per);
  }
  const r = await copiloto.perguntar(pergunta, usuario.id);
  if (r.situacao === 'RESPONDIDA') return { texto: r.texto, tabela: r.linhas.slice(0, 15), sugestoes: SUG.slice(0, 2) };
  return { texto: r.situacao === 'BLOQUEADA' ? `Não posso fazer isso: ${r.texto}` : 'Me diga um **tema** (água, perdas, energia, solar, lixo, reciclagem, ônibus, emissões), as **cidades** e o **período**. Ex.: "relatório de reciclagem em Santos em 2026".', sugestoes: SUG };
}

module.exports = { responder, SUG, relatorio };
