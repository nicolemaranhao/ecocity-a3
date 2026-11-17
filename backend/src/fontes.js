// De onde vem cada número: liga indicador -> métricas da fórmula -> dado -> fonte oficial.
const { consulta: query } = require('./db');
const { ORIGEM } = require('./linguagem');

const IBGE = { fonte: 'IBGE - Estimativas de população', sigla: 'IBGE', orgao: 'Instituto Brasileiro de Geografia e Estatística',
  url: 'https://www.ibge.gov.br/estatisticas/sociais/populacao/9103-estimativas-de-populacao.html', frequencia: 'ANUAL', origem: 'REAL' };
const PIOR = { REAL: 0, DERIVADO: 1, ESTIMADO: 2 };

let cacheMapa = null;
async function metricasPorIndicador() {
  if (cacheMapa) return cacheMapa;
  const [ind, met] = await Promise.all([query('SELECT codigo, formula FROM indicador'), query('SELECT codigo, nome FROM metrica')]);
  cacheMapa = Object.fromEntries(ind.map((i) => [i.codigo, {
    metricas: met.filter((m) => new RegExp(`\\b${m.codigo}\\b`).test(i.formula)).map((m) => m.codigo),
    usaPopulacao: /populacao/i.test(i.formula),
  }]));
  return cacheMapa;
}

// Fontes de todos os indicadores de UMA cidade em UM mês ('AAAA-MM')
async function dosIndicadores(idMun, mes) {
  const mapa = await metricasPorIndicador();
  const linhas = await query(`
    SELECT m.codigo AS metrica, m.nome AS metrica_nome, f.nome AS fonte, o.sigla, o.nome AS orgao, f.endpoint_url AS url, f.frequencia,
           f.confiabilidade, d.origem, d.referencia_origem AS referencia, d.valor
    FROM dado d JOIN metrica m USING (id_metrica) JOIN fonte_dados f USING (id_fonte) JOIN orgao o ON o.id_orgao = f.id_orgao
    WHERE d.id_municipio = ? AND d.data_referencia = ?`, [idMun, `${mes}-01`]);
  const [pop] = await query(`SELECT p.populacao, p.ano, p.fonte FROM populacao_anual p WHERE p.id_municipio = ?
                             AND p.ano = (SELECT MAX(ano) FROM populacao_anual WHERE id_municipio = ? AND ano <= ?)`, [idMun, idMun, Number(mes.slice(0, 4))]);
  const out = {};
  for (const [cod, { metricas, usaPopulacao }] of Object.entries(mapa)) {
    const fontes = linhas.filter((l) => metricas.includes(l.metrica));
    if (usaPopulacao && pop) fontes.push({ ...IBGE, metrica: 'POPULACAO', metrica_nome: `População (${pop.ano})`, referencia: `${pop.fonte}: ${Number(pop.populacao).toLocaleString('pt-BR')} habitantes`, valor: pop.populacao });
    const origem = fontes.reduce((o, f) => (PIOR[f.origem] > PIOR[o] ? f.origem : o), 'REAL');
    const nomes = [...new Set(fontes.map((f) => f.sigla))];
    out[cod] = { origem, origemTxt: ORIGEM[origem].rotulo, resumo: nomes.join(' + '), fontes };
  }
  return out;
}

async function deUmValor(idMun, codigo, mes) {
  const t = await dosIndicadores(idMun, mes);
  return t[codigo] || null;
}

// Catálogo para a página "De onde vêm os dados"
async function catalogo() {
  const mapa = await metricasPorIndicador();
  const fontes = await query(`
    SELECT f.id_fonte, f.nome, o.sigla, o.nome AS orgao, s.nome AS servico, f.tipo_integracao, f.frequencia, f.endpoint_url AS url,
           f.confiabilidade, f.confiabilidade_motivo, q.total_registros, q.registros_reais, q.registros_derivados, q.registros_estimados,
           DATE_FORMAT(q.ultimo_mes_oficial,'%Y-%m') AS ultimo_mes_oficial, DATE_FORMAT(q.ultimo_mes,'%Y-%m') AS ultimo_mes, q.status_ultimo_lote,
           (SELECT GROUP_CONCAT(DISTINCT m.codigo) FROM dado d JOIN metrica m USING (id_metrica) WHERE d.id_fonte = f.id_fonte) AS metricas
    FROM fonte_dados f JOIN orgao o USING (id_orgao) JOIN servico_publico s ON s.id_servico = f.id_servico
    LEFT JOIN vw_qualidade_fontes q ON q.id_fonte = f.id_fonte ORDER BY s.id_servico, f.nome`);
  const ind = await query('SELECT codigo, nome FROM indicador');
  for (const f of fontes) {
    const mets = String(f.metricas || '').split(',');
    f.indicadores = ind.filter((i) => mapa[i.codigo]?.metricas.some((m) => mets.includes(m))).map((i) => ({ codigo: i.codigo, nome: i.nome }));
  }
  fontes.push({ ...IBGE, nome: IBGE.fonte, servico: 'Todas', tipo_integracao: 'API_REST', confiabilidade: 5, confiabilidade_motivo: 'Estimativa oficial anual de população; usada para calcular os valores "por pessoa".',
    indicadores: ind.filter((i) => mapa[i.codigo]?.usaPopulacao).map((i) => ({ codigo: i.codigo, nome: i.nome })) });
  const origem = await query('SELECT origem, COUNT(*) AS n FROM dado GROUP BY origem');
  return { fontes, origem, tipos: ORIGEM };
}

module.exports = { dosIndicadores, deUmValor, catalogo, metricasPorIndicador };
