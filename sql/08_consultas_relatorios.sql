-- =====================================================================
--  EcoCity — Script 08: consultas para relatórios e dashboards (dados mensais)
--  Troque as variáveis abaixo para escolher cidades e meses.
-- =====================================================================
USE ecocity;

SET @inicio = '2024-01-01';     -- mês inicial do relatório
SET @fim    = '2024-12-01';     -- mês final do relatório
SET @cidades = '1,2,7';         -- ids dos municípios (1 = São Paulo, 2 = Campinas, 7 = Ribeirão Preto...)

-- R1. Ranking do último mês pelo Índice EcoCity (IES), com variação no mês e em 12 meses
SELECT posicao, municipio, ano_mes, ies, classificacao, variacao_mes, variacao_12m,
       CONCAT(metas_atingidas, '/', total_indicadores) AS metas,
       CONCAT(indicadores_oficiais, ' oficiais, ', indicadores_derivados, ' calculados, ', indicadores_estimados, ' estimados') AS base_de_dados
FROM vw_ies_ranking
ORDER BY posicao;

-- R2. Evolução mensal do IES das 8 cidades (média ponderada pela população do ano)
SELECT m.ano_mes,
       ROUND(SUM(m.ies * p.populacao) / SUM(p.populacao), 2) AS ies_ponderado
FROM vw_ies_municipio_mensal m
JOIN populacao_anual p ON p.id_municipio = m.id_municipio AND p.ano = YEAR(m.periodo)
GROUP BY m.ano_mes
ORDER BY m.ano_mes;

-- R3. Relatório por CIDADES e INTERVALO DE MESES escolhidos: média de cada indicador no período
SELECT municipio, codigo, indicador, unidade, meta,
       ROUND(AVG(valor), 2)                              AS media_no_periodo,
       ROUND(MIN(valor), 2) AS minimo, ROUND(MAX(valor), 2) AS maximo,
       SUM(atingiu_meta)                                 AS meses_na_meta,
       COUNT(*)                                          AS meses,
       ROUND(100 * SUM(origem <> 'ESTIMADO') / COUNT(*)) AS pct_base_oficial
FROM vw_indicador_desempenho
WHERE FIND_IN_SET(id_municipio, @cidades) AND periodo BETWEEN @inicio AND @fim
GROUP BY municipio, codigo, indicador, unidade, meta
ORDER BY codigo, media_no_periodo;

-- R4. Indicadores fora da meta no último mês (prioridades de ação)
SELECT municipio, servico, codigo, indicador, ROUND(valor,2) AS valor, meta, unidade, score, origem
FROM vw_indicador_desempenho
WHERE periodo = (SELECT MAX(periodo) FROM vw_ies_municipio_mensal)
  AND atingiu_meta = 0
ORDER BY score ASC
LIMIT 15;

-- R5. Comparação entre serviços mês a mês (Data Warehouse)
SELECT servico, rotulo AS mes, score_medio, pct_metas_atingidas
FROM vw_dw_tendencia_servico
ORDER BY servico, sk_tempo;

-- R6. Visão integrada: todos os serviços lado a lado por município no último mês (pivot)
SELECT municipio,
       MAX(CASE WHEN codigo = 'AGU-01' THEN ROUND(valor,1) END) AS agua_l_hab_dia,
       MAX(CASE WHEN codigo = 'AGU-02' THEN ROUND(valor,1) END) AS perdas_pct,
       MAX(CASE WHEN codigo = 'ENE-01' THEN ROUND(valor,1) END) AS energia_kwh_hab_mes,
       MAX(CASE WHEN codigo = 'ENE-02' THEN ROUND(valor,1) END) AS solar_w_hab,
       MAX(CASE WHEN codigo = 'RES-01' THEN ROUND(valor,2) END) AS residuos_kg_hab_dia,
       MAX(CASE WHEN codigo = 'RES-02' THEN ROUND(valor,1) END) AS reciclagem_pct,
       MAX(CASE WHEN codigo = 'MOB-01' THEN ROUND(valor,1) END) AS viagens_onibus_hab_mes,
       MAX(CASE WHEN codigo = 'MOB-02' THEN ROUND(valor,1) END) AS co2_kg_hab_mes
FROM vw_indicador_desempenho
WHERE periodo = (SELECT MAX(periodo) FROM vw_ies_municipio_mensal)
GROUP BY municipio
ORDER BY municipio;

-- R7. Mesmo mês, anos diferentes: variação contra o ano anterior (window function LAG 12)
SELECT municipio, ano_mes, ROUND(valor,2) AS viagens_hab_mes,
       ROUND(valor - LAG(valor, 12) OVER (PARTITION BY id_municipio ORDER BY periodo), 2) AS diferenca_12_meses
FROM vw_indicador_desempenho
WHERE codigo = 'MOB-01' AND municipio = 'São Paulo'
ORDER BY periodo;

-- R8. Média móvel de 3 meses das perdas de água (suaviza oscilações mensais)
SELECT municipio, ano_mes, ROUND(valor,1) AS perdas_pct,
       ROUND(AVG(valor) OVER (PARTITION BY id_municipio ORDER BY periodo ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS media_movel_3m
FROM vw_indicador_desempenho
WHERE codigo = 'AGU-02'
ORDER BY municipio, periodo;

-- R9. Geração solar: potência nova instalada por mês (DADO OFICIAL da ANEEL)
SELECT r.nome AS municipio, t.rotulo AS mes,
       ROUND(f.valor_total - LAG(f.valor_total) OVER (PARTITION BY r.sk_municipio ORDER BY t.sk_tempo)) AS kw_novos_no_mes
FROM fato_medicao f
JOIN dim_tempo     t ON t.sk_tempo     = f.sk_tempo
JOIN dim_municipio r ON r.sk_municipio = f.sk_municipio
JOIN dim_metrica   m ON m.sk_metrica   = f.sk_metrica
WHERE m.codigo = 'GD_POTENCIA' AND f.qtd_estimados = 0
ORDER BY r.nome, t.sk_tempo;

-- R10. Transparência: quanto dos dados é oficial, calculado de oficial ou estimado
SELECT * FROM vw_origem_dados ORDER BY servico, metrica;

-- R11. Drill-down no DW: passageiros por trimestre e ano (com subtotais ROLLUP)
SELECT t.ano, t.trimestre, ROUND(SUM(f.valor_total) / 1e6, 1) AS passageiros_milhoes
FROM fato_medicao f
JOIN dim_tempo   t ON t.sk_tempo   = f.sk_tempo
JOIN dim_metrica m ON m.sk_metrica = f.sk_metrica
WHERE m.codigo = 'TP_PASSAGEIROS'
GROUP BY t.ano, t.trimestre WITH ROLLUP;

-- R12. Efetividade das ações: o que funcionou x o que precisa ser revisto
SELECT titulo, municipio, indicador_alvo, status, efeito, variacao_pct,
       FORMAT(orcamento, 2, 'pt_BR') AS orcamento_rs
FROM vw_acoes_resultados
ORDER BY FIELD(efeito,'MELHOROU','ESTAVEL','PIOROU','AGUARDANDO_AVALIACAO'), variacao_pct;

-- R13. Governança: fontes, último mês oficial e linhas rejeitadas no staging
SELECT fonte, orgao, servico, frequencia, confiabilidade, registros_reais, registros_derivados,
       registros_estimados, ultimo_mes_oficial, status_ultimo_lote
FROM vw_qualidade_fontes
ORDER BY servico, fonte;

SELECT id_lote, codigo_metrica, nome_municipio, data_texto, valor_texto, erro
FROM stg_medicao_bruta
WHERE erro IS NOT NULL;

-- R14. Copiloto: relatórios da IA por situação e perguntas bloqueadas (segurança)
SELECT status, publico, COUNT(*) AS relatorios FROM relatorio_ia GROUP BY status, publico;
SELECT pergunta, situacao, motivo_bloqueio, criada_em FROM pergunta_ia ORDER BY criada_em DESC LIMIT 10;

-- R15. Trilha de auditoria (quem alterou o quê)
SELECT ocorrido_em, usuario_bd, tabela, operacao, id_registro, dados_antigos, dados_novos
FROM auditoria
ORDER BY ocorrido_em DESC
LIMIT 20;

-- R16. Metas: em vigor, aguardando parecer/decisão e histórico (quem propôs, quem deu parecer, quem aprovou)
SELECT codigo, indicador, abrangencia, valor, vigencia_inicio, vigencia_fim, status, em_vigor,
       proposta_por, parecer_por, IF(parecer_favoravel, 'favorável', 'desfavorável') AS parecer, aprovada_por
FROM vw_metas
ORDER BY status = 'APROVADA' DESC, codigo, vigencia_inicio;

-- R17. Análises compartilhadas: publicadas, nível de confiança e quem revisou
SELECT titulo, servico, municipios, autor, nivel_autor, revisado_por, nivel_confianca, pct_base_oficial, evidencias, comentarios
FROM vw_analises_publicadas
ORDER BY publicada_em DESC;

-- R18. Confiabilidade dos analistas (credencial + histórico de revisões)
SELECT nome, nivel, credencial, area, pode_publicar, publicadas, devolvidas, taxa_aprovacao, mfa_ativo
FROM vw_confiabilidade_analista;

-- R19. Segurança do login: tentativas por resultado e usuários bloqueados agora
SELECT resultado, COUNT(*) AS tentativas FROM acesso_log GROUP BY resultado;
SELECT email, bloqueado_ate FROM usuario WHERE bloqueado_ate > NOW();

-- R20. Cadastros: pedidos de analistas e gestores aguardando o ADMIN, recusados e aprovações que vencem em 30 dias
SELECT nome, perfil_pedido, orgao, cargo, cidade_atuacao, status, pedido_em, dias_aguardando, analisado_por, motivo_decisao, valido_ate
FROM vw_cadastros_profissionais
ORDER BY FIELD(status,'EM_ANALISE','SUSPENSO','RECUSADO','APROVADO'), vence_em_30_dias DESC, pedido_em;
