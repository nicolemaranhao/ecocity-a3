// Robô de coleta do EcoCity (v17) — atualiza o banco SOZINHO quando os órgãos públicos
// publicam dados novos.
//
// Como funciona (cada execução):
//   1. Confere cada fonte oficial (ANEEL, SPTrans, EPE, SEEG, SNIS/SINISA, IBGE).
//      Se a fonte não publicou nada novo desde a última vez, não baixa de novo.
//   2. Compara o que veio com o que já está no banco e separa só o que é NOVO ou MUDOU
//      (o órgão pode revisar números antigos: o banco acompanha a revisão).
//   3. Grava na tabela de entrada (stg_medicao_bruta) num lote por fonte.
//      O BANCO valida e carrega (sp_trocar_estimativas_do_lote + sp_processar_staging):
//      oficial substitui estimado; estimado nunca substitui oficial.
//   4. Se uma fonte anual publicou um ANO NOVO, o painel ganha os 12 meses desse ano
//      (o que ainda não tem fonte oficial é estimado e marcado como estimado).
//   5. Recalcula os indicadores dos meses que mudaram (sp_pipeline_mensal) e roda a IA.
//   6. Anota cada conferência na tabela coleta_verificacao (prova de quando o site mudou).
//
// Modo (COLETA_MODO no .env):
//   oficial (padrão) -> o painel só avança para um ano novo quando água (SNIS) e emissões
//                       (SEEG) daquele ano já foram publicadas. Mantém a maioria oficial.
//   mensal           -> o painel avança todo mês que a ANEEL/SPTrans publicam; o resto é estimado.
const { poolETL } = require('../db');
const C = require('./conectores');
const ia = require('../ia/alertas');

const { FONTE, ym, dias, rot } = C;
const RANK = { ESTIMADO: 1, DERIVADO: 2, REAL: 3 };
let rodando = false;
const historico = [];
let proximaVerificacao = null;
let atual = null;          // execução em andamento (a tela do administrador acompanha)

const mesAnterior = (d = new Date()) => {
  const x = new Date(d.getFullYear(), d.getMonth() - 1, 1);
  return ym(x.getFullYear(), x.getMonth() + 1);
};
const somaMes = (mes, n) => { const [a, m] = mes.split('-').map(Number); const d = new Date(a, m - 1 + n, 1); return ym(d.getFullYear(), d.getMonth() + 1); };
const NOMES = {
  [FONTE.ANEEL]: 'ANEEL – energia solar', [FONTE.SPTRANS]: 'SPTrans – ônibus de São Paulo', [FONTE.EPE]: 'EPE – energia do Estado',
  [FONTE.SEEG]: 'SEEG – emissões', [FONTE.AGUA_CONSUMO]: 'SNIS/SINISA – água', [FONTE.SINISA]: 'SINISA – resíduos',
};

// ------------------------------------------------------------------ leitura do banco
async function contexto(forcar) {
  const [municipios] = await poolETL.query('SELECT id_municipio, nome, codigo_ibge FROM municipio ORDER BY id_municipio');
  const [pops] = await poolETL.query('SELECT id_municipio, ano, populacao FROM populacao_anual');
  const [[jan]] = await poolETL.query("SELECT DATE_FORMAT(MIN(data_referencia), '%Y-%m') AS ini, DATE_FORMAT(MAX(data_referencia), '%Y-%m') AS fim FROM dado");
  const [vers] = await poolETL.query(`
    SELECT v.id_fonte, v.versao_fonte, TIMESTAMPDIFF(HOUR, v.verificado_em, NOW()) AS horas
    FROM coleta_verificacao v
    WHERE v.id_verificacao IN (SELECT MAX(id_verificacao) FROM coleta_verificacao WHERE status <> 'FALHA' GROUP BY id_fonte)`);
  const [dados] = await poolETL.query(`
    SELECT r.nome, m.codigo, DATE_FORMAT(d.data_referencia, '%Y-%m') AS mes, d.valor, d.origem, d.id_fonte
    FROM dado d JOIN municipio r USING (id_municipio) JOIN metrica m USING (id_metrica)`);
  const banco = new Map();
  for (const d of dados) {
    const k = `${d.nome}|${d.codigo}|${d.mes}`;
    const atual = banco.get(k);
    if (!atual || RANK[d.origem] > RANK[atual.origem]) banco.set(k, { valor: Number(d.valor), origem: d.origem, fonte: d.id_fonte });
  }
  const versao = Object.fromEntries(vers.map((v) => [v.id_fonte, v]));
  const popMap = {};
  for (const p of pops) (popMap[p.id_municipio] ||= {})[p.ano] = Number(p.populacao);
  return {
    forcar, municipios, banco, inicio: jan.ini, fim: jan.fim, desde: jan.ini || '2023-01',
    ultimaVersao: (f) => versao[f]?.versao_fonte || null,
    temAnoOficial: (metrica, ano) => [...banco.entries()].some(([k, v]) => v.origem !== 'ESTIMADO' && k.includes(`|${metrica}|${ano}-`)),
    horasDesde: (f) => (versao[f] ? Number(versao[f].horas) : Infinity),
    populacao: (nome, ano) => { const m = municipios.find((x) => x.nome === nome); return m && popMap[m.id_municipio]?.[ano]; },
    popMap,
  };
}

// ------------------------------------------------------------------ gravação (o banco valida)
async function carregarLote(idFonte, linhas, mensagem) {
  const [l] = await poolETL.execute('INSERT INTO lote_carga (id_fonte, mensagem) VALUES (?, ?)', [idFonte, mensagem.slice(0, 250)]);
  const idLote = l.insertId;
  for (let i = 0; i < linhas.length; i += 400) {
    const parte = linhas.slice(i, i + 400);
    await poolETL.query(
      'INSERT INTO stg_medicao_bruta (id_lote, codigo_metrica, nome_municipio, data_texto, valor_texto, origem_informada, referencia_informada) VALUES ?',
      [parte.map((x) => [idLote, x.metrica, x.municipio, `${x.mes}-01`, Number(x.valor).toFixed(4), x.origem || 'REAL', (x.referencia || '').slice(0, 300)])]);
  }
  await poolETL.query('CALL sp_trocar_estimativas_do_lote(?)', [idLote]);   // o melhor dado substitui o pior
  await poolETL.query('CALL sp_processar_staging(?)', [idLote]);            // o banco valida e carrega
  const [[r]] = await poolETL.query('SELECT status, registros_validos, registros_rejeitados FROM lote_carga WHERE id_lote = ?', [idLote]);
  return { lote: idLote, ...r };
}
const verificacao = (fonte, versao, novos, status, msg, lote = null) =>
  poolETL.query('CALL sp_registrar_verificacao(?,?,?,?,?,?)', [fonte, versao ? String(versao).slice(0, 120) : null, novos, status, String(msg || '').slice(0, 255), lote]);

// o valor veio novo ou mudou em relação ao banco?
function precisaGravar(ctx, x) {
  const e = ctx.banco.get(`${x.municipio}|${x.metrica}|${x.mes}`);
  if (!e) return true;
  if (RANK[x.origem] > RANK[e.origem]) return true;               // melhora a qualidade (ex.: estimado -> oficial)
  if (RANK[x.origem] < RANK[e.origem]) return false;              // nunca piora
  if (e.fonte !== x.fonte) return e.origem === 'ESTIMADO';        // mesma qualidade, outra fonte: fica o que estava
  return Math.abs(e.valor - x.valor) > Math.max(0.01, Math.abs(e.valor) * 1e-6);   // o órgão revisou o número
}

// ------------------------------------------------------------------ execução completa
async function atualizar({ origem = 'manual', forcar = false } = {}) {
  if (rodando) throw Object.assign(new Error('A coleta já está rodando. Aguarde terminar.'), { status: 409 });
  rodando = true;
  const exec = { origem, inicio: new Date().toISOString(), etapas: [], mes: null, modo: process.env.COLETA_MODO || 'mensal' };
  const etapa = (nome, ok, detalhe) => exec.etapas.push({ nome, ok, detalhe });
  atual = exec;
  try {
    const ctx = await contexto(forcar);
    const res = {};
    const conectores = [
      [FONTE.AGUA_CONSUMO, (c = ctx) => C.snisAgua(c)],
      [FONTE.SEEG, (c = ctx) => C.seeg(c)],
      [FONTE.SINISA, (c = ctx) => C.sinisaResiduos(c)],
      [FONTE.SPTRANS, (c = ctx) => C.sptrans(c)],
      [FONTE.EPE, (c = ctx) => C.epe(c)],
      [FONTE.ANEEL, () => {
        // o arquivo da ANEEL tem ~110 MB e muda quase todo dia: baixa no máximo a cada COLETA_ANEEL_DIAS dias
        const dd = Number(process.env.COLETA_ANEEL_DIAS || 7);
        if (!forcar && ctx.horasDesde(FONTE.ANEEL) < dd * 24) return { fonte: FONTE.ANEEL, versao: ctx.ultimaVersao(FONTE.ANEEL), semNovidade: true, linhas: [], pulado: `baixado há menos de ${dd} dias` };
        return C.aneelGD(ctx);
      }],
    ];
    for (const [fonte, fn] of conectores) {
      const t0 = Date.now();
      exec.agora = `Conferindo ${NOMES[fonte]}…`;
      try { res[fonte] = await fn(); res[fonte].seg = Math.round((Date.now() - t0) / 1000); }
      catch (e) {
        res[fonte] = { erro: e.message };
        await verificacao(fonte, null, 0, 'FALHA', e.message);
        etapa(NOMES[fonte], false, `${e.message} → o banco continua com os números anteriores`);
      }
    }

    exec.agora = 'Gravando no banco e recalculando os indicadores…';
    // ---------- até que mês o painel vai
    const fimBanco = ctx.fim;
    let limite = fimBanco;
    if (exec.modo === 'mensal') {
      const m = [res[FONTE.ANEEL]?.ultimoMes, res[FONTE.SPTRANS]?.ultimoMes].filter(Boolean).sort().pop();
      if (m && m > limite) limite = m;
    } else {
      const a = Math.min(res[FONTE.SEEG]?.ultimoAno || 0, res[FONTE.AGUA_CONSUMO]?.ultimoAno || 0);
      if (a && `${a}-12` > limite) limite = `${a}-12`;
    }
    if (limite > mesAnterior()) limite = mesAnterior();
    const mesesNovos = [];
    for (let m = somaMes(fimBanco, 1); m <= limite; m = somaMes(m, 1)) mesesNovos.push(m);
    const cabe = (mes) => mes >= ctx.desde && mes <= limite;

    // o painel vai ganhar meses novos: as fontes que não mudaram precisam mandar os números desses meses também
    if (mesesNovos.length) {
      const ctxTudo = { ...ctx, forcar: true };
      for (const [fonte, fn] of conectores) {
        if (!res[fonte]?.semNovidade || fonte === FONTE.SINISA) continue;
        exec.agora = `Buscando ${NOMES[fonte]} para os meses novos…`;
        try { const r = await (fonte === FONTE.ANEEL ? C.aneelGD(ctxTudo) : fn.call(null, ctxTudo)); res[fonte] = { ...r, semNovidade: false, detalhe: `${r.detalhe || ''} (relido para os meses novos)`.trim() }; }
        catch (e) { etapa(NOMES[fonte], false, `${e.message} → os meses novos ficam estimados`); }
      }
    }

    // ---------- população dos anos novos (IBGE)
    const anosNovos = [...new Set(mesesNovos.map((m) => Number(m.slice(0, 4))))];
    for (const ano of anosNovos) {
      let pops = [];
      try { pops = await C.ibgePopulacao(ano, ctx.municipios); } catch (e) { etapa('IBGE – população', false, e.message); }
      for (const m of ctx.municipios) {
        const p = pops.find((x) => x.codigo_ibge === String(m.codigo_ibge));
        const anos = Object.keys(ctx.popMap[m.id_municipio] || {}).map(Number).filter((x) => x <= ano).sort();
        const valor = p?.populacao || ctx.popMap[m.id_municipio]?.[anos[anos.length - 1]];
        if (!valor || ctx.popMap[m.id_municipio]?.[ano]) continue;
        await poolETL.execute('INSERT INTO populacao_anual (id_municipio, ano, populacao, fonte) VALUES (?,?,?,?)',
          [m.id_municipio, ano, valor, p ? `IBGE - estimativa ${ano} (API)` : `IBGE - última estimativa disponível (${anos[anos.length - 1]}), repetida até sair a de ${ano}`]);
        (ctx.popMap[m.id_municipio] ||= {})[ano] = valor;
      }
      etapa('IBGE – população', true, `${ano}: ${pops.length ? `${pops.length} cidades pela API` : 'repetida a última estimativa'}`);
    }

    // ---------- estimativas dos meses NOVOS que não têm fonte oficial na cidade
    const extras = [];
    const valorDe = (nome, metrica, mes) => extras.find((x) => x.municipio === nome && x.metrica === metrica && x.mes === mes)?.valor
      ?? ctx.banco.get(`${nome}|${metrica}|${mes}`)?.valor;
    const epeSP = res[FONTE.EPE]?.serieSP;
    const spt = res[FONTE.SPTRANS]?.serie;
    const sptMes = (k) => { const s = spt?.[k]; if (!s) return null; const d = dias(Number(k.slice(0, 4)), Number(k.slice(5))); return s.viagens * d / s.dias; };
    for (const mes of mesesNovos) {
      const ant = somaMes(mes, -12);
      for (const m of ctx.municipios) {
        const e0 = valorDe(m.nome, 'ENERGIA_CONSUMIDA', ant);
        if (e0 && epeSP?.[mes] && epeSP?.[ant]) {
          extras.push({ fonte: FONTE.EPE, metrica: 'ENERGIA_CONSUMIDA', municipio: m.nome, mes, origem: 'ESTIMADO', valor: e0 * epeSP[mes] / epeSP[ant],
            referencia: `ESTIMADO: consumo da cidade em ${rot(ant)} x variação OFICIAL do Estado de SP entre ${rot(ant)} e ${rot(mes)} (EPE). Não há dado oficial mensal por cidade.` });
        }
        if (m.nome !== 'São Paulo') {
          const t0 = valorDe(m.nome, 'TP_PASSAGEIROS', ant);
          if (t0 && sptMes(mes) && sptMes(ant)) {
            extras.push({ fonte: FONTE.SPTRANS, metrica: 'TP_PASSAGEIROS', municipio: m.nome, mes, origem: 'ESTIMADO', valor: t0 * sptMes(mes) / sptMes(ant),
              referencia: `ESTIMADO: passageiros da cidade em ${rot(ant)} x variação OFICIAL dos ônibus de São Paulo entre ${rot(ant)} e ${rot(mes)} (SPTrans). Oficial: operadora municipal.` });
          }
        }
      }
    }

    // ---------- separa o que é novo ou mudou, e grava um lote por fonte
    const tocados = new Set();
    const todas = [...Object.values(res).flatMap((r) => r.linhas || []), ...extras].filter((x) => cabe(x.mes));
    const porFonte = {};
    for (const x of todas) if (precisaGravar(ctx, x)) (porFonte[x.fonte] ||= []).push(x);
    for (const [fonte, r] of Object.entries(res)) {
      const f = Number(fonte);
      if (r.erro) continue;
      // água vem de duas fontes do cadastro (consumo = 1, perdas/produção = 2): um lote para cada
      const grupos = f === FONTE.AGUA_CONSUMO ? [FONTE.AGUA_CONSUMO, FONTE.AGUA_PERDAS] : [f];
      let novos = 0; let lote = null; const partes = [];
      for (const g of grupos) {
        const linhas = porFonte[g] || [];
        if (!linhas.length) continue;
        const out = await carregarLote(g, linhas, `Coleta automática: ${NOMES[f]} (${r.versao || ''})`);
        lote = out.lote; novos += out.registros_validos;
        linhas.forEach((x) => tocados.add(x.mes));
        partes.push(`${out.registros_validos} valores novos ou revisados${out.registros_rejeitados ? ` e ${out.registros_rejeitados} ignorados pelo banco` : ''} (lote ${out.lote})`);
      }
      let texto = partes.length ? partes.join('; ') : r.semNovidade ? `sem novidade${r.pulado ? ` (${r.pulado})` : ''}` : 'nada novo para o período do painel';
      if (r.aviso) texto += `. AVISO: ${r.aviso}`;
      await verificacao(f, r.versao, novos, partes.length || !r.semNovidade ? 'OK' : 'SEM_NOVIDADE', `${texto}${r.detalhe ? ` · ${r.detalhe}` : ''}`, lote);
      etapa(NOMES[f], !r.aviso, `${texto}${r.detalhe ? ` · ${r.detalhe}` : ''}`);
    }

    // ---------- planilhas que o administrador deixou na pasta dados_reais/entrada
    for (const p of C.planilhasDaPasta()) {
      const porF = {};
      for (const d of p.dados) (porF[d.fonte] ||= []).push(d);
      for (const [fonte, linhas] of Object.entries(porF)) {
        try {
          const r = await carregarLote(Number(fonte), linhas, `Planilha ${p.arquivo}`);
          linhas.forEach((x) => tocados.add(x.mes));
          etapa(`Planilha ${p.arquivo}`, r.registros_rejeitados === 0, `${r.registros_validos} aceitos, ${r.registros_rejeitados} recusados pelo banco`);
        } catch (e) { etapa(`Planilha ${p.arquivo}`, false, e.message); }
      }
      C.arquivarPlanilha(p.arquivo);
    }

    // ---------- meses novos: completa o que faltou com estimativa (marcada como estimada)
    for (const mes of mesesNovos) {
      await poolETL.query('CALL sp_estimar_mes(?)', [`${mes}-01`]);
      const [org] = await poolETL.query('SELECT origem, COUNT(*) AS n FROM dado WHERE data_referencia = ? GROUP BY origem', [`${mes}-01`]);
      const n = Object.fromEntries(org.map((o) => [o.origem, o.n]));
      tocados.add(mes);
      etapa(`Mês novo ${rot(mes)}`, true, `${n.REAL || 0} oficiais do mês, ${n.DERIVADO || 0} oficiais do ano, ${n.ESTIMADO || 0} estimados (sem fonte oficial ainda)`);
    }

    // ---------- recalcula indicadores e o Data Warehouse dos meses que mudaram
    const meses = [...tocados].filter((m) => m <= limite).sort();
    for (const mes of meses) await poolETL.query('CALL sp_pipeline_mensal(?)', [`${mes}-01`]);
    etapa('Indicadores e Data Warehouse', true, meses.length ? `${meses.length} meses recalculados (${rot(meses[0])} a ${rot(meses[meses.length - 1])})` : 'nada mudou');

    // ---------- IA de alertas no último mês do painel
    const [[u]] = await poolETL.query("SELECT DATE_FORMAT(MAX(periodo), '%Y-%m') AS m FROM indicador_valor");
    exec.mes = u.m;
    if (meses.length) {
      const al = await ia.gerar(u.m);
      etapa('IA – alertas de risco', true, `${al.gravados} alertas novos em ${rot(u.m)}`);
    }
    exec.status = exec.etapas.every((e) => e.ok) ? 'SUCESSO' : 'PARCIAL';
    exec.resumo = meses.length ? `${meses.length} meses atualizados; painel até ${rot(u.m)}` : `nenhuma fonte publicou novidade; painel até ${rot(u.m)}`;
  } catch (e) {
    exec.status = 'FALHA';
    etapa('Erro geral', false, e.sqlMessage || e.message);
  } finally {
    rodando = false; atual = null;
    exec.fim = new Date().toISOString();
    historico.unshift(exec);
    historico.length = Math.min(historico.length, 20);
    console.log(`[coleta] ${exec.status}: ${exec.resumo || ''}`);
  }
  return exec;
}

// Agendador: com COLETA_AUTOMATICA=true confere as fontes a cada COLETA_INTERVALO_HORAS (padrão 24 h).
function iniciarAgendador() {
  const ligado = process.env.COLETA_AUTOMATICA === 'true';
  const horas = Number(process.env.COLETA_INTERVALO_HORAS || 24);
  const rodar = async () => {
    proximaVerificacao = new Date(Date.now() + horas * 3600_000).toISOString();
    if (ligado && !rodando) await atualizar({ origem: 'agendador' }).catch((e) => console.error('[coleta]', e.message));
  };
  // banco recém-instalado: roda a IA uma vez sobre o último mês que já está no banco
  setTimeout(async () => {
    try {
      const [[ia2]] = await poolETL.query('SELECT COUNT(*) AS n FROM analise_ia WHERE modelo_versao = ?', [ia.MODELO]);
      if (!ia2.n) {
        const [[u]] = await poolETL.query("SELECT DATE_FORMAT(MAX(periodo), '%Y-%m') AS m FROM indicador_valor");
        const r = await ia.gerar(u.m);
        console.log(`[coleta] IA de alertas rodou sobre ${u.m}: ${r.gravados} alertas novos`);
      }
    } catch (e) { console.error('[coleta] IA inicial:', e.message); }
  }, 10_000);
  if (!ligado) { console.log('[coleta] robô desligado (COLETA_AUTOMATICA=true no .env para ligar)'); return; }
  setTimeout(rodar, 60_000);
  setInterval(rodar, horas * 3600_000).unref();
  console.log(`[coleta] robô ligado: confere as fontes oficiais a cada ${horas} h (modo ${process.env.COLETA_MODO || 'mensal'})`);
}

async function status() {
  const [lotes] = await poolETL.query(`
    SELECT l.id_lote, f.nome AS fonte, l.status, l.registros_validos, l.registros_rejeitados, l.mensagem,
           DATE_FORMAT(l.iniciado_em, '%Y-%m-%d %H:%i') AS iniciado_em
    FROM lote_carga l JOIN fonte_dados f USING (id_fonte) ORDER BY l.id_lote DESC LIMIT 15`);
  const [meses] = await poolETL.query(`
    SELECT DATE_FORMAT(data_referencia, '%Y-%m') AS mes, SUM(origem='REAL') AS oficiais, SUM(origem='DERIVADO') AS derivados,
           SUM(origem='ESTIMADO') AS estimados FROM dado GROUP BY data_referencia ORDER BY data_referencia DESC LIMIT 6`);
  const [fontes] = await poolETL.query(`
    SELECT id_fonte, fonte, frequencia, endpoint_url, DATE_FORMAT(verificado_em, '%d/%m/%Y %H:%i') AS verificado_em, versao_fonte, status,
           registros_novos, mensagem, DATE_FORMAT(ultima_novidade, '%d/%m/%Y') AS ultima_novidade
    FROM vw_coleta_fontes WHERE id_fonte <> 2 AND id_fonte <> 6 ORDER BY id_fonte`);
  return {
    rodando, atual, automatica: process.env.COLETA_AUTOMATICA === 'true', modo: process.env.COLETA_MODO || 'mensal',
    intervalo_horas: Number(process.env.COLETA_INTERVALO_HORAS || 24), proxima: proximaVerificacao,
    historico, lotes, meses, fontes,
  };
}

module.exports = { atualizar, iniciarAgendador, status, mesAnterior };

// Linha de comando:  npm run coletar            (confere as fontes e grava o que mudou)
//                    npm run coletar -- --forcar (baixa tudo de novo, mesmo sem novidade)
if (require.main === module) {
  atualizar({ origem: 'linha de comando', forcar: process.argv.includes('--forcar') })
    .then((r) => {
      console.log(`\nResultado: ${r.status} — ${r.resumo || ''}`);
      for (const e of r.etapas) console.log(`${e.ok ? '✓' : '!'} ${e.nome}: ${e.detalhe}`);
      process.exit(0);
    })
    .catch((e) => { console.error(e.message); process.exit(1); });
}
