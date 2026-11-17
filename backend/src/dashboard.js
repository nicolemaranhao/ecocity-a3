// Monta os dados de cada perfil (usado pela API e pelo retrato offline data.js)
const { query } = require('./db');

const servicosSQL = 'SELECT id_servico, nome, descricao FROM servico_publico ORDER BY id_servico';
const indicadoresSQL = `
  SELECT i.id_indicador, i.codigo, i.nome, i.descricao, i.formula, i.meta, i.sentido, i.ods, i.peso_ies,
         s.nome AS servico, u.sigla AS unidade
  FROM indicador i JOIN servico_publico s USING (id_servico) JOIN unidade_medida u USING (id_unidade)
  ORDER BY i.codigo`;
const municipiosSQL = `
  SELECT m.id_municipio, m.nome, m.regiao_metropolitana, m.codigo_ibge, m.area_km2, m.latitude, m.longitude,
         p.populacao, p.ano AS ano_populacao
  FROM municipio m JOIN populacao_anual p ON p.id_municipio = m.id_municipio
  WHERE p.ano = (SELECT MAX(ano) FROM populacao_anual)
  ORDER BY m.id_municipio`;

async function base() {
  const [ult] = await query("SELECT DATE_FORMAT(MAX(periodo), '%Y-%m') AS m FROM indicador_valor");
  const meses = (await query("SELECT DISTINCT DATE_FORMAT(periodo, '%Y-%m') AS m FROM indicador_valor ORDER BY 1")).map((r) => r.m);
  return {
    geradoEm: new Date().toISOString(), ultimoMes: ult.m, meses,
    servicos: await query(servicosSQL), indicadores: await query(indicadoresSQL), municipios: await query(municipiosSQL),
    ranking: await query('SELECT * FROM vw_ies_ranking ORDER BY posicao'),
  };
}

// ---------------------------- CIDADÃO (público) ----------------------------
async function dadosCidadao() {
  const b = await base();
  return {
    ...b,
    painelCidadao: await query('SELECT * FROM vw_painel_cidadao ORDER BY municipio, codigo'),
    serie12: await query(`SELECT id_municipio AS m, codigo AS c, ano_mes AS p, ROUND(valor, 3) AS v, score AS s, origem AS o
                          FROM vw_indicador_desempenho
                          WHERE periodo > DATE_SUB((SELECT MAX(periodo) FROM indicador_valor), INTERVAL 12 MONTH)
                          ORDER BY id_municipio, codigo, periodo`),
    iesCidadao: await query(`SELECT id_municipio, ano_mes, ies FROM vw_ies_municipio_mensal
                             WHERE periodo >= DATE_SUB((SELECT MAX(periodo) FROM vw_ies_municipio_mensal), INTERVAL 12 MONTH)
                             ORDER BY periodo`),
    relatoriosPublicos: await query(`SELECT id_relatorio, titulo, de, ate, municipios, conteudo, pct_dados_oficiais,
                                     DATE_FORMAT(revisado_em, '%Y-%m-%d') AS revisado_em, aprovado_por
                                     FROM vw_relatorios_publicados WHERE publico = 'CIDADAO' ORDER BY revisado_em DESC`),
    origemDados: await query('SELECT * FROM vw_origem_dados ORDER BY servico, metrica'),
    metasEmVigor: await query(`SELECT codigo, indicador, abrangencia, valor, unidade, DATE_FORMAT(vigencia_inicio,'%Y-%m') AS desde
                               FROM vw_metas WHERE em_vigor = 1 ORDER BY codigo, abrangencia`),
  };
}

// ------------------------- ANALISTA e GESTOR -------------------------
async function dadosAnalise() {
  const b = await base();
  const serie = (await query(`
      SELECT id_municipio AS m, codigo AS c, ano_mes AS p, ROUND(valor, 4) AS v, score AS s, atingiu_meta AS a, origem AS o
      FROM vw_indicador_desempenho ORDER BY periodo, id_municipio, codigo`));
  const ies = await query(`SELECT id_municipio AS m, ano_mes AS p, ies, indicadores_oficiais AS ofi,
                                  indicadores_derivados AS der, indicadores_estimados AS est
                           FROM vw_ies_municipio_mensal ORDER BY periodo`);
  return {
    ...b, serie, ies,
    painelCidadao: await query('SELECT * FROM vw_painel_cidadao ORDER BY municipio, codigo'),
    tendenciaServico: await query('SELECT ano_mes, rotulo, servico, score_medio, pct_metas_atingidas FROM vw_dw_tendencia_servico ORDER BY sk_tempo'),
    alertas: await query(`
      SELECT a.id_analise, a.tipo, a.severidade, a.titulo, a.descricao, a.confianca, a.status, a.modelo_versao,
             DATE_FORMAT(a.gerada_em,'%Y-%m-%d %H:%i') AS gerada_em, r.nome AS municipio, i.codigo AS indicador, s.nome AS servico
      FROM analise_ia a JOIN municipio r USING (id_municipio) JOIN indicador i USING (id_indicador)
      JOIN servico_publico s ON s.id_servico = i.id_servico
      ORDER BY FIELD(a.status,'NOVA','EM_ANALISE','VALIDADA','DESCARTADA'), FIELD(a.severidade,'CRITICO','ATENCAO','INFO'), a.gerada_em DESC`),
    acoes: await query('SELECT * FROM vw_acoes_resultados ORDER BY data_inicio'),
    fontes: await query('SELECT * FROM vw_qualidade_fontes ORDER BY servico, fonte'),
    origemDados: await query('SELECT * FROM vw_origem_dados ORDER BY servico, metrica'),
    relatorios: await query(`
      SELECT r.id_relatorio, r.titulo, r.tipo, r.publico, DATE_FORMAT(r.periodo_inicio,'%Y-%m') AS de, DATE_FORMAT(r.periodo_fim,'%Y-%m') AS ate,
             (SELECT GROUP_CONCAT(m.nome ORDER BY m.nome SEPARATOR ', ') FROM relatorio_municipio rm JOIN municipio m USING (id_municipio)
               WHERE rm.id_relatorio = r.id_relatorio) AS municipios,
             r.conteudo, r.pct_dados_oficiais, r.modelo, r.status, s.nome AS solicitado_por, v.nome AS revisado_por,
             r.comentario_revisao, DATE_FORMAT(r.criado_em,'%Y-%m-%d %H:%i') AS criado_em, DATE_FORMAT(r.revisado_em,'%Y-%m-%d %H:%i') AS revisado_em
      FROM relatorio_ia r JOIN usuario s ON s.id_usuario = r.solicitado_por LEFT JOIN usuario v ON v.id_usuario = r.revisado_por
      ORDER BY r.criado_em DESC`),
    perguntas: await query(`
      SELECT p.pergunta, p.situacao, p.motivo_bloqueio, p.sql_gerado, p.linhas_retornadas, p.tempo_ms, p.modelo,
             u.nome AS usuario, DATE_FORMAT(p.criada_em,'%Y-%m-%d %H:%i') AS criada_em
      FROM pergunta_ia p JOIN usuario u USING (id_usuario) ORDER BY p.criada_em DESC LIMIT 40`),
  };
}

// ------------------------------ ADMIN ------------------------------
const TABELAS = [
  ['stg_medicao_bruta', 'Staging'], ['lote_carga', 'Staging'],
  ['municipio', 'Core'], ['populacao_anual', 'Core'], ['orgao', 'Core'], ['fonte_dados', 'Core'], ['metrica', 'Core'],
  ['dado', 'Core'], ['indicador', 'Core'], ['indicador_valor', 'Core'], ['analise_ia', 'Core'], ['acao', 'Core'],
  ['resultado', 'Core'], ['perfil', 'Core'], ['usuario', 'Core'], ['auditoria', 'Core'],
  ['relatorio_ia', 'Copiloto'], ['relatorio_municipio', 'Copiloto'], ['pergunta_ia', 'Copiloto'],
  ['dim_tempo', 'Data Warehouse'], ['dim_municipio', 'Data Warehouse'], ['dim_metrica', 'Data Warehouse'],
  ['dim_indicador', 'Data Warehouse'], ['dim_servico', 'Data Warehouse'], ['fato_medicao', 'Data Warehouse'], ['fato_indicador', 'Data Warehouse'],
];

async function dadosAdmin() {
  const banco = [];
  for (const [t, camada] of TABELAS) {
    try {
      const col = t === 'usuario' ? 'id_usuario' : '*';
      const [r] = await query(`SELECT COUNT(${col}) AS n FROM ${t}`);   // nomes fixos da lista acima (sem entrada do usuário)
      banco.push({ tabela: t, camada, linhas: r.n });
    } catch { banco.push({ tabela: t, camada, linhas: null }); }
  }
  return {
    banco,
    usuarios: await query(`
      SELECT u.nome, u.email, p.nome AS perfil, m.nome AS municipio, u.ativo,
             DATE_FORMAT(u.criado_em,'%Y-%m-%d') AS criado_em, DATE_FORMAT(u.ultimo_acesso,'%Y-%m-%d %H:%i') AS ultimo_acesso
      FROM usuario u JOIN perfil p USING (id_perfil) LEFT JOIN municipio m ON m.id_municipio = u.id_municipio ORDER BY p.id_perfil DESC, u.nome`),
    auditoria: await query(`SELECT DATE_FORMAT(ocorrido_em,'%Y-%m-%d %H:%i:%s') AS ocorrido_em, usuario_bd, tabela, operacao, id_registro,
                                   dados_antigos, dados_novos FROM auditoria ORDER BY ocorrido_em DESC LIMIT 25`),
    lotes: await query(`
      SELECT l.id_lote, f.nome AS fonte, l.status, l.registros_lidos, l.registros_validos, l.registros_rejeitados, l.mensagem,
             DATE_FORMAT(l.iniciado_em,'%Y-%m-%d %H:%i') AS iniciado_em
      FROM lote_carga l JOIN fonte_dados f USING (id_fonte) ORDER BY l.iniciado_em DESC, l.id_lote DESC`),
    rejeitados: await query('SELECT id_lote, codigo_metrica, nome_municipio, data_texto, valor_texto, erro FROM stg_medicao_bruta WHERE erro IS NOT NULL'),
    copilotoUso: await query('SELECT * FROM vw_copiloto_uso'),
  };
}

module.exports = { dadosCidadao, dadosAnalise, dadosAdmin };
