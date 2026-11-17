-- =====================================================================
--  EcoCity — Script 02: índices de desempenho
--  Criados a partir das consultas mais frequentes dos dashboards e da API.
-- =====================================================================
USE ecocity;

-- Séries mensais: filtros por município + mês são os mais usados
CREATE INDEX ix_dado_municipio_data     ON dado (id_municipio, data_referencia);
CREATE INDEX ix_dado_metrica_data    ON dado (id_metrica, data_referencia);
CREATE INDEX ix_dado_qualidade       ON dado (qualidade);

CREATE INDEX ix_iv_municipio_periodo    ON indicador_valor (id_municipio, periodo);
CREATE INDEX ix_iv_periodo           ON indicador_valor (periodo);

-- Feed de alertas da IA (mais recentes e mais graves primeiro)
CREATE INDEX ix_analise_status_sev   ON analise_ia (status, severidade, gerada_em);
CREATE INDEX ix_analise_municipio       ON analise_ia (id_municipio, gerada_em);

-- Acompanhamento de ações
CREATE INDEX ix_acao_status          ON acao (status, data_inicio);
CREATE INDEX ix_acao_municipio          ON acao (id_municipio);

-- Monitoramento do ETL
CREATE INDEX ix_lote_fonte_inicio    ON lote_carga (id_fonte, iniciado_em);
CREATE INDEX ix_stg_lote_proc        ON stg_medicao_bruta (id_lote, processado);

-- Auditoria (consultas por tabela/registro e por período)
CREATE INDEX ix_auditoria_tabela_reg ON auditoria (tabela, id_registro);
CREATE INDEX ix_auditoria_data       ON auditoria (ocorrido_em);

-- Data Warehouse: chaves de fato já são PK compostas (tempo, região, ...);
-- índices extras para "fatiar" por indicador/métrica em todo o período
CREATE INDEX ix_fi_indicador_tempo   ON fato_indicador (sk_indicador, sk_tempo);
CREATE INDEX ix_fi_servico_tempo     ON fato_indicador (sk_servico, sk_tempo);
CREATE INDEX ix_fm_metrica_tempo     ON fato_medicao   (sk_metrica, sk_tempo);

-- Copiloto: fila de revisão de relatórios e histórico de perguntas por usuário
CREATE INDEX ix_relatorio_status     ON relatorio_ia (status, criado_em);
CREATE INDEX ix_relatorio_periodo    ON relatorio_ia (periodo_inicio, periodo_fim);
CREATE INDEX ix_pergunta_usuario     ON pergunta_ia (id_usuario, criada_em);
CREATE INDEX ix_pergunta_situacao    ON pergunta_ia (situacao);
