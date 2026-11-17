-- =====================================================================
--  EcoCity — Script 05: stored procedures (ETL + regras) e eventos
--  Todas as procedures críticas usam TRANSAÇÕES com ROLLBACK em caso de erro.
-- =====================================================================
USE ecocity;

DELIMITER $$

-- ---------------------------------------------------------------------
-- P1: sp_processar_staging — valida os dados brutos de um lote e carrega
--     os registros válidos na tabela DADO (Extract -> Transform -> Load)
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_processar_staging $$
CREATE PROCEDURE sp_processar_staging(IN p_id_lote INT UNSIGNED)
BEGIN
  DECLARE v_fonte   SMALLINT UNSIGNED;
  DECLARE v_servico TINYINT UNSIGNED;
  DECLARE v_lidos, v_validos INT DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    UPDATE lote_carga SET status = 'FALHA', finalizado_em = NOW(),
           mensagem = 'Erro inesperado no processamento — transação desfeita'
     WHERE id_lote = p_id_lote;
    RESIGNAL;
  END;

  SELECT l.id_fonte, f.id_servico INTO v_fonte, v_servico
  FROM lote_carga l JOIN fonte_dados f ON f.id_fonte = l.id_fonte
  WHERE l.id_lote = p_id_lote;

  IF v_fonte IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lote inexistente.';
  END IF;

  START TRANSACTION;

  -- 1) Transformação/validação: marca o motivo de rejeição de cada linha
  UPDATE stg_medicao_bruta s
  LEFT JOIN metrica m ON m.codigo = UPPER(TRIM(s.codigo_metrica))
  LEFT JOIN municipio  r ON r.nome   = TRIM(s.nome_municipio)
  SET s.erro = CASE
       WHEN m.id_metrica IS NULL                         THEN 'Métrica desconhecida'
       WHEN m.id_servico <> v_servico                    THEN 'Métrica não pertence ao serviço da fonte'
       WHEN r.id_municipio  IS NULL                         THEN 'Município desconhecido'
       WHEN s.data_texto NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN 'Data em formato inválido (AAAA-MM-DD)'
       WHEN s.data_texto > DATE_FORMAT(CURRENT_DATE,'%Y-%m-%d') THEN 'Data no futuro'
       WHEN REPLACE(s.valor_texto, ',', '.') NOT REGEXP '^[0-9]+(\\.[0-9]+)?$' THEN 'Valor não numérico ou negativo'
       WHEN COALESCE(UPPER(s.origem_informada), 'REAL') NOT IN ('REAL','DERIVADO','ESTIMADO') THEN 'Origem inválida (use REAL, DERIVADO ou ESTIMADO)'
       -- não troca um dado melhor por um pior (ex.: oficial do mês por estimativa)
       WHEN EXISTS (SELECT 1 FROM dado x
                    WHERE x.id_municipio = r.id_municipio AND x.id_metrica = m.id_metrica
                      AND x.data_referencia = DATE_FORMAT(s.data_texto, '%Y-%m-01')
                      AND (FIELD(x.origem, 'ESTIMADO','DERIVADO','REAL') > FIELD(COALESCE(UPPER(s.origem_informada), 'REAL'), 'ESTIMADO','DERIVADO','REAL')
                           OR (x.id_fonte <> v_fonte AND x.origem <> 'ESTIMADO'
                               AND FIELD(x.origem, 'ESTIMADO','DERIVADO','REAL') = FIELD(COALESCE(UPPER(s.origem_informada), 'REAL'), 'ESTIMADO','DERIVADO','REAL'))))
            THEN 'Ignorado: o mês já tem dado igual ou melhor de outra fonte'
       ELSE NULL END
  WHERE s.id_lote = p_id_lote AND s.processado = FALSE;

  -- 2) Carga: insere (ou atualiza) os registros válidos
  INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem)
  SELECT v_fonte, r.id_municipio, m.id_metrica, p_id_lote,
         DATE_FORMAT(s.data_texto, '%Y-%m-01'),
         CAST(REPLACE(s.valor_texto, ',', '.') AS DECIMAL(16,4)),
         COALESCE(UPPER(s.origem_informada), 'REAL'),
         LEFT(COALESCE(s.referencia_informada, CONCAT('Carga oficial - lote ', p_id_lote)), 300)
  FROM stg_medicao_bruta s
  JOIN metrica m ON m.codigo = UPPER(TRIM(s.codigo_metrica))
  JOIN municipio  r ON r.nome   = TRIM(s.nome_municipio)
  WHERE s.id_lote = p_id_lote AND s.processado = FALSE AND s.erro IS NULL
  ON DUPLICATE KEY UPDATE valor = VALUES(valor), id_lote = VALUES(id_lote),
                          origem = VALUES(origem), referencia_origem = VALUES(referencia_origem);

  SELECT COUNT(*), COALESCE(SUM(erro IS NULL),0) INTO v_lidos, v_validos
  FROM stg_medicao_bruta WHERE id_lote = p_id_lote AND processado = FALSE;

  UPDATE stg_medicao_bruta SET processado = TRUE
  WHERE id_lote = p_id_lote AND processado = FALSE;

  UPDATE lote_carga
     SET registros_lidos      = v_lidos,
         registros_validos    = v_validos,
         registros_rejeitados = v_lidos - v_validos,
         finalizado_em        = NOW(),
         status   = CASE WHEN v_validos = 0 THEN 'FALHA'
                         WHEN v_validos < v_lidos THEN 'PARCIAL'
                         ELSE 'SUCESSO' END,
         mensagem = CONCAT(v_validos, ' de ', v_lidos, ' registros carregados')
   WHERE id_lote = p_id_lote;

  COMMIT;
END $$

-- ---------------------------------------------------------------------
-- P2: sp_calcular_indicadores — calcula os 8 indicadores de
--     sustentabilidade de todos os municípios em um MÊS.
--     Unidades das métricas: m³/mês, MWh/mês, kW instalados (acumulado), t/mês,
--     passageiros/mês, t CO2e/mês. População = estimativa IBGE do ano do mês.
--     Origem do indicador = a "pior" origem entre os dados usados
--     (ESTIMADO > DERIVADO > REAL).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_calcular_indicadores $$
CREATE PROCEDURE sp_calcular_indicadores(IN p_periodo DATE)
BEGIN
  DECLARE v_periodo DATE DEFAULT DATE_FORMAT(p_periodo, '%Y-%m-01');

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  INSERT INTO indicador_valor (id_indicador, id_municipio, periodo, valor, origem)
  SELECT x.id_indicador, x.id_municipio, x.periodo, x.valor, x.origem
  FROM (
    WITH m AS (     -- "pivot" das métricas do mês por município
      SELECT d.id_municipio, COALESCE(pa.populacao, r.populacao) AS populacao,
             DAY(LAST_DAY(v_periodo)) AS dias,
             SUM(CASE WHEN me.codigo = 'AGUA_PRODUZIDA'      THEN d.valor END) AS agua_prod,
             SUM(CASE WHEN me.codigo = 'AGUA_CONSUMIDA'      THEN d.valor END) AS agua_cons,
             SUM(CASE WHEN me.codigo = 'ENERGIA_CONSUMIDA'   THEN d.valor END) AS ener_cons,
             SUM(CASE WHEN me.codigo = 'GD_POTENCIA'         THEN d.valor END) AS gd_kw,
             SUM(CASE WHEN me.codigo = 'RESIDUOS_COLETADOS'  THEN d.valor END) AS res_col,
             SUM(CASE WHEN me.codigo = 'RESIDUOS_RECICLADOS' THEN d.valor END) AS res_rec,
             SUM(CASE WHEN me.codigo = 'TP_PASSAGEIROS'      THEN d.valor END) AS tp_pass,
             SUM(CASE WHEN me.codigo = 'CO2_TRANSPORTE'      THEN d.valor END) AS co2,
             -- nível de origem de cada métrica: 1 = REAL, 2 = DERIVADO, 3 = ESTIMADO
             MAX(CASE WHEN me.codigo = 'AGUA_PRODUZIDA'      THEN FIELD(d.origem,'REAL','DERIVADO','ESTIMADO') END) AS e_agua_prod,
             MAX(CASE WHEN me.codigo = 'AGUA_CONSUMIDA'      THEN FIELD(d.origem,'REAL','DERIVADO','ESTIMADO') END) AS e_agua_cons,
             MAX(CASE WHEN me.codigo = 'ENERGIA_CONSUMIDA'   THEN FIELD(d.origem,'REAL','DERIVADO','ESTIMADO') END) AS e_ener_cons,
             MAX(CASE WHEN me.codigo = 'GD_POTENCIA'         THEN FIELD(d.origem,'REAL','DERIVADO','ESTIMADO') END) AS e_gd_kw,
             MAX(CASE WHEN me.codigo = 'RESIDUOS_COLETADOS'  THEN FIELD(d.origem,'REAL','DERIVADO','ESTIMADO') END) AS e_res_col,
             MAX(CASE WHEN me.codigo = 'RESIDUOS_RECICLADOS' THEN FIELD(d.origem,'REAL','DERIVADO','ESTIMADO') END) AS e_res_rec,
             MAX(CASE WHEN me.codigo = 'TP_PASSAGEIROS'      THEN FIELD(d.origem,'REAL','DERIVADO','ESTIMADO') END) AS e_tp_pass,
             MAX(CASE WHEN me.codigo = 'CO2_TRANSPORTE'      THEN FIELD(d.origem,'REAL','DERIVADO','ESTIMADO') END) AS e_co2
      FROM dado d
      JOIN metrica me ON me.id_metrica = d.id_metrica
      JOIN municipio r ON r.id_municipio = d.id_municipio
      LEFT JOIN populacao_anual pa ON pa.id_municipio = d.id_municipio AND pa.ano = YEAR(v_periodo)
      WHERE d.data_referencia = v_periodo AND d.qualidade <> 'REJEITADO'
      GROUP BY d.id_municipio, COALESCE(pa.populacao, r.populacao)
    ),
    calc AS (
      SELECT 'AGU-01' cod, id_municipio, agua_cons * 1000 / populacao / dias AS valor, e_agua_cons AS est FROM m WHERE agua_cons IS NOT NULL
      UNION ALL SELECT 'AGU-02', id_municipio, (agua_prod - agua_cons) / agua_prod * 100, GREATEST(e_agua_prod, e_agua_cons) FROM m WHERE agua_prod > 0 AND agua_cons IS NOT NULL
      UNION ALL SELECT 'ENE-01', id_municipio, ener_cons * 1000 / populacao, e_ener_cons FROM m WHERE ener_cons IS NOT NULL      -- kWh/hab no mês
      UNION ALL SELECT 'ENE-02', id_municipio, gd_kw * 1000 / populacao, e_gd_kw FROM m WHERE gd_kw IS NOT NULL                -- W por habitante
      UNION ALL SELECT 'RES-01', id_municipio, res_col * 1000 / populacao / dias, e_res_col FROM m WHERE res_col IS NOT NULL
      UNION ALL SELECT 'RES-02', id_municipio, res_rec / res_col * 100, GREATEST(e_res_rec, e_res_col) FROM m WHERE res_col > 0 AND res_rec IS NOT NULL
      UNION ALL SELECT 'MOB-01', id_municipio, tp_pass / populacao, e_tp_pass FROM m WHERE tp_pass IS NOT NULL                   -- viagens/hab no mês
      UNION ALL SELECT 'MOB-02', id_municipio, co2 * 1000 / populacao, e_co2 FROM m WHERE co2 IS NOT NULL                       -- kg CO2e/hab no mês
    )
    SELECT i.id_indicador, c.id_municipio, v_periodo AS periodo,
           ROUND(GREATEST(c.valor, 0), 4) AS valor,
           ELT(c.est, 'REAL', 'DERIVADO', 'ESTIMADO') AS origem
    FROM calc c JOIN indicador i ON i.codigo = c.cod
  ) AS x
  ON DUPLICATE KEY UPDATE valor = x.valor, origem = x.origem, calculado_em = NOW();

  COMMIT;
END $$

-- ---------------------------------------------------------------------
-- P3: sp_carga_dw — atualiza dimensões e recarrega os fatos do período
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_carga_dw $$
CREATE PROCEDURE sp_carga_dw(IN p_periodo DATE)
BEGIN
  DECLARE v_periodo DATE DEFAULT DATE_FORMAT(p_periodo, '%Y-%m-01');
  DECLARE v_sk INT UNSIGNED DEFAULT YEAR(v_periodo) * 100 + MONTH(v_periodo);

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  -- Dimensão tempo
  INSERT IGNORE INTO dim_tempo (sk_tempo, data_inicio, ano, semestre, trimestre, mes, nome_mes, rotulo, ano_mes)
  VALUES (v_sk, v_periodo, YEAR(v_periodo), IF(MONTH(v_periodo) <= 6, 1, 2), QUARTER(v_periodo), MONTH(v_periodo),
          ELT(MONTH(v_periodo),'janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'),
          CONCAT(ELT(MONTH(v_periodo),'jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'), '/', YEAR(v_periodo)),
          DATE_FORMAT(v_periodo, '%Y-%m'));

  -- Dimensões (SCD tipo 1: sobrescreve atributos alterados)
  INSERT INTO dim_municipio (id_municipio_origem, nome, codigo_ibge, regiao_metropolitana, populacao, area_km2, densidade_hab_km2)
  SELECT id_municipio, nome, codigo_ibge, regiao_metropolitana, populacao, area_km2, ROUND(populacao / area_km2, 2) FROM municipio AS src
  ON DUPLICATE KEY UPDATE nome = src.nome, codigo_ibge = src.codigo_ibge, regiao_metropolitana = src.regiao_metropolitana, populacao = src.populacao,
                          area_km2 = src.area_km2, densidade_hab_km2 = ROUND(src.populacao / src.area_km2, 2);

  INSERT INTO dim_servico (id_servico_origem, nome)
  SELECT id_servico, nome FROM servico_publico AS src
  ON DUPLICATE KEY UPDATE nome = src.nome;

  INSERT INTO dim_metrica (id_metrica_origem, codigo, nome, unidade)
  SELECT m.id_metrica, m.codigo, m.nome, u.sigla
  FROM metrica m JOIN unidade_medida u ON u.id_unidade = m.id_unidade
  ON DUPLICATE KEY UPDATE codigo = m.codigo, nome = m.nome, unidade = u.sigla;

  INSERT INTO dim_indicador (id_indicador_origem, codigo, nome, unidade, sentido, meta, peso_ies, ods)
  SELECT i.id_indicador, i.codigo, i.nome, u.sigla, i.sentido, i.meta, i.peso_ies, i.ods
  FROM indicador i JOIN unidade_medida u ON u.id_unidade = i.id_unidade
  ON DUPLICATE KEY UPDATE nome = i.nome, unidade = u.sigla, sentido = i.sentido,
                          meta = i.meta, peso_ies = i.peso_ies, ods = i.ods;

  -- Fatos do período (recarga idempotente)
  DELETE FROM fato_medicao   WHERE sk_tempo = v_sk;
  DELETE FROM fato_indicador WHERE sk_tempo = v_sk;

  INSERT INTO fato_medicao (sk_tempo, sk_municipio, sk_metrica, sk_servico,
                            valor_total, valor_per_capita, qtd_registros, qtd_suspeitos, qtd_derivados, qtd_estimados)
  SELECT v_sk, dr.sk_municipio, dm.sk_metrica, ds.sk_servico,
         SUM(d.valor), SUM(d.valor) / COALESCE(MAX(pa.populacao), dr.populacao), COUNT(*), SUM(d.qualidade = 'SUSPEITO'), SUM(d.origem = 'DERIVADO'), SUM(d.origem = 'ESTIMADO')
  FROM dado d
  JOIN metrica     m  ON m.id_metrica         = d.id_metrica
  JOIN dim_municipio  dr ON dr.id_municipio_origem  = d.id_municipio
  JOIN dim_metrica dm ON dm.id_metrica_origem = d.id_metrica
  JOIN dim_servico ds ON ds.id_servico_origem = m.id_servico
  LEFT JOIN populacao_anual pa ON pa.id_municipio = d.id_municipio AND pa.ano = YEAR(v_periodo)
  WHERE d.data_referencia = v_periodo AND d.qualidade <> 'REJEITADO'
  GROUP BY dr.sk_municipio, dm.sk_metrica, ds.sk_servico, dr.populacao;

  INSERT INTO fato_indicador (sk_tempo, sk_municipio, sk_indicador, sk_servico, valor, meta, atingiu_meta, score, origem)
  SELECT v_sk, dr.sk_municipio, di.sk_indicador, ds.sk_servico, v.valor, v.meta, v.atingiu_meta, v.score, v.origem
  FROM vw_indicador_desempenho v
  JOIN indicador     i  ON i.id_indicador          = v.id_indicador
  JOIN dim_municipio    dr ON dr.id_municipio_origem     = v.id_municipio
  JOIN dim_indicador di ON di.id_indicador_origem  = v.id_indicador
  JOIN dim_servico   ds ON ds.id_servico_origem    = i.id_servico
  WHERE v.periodo = v_periodo;

  COMMIT;
END $$

-- ---------------------------------------------------------------------
-- P4: sp_pipeline_mensal — orquestra o processamento completo de um mês
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_pipeline_mensal $$
CREATE PROCEDURE sp_pipeline_mensal(IN p_periodo DATE)
BEGIN
  CALL sp_calcular_indicadores(p_periodo);
  CALL sp_carga_dw(p_periodo);
END $$

-- ---------------------------------------------------------------------
-- P5: sp_registrar_resultado — fecha uma ação medindo o indicador-alvo
--     ANTES (mês anterior ao início) e DEPOIS (último mês disponível até a avaliação)
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_resultado $$
CREATE PROCEDURE sp_registrar_resultado(
  IN p_id_acao INT UNSIGNED,
  IN p_data_avaliacao DATE,
  IN p_observacao VARCHAR(500),
  IN p_id_usuario INT UNSIGNED)
BEGIN
  DECLARE v_ind SMALLINT UNSIGNED;
  DECLARE v_reg SMALLINT UNSIGNED;
  DECLARE v_ini DATE;
  DECLARE v_sentido VARCHAR(15);
  DECLARE v_status VARCHAR(15);
  DECLARE v_antes, v_depois DECIMAL(14,4);
  DECLARE v_aval VARCHAR(10);

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  -- bloqueia a linha da ação durante o fechamento (controle de concorrência)
  SELECT a.id_indicador_alvo, a.id_municipio, a.data_inicio, i.sentido, a.status
    INTO v_ind, v_reg, v_ini, v_sentido, v_status
  FROM acao a JOIN indicador i ON i.id_indicador = a.id_indicador_alvo
  WHERE a.id_acao = p_id_acao
  FOR UPDATE;

  IF v_ind IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ação não encontrada.';
  END IF;
  IF v_status = 'CANCELADA' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ação cancelada não pode receber resultado.';
  END IF;

  SELECT valor INTO v_antes FROM indicador_valor
  WHERE id_indicador = v_ind AND id_municipio = v_reg
    AND periodo = DATE_FORMAT(DATE_SUB(v_ini, INTERVAL 1 MONTH), '%Y-%m-01');

  SELECT valor INTO v_depois FROM indicador_valor
  WHERE id_indicador = v_ind AND id_municipio = v_reg AND periodo <= p_data_avaliacao
  ORDER BY periodo DESC LIMIT 1;

  IF v_antes IS NULL OR v_depois IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Indicador sem medição antes/depois da ação.';
  END IF;

  -- variação menor que 2% é considerada neutra
  SET v_aval = CASE
    WHEN ABS(v_depois - v_antes) / v_antes < 0.02 THEN 'NEUTRO'
    WHEN (v_sentido = 'MENOR_MELHOR' AND v_depois < v_antes)
      OR (v_sentido = 'MAIOR_MELHOR' AND v_depois > v_antes) THEN 'POSITIVO'
    ELSE 'NEGATIVO' END;

  INSERT INTO resultado (id_acao, id_indicador, valor_antes, valor_depois,
                         data_avaliacao, avaliacao, observacao, registrado_por)
  VALUES (p_id_acao, v_ind, v_antes, v_depois, p_data_avaliacao, v_aval, p_observacao, p_id_usuario);

  UPDATE acao SET status = 'CONCLUIDA' WHERE id_acao = p_id_acao;

  COMMIT;

  SELECT v_antes AS valor_antes, v_depois AS valor_depois, v_aval AS avaliacao;
END $$

-- ---------------------------------------------------------------------
-- P6: sp_dashboard_municipio — retorna o "raio-x" de um município (API/BI)
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_dashboard_municipio $$
CREATE PROCEDURE sp_dashboard_municipio(IN p_id_municipio SMALLINT UNSIGNED)
BEGIN
  SELECT * FROM vw_ies_ranking WHERE id_municipio = p_id_municipio;

  SELECT codigo, indicador, servico, valor, meta, unidade, score, atingiu_meta, origem
  FROM vw_indicador_desempenho
  WHERE id_municipio = p_id_municipio
    AND periodo = (SELECT MAX(periodo) FROM vw_ies_municipio_mensal)
  ORDER BY score;

  SELECT * FROM vw_alertas_abertos WHERE municipio = (SELECT nome FROM municipio WHERE id_municipio = p_id_municipio);
END $$

-- ---------------------------------------------------------------------
-- P7: sp_atualizar_dado_real — troca um valor ESTIMADO/DERIVADO pelo valor
--     oficial do mês. Recalcula os indicadores e o DW daquele mês.
--     Exemplo:
--     CALL sp_atualizar_dado_real('Campinas', 2026, 3, 'AGUA_CONSUMIDA', 7012345, 'SANASA - relatório mensal mar/2026');
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_atualizar_dado_real $$
CREATE PROCEDURE sp_atualizar_dado_real(
  IN p_municipio VARCHAR(60), IN p_ano SMALLINT, IN p_mes TINYINT, IN p_metrica VARCHAR(30),
  IN p_valor DECIMAL(16,4), IN p_fonte VARCHAR(200))
BEGIN
  DECLARE v_mun SMALLINT UNSIGNED;
  DECLARE v_met SMALLINT UNSIGNED;
  DECLARE v_fonte SMALLINT UNSIGNED;
  DECLARE v_data DATE;

  IF p_mes NOT BETWEEN 1 AND 12 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Mês inválido (use 1 a 12).'; END IF;
  SET v_data = MAKEDATE(p_ano, 1) + INTERVAL (p_mes - 1) MONTH;

  SELECT id_municipio INTO v_mun FROM municipio WHERE nome = p_municipio;
  SELECT m.id_metrica, f.id_fonte INTO v_met, v_fonte
  FROM metrica m JOIN fonte_dados f ON f.id_servico = m.id_servico
  WHERE m.codigo = UPPER(p_metrica) ORDER BY f.id_fonte LIMIT 1;

  IF v_mun IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Município não encontrado (confira o nome).'; END IF;
  IF v_met IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Métrica não encontrada (veja a tabela metrica).'; END IF;
  IF p_valor < 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O valor não pode ser negativo.'; END IF;

  IF EXISTS (SELECT 1 FROM dado WHERE id_municipio = v_mun AND id_metrica = v_met AND data_referencia = v_data) THEN
    UPDATE dado SET valor = p_valor, origem = 'REAL', referencia_origem = p_fonte, qualidade = 'VALIDO'
    WHERE id_municipio = v_mun AND id_metrica = v_met AND data_referencia = v_data;
  ELSE
    INSERT INTO dado (id_fonte, id_municipio, id_metrica, data_referencia, valor, origem, referencia_origem)
    VALUES (v_fonte, v_mun, v_met, v_data, p_valor, 'REAL', p_fonte);
  END IF;

  CALL sp_pipeline_mensal(v_data);
  SELECT CONCAT(p_municipio, ' ', DATE_FORMAT(v_data, '%m/%Y'), ' - ', p_metrica, ' agora é OFICIAL (', p_fonte, ')') AS resultado;
END $$

-- ---------------------------------------------------------------------
-- P8: sp_copiloto_dados — entrega ao Copiloto EXATAMENTE os números que
--     ele pode usar num relatório: cidades escolhidas x intervalo de meses.
--     p_municipios = ids separados por vírgula (ex.: '1,2,7').
--     Retorna 2 conjuntos: (1) indicadores mês a mês; (2) IES mês a mês.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_copiloto_dados $$
CREATE PROCEDURE sp_copiloto_dados(IN p_municipios VARCHAR(100), IN p_inicio DATE, IN p_fim DATE)
BEGIN
  DECLARE v_ini DATE DEFAULT DATE_FORMAT(p_inicio, '%Y-%m-01');
  DECLARE v_fim DATE DEFAULT DATE_FORMAT(p_fim, '%Y-%m-01');

  IF p_municipios NOT REGEXP '^[0-9]+(,[0-9]+)*$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lista de municípios inválida (use ids separados por vírgula).';
  END IF;
  IF v_fim < v_ini THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O mês final deve ser igual ou posterior ao inicial.';
  END IF;
  IF TIMESTAMPDIFF(MONTH, v_ini, v_fim) > 35 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Escolha no máximo 36 meses por relatório.';
  END IF;

  SELECT id_municipio, municipio, codigo, indicador, servico, ano_mes, ROUND(valor, 4) AS valor,
         meta, unidade, sentido, score, atingiu_meta, origem
  FROM vw_indicador_desempenho
  WHERE FIND_IN_SET(id_municipio, p_municipios) AND periodo BETWEEN v_ini AND v_fim
  ORDER BY municipio, codigo, periodo;

  SELECT id_municipio, municipio, ano_mes, ies, metas_atingidas, indicadores_oficiais,
         indicadores_derivados, indicadores_estimados
  FROM vw_ies_municipio_mensal
  WHERE FIND_IN_SET(id_municipio, p_municipios) AND periodo BETWEEN v_ini AND v_fim
  ORDER BY municipio, periodo;
END $$

-- ---------------------------------------------------------------------
-- P9: sp_salvar_relatorio — grava o relatório da IA e as cidades dele
--     numa única TRANSAÇÃO (ou grava tudo, ou nada).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_salvar_relatorio $$
CREATE PROCEDURE sp_salvar_relatorio(
  IN p_titulo VARCHAR(200), IN p_tipo VARCHAR(12), IN p_publico VARCHAR(8),
  IN p_inicio DATE, IN p_fim DATE, IN p_municipios VARCHAR(100),
  IN p_conteudo MEDIUMTEXT, IN p_dados JSON, IN p_pct DECIMAL(5,2),
  IN p_modelo VARCHAR(60), IN p_usuario INT UNSIGNED)
BEGIN
  DECLARE v_id INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  IF p_municipios NOT REGEXP '^[0-9]+(,[0-9]+)*$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lista de municípios inválida.';
  END IF;

  START TRANSACTION;
  INSERT INTO relatorio_ia (titulo, tipo, publico, periodo_inicio, periodo_fim, conteudo,
                            dados_usados, pct_dados_oficiais, modelo, solicitado_por)
  VALUES (p_titulo, p_tipo, p_publico, DATE_FORMAT(p_inicio, '%Y-%m-01'), DATE_FORMAT(p_fim, '%Y-%m-01'),
          p_conteudo, p_dados, p_pct, p_modelo, p_usuario);
  SET v_id = LAST_INSERT_ID();

  INSERT INTO relatorio_municipio (id_relatorio, id_municipio)
  SELECT v_id, id_municipio FROM municipio WHERE FIND_IN_SET(id_municipio, p_municipios);

  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nenhum município válido no relatório.';
  END IF;
  COMMIT;
  SELECT v_id AS id_relatorio;
END $$

-- ---------------------------------------------------------------------
-- P10: sp_revisar_relatorio — aprovação humana do relatório da IA
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_revisar_relatorio $$
CREATE PROCEDURE sp_revisar_relatorio(IN p_id INT UNSIGNED, IN p_decisao VARCHAR(10),
                                      IN p_revisor INT UNSIGNED, IN p_comentario VARCHAR(500))
BEGIN
  IF p_decisao NOT IN ('APROVADO','REJEITADO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Decisão deve ser APROVADO ou REJEITADO.';
  END IF;
  UPDATE relatorio_ia
     SET status = p_decisao, revisado_por = p_revisor, comentario_revisao = p_comentario
   WHERE id_relatorio = p_id;
  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Relatório não encontrado.';
  END IF;
  SELECT id_relatorio, status, revisado_em FROM relatorio_ia WHERE id_relatorio = p_id;
END $$

-- =====================================================================
--  CONFIANÇA: login, credencial do analista, análises e metas
-- =====================================================================

-- Perfil de um usuário (ou NULL se não existir / estiver inativo)
DROP FUNCTION IF EXISTS fn_perfil $$
CREATE FUNCTION fn_perfil(p_usuario INT UNSIGNED) RETURNS VARCHAR(30)
READS SQL DATA
BEGIN
  DECLARE v VARCHAR(30);
  SELECT p.nome INTO v FROM usuario u JOIN perfil p USING (id_perfil) WHERE u.id_usuario = p_usuario AND u.ativo;
  RETURN v;
END $$

-- 1 se o analista tem credencial VERIFICADA, dentro da validade e da área (serviço) pedida
DROP FUNCTION IF EXISTS fn_analista_habilitado $$
CREATE FUNCTION fn_analista_habilitado(p_usuario INT UNSIGNED, p_servico TINYINT UNSIGNED) RETURNS BOOLEAN
READS SQL DATA
BEGIN
  RETURN EXISTS (SELECT 1 FROM credencial_analista
                 WHERE id_usuario = p_usuario AND status = 'VERIFICADA' AND valida_ate >= CURRENT_DATE
                   AND (id_servico IS NULL OR id_servico = p_servico))
         AND fn_perfil(p_usuario) = 'ANALISTA'
         AND (SELECT status_cadastro FROM usuario WHERE id_usuario = p_usuario) = 'ATIVO';
END $$

-- ---------------------------------------------------------------------
-- F: fn_cpf_valido — confere os 2 dígitos verificadores do CPF
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_cpf_valido $$
CREATE FUNCTION fn_cpf_valido(p_cpf VARCHAR(14)) RETURNS BOOLEAN
DETERMINISTIC
BEGIN
  DECLARE c VARCHAR(30) DEFAULT REGEXP_REPLACE(COALESCE(p_cpf, ''), '[^0-9]', '');
  DECLARE i, soma, d1, d2 INT DEFAULT 0;
  IF CHAR_LENGTH(c) <> 11 OR c REGEXP '^(.)\\1{10}$' THEN RETURN FALSE; END IF;   -- 111.111.111-11 etc. não vale
  SET soma = 0, i = 1;
  WHILE i <= 9 DO SET soma = soma + SUBSTRING(c, i, 1) * (11 - i); SET i = i + 1; END WHILE;
  SET d1 = IF(soma % 11 < 2, 0, 11 - soma % 11);
  SET soma = 0, i = 1;
  WHILE i <= 10 DO SET soma = soma + SUBSTRING(c, i, 1) * (12 - i); SET i = i + 1; END WHILE;
  SET d2 = IF(soma % 11 < 2, 0, 11 - soma % 11);
  RETURN d1 = SUBSTRING(c, 10, 1) AND d2 = SUBSTRING(c, 11, 1);
END $$

-- ---------------------------------------------------------------------
-- P10a: sp_cadastrar_cidadao — cadastro SIMPLES: nome, e-mail, telefone (opcional),
--       cidade e senha. Entra na hora, sem análise (só vê dados públicos).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_cadastrar_cidadao $$
CREATE PROCEDURE sp_cadastrar_cidadao(IN p_nome VARCHAR(100), IN p_email VARCHAR(120), IN p_telefone VARCHAR(20),
                                      IN p_municipio SMALLINT UNSIGNED, IN p_senha_hash CHAR(60))
BEGIN
  IF CHAR_LENGTH(TRIM(COALESCE(p_nome, ''))) < 3 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o nome.'; END IF;
  IF EXISTS (SELECT 1 FROM usuario WHERE email = LOWER(TRIM(p_email))) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este e-mail já tem cadastro.';
  END IF;
  INSERT INTO usuario (nome, email, telefone, senha_hash, id_perfil, id_municipio, status_cadastro)
  VALUES (TRIM(p_nome), LOWER(TRIM(p_email)), NULLIF(REGEXP_REPLACE(COALESCE(p_telefone, ''), '[^0-9]', ''), ''), p_senha_hash,
          (SELECT id_perfil FROM perfil WHERE nome = 'CIDADAO'), p_municipio, 'ATIVO');
  SELECT LAST_INSERT_ID() AS id_usuario, 'ATIVO' AS status_cadastro;
END $$

-- ---------------------------------------------------------------------
-- P10b: sp_solicitar_acesso — cadastro COMPLETO de ANALISTA ou GESTOR.
--       Fica EM_ANALISE (não entra no sistema) até o ADMIN conferir os documentos.
--       Regras: CPF válido e único; e-mail do ÓRGÃO (não aceita gmail, hotmail...);
--       telefone; cargo, matrícula, formação; documento de vínculo (link https);
--       justificativa (mín. 50 caracteres); aceite do termo de responsabilidade.
--       Analista: registro no conselho profissional. Gestor: portaria de nomeação e cidade.
--       ADMIN NÃO se cadastra por aqui (só o DBA cria, com chave individual).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_solicitar_acesso $$
CREATE PROCEDURE sp_solicitar_acesso(
  IN p_perfil VARCHAR(30), IN p_nome VARCHAR(100), IN p_cpf VARCHAR(14), IN p_email_inst VARCHAR(120),
  IN p_telefone VARCHAR(20), IN p_senha_hash CHAR(60), IN p_orgao VARCHAR(120), IN p_cargo VARCHAR(80),
  IN p_matricula VARCHAR(30), IN p_formacao VARCHAR(120), IN p_registro VARCHAR(40), IN p_portaria VARCHAR(120),
  IN p_municipio SMALLINT UNSIGNED, IN p_documento_url VARCHAR(300), IN p_justificativa VARCHAR(600),
  IN p_aceite_termo BOOLEAN, IN p_ip VARCHAR(45))
BEGIN
  DECLARE v_email VARCHAR(120) DEFAULT LOWER(TRIM(COALESCE(p_email_inst, '')));
  DECLARE v_cpf VARCHAR(30) DEFAULT REGEXP_REPLACE(COALESCE(p_cpf, ''), '[^0-9]', '');
  DECLARE v_tel VARCHAR(20) DEFAULT REGEXP_REPLACE(COALESCE(p_telefone, ''), '[^0-9]', '');
  DECLARE v_id INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF p_perfil NOT IN ('ANALISTA','GESTOR') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cadastro profissional só para ANALISTA ou GESTOR.';
  END IF;
  IF CHAR_LENGTH(TRIM(COALESCE(p_nome, ''))) < 5 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o nome completo.'; END IF;
  IF NOT fn_cpf_valido(v_cpf) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CPF inválido.'; END IF;
  IF EXISTS (SELECT 1 FROM cadastro_profissional WHERE cpf_hash = SHA2(v_cpf, 256)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Já existe um cadastro com este CPF.';
  END IF;
  IF v_email NOT LIKE '%_@_%._%'
     OR SUBSTRING_INDEX(v_email, '@', -1) IN ('gmail.com','hotmail.com','outlook.com','live.com','yahoo.com','yahoo.com.br',
                                               'icloud.com','bol.com.br','uol.com.br','terra.com.br','ig.com.br') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Use o e-mail institucional do órgão (e-mail pessoal não é aceito).';
  END IF;
  IF EXISTS (SELECT 1 FROM usuario WHERE email = v_email) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este e-mail já tem cadastro.'; END IF;
  IF v_tel NOT REGEXP '^[0-9]{10,11}$' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Telefone inválido (DDD + número).'; END IF;
  IF CHAR_LENGTH(TRIM(COALESCE(p_orgao,''))) < 3 OR CHAR_LENGTH(TRIM(COALESCE(p_cargo,''))) < 3
     OR CHAR_LENGTH(TRIM(COALESCE(p_matricula,''))) < 3 OR CHAR_LENGTH(TRIM(COALESCE(p_formacao,''))) < 5 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe órgão, cargo, matrícula e formação.';
  END IF;
  IF COALESCE(p_documento_url, '') NOT LIKE 'https://%' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Envie o link (https) da declaração de vínculo assinada pelo órgão.';
  END IF;
  IF CHAR_LENGTH(TRIM(COALESCE(p_justificativa, ''))) < 50 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Explique por que precisa do acesso (mínimo 50 caracteres).';
  END IF;
  IF NOT COALESCE(p_aceite_termo, FALSE) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'É preciso aceitar o termo de responsabilidade.';
  END IF;
  IF p_perfil = 'ANALISTA' AND CHAR_LENGTH(TRIM(COALESCE(p_registro, ''))) < 5 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Analista: informe o registro no conselho profissional (CREA, CRQ, CRBio, CORECON...).';
  END IF;
  IF p_perfil = 'GESTOR' AND (CHAR_LENGTH(TRIM(COALESCE(p_portaria, ''))) < 5 OR p_municipio IS NULL) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Gestor: informe a portaria de nomeação (Diário Oficial) e a cidade em que atua.';
  END IF;

  START TRANSACTION;
  INSERT INTO usuario (nome, email, telefone, senha_hash, id_perfil, id_municipio, status_cadastro)
  VALUES (TRIM(p_nome), v_email, v_tel, p_senha_hash, (SELECT id_perfil FROM perfil WHERE nome = p_perfil), p_municipio, 'EM_ANALISE');
  SET v_id = LAST_INSERT_ID();
  INSERT INTO cadastro_profissional (id_usuario, cpf_hash, cpf_final, email_institucional, telefone_institucional, orgao, cargo,
         matricula, formacao, registro_conselho, portaria_nomeacao, id_municipio_atuacao, documento_url, justificativa,
         aceite_termo_em, ip_aceite)
  VALUES (v_id, SHA2(v_cpf, 256), RIGHT(v_cpf, 2), v_email, v_tel, TRIM(p_orgao), TRIM(p_cargo), TRIM(p_matricula), TRIM(p_formacao),
          NULLIF(TRIM(p_registro), ''), NULLIF(TRIM(p_portaria), ''), p_municipio, p_documento_url, TRIM(p_justificativa), NOW(), p_ip);
  COMMIT;
  SELECT v_id AS id_usuario, 'EM_ANALISE' AS status_cadastro;
END $$

-- ---------------------------------------------------------------------
-- P10c: sp_analisar_cadastro — o ADMIN confere os documentos e aprova, recusa ou suspende.
--       Nunca o próprio cadastro. Aprovação vale no máximo 1 ano (revalidação).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_analisar_cadastro $$
CREATE PROCEDURE sp_analisar_cadastro(IN p_usuario INT UNSIGNED, IN p_admin INT UNSIGNED, IN p_decisao VARCHAR(10),
                                      IN p_motivo VARCHAR(300), IN p_valido_ate DATE)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  IF fn_perfil(p_admin) IS NULL OR fn_perfil(p_admin) <> 'ADMIN' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só o administrador analisa cadastros.';
  END IF;
  IF p_usuario = p_admin THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ninguém aprova o próprio cadastro.'; END IF;
  IF p_decisao NOT IN ('APROVADO','RECUSADO','SUSPENSO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Decisão deve ser APROVADO, RECUSADO ou SUSPENSO.';
  END IF;
  IF CHAR_LENGTH(TRIM(COALESCE(p_motivo, ''))) < 15 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Registre o que foi conferido ou o motivo (mínimo 15 caracteres).';
  END IF;
  IF p_decisao = 'APROVADO' AND (p_valido_ate IS NULL OR p_valido_ate <= CURRENT_DATE OR p_valido_ate > CURRENT_DATE + INTERVAL 1 YEAR) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A aprovação precisa de validade futura de até 1 ano.';
  END IF;
  START TRANSACTION;
  UPDATE cadastro_profissional
     SET status = p_decisao, analisado_por = p_admin, analisado_em = NOW(), motivo_decisao = p_motivo,
         valido_ate = IF(p_decisao = 'APROVADO', p_valido_ate, valido_ate)
   WHERE id_usuario = p_usuario;
  IF ROW_COUNT() = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cadastro profissional não encontrado.'; END IF;
  UPDATE usuario SET status_cadastro = CASE p_decisao WHEN 'APROVADO' THEN 'ATIVO' WHEN 'RECUSADO' THEN 'RECUSADO' ELSE 'SUSPENSO' END
   WHERE id_usuario = p_usuario;
  COMMIT;
  SELECT p_usuario AS id_usuario, p_decisao AS decisao;
END $$

-- ---------------------------------------------------------------------
-- P10d: sp_criar_admin / sp_trocar_chave_admin — SÓ o DBA executa (não a API).
--       Cada administrador tem uma CHAVE INDIVIDUAL (guardada como hash bcrypt),
--       exigida no login junto com a senha e o código do aplicativo.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_criar_admin $$
CREATE PROCEDURE sp_criar_admin(IN p_nome VARCHAR(100), IN p_email VARCHAR(120), IN p_senha_hash CHAR(60), IN p_chave_hash CHAR(60))
BEGIN
  IF COALESCE(p_chave_hash, '') NOT LIKE '$2%' OR COALESCE(p_senha_hash, '') NOT LIKE '$2%' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Senha e chave devem chegar como hash bcrypt (use: npm run hash).';
  END IF;
  INSERT INTO usuario (nome, email, senha_hash, id_perfil, status_cadastro, chave_admin_hash)
  VALUES (p_nome, LOWER(TRIM(p_email)), p_senha_hash, (SELECT id_perfil FROM perfil WHERE nome = 'ADMIN'), 'ATIVO', p_chave_hash);
  SELECT LAST_INSERT_ID() AS id_usuario;
END $$

DROP PROCEDURE IF EXISTS sp_trocar_chave_admin $$
CREATE PROCEDURE sp_trocar_chave_admin(IN p_admin INT UNSIGNED, IN p_chave_hash CHAR(60))
BEGIN
  IF fn_perfil(p_admin) IS NULL OR fn_perfil(p_admin) <> 'ADMIN' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Usuário não é administrador.'; END IF;
  IF COALESCE(p_chave_hash, '') NOT LIKE '$2%' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A chave deve chegar como hash bcrypt.'; END IF;
  UPDATE usuario SET chave_admin_hash = p_chave_hash, tentativas_falhas = 0, bloqueado_ate = NULL WHERE id_usuario = p_admin;
END $$

-- ---------------------------------------------------------------------
-- P11: sp_registrar_login — a API confere a senha (bcrypt), o código do
--      aplicativo autenticador (2ª etapa) e, para o ADMIN, a chave individual.
--      O BANCO decide e registra: cadastro ainda em análise, bloqueio de 15 min
--      após 5 erros, senha vencida, 2ª etapa obrigatória, chave do admin.
--      Retorna: resultado e se o usuário ainda precisa configurar a 2ª etapa.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_login $$
CREATE PROCEDURE sp_registrar_login(IN p_email VARCHAR(120), IN p_senha_ok BOOLEAN, IN p_mfa_ok BOOLEAN,
                                    IN p_chave_ok BOOLEAN, IN p_ip VARCHAR(45))
BEGIN
  DECLARE v_id INT UNSIGNED;
  DECLARE v_ativo, v_mfa_ativo, v_exige BOOLEAN;
  DECLARE v_bloq, v_alterada DATETIME;
  DECLARE v_validade SMALLINT;
  DECLARE v_perfil, v_status VARCHAR(30);
  DECLARE v_res VARCHAR(20);

  SELECT u.id_usuario, u.ativo, u.mfa_ativo, p.exige_mfa, u.bloqueado_ate, u.senha_alterada_em, p.validade_senha_dias, p.nome, u.status_cadastro
    INTO v_id, v_ativo, v_mfa_ativo, v_exige, v_bloq, v_alterada, v_validade, v_perfil, v_status
  FROM usuario u JOIN perfil p USING (id_perfil) WHERE u.email = LOWER(TRIM(p_email));

  SET v_res = CASE
    WHEN v_id IS NULL                              THEN 'SENHA_ERRADA'      -- não revela se o e-mail existe
    WHEN v_bloq IS NOT NULL AND v_bloq > NOW()     THEN 'BLOQUEADO'
    WHEN NOT v_ativo                               THEN 'INATIVO'
    WHEN NOT p_senha_ok                            THEN 'SENHA_ERRADA'
    WHEN v_status = 'EM_ANALISE'                   THEN 'CADASTRO_EM_ANALISE'
    WHEN v_status <> 'ATIVO'                       THEN 'INATIVO'           -- recusado ou suspenso
    WHEN v_exige AND v_mfa_ativo AND NOT p_mfa_ok  THEN 'CODIGO_MFA_ERRADO'
    WHEN v_perfil = 'ADMIN' AND NOT COALESCE(p_chave_ok, FALSE) THEN 'CHAVE_ADMIN_ERRADA'
    WHEN v_alterada + INTERVAL v_validade DAY < NOW() THEN 'SENHA_EXPIRADA'
    ELSE 'SUCESSO' END;

  IF v_id IS NOT NULL THEN
    IF v_res IN ('SENHA_ERRADA','CODIGO_MFA_ERRADO','CHAVE_ADMIN_ERRADA') THEN
      -- 5º erro seguido: bloqueia por 15 minutos e zera o contador
      UPDATE usuario SET bloqueado_ate = IF(tentativas_falhas + 1 >= 5, NOW() + INTERVAL 15 MINUTE, bloqueado_ate),
             tentativas_falhas = IF(tentativas_falhas + 1 >= 5, 0, tentativas_falhas + 1)
      WHERE id_usuario = v_id;
    ELSEIF v_res = 'SUCESSO' THEN
      UPDATE usuario SET tentativas_falhas = 0, bloqueado_ate = NULL, ultimo_acesso = NOW() WHERE id_usuario = v_id;
    END IF;
  END IF;

  INSERT INTO acesso_log (id_usuario, email_tentado, resultado, ip) VALUES (v_id, LEFT(p_email, 120), v_res, p_ip);
  SELECT v_res AS resultado, (v_res = 'SUCESSO' AND v_exige AND NOT v_mfa_ativo) AS precisa_configurar_mfa;
END $$

-- ---------------------------------------------------------------------
-- P12: sp_verificar_credencial — o ADMIN confere os documentos do analista
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_verificar_credencial $$
CREATE PROCEDURE sp_verificar_credencial(IN p_analista INT UNSIGNED, IN p_admin INT UNSIGNED,
                                         IN p_status VARCHAR(10), IN p_valida_ate DATE, IN p_obs VARCHAR(300))
BEGIN
  IF fn_perfil(p_admin) <> 'ADMIN' OR fn_perfil(p_admin) IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só o administrador verifica credenciais.';
  END IF;
  IF p_status NOT IN ('VERIFICADA','SUSPENSA','REVOGADA') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Situação deve ser VERIFICADA, SUSPENSA ou REVOGADA.';
  END IF;
  IF p_status = 'VERIFICADA' AND (p_valida_ate IS NULL OR p_valida_ate <= CURRENT_DATE OR p_valida_ate > CURRENT_DATE + INTERVAL 1 YEAR) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A validade deve ser uma data futura de até 1 ano.';
  END IF;
  UPDATE credencial_analista
     SET status = p_status, verificado_por = p_admin, verificado_em = NOW(),
         valida_ate = IF(p_status = 'VERIFICADA', p_valida_ate, valida_ate), observacao = p_obs
   WHERE id_usuario = p_analista;
  IF ROW_COUNT() = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este usuário não tem credencial cadastrada.'; END IF;
END $$

-- ---------------------------------------------------------------------
-- P12b: sp_avaliar_fonte — o ADMIN dá a nota de confiabilidade (1 a 5) de uma
--       fonte, dizendo qual critério aplicou (ver comentário em fonte_dados)
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_avaliar_fonte $$
CREATE PROCEDURE sp_avaliar_fonte(IN p_fonte SMALLINT UNSIGNED, IN p_admin INT UNSIGNED,
                                  IN p_nota TINYINT UNSIGNED, IN p_motivo VARCHAR(200))
BEGIN
  IF fn_perfil(p_admin) IS NULL OR fn_perfil(p_admin) <> 'ADMIN' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só o administrador avalia a confiabilidade das fontes.';
  END IF;
  IF p_nota NOT BETWEEN 1 AND 5 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A nota vai de 1 a 5.'; END IF;
  IF CHAR_LENGTH(TRIM(COALESCE(p_motivo, ''))) < 10 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o critério usado (mínimo 10 caracteres).';
  END IF;
  UPDATE fonte_dados SET confiabilidade = p_nota, confiabilidade_motivo = p_motivo, avaliada_por = p_admin, avaliada_em = NOW()
  WHERE id_fonte = p_fonte;
  IF ROW_COUNT() = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fonte não encontrada.'; END IF;
END $$

-- ---------------------------------------------------------------------
-- P13: sp_enviar_analise — o analista envia a análise para revisão.
--      Regras: só o autor; credencial verificada na área; texto com pelo
--      menos 300 caracteres; pelo menos 1 cidade e 1 evidência do banco.
--      O banco calcula o NÍVEL DE CONFIANÇA pela origem dos dados citados.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_enviar_analise $$
CREATE PROCEDURE sp_enviar_analise(IN p_id INT UNSIGNED, IN p_usuario INT UNSIGNED)
BEGIN
  DECLARE v_autor INT UNSIGNED;
  DECLARE v_status VARCHAR(12);
  DECLARE v_serv TINYINT UNSIGNED;
  DECLARE v_ini, v_fim DATE;
  DECLARE v_texto INT;
  DECLARE v_pct DECIMAL(5,2);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  START TRANSACTION;
  SELECT id_autor, status, id_servico, periodo_inicio, periodo_fim, CHAR_LENGTH(conteudo)
    INTO v_autor, v_status, v_serv, v_ini, v_fim, v_texto
  FROM analise_publicada WHERE id_analise_pub = p_id FOR UPDATE;

  IF v_autor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Análise não encontrada.'; END IF;
  IF v_autor <> p_usuario THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só o autor pode enviar a análise.'; END IF;
  IF v_status NOT IN ('RASCUNHO','DEVOLVIDA') THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A análise já foi enviada.'; END IF;
  IF NOT fn_analista_habilitado(p_usuario, v_serv) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Credencial de analista não verificada, vencida ou de outra área.';
  END IF;
  IF v_texto < 300 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A análise precisa de pelo menos 300 caracteres.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM analise_municipio WHERE id_analise_pub = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe pelo menos uma cidade.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM analise_evidencia WHERE id_analise_pub = p_id AND tipo IN ('INDICADOR','CONSULTA_SQL')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Inclua pelo menos uma evidência com dados do banco (indicador ou consulta).';
  END IF;

  -- % dos valores citados que têm base oficial (REAL ou DERIVADO) no período da análise
  SELECT ROUND(100 * SUM(iv.origem <> 'ESTIMADO') / COUNT(*), 2) INTO v_pct
  FROM analise_evidencia e
  JOIN indicador_valor iv ON iv.id_indicador = e.id_indicador AND iv.id_municipio = e.id_municipio
  WHERE e.id_analise_pub = p_id AND e.tipo = 'INDICADOR' AND iv.periodo BETWEEN v_ini AND v_fim;

  UPDATE analise_publicada
     SET status = 'EM_REVISAO', enviada_em = NOW(), pct_base_oficial = v_pct,
         nivel_confianca = CASE WHEN v_pct IS NULL THEN 'MEDIA' WHEN v_pct >= 70 THEN 'ALTA' WHEN v_pct >= 40 THEN 'MEDIA' ELSE 'BAIXA' END,
         versao = IF(v_status = 'DEVOLVIDA', versao + 1, versao), revisado_por = NULL, parecer_revisao = NULL
   WHERE id_analise_pub = p_id;
  COMMIT;
  SELECT id_analise_pub, status, nivel_confianca, pct_base_oficial, versao FROM analise_publicada WHERE id_analise_pub = p_id;
END $$

-- ---------------------------------------------------------------------
-- P14: sp_revisar_analise — revisão por pares antes de compartilhar.
--      Revisor: um GESTOR, ou um ANALISTA habilitado na área com nível
--      igual ou maior que o do autor. Nunca o próprio autor. Parecer obrigatório.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_revisar_analise $$
CREATE PROCEDURE sp_revisar_analise(IN p_id INT UNSIGNED, IN p_revisor INT UNSIGNED, IN p_decisao VARCHAR(10), IN p_parecer VARCHAR(1000))
BEGIN
  DECLARE v_autor INT UNSIGNED;
  DECLARE v_status VARCHAR(12);
  DECLARE v_serv TINYINT UNSIGNED;
  DECLARE v_perfil VARCHAR(30) DEFAULT fn_perfil(p_revisor);
  DECLARE v_niv_autor, v_niv_rev INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF p_decisao NOT IN ('PUBLICADA','DEVOLVIDA') THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Decisão deve ser PUBLICADA ou DEVOLVIDA.'; END IF;
  IF CHAR_LENGTH(TRIM(COALESCE(p_parecer, ''))) < 20 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Escreva um parecer de pelo menos 20 caracteres.'; END IF;

  START TRANSACTION;
  SELECT id_autor, status, id_servico INTO v_autor, v_status, v_serv FROM analise_publicada WHERE id_analise_pub = p_id FOR UPDATE;
  IF v_status IS NULL OR v_status <> 'EM_REVISAO' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A análise não está aguardando revisão.'; END IF;
  IF p_revisor = v_autor THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O autor não pode revisar a própria análise.'; END IF;

  IF v_perfil = 'ANALISTA' THEN
    SELECT FIELD(nivel,'JUNIOR','PLENO','SENIOR') INTO v_niv_autor FROM credencial_analista WHERE id_usuario = v_autor;
    SELECT FIELD(nivel,'JUNIOR','PLENO','SENIOR') INTO v_niv_rev   FROM credencial_analista WHERE id_usuario = p_revisor;
    IF NOT fn_analista_habilitado(p_revisor, v_serv) OR v_niv_rev < v_niv_autor THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O revisor precisa ser analista verificado da área e de nível igual ou maior que o do autor.';
    END IF;
  ELSEIF v_perfil IS NULL OR v_perfil NOT IN ('GESTOR') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só gestores ou analistas verificados revisam análises.';
  END IF;

  UPDATE analise_publicada
     SET status = p_decisao, revisado_por = p_revisor, parecer_revisao = p_parecer,
         publicada_em = IF(p_decisao = 'PUBLICADA', NOW(), NULL)
   WHERE id_analise_pub = p_id;
  COMMIT;
  SELECT id_analise_pub, status, nivel_confianca FROM analise_publicada WHERE id_analise_pub = p_id;
END $$

-- ---------------------------------------------------------------------
-- P15: sp_propor_meta — o GESTOR propõe uma meta (formulário "Nova meta").
--      Regras: sem vigência retroativa (começa no mês seguinte ou depois),
--      justificativa e referência técnica obrigatórias, valor plausível.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_propor_meta $$
CREATE PROCEDURE sp_propor_meta(IN p_gestor INT UNSIGNED, IN p_codigo VARCHAR(10), IN p_municipio SMALLINT UNSIGNED,
                                IN p_valor DECIMAL(12,4), IN p_inicio DATE, IN p_justificativa VARCHAR(600), IN p_referencia VARCHAR(200))
BEGIN
  DECLARE v_ind SMALLINT UNSIGNED;
  DECLARE v_ref DECIMAL(12,4);
  DECLARE v_ini DATE DEFAULT DATE_FORMAT(p_inicio, '%Y-%m-01');

  IF fn_perfil(p_gestor) IS NULL OR fn_perfil(p_gestor) <> 'GESTOR' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só gestores propõem metas.';
  END IF;
  SELECT id_indicador, meta INTO v_ind, v_ref FROM indicador WHERE codigo = p_codigo;
  IF v_ind IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Indicador não encontrado.'; END IF;
  IF v_ini < DATE_FORMAT(CURRENT_DATE + INTERVAL 1 MONTH, '%Y-%m-01') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A meta não pode valer para meses passados: comece no próximo mês ou depois.';
  END IF;
  IF p_valor <= 0 OR p_valor < v_ref * 0.2 OR p_valor > v_ref * 5 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Valor fora da faixa plausível para este indicador (entre 0,2x e 5x a meta de referência).';
  END IF;
  IF CHAR_LENGTH(TRIM(COALESCE(p_justificativa,''))) < 30 OR CHAR_LENGTH(TRIM(COALESCE(p_referencia,''))) < 3 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe a justificativa (mín. 30 caracteres) e a referência técnica.';
  END IF;
  INSERT INTO meta (id_indicador, id_municipio, valor, vigencia_inicio, justificativa, referencia, proposta_por)
  VALUES (v_ind, p_municipio, p_valor, v_ini, p_justificativa, p_referencia, p_gestor);
  SELECT LAST_INSERT_ID() AS id_meta, 'PROPOSTA' AS status;
END $$

-- ---------------------------------------------------------------------
-- P16: sp_parecer_meta — um ANALISTA verificado na área dá o parecer técnico
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_parecer_meta $$
CREATE PROCEDURE sp_parecer_meta(IN p_meta INT UNSIGNED, IN p_analista INT UNSIGNED, IN p_favoravel BOOLEAN, IN p_parecer VARCHAR(1000))
BEGIN
  DECLARE v_serv TINYINT UNSIGNED;
  DECLARE v_status VARCHAR(16);
  SELECT i.id_servico, m.status INTO v_serv, v_status FROM meta m JOIN indicador i USING (id_indicador) WHERE m.id_meta = p_meta;
  IF v_status IS NULL OR v_status <> 'PROPOSTA' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A meta não está aguardando parecer.'; END IF;
  IF NOT fn_analista_habilitado(p_analista, v_serv) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O parecer precisa ser de um analista com credencial verificada nesta área.';
  END IF;
  IF CHAR_LENGTH(TRIM(COALESCE(p_parecer,''))) < 30 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O parecer precisa de pelo menos 30 caracteres.'; END IF;
  UPDATE meta SET status = 'PARECER_EMITIDO', parecer_por = p_analista, parecer_favoravel = p_favoravel, parecer = p_parecer
  WHERE id_meta = p_meta;
  SELECT p_meta AS id_meta, 'PARECER_EMITIDO' AS status;
END $$

-- ---------------------------------------------------------------------
-- P17: sp_decidir_meta — um GESTOR (diferente de quem propôs) aprova ou rejeita.
--      Ao aprovar, a meta anterior da mesma cidade/indicador é encerrada
--      (fica no histórico como SUBSTITUIDA) numa única TRANSAÇÃO.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_decidir_meta $$
CREATE PROCEDURE sp_decidir_meta(IN p_meta INT UNSIGNED, IN p_gestor INT UNSIGNED, IN p_aprovar BOOLEAN)
BEGIN
  DECLARE v_status VARCHAR(16);
  DECLARE v_prop INT UNSIGNED;
  DECLARE v_ind SMALLINT UNSIGNED;
  DECLARE v_mun SMALLINT UNSIGNED;
  DECLARE v_ini DATE;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  START TRANSACTION;
  SELECT status, proposta_por, id_indicador, id_municipio, vigencia_inicio INTO v_status, v_prop, v_ind, v_mun, v_ini
  FROM meta WHERE id_meta = p_meta FOR UPDATE;
  IF v_status IS NULL OR v_status <> 'PARECER_EMITIDO' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A meta ainda não tem parecer técnico.'; END IF;
  IF fn_perfil(p_gestor) IS NULL OR fn_perfil(p_gestor) <> 'GESTOR' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só gestores decidem metas.'; END IF;
  IF p_gestor = v_prop THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quem propôs a meta não pode aprová-la (outro gestor decide).'; END IF;

  IF p_aprovar THEN
    UPDATE meta SET status = 'SUBSTITUIDA', vigencia_fim = v_ini - INTERVAL 1 DAY
    WHERE id_indicador = v_ind AND id_municipio <=> v_mun AND status = 'APROVADA' AND vigencia_fim IS NULL AND id_meta <> p_meta;
  END IF;
  UPDATE meta SET status = IF(p_aprovar, 'APROVADA', 'REJEITADA'), aprovada_por = IF(p_aprovar, p_gestor, NULL), decidida_em = NOW()
  WHERE id_meta = p_meta;
  COMMIT;
  SELECT p_meta AS id_meta, IF(p_aprovar, 'APROVADA', 'REJEITADA') AS status;
END $$

DELIMITER ;

-- ---------------------------------------------------------------------
-- EVENTO: todo dia 5, o pipeline processa o mês anterior (as fontes mensais
-- publicam os dados do mês fechado nos primeiros dias do mês seguinte).
-- (requer SET GLOBAL event_scheduler = ON;)
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS ev_pipeline_anual;
DROP EVENT IF EXISTS ev_pipeline_mensal;
CREATE EVENT ev_pipeline_mensal
  ON SCHEDULE EVERY 1 MONTH
  STARTS (DATE_FORMAT(CURRENT_DATE + INTERVAL 1 MONTH, '%Y-%m-05 02:00:00'))
  COMMENT 'Calcula indicadores e recarrega o DW do mês anterior'
  DO CALL sp_pipeline_mensal(DATE_SUB(CURRENT_DATE, INTERVAL 1 MONTH));
