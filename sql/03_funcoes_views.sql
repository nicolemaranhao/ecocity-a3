-- =====================================================================
--  EcoCity — Script 03: funções e views (camada de consumo dos dashboards)
-- =====================================================================
USE ecocity;

DELIMITER $$

-- Normaliza o desempenho de um indicador em uma escala 0–100.
-- 100 = meta atingida/superada; cada 1% de distância da meta (no sentido
-- ruim) desconta 1,5 ponto. Ex.: 20% pior que a meta => score 70.
DROP FUNCTION IF EXISTS fn_score $$
CREATE FUNCTION fn_score(p_valor DECIMAL(14,4), p_meta DECIMAL(12,4), p_sentido VARCHAR(15))
RETURNS DECIMAL(5,2)
DETERMINISTIC NO SQL
BEGIN
  DECLARE v_desvio DECIMAL(12,4);   -- % de distância da meta no sentido ruim
  IF p_sentido = 'MAIOR_MELHOR' THEN
     SET v_desvio = (p_meta - p_valor) / p_meta * 100;
  ELSE
     SET v_desvio = (p_valor - p_meta) / p_meta * 100;
  END IF;
  RETURN ROUND(LEAST(100, GREATEST(0, 100 - 1.5 * GREATEST(v_desvio, 0))), 2);
END $$

-- Classificação textual do Índice EcoCity de Sustentabilidade (IES)
DROP FUNCTION IF EXISTS fn_classe_ies $$
CREATE FUNCTION fn_classe_ies(p_ies DECIMAL(5,2))
RETURNS VARCHAR(12)
DETERMINISTIC NO SQL
BEGIN
  RETURN CASE
    WHEN p_ies >= 85 THEN 'EXCELENTE'
    WHEN p_ies >= 70 THEN 'BOM'
    WHEN p_ies >= 55 THEN 'REGULAR'
    ELSE 'CRITICO'
  END;
END $$

-- Meta EM VIGOR de um indicador, numa cidade, num mês.
-- Prioridade: meta APROVADA específica da cidade > meta APROVADA padrão (todas as cidades)
-- > meta de referência da tabela indicador. Assim o histórico respeita a meta de cada época.
DROP FUNCTION IF EXISTS fn_meta_vigente $$
CREATE FUNCTION fn_meta_vigente(p_indicador SMALLINT UNSIGNED, p_municipio SMALLINT UNSIGNED, p_periodo DATE)
RETURNS DECIMAL(12,4)
READS SQL DATA
BEGIN
  DECLARE v DECIMAL(12,4);
  SELECT valor INTO v FROM meta
  WHERE id_indicador = p_indicador
    AND (id_municipio = p_municipio OR id_municipio IS NULL)
    AND status IN ('APROVADA','SUBSTITUIDA')
    AND vigencia_inicio <= p_periodo AND (vigencia_fim IS NULL OR vigencia_fim >= p_periodo)
  ORDER BY id_municipio IS NULL, vigencia_inicio DESC
  LIMIT 1;
  IF v IS NULL THEN SELECT meta INTO v FROM indicador WHERE id_indicador = p_indicador; END IF;
  RETURN v;
END $$

DELIMITER ;

-- 1) Desempenho de cada indicador por município e MÊS (comparado à meta em vigor naquele mês)
CREATE OR REPLACE VIEW vw_indicador_desempenho AS
SELECT x.*,
       CASE WHEN (x.sentido = 'MAIOR_MELHOR' AND x.valor >= x.meta)
              OR (x.sentido = 'MENOR_MELHOR' AND x.valor <= x.meta)
            THEN 1 ELSE 0 END                       AS atingiu_meta,
       fn_score(x.valor, x.meta, x.sentido)        AS score
FROM (
  SELECT iv.id_indicador_valor,
         i.id_indicador, i.codigo, i.nome           AS indicador,
         s.nome  AS servico,
         r.id_municipio, r.nome  AS municipio, r.regiao_metropolitana,
         iv.periodo, YEAR(iv.periodo) AS ano, MONTH(iv.periodo) AS mes,
         DATE_FORMAT(iv.periodo, '%Y-%m') AS ano_mes,
         iv.valor, iv.origem,
         fn_meta_vigente(i.id_indicador, r.id_municipio, iv.periodo) AS meta,
         u.sigla AS unidade, i.sentido, i.ods, i.peso_ies
  FROM indicador_valor iv
  JOIN indicador       i ON i.id_indicador = iv.id_indicador
  JOIN servico_publico s ON s.id_servico   = i.id_servico
  JOIN unidade_medida  u ON u.id_unidade   = i.id_unidade
  JOIN municipio       r ON r.id_municipio = iv.id_municipio
) AS x;

-- 2) Índice EcoCity de Sustentabilidade (IES) por município e mês
CREATE OR REPLACE VIEW vw_ies_municipio_mensal AS
SELECT id_municipio, municipio, regiao_metropolitana, periodo, ano_mes,
       ROUND(SUM(score * peso_ies) / SUM(peso_ies), 2) AS ies,
       SUM(atingiu_meta)                                AS metas_atingidas,
       COUNT(*)                                          AS total_indicadores,
       SUM(origem = 'REAL')                              AS indicadores_oficiais,
       SUM(origem = 'DERIVADO')                          AS indicadores_derivados,
       SUM(origem = 'ESTIMADO')                          AS indicadores_estimados
FROM vw_indicador_desempenho
GROUP BY id_municipio, municipio, regiao_metropolitana, periodo, ano_mes
-- só entram no índice os meses com os 8 indicadores calculados
HAVING COUNT(*) = (SELECT COUNT(*) FROM indicador);

-- 3) Ranking do último mês, com variação contra o mês anterior e contra o mesmo mês do ano passado
CREATE OR REPLACE VIEW vw_ies_ranking AS
WITH base AS (
  SELECT m.*,
         LAG(ies, 1)  OVER (PARTITION BY id_municipio ORDER BY periodo) AS ies_mes_anterior,
         LAG(ies, 12) OVER (PARTITION BY id_municipio ORDER BY periodo) AS ies_ano_anterior
  FROM vw_ies_municipio_mensal m
)
SELECT RANK() OVER (ORDER BY ies DESC) AS posicao,
       id_municipio, municipio, regiao_metropolitana, periodo, ano_mes, ies,
       fn_classe_ies(ies)                      AS classificacao,
       ROUND(ies - ies_mes_anterior, 2)        AS variacao_mes,
       ROUND(ies - ies_ano_anterior, 2)        AS variacao_12m,
       metas_atingidas, total_indicadores,
       indicadores_oficiais, indicadores_derivados, indicadores_estimados
FROM base
WHERE periodo = (SELECT MAX(periodo) FROM vw_ies_municipio_mensal);

-- 4) Painel do cidadão: linguagem simples, último mês, sinal verde/amarelo/vermelho
--    e comparação com o mesmo mês do ano passado (sem dados pessoais)
CREATE OR REPLACE VIEW vw_painel_cidadao AS
SELECT d.municipio, d.servico, d.codigo, d.indicador, d.ano_mes,
       ROUND(d.valor, 2) AS valor, d.unidade, d.meta,
       CASE WHEN d.atingiu_meta = 1 THEN 'VERDE'
            WHEN d.score >= 70     THEN 'AMARELO'
            ELSE 'VERMELHO' END AS sinal,
       CASE WHEN d.atingiu_meta = 1 THEN 'Dentro do ideal'
            WHEN d.score >= 70     THEN 'Um pouco longe do ideal'
            ELSE 'Precisa melhorar' END AS situacao,
       ROUND(a.valor, 2) AS valor_ano_passado,
       CASE WHEN a.valor IS NULL THEN 'Sem comparação'
            WHEN ABS(d.valor - a.valor) / NULLIF(a.valor, 0) < 0.02 THEN 'Igual ao ano passado'
            WHEN (d.sentido = 'MENOR_MELHOR' AND d.valor < a.valor)
              OR (d.sentido = 'MAIOR_MELHOR' AND d.valor > a.valor) THEN 'Melhor que no ano passado'
            ELSE 'Pior que no ano passado' END AS comparacao,
       CASE d.origem WHEN 'REAL' THEN 'Dado oficial'
                     WHEN 'DERIVADO' THEN 'Calculado a partir de dado oficial'
                     ELSE 'Valor estimado' END AS origem_do_dado
FROM vw_indicador_desempenho d
LEFT JOIN indicador_valor a
       ON a.id_indicador = d.id_indicador AND a.id_municipio = d.id_municipio
      AND a.periodo = DATE_SUB(d.periodo, INTERVAL 12 MONTH)
WHERE d.periodo = (SELECT MAX(periodo) FROM indicador_valor);

-- 5) Ações x Resultados (o que funcionou e o que precisa ser revisto)
CREATE OR REPLACE VIEW vw_acoes_resultados AS
SELECT a.id_acao, a.titulo, a.descricao, a.status, r.nome AS municipio,
       i.codigo AS indicador_alvo, i.nome AS indicador_nome, i.sentido,
       u.nome AS responsavel, a.orcamento, a.data_inicio, a.data_fim_prevista,
       a.id_analise,
       res.valor_antes, res.valor_depois, res.data_avaliacao, res.avaliacao,
       ROUND((res.valor_depois - res.valor_antes) / NULLIF(res.valor_antes,0) * 100, 2) AS variacao_pct,
       CASE
         WHEN res.id_resultado IS NULL THEN 'AGUARDANDO_AVALIACAO'
         WHEN ABS(res.valor_depois - res.valor_antes) / NULLIF(res.valor_antes,0) < 0.02 THEN 'ESTAVEL'
         WHEN (i.sentido = 'MENOR_MELHOR' AND res.valor_depois < res.valor_antes)
           OR (i.sentido = 'MAIOR_MELHOR' AND res.valor_depois > res.valor_antes) THEN 'MELHOROU'
         ELSE 'PIOROU'
       END AS efeito
FROM acao a
JOIN municipio r ON r.id_municipio = a.id_municipio
JOIN indicador i ON i.id_indicador = a.id_indicador_alvo
JOIN usuario   u ON u.id_usuario   = a.id_responsavel
LEFT JOIN resultado res ON res.id_acao = a.id_acao AND res.id_indicador = a.id_indicador_alvo;

-- 6) Qualidade e saúde das fontes de dados (governança)
CREATE OR REPLACE VIEW vw_qualidade_fontes AS
SELECT f.id_fonte, f.nome AS fonte, o.sigla AS orgao, s.nome AS servico,
       f.tipo_integracao, f.frequencia, f.confiabilidade, f.confiabilidade_motivo, f.ativa,
       COUNT(d.id_dado)                                            AS total_registros,
       ROUND(100 * SUM(d.qualidade = 'VALIDO') / NULLIF(COUNT(d.id_dado),0), 2) AS pct_validos,
       SUM(d.qualidade = 'SUSPEITO')                               AS suspeitos,
       SUM(d.origem = 'REAL')                                      AS registros_reais,
       SUM(d.origem = 'DERIVADO')                                  AS registros_derivados,
       SUM(d.origem = 'ESTIMADO')                                  AS registros_estimados,
       MAX(CASE WHEN d.origem = 'REAL' THEN d.data_referencia END) AS ultimo_mes_oficial,
       MAX(d.data_referencia)                                      AS ultimo_mes,
       (SELECT l.status FROM lote_carga l WHERE l.id_fonte = f.id_fonte
          ORDER BY l.iniciado_em DESC LIMIT 1)                     AS status_ultimo_lote
FROM fonte_dados f
JOIN orgao o           ON o.id_orgao   = f.id_orgao
JOIN servico_publico s ON s.id_servico = f.id_servico
LEFT JOIN dado d       ON d.id_fonte   = f.id_fonte
GROUP BY f.id_fonte, f.nome, o.sigla, s.nome, f.tipo_integracao, f.frequencia, f.confiabilidade, f.confiabilidade_motivo, f.ativa;

-- 7) Alertas/insights da IA ainda não resolvidos
CREATE OR REPLACE VIEW vw_alertas_abertos AS
SELECT a.id_analise, a.tipo, a.severidade, a.titulo, a.descricao, a.confianca,
       r.nome AS municipio, i.codigo AS indicador, s.nome AS servico, a.gerada_em, a.status
FROM analise_ia a
JOIN municipio r       ON r.id_municipio = a.id_municipio
JOIN indicador i       ON i.id_indicador = a.id_indicador
JOIN servico_publico s ON s.id_servico   = i.id_servico
WHERE a.status IN ('NOVA','EM_ANALISE')
ORDER BY FIELD(a.severidade,'CRITICO','ATENCAO','INFO'), a.gerada_em DESC;

-- 8) Tendência mensal por serviço (consulta direta no Data Warehouse)
CREATE OR REPLACE VIEW vw_dw_tendencia_servico AS
SELECT t.sk_tempo, t.ano_mes, t.rotulo, s.nome AS servico,
       ROUND(AVG(f.score), 2)                       AS score_medio,
       ROUND(100 * AVG(f.atingiu_meta), 1)          AS pct_metas_atingidas
FROM fato_indicador f
JOIN dim_tempo   t ON t.sk_tempo   = f.sk_tempo
JOIN dim_servico s ON s.sk_servico = f.sk_servico
GROUP BY t.sk_tempo, t.ano_mes, t.rotulo, s.nome;

-- 9) Visão consolidada das 8 cidades (ponderada pela população) por indicador e mês — DW
CREATE OR REPLACE VIEW vw_dw_cidade_indicador AS
SELECT t.sk_tempo, t.ano_mes, t.rotulo, di.codigo, di.nome, di.unidade, di.meta, di.sentido,
       ROUND(SUM(f.valor * r.populacao) / SUM(r.populacao), 4) AS valor_ponderado_pop,
       ROUND(AVG(f.score), 2) AS score_medio
FROM fato_indicador f
JOIN dim_tempo     t  ON t.sk_tempo      = f.sk_tempo
JOIN dim_indicador di ON di.sk_indicador = f.sk_indicador
JOIN dim_municipio r  ON r.sk_municipio  = f.sk_municipio
GROUP BY t.sk_tempo, t.ano_mes, t.rotulo, di.codigo, di.nome, di.unidade, di.meta, di.sentido;

-- 10) Transparência: quanto de cada métrica é oficial, derivado de oficial ou estimado
CREATE OR REPLACE VIEW vw_origem_dados AS
SELECT s.nome AS servico, me.codigo AS metrica, me.nome AS descricao,
       SUM(d.origem = 'REAL')     AS registros_reais,
       SUM(d.origem = 'DERIVADO') AS registros_derivados,
       SUM(d.origem = 'ESTIMADO') AS registros_estimados,
       ROUND(100 * SUM(d.origem = 'REAL') / COUNT(*), 1)                 AS pct_real,
       ROUND(100 * SUM(d.origem IN ('REAL','DERIVADO')) / COUNT(*), 1)   AS pct_base_oficial,
       DATE_FORMAT(MAX(CASE WHEN d.origem = 'REAL' THEN d.data_referencia END), '%Y-%m') AS ultimo_mes_oficial,
       MAX(d.referencia_origem)  AS exemplo_de_referencia
FROM dado d
JOIN metrica me        ON me.id_metrica = d.id_metrica
JOIN servico_publico s ON s.id_servico  = me.id_servico
GROUP BY s.nome, me.codigo, me.nome;

-- 11) Copiloto: relatórios aprovados (os de público CIDADAO aparecem no painel público)
CREATE OR REPLACE VIEW vw_relatorios_publicados AS
SELECT r.id_relatorio, r.titulo, r.tipo, r.publico,
       DATE_FORMAT(r.periodo_inicio, '%Y-%m') AS de, DATE_FORMAT(r.periodo_fim, '%Y-%m') AS ate,
       GROUP_CONCAT(m.nome ORDER BY m.nome SEPARATOR ', ') AS municipios,
       r.conteudo, r.pct_dados_oficiais, r.modelo, r.revisado_em,
       u.nome AS aprovado_por
FROM relatorio_ia r
JOIN relatorio_municipio rm ON rm.id_relatorio = r.id_relatorio
JOIN municipio m            ON m.id_municipio  = rm.id_municipio
JOIN usuario u              ON u.id_usuario    = r.revisado_por
WHERE r.status = 'APROVADO'
GROUP BY r.id_relatorio, r.titulo, r.tipo, r.publico, r.periodo_inicio, r.periodo_fim,
         r.conteudo, r.pct_dados_oficiais, r.modelo, r.revisado_em, u.nome;

-- 12) Copiloto: uso e segurança (quantas perguntas foram respondidas ou bloqueadas)
CREATE OR REPLACE VIEW vw_copiloto_uso AS
SELECT p.situacao, COUNT(*) AS perguntas,
       ROUND(AVG(p.tempo_ms)) AS tempo_medio_ms,
       MAX(p.criada_em) AS ultima
FROM pergunta_ia p
GROUP BY p.situacao;

-- 13) Metas: em vigor, propostas aguardando parecer/decisão e histórico
CREATE OR REPLACE VIEW vw_metas AS
SELECT m.id_meta, i.codigo, i.nome AS indicador, s.nome AS servico, u.sigla AS unidade, i.sentido,
       COALESCE(mu.nome, 'Todas as cidades') AS abrangencia,
       m.valor, m.vigencia_inicio, m.vigencia_fim, m.status,
       CASE WHEN m.status = 'APROVADA' AND m.vigencia_inicio <= CURRENT_DATE
                 AND (m.vigencia_fim IS NULL OR m.vigencia_fim >= CURRENT_DATE) THEN 1 ELSE 0 END AS em_vigor,
       m.justificativa, m.referencia,
       up.nome AS proposta_por, ua.nome AS parecer_por, m.parecer_favoravel, m.parecer,
       ud.nome AS aprovada_por, m.criada_em, m.decidida_em
FROM meta m
JOIN indicador i       ON i.id_indicador = m.id_indicador
JOIN servico_publico s ON s.id_servico   = i.id_servico
JOIN unidade_medida u  ON u.id_unidade   = i.id_unidade
LEFT JOIN municipio mu ON mu.id_municipio = m.id_municipio
JOIN usuario up        ON up.id_usuario  = m.proposta_por
LEFT JOIN usuario ua   ON ua.id_usuario  = m.parecer_por
LEFT JOIN usuario ud   ON ud.id_usuario  = m.aprovada_por;

-- 14) Análises dos analistas já PUBLICADAS (compartilhadas com analistas e gestores)
CREATE OR REPLACE VIEW vw_analises_publicadas AS
SELECT a.id_analise_pub, a.titulo, a.resumo, a.conteudo, s.nome AS servico,
       DATE_FORMAT(a.periodo_inicio, '%Y-%m') AS de, DATE_FORMAT(a.periodo_fim, '%Y-%m') AS ate,
       (SELECT GROUP_CONCAT(m.nome ORDER BY m.nome SEPARATOR ', ') FROM analise_municipio am
          JOIN municipio m USING (id_municipio) WHERE am.id_analise_pub = a.id_analise_pub) AS municipios,
       au.nome AS autor, c.nivel AS nivel_autor, c.orgao_vinculo,
       rv.nome AS revisado_por, a.parecer_revisao,
       a.nivel_confianca, a.pct_base_oficial, a.versao, a.publicada_em,
       (SELECT COUNT(*) FROM analise_evidencia e WHERE e.id_analise_pub = a.id_analise_pub) AS evidencias,
       (SELECT COUNT(*) FROM analise_comentario k WHERE k.id_analise_pub = a.id_analise_pub) AS comentarios
FROM analise_publicada a
JOIN servico_publico s ON s.id_servico = a.id_servico
JOIN usuario au ON au.id_usuario = a.id_autor
LEFT JOIN credencial_analista c ON c.id_usuario = a.id_autor
JOIN usuario rv ON rv.id_usuario = a.revisado_por
WHERE a.status = 'PUBLICADA';

-- 15) Fila de revisão: análises enviadas aguardando revisão por outra pessoa
CREATE OR REPLACE VIEW vw_fila_revisao_analises AS
SELECT a.id_analise_pub, a.titulo, a.resumo, s.nome AS servico, au.nome AS autor, c.nivel AS nivel_autor,
       a.nivel_confianca, a.pct_base_oficial, a.versao, a.enviada_em,
       TIMESTAMPDIFF(DAY, a.enviada_em, NOW()) AS dias_na_fila
FROM analise_publicada a
JOIN servico_publico s ON s.id_servico = a.id_servico
JOIN usuario au ON au.id_usuario = a.id_autor
LEFT JOIN credencial_analista c ON c.id_usuario = a.id_autor
WHERE a.status = 'EM_REVISAO'
ORDER BY a.enviada_em;

-- 16) Confiabilidade de cada analista: credencial + histórico de revisões
CREATE OR REPLACE VIEW vw_confiabilidade_analista AS
SELECT u.id_usuario, u.nome, c.orgao_vinculo, c.nivel, c.status AS credencial,
       COALESCE(s.nome, 'Todas') AS area, c.valida_ate,
       (c.status = 'VERIFICADA' AND c.valida_ate >= CURRENT_DATE) AS pode_publicar,
       SUM(a.status = 'PUBLICADA')  AS publicadas,
       SUM(a.status = 'DEVOLVIDA')  AS devolvidas,
       ROUND(100 * SUM(a.status = 'PUBLICADA') / NULLIF(SUM(a.status IN ('PUBLICADA','DEVOLVIDA')), 0), 1) AS taxa_aprovacao,
       u.mfa_ativo
FROM usuario u
JOIN perfil p ON p.id_perfil = u.id_perfil AND p.nome = 'ANALISTA'
LEFT JOIN credencial_analista c ON c.id_usuario = u.id_usuario
LEFT JOIN servico_publico s     ON s.id_servico = c.id_servico
LEFT JOIN analise_publicada a   ON a.id_autor   = u.id_usuario
GROUP BY u.id_usuario, u.nome, c.orgao_vinculo, c.nivel, c.status, s.nome, c.valida_ate, u.mfa_ativo;

-- V17: fila de cadastros profissionais para o ADMIN (sem CPF: só os 2 últimos dígitos)
CREATE OR REPLACE VIEW vw_cadastros_profissionais AS
SELECT u.id_usuario, u.nome, p.nome AS perfil_pedido, c.email_institucional, c.telefone_institucional,
       CONCAT('***.***.***-', c.cpf_final) AS cpf, c.orgao, c.cargo, c.matricula, c.formacao, c.registro_conselho,
       c.portaria_nomeacao, m.nome AS cidade_atuacao, c.documento_url, c.justificativa,
       DATE_FORMAT(c.aceite_termo_em, '%Y-%m-%d %H:%i') AS aceite_termo_em, c.status,
       a.nome AS analisado_por, DATE_FORMAT(c.analisado_em, '%Y-%m-%d') AS analisado_em, c.motivo_decisao, c.valido_ate,
       DATE_FORMAT(c.criado_em, '%Y-%m-%d') AS pedido_em, DATEDIFF(CURRENT_DATE, c.criado_em) AS dias_aguardando,
       (c.status = 'APROVADO' AND c.valido_ate < CURRENT_DATE + INTERVAL 30 DAY) AS vence_em_30_dias
FROM cadastro_profissional c
JOIN usuario u  ON u.id_usuario = c.id_usuario
JOIN perfil p   ON p.id_perfil  = u.id_perfil
LEFT JOIN municipio m ON m.id_municipio = c.id_municipio_atuacao
LEFT JOIN usuario a   ON a.id_usuario   = c.analisado_por;
