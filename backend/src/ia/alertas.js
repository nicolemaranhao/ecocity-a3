// IA de alertas e riscos do EcoCity (roda sozinha depois de cada coleta mensal).
// Técnicas simples e explicáveis, sobre a série mensal de cada cidade x indicador:
//   ALERTA_META -> o indicador está abaixo da meta há 3 meses seguidos
//   TENDENCIA   -> os 3 últimos meses estão piores que os mesmos meses do ano anterior
//   PREVISAO    -> regressão linear dos 6 últimos meses: a meta será perdida nos próximos 3 meses
//   ANOMALIA    -> o último mês fugiu muito do padrão (z-score da variação > 2,5)
// Os alertas entram como NOVA e um analista valida ou descarta (a IA não decide sozinha).
const { pool, poolETL } = require('../db');

const MODELO = 'ecocity-ia-v2-node';
const pior = (sentido, a, b) => (sentido === 'MAIOR_MELHOR' ? a < b : a > b);   // a é pior que b?
const media = (v) => v.reduce((s, x) => s + x, 0) / (v.length || 1);
const fmt = (n) => Number(n).toLocaleString('pt-BR', { maximumFractionDigits: 2 });

function regressao(ys) {               // y = a + b*x
  const n = ys.length; const xs = ys.map((_, i) => i);
  const mx = media(xs); const my = media(ys);
  const b = xs.reduce((s, x, i) => s + (x - mx) * (ys[i] - my), 0) / (xs.reduce((s, x) => s + (x - mx) ** 2, 0) || 1);
  return { a: my - b * mx, b };
}

function analisar(serie, mes) {
  const s = serie.filter((x) => x.ano_mes <= mes);
  if (s.length < 15) return [];
  const ult = s[s.length - 1];
  if (ult.ano_mes !== mes) return [];
  const { sentido, meta, unidade, indicador, municipio } = ult;
  const out = [];

  // ALERTA_META
  const ult3 = s.slice(-3);
  if (ult3.every((x) => !x.atingiu_meta)) {
    const sc = media(ult3.map((x) => x.score));
    out.push({
      tipo: 'ALERTA_META', severidade: sc < 55 ? 'CRITICO' : 'ATENCAO', confianca: 90,
      titulo: `${municipio}: ${indicador} fora da meta há 3 meses`,
      descricao: `Nos últimos 3 meses o valor ficou em ${fmt(media(ult3.map((x) => x.valor)))} ${unidade}, e a meta é ${fmt(meta)} ${unidade}. Nota média do indicador: ${fmt(sc)} de 100.`,
    });
  }

  // TENDENCIA (compara com os mesmos meses do ano anterior para não confundir sazonalidade)
  const ant3 = s.slice(-15, -12);
  if (ant3.length === 3) {
    const a = media(ult3.map((x) => x.valor)); const b = media(ant3.map((x) => x.valor));
    const varPct = b ? ((a - b) / Math.abs(b)) * 100 : 0;
    if (pior(sentido, a, b) && Math.abs(varPct) >= 5) {
      out.push({
        tipo: 'TENDENCIA', severidade: Math.abs(varPct) >= 15 ? 'CRITICO' : 'ATENCAO', confianca: Math.min(95, 60 + Math.abs(varPct)),
        titulo: `${municipio}: ${indicador} piorou ${fmt(Math.abs(varPct))}% em 1 ano`,
        descricao: `Média dos 3 últimos meses: ${fmt(a)} ${unidade}. Nos mesmos meses do ano passado: ${fmt(b)} ${unidade}.`,
      });
    }
  }

  // PREVISAO (risco de perder a meta)
  const y6 = s.slice(-6).map((x) => x.valor);
  const { a, b } = regressao(y6);
  const proj = a + b * (y6.length + 2);          // daqui a 3 meses
  if (ult.atingiu_meta && pior(sentido, proj, meta)) {
    out.push({
      tipo: 'PREVISAO', severidade: 'ATENCAO', confianca: 70,
      titulo: `${municipio}: risco de perder a meta de ${indicador}`,
      descricao: `Hoje a cidade cumpre a meta (${fmt(ult.valor)} ${unidade}), mas no ritmo dos últimos 6 meses deve chegar a ${fmt(proj)} ${unidade} em 3 meses, além da meta de ${fmt(meta)}.`,
    });
  }

  // ANOMALIA (variação do último mês muito fora do padrão)
  const vars = s.slice(-13).map((x, i, arr) => (i ? (x.valor - arr[i - 1].valor) / (Math.abs(arr[i - 1].valor) || 1) : null)).slice(1);
  const hist = vars.slice(0, -1); const ultimaVar = vars[vars.length - 1];
  const dp = Math.sqrt(media(hist.map((v) => (v - media(hist)) ** 2)));
  const z = dp ? (ultimaVar - media(hist)) / dp : 0;
  if (Math.abs(z) > 2.5 && pior(sentido, ult.valor, s[s.length - 2].valor)) {
    out.push({
      tipo: 'ANOMALIA', severidade: 'ATENCAO', confianca: Math.min(95, 50 + Math.abs(z) * 10),
      titulo: `${municipio}: ${indicador} teve um salto fora do normal`,
      descricao: `A variação de ${mes} (${fmt(ultimaVar * 100)}%) está ${fmt(Math.abs(z))} desvios do padrão dos últimos 12 meses. Vale conferir a fonte do dado (origem: ${ult.origem}).`,
    });
  }
  return out.map((o) => ({ ...o, id_indicador: ult.id_indicador, id_municipio: ult.id_municipio }));
}

async function gerar(mes) {
  const [linhas] = await poolETL.query(`
    SELECT id_indicador, codigo, indicador, id_municipio, municipio, ano_mes, valor, meta, unidade, sentido, score, atingiu_meta, origem
    FROM vw_indicador_desempenho ORDER BY id_municipio, id_indicador, periodo`);
  const grupos = {};
  for (const l of linhas) (grupos[`${l.id_municipio}-${l.id_indicador}`] ||= []).push(l);
  let alertas = Object.values(grupos).flatMap((g) => analisar(g, mes));
  const peso = { CRITICO: 0, ATENCAO: 1, INFO: 2 };
  alertas = alertas.sort((x, y) => peso[x.severidade] - peso[y.severidade] || y.confianca - x.confianca).slice(0, 25);

  let gravados = 0;
  for (const a of alertas) {
    // não repete um alerta igual que ainda está aberto
    const [[ja]] = await poolETL.query(
      `SELECT COUNT(*) AS n FROM analise_ia WHERE id_indicador = ? AND id_municipio = ? AND tipo = ?
       AND status IN ('NOVA','EM_ANALISE') AND gerada_em > NOW() - INTERVAL 45 DAY`, [a.id_indicador, a.id_municipio, a.tipo]);
    if (ja.n) continue;
    await poolETL.execute(
      `INSERT INTO analise_ia (id_indicador, id_municipio, tipo, titulo, descricao, confianca, severidade, modelo_versao)
       VALUES (?,?,?,?,?,?,?,?)`,
      [a.id_indicador, a.id_municipio, a.tipo, a.titulo.slice(0, 150), a.descricao, Math.round(a.confianca * 100) / 100, a.severidade, MODELO]);
    gravados++;
  }
  return { encontrados: alertas.length, gravados };
}

// Radar de riscos: uma nota de risco (0 a 100) por cidade e por área, no último mês
async function riscos() {
  const [[{ mes }]] = await pool.query("SELECT DATE_FORMAT(MAX(periodo), '%Y-%m') AS mes FROM vw_ies_municipio_mensal");
  const [cidades] = await pool.query(`SELECT id_municipio, municipio, ies FROM vw_ies_municipio_mensal WHERE ano_mes = ? ORDER BY municipio`, [mes]);
  const [areas] = await pool.query(`SELECT id_municipio, servico, ROUND(AVG(score),1) AS score, SUM(atingiu_meta) AS metas, COUNT(*) AS total
                                    FROM vw_indicador_desempenho WHERE ano_mes = ? GROUP BY id_municipio, servico`, [mes]);
  const [abertos] = await pool.query(`SELECT id_municipio, SUM(severidade='CRITICO') AS criticos, SUM(severidade='ATENCAO') AS atencao
                                      FROM analise_ia WHERE status IN ('NOVA','EM_ANALISE','VALIDADA') GROUP BY id_municipio`);
  const nivel = (r) => (r >= 50 ? 'ALTO' : r >= 30 ? 'MEDIO' : 'BAIXO');
  const lista = cidades.map((c) => {
    const al = abertos.find((a) => a.id_municipio === c.id_municipio) || { criticos: 0, atencao: 0 };
    const risco = Math.min(100, Math.round(0.7 * (100 - c.ies) + 6 * Number(al.criticos) + 2 * Number(al.atencao)));
    return {
      id_municipio: c.id_municipio, municipio: c.municipio, ies: c.ies, risco, nivel: nivel(risco),
      criticos: Number(al.criticos), atencao: Number(al.atencao),
      areas: areas.filter((a) => a.id_municipio === c.id_municipio).map((a) => ({
        servico: a.servico, score: a.score, risco: Math.round(100 - a.score), nivel: nivel(100 - a.score), metas: `${a.metas}/${a.total}`,
      })),
    };
  }).sort((a, b) => b.risco - a.risco);
  return { mes, cidades: lista, explicacao: 'Risco = 70% da distância da nota até 100 + peso dos alertas abertos (crítico 6, atenção 2). Alto ≥ 50, médio ≥ 30.' };
}

module.exports = { gerar, riscos, analisar, MODELO };

if (require.main === module) {
  gerar(process.argv[2]).then((r) => { console.log(r); process.exit(0); }).catch((e) => { console.error(e); process.exit(1); });
}
