// Dados prontos para as páginas de cada perfil: cidadão (minha cidade), analista (laboratório) e gestor (sala de situação).
const { consulta: query } = require('./db');
const fontes = require('./fontes');
const L = require('./linguagem');
const ia = require('./ia/alertas');

const ultimoMes = async () => (await query("SELECT DATE_FORMAT(MAX(periodo), '%Y-%m') AS m FROM indicador_valor"))[0].m;

// --------------------------------------------------------------- CIDADÃO
async function minhaCidade(idMun) {
  const mes = await ultimoMes();
  const [mun] = await query(`SELECT m.id_municipio, m.nome, m.regiao_metropolitana, p.populacao, p.ano AS ano_pop
                             FROM municipio m JOIN populacao_anual p ON p.id_municipio = m.id_municipio
                             WHERE m.id_municipio = ? ORDER BY p.ano DESC LIMIT 1`, [idMun]);
  if (!mun) throw Object.assign(new Error('Cidade não encontrada.'), { status: 404 });
  const [rk] = await query('SELECT * FROM vw_ies_ranking WHERE id_municipio = ?', [idMun]);
  const total = (await query('SELECT COUNT(*) AS n FROM vw_ies_ranking'))[0].n;
  const serie = await query(`SELECT codigo, ano_mes AS p, ROUND(valor, 3) AS v, score AS s, origem AS o, meta, unidade, sentido, indicador, servico
                             FROM vw_indicador_desempenho WHERE id_municipio = ?
                             AND periodo > DATE_SUB((SELECT MAX(periodo) FROM indicador_valor), INTERVAL 24 MONTH) ORDER BY codigo, periodo`, [idMun]);
  const iesSerie = await query(`SELECT ano_mes AS p, ies FROM vw_ies_municipio_mensal WHERE id_municipio = ?
                                AND periodo > DATE_SUB((SELECT MAX(periodo) FROM indicador_valor), INTERVAL 24 MONTH) ORDER BY periodo`, [idMun]);
  const media = await query(`SELECT ano_mes AS p, ROUND(AVG(ies), 2) AS ies FROM vw_ies_municipio_mensal
                             WHERE periodo > DATE_SUB((SELECT MAX(periodo) FROM indicador_valor), INTERVAL 24 MONTH) GROUP BY ano_mes ORDER BY ano_mes`);
  const fts = await fontes.dosIndicadores(idMun, mes);
  const codigos = [...new Set(serie.map((s) => s.codigo))];
  const indicadores = codigos.map((c) => {
    const s = serie.filter((x) => x.codigo === c); const u = s[s.length - 1]; const ant = s.find((x) => x.p === `${Number(mes.slice(0, 4)) - 1}${mes.slice(4)}`);
    const T = L.IND[c] || {};
    return { codigo: c, nome: u.indicador, simples: T.simples, icone: T.icone, servico: u.servico, unidade: u.unidade, unidadeSimples: T.unidadeSimples,
      meta: Number(u.meta), sentido: u.sentido, valor: Number(u.v), score: Number(u.s), origem: u.o, valorAnoPassado: ant ? Number(ant.v) : null,
      situacao: L.situacao(Number(u.s)), tendencia: L.tendencia(Number(u.v), ant ? Number(ant.v) : null, u.sentido),
      frase: T.frase?.(Number(u.v)), compara: T.compara?.(Number(u.v)), metaTxt: T.meta?.(Number(u.meta)), importa: T.importa,
      serie: s.map((x) => ({ p: x.p, v: Number(x.v), o: x.o })), fonte: fts[c] };
  });
  // último número OFICIAL de cada indicador (a fonte pode ter parado num mês/ano anterior ao do painel)
  const ofic = await query(`SELECT i.codigo, DATE_FORMAT(iv.periodo, '%Y-%m') AS p, iv.valor AS v, iv.origem AS o
      FROM indicador_valor iv JOIN indicador i USING (id_indicador)
      WHERE iv.id_municipio = ? AND iv.origem <> 'ESTIMADO'
        AND iv.periodo = (SELECT MAX(x.periodo) FROM indicador_valor x WHERE x.id_municipio = iv.id_municipio AND x.id_indicador = iv.id_indicador AND x.origem <> 'ESTIMADO')`, [idMun]);
  const FONTE_OFIC = { 'AGU-01': 'SNIS', 'AGU-02': 'SNIS', 'ENE-01': 'Anuário de Energéticos (SEMIL-SP)', 'ENE-02': 'ANEEL', 'RES-01': idMun === 1 ? 'SP Regula' : 'SINISA', 'RES-02': idMun === 1 ? 'SP Regula' : 'SINISA', 'MOB-01': 'SPTrans', 'MOB-02': 'SEEG' };
  const SEM_OFIC = { 'MOB-01': 'Esta cidade não publica dado oficial de passageiros de ônibus. A estimativa usa a variação oficial dos ônibus de São Paulo (SPTrans).' };
  for (const i of indicadores) {
    const o = ofic.find((x) => x.codigo === i.codigo);
    const fonteOf = idMun === 2 && i.codigo.startsWith('AGU') && o && o.p > '2024-12' ? 'SANASA' : FONTE_OFIC[i.codigo] || '';
    i.ultimoOficial = o ? { mes: o.p, mesTxt: L.mesLongo(o.p), valor: Number(o.v), origem: o.o, fonte: fonteOf, igualAoPainel: o.p === mes } : null;
    if (!o) i.semOficial = SEM_OFIC[i.codigo] || 'Ainda não há dado oficial publicado para este número.';
  }
  // comparação com as outras 7 cidades no mesmo mês (o cidadão vê isto no lugar de nota e meta)
  const ultimos = await query('SELECT id_municipio AS m, codigo AS c, valor AS v FROM vw_indicador_desempenho WHERE ano_mes = ?', [mes]);
  for (const i of indicadores) {
    const vals = ultimos.filter((x) => x.c === i.codigo).map((x) => Number(x.v));
    const media8 = vals.reduce((a, b) => a + b, 0) / (vals.length || 1);
    const ordem = [...vals].sort((a, b) => (i.sentido === 'MAIOR_MELHOR' ? b - a : a - b));
    const pct = media8 ? ((i.valor - media8) / media8) * 100 : 0;
    const melhor = i.sentido === 'MAIOR_MELHOR' ? pct > 0 : pct < 0;
    i.media8 = Math.round(media8 * 1000) / 1000; i.posicao = ordem.filter((v) => (i.sentido === 'MAIOR_MELHOR' ? v > i.valor + 1e-6 : v < i.valor - 1e-6)).length + 1;
    i.comparacao = Math.abs(pct) < 5 ? { nivel: 'ATENCAO', rotulo: 'Na média das cidades', pct } : melhor ? { nivel: 'BOM', rotulo: 'Melhor que a média', pct } : { nivel: 'CRITICO', rotulo: 'Pior que a média', pct };
    i.mediaTxt = `A média das 8 cidades é ${L.n(media8, media8 < 20 ? 2 : 0)} ${i.unidade}.`;
  }
  const areas = ['Água', 'Energia', 'Resíduos', 'Mobilidade'].map((sv) => {
    const it = indicadores.filter((i) => i.servico === sv); const score = it.reduce((a, b) => a + b.score, 0) / (it.length || 1);
    const bons = it.filter((i) => i.comparacao?.nivel === 'BOM').length; const ruins = it.filter((i) => i.comparacao?.nivel === 'CRITICO').length;
    const cmp = bons === it.length ? { nivel: 'BOM', rotulo: 'Melhor que a média' } : ruins === it.length ? { nivel: 'CRITICO', rotulo: 'Pior que a média' } : { nivel: 'ATENCAO', rotulo: 'Perto da média' };
    return { servico: sv, score: Math.round(score), ...L.situacaoArea(Math.round(score)), metas: `${it.filter((i) => i.score >= 100).length}/${it.length}`, comparacao: cmp };
  });
  const alertas = await query(`SELECT a.id_analise, a.tipo, a.severidade, a.titulo, a.descricao, DATE_FORMAT(a.gerada_em,'%Y-%m-%d') AS gerada_em,
                                      i.codigo AS indicador, s.nome AS servico
                               FROM analise_ia a JOIN indicador i USING (id_indicador) JOIN servico_publico s ON s.id_servico = i.id_servico
                               WHERE a.id_municipio = ? AND a.status IN ('NOVA','EM_ANALISE','VALIDADA')
                               ORDER BY FIELD(a.severidade,'CRITICO','ATENCAO','INFO'), a.gerada_em DESC LIMIT 12`, [idMun]);
  const vistos = new Set();
  const alertasSimples = alertas.map(L.alertaSimples).filter((a) => { const k = `${a.indicador}|${a.bom}`; if (vistos.has(k)) return false; vistos.add(k); return true; })
    .map((a) => { const i = indicadores.find((x) => x.codigo === a.indicador); return { ...a, explicacao: i ? `${i.frase} ${i.metaTxt}` : a.descricao, importa: i?.importa }; });
  const r = await ia.riscos(); const risco = r.cidades.find((c) => c.id_municipio === idMun);
  const acoes = await query('SELECT titulo, descricao, status, indicador_alvo, indicador_nome, efeito, variacao_pct, data_inicio, data_fim_prevista FROM vw_acoes_resultados WHERE municipio = ?', [mun.nome]);
  return { mes, mesTxt: L.mesLongo(mes), municipio: mun, posicao: rk?.posicao, total, ies: Number(rk?.ies), classificacao: rk?.classificacao,
    variacao_mes: rk?.variacao_mes, variacao_12m: rk?.variacao_12m, metas_atingidas: rk?.metas_atingidas,
    iesSerie, media, areas, indicadores, alertas: alertasSimples, risco, acoes };
}

// --------------------------------------------------------------- ANALISTA: laboratório de dados
async function laboratorio() {
  const [ind, mun, serie, metas] = await Promise.all([
    query(`SELECT i.id_indicador, i.codigo, i.nome, i.descricao, i.formula, i.meta, i.sentido, i.peso_ies, s.nome AS servico, u.sigla AS unidade
           FROM indicador i JOIN servico_publico s USING (id_servico) JOIN unidade_medida u USING (id_unidade) ORDER BY i.codigo`),
    query('SELECT id_municipio, nome FROM municipio ORDER BY nome'),
    query(`SELECT id_municipio AS m, codigo AS c, ano_mes AS p, ROUND(valor, 4) AS v, score AS s, origem AS o, meta AS mt
           FROM vw_indicador_desempenho ORDER BY periodo`),
    query('SELECT codigo, abrangencia, valor FROM vw_metas WHERE em_vigor = 1'),
  ]);
  const ies = await query('SELECT id_municipio AS m, ano_mes AS p, ies FROM vw_ies_municipio_mensal ORDER BY periodo');
  const meses = [...new Set(serie.map((s) => s.p))];
  return { indicadores: ind, municipios: mun, serie, ies, meses, metas, ultimoMes: meses[meses.length - 1] };
}

// --------------------------------------------------------------- GESTOR: sala de situação
async function salaSituacao(idMunFiltro) {
  const mes = await ultimoMes();
  const filtro = idMunFiltro ? 'AND id_municipio = ?' : '';
  const p = idMunFiltro ? [idMunFiltro] : [];
  const atual = await query(`SELECT id_municipio, municipio, codigo, indicador, servico, valor, meta, unidade, sentido, score, atingiu_meta, origem, peso_ies
                             FROM vw_indicador_desempenho WHERE ano_mes = ? ${filtro}`, [mes, ...p]);
  const pops = await query(`SELECT p.id_municipio, p.populacao FROM populacao_anual p
                            WHERE p.ano = (SELECT MAX(ano) FROM populacao_anual)`);
  const popDe = Object.fromEntries(pops.map((x) => [x.id_municipio, Number(x.populacao)]));
  const popTotal = Object.values(popDe).reduce((a, b) => a + b, 0);
  // Onde agir primeiro: distância da meta x peso do indicador x tamanho da população afetada
  const prioridades = atual.filter((a) => !a.atingiu_meta).map((a) => {
    const dist = a.sentido === 'MAIOR_MELHOR' ? (a.meta - a.valor) / a.meta : (a.valor - a.meta) / a.meta;
    const pop = popDe[a.id_municipio] || 0;
    const imp = Math.min(1, dist) * Number(a.peso_ies) * (0.5 + 0.5 * Math.sqrt(pop / popTotal));
    return { ...a, distancia_pct: Math.round(dist * 1000) / 10, populacao: pop, impacto: Math.round(imp * 1000) / 10,
      simples: L.IND[a.codigo]?.simples, frase: L.IND[a.codigo]?.frase(Number(a.valor)) };
  }).sort((a, b) => b.impacto - a.impacto).slice(0, 8);
  const tendencia = await query(`SELECT ano_mes, servico, score_medio, pct_metas_atingidas FROM vw_dw_tendencia_servico ORDER BY sk_tempo`);
  const ranking = await query('SELECT posicao, id_municipio, municipio, ies, classificacao, variacao_mes, variacao_12m, metas_atingidas FROM vw_ies_ranking ORDER BY posicao');
  const metasInd = await query(`SELECT codigo, indicador, servico, SUM(atingiu_meta) AS atingiram, COUNT(*) AS total FROM vw_indicador_desempenho
                                WHERE ano_mes = ? ${filtro} GROUP BY codigo, indicador, servico ORDER BY codigo`, [mes, ...p]);
  metasInd.forEach((m) => { m.simples = L.IND[m.codigo]?.simples || m.indicador; });
  const acoes = await query(`SELECT * FROM vw_acoes_resultados ${idMunFiltro ? 'WHERE municipio = (SELECT nome FROM municipio WHERE id_municipio = ?)' : ''} ORDER BY data_inicio DESC`, p);
  const alertas = await query(`SELECT a.id_analise, a.severidade, a.titulo, a.descricao, a.tipo, m.nome AS municipio, i.codigo AS indicador, s.nome AS servico
                               FROM analise_ia a JOIN municipio m USING (id_municipio) JOIN indicador i USING (id_indicador) JOIN servico_publico s ON s.id_servico = i.id_servico
                               WHERE a.status IN ('NOVA','EM_ANALISE','VALIDADA') AND a.severidade = 'CRITICO' ${idMunFiltro ? 'AND a.id_municipio = ?' : ''}
                               ORDER BY a.gerada_em DESC LIMIT 6`, p);
  const n = atual.length || 1;
  return { mes, mesTxt: L.mesLongo(mes), kpis: {
    ies_medio: Math.round((ranking.filter((r) => !idMunFiltro || r.id_municipio === idMunFiltro).reduce((a, b) => a + Number(b.ies), 0) / (idMunFiltro ? 1 : ranking.length)) * 10) / 10,
    pct_metas: Math.round((atual.filter((a) => a.atingiu_meta).length / n) * 100),
    criticos: (await query(`SELECT COUNT(*) AS n FROM analise_ia WHERE severidade='CRITICO' AND status IN ('NOVA','EM_ANALISE') ${idMunFiltro ? 'AND id_municipio = ?' : ''}`, p))[0].n,
    acoes_andamento: acoes.filter((a) => a.status === 'EM_EXECUCAO' || a.status === 'PLANEJADA').length,
    pct_oficial: Math.round((atual.filter((a) => a.origem !== 'ESTIMADO').length / n) * 100),
  }, prioridades, tendencia, ranking, metasInd, acoes, alertas };
}

// --------------------------------------------------------------- TODOS: explorar os dados das 8 cidades (mapa, comparar, mês a mês, simulador)
async function explorar() {
  const mes = await ultimoMes();
  const [mun, ind, serie, ies] = await Promise.all([
    query(`SELECT m.id_municipio, m.nome, m.latitude, m.longitude, m.area_km2, m.regiao_metropolitana, p.populacao
           FROM municipio m JOIN populacao_anual p ON p.id_municipio = m.id_municipio
           WHERE p.ano = (SELECT MAX(ano) FROM populacao_anual) ORDER BY m.nome`),
    query(`SELECT i.codigo, i.nome, i.descricao, i.formula, i.meta, i.sentido, i.peso_ies, i.ods, s.nome AS servico, u.sigla AS unidade
           FROM indicador i JOIN servico_publico s USING (id_servico) JOIN unidade_medida u USING (id_unidade) ORDER BY i.codigo`),
    query(`SELECT id_municipio AS m, codigo AS c, ano_mes AS p, ROUND(valor, 3) AS v, score AS s, origem AS o FROM vw_indicador_desempenho
           WHERE periodo > DATE_SUB((SELECT MAX(periodo) FROM indicador_valor), INTERVAL 24 MONTH) ORDER BY periodo`),
    query('SELECT id_municipio, posicao, ies, classificacao FROM vw_ies_ranking ORDER BY posicao'),
  ]);
  const indicadores = ind.map((i) => ({ ...i, meta: Number(i.meta), peso_ies: Number(i.peso_ies), simples: L.IND[i.codigo]?.simples, icone: L.IND[i.codigo]?.icone,
    unidadeSimples: L.IND[i.codigo]?.unidadeSimples, importa: L.IND[i.codigo]?.importa }));
  return { mes, mesTxt: L.mesLongo(mes), municipios: mun, indicadores, serie, ies, meses: [...new Set(serie.map((x) => x.p))] };
}

// O cidadão não tem acesso a metas nem à nota: tira esses campos e troca a "situação" pela comparação com as outras cidades
function paraCidadao(d) {
  const ind = d.indicadores.map(({ meta, score, metaTxt, situacao, ...i }) => ({ ...i, situacao: i.comparacao }));
  const areas = d.areas.map(({ score, metas, nivel, rotulo, comparacao, ...a }) => ({ ...a, ...comparacao }));
  const alertas = d.alertas.map((a) => {
    const i = ind.find((x) => x.codigo === a.indicador);
    const simples = a.bom ? a.simples : { ALERTA_META: `${i?.simples || a.indicador} precisa de atenção`, TENDENCIA: `${i?.simples} piorou em relação ao ano passado`,
      PREVISAO: `${i?.simples} pode piorar nos próximos meses`, ANOMALIA: `${i?.simples}: valor fora do normal neste mês` }[a.tipo] || a.simples;
    return { ...a, simples, explicacao: i ? `${i.frase} ${i.mediaTxt}` : a.descricao };
  });
  const { ies, classificacao, posicao, total, iesSerie, media, metas_atingidas, variacao_mes, variacao_12m, risco, ...resto } = d;
  return { ...resto, indicadores: ind, areas, alertas, risco: risco ? { nivel: risco.nivel, criticos: risco.criticos, atencao: risco.atencao } : null };
}

module.exports = { paraCidadao, minhaCidade, laboratorio, salaSituacao, ultimoMes, explorar };
