-- =====================================================================
--  EcoCity — Script 06: segurança (papéis, usuários e permissões)
--  Princípio do menor privilégio: cada perfil só acessa o necessário.
--  ATENÇÃO: troque as senhas abaixo antes de publicar (use um cofre de
--  segredos, ex.: OCI Vault). Na OCI, exigir TLS em todas as conexões.
-- =====================================================================
USE ecocity;

-- --------------------------- PAPÉIS (ROLES) ---------------------------
DROP ROLE IF EXISTS r_cidadao, r_especialista, r_analista, r_gestor, r_etl, r_bi, r_dba, r_ia;
CREATE ROLE r_cidadao, r_analista, r_gestor, r_etl, r_bi, r_dba, r_ia;

-- Cidadão: somente o painel público (dados agregados, sem dados pessoais)
GRANT SELECT ON ecocity.vw_painel_cidadao    TO r_cidadao;
GRANT SELECT ON ecocity.vw_ies_ranking       TO r_cidadao;
GRANT SELECT ON ecocity.vw_origem_dados      TO r_cidadao;      -- transparência sobre dados estimados
GRANT SELECT ON ecocity.vw_relatorios_publicados TO r_cidadao;   -- relatórios da IA já aprovados
GRANT SELECT ON ecocity.vw_metas          TO r_cidadao;   -- transparência: quem definiu cada meta e por quê

-- Analista: lê toda a camada analítica e trata as análises da IA
GRANT SELECT ON ecocity.vw_indicador_desempenho TO r_analista;
GRANT SELECT ON ecocity.vw_ies_municipio_mensal    TO r_analista;
GRANT SELECT ON ecocity.vw_ies_ranking          TO r_analista;
GRANT SELECT ON ecocity.vw_alertas_abertos      TO r_analista;
GRANT SELECT ON ecocity.vw_acoes_resultados     TO r_analista;
GRANT SELECT ON ecocity.vw_qualidade_fontes     TO r_analista;
GRANT SELECT ON ecocity.vw_origem_dados         TO r_analista;
GRANT SELECT ON ecocity.vw_relatorios_publicados TO r_analista;
GRANT SELECT ON ecocity.vw_dw_tendencia_servico TO r_analista;
GRANT SELECT ON ecocity.vw_dw_cidade_indicador  TO r_analista;
GRANT SELECT ON ecocity.dado                    TO r_analista;
GRANT SELECT ON ecocity.indicador               TO r_analista;
GRANT SELECT ON ecocity.municipio                  TO r_analista;
GRANT SELECT ON ecocity.populacao_anual            TO r_analista;
GRANT SELECT ON ecocity.servico_publico         TO r_analista;
GRANT SELECT ON ecocity.metrica                 TO r_analista;
GRANT SELECT ON ecocity.orgao                   TO r_analista;
GRANT SELECT ON ecocity.unidade_medida          TO r_analista;
GRANT SELECT ON ecocity.fonte_dados             TO r_analista;
GRANT SELECT ON ecocity.lote_carga              TO r_analista;   -- governança do ETL
GRANT SELECT ON ecocity.stg_medicao_bruta       TO r_analista;
GRANT SELECT ON ecocity.indicador_valor         TO r_analista;
GRANT SELECT, UPDATE (status, revisada_por) ON ecocity.analise_ia TO r_analista;
GRANT SELECT, INSERT ON ecocity.acao            TO r_analista;
-- Copiloto: o analista pede relatórios e faz perguntas (a API registra tudo)
GRANT SELECT ON ecocity.relatorio_ia        TO r_analista;
GRANT SELECT ON ecocity.relatorio_municipio TO r_analista;
GRANT SELECT, INSERT ON ecocity.pergunta_ia TO r_analista;
GRANT SELECT ON ecocity.vw_copiloto_uso     TO r_analista;
-- Análises compartilhadas: o analista escreve rascunhos e anexa evidências;
-- enviar, revisar e dar parecer em metas só pelas procedures (que checam a credencial)
GRANT SELECT, INSERT ON ecocity.analise_publicada TO r_analista;
GRANT UPDATE (titulo, resumo, conteudo, id_servico, periodo_inicio, periodo_fim) ON ecocity.analise_publicada TO r_analista;
GRANT SELECT, INSERT, DELETE ON ecocity.analise_municipio TO r_analista;
GRANT SELECT, INSERT, DELETE ON ecocity.analise_evidencia TO r_analista;
GRANT SELECT, INSERT ON ecocity.analise_comentario TO r_analista;
GRANT SELECT ON ecocity.vw_analises_publicadas     TO r_analista;
GRANT SELECT ON ecocity.vw_fila_revisao_analises   TO r_analista;
GRANT SELECT ON ecocity.vw_confiabilidade_analista TO r_analista;
GRANT SELECT ON ecocity.credencial_analista        TO r_analista;
GRANT SELECT ON ecocity.meta                       TO r_analista;
GRANT SELECT ON ecocity.vw_metas                   TO r_analista;
GRANT EXECUTE ON PROCEDURE ecocity.sp_enviar_analise  TO r_analista;
GRANT EXECUTE ON PROCEDURE ecocity.sp_revisar_analise TO r_analista;
GRANT EXECUTE ON PROCEDURE ecocity.sp_parecer_meta    TO r_analista;
GRANT EXECUTE ON PROCEDURE ecocity.sp_copiloto_dados   TO r_analista;
GRANT EXECUTE ON PROCEDURE ecocity.sp_salvar_relatorio TO r_analista;

-- Gestor: tudo do analista + gerencia ações e registra resultados
GRANT r_analista TO r_gestor;
GRANT SELECT, INSERT, UPDATE ON ecocity.acao      TO r_gestor;
GRANT SELECT, INSERT         ON ecocity.resultado TO r_gestor;
GRANT EXECUTE ON PROCEDURE ecocity.sp_registrar_resultado TO r_gestor;
GRANT EXECUTE ON PROCEDURE ecocity.sp_dashboard_municipio    TO r_gestor;
GRANT EXECUTE ON PROCEDURE ecocity.sp_revisar_relatorio      TO r_gestor;   -- aprova relatórios da IA
GRANT EXECUTE ON PROCEDURE ecocity.sp_propor_meta            TO r_gestor;   -- formulário de metas
GRANT EXECUTE ON PROCEDURE ecocity.sp_decidir_meta           TO r_gestor;

-- ETL (serviço de integração): carrega staging e executa o pipeline
GRANT SELECT, INSERT ON ecocity.stg_medicao_bruta TO r_etl;
GRANT SELECT, INSERT, UPDATE ON ecocity.lote_carga TO r_etl;
GRANT EXECUTE ON PROCEDURE ecocity.sp_processar_staging   TO r_etl;
GRANT EXECUTE ON PROCEDURE ecocity.sp_calcular_indicadores TO r_etl;
GRANT EXECUTE ON PROCEDURE ecocity.sp_carga_dw            TO r_etl;
GRANT EXECUTE ON PROCEDURE ecocity.sp_pipeline_mensal    TO r_etl;
GRANT EXECUTE ON PROCEDURE ecocity.sp_atualizar_dado_real TO r_etl;   -- troca estimado por oficial
GRANT SELECT, INSERT ON ecocity.analise_ia TO r_etl;          -- camada de IA grava insights
GRANT SELECT ON ecocity.indicador_valor TO r_etl;               -- IA lê as séries históricas
GRANT SELECT ON ecocity.indicador       TO r_etl;
GRANT SELECT ON ecocity.unidade_medida  TO r_etl;
GRANT SELECT ON ecocity.municipio          TO r_etl;
GRANT SELECT, INSERT, UPDATE ON ecocity.populacao_anual TO r_etl;

-- BI/Dashboards: somente leitura no Data Warehouse e views
GRANT SELECT ON ecocity.dim_tempo      TO r_bi;
GRANT SELECT ON ecocity.dim_municipio     TO r_bi;
GRANT SELECT ON ecocity.dim_servico    TO r_bi;
GRANT SELECT ON ecocity.dim_metrica    TO r_bi;
GRANT SELECT ON ecocity.dim_indicador  TO r_bi;
GRANT SELECT ON ecocity.fato_medicao   TO r_bi;
GRANT SELECT ON ecocity.fato_indicador TO r_bi;
GRANT SELECT ON ecocity.vw_dw_tendencia_servico TO r_bi;
GRANT SELECT ON ecocity.vw_dw_cidade_indicador  TO r_bi;

-- Analista também consulta o DW (herda o papel de BI)
GRANT r_bi TO r_analista;

-- IA (Copiloto): SOMENTE LEITURA e SOMENTE nas views de indicadores.
-- É com este papel que o SQL gerado pela IA é executado: mesmo que a IA
-- gere um DELETE/DROP, o próprio MySQL recusa. Sem acesso a usuários,
-- auditoria, e-mails ou senhas.
GRANT SELECT ON ecocity.vw_indicador_desempenho   TO r_ia;
GRANT SELECT ON ecocity.vw_ies_municipio_mensal   TO r_ia;
GRANT SELECT ON ecocity.vw_ies_ranking            TO r_ia;
GRANT SELECT ON ecocity.vw_origem_dados           TO r_ia;
GRANT SELECT ON ecocity.vw_acoes_resultados       TO r_ia;
GRANT SELECT ON ecocity.vw_dw_tendencia_servico   TO r_ia;
GRANT SELECT ON ecocity.vw_dw_cidade_indicador    TO r_ia;

-- DBA: administração completa do schema
GRANT ALL PRIVILEGES ON ecocity.* TO r_dba;

-- ---------------------------- USUÁRIOS --------------------------------
-- Política: senhas fortes, expiração a cada 90 dias e bloqueio após
-- 5 tentativas erradas (bloqueio de 1 dia).
DROP USER IF EXISTS 'ecocity_api'@'%', 'ecocity_etl'@'%', 'ecocity_bi'@'%', 'ecocity_dba'@'%', 'ecocity_ia'@'%';

CREATE USER 'ecocity_api'@'%' IDENTIFIED BY 'Api#EcoCity2026!'
  PASSWORD EXPIRE INTERVAL 90 DAY FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
CREATE USER 'ecocity_etl'@'%' IDENTIFIED BY 'Etl#EcoCity2026!'
  PASSWORD EXPIRE INTERVAL 90 DAY FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
CREATE USER 'ecocity_bi'@'%'  IDENTIFIED BY 'Bi#EcoCity2026!'
  PASSWORD EXPIRE INTERVAL 90 DAY FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
CREATE USER 'ecocity_dba'@'%' IDENTIFIED BY 'Dba#EcoCity2026!'
  PASSWORD EXPIRE INTERVAL 60 DAY FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 2;
-- Usuário do Copiloto: só leitura e com limite de uso (evita abuso/consultas pesadas)
CREATE USER 'ecocity_ia'@'%' IDENTIFIED BY 'Ia#EcoCity2026!'
  WITH MAX_QUERIES_PER_HOUR 600 MAX_USER_CONNECTIONS 3
  PASSWORD EXPIRE INTERVAL 90 DAY FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;

-- Em produção (OCI) descomente para exigir conexão criptografada:
-- ALTER USER 'ecocity_api'@'%', 'ecocity_etl'@'%', 'ecocity_bi'@'%', 'ecocity_dba'@'%', 'ecocity_ia'@'%' REQUIRE SSL;

-- A API atende cidadãos, analistas e gestores: o papel efetivo é
-- decidido na aplicação (JWT) e no banco ela recebe o papel de gestor.
GRANT r_gestor, r_cidadao TO 'ecocity_api'@'%';
GRANT r_etl               TO 'ecocity_etl'@'%';
GRANT r_bi                TO 'ecocity_bi'@'%';
GRANT r_dba               TO 'ecocity_dba'@'%';
GRANT EXECUTE ON PROCEDURE ecocity.sp_criar_admin        TO r_dba;   -- só o DBA cria administradores
GRANT EXECUTE ON PROCEDURE ecocity.sp_trocar_chave_admin TO r_dba;
GRANT r_ia                TO 'ecocity_ia'@'%';

-- Autenticação da API: acesso restrito por COLUNA à tabela de usuários
GRANT SELECT (id_usuario, nome, email, senha_hash, id_perfil, id_municipio, ativo, criado_em, ultimo_acesso),
      UPDATE (ultimo_acesso) ON ecocity.usuario TO 'ecocity_api'@'%';
-- Página do ADMIN: leitura da trilha de auditoria (a API só libera para o perfil ADMIN)
GRANT SELECT ON ecocity.auditoria TO 'ecocity_api'@'%';
-- Login seguro: o banco registra cada tentativa, bloqueia após 5 erros e controla a 2ª etapa
GRANT EXECUTE ON PROCEDURE ecocity.sp_registrar_login TO 'ecocity_api'@'%';
GRANT SELECT (mfa_ativo, mfa_segredo, senha_alterada_em, tentativas_falhas, bloqueado_ate),
      UPDATE (mfa_ativo, mfa_segredo, senha_hash, senha_alterada_em) ON ecocity.usuario TO 'ecocity_api'@'%';
GRANT SELECT ON ecocity.acesso_log TO 'ecocity_api'@'%';
GRANT SELECT, INSERT ON ecocity.credencial_analista TO 'ecocity_api'@'%';      -- cadastro de credencial (status PENDENTE)
GRANT EXECUTE ON PROCEDURE ecocity.sp_verificar_credencial TO 'ecocity_api'@'%'; -- só o ADMIN (checado na procedure)
GRANT EXECUTE ON PROCEDURE ecocity.sp_avaliar_fonte TO 'ecocity_api'@'%';        -- só o ADMIN (checado na procedure)
GRANT SELECT ON ecocity.perfil TO 'ecocity_api'@'%';
-- Cadastro: cidadão (simples) e analista/gestor (completo, aguarda o ADMIN). A API NÃO grava em usuario direto:
-- só chama as procedures, que aplicam as regras. Criar ADMIN é exclusivo do DBA (sp_criar_admin).
GRANT EXECUTE ON PROCEDURE ecocity.sp_cadastrar_cidadao TO 'ecocity_api'@'%';
GRANT EXECUTE ON PROCEDURE ecocity.sp_solicitar_acesso  TO 'ecocity_api'@'%';
GRANT EXECUTE ON PROCEDURE ecocity.sp_analisar_cadastro TO 'ecocity_api'@'%';   -- só o ADMIN (checado na procedure)
GRANT SELECT ON ecocity.vw_cadastros_profissionais TO 'ecocity_api'@'%';
GRANT SELECT (status_cadastro, telefone, chave_admin_hash) ON ecocity.usuario TO 'ecocity_api'@'%';

-- Copiloto: a API grava os relatórios e o histórico de perguntas
GRANT SELECT, INSERT, UPDATE (status, revisado_por, comentario_revisao) ON ecocity.relatorio_ia TO 'ecocity_api'@'%';

SET DEFAULT ROLE ALL TO 'ecocity_api'@'%', 'ecocity_etl'@'%', 'ecocity_bi'@'%', 'ecocity_dba'@'%', 'ecocity_ia'@'%';

-- Conferência
SHOW GRANTS FOR 'ecocity_api'@'%' USING r_gestor, r_cidadao;
SHOW GRANTS FOR 'ecocity_ia'@'%' USING r_ia;
