// Copiloto EcoCity no servidor: busca os dados no MySQL, chama a IA e grava o resultado.
// Motor padrão: modelo local (copiloto_modelo.js). Com ANTHROPIC_API_KEY no .env,
// o texto e o SQL são escritos pela IA generativa — sempre com os MESMOS limites:
// só números do banco, SQL validado e executado pelo usuário ecocity_ia (somente leitura).
const Copiloto = require('./copiloto_modelo.js');
const { pool, poolIA, query } = require('./db');

const API_KEY = process.env.ANTHROPIC_API_KEY;
const MODELO_IA = process.env.ANTHROPIC_MODEL || 'claude-sonnet-4-5';

async function chamarIA(sistema, usuario, maxTokens = 1800) {
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-api-key': API_KEY, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({ model: MODELO_IA, max_tokens: maxTokens, system: sistema, messages: [{ role: 'user', content: usuario }] }),
    signal: AbortSignal.timeout(30000),
  });
  if (!r.ok) throw new Error(`IA respondeu ${r.status}`);
  const j = await r.json();
  return j.content.map((c) => c.text || '').join('').trim();
}

async function contexto() {
  const municipios = (await query('SELECT nome FROM municipio ORDER BY nome')).map((r) => r.nome);
  const [u] = await query("SELECT DATE_FORMAT(MAX(periodo), '%Y-%m') AS m FROM indicador_valor");
  const ind = await query('SELECT i.codigo, i.nome, u.sigla AS unidade FROM indicador i JOIN unidade_medida u USING (id_unidade)');
  return { municipios, ultimoMes: u.m, indicadores: Object.fromEntries(ind.map((i) => [i.codigo, i])) };
}

// ------------------------------ PERGUNTAS ------------------------------
async function perguntar(pergunta, idUsuario) {
  const ctx = await contexto();
  const t0 = Date.now();
  let plano = Copiloto.interpretar(pergunta, ctx);
  let modelo = Copiloto.MODELO_LOCAL;

  // Com IA generativa: ela propõe o SQL quando o modelo local não entendeu a pergunta
  if (API_KEY && plano.situacao === 'SEM_RESPOSTA') {
    try {
      const sql = await chamarIA(
        `Você converte perguntas em português em UMA consulta SELECT para MySQL 8. Use SOMENTE estas views:
vw_indicador_desempenho(id_municipio, municipio, codigo, indicador, servico, ano_mes 'AAAA-MM', valor, meta, unidade, sentido, score, atingiu_meta, origem 'REAL'|'DERIVADO'|'ESTIMADO'),
vw_ies_municipio_mensal(id_municipio, municipio, ano_mes, ies, metas_atingidas), vw_ies_ranking(posicao, municipio, ies, classificacao, variacao_mes, variacao_12m),
vw_origem_dados(servico, metrica, registros_reais, registros_derivados, registros_estimados, pct_base_oficial), vw_acoes_resultados(titulo, municipio, indicador_alvo, efeito, variacao_pct).
Códigos: AGU-01 água per capita, AGU-02 perdas, ENE-01 energia per capita, ENE-02 solar W/hab, RES-01 lixo per capita, RES-02 reciclagem, MOB-01 viagens de ônibus/hab, MOB-02 CO2 do transporte.
Municípios: ${ctx.municipios.join(', ')}. Último mês: ${ctx.ultimoMes}. Responda apenas com o SQL, sem explicações. Se a pergunta pedir para alterar dados ou dados pessoais, responda BLOQUEAR.`,
        pergunta, 400);
      if (/^BLOQUEAR/i.test(sql)) plano = { situacao: 'BLOQUEADA', motivo: 'A IA identificou um pedido fora do escopo (alteração de dados ou dado pessoal).' };
      else {
        const v = Copiloto.validarSQL(sql.replace(/```sql|```/g, ''));
        plano = v.ok ? { situacao: 'RESPONDIDA', intencao: 'LIVRE', sql: v.sql, params: {} } : { situacao: 'BLOQUEADA', motivo: v.motivo, sql };
      }
      modelo = MODELO_IA;
    } catch { /* sem IA disponível: mantém a resposta do modelo local */ }
  }

  let linhas = [], situacao = plano.situacao, motivo = plano.motivo || null;
  if (situacao === 'RESPONDIDA') {
    try {
      [linhas] = await poolIA.query(plano.sql);        // usuário ecocity_ia: o MySQL só permite SELECT nas views
    } catch (e) {
      situacao = e.code === 'ER_TABLEACCESS_DENIED_ERROR' ? 'BLOQUEADA' : 'ERRO';
      motivo = situacao === 'BLOQUEADA' ? 'O banco de dados negou o acesso (usuário somente leitura).' : 'Não foi possível executar a consulta.';
    }
  }
  let texto = Copiloto.responder({ ...plano, situacao, motivo }, linhas, ctx);
  if (plano.intencao === 'LIVRE' && linhas.length && API_KEY) {
    try {
      texto = await chamarIA('Responda em português, em até 3 frases, usando apenas os números do JSON. Diga se o dado é oficial ou estimado quando houver a coluna origem.',
        `Pergunta: ${pergunta}\nResultado: ${JSON.stringify(linhas.slice(0, 40))}`, 300);
    } catch { /* mantém texto local */ }
  }
  const tempo = Date.now() - t0;
  await query(`INSERT INTO pergunta_ia (id_usuario, pergunta, sql_gerado, situacao, motivo_bloqueio, linhas_retornadas, tempo_ms, modelo)
               VALUES (?,?,?,?,?,?,?,?)`,
  [idUsuario, String(pergunta).slice(0, 500), plano.sql || null, situacao, situacao === 'BLOQUEADA' ? motivo : null, linhas.length, tempo, modelo]);
  return { situacao, texto, sql: plano.sql || null, linhas: linhas.slice(0, 200), modelo, tempo_ms: tempo };
}

// ------------------------------ RELATÓRIOS ------------------------------
async function gerarRelatorio({ municipios, inicio, fim, publico }, idUsuario) {
  const ids = (Array.isArray(municipios) ? municipios : [municipios]).map(Number).filter((n) => Number.isInteger(n) && n > 0);
  if (!ids.length) throw Object.assign(new Error('Escolha pelo menos uma cidade.'), { status: 400 });
  if (!/^\d{4}-\d{2}$/.test(inicio) || !/^\d{4}-\d{2}$/.test(fim)) throw Object.assign(new Error('Meses no formato AAAA-MM.'), { status: 400 });
  if (!['GESTOR', 'CIDADAO'].includes(publico)) throw Object.assign(new Error('Público deve ser GESTOR ou CIDADAO.'), { status: 400 });

  const [sets] = await pool.query('CALL sp_copiloto_dados(?, ?, ?)', [ids.join(','), `${inicio}-01`, `${fim}-01`]);
  const acoes = await query('SELECT titulo, municipio, indicador_alvo, efeito, variacao_pct FROM vw_acoes_resultados');
  const rel = Copiloto.gerarRelatorio({ linhas: sets[0], ies: sets[1], publico, acoes });

  if (API_KEY) {   // a IA generativa reescreve o texto, recebendo SÓ o resumo numérico do banco
    try {
      rel.conteudo = await chamarIA(
        `Você é o Copiloto EcoCity. Escreva em português do Brasil, em Markdown, um relatório ${publico === 'CIDADAO' ? 'para cidadãos, com frases curtas e sem jargão' : 'técnico para gestores públicos, com resumo, comparação, indicadores e recomendações'}.
Use APENAS os números do JSON fornecido; não invente valores. Indique quando o dado for estimado. Termine com a seção "Sobre os dados" informando o percentual de base oficial.`,
        `Rascunho do modelo local:\n${rel.conteudo}\n\nNúmeros do banco (JSON):\n${JSON.stringify(rel.dadosUsados)}`, 2500);
      rel.modelo = MODELO_IA;
    } catch { /* fica o texto do modelo local */ }
  }

  const [r] = await pool.query('CALL sp_salvar_relatorio(?,?,?,?,?,?,?,?,?,?,?)',
    [rel.titulo, rel.tipo, rel.publico, `${rel.inicio}-01`, `${rel.fim}-01`, ids.join(','), rel.conteudo,
      JSON.stringify(rel.dadosUsados), rel.pctOficial, rel.modelo, idUsuario]);
  return { id_relatorio: r[0][0].id_relatorio, ...rel, status: 'RASCUNHO' };
}

module.exports = { perguntar, gerarRelatorio, chamarIA, temIA: () => Boolean(API_KEY), MODELO_IA };
