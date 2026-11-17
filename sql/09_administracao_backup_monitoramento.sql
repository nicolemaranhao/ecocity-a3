-- =====================================================================
--  EcoCity — Script 09: administração, backup e monitoramento
--  Complementa o Plano de Segurança e Administração (docs/plano_seguranca.md)
-- =====================================================================
USE ecocity;

-- ------------------------------------------------------------------
-- 1. BACKUP (executar no shell / agendar via cron ou OCI)
-- ------------------------------------------------------------------
-- Backup lógico completo e consistente (sem travar tabelas InnoDB):
--   mysqldump -u ecocity_dba -p --single-transaction --routines --triggers \
--             --events --set-gtid-purged=OFF ecocity | gzip > ecocity_$(date +%F).sql.gz
--
-- Na OCI (MySQL HeatWave): backups automáticos diários com retenção de
-- 35 dias + PITR (point-in-time recovery) habilitado via binlog.
-- Cópia semanal do dump para o Object Storage (bucket com versionamento):
--   oci os object put -bn ecocity-backups --file ecocity_$(date +%F).sql.gz
--
-- Restauração (teste mensal obrigatório em ambiente de homologação):
--   gunzip < ecocity_2026-10-05.sql.gz | mysql -u ecocity_dba -p ecocity

-- Registro de execuções de backup (para auditoria do plano)
CREATE TABLE IF NOT EXISTS adm_backup_log (
  id_backup     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tipo          ENUM('COMPLETO','INCREMENTAL','BINLOG','TESTE_RESTAURACAO') NOT NULL,
  destino       VARCHAR(200) NOT NULL,
  tamanho_mb    DECIMAL(10,2) NULL,
  iniciado_em   DATETIME NOT NULL,
  finalizado_em DATETIME NULL,
  status        ENUM('SUCESSO','FALHA') NOT NULL,
  observacao    VARCHAR(255) NULL
) ENGINE=InnoDB;

INSERT INTO adm_backup_log (tipo, destino, tamanho_mb, iniciado_em, finalizado_em, status, observacao) VALUES
('COMPLETO', 'oci://ecocity-backups/ecocity_2026-10-05.sql.gz', 2.40, '2026-10-05 01:00:00', '2026-10-05 01:00:41', 'SUCESSO', 'Backup diário automático'),
('TESTE_RESTAURACAO', 'homologacao-mysql', NULL, '2026-10-06 10:00:00', '2026-10-06 10:03:12', 'SUCESSO', 'RTO medido: 3 min 12 s');

-- ------------------------------------------------------------------
-- 2. MONITORAMENTO DE DESEMPENHO
-- ------------------------------------------------------------------
-- 2.1 Plano de execução das consultas mais usadas (verifica uso de índices)
EXPLAIN SELECT * FROM vw_indicador_desempenho WHERE id_municipio = 2 AND periodo = '2024-12-01';
EXPLAIN FORMAT=TREE
SELECT r.regiao_metropolitana, SUM(f.valor_total) FROM fato_medicao f
JOIN dim_municipio r ON r.sk_municipio = f.sk_municipio
WHERE f.sk_metrica = 3 GROUP BY r.regiao_metropolitana;

-- 2.2 Tamanho de cada tabela (crescimento do banco)
SELECT table_name AS tabela, table_rows AS linhas_aprox,
       ROUND((data_length + index_length) / 1024, 1) AS tamanho_kb
FROM information_schema.tables
WHERE table_schema = 'ecocity' AND table_type = 'BASE TABLE'
ORDER BY (data_length + index_length) DESC;

-- 2.3 Consultas mais lentas / mais executadas (performance_schema)
SELECT LEFT(digest_text, 90) AS consulta, count_star AS execucoes,
       ROUND(avg_timer_wait / 1e9, 3) AS media_ms,
       ROUND(sum_rows_examined / NULLIF(count_star,0)) AS linhas_lidas_media
FROM performance_schema.events_statements_summary_by_digest
WHERE schema_name = 'ecocity'
ORDER BY avg_timer_wait DESC
LIMIT 10;

-- 2.4 Índices nunca utilizados (candidatos a remoção)
SELECT * FROM sys.schema_unused_indexes WHERE object_schema = 'ecocity';

-- 2.5 Conexões ativas e uso por usuário
SELECT user, host, db, command, time, state
FROM information_schema.processlist
WHERE db = 'ecocity';

-- 2.6 Saúde do ETL: fontes sem carga há mais de 35 dias (dados desatualizados)
SELECT f.nome, MAX(l.iniciado_em) AS ultima_carga,
       DATEDIFF(NOW(), MAX(l.iniciado_em)) AS dias_sem_carga
FROM fonte_dados f LEFT JOIN lote_carga l ON l.id_fonte = f.id_fonte
GROUP BY f.id_fonte, f.nome
HAVING ultima_carga IS NULL OR dias_sem_carga > 35;

-- ------------------------------------------------------------------
-- 3. MANUTENÇÃO
-- ------------------------------------------------------------------
ANALYZE TABLE dado, indicador_valor, fato_medicao, fato_indicador;   -- atualiza estatísticas

-- Expurgo da auditoria com mais de 5 anos (LGPD: retenção mínima necessária)
DELETE FROM auditoria WHERE ocorrido_em < DATE_SUB(NOW(), INTERVAL 5 YEAR);
-- Expurgo do staging já processado com mais de 90 dias
DELETE FROM stg_medicao_bruta WHERE processado = TRUE AND recebido_em < DATE_SUB(NOW(), INTERVAL 90 DAY);
