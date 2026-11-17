-- =====================================================================
--  EcoCity — Script 11: coleta automática mensal
--  O robô de coleta (backend/src/coleta) roda todo mês:
--    1) baixa os dados das fontes oficiais e grava no staging (sp_processar_staging);
--    2) o que a fonte ainda não publicou é ESTIMADO por esta procedure;
--    3) sp_pipeline_mensal calcula os indicadores e o Data Warehouse;
--    4) a IA gera os alertas de risco.
--  Quando o dado oficial sai depois, ele SUBSTITUI a estimativa (origem vira REAL).
-- =====================================================================
USE ecocity;

DELIMITER $$

-- ---------------------------------------------------------------------
-- sp_estimar_mes: preenche só o que está faltando no mês (cidade x métrica).
-- Regra (simples e explicável):
--   valor = mesmo mês do ano anterior x tendência dos últimos 3 meses
--           (soma dos 3 últimos meses / soma dos mesmos 3 meses do ano anterior),
--           com a tendência limitada entre -30% e +30%;
--   GD_POTENCIA é acumulada: último valor + 1/12 do crescimento dos últimos 12 meses.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_estimar_mes $$
CREATE PROCEDURE sp_estimar_mes(IN p_periodo DATE)
BEGIN
  DECLARE v_mes DATE DEFAULT DATE_FORMAT(p_periodo, '%Y-%m-01');
  DECLARE v_antes INT DEFAULT 0;

  IF v_mes > DATE_FORMAT(CURRENT_DATE, '%Y-%m-01') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Não é possível estimar um mês que ainda não começou.';
  END IF;

  SELECT COUNT(*) INTO v_antes FROM dado WHERE data_referencia = v_mes;

  INSERT INTO dado (id_fonte, id_municipio, id_metrica, data_referencia, valor, qualidade, origem, referencia_origem)
  SELECT e.id_fonte, e.id_municipio, e.id_metrica, v_mes, ROUND(e.valor, 4), 'VALIDO', 'ESTIMADO',
         CONCAT('Estimativa automática EcoCity (', DATE_FORMAT(v_mes, '%m/%Y'),
                '): mesmo mês do ano anterior x tendência dos últimos 3 meses')
  FROM (
    SELECT m.id_municipio, k.id_metrica,
           COALESCE(
             (SELECT d.id_fonte FROM dado d WHERE d.id_municipio = m.id_municipio AND d.id_metrica = k.id_metrica
               AND d.data_referencia < v_mes ORDER BY d.data_referencia DESC LIMIT 1),
             (SELECT f.id_fonte FROM fonte_dados f WHERE f.id_servico = k.id_servico ORDER BY f.confiabilidade DESC LIMIT 1)) AS id_fonte,
           CASE
             WHEN k.codigo = 'GD_POTENCIA' THEN
               u1.valor + GREATEST(0, u1.valor - u13.valor) / 12
             WHEN a12.valor IS NOT NULL AND t_ant.s > 0 THEN
               a12.valor * LEAST(1.3, GREATEST(0.7, t_rec.s / t_ant.s))
             WHEN a12.valor IS NOT NULL THEN a12.valor
             ELSE t_rec.s / NULLIF(t_rec.n, 0)
           END AS valor
    FROM municipio m
    CROSS JOIN metrica k
    LEFT JOIN dado a12 ON a12.id_municipio = m.id_municipio AND a12.id_metrica = k.id_metrica
                      AND a12.data_referencia = v_mes - INTERVAL 12 MONTH AND a12.qualidade <> 'REJEITADO'
    LEFT JOIN dado u1  ON u1.id_municipio = m.id_municipio AND u1.id_metrica = k.id_metrica
                      AND u1.data_referencia = v_mes - INTERVAL 1 MONTH AND u1.qualidade <> 'REJEITADO'
    LEFT JOIN dado u13 ON u13.id_municipio = m.id_municipio AND u13.id_metrica = k.id_metrica
                      AND u13.data_referencia = v_mes - INTERVAL 13 MONTH AND u13.qualidade <> 'REJEITADO'
    LEFT JOIN (SELECT id_municipio, id_metrica, SUM(valor) s, COUNT(*) n FROM dado
               WHERE data_referencia BETWEEN v_mes - INTERVAL 3 MONTH AND v_mes - INTERVAL 1 MONTH AND qualidade <> 'REJEITADO'
               GROUP BY id_municipio, id_metrica) t_rec ON t_rec.id_municipio = m.id_municipio AND t_rec.id_metrica = k.id_metrica
    LEFT JOIN (SELECT id_municipio, id_metrica, SUM(valor) s FROM dado
               WHERE data_referencia BETWEEN v_mes - INTERVAL 15 MONTH AND v_mes - INTERVAL 13 MONTH AND qualidade <> 'REJEITADO'
               GROUP BY id_municipio, id_metrica) t_ant ON t_ant.id_municipio = m.id_municipio AND t_ant.id_metrica = k.id_metrica
    WHERE NOT EXISTS (SELECT 1 FROM dado x WHERE x.id_municipio = m.id_municipio AND x.id_metrica = k.id_metrica
                        AND x.data_referencia = v_mes AND x.qualidade <> 'REJEITADO')
  ) e
  WHERE e.valor IS NOT NULL AND e.id_fonte IS NOT NULL;

  SELECT DATE_FORMAT(v_mes, '%Y-%m') AS mes,
         ROW_COUNT() AS estimados_agora,
         (SELECT COUNT(*) FROM dado WHERE data_referencia = v_mes AND origem = 'REAL') AS oficiais_no_mes,
         (SELECT COUNT(*) FROM dado WHERE data_referencia = v_mes) AS total_no_mes;
END $$

-- ---------------------------------------------------------------------
-- sp_trocar_estimativas_do_lote: antes de carregar um lote, apaga o valor antigo
-- do mesmo mês (cidade x métrica) que vai ser substituído por um MELHOR:
--   ESTIMADO sai quando chega DERIVADO ou REAL; DERIVADO sai quando chega REAL;
--   de outra fonte com a mesma qualidade, fica o que já estava.
-- Assim nunca ficam dois valores para o mesmo mês.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_trocar_estimativas_do_lote $$
CREATE PROCEDURE sp_trocar_estimativas_do_lote(IN p_id_lote INT UNSIGNED)
BEGIN
  DELETE d FROM dado d
  JOIN metrica   m ON m.id_metrica   = d.id_metrica
  JOIN municipio r ON r.id_municipio = d.id_municipio
  JOIN stg_medicao_bruta s ON s.id_lote = p_id_lote AND s.processado = FALSE
       AND UPPER(TRIM(s.codigo_metrica)) = m.codigo AND TRIM(s.nome_municipio) = r.nome
       AND s.data_texto REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
       AND d.data_referencia = DATE_FORMAT(s.data_texto, '%Y-%m-01')
  JOIN lote_carga l ON l.id_lote = p_id_lote
  WHERE d.id_fonte <> l.id_fonte
    AND (d.origem = 'ESTIMADO'
         OR FIELD(d.origem, 'ESTIMADO','DERIVADO','REAL') < FIELD(COALESCE(UPPER(s.origem_informada), 'REAL'), 'ESTIMADO','DERIVADO','REAL'));
  SELECT ROW_COUNT() AS estimativas_trocadas;
END $$

-- ---------------------------------------------------------------------
-- sp_registrar_verificacao: o robô anota cada conferência de fonte (v17).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_verificacao $$
CREATE PROCEDURE sp_registrar_verificacao(IN p_fonte SMALLINT UNSIGNED, IN p_versao VARCHAR(120),
  IN p_novos INT UNSIGNED, IN p_status VARCHAR(15), IN p_msg VARCHAR(255), IN p_lote INT UNSIGNED)
BEGIN
  DECLARE v_ult VARCHAR(120);
  SELECT versao_fonte INTO v_ult FROM coleta_verificacao
   WHERE id_fonte = p_fonte AND status <> 'FALHA' ORDER BY id_verificacao DESC LIMIT 1;
  INSERT INTO coleta_verificacao (id_fonte, versao_fonte, novidade, registros_novos, status, mensagem, id_lote)
  VALUES (p_fonte, p_versao, p_status <> 'FALHA' AND NOT (v_ult <=> p_versao), p_novos, p_status, LEFT(p_msg, 255), p_lote);
END $$

-- Painel do administrador: última verificação de cada fonte
DROP VIEW IF EXISTS vw_coleta_fontes $$
CREATE VIEW vw_coleta_fontes AS
SELECT f.id_fonte, f.nome AS fonte, f.frequencia, f.endpoint_url,
       v.verificado_em, v.versao_fonte, v.status, v.registros_novos, v.mensagem,
       (SELECT MAX(x.verificado_em) FROM coleta_verificacao x WHERE x.id_fonte = f.id_fonte AND x.novidade) AS ultima_novidade
FROM fonte_dados f
LEFT JOIN coleta_verificacao v ON v.id_verificacao =
     (SELECT MAX(y.id_verificacao) FROM coleta_verificacao y WHERE y.id_fonte = f.id_fonte) $$

DELIMITER ;

-- O robô de coleta usa o usuário ecocity_etl (papel r_etl): só o necessário para a carga.
GRANT EXECUTE ON PROCEDURE ecocity.sp_estimar_mes TO r_etl;
GRANT EXECUTE ON PROCEDURE ecocity.sp_trocar_estimativas_do_lote TO r_etl;
GRANT EXECUTE ON PROCEDURE ecocity.sp_registrar_verificacao TO r_etl;
GRANT SELECT ON ecocity.coleta_verificacao TO r_etl;
GRANT SELECT ON ecocity.vw_coleta_fontes   TO r_etl;
GRANT SELECT ON ecocity.populacao_anual    TO r_etl;
GRANT SELECT ON ecocity.lote_carga         TO r_etl;
GRANT SELECT ON ecocity.metrica              TO r_etl;
GRANT SELECT ON ecocity.fonte_dados          TO r_etl;
GRANT SELECT ON ecocity.dado                 TO r_etl;
GRANT SELECT ON ecocity.vw_indicador_desempenho  TO r_etl;
GRANT SELECT ON ecocity.vw_ies_municipio_mensal  TO r_etl;
GRANT SELECT ON ecocity.servico_publico      TO r_etl;
GRANT SELECT ON ecocity.meta                 TO r_etl;
