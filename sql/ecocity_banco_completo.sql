-- =====================================================================
--  EcoCity — BANCO COMPLETO EM UM ÚNICO ARQUIVO (para o MySQL Workbench)
--  Como usar: File > Open SQL Script... > escolha este arquivo > clique no raio
--  Cria o banco 'ecocity' do zero (apaga a versão anterior, se existir).
--  Dados MENSAIS de 8 municípios de SP, de jan/2023 a set/2026 (45 meses).
--  Cada número usa o último dado oficial publicado da sua fonte (coleta em 16/11/2026).
--    REAL     = oficial do mês: energia solar (ANEEL) e ônibus de São Paulo (SPTrans);
--    DERIVADO = total oficial do ano ÷ meses: água, resíduos, emissões, resíduos de SP;
--    ESTIMADO = a fonte ainda não publicou o período ou não há dado oficial da cidade.
--  v17: robô de coleta que confere os sites dos órgãos e atualiza o banco sozinho
--  (tabela coleta_verificacao, view vw_coleta_fontes, sp_registrar_verificacao).
--  Inclui o Copiloto EcoCity, análises compartilhadas pelos analistas (com revisão
--  por pares), credenciais dos analistas, metas com vigência, cadastro por perfil
--  (cidadão simples; analista e gestor aprovados pelo admin; admin com chave individual)
--  e controle de login.
-- =====================================================================
SET SQL_SAFE_UPDATES = 0;
SET NAMES utf8mb4;

-- >>>>>>>>>>>>>>>>>>>> 01_create_database_tabelas.sql <<<<<<<<<<<<<<<<<<<<
-- =====================================================================
--  EcoCity — Data Warehouse para Comunidades Sustentáveis
--  Script 01: criação do banco de dados e das tabelas (com constraints)
--  SGBD: MySQL 8.0+ (MySQL HeatWave na Oracle Cloud Infrastructure)
--  Autoras: Gabriela Sant'Ana Merces Assis e Nicole Maranhão Assis
-- =====================================================================
--  Arquitetura em 3 camadas dentro do mesmo schema:
--    STAGING (stg_*)  -> dados brutos recebidos das fontes, sem tipagem
--    CORE             -> modelo relacional normalizado (3FN)
--    DW (dim_* fato_*)-> modelo dimensional (estrela) para dashboards
-- =====================================================================

DROP DATABASE IF EXISTS ecocity;
CREATE DATABASE ecocity
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;
USE ecocity;

-- ---------------------------------------------------------------------
--  CAMADA CORE (3FN)
-- ---------------------------------------------------------------------

-- Perfis de acesso da aplicação (cidadão, analista, gestor, admin)
CREATE TABLE perfil (
  id_perfil     TINYINT UNSIGNED AUTO_INCREMENT,
  nome          VARCHAR(30)  NOT NULL,
  descricao     VARCHAR(200) NOT NULL,
  exige_mfa     BOOLEAN      NOT NULL DEFAULT FALSE,   -- login em 2 etapas obrigatório (código do aplicativo autenticador)
  validade_senha_dias SMALLINT UNSIGNED NOT NULL DEFAULT 180,
  CONSTRAINT pk_perfil PRIMARY KEY (id_perfil),
  CONSTRAINT uq_perfil_nome UNIQUE (nome)
) ENGINE=InnoDB;

-- Municípios monitorados (cidades do Estado de São Paulo)
CREATE TABLE municipio (
  id_municipio  SMALLINT UNSIGNED AUTO_INCREMENT,
  nome          VARCHAR(60)  NOT NULL,
  codigo_ibge   CHAR(7)      NOT NULL,              -- código oficial do IBGE
  uf            CHAR(2)      NOT NULL DEFAULT 'SP',
  regiao_metropolitana VARCHAR(40) NOT NULL,        -- RM / aglomeração urbana
  area_km2      DECIMAL(9,2) NOT NULL,
  populacao     INT UNSIGNED NOT NULL,
  fonte_populacao VARCHAR(80) NOT NULL DEFAULT 'IBGE - Censo 2022',
  latitude      DECIMAL(9,6) NULL,
  longitude     DECIMAL(9,6) NULL,
  CONSTRAINT pk_municipio PRIMARY KEY (id_municipio),
  CONSTRAINT uq_municipio_nome UNIQUE (nome, uf),
  CONSTRAINT uq_municipio_ibge UNIQUE (codigo_ibge),
  CONSTRAINT ck_municipio_ibge CHECK (codigo_ibge REGEXP '^[0-9]{7}$'),
  CONSTRAINT ck_municipio_area CHECK (area_km2 > 0),
  CONSTRAINT ck_municipio_pop  CHECK (populacao > 0),
  CONSTRAINT ck_municipio_lat  CHECK (latitude  IS NULL OR latitude  BETWEEN -90  AND 90),
  CONSTRAINT ck_municipio_lon  CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
) ENGINE=InnoDB;

-- População de cada município por ano (IBGE: Censo 2022 e estimativas anuais).
-- O IBGE só publica população por ANO; os indicadores mensais usam a população do ano do mês.
-- Tabela separada para manter a 3FN: a população depende de (município, ano).
CREATE TABLE populacao_anual (
  id_municipio  SMALLINT UNSIGNED NOT NULL,
  ano           SMALLINT UNSIGNED NOT NULL,
  populacao     INT UNSIGNED NOT NULL,
  fonte         VARCHAR(120) NOT NULL,
  CONSTRAINT pk_populacao_anual PRIMARY KEY (id_municipio, ano),
  CONSTRAINT fk_pop_municipio FOREIGN KEY (id_municipio) REFERENCES municipio (id_municipio) ON DELETE CASCADE,
  CONSTRAINT ck_pop_ano CHECK (ano BETWEEN 2000 AND 2100),
  CONSTRAINT ck_pop_valor CHECK (populacao > 0)
) ENGINE=InnoDB;

-- Usuários do sistema
CREATE TABLE usuario (
  id_usuario    INT UNSIGNED AUTO_INCREMENT,
  nome          VARCHAR(100) NOT NULL,
  email         VARCHAR(120) NOT NULL,
  senha_hash    CHAR(60)     NOT NULL,              -- bcrypt
  id_perfil     TINYINT UNSIGNED NOT NULL,
  id_municipio     SMALLINT UNSIGNED NULL,             -- município de interesse/atuação
  telefone      VARCHAR(20)  NULL,                       -- celular (cidadão: opcional, para avisos)
  ativo         BOOLEAN      NOT NULL DEFAULT TRUE,
  -- Analista e gestor só entram depois que o ADMIN aprova o cadastro profissional
  status_cadastro ENUM('ATIVO','EM_ANALISE','RECUSADO','SUSPENSO') NOT NULL DEFAULT 'ATIVO',
  chave_admin_hash CHAR(60)  NULL,                       -- só ADMIN: chave individual (bcrypt), entregue pelo DBA
  mfa_ativo     BOOLEAN      NOT NULL DEFAULT FALSE,     -- 2ª etapa do login configurada
  mfa_segredo   VARBINARY(64) NULL,                      -- segredo TOTP CRIPTOGRAFADO pela aplicação (AES)
  senha_alterada_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  tentativas_falhas TINYINT UNSIGNED NOT NULL DEFAULT 0,
  bloqueado_ate DATETIME     NULL,                       -- bloqueio temporário após 5 erros
  criado_em     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ultimo_acesso DATETIME     NULL,
  CONSTRAINT pk_usuario PRIMARY KEY (id_usuario),
  CONSTRAINT uq_usuario_email UNIQUE (email),
  CONSTRAINT fk_usuario_perfil FOREIGN KEY (id_perfil)
      REFERENCES perfil (id_perfil) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_usuario_municipio FOREIGN KEY (id_municipio)
      REFERENCES municipio (id_municipio) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT ck_usuario_email CHECK (email LIKE '%_@_%._%'),
  CONSTRAINT ck_usuario_mfa   CHECK (mfa_ativo = FALSE OR mfa_segredo IS NOT NULL),
  CONSTRAINT ck_usuario_tel   CHECK (telefone IS NULL OR telefone REGEXP '^[0-9]{10,11}$')   -- DDD + número, só dígitos
) ENGINE=InnoDB;

-- Serviços públicos integrados (Água, Energia, Resíduos, Mobilidade)
CREATE TABLE servico_publico (
  id_servico    TINYINT UNSIGNED AUTO_INCREMENT,
  nome          VARCHAR(30)  NOT NULL,
  descricao     VARCHAR(200) NOT NULL,
  CONSTRAINT pk_servico PRIMARY KEY (id_servico),
  CONSTRAINT uq_servico_nome UNIQUE (nome)
) ENGINE=InnoDB;

-- Órgãos / concessionárias responsáveis pelas fontes
CREATE TABLE orgao (
  id_orgao      SMALLINT UNSIGNED AUTO_INCREMENT,
  nome          VARCHAR(120) NOT NULL,
  sigla         VARCHAR(15)  NOT NULL,
  tipo          ENUM('SECRETARIA','CONCESSIONARIA','AUTARQUIA','EMPRESA_PUBLICA','PARCEIRO') NOT NULL,
  email_contato VARCHAR(120) NULL,
  CONSTRAINT pk_orgao PRIMARY KEY (id_orgao),
  CONSTRAINT uq_orgao_sigla UNIQUE (sigla)
) ENGINE=InnoDB;

-- Fontes de dados (APIs, arquivos, sensores IoT...)
CREATE TABLE fonte_dados (
  id_fonte        SMALLINT UNSIGNED AUTO_INCREMENT,
  nome            VARCHAR(120) NOT NULL,
  id_orgao        SMALLINT UNSIGNED NOT NULL,
  id_servico      TINYINT UNSIGNED  NOT NULL,
  tipo_integracao ENUM('API_REST','ARQUIVO_CSV','ARQUIVO_PARQUET','PDF','SENSOR_IOT','PLANILHA','PAGINA_WEB','MANUAL') NOT NULL,
  frequencia      ENUM('TEMPO_REAL','DIARIA','SEMANAL','MENSAL','SEMESTRAL','ANUAL') NOT NULL,   -- de quanto em quanto tempo a fonte publica
  endpoint_url    VARCHAR(255) NULL,
  -- Nota dada pelo ADMINISTRADOR seguindo critérios fixos (sp_avaliar_fonte):
  --   5 = órgão oficial, dado mensal, atualizado e por município
  --   4 = órgão oficial, mas dado anual, atrasado ou só do Estado
  --   3 = dado oficial publicado em PDF ou imagem (extração manual)
  --   2 = fonte não governamental reconhecida
  --   1 = fonte com erros já encontrados
  confiabilidade  TINYINT UNSIGNED NOT NULL DEFAULT 3,
  confiabilidade_motivo VARCHAR(200) NULL,               -- qual critério foi aplicado
  avaliada_por    INT UNSIGNED NULL,                     -- administrador que deu a nota
  avaliada_em     DATETIME NULL,
  ativa           BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_fonte PRIMARY KEY (id_fonte),
  CONSTRAINT uq_fonte_nome UNIQUE (nome),
  CONSTRAINT fk_fonte_orgao   FOREIGN KEY (id_orgao)   REFERENCES orgao (id_orgao),
  CONSTRAINT fk_fonte_servico FOREIGN KEY (id_servico) REFERENCES servico_publico (id_servico),
  CONSTRAINT fk_fonte_avaliador FOREIGN KEY (avaliada_por) REFERENCES usuario (id_usuario),
  CONSTRAINT ck_fonte_conf CHECK (confiabilidade BETWEEN 1 AND 5)
) ENGINE=InnoDB;

-- Unidades de medida
CREATE TABLE unidade_medida (
  id_unidade    TINYINT UNSIGNED AUTO_INCREMENT,
  sigla         VARCHAR(20) NOT NULL,
  descricao     VARCHAR(80) NOT NULL,
  CONSTRAINT pk_unidade PRIMARY KEY (id_unidade),
  CONSTRAINT uq_unidade_sigla UNIQUE (sigla)
) ENGINE=InnoDB;

-- Métricas brutas coletadas (ex.: m³ de água consumida, kWh consumidos)
CREATE TABLE metrica (
  id_metrica    SMALLINT UNSIGNED AUTO_INCREMENT,
  codigo        VARCHAR(30)  NOT NULL,
  nome          VARCHAR(100) NOT NULL,
  id_servico    TINYINT UNSIGNED NOT NULL,
  id_unidade    TINYINT UNSIGNED NOT NULL,
  descricao     VARCHAR(255) NULL,
  CONSTRAINT pk_metrica PRIMARY KEY (id_metrica),
  CONSTRAINT uq_metrica_codigo UNIQUE (codigo),
  CONSTRAINT fk_metrica_servico FOREIGN KEY (id_servico) REFERENCES servico_publico (id_servico),
  CONSTRAINT fk_metrica_unidade FOREIGN KEY (id_unidade) REFERENCES unidade_medida (id_unidade)
) ENGINE=InnoDB;

-- Controle de cargas (ETL) — rastreabilidade de cada importação
CREATE TABLE lote_carga (
  id_lote              INT UNSIGNED AUTO_INCREMENT,
  id_fonte             SMALLINT UNSIGNED NOT NULL,
  iniciado_em          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finalizado_em        DATETIME NULL,
  registros_lidos      INT UNSIGNED NOT NULL DEFAULT 0,
  registros_validos    INT UNSIGNED NOT NULL DEFAULT 0,
  registros_rejeitados INT UNSIGNED NOT NULL DEFAULT 0,
  status               ENUM('EM_ANDAMENTO','SUCESSO','PARCIAL','FALHA') NOT NULL DEFAULT 'EM_ANDAMENTO',
  mensagem             VARCHAR(255) NULL,
  CONSTRAINT pk_lote PRIMARY KEY (id_lote),
  CONSTRAINT fk_lote_fonte FOREIGN KEY (id_fonte) REFERENCES fonte_dados (id_fonte),
  CONSTRAINT ck_lote_datas CHECK (finalizado_em IS NULL OR finalizado_em >= iniciado_em)
) ENGINE=InnoDB;

-- DADO: medições integradas e tipadas (granularidade MENSAL por município)
--   origem: REAL     = número oficial publicado para aquele mês;
--           DERIVADO = calculado a partir de dado oficial de um período maior (ex.: total anual oficial ÷ meses);
--           ESTIMADO = estimativa da equipe (não há dado oficial publicado para o mês).
CREATE TABLE dado (
  id_dado         BIGINT UNSIGNED AUTO_INCREMENT,
  id_fonte        SMALLINT UNSIGNED NOT NULL,
  id_municipio       SMALLINT UNSIGNED NOT NULL,
  id_metrica      SMALLINT UNSIGNED NOT NULL,
  id_lote         INT UNSIGNED NULL,
  data_referencia DATE NOT NULL,                       -- sempre o 1º dia do mês
  valor           DECIMAL(16,4) NOT NULL,
  qualidade       ENUM('VALIDO','SUSPEITO','REJEITADO') NOT NULL DEFAULT 'VALIDO',
  origem          ENUM('REAL','DERIVADO','ESTIMADO') NOT NULL DEFAULT 'REAL',  -- transparência
  referencia_origem VARCHAR(300) NULL,                 -- de onde veio o número (ou como foi estimado)
  registrado_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_dado PRIMARY KEY (id_dado),
  CONSTRAINT uq_dado_chave UNIQUE (id_fonte, id_municipio, id_metrica, data_referencia),
  CONSTRAINT fk_dado_fonte   FOREIGN KEY (id_fonte)   REFERENCES fonte_dados (id_fonte),
  CONSTRAINT fk_dado_municipio  FOREIGN KEY (id_municipio)  REFERENCES municipio (id_municipio),
  CONSTRAINT fk_dado_metrica FOREIGN KEY (id_metrica) REFERENCES metrica (id_metrica),
  CONSTRAINT fk_dado_lote    FOREIGN KEY (id_lote)    REFERENCES lote_carga (id_lote) ON DELETE SET NULL,
  CONSTRAINT ck_dado_valor   CHECK (valor >= 0),
  CONSTRAINT ck_dado_mes     CHECK (DAY(data_referencia) = 1)
) ENGINE=InnoDB;

-- Indicadores de sustentabilidade urbana (baseados na ISO 37120 / ODS 11)
CREATE TABLE indicador (
  id_indicador     SMALLINT UNSIGNED AUTO_INCREMENT,
  codigo           VARCHAR(10)  NOT NULL,
  nome             VARCHAR(100) NOT NULL,
  descricao        VARCHAR(255) NOT NULL,
  formula          VARCHAR(255) NOT NULL,
  id_servico       TINYINT UNSIGNED NOT NULL,
  id_unidade       TINYINT UNSIGNED NOT NULL,
  meta             DECIMAL(12,4) NOT NULL,           -- meta de REFERÊNCIA; a meta em vigor fica na tabela meta
  sentido          ENUM('MAIOR_MELHOR','MENOR_MELHOR') NOT NULL,
  ods              VARCHAR(20) NOT NULL,
  peso_ies         DECIMAL(4,2) NOT NULL DEFAULT 1.00,  -- peso no Índice EcoCity
  CONSTRAINT pk_indicador PRIMARY KEY (id_indicador),
  CONSTRAINT uq_indicador_codigo UNIQUE (codigo),
  CONSTRAINT fk_indicador_servico FOREIGN KEY (id_servico) REFERENCES servico_publico (id_servico),
  CONSTRAINT fk_indicador_unidade FOREIGN KEY (id_unidade) REFERENCES unidade_medida (id_unidade),
  CONSTRAINT ck_indicador_meta CHECK (meta > 0),
  CONSTRAINT ck_indicador_peso CHECK (peso_ies > 0 AND peso_ies <= 5)
) ENGINE=InnoDB;

-- Valores calculados dos indicadores por município e MÊS
CREATE TABLE indicador_valor (
  id_indicador_valor BIGINT UNSIGNED AUTO_INCREMENT,
  id_indicador       SMALLINT UNSIGNED NOT NULL,
  id_municipio          SMALLINT UNSIGNED NOT NULL,
  periodo            DATE NOT NULL,                 -- sempre o 1º dia do mês
  valor              DECIMAL(14,4) NOT NULL,
  origem             ENUM('REAL','DERIVADO','ESTIMADO') NOT NULL,  -- a pior origem entre os dados usados no cálculo
  calculado_em       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_indicador_valor PRIMARY KEY (id_indicador_valor),
  CONSTRAINT uq_indicador_valor UNIQUE (id_indicador, id_municipio, periodo),
  CONSTRAINT fk_iv_indicador FOREIGN KEY (id_indicador) REFERENCES indicador (id_indicador),
  CONSTRAINT fk_iv_municipio    FOREIGN KEY (id_municipio)    REFERENCES municipio (id_municipio),
  CONSTRAINT ck_iv_periodo   CHECK (DAY(periodo) = 1),
  CONSTRAINT ck_iv_valor     CHECK (valor >= 0)
) ENGINE=InnoDB;

-- Análises geradas pela camada de IA (apoio à decisão — não substitui o especialista)
CREATE TABLE analise_ia (
  id_analise     INT UNSIGNED AUTO_INCREMENT,
  id_indicador   SMALLINT UNSIGNED NOT NULL,
  id_municipio      SMALLINT UNSIGNED NOT NULL,
  tipo           ENUM('TENDENCIA','ANOMALIA','PREVISAO','CORRELACAO','ALERTA_META') NOT NULL,
  titulo         VARCHAR(150) NOT NULL,
  descricao      TEXT NOT NULL,
  confianca      DECIMAL(5,2) NOT NULL,             -- %
  severidade     ENUM('INFO','ATENCAO','CRITICO') NOT NULL DEFAULT 'INFO',
  modelo_versao  VARCHAR(30) NOT NULL,
  gerada_em      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status         ENUM('NOVA','EM_ANALISE','VALIDADA','DESCARTADA') NOT NULL DEFAULT 'NOVA',
  revisada_por   INT UNSIGNED NULL,
  CONSTRAINT pk_analise PRIMARY KEY (id_analise),
  CONSTRAINT fk_analise_indicador FOREIGN KEY (id_indicador) REFERENCES indicador (id_indicador),
  CONSTRAINT fk_analise_municipio    FOREIGN KEY (id_municipio)    REFERENCES municipio (id_municipio),
  CONSTRAINT fk_analise_revisor   FOREIGN KEY (revisada_por) REFERENCES usuario (id_usuario) ON DELETE SET NULL,
  CONSTRAINT ck_analise_conf CHECK (confianca BETWEEN 0 AND 100)
) ENGINE=InnoDB;

-- Ações/estratégias registradas por gestores e especialistas
CREATE TABLE acao (
  id_acao           INT UNSIGNED AUTO_INCREMENT,
  titulo            VARCHAR(150) NOT NULL,
  descricao         TEXT NOT NULL,
  id_municipio         SMALLINT UNSIGNED NOT NULL,
  id_indicador_alvo SMALLINT UNSIGNED NOT NULL,
  id_responsavel    INT UNSIGNED NOT NULL,
  id_analise        INT UNSIGNED NULL,               -- análise de IA que motivou a ação
  data_inicio       DATE NOT NULL,
  data_fim_prevista DATE NOT NULL,
  orcamento         DECIMAL(14,2) NOT NULL DEFAULT 0,
  status            ENUM('PLANEJADA','EM_EXECUCAO','CONCLUIDA','CANCELADA') NOT NULL DEFAULT 'PLANEJADA',
  criada_em         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_acao PRIMARY KEY (id_acao),
  CONSTRAINT fk_acao_municipio      FOREIGN KEY (id_municipio)         REFERENCES municipio (id_municipio),
  CONSTRAINT fk_acao_indicador   FOREIGN KEY (id_indicador_alvo) REFERENCES indicador (id_indicador),
  CONSTRAINT fk_acao_responsavel FOREIGN KEY (id_responsavel)    REFERENCES usuario (id_usuario),
  CONSTRAINT fk_acao_analise     FOREIGN KEY (id_analise)        REFERENCES analise_ia (id_analise) ON DELETE SET NULL,
  CONSTRAINT ck_acao_datas     CHECK (data_fim_prevista >= data_inicio),
  CONSTRAINT ck_acao_orcamento CHECK (orcamento >= 0)
) ENGINE=InnoDB;

-- Resultados medidos das ações (antes x depois)
CREATE TABLE resultado (
  id_resultado    INT UNSIGNED AUTO_INCREMENT,
  id_acao         INT UNSIGNED NOT NULL,
  id_indicador    SMALLINT UNSIGNED NOT NULL,
  valor_antes     DECIMAL(14,4) NOT NULL,
  valor_depois    DECIMAL(14,4) NOT NULL,
  data_avaliacao  DATE NOT NULL,
  avaliacao       ENUM('POSITIVO','NEUTRO','NEGATIVO') NOT NULL,
  observacao      VARCHAR(500) NULL,
  registrado_por  INT UNSIGNED NOT NULL,
  CONSTRAINT pk_resultado PRIMARY KEY (id_resultado),
  CONSTRAINT uq_resultado UNIQUE (id_acao, id_indicador, data_avaliacao),
  CONSTRAINT fk_resultado_acao      FOREIGN KEY (id_acao)        REFERENCES acao (id_acao) ON DELETE CASCADE,
  CONSTRAINT fk_resultado_indicador FOREIGN KEY (id_indicador)   REFERENCES indicador (id_indicador),
  CONSTRAINT fk_resultado_usuario   FOREIGN KEY (registrado_por) REFERENCES usuario (id_usuario),
  CONSTRAINT ck_resultado_valores CHECK (valor_antes >= 0 AND valor_depois >= 0)
) ENGINE=InnoDB;

-- Trilha de auditoria (alimentada por triggers)
CREATE TABLE auditoria (
  id_auditoria   BIGINT UNSIGNED AUTO_INCREMENT,
  tabela         VARCHAR(40) NOT NULL,
  operacao       ENUM('INSERT','UPDATE','DELETE') NOT NULL,
  id_registro    BIGINT UNSIGNED NOT NULL,
  usuario_bd     VARCHAR(100) NOT NULL,
  ocorrido_em    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  dados_antigos  JSON NULL,
  dados_novos    JSON NULL,
  CONSTRAINT pk_auditoria PRIMARY KEY (id_auditoria)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  CONFIANÇA: login dos usuários, credencial dos analistas e metas
-- ---------------------------------------------------------------------
-- Registro de cada tentativa de login (sucesso ou falha) — base do bloqueio e da auditoria de acesso
CREATE TABLE acesso_log (
  id_acesso     BIGINT UNSIGNED AUTO_INCREMENT,
  id_usuario    INT UNSIGNED NULL,                       -- NULL quando o e-mail nem existe
  email_tentado VARCHAR(120) NOT NULL,
  resultado     ENUM('SUCESSO','SENHA_ERRADA','CODIGO_MFA_ERRADO','CHAVE_ADMIN_ERRADA','BLOQUEADO','INATIVO','SENHA_EXPIRADA','CADASTRO_EM_ANALISE') NOT NULL,
  ip            VARCHAR(45) NULL,
  ocorrido_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_acesso_log PRIMARY KEY (id_acesso),
  CONSTRAINT fk_acesso_usuario FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Credencial profissional do analista: só analista VERIFICADO e dentro da validade publica análises
CREATE TABLE credencial_analista (
  id_usuario      INT UNSIGNED NOT NULL,
  orgao_vinculo   VARCHAR(120) NOT NULL,                 -- onde trabalha (concessionária, secretaria, universidade...)
  registro_profissional VARCHAR(40) NOT NULL,            -- ex.: CREA, CRQ, CRBio, CORECON
  id_servico      TINYINT UNSIGNED NULL,                 -- área em que pode publicar (NULL = todas)
  nivel           ENUM('JUNIOR','PLENO','SENIOR') NOT NULL,
  status          ENUM('PENDENTE','VERIFICADA','SUSPENSA','REVOGADA') NOT NULL DEFAULT 'PENDENTE',
  verificado_por  INT UNSIGNED NULL,                     -- administrador que conferiu os documentos
  verificado_em   DATETIME NULL,
  valida_ate      DATE NULL,                             -- renovação anual
  observacao      VARCHAR(300) NULL,
  CONSTRAINT pk_credencial PRIMARY KEY (id_usuario),
  CONSTRAINT fk_cred_usuario  FOREIGN KEY (id_usuario)     REFERENCES usuario (id_usuario) ON DELETE CASCADE,
  CONSTRAINT fk_cred_servico  FOREIGN KEY (id_servico)     REFERENCES servico_publico (id_servico),
  CONSTRAINT fk_cred_verif    FOREIGN KEY (verificado_por) REFERENCES usuario (id_usuario),
  CONSTRAINT uq_cred_registro UNIQUE (registro_profissional),
  CONSTRAINT ck_cred_verificada CHECK (status <> 'VERIFICADA' OR (verificado_por IS NOT NULL AND verificado_em IS NOT NULL AND valida_ate IS NOT NULL))
) ENGINE=InnoDB;

-- Cadastro profissional de ANALISTA e GESTOR: comprova quem é a pessoa e o vínculo
-- com um órgão ANTES de liberar a página. O ADMIN confere os documentos e aprova.
-- (O cidadão não tem esta tabela: o cadastro dele é só nome, e-mail, telefone e cidade.)
CREATE TABLE cadastro_profissional (
  id_usuario          INT UNSIGNED NOT NULL,
  cpf_hash            CHAR(64)     NOT NULL,             -- SHA-256 do CPF: impede cadastro duplicado sem guardar o número (LGPD)
  cpf_final           CHAR(2)      NOT NULL,             -- 2 últimos dígitos, só para conferência visual
  email_institucional VARCHAR(120) NOT NULL,             -- e-mail do órgão (gmail, hotmail etc. são recusados)
  telefone_institucional VARCHAR(20) NOT NULL,
  orgao               VARCHAR(120) NOT NULL,             -- prefeitura, secretaria, concessionária, universidade...
  cargo               VARCHAR(80)  NOT NULL,
  matricula           VARCHAR(30)  NOT NULL,             -- matrícula funcional no órgão
  formacao            VARCHAR(120) NOT NULL,             -- ex.: Engenharia Ambiental (USP, 2018)
  registro_conselho   VARCHAR(40)  NULL,                 -- CREA, CRQ, CRBio, CORECON... (analista)
  portaria_nomeacao   VARCHAR(120) NULL,                 -- ato de nomeação no Diário Oficial (obrigatório para gestor)
  id_municipio_atuacao SMALLINT UNSIGNED NULL,           -- cidade onde atua (obrigatório para gestor)
  documento_url       VARCHAR(300) NOT NULL,             -- declaração de vínculo assinada pelo órgão (PDF)
  justificativa       VARCHAR(600) NOT NULL,             -- por que precisa do acesso
  aceite_termo_em     DATETIME     NOT NULL,             -- aceitou o termo de responsabilidade e uso dos dados
  ip_aceite           VARCHAR(45)  NULL,
  status              ENUM('EM_ANALISE','APROVADO','RECUSADO','SUSPENSO') NOT NULL DEFAULT 'EM_ANALISE',
  analisado_por       INT UNSIGNED NULL,                 -- ADMIN que conferiu
  analisado_em        DATETIME     NULL,
  motivo_decisao      VARCHAR(300) NULL,
  valido_ate          DATE         NULL,                 -- revalidação anual do vínculo
  criado_em           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_cadastro_prof PRIMARY KEY (id_usuario),
  CONSTRAINT fk_cadprof_usuario  FOREIGN KEY (id_usuario)  REFERENCES usuario (id_usuario) ON DELETE CASCADE,
  CONSTRAINT fk_cadprof_analisou FOREIGN KEY (analisado_por) REFERENCES usuario (id_usuario),
  CONSTRAINT fk_cadprof_municipio FOREIGN KEY (id_municipio_atuacao) REFERENCES municipio (id_municipio),
  CONSTRAINT uq_cadprof_cpf   UNIQUE (cpf_hash),
  CONSTRAINT uq_cadprof_email UNIQUE (email_institucional),
  CONSTRAINT ck_cadprof_aprov CHECK (status = 'EM_ANALISE' OR (analisado_por IS NOT NULL AND analisado_em IS NOT NULL)),
  CONSTRAINT ck_cadprof_valid CHECK (status <> 'APROVADO' OR valido_ate IS NOT NULL)
) ENGINE=InnoDB;

-- Metas dos indicadores, com vigência (histórico): proposta pelo GESTOR, parecer técnico do ANALISTA,
-- aprovação pelo GESTOR. id_municipio NULL = meta padrão para todas as cidades.
CREATE TABLE meta (
  id_meta          INT UNSIGNED AUTO_INCREMENT,
  id_indicador     SMALLINT UNSIGNED NOT NULL,
  id_municipio     SMALLINT UNSIGNED NULL,
  valor            DECIMAL(12,4) NOT NULL,
  vigencia_inicio  DATE NOT NULL,                        -- 1º dia do mês em que passa a valer
  vigencia_fim     DATE NULL,                            -- NULL = em vigor
  justificativa    VARCHAR(600) NOT NULL,                -- por que esse valor
  referencia       VARCHAR(200) NOT NULL,                -- base técnica: ODS, ISO 37120, lei, plano municipal...
  status           ENUM('PROPOSTA','PARECER_EMITIDO','APROVADA','REJEITADA','SUBSTITUIDA') NOT NULL DEFAULT 'PROPOSTA',
  proposta_por     INT UNSIGNED NOT NULL,                -- gestor
  parecer_por      INT UNSIGNED NULL,                    -- analista credenciado
  parecer_favoravel BOOLEAN NULL,
  parecer          VARCHAR(1000) NULL,
  aprovada_por     INT UNSIGNED NULL,                    -- gestor
  criada_em        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  decidida_em      DATETIME NULL,
  CONSTRAINT pk_meta PRIMARY KEY (id_meta),
  CONSTRAINT fk_meta_indicador FOREIGN KEY (id_indicador) REFERENCES indicador (id_indicador),
  CONSTRAINT fk_meta_municipio FOREIGN KEY (id_municipio) REFERENCES municipio (id_municipio),
  CONSTRAINT fk_meta_proposta  FOREIGN KEY (proposta_por) REFERENCES usuario (id_usuario),
  CONSTRAINT fk_meta_parecer   FOREIGN KEY (parecer_por)  REFERENCES usuario (id_usuario),
  CONSTRAINT fk_meta_aprovada  FOREIGN KEY (aprovada_por) REFERENCES usuario (id_usuario),
  CONSTRAINT ck_meta_valor     CHECK (valor > 0),
  CONSTRAINT ck_meta_vigencia  CHECK (DAY(vigencia_inicio) = 1 AND (vigencia_fim IS NULL OR vigencia_fim >= vigencia_inicio)),
  CONSTRAINT ck_meta_aprovada  CHECK (status NOT IN ('APROVADA','SUBSTITUIDA') OR (parecer_por IS NOT NULL AND aprovada_por IS NOT NULL))
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  ANÁLISES DOS ANALISTAS (compartilhadas no sistema, com revisão por pares)
-- ---------------------------------------------------------------------
CREATE TABLE analise_publicada (
  id_analise_pub   INT UNSIGNED AUTO_INCREMENT,
  titulo           VARCHAR(200) NOT NULL,
  resumo           VARCHAR(500) NOT NULL,
  conteudo         TEXT NOT NULL,
  id_servico       TINYINT UNSIGNED NOT NULL,             -- área da análise
  periodo_inicio   DATE NOT NULL,
  periodo_fim      DATE NOT NULL,
  id_autor         INT UNSIGNED NOT NULL,
  status           ENUM('RASCUNHO','EM_REVISAO','PUBLICADA','DEVOLVIDA','ARQUIVADA') NOT NULL DEFAULT 'RASCUNHO',
  nivel_confianca  ENUM('ALTA','MEDIA','BAIXA') NULL,     -- calculado pelo banco a partir das evidências
  pct_base_oficial DECIMAL(5,2) NULL,
  versao           SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  revisado_por     INT UNSIGNED NULL,
  parecer_revisao  VARCHAR(1000) NULL,
  criada_em        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  enviada_em       DATETIME NULL,
  publicada_em     DATETIME NULL,
  CONSTRAINT pk_analise_pub PRIMARY KEY (id_analise_pub),
  CONSTRAINT fk_ap_servico FOREIGN KEY (id_servico) REFERENCES servico_publico (id_servico),
  CONSTRAINT fk_ap_autor   FOREIGN KEY (id_autor)   REFERENCES usuario (id_usuario),
  CONSTRAINT fk_ap_revisor FOREIGN KEY (revisado_por) REFERENCES usuario (id_usuario),
  CONSTRAINT ck_ap_periodo CHECK (periodo_fim >= periodo_inicio AND DAY(periodo_inicio) = 1 AND DAY(periodo_fim) = 1),
  CONSTRAINT ck_ap_pct     CHECK (pct_base_oficial IS NULL OR pct_base_oficial BETWEEN 0 AND 100),
  CONSTRAINT ck_ap_publicada CHECK (status <> 'PUBLICADA' OR (revisado_por IS NOT NULL AND revisado_por <> id_autor AND nivel_confianca IS NOT NULL))
) ENGINE=InnoDB;

-- Cidades tratadas em cada análise (N:N)
CREATE TABLE analise_municipio (
  id_analise_pub INT UNSIGNED NOT NULL,
  id_municipio   SMALLINT UNSIGNED NOT NULL,
  CONSTRAINT pk_analise_municipio PRIMARY KEY (id_analise_pub, id_municipio),
  CONSTRAINT fk_am_analise   FOREIGN KEY (id_analise_pub) REFERENCES analise_publicada (id_analise_pub) ON DELETE CASCADE,
  CONSTRAINT fk_am_municipio FOREIGN KEY (id_municipio)   REFERENCES municipio (id_municipio)
) ENGINE=InnoDB;

-- Evidências: em que dados a análise se apoia (sem evidência do banco, não pode ser enviada)
CREATE TABLE analise_evidencia (
  id_evidencia   INT UNSIGNED AUTO_INCREMENT,
  id_analise_pub INT UNSIGNED NOT NULL,
  tipo           ENUM('INDICADOR','CONSULTA_SQL','FONTE_EXTERNA') NOT NULL,
  id_indicador   SMALLINT UNSIGNED NULL,                  -- tipo INDICADOR: série de um indicador...
  id_municipio   SMALLINT UNSIGNED NULL,                  -- ...de uma cidade no período da análise
  consulta_sql   TEXT NULL,                               -- tipo CONSULTA_SQL: consulta que reproduz o resultado
  url            VARCHAR(300) NULL,                       -- tipo FONTE_EXTERNA: documento oficial citado
  descricao      VARCHAR(300) NOT NULL,
  CONSTRAINT pk_evidencia PRIMARY KEY (id_evidencia),
  CONSTRAINT fk_ev_analise   FOREIGN KEY (id_analise_pub) REFERENCES analise_publicada (id_analise_pub) ON DELETE CASCADE,
  CONSTRAINT fk_ev_indicador FOREIGN KEY (id_indicador)   REFERENCES indicador (id_indicador),
  CONSTRAINT fk_ev_municipio FOREIGN KEY (id_municipio)   REFERENCES municipio (id_municipio),
  CONSTRAINT ck_ev_tipo CHECK (
       (tipo = 'INDICADOR'     AND id_indicador IS NOT NULL AND id_municipio IS NOT NULL)
    OR (tipo = 'CONSULTA_SQL'  AND consulta_sql IS NOT NULL)
    OR (tipo = 'FONTE_EXTERNA' AND url IS NOT NULL))
) ENGINE=InnoDB;

-- Comentários dos colegas nas análises publicadas
CREATE TABLE analise_comentario (
  id_comentario  INT UNSIGNED AUTO_INCREMENT,
  id_analise_pub INT UNSIGNED NOT NULL,
  id_usuario     INT UNSIGNED NOT NULL,
  texto          VARCHAR(1000) NOT NULL,
  criado_em      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_comentario PRIMARY KEY (id_comentario),
  CONSTRAINT fk_com_analise FOREIGN KEY (id_analise_pub) REFERENCES analise_publicada (id_analise_pub) ON DELETE CASCADE,
  CONSTRAINT fk_com_usuario FOREIGN KEY (id_usuario)     REFERENCES usuario (id_usuario),
  CONSTRAINT ck_com_texto   CHECK (CHAR_LENGTH(TRIM(texto)) >= 3)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  COPILOTO ECOCITY (IA generativa com dados do banco)
-- ---------------------------------------------------------------------
-- Relatórios escritos pela IA. Só ficam públicos depois de APROVADOS por uma pessoa.
CREATE TABLE relatorio_ia (
  id_relatorio      INT UNSIGNED AUTO_INCREMENT,
  titulo            VARCHAR(200) NOT NULL,
  tipo              ENUM('MUNICIPIO','COMPARATIVO') NOT NULL,     -- 1 cidade ou várias cidades
  publico           ENUM('GESTOR','CIDADAO') NOT NULL,            -- linguagem técnica ou simples
  periodo_inicio    DATE NOT NULL,                                -- 1º dia do mês inicial
  periodo_fim       DATE NOT NULL,                                -- 1º dia do mês final
  conteudo          MEDIUMTEXT NOT NULL,                          -- texto do relatório (Markdown)
  dados_usados      JSON NOT NULL,                                -- números exatos usados (rastreabilidade)
  pct_dados_oficiais DECIMAL(5,2) NOT NULL,                       -- quanto do relatório se apoia em dado oficial
  modelo            VARCHAR(60) NOT NULL,                         -- motor que escreveu (modelo de IA ou modelo local)
  status            ENUM('RASCUNHO','APROVADO','REJEITADO') NOT NULL DEFAULT 'RASCUNHO',
  solicitado_por    INT UNSIGNED NOT NULL,
  revisado_por      INT UNSIGNED NULL,
  comentario_revisao VARCHAR(500) NULL,
  criado_em         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revisado_em       DATETIME NULL,
  CONSTRAINT pk_relatorio PRIMARY KEY (id_relatorio),
  CONSTRAINT fk_relatorio_solicitante FOREIGN KEY (solicitado_por) REFERENCES usuario (id_usuario),
  CONSTRAINT fk_relatorio_revisor     FOREIGN KEY (revisado_por)  REFERENCES usuario (id_usuario),
  CONSTRAINT ck_relatorio_periodo CHECK (periodo_fim >= periodo_inicio AND DAY(periodo_inicio) = 1 AND DAY(periodo_fim) = 1),
  CONSTRAINT ck_relatorio_pct     CHECK (pct_dados_oficiais BETWEEN 0 AND 100),
  CONSTRAINT ck_relatorio_revisao CHECK (status = 'RASCUNHO' OR revisado_por IS NOT NULL)
) ENGINE=InnoDB;

-- Municípios incluídos em cada relatório (relação N:N — mantém a 3FN)
CREATE TABLE relatorio_municipio (
  id_relatorio  INT UNSIGNED NOT NULL,
  id_municipio  SMALLINT UNSIGNED NOT NULL,
  CONSTRAINT pk_relatorio_municipio PRIMARY KEY (id_relatorio, id_municipio),
  CONSTRAINT fk_rm_relatorio FOREIGN KEY (id_relatorio) REFERENCES relatorio_ia (id_relatorio) ON DELETE CASCADE,
  CONSTRAINT fk_rm_municipio FOREIGN KEY (id_municipio) REFERENCES municipio (id_municipio)
) ENGINE=InnoDB;

-- Perguntas em português feitas ao Copiloto e o SQL que a IA gerou
CREATE TABLE pergunta_ia (
  id_pergunta      INT UNSIGNED AUTO_INCREMENT,
  id_usuario       INT UNSIGNED NOT NULL,
  pergunta         VARCHAR(500) NOT NULL,
  sql_gerado       TEXT NULL,
  situacao         ENUM('RESPONDIDA','BLOQUEADA','SEM_RESPOSTA','ERRO') NOT NULL,
  motivo_bloqueio  VARCHAR(200) NULL,                             -- por que a consulta foi barrada
  linhas_retornadas INT UNSIGNED NOT NULL DEFAULT 0,
  tempo_ms         INT UNSIGNED NOT NULL DEFAULT 0,
  modelo           VARCHAR(60) NOT NULL,
  criada_em        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_pergunta PRIMARY KEY (id_pergunta),
  CONSTRAINT fk_pergunta_usuario FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario),
  CONSTRAINT ck_pergunta_bloqueio CHECK (situacao <> 'BLOQUEADA' OR motivo_bloqueio IS NOT NULL)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  CAMADA STAGING (dados brutos, ainda não validados)
-- ---------------------------------------------------------------------
CREATE TABLE stg_medicao_bruta (
  id_stg          BIGINT UNSIGNED AUTO_INCREMENT,
  id_lote         INT UNSIGNED NOT NULL,
  codigo_metrica  VARCHAR(50)  NULL,
  nome_municipio     VARCHAR(80)  NULL,
  data_texto      VARCHAR(20)  NULL,
  valor_texto     VARCHAR(40)  NULL,
  origem_informada     VARCHAR(10)  NULL,          -- REAL (do mês), DERIVADO (total oficial do ano ÷ meses) ou ESTIMADO; vazio = REAL
  referencia_informada VARCHAR(300) NULL,          -- de onde veio o número (vai para dado.referencia_origem)
  processado      BOOLEAN NOT NULL DEFAULT FALSE,
  erro            VARCHAR(150) NULL,
  recebido_em     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_stg PRIMARY KEY (id_stg),
  CONSTRAINT fk_stg_lote FOREIGN KEY (id_lote) REFERENCES lote_carga (id_lote) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Robô de coleta: registro de cada verificação de fonte (v17).
-- O robô confere as fontes todo dia; só baixa de novo quando a "versão"
-- publicada mudou (data do arquivo, ano novo etc.). Assim dá para provar
-- QUANDO o site do órgão foi atualizado e o que entrou no banco.
-- ---------------------------------------------------------------------
CREATE TABLE coleta_verificacao (
  id_verificacao  INT UNSIGNED AUTO_INCREMENT,
  id_fonte        SMALLINT UNSIGNED NOT NULL,
  verificado_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  versao_fonte    VARCHAR(120) NULL,                -- ex.: data do arquivo publicado, último ano disponível
  novidade        BOOLEAN NOT NULL DEFAULT FALSE,   -- a fonte publicou algo novo desde a última verificação?
  registros_novos INT UNSIGNED NOT NULL DEFAULT 0,  -- valores que entraram ou mudaram no banco
  status          ENUM('OK','SEM_NOVIDADE','FALHA') NOT NULL,
  mensagem        VARCHAR(255) NULL,
  id_lote         INT UNSIGNED NULL,
  CONSTRAINT pk_verificacao PRIMARY KEY (id_verificacao),
  CONSTRAINT fk_verif_fonte FOREIGN KEY (id_fonte) REFERENCES fonte_dados (id_fonte),
  CONSTRAINT fk_verif_lote  FOREIGN KEY (id_lote)  REFERENCES lote_carga (id_lote) ON DELETE SET NULL,
  INDEX ix_verif_fonte (id_fonte, verificado_em)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  CAMADA DATA WAREHOUSE (modelo estrela — desnormalizado de propósito)
-- ---------------------------------------------------------------------
CREATE TABLE dim_tempo (
  sk_tempo     INT UNSIGNED NOT NULL,          -- AAAAMM (ex.: 202609)
  data_inicio  DATE NOT NULL,
  ano          SMALLINT UNSIGNED NOT NULL,
  semestre     TINYINT UNSIGNED NOT NULL,
  trimestre    TINYINT UNSIGNED NOT NULL,
  mes          TINYINT UNSIGNED NOT NULL,
  nome_mes     VARCHAR(12) NOT NULL,           -- 'setembro'
  rotulo       CHAR(8) NOT NULL,               -- 'set/2026'
  ano_mes      CHAR(7) NOT NULL,               -- '2026-09'
  CONSTRAINT pk_dim_tempo PRIMARY KEY (sk_tempo),
  CONSTRAINT uq_dim_tempo_data UNIQUE (data_inicio),
  CONSTRAINT ck_dim_tempo_mes CHECK (mes BETWEEN 1 AND 12)
) ENGINE=InnoDB;

CREATE TABLE dim_municipio (
  sk_municipio        SMALLINT UNSIGNED AUTO_INCREMENT,
  id_municipio_origem SMALLINT UNSIGNED NOT NULL,
  nome             VARCHAR(60) NOT NULL,
  codigo_ibge      CHAR(7) NOT NULL,
  regiao_metropolitana VARCHAR(40) NOT NULL,
  populacao        INT UNSIGNED NOT NULL,
  area_km2         DECIMAL(9,2) NOT NULL,
  densidade_hab_km2 DECIMAL(10,2) NOT NULL,
  atualizado_em    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_dim_municipio PRIMARY KEY (sk_municipio),
  CONSTRAINT uq_dim_municipio_origem UNIQUE (id_municipio_origem)
) ENGINE=InnoDB;

CREATE TABLE dim_servico (
  sk_servico        TINYINT UNSIGNED AUTO_INCREMENT,
  id_servico_origem TINYINT UNSIGNED NOT NULL,
  nome              VARCHAR(30) NOT NULL,
  CONSTRAINT pk_dim_servico PRIMARY KEY (sk_servico),
  CONSTRAINT uq_dim_servico_origem UNIQUE (id_servico_origem)
) ENGINE=InnoDB;

CREATE TABLE dim_metrica (
  sk_metrica        SMALLINT UNSIGNED AUTO_INCREMENT,
  id_metrica_origem SMALLINT UNSIGNED NOT NULL,
  codigo            VARCHAR(30) NOT NULL,
  nome              VARCHAR(100) NOT NULL,
  unidade           VARCHAR(20) NOT NULL,
  CONSTRAINT pk_dim_metrica PRIMARY KEY (sk_metrica),
  CONSTRAINT uq_dim_metrica_origem UNIQUE (id_metrica_origem)
) ENGINE=InnoDB;

CREATE TABLE dim_indicador (
  sk_indicador        SMALLINT UNSIGNED AUTO_INCREMENT,
  id_indicador_origem SMALLINT UNSIGNED NOT NULL,
  codigo              VARCHAR(10) NOT NULL,
  nome                VARCHAR(100) NOT NULL,
  unidade             VARCHAR(20) NOT NULL,
  sentido             VARCHAR(15) NOT NULL,
  meta                DECIMAL(12,4) NOT NULL,
  peso_ies            DECIMAL(4,2) NOT NULL,
  ods                 VARCHAR(20) NOT NULL,
  CONSTRAINT pk_dim_indicador PRIMARY KEY (sk_indicador),
  CONSTRAINT uq_dim_indicador_origem UNIQUE (id_indicador_origem)
) ENGINE=InnoDB;

-- Fato 1: medições por mês x município x métrica
CREATE TABLE fato_medicao (
  sk_tempo        INT UNSIGNED NOT NULL,
  sk_municipio       SMALLINT UNSIGNED NOT NULL,
  sk_metrica      SMALLINT UNSIGNED NOT NULL,
  sk_servico      TINYINT UNSIGNED NOT NULL,
  valor_total     DECIMAL(18,4) NOT NULL,
  valor_per_capita DECIMAL(14,6) NOT NULL,
  qtd_registros   INT UNSIGNED NOT NULL,
  qtd_suspeitos   INT UNSIGNED NOT NULL DEFAULT 0,
  qtd_derivados   INT UNSIGNED NOT NULL DEFAULT 0,
  qtd_estimados   INT UNSIGNED NOT NULL DEFAULT 0,
  CONSTRAINT pk_fato_medicao PRIMARY KEY (sk_tempo, sk_municipio, sk_metrica),
  CONSTRAINT fk_fm_tempo    FOREIGN KEY (sk_tempo)   REFERENCES dim_tempo (sk_tempo),
  CONSTRAINT fk_fm_municipio   FOREIGN KEY (sk_municipio)  REFERENCES dim_municipio (sk_municipio),
  CONSTRAINT fk_fm_metrica  FOREIGN KEY (sk_metrica) REFERENCES dim_metrica (sk_metrica),
  CONSTRAINT fk_fm_servico  FOREIGN KEY (sk_servico) REFERENCES dim_servico (sk_servico)
) ENGINE=InnoDB;

-- Fato 2: desempenho dos indicadores por mês x município
CREATE TABLE fato_indicador (
  sk_tempo        INT UNSIGNED NOT NULL,
  sk_municipio       SMALLINT UNSIGNED NOT NULL,
  sk_indicador    SMALLINT UNSIGNED NOT NULL,
  sk_servico      TINYINT UNSIGNED NOT NULL,
  valor           DECIMAL(14,4) NOT NULL,
  meta            DECIMAL(12,4) NOT NULL,
  atingiu_meta    BOOLEAN NOT NULL,
  score           DECIMAL(5,2) NOT NULL,       -- 0 a 100 (desempenho normalizado)
  origem          VARCHAR(8) NOT NULL,         -- REAL / DERIVADO / ESTIMADO
  CONSTRAINT pk_fato_indicador PRIMARY KEY (sk_tempo, sk_municipio, sk_indicador),
  CONSTRAINT fk_fi_tempo     FOREIGN KEY (sk_tempo)     REFERENCES dim_tempo (sk_tempo),
  CONSTRAINT fk_fi_municipio    FOREIGN KEY (sk_municipio)    REFERENCES dim_municipio (sk_municipio),
  CONSTRAINT fk_fi_indicador FOREIGN KEY (sk_indicador) REFERENCES dim_indicador (sk_indicador),
  CONSTRAINT fk_fi_servico   FOREIGN KEY (sk_servico)   REFERENCES dim_servico (sk_servico),
  CONSTRAINT ck_fi_score CHECK (score BETWEEN 0 AND 100)
) ENGINE=InnoDB;

-- >>>>>>>>>>>>>>>>>>>> 02_indices.sql <<<<<<<<<<<<<<<<<<<<
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

-- >>>>>>>>>>>>>>>>>>>> 03_funcoes_views.sql <<<<<<<<<<<<<<<<<<<<
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

-- >>>>>>>>>>>>>>>>>>>> 04_triggers.sql <<<<<<<<<<<<<<<<<<<<
-- =====================================================================
--  EcoCity — Script 04: triggers (qualidade de dados, auditoria e alertas)
-- =====================================================================
USE ecocity;

DELIMITER $$

-- ---------------------------------------------------------------------
-- T1: Validação e marcação de qualidade antes de inserir um DADO
--     - data_referencia é normalizada para o 1º dia do mês (dados mensais)
--     - valores 3x acima (ou 70% abaixo) da média dos 3 meses anteriores
--       são marcados como SUSPEITO para revisão (não são descartados)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_dado_bi $$
CREATE TRIGGER trg_dado_bi
BEFORE INSERT ON dado
FOR EACH ROW
BEGIN
  DECLARE v_media DECIMAL(16,4);

  IF NEW.data_referencia > CURRENT_DATE THEN
     SIGNAL SQLSTATE '45000'
       SET MESSAGE_TEXT = 'Data de referência no futuro não é permitida.';
  END IF;

  SET NEW.data_referencia = DATE_FORMAT(NEW.data_referencia, '%Y-%m-01');

  SELECT AVG(valor) INTO v_media
  FROM dado
  WHERE id_municipio  = NEW.id_municipio
    AND id_metrica = NEW.id_metrica
    AND qualidade  = 'VALIDO'
    AND data_referencia BETWEEN DATE_SUB(NEW.data_referencia, INTERVAL 3 MONTH)
                            AND DATE_SUB(NEW.data_referencia, INTERVAL 1 MONTH);

  IF v_media IS NOT NULL AND v_media > 0
     AND (NEW.valor > v_media * 3 OR NEW.valor < v_media * 0.3) THEN
     SET NEW.qualidade = 'SUSPEITO';
  END IF;
END $$

-- T2/T3: Auditoria de alterações e exclusões em DADO
DROP TRIGGER IF EXISTS trg_dado_au $$
CREATE TRIGGER trg_dado_au
AFTER UPDATE ON dado
FOR EACH ROW
BEGIN
  INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
  VALUES ('dado', 'UPDATE', OLD.id_dado, CURRENT_USER(),
          JSON_OBJECT('valor', OLD.valor, 'qualidade', OLD.qualidade, 'origem', OLD.origem),
          JSON_OBJECT('valor', NEW.valor, 'qualidade', NEW.qualidade, 'origem', NEW.origem, 'referencia', NEW.referencia_origem));
END $$

DROP TRIGGER IF EXISTS trg_dado_ad $$
CREATE TRIGGER trg_dado_ad
AFTER DELETE ON dado
FOR EACH ROW
BEGIN
  INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos)
  VALUES ('dado', 'DELETE', OLD.id_dado, CURRENT_USER(),
          JSON_OBJECT('id_municipio', OLD.id_municipio, 'id_metrica', OLD.id_metrica,
                      'data_referencia', OLD.data_referencia, 'valor', OLD.valor));
END $$

-- T4: Auditoria de mudança de status / orçamento das AÇÕES
DROP TRIGGER IF EXISTS trg_acao_au $$
CREATE TRIGGER trg_acao_au
AFTER UPDATE ON acao
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status OR OLD.orcamento <> NEW.orcamento THEN
    INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
    VALUES ('acao', 'UPDATE', OLD.id_acao, CURRENT_USER(),
            JSON_OBJECT('status', OLD.status, 'orcamento', OLD.orcamento),
            JSON_OBJECT('status', NEW.status, 'orcamento', NEW.orcamento));
  END IF;
END $$

-- T5: Impede que uma ação CANCELADA ou CONCLUIDA volte a ser PLANEJADA
DROP TRIGGER IF EXISTS trg_acao_bu $$
CREATE TRIGGER trg_acao_bu
BEFORE UPDATE ON acao
FOR EACH ROW
BEGIN
  IF OLD.status IN ('CONCLUIDA','CANCELADA') AND NEW.status = 'PLANEJADA' THEN
     SIGNAL SQLSTATE '45000'
       SET MESSAGE_TEXT = 'Ação concluída/cancelada não pode voltar para PLANEJADA.';
  END IF;
END $$

-- T6: Alerta automático — se um indicador ficar mais de 40% distante da meta
--     (no sentido ruim) no MÊS MAIS RECENTE, é criado/atualizado um alerta
--     ALERTA_META (CRITICO). Se o indicador melhorar, o alerta automático sai.
DROP PROCEDURE IF EXISTS sp_avaliar_alerta_meta $$
CREATE PROCEDURE sp_avaliar_alerta_meta(IN p_ind SMALLINT UNSIGNED, IN p_mun SMALLINT UNSIGNED,
                                        IN p_periodo DATE, IN p_valor DECIMAL(14,4), IN p_origem VARCHAR(8))
BEGIN
  DECLARE v_meta DECIMAL(12,4);
  DECLARE v_sentido VARCHAR(15);
  DECLARE v_nome VARCHAR(100);
  DECLARE v_desvio DECIMAL(10,2);
  DECLARE v_titulo VARCHAR(150);
  DECLARE v_desc TEXT;

  -- só o mês mais recente do indicador/município gera alerta
  IF NOT EXISTS (SELECT 1 FROM indicador_valor
                 WHERE id_indicador = p_ind AND id_municipio = p_mun AND periodo > p_periodo) THEN

    SELECT sentido, nome INTO v_sentido, v_nome FROM indicador WHERE id_indicador = p_ind;
    SET v_meta = fn_meta_vigente(p_ind, p_mun, p_periodo);      -- meta em vigor naquele mês

    SET v_desvio = CASE WHEN v_sentido = 'MENOR_MELHOR'
                        THEN (p_valor - v_meta) / v_meta * 100
                        ELSE (v_meta - p_valor) / v_meta * 100 END;
    SET v_titulo = CONCAT(v_nome, ': ', ROUND(v_desvio,1), '% distante da meta');
    SET v_desc = CONCAT('Valor ', ROUND(p_valor,2), ' em ', DATE_FORMAT(p_periodo, '%m/%Y'), ' (meta ', ROUND(v_meta,2), ').',
                        CASE p_origem WHEN 'ESTIMADO' THEN ' Atenção: calculado com dado ESTIMADO.'
                                      WHEN 'DERIVADO' THEN ' Calculado a partir de dado oficial de período maior.'
                                      ELSE ' Calculado com dados oficiais do mês.' END,
                        ' Gerado automaticamente por regra de negócio.');

    IF v_desvio > 40 THEN
      IF EXISTS (SELECT 1 FROM analise_ia WHERE id_indicador = p_ind AND id_municipio = p_mun
                   AND tipo = 'ALERTA_META' AND status = 'NOVA') THEN
        UPDATE analise_ia SET titulo = v_titulo, descricao = v_desc, gerada_em = NOW()
        WHERE id_indicador = p_ind AND id_municipio = p_mun AND tipo = 'ALERTA_META' AND status = 'NOVA';
      ELSEIF NOT EXISTS (SELECT 1 FROM analise_ia WHERE id_indicador = p_ind AND id_municipio = p_mun
                           AND tipo = 'ALERTA_META' AND status = 'EM_ANALISE') THEN
        INSERT INTO analise_ia (id_indicador, id_municipio, tipo, titulo, descricao, confianca, severidade, modelo_versao)
        VALUES (p_ind, p_mun, 'ALERTA_META', v_titulo, v_desc, 100.00, 'CRITICO', 'regra-trigger-v3');
      END IF;
    ELSE
      DELETE FROM analise_ia WHERE id_indicador = p_ind AND id_municipio = p_mun
                               AND tipo = 'ALERTA_META' AND status = 'NOVA';
    END IF;
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_indicador_valor_ai $$
CREATE TRIGGER trg_indicador_valor_ai
AFTER INSERT ON indicador_valor
FOR EACH ROW
BEGIN
  CALL sp_avaliar_alerta_meta(NEW.id_indicador, NEW.id_municipio, NEW.periodo, NEW.valor, NEW.origem);
END $$

DROP TRIGGER IF EXISTS trg_indicador_valor_au $$
CREATE TRIGGER trg_indicador_valor_au
AFTER UPDATE ON indicador_valor
FOR EACH ROW
BEGIN
  IF NEW.valor <> OLD.valor OR NEW.origem <> OLD.origem THEN
    CALL sp_avaliar_alerta_meta(NEW.id_indicador, NEW.id_municipio, NEW.periodo, NEW.valor, NEW.origem);
  END IF;
END $$

-- T7: Usuários — e-mail em minúsculas e regras de cadastro por perfil:
--   - ADMIN só existe com chave individual (criado pelo DBA, nunca pelo site);
--   - ANALISTA e GESTOR nascem EM_ANALISE: só entram depois que o ADMIN aprova o cadastro profissional.
DROP TRIGGER IF EXISTS trg_usuario_bi $$
CREATE TRIGGER trg_usuario_bi
BEFORE INSERT ON usuario
FOR EACH ROW
BEGIN
  DECLARE v_perfil VARCHAR(30) DEFAULT (SELECT nome FROM perfil WHERE id_perfil = NEW.id_perfil);
  SET NEW.email = LOWER(TRIM(NEW.email));
  IF v_perfil = 'ADMIN' AND NEW.chave_admin_hash IS NULL THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Administrador só pode ser criado pelo DBA, com chave individual.';
  END IF;
  IF v_perfil IN ('ANALISTA','GESTOR') THEN SET NEW.status_cadastro = 'EM_ANALISE'; END IF;
END $$

DROP TRIGGER IF EXISTS trg_usuario_bu $$
CREATE TRIGGER trg_usuario_bu
BEFORE UPDATE ON usuario
FOR EACH ROW
BEGIN
  DECLARE v_perfil VARCHAR(30) DEFAULT (SELECT nome FROM perfil WHERE id_perfil = NEW.id_perfil);
  IF v_perfil = 'ADMIN' AND NEW.chave_admin_hash IS NULL THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ninguém vira administrador sem chave individual (só o DBA concede).';
  END IF;
  IF v_perfil IN ('ANALISTA','GESTOR') AND NEW.status_cadastro = 'ATIVO'
     AND (OLD.status_cadastro <> 'ATIVO' OR NEW.id_perfil <> OLD.id_perfil)
     AND NOT EXISTS (SELECT 1 FROM cadastro_profissional c WHERE c.id_usuario = NEW.id_usuario
                     AND c.status = 'APROVADO' AND c.valido_ate >= CURRENT_DATE) THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Analista ou gestor só fica ativo com cadastro profissional aprovado pelo administrador.';
  END IF;
END $$

-- T7b: mudança de perfil ou de situação do cadastro vai para a auditoria
DROP TRIGGER IF EXISTS trg_usuario_au $$
CREATE TRIGGER trg_usuario_au
AFTER UPDATE ON usuario
FOR EACH ROW
BEGIN
  IF NEW.id_perfil <> OLD.id_perfil OR NEW.status_cadastro <> OLD.status_cadastro THEN
    INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
    VALUES ('usuario', 'UPDATE', OLD.id_usuario, CURRENT_USER(),
            JSON_OBJECT('id_perfil', OLD.id_perfil, 'status_cadastro', OLD.status_cadastro),
            JSON_OBJECT('id_perfil', NEW.id_perfil, 'status_cadastro', NEW.status_cadastro));
  END IF;
END $$


-- ---------------------------------------------------------------------
-- T8/T9: COPILOTO — revisão humana obrigatória dos relatórios da IA
--   - um relatório APROVADO ou REJEITADO não pode mais ter o texto alterado;
--   - quem pediu o relatório não pode aprová-lo (segregação de funções);
--   - toda mudança de status fica na auditoria.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_relatorio_bu $$
CREATE TRIGGER trg_relatorio_bu
BEFORE UPDATE ON relatorio_ia
FOR EACH ROW
BEGIN
  IF OLD.status <> 'RASCUNHO' AND (NEW.conteudo <> OLD.conteudo OR NEW.dados_usados <> OLD.dados_usados) THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Relatório já revisado não pode ter o texto alterado.';
  END IF;
  IF OLD.status <> 'RASCUNHO' AND NEW.status <> OLD.status THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Relatório já revisado não pode mudar de situação.';
  END IF;
  IF NEW.status <> 'RASCUNHO' AND OLD.status = 'RASCUNHO' THEN
     IF NEW.revisado_por IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe quem revisou o relatório.';
     END IF;
     IF NEW.revisado_por = NEW.solicitado_por THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quem pediu o relatório não pode aprová-lo (revisão por outra pessoa).';
     END IF;
     SET NEW.revisado_em = NOW();
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_relatorio_au $$
CREATE TRIGGER trg_relatorio_au
AFTER UPDATE ON relatorio_ia
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
    VALUES ('relatorio_ia', 'UPDATE', OLD.id_relatorio, CURRENT_USER(),
            JSON_OBJECT('status', OLD.status),
            JSON_OBJECT('status', NEW.status, 'revisado_por', NEW.revisado_por, 'comentario', NEW.comentario_revisao));
  END IF;
END $$


-- ---------------------------------------------------------------------
-- T10/T11: ANÁLISES DOS ANALISTAS
--   - análise em revisão ou publicada não pode ter o texto alterado
--     (para corrigir, o revisor devolve e o autor envia uma nova versão);
--   - toda mudança de situação vai para a auditoria.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_analise_pub_bu $$
CREATE TRIGGER trg_analise_pub_bu
BEFORE UPDATE ON analise_publicada
FOR EACH ROW
BEGIN
  IF OLD.status IN ('EM_REVISAO','PUBLICADA','ARQUIVADA')
     AND (NEW.titulo <> OLD.titulo OR NEW.resumo <> OLD.resumo OR NEW.conteudo <> OLD.conteudo
          OR NEW.periodo_inicio <> OLD.periodo_inicio OR NEW.periodo_fim <> OLD.periodo_fim) THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Análise em revisão ou publicada não pode ser editada.';
  END IF;
  IF NEW.id_autor <> OLD.id_autor THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O autor de uma análise não pode ser trocado.';
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_analise_pub_au $$
CREATE TRIGGER trg_analise_pub_au
AFTER UPDATE ON analise_publicada
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
    VALUES ('analise_publicada', 'UPDATE', OLD.id_analise_pub, CURRENT_USER(),
            JSON_OBJECT('status', OLD.status, 'versao', OLD.versao),
            JSON_OBJECT('status', NEW.status, 'versao', NEW.versao, 'revisado_por', NEW.revisado_por,
                        'nivel_confianca', NEW.nivel_confianca));
  END IF;
END $$

-- T12: comentários só em análises já publicadas
DROP TRIGGER IF EXISTS trg_comentario_bi $$
CREATE TRIGGER trg_comentario_bi
BEFORE INSERT ON analise_comentario
FOR EACH ROW
BEGIN
  IF (SELECT status FROM analise_publicada WHERE id_analise_pub = NEW.id_analise_pub) <> 'PUBLICADA' THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só é possível comentar análises publicadas.';
  END IF;
END $$

-- T13: METAS — meta aprovada não muda de valor nem de vigência de início; mudanças vão para a auditoria
DROP TRIGGER IF EXISTS trg_meta_bu $$
CREATE TRIGGER trg_meta_bu
BEFORE UPDATE ON meta
FOR EACH ROW
BEGIN
  IF OLD.status IN ('APROVADA','SUBSTITUIDA','REJEITADA')
     AND (NEW.valor <> OLD.valor OR NEW.vigencia_inicio <> OLD.vigencia_inicio OR NEW.id_indicador <> OLD.id_indicador
          OR NOT (NEW.id_municipio <=> OLD.id_municipio)) THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Meta já decidida não pode ser alterada. Proponha uma nova meta.';
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_meta_au $$
CREATE TRIGGER trg_meta_au
AFTER UPDATE ON meta
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
    VALUES ('meta', 'UPDATE', OLD.id_meta, CURRENT_USER(),
            JSON_OBJECT('status', OLD.status, 'valor', OLD.valor),
            JSON_OBJECT('status', NEW.status, 'valor', NEW.valor, 'vigencia_fim', NEW.vigencia_fim,
                        'parecer_por', NEW.parecer_por, 'aprovada_por', NEW.aprovada_por));
  END IF;
END $$

DELIMITER ;

-- >>>>>>>>>>>>>>>>>>>> 05_procedures_eventos.sql <<<<<<<<<<<<<<<<<<<<
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

-- >>>>>>>>>>>>>>>>>>>> 06_seguranca.sql <<<<<<<<<<<<<<<<<<<<
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

-- >>>>>>>>>>>>>>>>>>>> 07_dados_teste.sql <<<<<<<<<<<<<<<<<<<<
-- =====================================================================
--  EcoCity — Script 07: dados (gerado por gerar_dados_teste.py)
--  8 municípios do Estado de São Paulo, dados MENSAIS de jan/2023 a set/2026 (45 meses).
--  Cada número usa o ÚLTIMO dado oficial publicado da sua fonte (coleta em 16/11/2026).
--
--  Coluna dado.origem:
--   REAL     = oficial do mês: energia solar (ANEEL) e ônibus de São Paulo (SPTrans), até set/2026.
--   DERIVADO = total oficial do ano ÷ meses: água e resíduos 2023-2024 (SNIS/SINISA), água de Campinas
--              2025-jun/2026 (SANASA), energia por cidade 2024 (Anuário SEMIL-SP), emissões
--              2023-2025 (SEEG), resíduos de São Paulo até ago/2026 (SP Regula).
--   ESTIMADO = a fonte ainda não publicou ou não há dado da cidade: água e resíduos 2025-2026,
--              emissões 2026, energia por cidade 2025-2026 e ônibus das outras 7 cidades.
--  A coluna referencia_origem explica cada número. Para trocar por um oficial:
--     CALL sp_atualizar_dado_real('Campinas', 2024, 3, 'ENERGIA_CONSUMIDA', 512345, 'CPFL mar/2024');
--  AÇÕES, RESULTADOS e insights históricos são ilustrativos.
--  Senha dos usuários de demonstração: EcoCity@2026
-- =====================================================================
USE ecocity;
SET NAMES utf8mb4;

-- Perfis: quem precisa de login em 2 etapas e de quanto em quanto tempo troca a senha
INSERT INTO perfil (nome, descricao, exige_mfa, validade_senha_dias) VALUES
  ('CIDADAO','Consulta o painel público da sua cidade, em linguagem simples', FALSE, 365),
  ('ANALISTA','Explora os dados, publica análises revisadas por pares, dá parecer em metas e usa o Copiloto', TRUE, 90),
  ('GESTOR','Propõe e aprova metas, decide ações, aprova relatórios e análises', TRUE, 90),
  ('ADMIN','Administra usuários, credenciais, fontes, cargas, segurança e auditoria', TRUE, 60);

-- Municípios: dados REAIS do IBGE (código, área e população do Censo 2022)
INSERT INTO municipio (nome, codigo_ibge, regiao_metropolitana, area_km2, populacao, fonte_populacao, latitude, longitude) VALUES
  ('São Paulo','3550308','RM de São Paulo',1521.202,11451999,'IBGE - Censo 2022',-23.5505,-46.6333),
  ('Campinas','3509502','RM de Campinas',794.571,1139047,'IBGE - Censo 2022',-22.9056,-47.0608),
  ('Guarulhos','3518800','RM de São Paulo',318.675,1291771,'IBGE - Censo 2022',-23.4543,-46.5337),
  ('Santo André','3547809','RM de São Paulo',175.782,748919,'IBGE - Censo 2022',-23.6639,-46.5383),
  ('São José dos Campos','3549904','RM do Vale do Paraíba',1099.409,697054,'IBGE - Censo 2022',-23.1896,-45.8841),
  ('Sorocaba','3552205','RM de Sorocaba',449.872,723682,'IBGE - Censo 2022',-23.5015,-47.4526),
  ('Ribeirão Preto','3543402','RM de Ribeirão Preto',650.916,698642,'IBGE - Censo 2022',-21.1775,-47.8103),
  ('Santos','3548500','RM da Baixada Santista',281.033,418608,'IBGE - Censo 2022',-23.9608,-46.3336);

-- População por ano: REAL (IBGE, estimativas da população; 2023 via SNIS; 2025 e 2026 publicadas em 28/08/2026)
INSERT INTO populacao_anual (id_municipio, ano, populacao, fonte) VALUES
  (1,2023,11671681,'IBGE - estimativa da população 2023'),
  (1,2024,11895578,'IBGE - estimativa da população 2024'),
  (1,2025,11904961,'IBGE - estimativa publicada em 28/08/2026'),
  (1,2026,11911337,'IBGE - estimativa publicada em 28/08/2026'),
  (2,2023,1162275,'IBGE - estimativa da população 2023'),
  (2,2024,1185977,'IBGE - estimativa da população 2024'),
  (2,2025,1187974,'IBGE - estimativa publicada em 28/08/2026'),
  (2,2026,1189761,'IBGE - estimativa publicada em 28/08/2026'),
  (3,2023,1318295,'IBGE - estimativa da população 2023'),
  (3,2024,1345364,'IBGE - estimativa da população 2024'),
  (3,2025,1349100,'IBGE - estimativa publicada em 28/08/2026'),
  (3,2026,1351284,'IBGE - estimativa publicada em 28/08/2026'),
  (4,2023,763670,'IBGE - estimativa da população 2023'),
  (4,2024,778711,'IBGE - estimativa da população 2024'),
  (4,2025,782048,'IBGE - estimativa publicada em 28/08/2026'),
  (4,2026,784290,'IBGE - estimativa publicada em 28/08/2026'),
  (5,2023,710770,'IBGE - estimativa da população 2023'),
  (5,2024,724756,'IBGE - estimativa da população 2024'),
  (5,2025,727078,'IBGE - estimativa publicada em 28/08/2026'),
  (5,2026,729153,'IBGE - estimativa publicada em 28/08/2026'),
  (6,2023,740378,'IBGE - estimativa da população 2023'),
  (6,2024,757459,'IBGE - estimativa da população 2024'),
  (6,2025,762172,'IBGE - estimativa publicada em 28/08/2026'),
  (6,2026,766390,'IBGE - estimativa publicada em 28/08/2026'),
  (7,2023,713366,'IBGE - estimativa da população 2023'),
  (7,2024,728400,'IBGE - estimativa da população 2024'),
  (7,2025,731639,'IBGE - estimativa publicada em 28/08/2026'),
  (7,2026,734538,'IBGE - estimativa publicada em 28/08/2026'),
  (8,2023,424052,'IBGE - estimativa da população 2023'),
  (8,2024,429567,'IBGE - estimativa da população 2024'),
  (8,2025,429547,'IBGE - estimativa publicada em 28/08/2026'),
  (8,2026,429528,'IBGE - estimativa publicada em 28/08/2026');

-- Usuários de DEMONSTRAÇÃO. O ADMIN nasce com chave individual (exigida pelo trigger);
-- analistas e gestores nascem EM_ANALISE e só ficam ATIVOS depois do cadastro profissional aprovado (abaixo).
INSERT INTO usuario (nome, email, telefone, senha_hash, id_perfil, id_municipio, chave_admin_hash) VALUES
  ('Administrador EcoCity','admin@ecocity.local',NULL,'$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy',4,NULL,'$2b$10$uEDzKZvLw1YTl/oBIdmyJ.SNdOPdIbQ/mGxUA0J875Da45DNaLriO'),
  ('Marina Duarte','marina.duarte@ecocity.local','1132150001','$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy',3,NULL,NULL),
  ('Carlos Menezes','carlos.menezes@ecocity.local','1131240002','$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy',3,1,NULL),
  ('Rafael Nunes','rafael.nunes@ecocity.local','1124750003','$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy',2,3,NULL),
  ('Lúcia Andrade','lucia.andrade@ecocity.local','1932110004','$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy',2,7,NULL),
  ('Beatriz Rocha','beatriz.rocha@ecocity.local','1532380005','$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy',2,6,NULL),
  ('João Pereira','JOAO.PEREIRA@email.com ','11987654321','$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy',1,2,NULL),
  ('Ana Lima','ana.lima@email.com',NULL,'$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy',1,8,NULL);

-- Login em 2 etapas já configurado para analistas, gestores e admin (segredo de DEMONSTRAÇÃO, criptografado com AES)
UPDATE usuario SET mfa_ativo = TRUE, mfa_segredo = AES_ENCRYPT('JBSWY3DPEHPK3PXP', UNHEX(SHA2('chave-demo-ecocity', 256)))
WHERE id_perfil IN (2, 3, 4) AND email <> 'beatriz.rocha@ecocity.local';

INSERT INTO servico_publico (nome, descricao) VALUES
  ('Água','Abastecimento, consumo e perdas na rede de distribuição'),
  ('Energia','Consumo de energia elétrica e geração renovável distribuída'),
  ('Resíduos','Coleta, destinação e reciclagem de resíduos sólidos urbanos'),
  ('Mobilidade','Transporte público e emissões do setor de transportes');

-- Órgãos e instituições que publicam os dados (REAIS)
INSERT INTO orgao (nome, sigla, tipo, email_contato) VALUES
  ('Ministério das Cidades - SNIS/SINISA','MCID','SECRETARIA',NULL),
  ('Empresa de Pesquisa Energética','EPE','EMPRESA_PUBLICA',NULL),
  ('Agência Nacional de Energia Elétrica','ANEEL','AUTARQUIA',NULL),
  ('São Paulo Transporte S.A.','SPTRANS','EMPRESA_PUBLICA',NULL),
  ('Observatório do Clima - SEEG','SEEG','PARCEIRO',NULL),
  ('Instituto Brasileiro de Geografia e Estatística','IBGE','AUTARQUIA',NULL),
  ('Agência Reguladora de Serviços Públicos de São Paulo','SPREGULA','AUTARQUIA',NULL),
  ('Secretaria de Meio Ambiente, Infraestrutura e Logística de SP','SEMIL','SECRETARIA',NULL),
  ('Sociedade de Abastecimento de Água e Saneamento (Campinas)','SANASA','EMPRESA_PUBLICA',NULL);

INSERT INTO fonte_dados (nome, id_orgao, id_servico, tipo_integracao, frequencia, endpoint_url) VALUES
  ('SNIS/SINISA - Água (consumo)',1,1,'PAGINA_WEB','ANUAL','https://www.painelsaneamento.org.br'),
  ('SNIS/SINISA - Água (produção e perdas)',1,1,'PAGINA_WEB','ANUAL','https://www.painelsaneamento.org.br'),
  ('EPE - Consumo mensal de energia por UF',2,2,'PLANILHA','MENSAL','https://www.epe.gov.br/pt/publicacoes-dados-abertos/publicacoes/consumo-de-energia-eletrica'),
  ('ANEEL - Geração Distribuída',3,2,'ARQUIVO_PARQUET','MENSAL','https://dadosabertos.aneel.gov.br/dataset/relacao-de-empreendimentos-de-geracao-distribuida'),
  ('SINISA - Resíduos Sólidos',1,3,'ARQUIVO_CSV','ANUAL','https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa'),
  ('SP Regula - Quantitativos de coleta (São Paulo)',7,3,'PAGINA_WEB','SEMESTRAL','https://prefeitura.sp.gov.br/web/spregula/w/residuos_solidos/menu/185375'),
  ('SPTrans - Situação dos ônibus (passageiros)',4,4,'PDF','DIARIA','https://www.sptrans.com.br'),
  ('SEEG Municípios - Transportes',5,4,'API_REST','ANUAL','https://plataforma.seeg.eco.br'),
  ('SEMIL - Anuário de Energéticos por Município',8,2,'PDF','ANUAL','https://semil.sp.gov.br/anuario-de-energeticos-por-municipios-do-estado-de-sao-paulo/'),
  ('SANASA - Relatórios de água de Campinas',9,1,'PDF','MENSAL','https://www.sanasa.com.br');

-- Nota de confiabilidade dada pelo ADMINISTRADOR, com o critério aplicado
CALL sp_avaliar_fonte(1, 1, 4, 'Critério 4: órgão oficial, mas o dado é anual');
CALL sp_avaliar_fonte(2, 1, 4, 'Critério 4: órgão oficial, mas o dado é anual');
CALL sp_avaliar_fonte(3, 1, 4, 'Critério 4: órgão oficial e mensal, mas só do Estado (não por município)');
CALL sp_avaliar_fonte(4, 1, 5, 'Critério 5: órgão oficial, dado mensal, atualizado e por município');
CALL sp_avaliar_fonte(5, 1, 4, 'Critério 4: órgão oficial, mas o dado é anual');
CALL sp_avaliar_fonte(6, 1, 3, 'Critério 3: dado oficial publicado em imagens na página (extração manual)');
CALL sp_avaliar_fonte(7, 1, 3, 'Critério 3: dado oficial publicado em PDF (extração manual)');
CALL sp_avaliar_fonte(8, 1, 2, 'Critério 2: fonte não governamental reconhecida (Observatório do Clima)');
CALL sp_avaliar_fonte(9, 1, 4, 'Critério 4: órgão oficial e por município, mas o dado é anual');
CALL sp_avaliar_fonte(10, 1, 4, 'Critério 4: operadora pública oficial, só de Campinas, publicado em PDF');

INSERT INTO unidade_medida (sigla, descricao) VALUES
  ('m³','metro cúbico'),
  ('MWh','megawatt-hora'),
  ('t','tonelada'),
  ('passageiros','passageiros transportados'),
  ('t CO2e','toneladas de CO2 equivalente'),
  ('L/hab/dia','litros por habitante por dia'),
  ('%','percentual'),
  ('kWh/hab/mês','quilowatt-hora por habitante por mês'),
  ('kg/hab/dia','quilogramas por habitante por dia'),
  ('viagens/hab/mês','viagens em transporte público por habitante por mês'),
  ('kg CO2e/hab/mês','kg de CO2 equivalente por habitante por mês'),
  ('kW','quilowatt de potência instalada'),
  ('W/hab','watts de potência instalada por habitante');

INSERT INTO metrica (codigo, nome, id_servico, id_unidade) VALUES
  ('AGUA_PRODUZIDA','Volume de água produzido no mês',1,1),
  ('AGUA_CONSUMIDA','Volume de água consumido no mês',1,1),
  ('ENERGIA_CONSUMIDA','Energia elétrica consumida no mês (todas as classes)',2,2),
  ('GD_POTENCIA','Potência instalada de micro e minigeração distribuída (acumulada até o fim do mês)',2,12),
  ('RESIDUOS_COLETADOS','Resíduos sólidos domiciliares coletados no mês',3,3),
  ('RESIDUOS_RECICLADOS','Resíduos recuperados pela coleta seletiva no mês',3,3),
  ('TP_PASSAGEIROS','Passageiros transportados por ônibus no mês',4,4),
  ('CO2_TRANSPORTE','Emissões de CO2e do setor de transportes no mês',4,5);

-- Metas definidas pela equipe a partir de referências do setor (podem ser ajustadas)
INSERT INTO indicador (codigo, nome, descricao, formula, id_servico, id_unidade, meta, sentido, ods, peso_ies) VALUES
  ('AGU-01','Consumo de água per capita','Litros consumidos por habitante por dia','AGUA_CONSUMIDA*1000 / populacao / dias_do_mes',1,6,150,'MENOR_MELHOR','ODS 6.4',1.0),
  ('AGU-02','Perdas na distribuição de água','Percentual da água produzida que se perde antes de chegar às casas','(AGUA_PRODUZIDA - AGUA_CONSUMIDA) / AGUA_PRODUZIDA * 100',1,7,25,'MENOR_MELHOR','ODS 6.4',1.2),
  ('ENE-01','Consumo de energia per capita','kWh consumidos por habitante no mês (todas as classes)','ENERGIA_CONSUMIDA*1000 / populacao',2,8,220,'MENOR_MELHOR','ODS 7.3',1.0),
  ('ENE-02','Geração distribuída por habitante','Potência de micro e minigeração distribuída (em geral painéis solares) instalada por habitante','GD_POTENCIA*1000 / populacao',2,13,100,'MAIOR_MELHOR','ODS 7.2',1.2),
  ('RES-01','Geração de resíduos per capita','kg de resíduos domiciliares coletados por habitante por dia','RESIDUOS_COLETADOS*1000 / populacao / dias_do_mes',3,9,0.95,'MENOR_MELHOR','ODS 12.5',1.0),
  ('RES-02','Taxa de reciclagem','Percentual dos resíduos coletados recuperado pela coleta seletiva','RESIDUOS_RECICLADOS / RESIDUOS_COLETADOS * 100',3,7,10,'MAIOR_MELHOR','ODS 11.6',1.3),
  ('MOB-01','Uso do transporte público','Viagens de ônibus por habitante no mês','TP_PASSAGEIROS / populacao',4,10,15,'MAIOR_MELHOR','ODS 11.2',1.0),
  ('MOB-02','Emissões do transporte per capita','kg de CO2e emitidos pelo transporte por habitante no mês','CO2_TRANSPORTE*1000 / populacao',4,11,65,'MENOR_MELHOR','ODS 13.2',1.3);

-- Credenciais dos analistas (ILUSTRATIVAS): conferidas pelo administrador; só VERIFICADA e dentro da validade publica
INSERT INTO credencial_analista (id_usuario, orgao_vinculo, registro_profissional, id_servico, nivel, status, verificado_por, verificado_em, valida_ate, observacao) VALUES
  (4, 'Secretaria de Meio Ambiente de Guarulhos (ilustrativo)', 'CREA-SP 5069990001', NULL, 'SENIOR', 'VERIFICADA', 1, '2026-02-10 10:00:00', '2027-02-10', 'Engenheiro sanitarista; atua em todas as áreas'),
  (5, 'Universidade (grupo de pesquisa em energia, ilustrativo)', 'CREA-SP 5069990002', 2, 'PLENO', 'VERIFICADA', 1, '2026-03-05 14:30:00', '2027-03-05', 'Especialista em energia'),
  (6, 'Cooperativa de reciclagem de Sorocaba (ilustrativo)', 'CRQ-IV 4099990003', 3, 'JUNIOR', 'PENDENTE', NULL, NULL, NULL, 'Aguardando envio do diploma');

-- Cadastro profissional (ILUSTRATIVO) de gestores e analistas: conferido e aprovado pelo ADMIN
INSERT INTO cadastro_profissional (id_usuario, cpf_hash, cpf_final, email_institucional, telefone_institucional, orgao, cargo, matricula,
       formacao, registro_conselho, portaria_nomeacao, id_municipio_atuacao, documento_url, justificativa, aceite_termo_em, ip_aceite,
       status, analisado_por, analisado_em, motivo_decisao, valido_ate, criado_em) VALUES
  (2, SHA2('52998224725', 256), '25', 'marina.duarte@ecocity.local', (SELECT telefone FROM usuario WHERE id_usuario = 2), 'Consórcio Intermunicipal de Sustentabilidade (ilustrativo)', 'Coordenadora de Planejamento', 'CIS-0412', 'Gestão Ambiental (Unicamp, 2012)', NULL, 'Portaria CIS nº 18/2025 (Diário Oficial, ilustrativo)', 1, 'https://drive.ecocity.local/documentos/vinculo_2.pdf', 'Preciso acompanhar os indicadores mensais da minha área para planejar ações e responder à população.', '2026-01-20 09:00:00', '10.0.0.12', 'APROVADO', 1, '2026-01-27 15:00:00', 'Declaração de vínculo, matrícula e portaria conferidos.', '2027-01-27', '2026-01-20 09:00:00'),
  (3, SHA2('11144477735', 256), '35', 'carlos.menezes@ecocity.local', (SELECT telefone FROM usuario WHERE id_usuario = 3), 'Prefeitura de São Paulo - Secretaria do Verde (ilustrativo)', 'Diretor de Indicadores', 'SVMA-77310', 'Engenharia Civil (Poli-USP, 2005)', NULL, 'Portaria SVMA nº 102/2025 (Diário Oficial, ilustrativo)', 1, 'https://drive.ecocity.local/documentos/vinculo_3.pdf', 'Preciso acompanhar os indicadores mensais da minha área para planejar ações e responder à população.', '2026-01-21 09:00:00', '10.0.0.13', 'APROVADO', 1, '2026-01-28 15:00:00', 'Declaração de vínculo, matrícula e portaria conferidos.', '2027-01-28', '2026-01-21 09:00:00'),
  (4, SHA2('39053344705', 256), '05', 'rafael.nunes@ecocity.local', (SELECT telefone FROM usuario WHERE id_usuario = 4), 'Secretaria de Meio Ambiente de Guarulhos (ilustrativo)', 'Engenheiro Sanitarista', 'SMA-2290', 'Engenharia Sanitária (Unesp, 2010)', 'CREA-SP 5069990001', NULL, 3, 'https://drive.ecocity.local/documentos/vinculo_4.pdf', 'Preciso acompanhar os indicadores mensais da minha área para planejar ações e responder à população.', '2026-02-03 09:00:00', '10.0.0.14', 'APROVADO', 1, '2026-02-10 15:00:00', 'Declaração de vínculo, matrícula e registro no conselho conferidos.', '2027-02-10', '2026-02-03 09:00:00'),
  (5, SHA2('12345678909', 256), '09', 'lucia.andrade@ecocity.local', (SELECT telefone FROM usuario WHERE id_usuario = 5), 'Universidade - grupo de pesquisa em energia (ilustrativo)', 'Pesquisadora', 'UNI-55120', 'Engenharia Elétrica (Unicamp, 2014)', 'CREA-SP 5069990002', NULL, 7, 'https://drive.ecocity.local/documentos/vinculo_5.pdf', 'Preciso acompanhar os indicadores mensais da minha área para planejar ações e responder à população.', '2026-02-26 09:00:00', '10.0.0.15', 'APROVADO', 1, '2026-03-05 15:00:00', 'Declaração de vínculo, matrícula e registro no conselho conferidos.', '2027-03-05', '2026-02-26 09:00:00'),
  (6, SHA2('98765432100', 256), '00', 'beatriz.rocha@ecocity.local', (SELECT telefone FROM usuario WHERE id_usuario = 6), 'Cooperativa de reciclagem de Sorocaba (ilustrativo)', 'Técnica Ambiental', 'COOP-0081', 'Técnico em Meio Ambiente (Etec, 2021)', 'CRQ-IV 4099990003', NULL, 6, 'https://drive.ecocity.local/documentos/vinculo_6.pdf', 'Preciso acompanhar os indicadores mensais da minha área para planejar ações e responder à população.', '2026-09-01 09:00:00', '10.0.0.16', 'APROVADO', 1, '2026-09-08 15:00:00', 'Declaração de vínculo, matrícula e registro no conselho conferidos.', '2027-09-08', '2026-09-01 09:00:00');
UPDATE usuario SET status_cadastro = 'ATIVO' WHERE id_usuario IN (2, 3, 4, 5, 6);

-- Pedidos de acesso feitos pelo formulário (procedure): um gestor aguardando o ADMIN e um analista recusado
CALL sp_solicitar_acesso('GESTOR', 'Paulo Henrique Souza', '24681357928', 'paulo.souza@santos.sp.gov.br', '13 3201-5000', '$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy',
     'Prefeitura de Santos - Secretaria de Meio Ambiente', 'Chefe de Departamento de Resíduos', 'PMS-48120', 'Engenharia Ambiental (Unisantos, 2011)',
     NULL, 'Portaria nº 2.311/2026 - Diário Oficial de Santos de 02/10/2026', 8, 'https://drive.ecocity.local/documentos/paulo_portaria.pdf',
     'Fui nomeado para coordenar a coleta seletiva de Santos e preciso propor as metas de reciclagem para 2027.', TRUE, '189.40.12.7');
CALL sp_solicitar_acesso('ANALISTA', 'Diego Martins', '13579246828', 'diego.martins@consultoriaverde.com.br', '11 4002-8922', '$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy',
     'Consultoria Verde Ltda.', 'Consultor', 'CV-001', 'Administração (2019)', 'CRA-SP 0000000', NULL, 2,
     'https://drive.ecocity.local/documentos/diego_declaracao.pdf', 'Quero acessar os dados para oferecer consultoria às prefeituras da região de Campinas.', TRUE, '201.17.3.90');
CALL sp_analisar_cadastro((SELECT id_usuario FROM usuario WHERE email = 'diego.martins@consultoriaverde.com.br'), 1, 'RECUSADO',
     'Declaração sem assinatura do órgão e registro no conselho não confere com a área de atuação.', NULL);

-- Metas em vigor desde jan/2023 (proposta: gestora Marina; parecer: analista Rafael; aprovação: gestor Carlos)
INSERT INTO meta (id_indicador, id_municipio, valor, vigencia_inicio, justificativa, referencia, status, proposta_por, parecer_por, parecer_favoravel, parecer, aprovada_por, criada_em, decidida_em) VALUES
  (1,NULL,150,'2023-01-01','Consumo acima de 150 L por pessoa por dia indica desperdício em cidades de grande porte; valor usado como referência pela equipe a partir das médias do SNIS.','SNIS (IN022) e ODS 6.4','APROVADA',2,4,TRUE,'Valor coerente com a série histórica e com a referência técnica citada.',3,'2022-12-05 09:00:00','2022-12-15 16:00:00'),
  (2,NULL,25,'2023-01-01','Perdas acima de 25% mostram vazamentos e ligações irregulares em excesso; é o patamar usado nas metas federais de redução de perdas.','Portaria MDR nº 490/2021 e ODS 6.4','APROVADA',2,4,TRUE,'Valor coerente com a série histórica e com a referência técnica citada.',3,'2022-12-05 09:00:00','2022-12-15 16:00:00'),
  (3,NULL,220,'2023-01-01','Consumo total por habitante compatível com uso eficiente de energia em cidades paulistas, definido pela equipe a partir da série da EPE.','EPE e ODS 7.3','APROVADA',2,4,TRUE,'Valor coerente com a série histórica e com a referência técnica citada.',3,'2022-12-05 09:00:00','2022-12-15 16:00:00'),
  (4,NULL,100,'2023-01-01','100 W de geração própria por habitante equivale a uma parcela relevante da demanda residencial atendida por fonte renovável.','ANEEL e ODS 7.2','APROVADA',2,4,TRUE,'Valor coerente com a série histórica e com a referência técnica citada.',3,'2022-12-05 09:00:00','2022-12-15 16:00:00'),
  (5,NULL,0.95,'2023-01-01','Valor próximo da média nacional de resíduos coletados por habitante; acima disso indica desperdício ou falta de reaproveitamento.','SINISA e ODS 12.5','APROVADA',2,4,TRUE,'Valor coerente com a série histórica e com a referência técnica citada.',3,'2022-12-05 09:00:00','2022-12-15 16:00:00'),
  (6,NULL,10,'2023-01-01','Recuperar 10% do que é coletado é um patamar alcançável com coleta seletiva ampla e cooperativas.','Lei 12.305/2010 (PNRS) e ODS 11.6','APROVADA',2,4,TRUE,'Valor coerente com a série histórica e com a referência técnica citada.',3,'2022-12-05 09:00:00','2022-12-15 16:00:00'),
  (7,NULL,15,'2023-01-01','Média de uma viagem de ônibus a cada dois dias por habitante, típica de cidades com transporte público bem usado.','SPTrans e ODS 11.2','APROVADA',2,4,TRUE,'Valor coerente com a série histórica e com a referência técnica citada.',3,'2022-12-05 09:00:00','2022-12-15 16:00:00'),
  (8,NULL,65,'2023-01-01','Teto de emissões do transporte por habitante compatível com a redução gradual prevista nos compromissos climáticos.','SEEG e ODS 13.2','APROVADA',2,4,TRUE,'Valor coerente com a série histórica e com a referência técnica citada.',3,'2022-12-05 09:00:00','2022-12-15 16:00:00'),
  (6,8,12,'2024-07-01','Santos já recicla perto de 9% do que coleta; a meta local mais ambiciosa estimula a ampliação da coleta seletiva.','Plano Municipal de Gestão Integrada de Resíduos (ilustrativo)','APROVADA',3,4,TRUE,'Santos tem a maior taxa de recuperação entre as 8 cidades; 12% é desafiador, mas possível.',2,'2024-05-13 10:00:00','2024-06-03 11:00:00');

-- Lotes de carga (um por fonte)
INSERT INTO lote_carga (id_fonte, iniciado_em, finalizado_em, registros_lidos, registros_validos, registros_rejeitados, status, mensagem) VALUES
  (1,'2026-10-15 02:00:01','2026-10-15 02:01:01',0,0,0,'SUCESSO','Consumo de água: totais OFICIAIS 2023 e 2024 (SNIS) distribuídos pelos meses'),
  (2,'2026-10-15 02:00:02','2026-10-15 02:01:02',0,0,0,'SUCESSO','Produção de água: perdas OFICIAIS 2023 e 2024 (SNIS)'),
  (3,'2026-10-15 02:00:03','2026-10-15 02:01:03',0,0,0,'SUCESSO','Energia: série mensal OFICIAL da EPE (Estado de SP) x consumo per capita ESTIMADO por cidade'),
  (4,'2026-10-15 02:00:04','2026-10-15 02:01:04',0,0,0,'SUCESSO','Geração distribuída: OFICIAL mês a mês em 2024; 2023 calculado do acumulado oficial (ANEEL)'),
  (5,'2026-10-15 02:00:05','2026-10-15 02:01:05',0,0,0,'SUCESSO','Resíduos: per capita OFICIAL 2023 e 2024 (SINISA)'),
  (6,'2026-10-15 02:00:06','2026-10-15 02:01:06',0,0,0,'SUCESSO','Resíduos de São Paulo: totais OFICIAIS 2023 e 2024 (SP Regula)'),
  (7,'2026-10-15 02:00:07','2026-10-15 02:01:07',0,0,0,'SUCESSO','Passageiros: São Paulo OFICIAL (SPTrans); demais cidades ESTIMADAS'),
  (8,'2026-10-15 02:00:08','2026-10-15 02:01:08',0,0,0,'SUCESSO','Emissões: totais OFICIAIS 2023 a 2025 (SEEG) distribuídos pelos dias'),
  (9,'2026-10-15 02:00:09','2026-10-15 02:01:09',0,0,0,'SUCESSO','Energia por cidade: totais OFICIAIS do Anuário de Energéticos (SEMIL-SP) distribuídos pela variação da EPE'),
  (10,'2026-10-15 02:00:10','2026-10-15 02:01:10',0,0,0,'SUCESSO','Água de Campinas 2025 e jan-jun/2026: totais OFICIAIS da SANASA');

-- Medições mensais: 8 municípios x 8 métricas x 45 meses (jan/2023 a set/2026)
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,1,2,1,'2023-01-01',67230986.0889,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-01-01',90121965.2666,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-01-01',2148843.5306,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-01-01',83492.3200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2023 (83,492 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-01-01',299401.3539,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-01-01',6150.1129,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-01-01',152175430.0000,'REAL','SPTrans jan/2023: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2023-01-01',782635.0027,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-02-01',60151886.5189,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-02-01',80632555.6554,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-02-01',2197189.5723,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-02-01',90526.1700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2023 (90,526 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-02-01',270427.0294,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-02-01',5554.9407,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-02-01',150291844.0000,'REAL','SPTrans fev/2023: soma diária das viagens de passageiros (28 de 28 dias publicados)'),
  (8,1,8,8,'2023-02-01',706896.1315,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-03-01',65962476.9174,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-03-01',88421550.8276,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-03-01',2254644.0262,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-03-01',97122.6600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2023 (97,123 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-03-01',299401.3539,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-03-01',6150.1129,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-03-01',185951265.0000,'REAL','SPTrans mar/2023: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2023-03-01',782635.0027,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-04-01',61379476.0397,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-04-01',82278118.0157,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-04-01',2298127.7038,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-04-01',102435.9700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2023 (102,436 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-04-01',289743.2458,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-04-01',5951.7222,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-04-01',160177119.0000,'REAL','SPTrans abr/2023: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2023-04-01',757388.7123,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-05-01',60888440.2314,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-05-01',81619893.0716,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-05-01',2128346.3185,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-05-01',108176.8800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2023 (108,177 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-05-01',299401.3539,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-05-01',6150.1129,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-05-01',183944956.0000,'REAL','SPTrans mai/2023: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2023-05-01',782635.0027,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-06-01',57696707.4773,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-06-01',77341430.9348,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-06-01',2164456.6735,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-06-01',111804.6800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2023 (111,805 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-06-01',289743.2458,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-06-01',5951.7222,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-06-01',168144920.0000,'REAL','SPTrans jun/2023: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2023-06-01',757388.7123,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-07-01',59619931.0599,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-07-01',79919478.6326,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-07-01',2114810.4093,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-07-01',114788.6300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2023 (114,789 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-07-01',299401.3539,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-07-01',6150.1129,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-07-01',159072956.0000,'REAL','SPTrans jul/2023: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2023-07-01',782635.0027,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-08-01',60888440.2314,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-08-01',81619893.0716,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-08-01',2172356.0635,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-08-01',117978.2900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2023 (117,978 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-08-01',299401.3539,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-08-01',6150.1129,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-08-01',180468179.0000,'REAL','SPTrans ago/2023: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2023-08-01',782635.0027,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-09-01',60765681.2793,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-09-01',81455336.8356,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-09-01',2275248.4320,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-09-01',120210.1800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2023 (120,210 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-09-01',289743.2458,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-09-01',5951.7222,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-09-01',166010159.0000,'REAL','SPTrans set/2023: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2023-09-01',757388.7123,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-10-01',64693967.7459,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-10-01',86721136.3886,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-10-01',2332593.7884,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-10-01',122667.1600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2023 (122,667 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-10-01',299401.3539,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-10-01',6150.1129,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-10-01',171713379.0000,'REAL','SPTrans out/2023: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2023-10-01',782635.0027,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-11-01',63220860.3209,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-11-01',84746461.5562,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-11-01',2388326.6708,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-11-01',124756.0800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2023 (124,756 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-11-01',289743.2458,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-11-01',5951.7222,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-11-01',170523955.7143,'REAL','SPTrans nov/2023: soma diária das viagens de passageiros (28 de 30 dias publicados; dias faltantes completados pela média do mês)'),
  (8,1,8,8,'2023-11-01',757388.7123,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2023-12-01',67230986.0889,'DERIVADO','SNIS 2023: consumo anual oficial de 749.73 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2023-12-01',90121965.2666,'DERIVADO','SNIS 2023: índice de perdas oficial de 25.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2023-12-01',2435056.8112,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 26.91 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,1,4,4,'2023-12-01',127213.2000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2023 (127,213 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2023-12-01',299401.3539,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2023-12-01',6150.1129,'DERIVADO','SP Regula: total OFICIAL de 2023 (3.53 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2023-12-01',179310919.0000,'REAL','SPTrans dez/2023: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2023-12-01',782635.0027,'DERIVADO','SEEG Municípios 2023: 9,214,896 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,1,2,1,'2024-01-01',69170730.0977,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-01-01',91616861.0565,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-01-01',2335601.7838,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-01-01',129710.9600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2024 (129,711 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-01-01',305560.5196,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-01-01',7800.0345,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-01-01',153426790.0000,'REAL','SPTrans jan/2024: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2024-01-01',724853.6038,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-02-01',64097648.5537,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-02-01',84897547.7532,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-02-01',2342669.5254,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-02-01',132207.6500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2024 (132,208 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-02-01',285846.9377,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-02-01',7296.8065,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-02-01',159195385.0000,'REAL','SPTrans fev/2024: soma diária das viagens de passageiros (29 de 29 dias publicados)'),
  (8,1,8,8,'2024-02-01',678088.8552,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-03-01',67865621.9826,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-03-01',89888241.0366,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-03-01',2407059.1007,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-03-01',134765.2200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2024 (134,765 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-03-01',305560.5196,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-03-01',7800.0345,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-03-01',169568021.0000,'REAL','SPTrans mar/2024: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2024-03-01',724853.6038,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-04-01',63150392.6637,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-04-01',83642904.1904,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-04-01',2367600.1353,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-04-01',136828.0500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2024 (136,828 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-04-01',295703.7287,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-04-01',7548.4205,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-04-01',185358776.0000,'REAL','SPTrans abr/2024: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2024-04-01',701471.2295,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-05-01',62645189.5224,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-05-01',82973760.9569,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-05-01',2408545.1909,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-05-01',139361.0700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2024 (139,361 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-05-01',305560.5196,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-05-01',7800.0345,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-05-01',175752491.0000,'REAL','SPTrans mai/2024: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2024-05-01',724853.6038,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-06-01',59361369.1039,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-06-01',78624329.9390,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-06-01',2297033.0020,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-06-01',142274.5500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2024 (142,275 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-06-01',295703.7287,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-06-01',7548.4205,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-06-01',177192014.0000,'REAL','SPTrans jun/2024: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2024-06-01',701471.2295,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-07-01',61340081.4074,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-07-01',81245140.9369,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-07-01',2189915.5531,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-07-01',145324.8900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2024 (145,325 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-07-01',305560.5196,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-07-01',7800.0345,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-07-01',164339431.0000,'REAL','SPTrans jul/2024: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2024-07-01',724853.6038,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-08-01',62645189.5224,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-08-01',82973760.9569,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-08-01',2265070.0920,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-08-01',148928.1700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2024 (148,928 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-08-01',305560.5196,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-08-01',7800.0345,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-08-01',185458190.0000,'REAL','SPTrans ago/2024: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2024-08-01',724853.6038,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-09-01',62518888.7371,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-09-01',82806475.1485,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-09-01',2316440.5896,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-09-01',152562.8400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2024 (152,563 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-09-01',295703.7287,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-09-01',7548.4205,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-09-01',181092808.0000,'REAL','SPTrans set/2024: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2024-09-01',701471.2295,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-10-01',66560513.8676,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-10-01',88159621.0167,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-10-01',2408684.6944,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-10-01',155299.8100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2024 (155,300 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-10-01',305560.5196,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-10-01',7800.0345,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-10-01',191695666.0000,'REAL','SPTrans out/2024: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2024-10-01',724853.6038,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-11-01',65044904.4437,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-11-01',86152191.3161,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-11-01',2372926.7214,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-11-01',157983.8300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2024 (157,984 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-11-01',295703.7287,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-11-01',7548.4205,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-11-01',174480231.0000,'REAL','SPTrans nov/2024: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2024-11-01',701471.2295,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2024-12-01',69170730.0977,'DERIVADO','SNIS 2024: consumo anual oficial de 773.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,1,1,2,'2024-12-01',91616861.0565,'DERIVADO','SNIS 2024: índice de perdas oficial de 24.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,1,3,9,'2024-12-01',2364562.7275,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 28.076 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,1,4,4,'2024-12-01',160945.2600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2024 (160,945 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2024-12-01',305560.5196,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2024-12-01',7800.0345,'DERIVADO','SP Regula: total OFICIAL de 2024 (3.61 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2024-12-01',157343014.2069,'REAL','SPTrans dez/2024: soma diária das viagens de passageiros (29 de 31 dias publicados; dias faltantes completados pela média do mês)'),
  (8,1,8,8,'2024-12-01',724853.6038,'DERIVADO','SEEG Municípios 2024: 8,557,949 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,1,2,1,'2025-01-01',68991928.5716,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-01-01',91380037.8431,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-01-01',2368819.0738,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE jan/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-01-01',164625.0800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2025 (164,625 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-01-01',309383.5162,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-01-01',7931.6727,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-01-01',156372400.0000,'REAL','SPTrans jan/2025: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2025-01-01',720736.7507,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-02-01',62117636.7545,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-02-01',82275015.5689,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-02-01',2427842.2613,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE fev/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-02-01',167759.6700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2025 (167,760 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-02-01',279443.1759,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-02-01',7164.0915,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-02-01',164495879.0000,'REAL','SPTrans fev/2025: soma diária das viagens de passageiros (28 de 28 dias publicados)'),
  (8,1,8,8,'2025-02-01',650988.0329,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-03-01',67672232.7758,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-03-01',89632096.3918,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-03-01',2490556.9212,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE mar/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-03-01',171258.1600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2025 (171,258 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-03-01',309383.5162,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-03-01',7931.6727,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-03-01',174196733.0000,'REAL','SPTrans mar/2025: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2025-03-01',720736.7507,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-04-01',63475798.1309,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-04-01',84073904.8091,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-04-01',2396920.2752,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE abr/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-04-01',174664.6900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2025 (174,665 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-04-01',299403.4027,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-04-01',7675.8123,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-04-01',171695757.0000,'REAL','SPTrans abr/2025: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2025-04-01',697487.1781,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-05-01',63151403.3511,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-05-01',83644242.8492,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-05-01',2319558.9541,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE mai/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-05-01',178686.1900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2025 (178,686 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-05-01',309383.5162,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-05-01',7931.6727,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-05-01',179915148.4667,'REAL','SPTrans mai/2025: soma diária das viagens de passageiros (30 de 31 dias publicados; dias faltantes completados pela média do mês)'),
  (8,1,8,8,'2025-05-01',720736.7507,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-06-01',59790689.2096,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-06-01',79192965.8406,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-06-01',2237512.1884,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE jun/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-06-01',181728.9000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2025 (181,729 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-06-01',299403.4027,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-06-01',7675.8123,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-06-01',165582826.0000,'REAL','SPTrans jun/2025: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2025-06-01',697487.1781,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-07-01',61803889.9279,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-07-01',81859456.8582,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-07-01',2187092.7938,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE jul/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-07-01',184974.7300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2025 (184,975 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-07-01',309383.5162,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-07-01',7931.6727,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-07-01',168063809.0000,'REAL','SPTrans jul/2025: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2025-07-01',720736.7507,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-08-01',62604778.4602,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-08-01',82920236.3711,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-08-01',2264005.5755,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE ago/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-08-01',188055.1100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2025 (188,055 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-08-01',309383.5162,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-08-01',7931.6727,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-08-01',175385062.0000,'REAL','SPTrans ago/2025: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2025-08-01',720736.7507,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-09-01',62348866.2755,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-09-01',82581279.8351,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-09-01',2292636.7643,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE set/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-09-01',191088.9100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2025 (191,089 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-09-01',299403.4027,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-09-01',7675.8123,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-09-01',174817858.0000,'REAL','SPTrans set/2025: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2025-09-01',697487.1781,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-10-01',66741711.6118,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-10-01',88399618.0289,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-10-01',2366419.5669,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE out/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-10-01',195317.4200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2025 (195,317 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-10-01',309383.5162,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-10-01',7931.6727,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-10-01',184321572.1667,'REAL','SPTrans out/2025: soma diária das viagens de passageiros (30 de 31 dias publicados; dias faltantes completados pela média do mês)'),
  (8,1,8,8,'2025-10-01',720736.7507,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-11-01',65467955.0378,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-11-01',86712523.2289,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-11-01',2372982.4545,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE nov/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-11-01',199157.9800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2025 (199,158 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-11-01',299403.4027,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-11-01',7675.8123,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-11-01',166665148.0000,'REAL','SPTrans nov/2025: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2025-11-01',697487.1781,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,1,2,1,'2025-12-01',69093113.1059,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,1,1,2,'2025-12-01',91514057.0938,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,1,3,3,'2025-12-01',2371311.1391,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE dez/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,1,4,4,'2025-12-01',209999.8000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2025 (210,000 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2025-12-01',309383.5162,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (6,1,6,6,'2025-12-01',7931.6727,'DERIVADO','SP Regula: total OFICIAL de 2025 (3.64 milhões de t, coleta comum + seletiva) dividido pelos dias'),
  (7,1,7,7,'2025-12-01',153281475.0000,'REAL','SPTrans dez/2025: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2025-12-01',720736.7507,'DERIVADO','SEEG Municípios 2025: 8,486,094 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,1,2,1,'2026-01-01',69985420.7906,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,1,1,2,'2026-01-01',92695921.5769,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,1,3,3,'2026-01-01',2428888.2925,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE jan/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,1,4,4,'2026-01-01',214041.2000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2026 (214,041 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2026-01-01',320316.8343,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (6,1,6,6,'2026-01-01',8353.7293,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (7,1,7,7,'2026-01-01',148249815.0000,'REAL','SPTrans jan/2026: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2026-01-01',724643.4064,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,1,2,1,'2026-02-01',62635922.2742,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,1,1,2,'2026-02-01',82961486.4559,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,1,3,3,'2026-02-01',2370779.4693,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE fev/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,1,4,4,'2026-02-01',219384.7000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2026 (219,385 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2026-02-01',289318.4309,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (6,1,6,6,'2026-02-01',7545.3039,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (7,1,7,7,'2026-02-01',149842855.5556,'REAL','SPTrans fev/2026: soma diária das viagens de passageiros (27 de 28 dias publicados; dias faltantes completados pela média do mês)'),
  (8,1,8,8,'2026-02-01',646921.3516,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,1,2,1,'2026-03-01',67967695.8121,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,1,1,2,'2026-03-01',90023438.1618,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,1,3,3,'2026-03-01',2372026.0371,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE mar/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,1,4,4,'2026-03-01',223806.2000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2026 (223,806 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2026-03-01',320316.8343,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (6,1,6,6,'2026-03-01',8353.7293,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (7,1,7,7,'2026-03-01',178448892.0000,'REAL','SPTrans mar/2026: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2026-03-01',718724.2689,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,1,2,1,'2026-04-01',63364126.9735,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,1,1,2,'2026-04-01',83925995.9914,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,1,3,3,'2026-04-01',2504163.7322,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE abr/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,1,4,4,'2026-04-01',230187.8600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2026 (230,188 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2026-04-01',309984.0331,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (6,1,6,6,'2026-04-01',8084.2541,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (7,1,7,7,'2026-04-01',167628864.0000,'REAL','SPTrans abr/2026: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2026-04-01',700138.2791,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,1,2,1,'2026-05-01',62977957.4359,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,1,1,2,'2026-05-01',83414513.1601,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,1,3,3,'2026-05-01',2378243.8659,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE mai/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,1,4,4,'2026-05-01',243925.3400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2026 (243,925 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2026-05-01',320316.8343,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (6,1,6,6,'2026-05-01',8353.7293,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (7,1,7,7,'2026-05-01',170272143.0000,'REAL','SPTrans mai/2026: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2026-05-01',723555.6813,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,1,2,1,'2026-06-01',59472726.7118,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,1,1,2,'2026-06-01',78771823.4594,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,1,3,3,'2026-06-01',2257500.2919,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE jun/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,1,4,4,'2026-06-01',253118.4900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2026 (253,118 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2026-06-01',309984.0331,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (6,1,6,6,'2026-06-01',8084.2541,'DERIVADO','SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias'),
  (7,1,7,7,'2026-06-01',162608085.0000,'REAL','SPTrans jun/2026: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2026-06-01',696730.4609,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,1,2,1,'2026-07-01',61674090.2959,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,1,1,2,'2026-07-01',81687536.8158,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,1,3,3,'2026-07-01',2253360.8902,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE jul/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,1,4,4,'2026-07-01',257540.5400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2026 (257,541 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2026-07-01',314139.0100,'DERIVADO','SP Regula: total OFICIAL jan-ago/2026 menos o 1º semestre (= jul+ago) dividido pelos dias'),
  (6,1,6,6,'2026-07-01',8232.9950,'DERIVADO','SP Regula: total OFICIAL jan-ago/2026 menos o 1º semestre (= jul+ago) dividido pelos dias'),
  (7,1,7,7,'2026-07-01',160301840.0000,'REAL','SPTrans jul/2026: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2026-07-01',716697.3494,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,1,2,1,'2026-08-01',62906437.9685,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,1,1,2,'2026-08-01',83319785.3887,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,1,3,3,'2026-08-01',2326974.8344,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE ago/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,1,4,4,'2026-08-01',262028.7500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2026 (262,029 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2026-08-01',314139.0100,'DERIVADO','SP Regula: total OFICIAL jan-ago/2026 menos o 1º semestre (= jul+ago) dividido pelos dias'),
  (6,1,6,6,'2026-08-01',8232.9950,'DERIVADO','SP Regula: total OFICIAL jan-ago/2026 menos o 1º semestre (= jul+ago) dividido pelos dias'),
  (7,1,7,7,'2026-08-01',171962562.0000,'REAL','SPTrans ago/2026: soma diária das viagens de passageiros (31 de 31 dias publicados)'),
  (8,1,8,8,'2026-08-01',722278.4623,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,1,2,1,'2026-09-01',62764215.4270,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (178 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,1,1,2,'2026-09-01',83131411.1616,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 24.5%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,1,3,3,'2026-09-01',2355722.9744,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 28.076 TWh) x variação oficial do Estado (EPE ainda não publicou set/2026; usado set/2025 x crescimento recente). O Anuário de 2026 ainda não foi publicado'),
  (4,1,4,4,'2026-09-01',271605.8700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2026 (271,606 kW). Base de 16/11/2026.'),
  (6,1,5,6,'2026-09-01',302538.0191,'ESTIMADO','ESTIMADO: média diária oficial de jul-ago/2026 (SP Regula, último dado publicado). Setembro ainda não publicado'),
  (6,1,6,6,'2026-09-01',7954.6613,'ESTIMADO','ESTIMADO: média diária oficial de jul-ago/2026 (SP Regula, último dado publicado). Setembro ainda não publicado'),
  (7,1,7,7,'2026-09-01',161693501.0000,'REAL','SPTrans set/2026: soma diária das viagens de passageiros (30 de 30 dias publicados)'),
  (8,1,8,8,'2026-09-01',702619.9565,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,2,2,1,'2023-01-01',7287785.5671,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-01-01',9075698.0910,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-01-01',256328.0466,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-01-01',62999.5900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2023 (63,000 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-01-01',39993.8827,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-01-01',1827.7204,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-01-01',9406844.3011,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-01-01',165690.7534,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2023-02-01',6520416.7886,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-02-01',8120070.7205,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-02-01',262095.0772,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-02-01',65550.4600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2023 (65,550 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-02-01',36123.5070,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-02-01',1650.8443,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-02-01',9297620.7975,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-02-01',149656.1644,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2023-03-01',7150280.1790,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-03-01',8904458.5044,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-03-01',268948.6185,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-03-01',68446.1600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2023 (68,446 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-03-01',39993.8827,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-03-01',1827.7204,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-03-01',11390351.4615,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-03-01',165690.7534,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,2,2,1,'2023-04-01',6653486.5189,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-04-01',8285786.4495,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-04-01',274135.6347,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-04-01',70689.6900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2023 (70,690 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-04-01',38703.7575,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-04-01',1768.7617,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-04-01',9851022.8213,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-04-01',160345.8904,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2023-05-01',6600258.6268,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-05-01',8219500.1579,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-05-01',253883.0057,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-05-01',72986.3000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2023 (72,986 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-05-01',39993.8827,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-05-01',1827.7204,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-05-01',11291031.0834,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-05-01',165690.7534,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2023-06-01',6254277.3278,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-06-01',7788639.2625,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-06-01',258190.4839,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-06-01',74276.9000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2023 (74,277 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-06-01',38703.7575,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-06-01',1768.7617,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-06-01',10304522.3556,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-06-01',160345.8904,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2023-07-01',6462753.2387,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-07-01',8048260.5713,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-07-01',252268.3543,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-07-01',75447.3900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2023 (75,447 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-07-01',39993.8827,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-07-01',1827.7204,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-07-01',9877581.2269,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-07-01',165690.7534,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2023-08-01',6600258.6268,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-08-01',8219500.1579,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-08-01',259132.7746,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-08-01',76689.7900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2023 (76,690 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-08-01',39993.8827,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-08-01',1827.7204,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-08-01',11246770.4606,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-08-01',165690.7534,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2023-09-01',6586951.6537,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-09-01',8202928.5850,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-09-01',271406.4462,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-09-01',77911.0000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2023 (77,911 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-09-01',38703.7575,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-09-01',1768.7617,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-09-01',10184720.2669,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-09-01',160345.8904,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2023-10-01',7012774.7910,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-10-01',8733218.9178,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-10-01',278246.9736,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-10-01',79385.8600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2023 (79,386 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-10-01',39993.8827,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-10-01',1827.7204,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-10-01',10644993.8565,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-10-01',165690.7534,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2023-11-01',6853091.1145,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-11-01',8534360.0430,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-11-01',284895.1547,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-11-01',80825.9000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2023 (80,826 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-11-01',38703.7575,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-11-01',1768.7617,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-11-01',10539143.1543,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-11-01',160345.8904,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2023-12-01',7287785.5671,'DERIVADO','SNIS 2023: consumo anual oficial de 81.27 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2023-12-01',9075698.0910,'DERIVADO','SNIS 2023: índice de perdas oficial de 19.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2023-12-01',290469.4301,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.21 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,2,4,4,'2023-12-01',82293.3800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2023 (82,293 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2023-12-01',39993.8827,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.11 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2023-12-01',1827.7204,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.57% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2023-12-01',11084894.2566,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2023). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2023-12-01',165690.7534,'DERIVADO','SEEG Municípios 2023: 1,950,875 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-01-01',7498231.9171,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-01-01',9088765.9601,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-01-01',283082.3283,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-01-01',83608.7300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2024 (83,609 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-01-01',43015.3858,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-01-01',2563.7170,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-01-01',9629148.0727,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-01-01',148674.2213,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-02-01',6948300.7266,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-02-01',8422182.6988,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-02-01',283938.9610,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-02-01',85341.8800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2024 (85,342 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-02-01',40240.1996,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-02-01',2398.3159,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-02-01',10123186.8326,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-02-01',139082.3361,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-03-01',7356755.8432,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-03-01',8917279.8099,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-03-01',291743.1813,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-03-01',87509.6000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2024 (87,510 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-03-01',43015.3858,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-03-01',2563.7170,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-03-01',10727299.0068,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-03-01',148674.2213,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,2,2,1,'2024-04-01',6845616.4794,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-04-01',8297716.9447,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-04-01',286960.6298,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-04-01',89924.8600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2024 (89,925 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-04-01',41627.7927,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-04-01',2481.0164,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-04-01',11686522.7360,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-04-01',143878.2787,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-05-01',6790851.5475,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-05-01',8231335.2091,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-05-01',291923.3001,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-05-01',92305.1500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2024 (92,305 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-05-01',43015.3858,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-05-01',2563.7170,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-05-01',11083661.4489,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-05-01',148674.2213,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-06-01',6434879.4906,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-06-01',7799853.9280,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-06-01',278407.6699,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-06-01',95016.1700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2024 (95,016 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-06-01',41627.7927,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-06-01',2481.0164,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-06-01',11277324.5196,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-06-01',143878.2787,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-07-01',6649375.4736,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-07-01',8059849.0589,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-07-01',265424.6961,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-07-01',97674.8500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2024 (97,675 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-07-01',43015.3858,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-07-01',2563.7170,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-07-01',10471306.2242,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-07-01',148674.2213,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-08-01',6790851.5475,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-08-01',8231335.2091,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-08-01',274533.6640,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-08-01',99886.9600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2024 (99,887 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-08-01',43015.3858,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-08-01',2563.7170,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-08-01',11713583.3651,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-08-01',148674.2213,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-09-01',6777160.3146,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-09-01',8214739.7752,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-09-01',280759.9309,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-09-01',101891.3800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2024 (101,891 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-09-01',41627.7927,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-09-01',2481.0164,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-09-01',11441101.9153,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-09-01',143878.2787,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-10-01',7215279.7692,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-10-01',8745793.6597,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-10-01',291940.2084,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-10-01',104277.4200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2024 (104,277 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-10-01',43015.3858,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-10-01',2563.7170,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-10-01',12137572.5961,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-10-01',148674.2213,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-11-01',7050984.9737,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-11-01',8546648.4530,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-11-01',287606.2289,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-11-01',106124.3100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2024 (106,124 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-11-01',41627.7927,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-11-01',2481.0164,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-11-01',10967803.3838,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-11-01',143878.2787,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,2,2,1,'2024-12-01',7498231.9171,'DERIVADO','SNIS 2024: consumo anual oficial de 83.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,2,1,2,'2024-12-01',9088765.9601,'DERIVADO','SNIS 2024: índice de perdas oficial de 17.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,2,3,9,'2024-12-01',286592.4864,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.403 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,2,4,4,'2024-12-01',108004.4100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2024 (108,004 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2024-12-01',43015.3858,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.17 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,2,6,5,'2024-12-01',2563.7170,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 5.96% recuperado (oficial) x coleta do mês'),
  (7,2,7,7,'2024-12-01',9988293.9886,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2024). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2024-12-01',148674.2213,'DERIVADO','SEEG Municípios 2024: 1,755,315 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-01-01',9156577.3664,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-01-01',7638416.8390,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-01-01',287106.9538,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE jan/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-01-01',109480.1700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2025 (109,480 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-01-01',43060.5332,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-01-01',2566.4078,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-01-01',9960126.8423,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-01-01',147329.8356,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-02-01',8192433.7971,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-02-01',6834128.2735,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-02-01',293260.0087,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE fev/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-02-01',111167.4000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2025 (111,167 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-02-01',38677.9517,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-02-01',2305.2059,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-02-01',10349574.4986,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-02-01',133072.1096,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-03-01',8983811.7557,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-03-01',7494295.7666,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-03-01',301403.1068,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE mar/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-03-01',113372.2600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2025 (113,372 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-03-01',43289.0061,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-03-01',2580.0248,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-03-01',11032205.3772,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-03-01',147329.8356,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (10,2,1,10,'2025-04-01',8359626.3235,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-04-01',6973600.2791,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-04-01',290285.8931,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE abr/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-04-01',115621.2900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2025 (115,621 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-04-01',41726.5198,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-04-01',2486.9006,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-04-01',10850425.0789,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-04-01',142577.2603,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-05-01',8292749.3130,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-05-01',6917811.4769,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-05-01',281978.0512,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE mai/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-05-01',117960.4000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2025 (117,960 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-05-01',42777.7276,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-05-01',2549.5526,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-05-01',11368956.8300,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-05-01',147329.8356,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-06-01',7858048.7441,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-06-01',6555184.2624,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-06-01',270637.5062,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE jun/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-06-01',119840.0200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2025 (119,840 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-06-01',42105.9098,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-06-01',2509.5122,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-06-01',10530772.6198,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-06-01',142577.2603,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-07-01',8119983.7023,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-07-01',6773690.4044,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-07-01',265021.7842,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE jul/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-07-01',121870.0900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2025 (121,870 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-07-01',43614.2634,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-07-01',2599.4101,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-07-01',10693539.6142,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-07-01',147329.8356,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-08-01',8292749.3130,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-08-01',6917811.4769,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-08-01',273752.0509,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE ago/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-08-01',123605.4500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2025 (123,605 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-08-01',43626.6022,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-08-01',2600.1455,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-08-01',10996849.5674,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-08-01',147329.8356,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-09-01',8276030.0603,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-09-01',6903864.2763,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-09-01',277592.2752,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE set/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-09-01',125488.7600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2025 (125,489 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-09-01',42054.5095,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-09-01',2506.4488,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-09-01',11053398.2390,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-09-01',142577.2603,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-10-01',8811046.1450,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-10-01',7350174.6942,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-10-01',285989.3656,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE out/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-10-01',127406.3100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2025 (127,406 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-10-01',43689.2387,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-10-01',2603.8786,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-10-01',11759644.7959,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-10-01',147329.8356,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-11-01',8610415.1133,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-11-01',7182808.2875,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-11-01',287987.6106,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE nov/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-11-01',128786.6900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2025 (128,787 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-11-01',41671.8007,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-11-01',2483.6393,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-11-01',10442920.4882,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-11-01',142577.2603,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2025-12-01',9156577.3664,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2025-12-01',7638416.8390,'DERIVADO','SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2025-12-01',287444.8649,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE dez/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,2,4,4,'2025-12-01',130229.5400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2025 (130,230 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2025-12-01',43085.7756,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2025'),
  (5,2,6,5,'2025-12-01',2567.9122,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2025-12-01',9610597.0425,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2025). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2025-12-01',147329.8356,'DERIVADO','SEEG Municípios 2025: 1,734,690 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (10,2,1,10,'2026-01-01',8936144.0904,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2026-01-01',7595722.4769,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2026-01-01',293962.3345,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE jan/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,2,4,4,'2026-01-01',131632.7300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2026 (131,633 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2026-01-01',43037.8163,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2026'),
  (5,2,6,5,'2026-01-01',2565.0539,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2026-01-01',9375305.4974,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2026). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2026-01-01',146404.1720,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (10,2,1,10,'2026-02-01',7995211.0852,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2026-02-01',6795929.4224,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2026-02-01',286165.9768,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE fev/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,2,4,4,'2026-02-01',133195.8900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2026 (133,196 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2026-02-01',39070.8625,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2026'),
  (5,2,6,5,'2026-02-01',2328.6234,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2026-02-01',9567639.5527,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2026). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2026-02-01',132383.2293,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (10,2,1,10,'2026-03-01',8767537.5982,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2026-03-01',7452406.9584,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2026-03-01',288040.3440,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE mar/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,2,4,4,'2026-03-01',134879.3400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2026 (134,879 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2026-03-01',42826.1874,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2026'),
  (5,2,6,5,'2026-03-01',2552.4408,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2026-03-01',11323880.2354,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2026). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2026-03-01',148146.0405,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (10,2,1,10,'2026-04-01',8158378.6583,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2026-04-01',6934621.8596,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2026-04-01',303705.9735,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE abr/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,2,4,4,'2026-04-01',136645.0400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2026 (136,645 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2026-04-01',41971.6823,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2026'),
  (5,2,6,5,'2026-04-01',2501.5123,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2026-04-01',10640312.8428,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2026). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2026-04-01',142002.9743,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (10,2,1,10,'2026-05-01',8093111.6291,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2026-05-01',6879144.8847,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2026-05-01',288918.9762,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE mai/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,2,4,4,'2026-05-01',138409.6500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2026 (138,410 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2026-05-01',43260.1662,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2026'),
  (5,2,6,5,'2026-05-01',2578.3059,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2026-05-01',10837009.2822,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2026). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2026-05-01',148613.6736,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (10,2,1,10,'2026-06-01',7668875.9388,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); total dividido pelos meses (perfil sazonal)'),
  (10,2,2,10,'2026-06-01',6518544.5480,'DERIVADO','SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais); consumo = água distribuída x (1 - perdas)'),
  (3,2,3,3,'2026-06-01',273769.0001,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE jun/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,2,4,4,'2026-06-01',140333.8600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2026 (140,334 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2026-06-01',42036.8233,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2026'),
  (5,2,6,5,'2026-06-01',2505.3947,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2026-06-01',10218567.4074,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2026). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2026-06-01',142158.7127,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,2,2,1,'2026-07-01',6742937.1091,'ESTIMADO','ESTIMADO: média diária oficial de jan-jun/2026 (SANASA em Números, ago/2026) x perfil sazonal. A SANASA ainda não publicou jul/2026'),
  (2,2,1,2,'2026-07-01',7932867.1872,'ESTIMADO','ESTIMADO: média diária oficial de jan-jun/2026 e perdas acumuladas de 15.00% (SANASA). A SANASA ainda não publicou jul/2026'),
  (3,2,3,3,'2026-07-01',274119.1573,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE jul/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,2,4,4,'2026-07-01',141737.6900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2026 (141,738 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2026-07-01',43639.3851,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2026'),
  (5,2,6,5,'2026-07-01',2600.9074,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2026-07-01',10148703.3174,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2026). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2026-07-01',146570.3755,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,2,2,1,'2026-08-01',6893059.0455,'ESTIMADO','ESTIMADO: média diária oficial de jan-jun/2026 (SANASA em Números, ago/2026) x perfil sazonal. A SANASA ainda não publicou ago/2026'),
  (2,2,1,2,'2026-08-01',8109481.2299,'ESTIMADO','ESTIMADO: média diária oficial de jan-jun/2026 e perdas acumuladas de 15.00% (SANASA). A SANASA ainda não publicou ago/2026'),
  (3,2,3,3,'2026-08-01',282453.0908,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE ago/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,2,4,4,'2026-08-01',142943.4700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2026 (142,943 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2026-08-01',43519.5643,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2026'),
  (5,2,6,5,'2026-08-01',2593.7660,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2026-08-01',10976271.8559,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2026). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2026-08-01',147093.4658,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,2,2,1,'2026-09-01',6858029.1351,'ESTIMADO','ESTIMADO: média diária oficial de jan-jun/2026 (SANASA em Números, ago/2026) x perfil sazonal. A SANASA ainda não publicou set/2026'),
  (2,2,1,2,'2026-09-01',8068269.5707,'ESTIMADO','ESTIMADO: média diária oficial de jan-jun/2026 e perdas acumuladas de 15.00% (SANASA). A SANASA ainda não publicou set/2026'),
  (3,2,3,3,'2026-09-01',285273.4804,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.403 TWh) x variação oficial do Estado (EPE ainda não publicou set/2026; usado set/2025 x crescimento recente). O Anuário de 2026 ainda não foi publicado'),
  (4,2,4,4,'2026-09-01',143834.2400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2026 (143,834 kW). Base de 16/11/2026.'),
  (5,2,5,5,'2026-09-01',41785.7062,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.17 kg/hab/dia) x população IBGE 2026'),
  (5,2,6,5,'2026-09-01',2490.4281,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 5.96%)'),
  (7,2,7,7,'2026-09-01',10173751.5599,'ESTIMADO','ESTIMADO: 9.2 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2026). Não há dado oficial mensal desta cidade'),
  (8,2,8,8,'2026-09-01',141681.6837,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,3,2,1,'2023-01-01',6553515.5774,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-01-01',9191466.4480,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-01-01',293060.4146,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-01-01',23773.9700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2023 (23,774 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-01-01',31876.3731,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-01-01',366.5783,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-01-01',8978434.2812,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-01-01',347162.8000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2023-02-01',5863461.8983,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-02-01',8223649.2262,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-02-01',299653.8733,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-02-01',24833.4500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2023 (24,833 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-02-01',28791.5628,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-02-01',331.1030,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-02-01',9007022.4833,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-02-01',313566.4000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2023-03-01',6429864.3401,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-03-01',9018042.5528,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-03-01',307489.5420,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-03-01',27108.0700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2023 (27,108 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-03-01',31876.3731,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-03-01',366.5783,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-03-01',10959116.3963,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-03-01',347162.8000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2023-04-01',5983124.3860,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-04-01',8391478.8022,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-04-01',313419.8689,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-04-01',28051.2700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2023 (28,051 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-04-01',30848.1030,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-04-01',354.7532,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-04-01',9496429.4951,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-04-01',335964.0000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2023-05-01',5935259.3909,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-05-01',8324346.9718,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-05-01',290264.9940,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-05-01',29211.0300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2023 (29,211 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-05-01',31876.3731,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-05-01',366.5783,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-05-01',10906951.4348,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-05-01',347162.8000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2023-06-01',5624136.9228,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-06-01',7887990.0741,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-06-01',295189.7433,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-06-01',30191.6200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2023 (30,192 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-06-01',30848.1030,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-06-01',354.7532,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-06-01',10053315.1491,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-06-01',335964.0000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,3,2,1,'2023-07-01',5811608.1536,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-07-01',8150923.0766,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-07-01',288418.9596,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-07-01',31245.0800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2023 (31,245 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-07-01',31876.3731,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-07-01',366.5783,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-07-01',9370191.2330,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-07-01',347162.8000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2023-08-01',5935259.3909,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-08-01',8324346.9718,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-08-01',296267.0663,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-08-01',32430.8100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2023 (32,431 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-08-01',31876.3731,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-08-01',366.5783,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-08-01',10734493.2612,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-08-01',347162.8000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2023-09-01',5923293.1421,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-09-01',8307564.0142,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-09-01',310299.5818,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-09-01',33140.9200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2023 (33,141 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-09-01',30848.1030,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-09-01',354.7532,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-09-01',9838450.8170,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-09-01',335964.0000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2023-10-01',6306213.1028,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-10-01',8844618.6575,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-10-01',318120.3717,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-10-01',33537.2200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2023 (33,537 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-10-01',31876.3731,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-10-01',366.5783,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-10-01',10171527.6775,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-10-01',347162.8000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2023-11-01',6162618.1176,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-11-01',8643223.1663,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-11-01',325721.2516,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-11-01',39201.4200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2023 (39,201 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-11-01',30848.1030,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-11-01',354.7532,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-11-01',10105608.8385,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-11-01',335964.0000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2023-12-01',6553515.5774,'DERIVADO','SNIS 2023: consumo anual oficial de 73.08 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2023-12-01',9191466.4480,'DERIVADO','SNIS 2023: índice de perdas oficial de 28.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2023-12-01',332094.3329,'DERIVADO','Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de 3.67 TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE'),
  (4,3,4,4,'2023-12-01',40180.4400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2023 (40,180 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2023-12-01',31876.3731,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.78 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2023-12-01',366.5783,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.15% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2023-12-01',10582693.0785,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2023). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2023-12-01',347162.8000,'DERIVADO','SEEG Municípios 2023: 4,087,562 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-01-01',6227980.8637,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-01-01',8637976.2326,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-01-01',320641.6447,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-01-01',40685.2700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2024 (40,685 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-01-01',30028.5245,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-01-01',447.4250,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-01-01',9395064.6313,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-01-01',313507.0656,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-02-01',5771211.7255,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-02-01',8004454.5430,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-02-01',321611.9352,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-02-01',41310.2100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2024 (41,310 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-02-01',28091.2003,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-02-01',418.5589,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-02-01',9675423.5838,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-02-01',293280.8033,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-03-01',6110471.7908,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-03-01',8474995.5490,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-03-01',330451.6182,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-03-01',45694.0300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2024 (45,694 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-03-01',30028.5245,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-03-01',447.4250,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-03-01',10353864.1269,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-03-01',313507.0656,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-04-01',5685922.8823,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-04-01',7886162.1113,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-04-01',325034.5185,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-04-01',46452.3400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2024 (46,452 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-04-01',29059.8624,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-04-01',432.9919,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-04-01',11171572.8608,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-04-01',303393.9344,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-05-01',5640435.4992,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-05-01',7823072.8144,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-05-01',330655.6351,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-05-01',47673.1200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2024 (47,673 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-05-01',30028.5245,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-05-01',447.4250,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-05-01',10670621.3524,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-05-01',313507.0656,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-06-01',5344767.5093,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-06-01',7412992.3846,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-06-01',315346.7533,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-06-01',48350.6200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2024 (48,351 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-06-01',29059.8624,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-06-01',432.9919,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-06-01',10739522.5612,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-06-01',303393.9344,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,3,2,1,'2024-07-01',5522926.4263,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-07-01',7660092.1308,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-07-01',300641.2007,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-07-01',49067.3000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2024 (49,067 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-07-01',30028.5245,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-07-01',447.4250,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-07-01',9941146.9305,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-07-01',313507.0656,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-08-01',5640435.4992,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-08-01',7823072.8144,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-08-01',310958.7450,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-08-01',49679.7300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2024 (49,680 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-08-01',30028.5245,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-08-01',447.4250,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-08-01',11277587.2444,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-08-01',313507.0656,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-09-01',5629063.6534,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-09-01',7807300.4902,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-09-01',318011.1120,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-09-01',50283.2700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2024 (50,283 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-09-01',29059.8624,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-09-01',432.9919,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-09-01',11029777.4415,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-09-01',303393.9344,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-10-01',5992962.7179,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-10-01',8312014.8653,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-10-01',330674.7868,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-10-01',51573.3200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2024 (51,573 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-10-01',30028.5245,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-10-01',447.4250,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-10-01',11533863.1215,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-10-01',313507.0656,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-11-01',5856500.5687,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-11-01',8122746.9747,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-11-01',325765.7756,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-11-01',52337.2700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2024 (52,337 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-11-01',29059.8624,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-11-01',432.9919,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-11-01',10567866.6201,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-11-01',303393.9344,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2024-12-01',6227980.8637,'DERIVADO','SNIS 2024: consumo anual oficial de 69.65 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,3,1,2,'2024-12-01',8637976.2326,'DERIVADO','SNIS 2024: índice de perdas oficial de 27.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,3,3,9,'2024-12-01',324617.5299,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 3.854 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,3,4,4,'2024-12-01',52872.2900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2024 (52,872 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2024-12-01',30028.5245,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.72 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,3,6,5,'2024-12-01',447.4250,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,3,7,7,'2024-12-01',9491008.5278,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2024). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2024-12-01',313507.0656,'DERIVADO','SEEG Municípios 2024: 3,701,406 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-01-01',6304615.0269,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-01-01',8744264.9472,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-01-01',324012.2194,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE jan/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-01-01',53561.0800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2025 (53,561 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-01-01',30152.3521,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-01-01',449.2700,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-01-01',9581130.2029,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-01-01',302358.2027,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-02-01',5598667.6757,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-02-01',7765142.4074,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-02-01',333024.8760,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE fev/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-02-01',54419.6800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2025 (54,420 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-02-01',26943.7159,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-02-01',401.4614,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-02-01',10053230.6833,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-02-01',273097.7315,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-03-01',6181370.0233,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-03-01',8573328.7425,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-03-01',341656.4776,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE mar/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-03-01',55087.9300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2025 (55,088 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-03-01',30138.9554,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-03-01',449.0704,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-03-01',10661890.5134,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-03-01',302358.2027,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-04-01',5718875.1360,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-04-01',7931865.6532,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-04-01',330112.3055,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE abr/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-04-01',55879.5600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2025 (55,880 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-04-01',28843.6678,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-04-01',429.7707,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-04-01',10521138.5686,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-04-01',292604.7123,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-05-01',5661610.2326,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-05-01',7852441.3766,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-05-01',318127.3727,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE mai/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-05-01',56894.7000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2025 (56,895 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-05-01',30034.3017,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-05-01',447.5111,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-05-01',10857122.3529,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-05-01',302358.2027,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-06-01',5357517.8912,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-06-01',7430676.6868,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-06-01',306135.6452,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE jun/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-06-01',58127.9100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2025 (58,128 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-06-01',28933.7585,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-06-01',431.1130,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-06-01',10076662.0958,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-06-01',292604.7123,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,3,2,1,'2025-07-01',5578338.0424,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-07-01',7736945.9673,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-07-01',299843.7368,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE jul/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-07-01',58753.2600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2025 (58,753 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-07-01',30082.7339,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-07-01',448.2327,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-07-01',10192497.5425,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-07-01',302358.2027,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-08-01',5669966.2020,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-08-01',7864030.7934,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-08-01',309585.1483,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE ago/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-08-01',59528.7400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2025 (59,529 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-08-01',30379.8500,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-08-01',452.6598,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-08-01',10737036.3201,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-08-01',302358.2027,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-09-01',5688791.7307,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-09-01',7890141.0967,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-09-01',314821.3503,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE set/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-09-01',60212.6200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2025 (60,213 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-09-01',28905.6884,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-09-01',430.6948,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-09-01',10735711.1150,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-09-01',292604.7123,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-10-01',6062575.0296,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-10-01',8408564.5348,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-10-01',324434.1042,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE out/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-10-01',60956.4500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2025 (60,956 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-10-01',30028.8053,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-10-01',447.4292,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-10-01',11281121.6852,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-10-01',302358.2027,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-11-01',5921783.3568,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-11-01',8213291.7570,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-11-01',325750.0309,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE nov/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-11-01',61659.2200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2025 (61,659 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-11-01',29543.7476,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-11-01',440.2018,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-11-01',10112980.5227,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-11-01',292604.7123,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2025-12-01',6227993.8501,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,3,1,2,'2025-12-01',8637994.2443,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,3,3,3,'2025-12-01',326354.2158,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE dez/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,3,4,4,'2025-12-01',64268.1600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2025 (64,268 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2025-12-01',30177.2539,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2025'),
  (5,3,6,5,'2025-12-01',449.6411,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2025-12-01',9335662.1635,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2025). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2025-12-01',302358.2027,'DERIVADO','SEEG Municípios 2025: 3,560,024 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,3,2,1,'2026-01-01',6233352.5579,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,3,1,2,'2026-01-01',8645426.5714,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,3,3,3,'2026-01-01',332881.3637,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE jan/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,3,4,4,'2026-01-01',64692.6500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2026 (64,693 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2026-01-01',30211.1476,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2026'),
  (5,3,6,5,'2026-01-01',450.1461,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2026-01-01',9049185.3199,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2026). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2026-01-01',301463.9545,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,3,2,1,'2026-02-01',5593622.7890,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,3,1,2,'2026-02-01',7758145.3385,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,3,3,3,'2026-02-01',324831.8701,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE fev/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,3,4,4,'2026-02-01',65116.0300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2026 (65,116 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2026-02-01',27287.4345,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2026'),
  (5,3,6,5,'2026-02-01',406.5828,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2026-02-01',9061188.8519,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2026). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2026-02-01',272505.6939,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,3,2,1,'2026-03-01',6198964.5075,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,3,1,2,'2026-03-01',8597731.6332,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,3,3,3,'2026-03-01',324636.5479,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE mar/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,3,4,4,'2026-03-01',65974.2000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2026 (65,974 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2026-03-01',30327.6409,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2026'),
  (5,3,6,5,'2026-03-01',451.8818,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2026-03-01',10934108.8152,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2026). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2026-03-01',303925.1286,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,3,2,1,'2026-04-01',5697772.4078,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,3,1,2,'2026-04-01',7902596.9596,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,3,3,3,'2026-04-01',343106.9702,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE abr/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,3,4,4,'2026-04-01',67026.6500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2026 (67,027 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2026-04-01',29193.5369,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2026'),
  (5,3,6,5,'2026-04-01',434.9837,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2026-04-01',10172562.6344,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2026). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2026-04-01',294660.5108,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,3,2,1,'2026-05-01',5661783.1023,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,3,1,2,'2026-05-01',7852681.1405,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,3,3,3,'2026-05-01',327255.7370,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE mai/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,3,4,4,'2026-05-01',67810.7600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2026 (67,811 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2026-05-01',29944.2787,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2026'),
  (5,3,6,5,'2026-05-01',446.1698,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2026-05-01',10288565.9761,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2026). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2026-05-01',302419.5348,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,3,2,1,'2026-06-01',5417277.2630,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,3,1,2,'2026-06-01',7513560.6976,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,3,3,3,'2026-06-01',310799.1621,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE jun/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,3,4,4,'2026-06-01',68801.0600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2026 (68,801 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2026-06-01',29112.8926,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2026'),
  (5,3,6,5,'2026-06-01',433.7821,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2026-06-01',9816064.6167,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2026). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2026-06-01',291186.0485,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,3,2,1,'2026-07-01',5519972.3998,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,3,1,2,'2026-07-01',7655995.0066,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,3,3,3,'2026-07-01',308422.1133,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE jul/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,3,4,4,'2026-07-01',69812.1700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2026 (69,812 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2026-07-01',30328.7984,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2026'),
  (5,3,6,5,'2026-07-01',451.8991,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2026-07-01',9786491.6224,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2026). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2026-07-01',304960.8811,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,3,2,1,'2026-08-01',5667170.3568,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,3,1,2,'2026-08-01',7860153.0607,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,3,3,3,'2026-08-01',319532.8211,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE ago/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,3,4,4,'2026-08-01',70124.7800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2026 (70,125 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2026-08-01',30257.7054,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2026'),
  (5,3,6,5,'2026-08-01',450.8398,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2026-08-01',10514785.3290,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2026). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2026-08-01',303405.6190,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,3,2,1,'2026-09-01',5707851.3268,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (141 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,3,1,2,'2026-09-01',7916576.0427,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 27.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,3,3,3,'2026-09-01',321855.0076,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 3.854 TWh) x variação oficial do Estado (EPE ainda não publicou set/2026; usado set/2025 x crescimento recente). O Anuário de 2026 ainda não foi publicado'),
  (4,3,4,4,'2026-09-01',70781.0100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2026 (70,781 kW). Base de 16/11/2026.'),
  (5,3,5,5,'2026-09-01',28938.7364,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.72 kg/hab/dia) x população IBGE 2026'),
  (5,3,6,5,'2026-09-01',431.1872,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.49%)'),
  (7,3,7,7,'2026-09-01',9849017.7624,'ESTIMADO','ESTIMADO: 7.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2026). Não há dado oficial mensal desta cidade'),
  (8,3,8,8,'2026-09-01',295325.0761,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,4,2,1,'2023-01-01',4116599.1819,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-01-01',6209048.5398,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-01-01',197368.7649,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE jan/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-01-01',5957.3500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2023 (5,957 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-01-01',23200.2946,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-01-01',271.4434,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-01-01',4587322.3050,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-01-01',34469.0274,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2023-02-01',3683141.0818,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-02-01',5555265.5833,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-02-01',201781.7641,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE fev/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-02-01',6466.7400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2023 (6,467 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-02-01',20955.1048,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-02-01',245.1747,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-02-01',4530084.9134,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-02-01',31133.3151,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2023-03-01',4038927.4992,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-03-01',6091896.6805,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-03-01',207161.2858,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE mar/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-03-01',7061.3300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2023 (7,061 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-03-01',23200.2946,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-03-01',271.4434,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-03-01',5572274.1093,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-03-01',34469.0274,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2023-04-01',3758307.2263,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-04-01',5668638.3504,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-04-01',211195.9345,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE abr/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-04-01',7317.5000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2023 (7,318 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-04-01',22451.8980,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-04-01',262.6872,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-04-01',4796768.9854,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-04-01',33357.1233,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2023-05-01',3728240.7685,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-05-01',5623289.2436,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-05-01',195263.1333,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE mai/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-05-01',7862.5000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2023 (7,862 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-05-01',23200.2946,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-05-01',271.4434,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-05-01',5517422.0542,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-05-01',34469.0274,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2023-06-01',3532808.7927,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-06-01',5328520.0493,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-06-01',197447.5190,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE jun/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-06-01',8005.7500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2023 (8,006 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-06-01',22451.8980,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-06-01',262.6872,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-06-01',5069614.4820,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-06-01',33357.1233,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2023-07-01',3650569.0858,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-07-01',5506137.3843,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-07-01',193330.5887,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE jul/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-07-01',8327.2800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2023 (8,327 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-07-01',23200.2946,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-07-01',271.4434,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-07-01',4821220.0552,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-07-01',34469.0274,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2023-08-01',3728240.7685,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-08-01',5623289.2436,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-08-01',199403.3423,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE ago/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-08-01',8532.9500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2023 (8,533 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-08-01',23200.2946,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-08-01',271.4434,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-08-01',5379052.5071,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-08-01',34469.0274,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2023-09-01',3720724.1540,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-09-01',5611951.9669,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-09-01',208794.7111,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE set/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-09-01',8602.6300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2023 (8,603 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-09-01',22451.8980,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-09-01',262.6872,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-09-01',4967716.1350,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-09-01',33357.1233,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,4,2,1,'2023-10-01',3961255.8165,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-10-01',5974744.8213,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-10-01',214287.9745,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE out/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-10-01',8798.4500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2023 (8,798 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-10-01',23200.2946,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-10-01',271.4434,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-10-01',5161409.0419,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-10-01',34469.0274,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2023-11-01',3871056.4431,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-11-01',5838697.5009,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-11-01',218427.3540,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE nov/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-11-01',8922.0800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2023 (8,922 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-11-01',22451.8980,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-11-01',262.6872,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-11-01',5127573.0178,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-11-01',33357.1233,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2023-12-01',4116599.1819,'DERIVADO','SNIS 2023: consumo anual oficial de 45.91 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2023-12-01',6209048.5398,'DERIVADO','SNIS 2023: índice de perdas oficial de 33.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,4,3,3,'2023-12-01',223377.5450,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE dez/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,4,4,4,'2023-12-01',9055.7900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2023 (9,056 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2023-12-01',23200.2946,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.98 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2023-12-01',271.4434,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.17% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2023-12-01',5343512.4655,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2023). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2023-12-01',34469.0274,'DERIVADO','SEEG Municípios 2023: 405,845 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-01-01',4242727.7210,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-01-01',6139982.2301,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-01-01',216006.4188,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-01-01',9227.2200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2024 (9,227 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-01-01',22208.8377,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-01-01',233.1928,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-01-01',4709795.4101,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-01-01',31827.0902,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-02-01',3931559.9241,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-02-01',5689667.0392,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-02-01',216660.0737,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-02-01',9416.6500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2024 (9,417 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-02-01',20776.0095,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-02-01',218.1481,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-02-01',4838056.1960,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-02-01',29773.7295,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-03-01',4162676.2546,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-03-01',6024133.5088,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-03-01',222615.0964,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-03-01',9597.9000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2024 (9,598 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-03-01',22208.8377,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-03-01',233.1928,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-03-01',5154056.1206,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-03-01',31827.0902,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-04-01',3873458.0533,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-04-01',5605583.2898,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-04-01',218965.7629,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-04-01',9903.4700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2024 (9,903 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-04-01',21492.4236,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-04-01',225.6704,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-04-01',5659945.1179,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-04-01',30800.4098,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-05-01',3842470.3889,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-05-01',5560738.6235,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-05-01',222752.5364,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-05-01',10101.2000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2024 (10,101 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-05-01',22208.8377,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-05-01',233.1928,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-05-01',5398248.6811,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-05-01',31827.0902,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-06-01',3641050.5701,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-06-01',5269248.2925,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-06-01',212439.4133,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-06-01',10273.2100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2024 (10,273 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-06-01',21492.4236,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-06-01',225.6704,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-06-01',5443321.7843,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-06-01',30800.4098,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-07-01',3762418.9224,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-07-01',5444889.9022,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-07-01',202532.7346,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-07-01',10379.2300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2024 (10,379 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-07-01',22208.8377,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-07-01',233.1928,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-07-01',4985379.6587,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-07-01',31827.0902,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-08-01',3842470.3889,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-08-01',5560738.6235,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-08-01',209483.3470,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-08-01',10638.6600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2024 (10,639 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-08-01',22208.8377,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-08-01',233.1928,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-08-01',5688434.9893,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-08-01',31827.0902,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-09-01',3834723.4727,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-09-01',5549527.4569,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-09-01',214234.3098,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-09-01',10933.0400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2024 (10,933 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-09-01',21492.4236,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-09-01',225.6704,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-09-01',5529897.6019,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-09-01',30800.4098,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,4,2,1,'2024-10-01',4082624.7882,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-10-01',5908284.7875,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-10-01',222765.4382,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-10-01',11316.2900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2024 (11,316 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-10-01',22208.8377,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-10-01',233.1928,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-10-01',5856972.5742,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-10-01',31827.0902,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-11-01',3989661.7949,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-11-01',5773750.7885,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-11-01',219458.3883,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-11-01',11520.5900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2024 (11,521 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-11-01',21492.4236,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-11-01',225.6704,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-11-01',5315506.4851,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-11-01',30800.4098,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2024-12-01',4242727.7210,'DERIVADO','SNIS 2024: consumo anual oficial de 47.45 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,4,1,2,'2024-12-01',6139982.2301,'DERIVADO','SNIS 2024: índice de perdas oficial de 30.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,4,3,9,'2024-12-01',218684.8505,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.597 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,4,4,4,'2024-12-01',11769.7600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2024 (11,770 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2024-12-01',22208.8377,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,4,6,5,'2024-12-01',233.1928,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.05% recuperado (oficial) x coleta do mês'),
  (7,4,7,7,'2024-12-01',4810933.1144,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2024). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2024-12-01',31827.0902,'DERIVADO','SEEG Municípios 2024: 375,765 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-01-01',4253411.8618,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-01-01',6155444.0836,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-01-01',218417.2288,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE jan/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-01-01',12243.6000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2025 (12,244 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-01-01',22332.7323,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-01-01',234.4937,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-01-01',4824884.9630,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-01-01',33220.2795,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-02-01',3849285.8627,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-02-01',5570601.8273,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-02-01',224221.5263,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE fev/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-02-01',12517.0000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2025 (12,517 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-02-01',20083.2211,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-02-01',210.8738,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-02-01',5034395.5222,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-02-01',30005.4137,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-03-01',4168337.5807,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-03-01',6032326.4554,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-03-01',229968.1167,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE mar/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-03-01',12771.0000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2025 (12,771 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-03-01',22154.6824,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-03-01',232.6242,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-03-01',5355277.8710,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-03-01',33220.2795,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-04-01',3885974.0476,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-04-01',5623696.1615,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-04-01',221248.7703,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE abr/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-04-01',13078.6000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2025 (13,079 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-04-01',21872.1782,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-04-01',229.6579,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-04-01',5290516.1942,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-04-01',32148.6575,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-05-01',3890531.3770,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-05-01',5630291.4284,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-05-01',214531.5799,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE mai/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-05-01',13534.1600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2025 (13,534 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-05-01',22404.5197,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-05-01',235.2475,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-05-01',5584470.7125,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-05-01',33220.2795,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-06-01',3667495.8204,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-06-01',5307519.2769,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-06-01',206103.9292,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE jun/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-06-01',13903.3600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2025 (13,903 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-06-01',21670.6513,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-06-01',227.5418,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-06-01',5118542.6535,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-06-01',32148.6575,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-07-01',3777830.4407,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-07-01',5467193.1124,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-07-01',202387.0455,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE jul/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-07-01',14324.1000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2025 (14,324 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-07-01',21977.0830,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-07-01',230.7594,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-07-01',5218350.5758,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-07-01',33220.2795,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-08-01',3867685.2870,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-08-01',5597229.0694,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-08-01',209980.6620,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE ago/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-08-01',14492.9200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2025 (14,493 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-08-01',22423.8773,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-08-01',235.4507,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-08-01',5433157.5250,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-08-01',33220.2795,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-09-01',3888104.8491,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-09-01',5626779.8106,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-09-01',212183.8965,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE set/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-09-01',14726.6700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2025 (14,727 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-09-01',21519.1718,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-09-01',225.9513,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-09-01',5427852.0691,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-09-01',32148.6575,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,4,2,1,'2025-10-01',4141020.7306,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-10-01',5992794.1108,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-10-01',217839.7056,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE out/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-10-01',15118.5200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2025 (15,119 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-10-01',22524.1845,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-10-01',236.5039,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-10-01',5651219.0072,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-10-01',33220.2795,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-11-01',3998513.8874,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-11-01',5786561.3421,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-11-01',218902.0302,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE nov/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-11-01',15497.2700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2025 (15,497 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-11-01',21673.2446,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-11-01',227.5691,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-11-01',5130907.9832,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-11-01',32148.6575,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2025-12-01',4270809.6386,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,4,1,2,'2025-12-01',6180621.7636,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,4,3,3,'2025-12-01',220253.2040,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE dez/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,4,4,4,'2025-12-01',16145.6700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2025 (16,146 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2025-12-01',22357.9265,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,4,6,5,'2025-12-01',234.7582,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2025-12-01',4684854.8171,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2025). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2025-12-01',33220.2795,'DERIVADO','SEEG Municípios 2025: 391,142 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,4,2,1,'2026-01-01',4293607.9979,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,4,1,2,'2026-01-01',6213615.0477,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,4,3,3,'2026-01-01',223245.0268,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE jan/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,4,4,4,'2026-01-01',16724.0200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2026 (16,724 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2026-01-01',22632.2042,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,4,6,5,'2026-01-01',237.6381,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2026-01-01',4613794.1163,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2026). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2026-01-01',33482.7625,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,4,2,1,'2026-02-01',3854211.4664,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,4,1,2,'2026-02-01',5577730.0526,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,4,3,3,'2026-02-01',219590.8670,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE fev/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,4,4,4,'2026-02-01',18320.6700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2026 (18,321 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2026-02-01',20382.3317,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,4,6,5,'2026-02-01',214.0145,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2026-02-01',4634594.9909,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2026). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2026-02-01',29891.2454,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,4,2,1,'2026-03-01',4195429.2832,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,4,1,2,'2026-03-01',6071532.9714,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,4,3,3,'2026-03-01',219679.5432,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE mar/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,4,4,4,'2026-03-01',21471.1500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2026 (21,471 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2026-03-01',22125.0084,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,4,6,5,'2026-03-01',232.3126,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2026-03-01',5530423.7568,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2026). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2026-03-01',33581.4069,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,4,2,1,'2026-04-01',3881750.8223,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,4,1,2,'2026-04-01',5617584.4027,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,4,3,3,'2026-04-01',230377.7899,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE abr/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,4,4,4,'2026-04-01',21760.4500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2026 (21,760 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2026-04-01',21872.8546,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,4,6,5,'2026-04-01',229.6650,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2026-04-01',5178844.8968,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2026). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2026-04-01',32278.2884,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,4,2,1,'2026-05-01',3908886.6177,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,4,1,2,'2026-05-01',5656854.7289,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,4,3,3,'2026-05-01',220578.6712,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE mai/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,4,4,4,'2026-05-01',22243.5500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2026 (22,244 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2026-05-01',22678.7378,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,4,6,5,'2026-05-01',238.1267,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2026-05-01',5253597.5960,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2026). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2026-05-01',33392.3003,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,4,2,1,'2026-06-01',3657064.5132,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,4,1,2,'2026-06-01',5292423.3187,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,4,3,3,'2026-06-01',208927.9011,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE jun/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,4,4,4,'2026-06-01',22547.8200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2026 (22,548 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2026-06-01',21377.2548,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,4,6,5,'2026-06-01',224.4612,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2026-06-01',5038794.6119,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2026). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2026-06-01',32154.9895,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,4,2,1,'2026-07-01',3785252.9882,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,4,1,2,'2026-07-01',5477934.8599,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,4,3,3,'2026-07-01',207638.7313,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE jul/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,4,4,4,'2026-07-01',22919.0700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2026 (22,919 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2026-07-01',22430.1708,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,4,6,5,'2026-07-01',235.5168,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2026-07-01',4972736.1020,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2026). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2026-07-01',33135.4584,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,4,2,1,'2026-08-01',3867744.1842,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,4,1,2,'2026-08-01',5597314.3042,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,4,3,3,'2026-08-01',214849.4835,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE ago/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,4,4,4,'2026-08-01',23476.7500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2026 (23,477 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2026-08-01',22272.1421,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,4,6,5,'2026-08-01',233.8575,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2026-08-01',5354143.1894,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2026). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2026-08-01',33149.5770,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,4,2,1,'2026-09-01',3888083.7281,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (166 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,4,1,2,'2026-09-01',5626749.2447,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 30.9%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,4,3,3,'2026-09-01',216291.1890,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.597 TWh) x variação oficial do Estado (EPE ainda não publicou set/2026; usado set/2025 x crescimento recente). O Anuário de 2026 ainda não foi publicado'),
  (4,4,4,4,'2026-09-01',23898.4500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2026 (23,898 kW). Base de 16/11/2026.'),
  (5,4,5,5,'2026-09-01',21715.2078,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,4,6,5,'2026-09-01',228.0097,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.05%)'),
  (7,4,7,7,'2026-09-01',4985262.0644,'ESTIMADO','ESTIMADO: 6.8 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2026). Não há dado oficial mensal desta cidade'),
  (8,4,8,8,'2026-09-01',32200.9226,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,5,2,1,'2023-01-01',3865925.5545,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-01-01',6088071.7394,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-01-01',160230.7513,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE jan/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-01-01',35278.2300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2023 (35,278 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-01-01',15423.7090,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-01-01',664.7619,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-01-01',4603189.2920,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-01-01',57348.6411,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-02-01',3458862.1821,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-02-01',5447027.0584,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-02-01',164053.9257,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE fev/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-02-01',36886.2200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2023 (36,886 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-02-01',13931.0920,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-02-01',600.4301,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-02-01',4554752.5618,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-02-01',51798.7726,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-03-01',3792983.5629,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-03-01',5973202.4613,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-03-01',167259.5777,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE mar/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-03-01',39091.9200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2023 (39,092 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-03-01',15423.7090,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-03-01',664.7619,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-03-01',5581811.6398,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-03-01',57348.6411,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-04-01',3529451.2062,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-04-01',5558190.8759,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-04-01',170497.3403,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE abr/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-04-01',40877.4800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2023 (40,877 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-04-01',14926.1700,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-04-01',643.3179,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-04-01',4810335.4961,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-04-01',55498.6849,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-05-01',3501215.5966,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-05-01',5513725.3489,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-05-01',157881.4505,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE mai/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-05-01',42768.7500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2023 (42,769 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-05-01',15423.7090,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-05-01',664.7619,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-05-01',5562544.1901,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-05-01',57348.6411,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-06-01',3317684.1338,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-06-01',5224699.4234,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-06-01',161012.2669,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE jun/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-06-01',43772.6700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2023 (43,773 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-06-01',14926.1700,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-06-01',643.3179,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-06-01',5084255.6469,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-06-01',55498.6849,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-07-01',3428273.6050,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-07-01',5398856.0708,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-07-01',157480.7143,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE jul/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-07-01',47925.1600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2023 (47,925 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-07-01',15423.7090,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-07-01',664.7619,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-07-01',4725899.3033,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-07-01',57348.6411,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-08-01',3501215.5966,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-08-01',5513725.3489,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-08-01',161418.3642,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE ago/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-08-01',49631.9100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2023 (49,632 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-08-01',15423.7090,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-08-01',664.7619,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-08-01',5401171.7458,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-08-01',57348.6411,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-09-01',3494156.6941,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-09-01',5502608.9671,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-09-01',168849.4433,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE set/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-09-01',51323.2700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2023 (51,323 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-09-01',14926.1700,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-09-01',643.3179,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-09-01',4947164.0622,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-09-01',55498.6849,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-10-01',3720041.5713,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-10-01',5858333.1832,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-10-01',173651.7535,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE out/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-10-01',52321.6700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2023 (52,322 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-10-01',15423.7090,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-10-01',664.7619,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-10-01',5114267.3335,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-10-01',57348.6411,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-11-01',3635334.7424,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-11-01',5724936.6022,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-11-01',178333.7854,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE nov/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-11-01',55425.2700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2023 (55,425 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-11-01',14926.1700,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-11-01',643.3179,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-11-01',5115484.1595,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-11-01',55498.6849,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2023-12-01',3865925.5545,'DERIVADO','SNIS 2023: consumo anual oficial de 43.11 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2023-12-01',6088071.7394,'DERIVADO','SNIS 2023: índice de perdas oficial de 36.5% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,5,3,3,'2023-12-01',181662.1590,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE dez/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,5,4,4,'2023-12-01',56765.5100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2023 (56,766 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2023-12-01',15423.7090,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.7 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,5,6,5,'2023-12-01',664.7619,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 4.31% recuperado (oficial) x coleta do mês'),
  (7,5,7,7,'2023-12-01',5405130.1538,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2023). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2023-12-01',57348.6411,'DERIVADO','SEEG Municípios 2023: 675,234 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,5,2,1,'2024-01-01',4033026.9308,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-01-01',5939656.7464,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-01-01',175454.1847,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-01-01',57550.6500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2024 (57,551 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-01-01',15671.1528,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-01-01',675.4267,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-01-01',4705589.4467,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-01-01',54555.5109,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-02-01',3737238.8936,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-02-01',5504033.7166,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-02-01',175985.1249,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-02-01',58420.5000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2024 (58,420 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-02-01',14777.6699,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-02-01',636.9176,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-02-01',4856290.0982,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-02-01',51035.8005,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-03-01',3956932.0830,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-03-01',5827587.7512,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-03-01',180822.1739,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-03-01',63775.1900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2024 (63,775 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-03-01',15920.4137,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-03-01',686.1698,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-03-01',5149168.3080,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-03-01',54555.5109,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-04-01',3682008.7621,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-04-01',5422693.3169,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-04-01',177857.9526,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-04-01',69292.3100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2024 (69,292 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-04-01',15228.5268,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-04-01',656.3495,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-04-01',5708953.8992,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-04-01',52795.6557,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-05-01',3652552.6920,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-05-01',5379311.7703,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-05-01',180933.8114,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-05-01',74462.9100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2024 (74,463 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-05-01',15813.7995,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-05-01',681.5748,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-05-01',5372998.6542,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-05-01',54555.5109,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-06-01',3461088.2364,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-06-01',5097331.7178,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-06-01',172556.8354,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-06-01',75572.3700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2024 (75,572 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-06-01',15258.8306,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-06-01',657.6556,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-06-01',5376518.6818,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-06-01',52795.6557,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-07-01',3576457.8443,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-07-01',5267242.7751,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-07-01',164509.9993,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-07-01',85792.8900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2024 (85,793 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-07-01',15858.8637,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-07-01',683.5170,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-07-01',4987068.8802,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-07-01',54555.5109,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-08-01',3652552.6920,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-08-01',5379311.7703,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-08-01',170155.7299,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-08-01',86955.5700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2024 (86,956 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-08-01',15724.7578,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-08-01',677.7371,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-08-01',5653382.7042,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-08-01',54555.5109,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-09-01',3645188.6745,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-09-01',5368466.3837,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-09-01',174014.7648,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-09-01',88463.8000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2024 (88,464 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-09-01',15335.5283,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-09-01',660.9613,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-09-01',5510782.9738,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-09-01',52795.6557,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-10-01',3880837.2353,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-10-01',5715518.7560,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-10-01',180944.2912,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-10-01',89974.6300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2024 (89,975 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-10-01',15644.6383,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-10-01',674.2839,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-10-01',5866308.9940,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-10-01',54555.5109,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-11-01',3792469.0250,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-11-01',5585374.1164,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-11-01',178258.0944,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-11-01',91230.9300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2024 (91,231 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-11-01',15143.0366,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-11-01',652.6649,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-11-01',5382278.2868,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-11-01',52795.6557,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2024-12-01',4033026.9308,'DERIVADO','SNIS 2024: consumo anual oficial de 45.10 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,5,1,2,'2024-12-01',5939656.7464,'DERIVADO','SNIS 2024: índice de perdas oficial de 32.1% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,5,3,9,'2024-12-01',177629.7776,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.109 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,5,4,4,'2024-12-01',92718.7000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2024 (92,719 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2024-12-01',15832.8206,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2024'),
  (5,5,6,5,'2024-12-01',682.3946,'ESTIMADO','ESTIMADO: o valor oficial do SINISA 2024 é inconsistente; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2024-12-01',4848837.6529,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2024). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2024-12-01',54555.5109,'DERIVADO','SEEG Municípios 2024: 644,107 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,5,2,1,'2025-01-01',4050740.8676,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-01-01',5965745.0186,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-01-01',177485.7621,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE jan/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-01-01',94052.0500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2025 (94,052 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-01-01',15922.6097,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-01-01',686.2645,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-01-01',4773204.6912,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-01-01',53353.8877,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-02-01',3640832.8381,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-02-01',5362051.3080,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-02-01',181639.3357,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE fev/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-02-01',95049.5100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2025 (95,050 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-02-01',14373.5062,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-02-01',619.4981,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-02-01',5040310.9078,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-02-01',48190.6082,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-03-01',3999797.7513,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-03-01',5890718.3377,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-03-01',187332.1922,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE mar/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-03-01',96485.3100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2025 (96,485 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-03-01',15614.0004,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-03-01',672.9634,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-03-01',5373202.0053,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-03-01',53353.8877,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-04-01',3713220.1879,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-04-01',5468660.0706,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-04-01',179442.8767,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE abr/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-04-01',97741.4200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2025 (97,741 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-04-01',15162.1983,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-04-01',653.4907,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-04-01',5305820.5271,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-04-01',51632.7945,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-05-01',3663713.9946,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-05-01',5395749.6239,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-05-01',174657.8186,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE mai/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-05-01',98980.7200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2025 (98,981 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-05-01',15751.2988,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-05-01',678.8810,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-05-01',5483574.6662,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-05-01',53353.8877,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-06-01',3488757.7434,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-06-01',5138082.0964,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-06-01',167369.2493,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE jun/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-06-01',99775.9700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2025 (99,776 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-06-01',15484.9562,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-06-01',667.4016,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-06-01',5089027.0403,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-06-01',51632.7945,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-07-01',3576058.1314,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-07-01',5266654.0963,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-07-01',163913.0335,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE jul/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-07-01',100700.8300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2025 (100,701 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-07-01',15757.7431,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-07-01',679.1587,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-07-01',5148763.3066,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-07-01',53353.8877,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-08-01',3646176.5162,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-08-01',5369921.2316,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-08-01',170214.7675,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE ago/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-08-01',101888.6400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2025 (101,889 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-08-01',15860.0070,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-08-01',683.5663,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-08-01',5366120.4624,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-08-01',53353.8877,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-09-01',3677398.3050,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-09-01',5415903.2474,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-09-01',172372.4443,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE set/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-09-01',103008.2700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2025 (103,008 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-09-01',15455.7743,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-09-01',666.1439,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-09-01',5403557.9260,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-09-01',51632.7945,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-10-01',3932216.0250,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-10-01',5791187.0767,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-10-01',177560.5441,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE out/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-10-01',104803.1400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2025 (104,803 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-10-01',15799.5603,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-10-01',680.9610,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-10-01',5625181.1958,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-10-01',53353.8877,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-11-01',3806018.8637,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-11-01',5605329.6962,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-11-01',177765.3666,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE nov/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-11-01',105677.3700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2025 (105,677 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-11-01',15462.3470,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-11-01',666.4272,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-11-01',5138983.3064,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-11-01',51632.7945,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,5,2,1,'2025-12-01',4025259.1997,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,5,1,2,'2025-12-01',5928216.7889,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,5,3,3,'2025-12-01',178575.6876,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE dez/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,5,4,4,'2025-12-01',107012.9300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2025 (107,013 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2025-12-01',15660.2897,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2025'),
  (5,5,6,5,'2025-12-01',674.9585,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2025-12-01',4689568.4948,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2025). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2025-12-01',53353.8877,'DERIVADO','SEEG Municípios 2025: 628,199 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,5,2,1,'2026-01-01',4078009.1537,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,5,1,2,'2026-01-01',6005904.4973,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,5,3,3,'2026-01-01',181713.2916,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE jan/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,5,4,4,'2026-01-01',107823.9900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2026 (107,824 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2026-01-01',15954.6763,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2026'),
  (5,5,6,5,'2026-01-01',687.6465,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2026-01-01',4561526.1011,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2026). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2026-01-01',53839.3342,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,5,2,1,'2026-02-01',3630814.0729,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,5,1,2,'2026-02-01',5347296.1310,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,5,3,3,'2026-02-01',177418.5394,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE fev/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,5,4,4,'2026-02-01',108860.8600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2026 (108,861 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2026-02-01',14171.2958,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2026'),
  (5,5,6,5,'2026-02-01',610.7828,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2026-02-01',4577782.5838,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2026). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2026-02-01',48600.2397,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,5,2,1,'2026-03-01',3977068.3674,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,5,1,2,'2026-03-01',5857243.5455,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,5,3,3,'2026-03-01',177421.4854,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE mar/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,5,4,4,'2026-03-01',110591.1400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2026 (110,591 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2026-03-01',15684.5951,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2026'),
  (5,5,6,5,'2026-03-01',676.0060,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2026-03-01',5488660.9279,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2026). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2026-03-01',53315.1663,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,5,2,1,'2026-04-01',3722232.1708,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,5,1,2,'2026-04-01',5481932.5049,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,5,3,3,'2026-04-01',186920.2692,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE abr/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,5,4,4,'2026-04-01',112250.0800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2026 (112,250 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2026-04-01',15400.6107,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2026'),
  (5,5,6,5,'2026-04-01',663.7663,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2026-04-01',5164307.5244,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2026). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2026-04-01',51375.3466,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,5,2,1,'2026-05-01',3660937.5168,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,5,1,2,'2026-05-01',5391660.5549,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,5,3,3,'2026-05-01',179095.4653,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE mai/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,5,4,4,'2026-05-01',113728.7100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2026 (113,729 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2026-05-01',15689.4273,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2026'),
  (5,5,6,5,'2026-05-01',676.2143,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2026-05-01',5237827.0029,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2026). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2026-05-01',53596.9705,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,5,2,1,'2026-06-01',3473233.8272,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,5,1,2,'2026-06-01',5115219.1859,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,5,3,3,'2026-06-01',169433.9852,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE jun/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,5,4,4,'2026-06-01',115140.1700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2026 (115,140 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2026-06-01',15343.2779,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2026'),
  (5,5,6,5,'2026-06-01',661.2953,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2026-06-01',5026934.0115,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2026). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2026-06-01',51930.2204,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,5,2,1,'2026-07-01',3611428.7620,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,5,1,2,'2026-07-01',5318746.3358,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,5,3,3,'2026-07-01',168747.4271,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE jul/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,5,4,4,'2026-07-01',116363.5600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2026 (116,364 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2026-07-01',15713.8592,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2026'),
  (5,5,6,5,'2026-07-01',677.2673,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2026-07-01',4926790.0198,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2026). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2026-07-01',53236.7038,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,5,2,1,'2026-08-01',3698590.5499,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,5,1,2,'2026-08-01',5447114.2120,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,5,3,3,'2026-08-01',175138.7746,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE ago/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,5,4,4,'2026-08-01',116490.8500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2026 (116,491 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2026-08-01',16054.4527,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2026'),
  (5,5,6,5,'2026-08-01',691.9469,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2026-08-01',5337152.1577,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2026). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2026-08-01',53641.3189,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,5,2,1,'2026-09-01',3668011.4400,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (170 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,5,1,2,'2026-09-01',5402078.7040,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 32.1%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,5,3,3,'2026-09-01',176162.3673,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.109 TWh) x variação oficial do Estado (EPE ainda não publicou set/2026; usado set/2025 x crescimento recente). O Anuário de 2026 ainda não foi publicado'),
  (4,5,4,4,'2026-09-01',117621.7500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2026 (117,622 kW). Base de 16/11/2026.'),
  (5,5,5,5,'2026-09-01',15361.1844,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2023: 0.7 kg/hab/dia) x população IBGE 2026'),
  (5,5,6,5,'2026-09-01',662.0670,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2023: 4.31%)'),
  (7,5,7,7,'2026-09-01',4953217.0019,'ESTIMADO','ESTIMADO: 7.3 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2026). Não há dado oficial mensal desta cidade'),
  (8,5,8,8,'2026-09-01',52097.6732,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,6,2,1,'2023-01-01',4382746.8884,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-01-01',6732330.0898,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-01-01',181962.9878,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE jan/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-01-01',23220.2100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2023 (23,220 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-01-01',19967.9947,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-01-01',297.5231,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-01-01',4260716.7857,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-01-01',46526.4137,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2023-02-01',3921264.7146,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-02-01',6023448.1022,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-02-01',185538.9056,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE fev/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-02-01',24629.1000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2023 (24,629 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-02-01',18035.6081,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-02-01',268.7306,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-02-01',4206709.5785,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-02-01',42023.8575,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2023-03-01',4300053.5509,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-03-01',6605304.9937,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-03-01',190876.4084,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE mar/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-03-01',25929.7000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2023 (25,930 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-03-01',19967.9947,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-03-01',297.5231,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-03-01',5229218.3477,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-03-01',46526.4137,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,6,2,1,'2023-04-01',4001290.5251,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-04-01',6146375.6145,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-04-01',194473.8792,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE abr/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-04-01',26790.2500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2023 (26,790 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-04-01',19323.8658,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-04-01',287.9256,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-04-01',4499421.9960,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-04-01',45025.5616,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2023-05-01',3969280.2009,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-05-01',6097204.6096,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-05-01',179414.4012,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE mai/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-05-01',27544.3100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2023 (27,544 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-05-01',19967.9947,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-05-01',297.5231,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-05-01',5233972.0957,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-05-01',46526.4137,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2023-06-01',3761213.0935,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-06-01',5777593.0776,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-06-01',182643.0935,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE jun/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-06-01',28223.2100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2023 (28,223 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-06-01',19323.8658,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-06-01',287.9256,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-06-01',4725098.7940,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-06-01',45025.5616,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2023-07-01',3886586.8633,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-07-01',5970179.5136,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-07-01',177959.8167,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE jul/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-07-01',28920.4100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2023 (28,920 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-07-01',19967.9947,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-07-01',297.5231,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-07-01',4487477.8226,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-07-01',46526.4137,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2023-08-01',3969280.2009,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-08-01',6097204.6096,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-08-01',182817.4578,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE ago/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-08-01',29642.3900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2023 (29,642 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-08-01',19967.9947,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-08-01',297.5231,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-08-01',5122784.8267,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-08-01',46526.4137,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2023-09-01',3961277.6198,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-09-01',6084911.8584,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-09-01',192393.5813,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE set/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-09-01',30315.5700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2023 (30,316 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-09-01',19323.8658,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-09-01',287.9256,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-09-01',4708624.3387,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-09-01',45025.5616,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2023-10-01',4217360.2134,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-10-01',6478279.8977,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-10-01',197407.6472,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE out/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-10-01',30801.8600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2023 (30,802 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-10-01',19967.9947,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-10-01',297.5231,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-10-01',4833171.8964,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-10-01',46526.4137,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2023-11-01',4121329.2408,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-11-01',6330766.8830,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-11-01',201667.2845,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE nov/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-11-01',32232.9800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2023 (32,233 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-11-01',19323.8658,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-11-01',287.9256,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-11-01',4779656.8698,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-11-01',45025.5616,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2023-12-01',4382746.8884,'DERIVADO','SNIS 2023: consumo anual oficial de 48.87 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2023-12-01',6732330.0898,'DERIVADO','SNIS 2023: índice de perdas oficial de 34.9% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,6,3,3,'2023-12-01',205657.5979,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE dez/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,6,4,4,'2023-12-01',33202.2400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2023 (33,202 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2023-12-01',19967.9947,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 0.87 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2023-12-01',297.5231,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 1.49% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2023-12-01',5069703.4484,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2023). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2023-12-01',46526.4137,'DERIVADO','SEEG Municípios 2023: 547,811 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-01-01',4610903.8619,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-01-01',7007452.6776,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-01-01',199208.5333,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-01-01',34515.7000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2024 (34,516 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-01-01',21602.7307,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-01-01',399.6505,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-01-01',4420444.1007,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-01-01',42477.9617,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-02-01',4272733.4934,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-02-01',6493515.9475,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-02-01',199811.3563,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-02-01',38563.7300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2024 (38,564 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-02-01',20209.0061,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-02-01',373.8666,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-02-01',4585986.2354,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-02-01',39737.4481,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-03-01',4523905.6758,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-03-01',6875236.5894,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-03-01',205303.2826,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-03-01',41667.4500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2024 (41,667 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-03-01',21602.7307,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-03-01',399.6505,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-03-01',4886918.8514,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-03-01',42477.9617,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,6,2,1,'2024-04-01',4209589.6487,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-04-01',6397552.6576,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-04-01',201937.7420,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-04-01',42678.1500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2024 (42,678 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-04-01',20905.8684,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-04-01',386.7586,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-04-01',5325022.3479,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-04-01',41107.7049,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-05-01',4175912.9315,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-05-01',6346372.2363,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-05-01',205430.0344,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-05-01',45321.1900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2024 (45,321 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-05-01',21602.7307,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-05-01',399.6505,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-05-01',5131136.5114,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-05-01',42477.9617,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-06-01',3957014.2698,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-06-01',6013699.4981,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-06-01',195918.9184,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-06-01',46730.7800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2024 (46,731 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-06-01',20905.8684,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-06-01',386.7586,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-06-01',5160319.4924,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-06-01',41107.7049,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-07-01',4088914.7454,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-07-01',6214156.1481,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-07-01',186782.6392,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-07-01',48325.2000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2024 (48,325 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-07-01',21602.7307,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-07-01',399.6505,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-07-01',4720527.1327,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-07-01',42477.9617,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-08-01',4175912.9315,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-08-01',6346372.2363,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-08-01',193192.7326,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-08-01',52686.3600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2024 (52,686 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-08-01',21602.7307,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-08-01',399.6505,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-08-01',5336063.9971,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-08-01',42477.9617,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-09-01',4167493.7522,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-09-01',6333577.1310,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-09-01',197574.2335,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-09-01',57024.2400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2024 (57,024 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-09-01',20905.8684,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-09-01',386.7586,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-09-01',5282714.7969,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-09-01',41107.7049,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-10-01',4436907.4897,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-10-01',6743020.5011,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-10-01',205441.9330,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-10-01',59106.7200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2024 (59,107 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-10-01',21602.7307,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-10-01',399.6505,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-10-01',5583596.1807,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-10-01',42477.9617,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-11-01',4335877.3382,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-11-01',6589479.2373,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-11-01',202392.0580,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-11-01',60584.9700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2024 (60,585 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-11-01',20905.8684,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-11-01',386.7586,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-11-01',5046742.7764,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-11-01',41107.7049,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2024-12-01',4610903.8619,'DERIVADO','SNIS 2024: consumo anual oficial de 51.57 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,6,1,2,'2024-12-01',7007452.6776,'DERIVADO','SNIS 2024: índice de perdas oficial de 34.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,6,3,9,'2024-12-01',201678.6749,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.395 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,6,4,4,'2024-12-01',62438.6300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2024 (62,439 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2024-12-01',21602.7307,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.92 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,6,6,5,'2024-12-01',399.6505,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 1.85% recuperado (oficial) x coleta do mês'),
  (7,6,7,7,'2024-12-01',4538528.6832,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2024). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2024-12-01',42477.9617,'DERIVADO','SEEG Municípios 2024: 501,514 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-01-01',4623003.6541,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-01-01',7025841.4196,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-01-01',202214.3923,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE jan/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-01-01',63840.6000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2025 (63,841 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-01-01',21551.1909,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-01-01',398.6970,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-01-01',4545964.6252,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-01-01',42314.5753,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-02-01',4143103.6704,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-02-01',6296510.1373,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-02-01',206494.5278,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE fev/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-02-01',64918.7800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2025 (64,919 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-02-01',19649.2046,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-02-01',363.5103,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-02-01',4786898.8787,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-02-01',38219.6164,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-03-01',4585827.5344,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-03-01',6969342.7574,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-03-01',212505.7199,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE mar/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-03-01',66082.1500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2025 (66,082 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-03-01',21980.9108,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-03-01',406.6469,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-03-01',5066653.9562,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-03-01',42314.5753,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,6,2,1,'2025-04-01',4251388.9817,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-04-01',6461077.4798,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-04-01',204902.8356,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE abr/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-04-01',67419.5700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2025 (67,420 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-04-01',20925.9885,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-04-01',387.1308,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-04-01',5044721.4946,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-04-01',40949.5890,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-05-01',4206127.3729,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-05-01',6392290.8403,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-05-01',197946.8801,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE mai/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-05-01',68603.8600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2025 (68,604 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-05-01',21762.6390,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-05-01',402.6088,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-05-01',5197743.2378,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-05-01',42314.5753,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-06-01',3995821.5153,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-06-01',6072677.0749,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-06-01',191164.6790,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE jun/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-06-01',69893.3300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2025 (69,893 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-06-01',21180.3014,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-06-01',391.8356,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-06-01',4781685.0681,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-06-01',40949.5890,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-07-01',4146480.4804,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-07-01',6301642.0675,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-07-01',186646.9589,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE jul/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-07-01',71672.7600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2025 (71,673 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-07-01',21450.9180,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-07-01',396.8420,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-07-01',4905684.9612,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-07-01',42314.5753,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-08-01',4182028.1481,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-08-01',6355665.8785,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-08-01',193372.5073,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE ago/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-08-01',73135.8100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2025 (73,136 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-08-01',22024.7100,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-08-01',407.4571,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-08-01',5069623.8023,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-08-01',42314.5753,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-09-01',4189274.8896,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-09-01',6366679.1636,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-09-01',195112.5941,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE set/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-09-01',74719.6100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2025 (74,720 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-09-01',20945.4826,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-09-01',387.4914,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-09-01',5081537.2013,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-09-01',40949.5890,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-10-01',4454295.8063,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-10-01',6769446.5141,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-10-01',200611.1581,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE out/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-10-01',76177.1800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2025 (76,177 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-10-01',21532.1430,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-10-01',398.3446,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-10-01',5325249.0644,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-10-01',42314.5753,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-11-01',4384694.0381,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-11-01',6663668.7509,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-11-01',202090.1807,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE nov/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-11-01',77824.4400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2025 (77,824 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-11-01',21065.0212,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-11-01',389.7029,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-11-01',4803024.9584,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-11-01',40949.5890,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2025-12-01',4631532.0579,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,6,1,2,'2025-12-01',7038802.5196,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,6,3,3,'2025-12-01',202436.8859,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE dez/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,6,4,4,'2025-12-01',79341.9500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2025 (79,342 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2025-12-01',21765.0207,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2025'),
  (5,6,6,5,'2025-12-01',402.6529,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2025-12-01',4456270.3563,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2025). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2025-12-01',42314.5753,'DERIVADO','SEEG Municípios 2025: 498,220 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,6,2,1,'2026-01-01',4696550.0609,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,6,1,2,'2026-01-01',7137614.0743,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,6,3,3,'2026-01-01',205886.2712,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE jan/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,6,4,4,'2026-01-01',80693.5100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2026 (80,694 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2026-01-01',21742.3656,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,6,6,5,'2026-01-01',402.2338,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2026-01-01',4355452.5892,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2026). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2026-01-01',42235.7790,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,6,2,1,'2026-02-01',4152497.8503,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,6,1,2,'2026-02-01',6310787.0065,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,6,3,3,'2026-02-01',201531.2944,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE fev/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,6,4,4,'2026-02-01',82617.6300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2026 (82,618 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2026-02-01',19793.1472,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,6,6,5,'2026-02-01',366.1732,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2026-02-01',4401362.7571,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2026). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2026-02-01',38623.8743,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,6,2,1,'2026-03-01',4571957.8908,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,6,1,2,'2026-03-01',6948264.2717,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,6,3,3,'2026-03-01',202637.6706,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE mar/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,6,4,4,'2026-03-01',84509.4100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2026 (84,509 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2026-03-01',21636.9955,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,6,6,5,'2026-03-01',400.2844,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2026-03-01',5188020.6508,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2026). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2026-03-01',42764.1878,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,6,2,1,'2026-04-01',4265620.2577,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,6,1,2,'2026-04-01',6482705.5588,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,6,3,3,'2026-04-01',212830.2886,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE abr/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,6,4,4,'2026-04-01',86451.0500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2026 (86,451 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2026-04-01',21363.7428,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,6,6,5,'2026-04-01',395.2292,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2026-04-01',4871425.4246,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2026). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2026-04-01',40994.8077,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,6,2,1,'2026-05-01',4268445.4344,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,6,1,2,'2026-05-01',6486999.1404,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,6,3,3,'2026-05-01',203151.7711,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE mai/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,6,4,4,'2026-05-01',88497.3500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2026 (88,497 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2026-05-01',21633.5219,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,6,6,5,'2026-05-01',400.2202,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2026-05-01',5030049.3735,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2026). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2026-05-01',42495.6328,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,6,2,1,'2026-06-01',4009704.7123,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,6,1,2,'2026-06-01',6093776.1585,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,6,3,3,'2026-06-01',193215.9510,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE jun/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,6,4,4,'2026-06-01',90698.6900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2026 (90,699 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2026-06-01',21282.4779,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,6,6,5,'2026-06-01',393.7258,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2026-06-01',4801414.2883,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2026). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2026-06-01',41261.4275,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,6,2,1,'2026-07-01',4144509.7715,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,6,1,2,'2026-07-01',6298647.0692,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,6,3,3,'2026-07-01',192885.1275,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE jul/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,6,4,4,'2026-07-01',92133.8900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2026 (92,134 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2026-07-01',21927.3486,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,6,6,5,'2026-07-01',405.6559,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2026-07-01',4651096.0344,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2026). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2026-07-01',42818.9766,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,6,2,1,'2026-08-01',4252930.5876,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,6,1,2,'2026-08-01',6463420.3459,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,6,3,3,'2026-08-01',197467.6131,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE ago/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,6,4,4,'2026-08-01',92779.6100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2026 (92,780 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2026-08-01',21581.2644,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,6,6,5,'2026-08-01',399.2534,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2026-08-01',5052111.7249,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2026). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2026-08-01',42631.9333,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,6,2,1,'2026-09-01',4205051.8679,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (186 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,6,1,2,'2026-09-01',6390656.3341,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 34.2%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,6,3,3,'2026-09-01',199731.7695,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.395 TWh) x variação oficial do Estado (EPE ainda não publicou set/2026; usado set/2025 x crescimento recente). O Anuário de 2026 ainda não foi publicado'),
  (4,6,4,4,'2026-09-01',92779.6100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2026 (92,780 kW). Base de 16/11/2026.'),
  (5,6,5,5,'2026-09-01',21241.9053,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.92 kg/hab/dia) x população IBGE 2026'),
  (5,6,6,5,'2026-09-01',392.9752,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 1.85%)'),
  (7,6,7,7,'2026-09-01',4700701.5986,'ESTIMADO','ESTIMADO: 6.6 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2026). Não há dado oficial mensal desta cidade'),
  (8,6,8,8,'2026-09-01',41471.3646,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,7,2,1,'2023-01-01',6354161.2641,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-01-01',10899075.9246,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-01-01',181400.9244,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE jan/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-01-01',67460.2300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2023 (67,460 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-01-01',23662.3502,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-01-01',97.0156,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-01-01',3358434.7375,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-01-01',76027.3726,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2023-02-01',5685098.6355,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-02-01',9751455.6355,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-02-01',185464.3940,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE fev/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-02-01',72277.1100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2023 (72,277 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-02-01',21372.4454,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-02-01',87.6270,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-02-01',3358229.3053,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-02-01',68669.8849,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2023-03-01',6234271.4289,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-03-01',10693432.9826,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-03-01',190227.1661,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE mar/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-03-01',76142.4300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2023 (76,142 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-03-01',23662.3502,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-03-01',97.0156,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-03-01',4166733.0456,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-03-01',76027.3726,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2023-04-01',5801121.0567,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-04-01',9950464.9342,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-04-01',192927.2554,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE abr/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-04-01',78936.4400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2023 (78,936 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-04-01',22899.0486,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-04-01',93.8861,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-04-01',3558917.5449,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-04-01',73574.8767,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2023-05-01',5754712.0882,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-05-01',9870861.2148,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-05-01',178276.6805,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE mai/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-05-01',81850.9200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2023 (81,851 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-05-01',23662.3502,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-05-01',97.0156,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-05-01',4099775.2816,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-05-01',76027.3726,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2023-06-01',5453053.7933,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-06-01',9353437.0382,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-06-01',182578.7270,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE jun/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-06-01',83423.6500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2023 (83,424 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-06-01',22899.0486,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-06-01',93.8861,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-06-01',3771556.8149,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-06-01',73574.8767,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,7,2,1,'2023-07-01',5634822.2530,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-07-01',9665218.2728,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-07-01',177823.8594,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE jul/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-07-01',84507.3400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2023 (84,507 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-07-01',23662.3502,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-07-01',97.0156,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-07-01',3518275.2588,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-07-01',76027.3726,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2023-08-01',5754712.0882,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-08-01',9870861.2148,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-08-01',183108.5594,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE ago/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-08-01',85548.7000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2023 (85,549 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-08-01',23662.3502,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-08-01',97.0156,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-08-01',4025390.9351,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-08-01',76027.3726,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2023-09-01',5743109.8461,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-09-01',9850960.2849,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-09-01',192051.3049,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE set/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-09-01',87481.2200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2023 (87,481 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-09-01',22899.0486,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-09-01',93.8861,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-09-01',3695235.4566,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-09-01',73574.8767,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2023-10-01',6114381.5937,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-10-01',10487790.0407,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-10-01',196325.0663,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE out/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-10-01',89053.4800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2023 (89,053 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-10-01',23662.3502,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-10-01',97.0156,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-10-01',3832667.5739,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-10-01',76027.3726,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2023-11-01',5975154.6884,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-11-01',10248978.8823,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-11-01',201533.5492,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE nov/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-11-01',90557.3100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2023 (90,557 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-11-01',22899.0486,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-11-01',93.8861,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-11-01',3811968.7482,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-11-01',73574.8767,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2023-12-01',6354161.2641,'DERIVADO','SNIS 2023: consumo anual oficial de 70.86 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2023-12-01',10899075.9246,'DERIVADO','SNIS 2023: índice de perdas oficial de 41.7% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,7,3,3,'2023-12-01',204486.5300,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE dez/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,7,4,4,'2023-12-01',92390.6600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2023 (92,391 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2023-12-01',23662.3502,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.07 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2023-12-01',97.0156,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 0.41% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2023-12-01',3975226.3537,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2023). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2023-12-01',76027.3726,'DERIVADO','SEEG Municípios 2023: 895,161 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-01-01',6792216.2764,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-01-01',10747177.6525,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-01-01',198365.1793,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-01-01',95406.5000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2024 (95,407 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-01-01',21677.1840,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-01-01',91.0442,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-01-01',3502890.7745,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-01-01',74679.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-02-01',6294065.2957,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-02-01',9958964.0754,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-02-01',198965.4503,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-02-01',98034.7400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2024 (98,035 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-02-01',20278.6560,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-02-01',85.1704,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-02-01',3618584.1082,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-02-01',69861.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-03-01',6664061.2523,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-03-01',10544400.7156,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-03-01',204434.1263,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-03-01',101760.8500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2024 (101,761 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-03-01',21677.1840,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-03-01',91.0442,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-03-01',3845483.3808,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-03-01',74679.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-04-01',6201049.5524,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-04-01',9811787.2664,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-04-01',201082.8338,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-04-01',105157.0400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2024 (105,157 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-04-01',20977.9200,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-04-01',88.1073,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-04-01',4244068.0240,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-04-01',72270.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-05-01',6151441.1559,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-05-01',9733292.9683,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-05-01',204560.3416,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-05-01',108580.3700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2024 (108,580 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-05-01',21677.1840,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-05-01',91.0442,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-05-01',4000084.9393,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-05-01',74679.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-06-01',5828986.5792,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-06-01',9223080.0304,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-06-01',195089.4911,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-06-01',111922.9400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2024 (111,923 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-06-01',20977.9200,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-06-01',88.1073,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-06-01',4033244.2886,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-06-01',72270.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,7,2,1,'2024-07-01',6023286.1319,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-07-01',9530516.0314,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-07-01',185991.8906,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-07-01',115474.7700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2024 (115,475 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-07-01',21677.1840,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-07-01',91.0442,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-07-01',3708393.8153,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-07-01',74679.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-08-01',6151441.1559,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-08-01',9733292.9683,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-08-01',192374.8467,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-08-01',118569.6600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2024 (118,570 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-08-01',21677.1840,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-08-01',91.0442,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-08-01',4199950.7937,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-08-01',74679.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-09-01',6139039.0568,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-09-01',9713669.3937,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-09-01',196737.7984,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-09-01',121160.9200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2024 (121,161 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-09-01',20977.9200,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-09-01',88.1073,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-09-01',4081408.8483,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-09-01',72270.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-10-01',6535906.2282,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-10-01',10341623.7788,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-10-01',204572.1898,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-10-01',123793.5300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2024 (123,794 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-10-01',21677.1840,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-10-01',91.0442,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-10-01',4368600.3063,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-10-01',74679.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-11-01',6387081.0389,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-11-01',10106140.8844,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-11-01',201535.2266,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-11-01',126123.2100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2024 (126,123 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-11-01',20977.9200,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-11-01',88.1073,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-11-01',3934998.0144,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-11-01',72270.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2024-12-01',6792216.2764,'DERIVADO','SNIS 2024: consumo anual oficial de 75.96 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,7,1,2,'2024-12-01',10747177.6525,'DERIVADO','SNIS 2024: índice de perdas oficial de 36.8% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,7,3,9,'2024-12-01',200824.8635,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 2.385 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,7,4,4,'2024-12-01',129495.1400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2024 (129,495 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2024-12-01',21677.1840,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 0.96 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,7,6,5,'2024-12-01',91.0442,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 0.42% recuperado (oficial) x coleta do mês'),
  (7,7,7,7,'2024-12-01',3609520.7896,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2024). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2024-12-01',74679.0000,'DERIVADO','SEEG Municípios 2024: 881,694 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-01-01',6848157.6721,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-01-01',10835692.5192,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-01-01',200999.2092,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE jan/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-01-01',132120.9000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2025 (132,121 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-01-01',21868.5981,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-01-01',91.8481,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-01-01',3578367.5359,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-01-01',74823.8082,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-02-01',6116560.2927,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-02-01',9678101.7289,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-02-01',205571.9636,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE fev/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-02-01',135605.7400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2025 (135,606 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-02-01',19384.4195,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-02-01',81.4146,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-02-01',3788557.8171,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-02-01',67582.7945,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-03-01',6672762.2013,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-03-01',10558168.0400,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-03-01',211325.3402,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE mar/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-03-01',138471.9700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2025 (138,472 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-03-01',21506.9758,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-03-01',90.3293,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-03-01',3983052.0206,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-03-01',74823.8082,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-04-01',6221200.4113,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-04-01',9843671.5369,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-04-01',204249.0852,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE abr/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-04-01',141210.9200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2025 (141,211 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-04-01',21228.5613,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-04-01',89.1600,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-04-01',3889487.9420,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-04-01',72410.1370,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-05-01',6205830.3693,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-05-01',9819351.8501,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-05-01',196328.1499,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE mai/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-05-01',144079.1200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2025 (144,079 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-05-01',22076.5884,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-05-01',92.7217,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-05-01',4144251.8737,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-05-01',74823.8082,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-06-01',5891353.5256,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-06-01',9321761.9077,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-06-01',189334.8523,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE jun/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-06-01',146481.9100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2025 (146,482 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-06-01',21052.7327,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-06-01',88.4215,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-06-01',3770012.1500,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-06-01',72410.1370,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,7,2,1,'2025-07-01',6105147.1426,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-07-01',9660042.9472,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-07-01',185906.4917,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE jul/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-07-01',149168.5100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2025 (149,169 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-07-01',21708.2811,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-07-01',91.1748,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-07-01',3841232.9058,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-07-01',74823.8082,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-08-01',6230264.1454,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-08-01',9858012.8883,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-08-01',191984.2281,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE ago/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-08-01',151357.7000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2025 (151,358 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-08-01',21766.3614,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-08-01',91.4187,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-08-01',4015106.2255,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-08-01',74823.8082,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-09-01',6177149.7653,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-09-01',9773971.1475,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-09-01',194641.5726,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE set/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-09-01',153664.9000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2025 (153,665 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-09-01',21127.0672,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-09-01',88.7337,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-09-01',4001710.8144,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-09-01',72410.1370,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-10-01',6581148.1375,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-10-01',10413209.0784,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-10-01',199702.0541,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE out/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-10-01',155815.0300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2025 (155,815 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-10-01',22064.5400,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-10-01',92.6711,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-10-01',4201920.2176,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-10-01',74823.8082,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-11-01',6385098.7620,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-11-01',10103004.3702,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-11-01',201195.4700,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE nov/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-11-01',157779.9500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2025 (157,780 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-11-01',20843.8163,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-11-01',87.5440,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-11-01',3788468.7306,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-11-01',72410.1370,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2025-12-01',6843447.8762,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,7,1,2,'2025-12-01',10828240.3104,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,7,3,3,'2025-12-01',201423.5123,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE dez/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,7,4,4,'2025-12-01',159832.8900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2025 (159,833 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2025-12-01',21728.9688,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2025'),
  (5,7,6,5,'2025-12-01',91.2617,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2025-12-01',3518863.7035,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2025). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2025-12-01',74823.8082,'DERIVADO','SEEG Municípios 2025: 880,990 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,7,2,1,'2026-01-01',6816161.9462,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,7,1,2,'2026-01-01',10785066.3705,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,7,3,3,'2026-01-01',205750.1329,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE jan/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,7,4,4,'2026-01-01',161478.6500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2026 (161,479 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2026-01-01',21872.9717,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2026'),
  (5,7,6,5,'2026-01-01',91.8665,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2026-01-01',3431659.7050,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2026). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2026-01-01',74666.1583,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,7,2,1,'2026-02-01',6132097.0573,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,7,1,2,'2026-02-01',9702685.2172,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,7,3,3,'2026-02-01',200874.8411,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE fev/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,7,4,4,'2026-02-01',163214.7800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2026 (163,215 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2026-02-01',19493.2215,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2026'),
  (5,7,6,5,'2026-02-01',81.8715,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2026-02-01',3414697.6737,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2026). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2026-02-01',67747.8821,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,7,2,1,'2026-03-01',6696693.9218,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,7,1,2,'2026-03-01',10596034.6865,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,7,3,3,'2026-03-01',200730.9250,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE mar/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,7,4,4,'2026-03-01',166152.2100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2026 (166,152 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2026-03-01',22181.1514,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2026'),
  (5,7,6,5,'2026-03-01',93.1608,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2026-03-01',4085487.5370,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2026). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2026-03-01',74526.2597,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,7,2,1,'2026-04-01',6240001.3472,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,7,1,2,'2026-04-01',9873419.8532,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,7,3,3,'2026-04-01',211640.1188,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE abr/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,7,4,4,'2026-04-01',168603.5800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2026 (168,604 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2026-04-01',21345.3413,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2026'),
  (5,7,6,5,'2026-04-01',89.6504,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2026-04-01',3847290.5877,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2026). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2026-04-01',73176.4665,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,7,2,1,'2026-05-01',6178925.5344,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,7,1,2,'2026-05-01',9776780.9088,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,7,3,3,'2026-05-01',202218.5962,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE mai/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,7,4,4,'2026-05-01',170519.8900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2026 (170,520 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2026-05-01',22129.7157,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2026'),
  (5,7,6,5,'2026-05-01',92.9448,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2026-05-01',3884039.0331,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2026). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2026-05-01',75531.5315,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,7,2,1,'2026-06-01',5922792.1267,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,7,1,2,'2026-06-01',9371506.5296,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,7,3,3,'2026-06-01',191946.9992,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE jun/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,7,4,4,'2026-06-01',172740.6500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2026 (172,741 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2026-06-01',21408.1646,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2026'),
  (5,7,6,5,'2026-06-01',89.9143,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2026-06-01',3733920.9480,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2026). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2026-06-01',72156.8514,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,7,2,1,'2026-07-01',6135503.1688,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,7,1,2,'2026-07-01',9708074.6341,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,7,3,3,'2026-07-01',192115.8548,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE jul/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,7,4,4,'2026-07-01',173787.1900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2026 (173,787 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2026-07-01',21986.9862,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2026'),
  (5,7,6,5,'2026-07-01',92.3453,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2026-07-01',3702379.7076,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2026). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2026-07-01',75138.9018,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,7,2,1,'2026-08-01',6263464.1571,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,7,1,2,'2026-08-01',9910544.5523,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,7,3,3,'2026-08-01',197958.8311,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE ago/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,7,4,4,'2026-08-01',174930.5300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2026 (174,931 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2026-08-01',22123.5616,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2026'),
  (5,7,6,5,'2026-08-01',92.9190,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2026-08-01',3981680.7450,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2026). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2026-08-01',75301.0941,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,7,2,1,'2026-09-01',6254515.5533,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (285 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,7,1,2,'2026-09-01',9896385.3692,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 36.8%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,7,3,3,'2026-09-01',198686.6197,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 2.385 TWh) x variação oficial do Estado (EPE ainda não publicou set/2026; usado set/2025 x crescimento recente). O Anuário de 2026 ainda não foi publicado'),
  (4,7,4,4,'2026-09-01',175993.5300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2026 (175,994 kW). Base de 16/11/2026.'),
  (5,7,5,5,'2026-09-01',20895.1832,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 0.96 kg/hab/dia) x população IBGE 2026'),
  (5,7,6,5,'2026-09-01',87.7598,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 0.42%)'),
  (7,7,7,7,'2026-09-01',3720498.9574,'ESTIMADO','ESTIMADO: 5.4 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2026). Não há dado oficial mensal desta cidade'),
  (8,7,8,8,'2026-09-01',72440.1362,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,8,2,1,'2023-01-01',3346846.2389,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-01-01',3606515.3437,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-01-01',114971.5830,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE jan/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-01-01',7919.5900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2023 (7,920 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-01-01',17220.7517,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-01-01',1387.9926,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-01-01',3179710.6374,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-01-01',40612.7178,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2023-02-01',2994439.4226,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-02-01',3226766.6191,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-02-01',117592.5623,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE fev/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-02-01',8141.6400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2023 (8,142 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-02-01',15554.2274,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-02-01',1253.6707,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-02-01',3159592.3563,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-02-01',36682.4548,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2023-03-01',3283698.1967,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-03-01',3538467.8844,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-03-01',120694.3421,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE mar/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-03-01',8488.6700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2023 (8,489 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-03-01',17220.7517,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-03-01',1387.9926,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-03-01',3891889.1801,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-03-01',40612.7178,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2023-04-01',3055550.4312,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-04-01',3292618.9991,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-04-01',123491.3931,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE abr/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-04-01',8585.6700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2023 (8,586 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-04-01',16665.2436,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-04-01',1343.2186,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-04-01',3342211.9499,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-04-01',39302.6301,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2023-05-01',3031106.0277,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-05-01',3266278.0471,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-05-01',114340.7920,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE mai/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-05-01',8849.4700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2023 (8,849 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-05-01',17220.7517,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-05-01',1387.9926,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-05-01',3837590.1073,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-05-01',40612.7178,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2023-06-01',2872217.4053,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-06-01',3095061.8592,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-06-01',116260.8133,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE jun/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-06-01',8956.4500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2023 (8,956 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-06-01',16665.2436,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-06-01',1343.2186,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-06-01',3473818.9603,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-06-01',39302.6301,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2023-07-01',2967957.9855,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-07-01',3198230.5878,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-07-01',113463.9449,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE jul/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-07-01',9084.8000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2023 (9,085 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-07-01',17220.7517,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-07-01',1387.9926,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-07-01',3318463.5469,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-07-01',40612.7178,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2023-08-01',3031106.0277,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-08-01',3266278.0471,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-08-01',116655.9519,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE ago/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-08-01',9283.7700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2023 (9,284 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-08-01',17220.7517,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-08-01',1387.9926,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-08-01',3742638.7464,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-08-01',40612.7178,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2023-09-01',3024994.9269,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-09-01',3259692.8091,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-09-01',121742.3961,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE set/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-09-01',9413.2200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2023 (9,413 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-09-01',16665.2436,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-09-01',1343.2186,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-09-01',3452736.6436,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-09-01',39302.6301,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,8,2,1,'2023-10-01',3220550.1545,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-10-01',3470420.4251,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-10-01',124885.2106,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE out/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-10-01',9481.9600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2023 (9,482 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-10-01',17220.7517,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-10-01',1387.9926,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-10-01',3592046.0731,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-10-01',40612.7178,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2023-11-01',3147216.9441,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-11-01',3391397.5691,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-11-01',127960.5466,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE nov/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-11-01',10244.5600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2023 (10,245 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-11-01',16665.2436,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-11-01',1343.2186,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-11-01',3536026.4959,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-11-01',39302.6301,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2023-12-01',3346846.2389,'DERIVADO','SNIS 2023: consumo anual oficial de 37.32 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2023-12-01',3606515.3437,'DERIVADO','SNIS 2023: índice de perdas oficial de 7.2% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (3,8,3,3,'2023-12-01',130862.6005,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE dez/2023). O Anuário de 2023 ainda não foi publicado'),
  (4,8,4,4,'2023-12-01',10362.7100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2023 (10,363 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2023-12-01',17220.7517,'DERIVADO','SINISA (ano-base 2023): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2023-12-01',1387.9926,'DERIVADO','SINISA (ano-base 2023): IRS3010 = 8.06% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2023-12-01',3738267.4285,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2023). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2023-12-01',40612.7178,'DERIVADO','SEEG Municípios 2023: 478,182 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-01-01',3288818.4364,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-01-01',3476552.2584,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-01-01',126708.7638,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-01-01',10492.5800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2024 (10,493 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-01-01',17444.7159,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-01-01',1482.8008,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-01-01',3229365.5618,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-01-01',39398.4590,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-02-01',3047611.7282,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-02-01',3221576.8797,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-02-01',127092.1959,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-02-01',10604.7800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2024 (10,605 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-02-01',16319.2503,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-02-01',1387.1363,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-02-01',3346873.7577,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-02-01',36856.6230,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-03-01',3226765.2584,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-03-01',3410956.9327,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-03-01',130585.3956,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-03-01',10823.9600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2024 (10,824 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-03-01',17444.7159,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-03-01',1482.8008,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-03-01',3591242.9414,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-03-01',39398.4590,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-04-01',3002573.1312,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-04-01',3173967.3692,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-04-01',128444.7068,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-04-01',10992.4600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2024 (10,992 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-04-01',16881.9831,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-04-01',1434.9686,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-04-01',3888312.4144,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-04-01',38127.5410,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-05-01',2978552.5462,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-05-01',3148575.6302,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-05-01',130666.0175,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-05-01',11358.4000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2024 (11,358 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-05-01',17444.7159,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-05-01',1482.8008,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-05-01',3681120.8087,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-05-01',39398.4590,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-06-01',2822418.7434,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-06-01',2983529.3270,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-06-01',124616.3683,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-06-01',11512.0200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2024 (11,512 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-06-01',16881.9831,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-06-01',1434.9686,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-06-01',3730123.6526,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-06-01',38127.5410,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-07-01',2916499.3681,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-07-01',3082980.3046,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-07-01',118805.1381,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-07-01',11769.5100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2024 (11,770 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-07-01',17444.7159,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-07-01',1482.8008,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-07-01',3487565.7843,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-07-01',39398.4590,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-08-01',2978552.5462,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-08-01',3148575.6302,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-08-01',122882.3480,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-08-01',11886.9200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2024 (11,887 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-08-01',17444.7159,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-08-01',1482.8008,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-08-01',3887372.5133,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-08-01',39398.4590,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-09-01',2972547.3999,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-09-01',3142227.6955,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-09-01',125669.2496,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-09-01',12085.4200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2024 (12,085 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-09-01',16881.9831,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-09-01',1434.9686,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-09-01',3857819.8693,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-09-01',38127.5410,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,8,2,1,'2024-10-01',3164712.0803,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-10-01',3345361.6071,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-10-01',130673.5857,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-10-01',12444.0400,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2024 (12,444 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-10-01',17444.7159,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-10-01',1482.8008,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-10-01',4077410.1217,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-10-01',39398.4590,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-11-01',3092650.3252,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-11-01',3269186.3903,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-11-01',128733.6795,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-11-01',12663.6900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2024 (12,664 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-11-01',16881.9831,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-11-01',1434.9686,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-11-01',3705064.9933,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-11-01',38127.5410,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2024-12-01',3288818.4364,'DERIVADO','SNIS 2024: consumo anual oficial de 36.78 milhões de m³ distribuído pelos meses (perfil sazonal). SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (2,8,1,2,'2024-12-01',3476552.2584,'DERIVADO','SNIS 2024: índice de perdas oficial de 5.4% aplicado ao consumo do mês. SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)'),
  (9,8,3,9,'2024-12-01',128279.9243,'DERIVADO','Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de 1.523 TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)'),
  (4,8,4,4,'2024-12-01',12830.1200,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2024 (12,830 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2024-12-01',17444.7159,'DERIVADO','SINISA (ano-base 2024): IRS1004 = 1.31 kg/hab/dia (oficial) x população IBGE x dias do mês'),
  (5,8,6,5,'2024-12-01',1482.8008,'DERIVADO','SINISA (ano-base 2024): IRS3010 = 8.5% recuperado (oficial) x coleta do mês'),
  (7,8,7,7,'2024-12-01',3344069.4409,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2024). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2024-12-01',39398.4590,'DERIVADO','SEEG Municípios 2024: 465,156 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-01-01',3296322.5547,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-01-01',3484484.7301,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-01-01',128707.1159,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE jan/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-01-01',12963.3800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2025 (12,963 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-01-01',17541.6128,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-01-01',1491.0371,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-01-01',3290241.6008,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-01-01',52714.2685,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-02-01',2950208.9151,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-02-01',3118614.0751,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-02-01',130930.5369,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE fev/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-02-01',13102.8900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2025 (13,103 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-02-01',15520.1596,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-02-01',1319.2136,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-02-01',3465138.4133,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-02-01',47612.8877,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-03-01',3259568.1592,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-03-01',3445632.3036,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-03-01',135412.8622,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE mar/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-03-01',13279.3000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2025 (13,279 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-03-01',17401.3210,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-03-01',1479.1123,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-03-01',3683261.4568,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-03-01',52714.2685,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-04-01',3011252.2171,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-04-01',3183141.8785,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-04-01',129826.7715,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE abr/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-04-01',13477.3700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2025 (13,477 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-04-01',17004.0496,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-04-01',1445.3442,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-04-01',3632157.0565,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-04-01',51013.8082,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-05-01',2993755.3532,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-05-01',3164646.2508,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-05-01',125526.6473,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE mai/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-05-01',13679.8900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2025 (13,680 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-05-01',17379.6614,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-05-01',1477.2712,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-05-01',3779707.1840,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-05-01',52714.2685,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-06-01',2821132.8897,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-06-01',2982170.0737,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-06-01',121297.5208,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE jun/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-06-01',13969.4300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2025 (13,969 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-06-01',16972.4322,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-06-01',1442.6567,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-06-01',3501104.1779,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-06-01',51013.8082,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-07-01',2915317.4647,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-07-01',3081730.9352,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-07-01',118599.5737,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE jul/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-07-01',14146.5700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2025 (14,147 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-07-01',17691.1388,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-07-01',1503.7468,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-07-01',3537671.9661,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-07-01',52714.2685,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-08-01',2997862.9027,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-08-01',3168988.2693,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-08-01',122922.9970,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE ago/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-08-01',14428.6300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2025 (14,429 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-08-01',17490.9541,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-08-01',1486.7311,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-08-01',3684381.9633,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-08-01',52714.2685,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-09-01',2979191.6892,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-09-01',3149251.2571,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-09-01',124502.0375,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE set/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-09-01',14614.8500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2025 (14,615 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-09-01',16935.5393,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-09-01',1439.5208,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-09-01',3691659.0434,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-09-01',51013.8082,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês');
INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES
  (1,8,2,1,'2025-10-01',3181466.8005,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-10-01',3363072.7278,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-10-01',127661.8655,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE out/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-10-01',14853.0100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de out/2025 (14,853 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-10-01',17248.7975,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-10-01',1466.1478,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-10-01',3900943.2032,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans out/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-10-01',52714.2685,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-11-01',3091605.7947,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-11-01',3268082.2354,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-11-01',128457.3053,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE nov/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-11-01',15089.7900,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de nov/2025 (15,090 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-11-01',16755.6279,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-11-01',1424.2284,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-11-01',3515393.1938,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans nov/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-11-01',51013.8082,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2025-12-01',3286884.8166,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2025 x perfil sazonal. O SNIS/SINISA de 2025 ainda não foi publicado'),
  (2,8,1,2,'2025-12-01',3474508.2628,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2025 ainda não foi publicado'),
  (3,8,3,3,'2025-12-01',128541.9329,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE dez/2025). O Anuário de 2025 ainda não foi publicado'),
  (4,8,4,4,'2025-12-01',15366.7000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de dez/2025 (15,367 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2025-12-01',17513.7789,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2025'),
  (5,8,6,5,'2025-12-01',1488.6712,'ESTIMADO','ESTIMADO: o SINISA de 2025 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2025-12-01',3204659.6302,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans dez/2025). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2025-12-01',52714.2685,'DERIVADO','SEEG Municípios 2025: 620,668 t CO2e no ano (oficial) dividido pelos dias do mês'),
  (1,8,2,1,'2026-01-01',3302133.4536,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,8,1,2,'2026-01-01',3490627.3293,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,8,3,3,'2026-01-01',130894.4558,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE jan/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,8,4,4,'2026-01-01',15556.0800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jan/2026 (15,556 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2026-01-01',17616.8380,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2026'),
  (5,8,6,5,'2026-01-01',1497.4312,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2026-01-01',3126799.2034,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jan/2026). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2026-01-01',52347.8083,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,8,2,1,'2026-02-01',2944896.6329,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,8,1,2,'2026-02-01',3112998.5549,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,8,3,3,'2026-02-01',128370.3985,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE fev/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,8,4,4,'2026-02-01',15779.9800,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de fev/2026 (15,780 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2026-02-01',15882.3841,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2026'),
  (5,8,6,5,'2026-02-01',1350.0027,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2026-02-01',3178374.6427,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans fev/2026). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2026-02-01',47862.8113,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,8,2,1,'2026-03-01',3222418.0278,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,8,1,2,'2026-03-01',3406361.5516,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,8,3,3,'2026-03-01',128872.2802,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE mar/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,8,4,4,'2026-03-01',15971.7500,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mar/2026 (15,972 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2026-03-01',17396.2667,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2026'),
  (5,8,6,5,'2026-03-01',1478.6827,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2026-03-01',3752632.8077,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mar/2026). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2026-03-01',52554.3489,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,8,2,1,'2026-04-01',2994541.4239,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,8,1,2,'2026-04-01',3165477.1923,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,8,3,3,'2026-04-01',135567.2907,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE abr/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,8,4,4,'2026-04-01',16164.7700,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de abr/2026 (16,165 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2026-04-01',16642.7579,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2026'),
  (5,8,6,5,'2026-04-01',1414.6344,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2026-04-01',3519212.6474,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans abr/2026). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2026-04-01',51174.0171,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,8,2,1,'2026-05-01',2996599.0919,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,8,1,2,'2026-05-01',3167652.3171,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,8,3,3,'2026-05-01',129783.8989,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE mai/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,8,4,4,'2026-05-01',16326.6100,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de mai/2026 (16,327 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2026-05-01',17392.5667,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2026'),
  (5,8,6,5,'2026-05-01',1478.3682,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2026-05-01',3621754.4500,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans mai/2026). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2026-05-01',52850.8362,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,8,2,1,'2026-06-01',2814765.9412,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,8,1,2,'2026-06-01',2975439.6841,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,8,3,3,'2026-06-01',122157.2591,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE jun/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,8,4,4,'2026-06-01',16623.3300,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jun/2026 (16,623 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2026-06-01',16822.2950,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2026'),
  (5,8,6,5,'2026-06-01',1429.8951,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2026-06-01',3440465.4622,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jun/2026). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2026-06-01',51129.5227,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,8,2,1,'2026-07-01',2919293.1507,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,8,1,2,'2026-07-01',3085933.5631,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,8,3,3,'2026-07-01',122362.4793,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE jul/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,8,4,4,'2026-07-01',16737.1000,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de jul/2026 (16,737 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2026-07-01',17339.9802,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2026'),
  (5,8,6,5,'2026-07-01',1473.8983,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2026-07-01',3387701.3223,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans jul/2026). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2026-07-01',53108.9882,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,8,2,1,'2026-08-01',2995692.9318,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,8,1,2,'2026-08-01',3166694.4311,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,8,3,3,'2026-08-01',125835.0471,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE ago/2026). O Anuário de 2026 ainda não foi publicado'),
  (4,8,4,4,'2026-08-01',16893.5600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de ago/2026 (16,894 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2026-08-01',17664.0589,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2026'),
  (5,8,6,5,'2026-08-01',1501.4450,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2026-08-01',3612317.9693,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans ago/2026). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2026-08-01',52719.2495,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado'),
  (1,8,2,1,'2026-09-01',2958363.1562,'ESTIMADO','ESTIMADO: último dado oficial é o SNIS 2024 (234 L por pessoa por dia) x população IBGE 2026 x perfil sazonal. O SNIS/SINISA de 2026 ainda não foi publicado'),
  (2,8,1,2,'2026-09-01',3127233.7803,'ESTIMADO','ESTIMADO: mantido o último índice de perdas oficial (SNIS 2024: 5.4%). O SNIS/SINISA de 2026 ainda não foi publicado'),
  (3,8,3,3,'2026-09-01',127499.1795,'ESTIMADO','ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: 1.523 TWh) x variação oficial do Estado (EPE ainda não publicou set/2026; usado set/2025 x crescimento recente). O Anuário de 2026 ainda não foi publicado'),
  (4,8,4,4,'2026-09-01',16893.5600,'REAL','ANEEL - geração distribuída: potência acumulada até o fim de set/2026 (16,894 kW). Base de 16/11/2026.'),
  (5,8,5,5,'2026-09-01',16726.1919,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usado o último oficial (SINISA 2024: 1.31 kg/hab/dia) x população IBGE 2026'),
  (5,8,6,5,'2026-09-01',1421.7263,'ESTIMADO','ESTIMADO: o SINISA de 2026 ainda não foi publicado; usada a última taxa oficial de reciclagem (SINISA 2024: 8.5%)'),
  (7,8,7,7,'2026-09-01',3391635.4003,'ESTIMADO','ESTIMADO: 8.5 viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans set/2026). Não há dado oficial mensal desta cidade'),
  (8,8,8,8,'2026-09-01',50954.8346,'ESTIMADO','ESTIMADO: emissão por pessoa do último ano oficial (SEEG 2025) x população IBGE 2026. O SEEG de 2026 ainda não foi publicado');

-- Atualiza a contagem de registros de cada lote
UPDATE lote_carga l SET registros_lidos = (SELECT COUNT(*) FROM dado d WHERE d.id_lote = l.id_lote),
                        registros_validos = registros_lidos WHERE l.id_lote <= 10;

-- Insights históricos (ILUSTRATIVOS) que motivaram ações
INSERT INTO analise_ia (id_indicador, id_municipio, tipo, titulo, descricao, confianca, severidade, modelo_versao, gerada_em, status, revisada_por) VALUES
  (2, 3, 'ANOMALIA', 'Perdas de água muito altas em Guarulhos', 'As perdas na distribuição seguem bem acima da meta de 25% (dado oficial do SNIS). (insight histórico ilustrativo)', 86.00, 'CRITICO', 'ecocity-ia-v0.2', '2023-03-10 08:00:00', 'VALIDADA', 4),
  (6, 6, 'TENDENCIA', 'Reciclagem abaixo da meta em Sorocaba', 'A taxa de reciclagem está bem abaixo da meta de 10%, enquanto Santos se aproxima dela. (insight ilustrativo)', 80.00, 'ATENCAO', 'ecocity-ia-v0.2', '2023-03-12 08:00:00', 'VALIDADA', 6),
  (4, 3, 'CORRELACAO', 'Pouca geração solar em Guarulhos', 'Guarulhos tem uma das menores potências de geração distribuída por habitante (ANEEL). (insight histórico ilustrativo)', 72.00, 'ATENCAO', 'ecocity-ia-v0.2', '2023-03-20 08:00:00', 'VALIDADA', 5);

-- Processa os 24 meses: indicadores + carga do Data Warehouse
CALL sp_pipeline_mensal('2023-01-01');
CALL sp_pipeline_mensal('2023-02-01');
CALL sp_pipeline_mensal('2023-03-01');
CALL sp_pipeline_mensal('2023-04-01');
CALL sp_pipeline_mensal('2023-05-01');
CALL sp_pipeline_mensal('2023-06-01');
CALL sp_pipeline_mensal('2023-07-01');
CALL sp_pipeline_mensal('2023-08-01');
CALL sp_pipeline_mensal('2023-09-01');
CALL sp_pipeline_mensal('2023-10-01');
CALL sp_pipeline_mensal('2023-11-01');
CALL sp_pipeline_mensal('2023-12-01');
CALL sp_pipeline_mensal('2024-01-01');
CALL sp_pipeline_mensal('2024-02-01');
CALL sp_pipeline_mensal('2024-03-01');
CALL sp_pipeline_mensal('2024-04-01');
CALL sp_pipeline_mensal('2024-05-01');
CALL sp_pipeline_mensal('2024-06-01');
CALL sp_pipeline_mensal('2024-07-01');
CALL sp_pipeline_mensal('2024-08-01');
CALL sp_pipeline_mensal('2024-09-01');
CALL sp_pipeline_mensal('2024-10-01');
CALL sp_pipeline_mensal('2024-11-01');
CALL sp_pipeline_mensal('2024-12-01');
CALL sp_pipeline_mensal('2025-01-01');
CALL sp_pipeline_mensal('2025-02-01');
CALL sp_pipeline_mensal('2025-03-01');
CALL sp_pipeline_mensal('2025-04-01');
CALL sp_pipeline_mensal('2025-05-01');
CALL sp_pipeline_mensal('2025-06-01');
CALL sp_pipeline_mensal('2025-07-01');
CALL sp_pipeline_mensal('2025-08-01');
CALL sp_pipeline_mensal('2025-09-01');
CALL sp_pipeline_mensal('2025-10-01');
CALL sp_pipeline_mensal('2025-11-01');
CALL sp_pipeline_mensal('2025-12-01');
CALL sp_pipeline_mensal('2026-01-01');
CALL sp_pipeline_mensal('2026-02-01');
CALL sp_pipeline_mensal('2026-03-01');
CALL sp_pipeline_mensal('2026-04-01');
CALL sp_pipeline_mensal('2026-05-01');
CALL sp_pipeline_mensal('2026-06-01');
CALL sp_pipeline_mensal('2026-07-01');
CALL sp_pipeline_mensal('2026-08-01');
CALL sp_pipeline_mensal('2026-09-01');

-- Ações ILUSTRATIVAS (criadas para demonstrar o sistema)
INSERT INTO acao (titulo, descricao, id_municipio, id_indicador_alvo, id_responsavel, id_analise, data_inicio, data_fim_prevista, orcamento, status) VALUES
  ('Programa de redução de perdas de água','Setorização da rede, troca de tubulações antigas e combate a fraudes. (ação ilustrativa)',3,2,2,1,'2023-05-01','2025-12-31',18500000,'EM_EXECUCAO'),
  ('Ampliação da coleta seletiva com cooperativas','Coleta seletiva porta a porta e novos ecopontos. (ação ilustrativa)',6,6,2,2,'2023-05-01','2025-12-31',4200000,'EM_EXECUCAO'),
  ('Energia solar em prédios públicos','Usinas fotovoltaicas em escolas e unidades de saúde. (ação ilustrativa)',3,4,2,3,'2023-06-01','2024-12-31',6800000,'EM_EXECUCAO'),
  ('Campanha de uso consciente da água','Campanha educativa em escolas e redes sociais. (ação ilustrativa)',7,1,2,NULL,'2024-02-01','2025-03-31',350000,'EM_EXECUCAO'),
  ('Ônibus elétricos e faixas exclusivas','Substituição gradual da frota a diesel por ônibus elétricos. (ação ilustrativa)',1,7,3,NULL,'2024-02-01','2027-12-31',95000000,'EM_EXECUCAO'),
  ('Ecopontos e compostagem de orgânicos','Rede de ecopontos e compostagem de resíduos de feiras. (ação ilustrativa)',8,5,2,NULL,'2024-06-01','2025-12-31',2600000,'EM_EXECUCAO'),
  ('Plano de redução de perdas','Diagnóstico e plano de redução de perdas na rede de distribuição. (ação ilustrativa)',7,2,2,NULL,'2027-01-01','2028-12-31',22000000,'PLANEJADA');

-- Fechamento das ações: a procedure mede ANTES (mês anterior ao início) x DEPOIS (último mês) numa transação
CALL sp_registrar_resultado(1, '2024-12-31', 'Perdas comparadas entre abr/2023 e dez/2024, ambas calculadas do índice OFICIAL do SNIS. A ação é ilustrativa.', 2);
CALL sp_registrar_resultado(2, '2024-12-31', 'Taxa de reciclagem abr/2023 x dez/2024, ambas do SINISA (oficial). A ação é ilustrativa.', 2);
CALL sp_registrar_resultado(3, '2024-12-31', 'Antes e depois vêm da ANEEL (potência por habitante). A ação é ilustrativa.', 2);
CALL sp_registrar_resultado(5, '2024-12-31', 'Passageiros de ônibus de São Paulo: dados da SPTrans (jan/2024 x dez/2024). A ação é ilustrativa.', 3);

-- =================== ANÁLISES DOS ANALISTAS (ILUSTRATIVAS) ===================
-- Criadas como rascunho, enviadas pela procedure (que calcula a confiança) e revisadas por outra pessoa
INSERT INTO analise_publicada (titulo, resumo, conteudo, id_servico, periodo_inicio, periodo_fim, id_autor, criada_em) VALUES ('Perdas de água em Guarulhos caem, mas seguem acima da meta','O índice oficial de perdas do SNIS caiu entre 2023 e 2024, mas Guarulhos continua acima da meta de 25%.','Segundo o SNIS, o índice de perdas na distribuição de Guarulhos caiu entre 2023 e 2024. Mesmo assim, a cidade segue acima da meta de 25%. Todos os meses do período são calculados a partir do índice anual oficial, por isso a análise compara anos e não meses. Recomenda-se manter a setorização da rede e a troca de hidrômetros e refazer esta análise quando o SINISA publicar o ano-base 2025.',1,'2023-01-01','2024-12-01',4,'2026-10-01 09:00:00');
INSERT INTO analise_municipio (id_analise_pub, id_municipio) VALUES (1,3);
INSERT INTO analise_evidencia (id_analise_pub, tipo, id_indicador, id_municipio, consulta_sql, url, descricao) VALUES (1,'INDICADOR',2,3,NULL,NULL,'Série mensal de perdas (AGU-02) de Guarulhos'),
  (1,'FONTE_EXTERNA',NULL,NULL,NULL,'https://www.painelsaneamento.org.br','Painel Saneamento Brasil — índice de perdas 2023 e 2024'),
  (1,'CONSULTA_SQL',NULL,NULL,'SELECT ano_mes, valor FROM vw_indicador_desempenho WHERE codigo = ''AGU-02'' AND municipio = ''Guarulhos''',NULL,'Consulta que reproduz a série');
CALL sp_enviar_analise(1, 4);
CALL sp_revisar_analise(1, 2, 'PUBLICADA', 'Bem fundamentada em dado oficial; a ressalva de que o dado é anual está correta.');
INSERT INTO analise_publicada (titulo, resumo, conteudo, id_servico, periodo_inicio, periodo_fim, id_autor, criada_em) VALUES ('Energia solar cresce todo mês em Ribeirão Preto e Campinas','Dados oficiais mensais da ANEEL mostram crescimento contínuo: Ribeirão Preto passou da meta de 100 W por habitante e Campinas chegou perto dela.','Ao longo de 2024, a potência de micro e minigeração distribuída por habitante subiu todos os meses em Ribeirão Preto e em Campinas. Ribeirão Preto terminou o ano bem acima da meta de 100 W por habitante e Campinas passou de cerca de 70 para 92 W. Todos os valores do período são dados oficiais da ANEEL, por mês de cadastro. As duas cidades servem de referência para Guarulhos e Santos, que estão bem abaixo da meta.',2,'2024-01-01','2024-12-01',5,'2026-10-02 09:00:00');
INSERT INTO analise_municipio (id_analise_pub, id_municipio) VALUES (2,7),(2,2);
INSERT INTO analise_evidencia (id_analise_pub, tipo, id_indicador, id_municipio, consulta_sql, url, descricao) VALUES (2,'INDICADOR',4,7,NULL,NULL,'ENE-02 de Ribeirão Preto'),
  (2,'INDICADOR',4,2,NULL,NULL,'ENE-02 de Campinas'),
  (2,'FONTE_EXTERNA',NULL,NULL,NULL,'https://dadosabertos.aneel.gov.br/dataset/relacao-de-empreendimentos-de-geracao-distribuida','Base da ANEEL de 10/10/2026');
CALL sp_enviar_analise(2, 5);
CALL sp_revisar_analise(2, 4, 'PUBLICADA', 'Análise bem fundamentada em dados oficiais mês a mês.');
INSERT INTO analise_publicada (titulo, resumo, conteudo, id_servico, periodo_inicio, periodo_fim, id_autor, criada_em) VALUES ('Viagens de ônibus por habitante em São Paulo em 2024','Os dados diários da SPTrans mostram como as viagens de ônibus por habitante variam ao longo do ano.','Somando os dados diários oficiais da SPTrans por mês, as viagens de ônibus por habitante em São Paulo caem nas férias (janeiro e julho) e sobem nos meses de aula. A cidade segue abaixo da meta de 15 viagens por habitante por mês. Sugere-se cruzar com dados do metrô antes de concluir que houve migração para o transporte individual.',4,'2024-01-01','2024-12-01',4,'2026-10-03 09:00:00');
INSERT INTO analise_municipio (id_analise_pub, id_municipio) VALUES (3,1);
INSERT INTO analise_evidencia (id_analise_pub, tipo, id_indicador, id_municipio, consulta_sql, url, descricao) VALUES (3,'INDICADOR',7,1,NULL,NULL,'MOB-01 de São Paulo'),
  (3,'FONTE_EXTERNA',NULL,NULL,NULL,'https://www.sptrans.com.br','Relatório diário ''Situação dos ônibus'' da SPTrans');
CALL sp_enviar_analise(3, 4);
INSERT INTO analise_publicada (titulo, resumo, conteudo, id_servico, periodo_inicio, periodo_fim, id_autor, criada_em) VALUES ('Campinas economizou energia elétrica?','O consumo de energia por habitante em Campinas variou entre 2023 e 2024.','O consumo de energia elétrica por habitante de Campinas variou entre 2023 e 2024. Isso indicaria resultado das ações de eficiência energética da cidade. Recomenda-se ampliar a troca de iluminação pública por LED e divulgar o resultado para a população como exemplo de economia de energia no município.',2,'2023-01-01','2024-12-01',5,'2026-10-04 09:00:00');
INSERT INTO analise_municipio (id_analise_pub, id_municipio) VALUES (4,2);
INSERT INTO analise_evidencia (id_analise_pub, tipo, id_indicador, id_municipio, consulta_sql, url, descricao) VALUES (4,'INDICADOR',3,2,NULL,NULL,'ENE-01 de Campinas');
CALL sp_enviar_analise(4, 5);
CALL sp_revisar_analise(4, 2, 'DEVOLVIDA', 'O consumo municipal é ESTIMADO a partir da série estadual da EPE; a variação reflete o Estado, não Campinas. Reescreva deixando essa limitação clara.');
INSERT INTO analise_publicada (titulo, resumo, conteudo, id_servico, periodo_inicio, periodo_fim, id_autor, criada_em) VALUES ('Reciclagem em Sorocaba segue abaixo de 2%','Rascunho: a taxa de reciclagem de Sorocaba continua muito abaixo da meta.','Rascunho em elaboração. A taxa de recuperação de recicláveis de Sorocaba ficou abaixo de 2% em 2023 e 2024 (SINISA, oficial), muito abaixo da meta de 10%. Falta incluir a comparação com Santos e as evidências. Esta análise ainda não pode ser enviada porque a credencial da autora está pendente de verificação pelo administrador do sistema.',3,'2023-01-01','2024-12-01',6,'2026-10-05 09:00:00');
INSERT INTO analise_municipio (id_analise_pub, id_municipio) VALUES (5,6);
INSERT INTO analise_evidencia (id_analise_pub, tipo, id_indicador, id_municipio, consulta_sql, url, descricao) VALUES (5,'INDICADOR',6,6,NULL,NULL,'RES-02 de Sorocaba');
INSERT INTO analise_comentario (id_analise_pub, id_usuario, texto) VALUES
  (1, 5, 'Boa leitura. Vale incluir Santo André, que também está acima de 30% de perdas.'),
  (1, 3, 'Vamos usar esta análise na revisão do programa de perdas. Obrigado.'),
  (2, 4, 'Concordo. Guarulhos poderia replicar o programa de painéis em escolas de Ribeirão Preto.'),
  (2, 6, 'Seria interessante cruzar com o número de sistemas instalados por bairro.');

-- =================== METAS NOVAS (fluxo completo pelas procedures) ===================
CALL sp_propor_meta(2, 'AGU-01', 7, 220, '2027-01-01', 'Ribeirão Preto consome perto de 280 L por habitante por dia; uma meta intermediária de 220 L é mais realista para 2027.', 'Plano Municipal de Saneamento (ilustrativo) e ODS 6.4');
CALL sp_propor_meta(3, 'AGU-02', 3, 22, '2027-01-01', 'Guarulhos está perto de 25% de perdas; o programa de setorização permite mirar 22% a partir de 2027.', 'Portaria MDR nº 490/2021');
CALL sp_parecer_meta(LAST_INSERT_ID(), 4, TRUE, 'A série oficial de 2023 e 2024 mostra queda; 22% em 2027 é alcançável.');
CALL sp_propor_meta(2, 'ENE-02', 5, 300, '2027-01-01', 'São José dos Campos tem ótima irradiação solar e já passa de 150 W por habitante; queremos triplicar a meta.', 'ODS 7.2');
SET @m = (SELECT MAX(id_meta) FROM meta);
CALL sp_parecer_meta(@m, 5, FALSE, 'O ritmo atual da ANEEL (cerca de 1% ao mês) leva a cidade a uns 230 W/hab em 2027; 300 W/hab não é realista. Sugiro 230.');
CALL sp_decidir_meta(@m, 3, FALSE);

-- =================== LOGIN: exemplos registrados pelo banco ===================
CALL sp_registrar_login('rafael.nunes@ecocity.local', TRUE, TRUE, TRUE, '10.0.0.15');
CALL sp_registrar_login('marina.duarte@ecocity.local', TRUE, TRUE, TRUE, '10.0.0.22');
CALL sp_registrar_login('lucia.andrade@ecocity.local', TRUE, FALSE, TRUE, '10.0.0.31');      -- código do autenticador errado
CALL sp_registrar_login('beatriz.rocha@ecocity.local', FALSE, FALSE, TRUE, '177.10.20.30');   -- senha errada
CALL sp_registrar_login('beatriz.rocha@ecocity.local', FALSE, FALSE, TRUE, '177.10.20.30');   -- senha errada
CALL sp_registrar_login('beatriz.rocha@ecocity.local', FALSE, FALSE, TRUE, '177.10.20.30');   -- senha errada
CALL sp_registrar_login('beatriz.rocha@ecocity.local', FALSE, FALSE, TRUE, '177.10.20.30');   -- senha errada
CALL sp_registrar_login('beatriz.rocha@ecocity.local', FALSE, FALSE, TRUE, '177.10.20.30');   -- senha errada
CALL sp_registrar_login('beatriz.rocha@ecocity.local', TRUE, FALSE, TRUE, '177.10.20.30');    -- bloqueada por 15 minutos
CALL sp_registrar_login('nao.existe@ecocity.local', FALSE, FALSE, TRUE, '45.90.1.2');
CALL sp_registrar_login('admin@ecocity.local', TRUE, TRUE, FALSE, '200.150.3.9');          -- senha e código certos, CHAVE do admin errada
CALL sp_registrar_login('paulo.souza@santos.sp.gov.br', TRUE, TRUE, TRUE, '189.40.12.7');   -- cadastro ainda em análise: não entra

-- Demonstração do ETL: lote com linhas inválidas (todas rejeitadas pelo banco)
INSERT INTO lote_carga (id_fonte, iniciado_em) VALUES (7, '2026-10-15 03:00:00');
SET @lote = LAST_INSERT_ID();
INSERT INTO stg_medicao_bruta (id_lote, codigo_metrica, nome_municipio, data_texto, valor_texto) VALUES
  (@lote,'TP_PASSAGEIROS','Cidade Fantasma','2024-09-01','150000'),
  (@lote,'TP_PASSAGEIROS','Santos','01/09/2024','abc'),
  (@lote,'AGUA_CONSUMIDA','Santos','2024-09-01','12000');
CALL sp_processar_staging(@lote);

-- >>>>>>>>>>>>>>>>>>>> 07b_insights_ia.sql <<<<<<<<<<<<<<<<<<<<
-- =====================================================================
--  EcoCity — Script 07b: análises geradas pelo módulo de IA (ia/analise_ia.py)
--  Saída do modelo ecocity-ia-v1.0-mensal (séries mensais jan/2023 a set/2026).
-- =====================================================================
USE ecocity;
SET NAMES utf8mb4;
INSERT INTO `analise_ia` (`id_indicador`, `id_municipio`, `tipo`, `titulo`, `descricao`, `confianca`, `severidade`, `modelo_versao`, `gerada_em`, `status`, `revisada_por`) VALUES (2,2,'TENDENCIA','Perdas na distribuição de água: tendência de melhora em Campinas','Nos 3 últimos meses a média foi 15.00 %, -9.5% em relação aos mesmos meses do ano anterior (16.58). A direção se repetiu em 100% dos meses comparáveis. Meta: 25 %. Base: 80% de dados oficiais ou calculados de dado oficial.',100.00,'INFO','ecocity-ia-v1.0-mensal','2026-11-16 15:49:46','NOVA',NULL);
INSERT INTO `analise_ia` (`id_indicador`, `id_municipio`, `tipo`, `titulo`, `descricao`, `confianca`, `severidade`, `modelo_versao`, `gerada_em`, `status`, `revisada_por`) VALUES (4,1,'TENDENCIA','Geração distribuída por habitante: tendência de melhora em São Paulo','Nos 3 últimos meses a média foi 22.14 W/hab, +40.2% em relação aos mesmos meses do ano anterior (15.80). A direção se repetiu em 100% dos meses comparáveis. Meta: 100 W/hab. Base: 100% de dados oficiais ou calculados de dado oficial.',100.00,'INFO','ecocity-ia-v1.0-mensal','2026-11-16 15:49:46','NOVA',NULL);
INSERT INTO `analise_ia` (`id_indicador`, `id_municipio`, `tipo`, `titulo`, `descricao`, `confianca`, `severidade`, `modelo_versao`, `gerada_em`, `status`, `revisada_por`) VALUES (4,2,'TENDENCIA','Geração distribuída por habitante: tendência de melhora em Campinas','Nos 3 últimos meses a média foi 120.06 W/hab, +15.3% em relação aos mesmos meses do ano anterior (104.09). A direção se repetiu em 100% dos meses comparáveis. Meta: 100 W/hab. Base: 100% de dados oficiais ou calculados de dado oficial.',100.00,'INFO','ecocity-ia-v1.0-mensal','2026-11-16 15:49:46','NOVA',NULL);
INSERT INTO `analise_ia` (`id_indicador`, `id_municipio`, `tipo`, `titulo`, `descricao`, `confianca`, `severidade`, `modelo_versao`, `gerada_em`, `status`, `revisada_por`) VALUES (6,1,'TENDENCIA','Taxa de reciclagem: tendência de melhora em São Paulo','Nos 3 últimos meses a média foi 2.62 %, +2.3% em relação aos mesmos meses do ano anterior (2.56). A direção se repetiu em 100% dos meses comparáveis. Meta: 10 %. Base: 93% de dados oficiais ou calculados de dado oficial.',100.00,'INFO','ecocity-ia-v1.0-mensal','2026-11-16 15:49:46','NOVA',NULL);

-- >>>>>>>>>>>>>>>>>>>> 07c_copiloto_exemplos.sql <<<<<<<<<<<<<<<<<<<<
-- =====================================================================
--  EcoCity — Script 07c: exemplos do Copiloto EcoCity
--  Relatórios escritos pelo Copiloto (modelo local) com os dados do banco e
--  perguntas em português (incluindo 2 BLOQUEADAS por segurança).
--  Gerado por backend/src/gerar_exemplos_copiloto.js
-- =====================================================================
USE ecocity;
SET NAMES utf8mb4;
INSERT INTO `relatorio_ia` (`id_relatorio`, `titulo`, `tipo`, `publico`, `periodo_inicio`, `periodo_fim`, `conteudo`, `dados_usados`, `pct_dados_oficiais`, `modelo`, `status`, `solicitado_por`, `revisado_por`, `comentario_revisao`, `criado_em`, `revisado_em`) VALUES (1,'Como está Campinas — out/2025 a set/2026','MUNICIPIO','CIDADAO','2025-10-01','2026-09-01','No período (out/2025 a set/2026), a nota de sustentabilidade de Campinas foi **59 de 100**, uma situação **regular**.\n\n**O que está indo bem**\n- De cada 100 litros de água tratada, **15,4 se perderam no caminho** até as casas (vazamentos e ligações irregulares). O ideal é até 25 litros.\n- Há **114 watts de energia solar** (e outras fontes próprias) instalados para cada morador. O ideal é 100 watts ou mais.\n\n**O que precisa melhorar**\n- Cada pessoa usou, em média, **195 litros de água por dia**. O ideal é até 150 litros.\n- A cidade consumiu **241 kWh de energia por morador** no mês (casas, comércio e indústria). O ideal é até 220 kWh.\n- Cada morador fez, em média, **8,8 viagens de ônibus** no mês. O ideal é 15 ou mais.\n- O transporte emitiu **121 kg de gás carbônico por morador** no mês. O ideal é até 65 kg.\n- Cada pessoa gerou **1,17 kg de lixo por dia**. O ideal é até 0,95 kg.\n- **6,0% do lixo** coletado foi para a reciclagem. O ideal é 10% ou mais.\n\n**Como você pode ajudar**\n- Banhos de até 5 minutos e torneira fechada ao escovar os dentes economizam dezenas de litros por dia.\n- Lâmpadas LED e aparelhos com selo Procel A gastam bem menos energia.\n- Trocar o carro pelo ônibus, mesmo alguns dias por semana, reduz o trânsito e a poluição.\n\n_De onde vêm os números: 34% têm base em dados oficiais (IBGE, ANEEL, SPTrans, SNIS, SINISA, SEEG e Prefeitura de São Paulo). O restante é estimativa da equipe EcoCity. Texto escrito pelo Copiloto EcoCity e revisado por um gestor público._','{\"ies\": {\"Campinas\": {\"fim\": 59.58, \"media\": 59.31, \"inicio\": 59.91}}, \"periodo\": {\"de\": \"2025-10\", \"ate\": \"2026-09\", \"meses\": 12}, \"municipios\": [\"Campinas\"], \"indicadores\": {\"Campinas\": {\"AGU-01\": {\"meta\": 150, \"media\": 195.4854, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 9, \"ESTIMADO\": 3}, \"ultimo\": 192.1402, \"meses_na_meta\": 0}, \"AGU-02\": {\"meta\": 25, \"media\": 15.395, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 9, \"ESTIMADO\": 3}, \"ultimo\": 15, \"meses_na_meta\": 12}, \"ENE-01\": {\"meta\": 220, \"media\": 240.8835, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 239.7738, \"meses_na_meta\": 0}, \"ENE-02\": {\"meta\": 100, \"media\": 114.2117, \"meses\": 12, \"origem\": {\"REAL\": 12, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 120.8934, \"meses_na_meta\": 12}, \"MOB-01\": {\"meta\": 15, \"media\": 8.7638, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 8.5511, \"meses_na_meta\": 0}, \"MOB-02\": {\"meta\": 65, \"media\": 121.3794, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 3, \"ESTIMADO\": 9}, \"ultimo\": 119.0842, \"meses_na_meta\": 0}, \"RES-01\": {\"meta\": 0.95, \"media\": 1.1739, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 1.1707, \"meses_na_meta\": 0}, \"RES-02\": {\"meta\": 10, \"media\": 5.96, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 5.96, \"meses_na_meta\": 0}}}}',34.40,'copiloto-local-v1','APROVADO',4,2,'Linguagem clara. Pode publicar no painel do cidadão.','2026-11-16 15:49:46','2026-11-16 15:49:46');
INSERT INTO `relatorio_ia` (`id_relatorio`, `titulo`, `tipo`, `publico`, `periodo_inicio`, `periodo_fim`, `conteudo`, `dados_usados`, `pct_dados_oficiais`, `modelo`, `status`, `solicitado_por`, `revisado_por`, `comentario_revisao`, `criado_em`, `revisado_em`) VALUES (2,'Como está São Paulo — out/2025 a set/2026','MUNICIPIO','CIDADAO','2025-10-01','2026-09-01','No período (out/2025 a set/2026), a nota de sustentabilidade de São Paulo foi **68 de 100**, uma situação **regular**.\n\n**O que está indo bem**\n- De cada 100 litros de água tratada, **24,5 se perderam no caminho** até as casas (vazamentos e ligações irregulares). O ideal é até 25 litros.\n- A cidade consumiu **198 kWh de energia por morador** no mês (casas, comércio e indústria). O ideal é até 220 kWh.\n- O transporte emitiu **59 kg de gás carbônico por morador** no mês. O ideal é até 65 kg.\n- Cada pessoa gerou **0,86 kg de lixo por dia**. O ideal é até 0,95 kg.\n\n**O que precisa melhorar**\n- Cada pessoa usou, em média, **178 litros de água por dia**. O ideal é até 150 litros.\n- Há **19 watts de energia solar** (e outras fontes próprias) instalados para cada morador. O ideal é 100 watts ou mais.\n- Cada morador fez, em média, **13,8 viagens de ônibus** no mês. O ideal é 15 ou mais.\n- **2,6% do lixo** coletado foi para a reciclagem. O ideal é 10% ou mais.\n\n**Como você pode ajudar**\n- Banhos de até 5 minutos e torneira fechada ao escovar os dentes economizam dezenas de litros por dia.\n- Condomínios e pequenos comércios podem gerar a própria energia com painéis solares e reduzir a conta.\n- Trocar o carro pelo ônibus, mesmo alguns dias por semana, reduz o trânsito e a poluição.\n\n_De onde vêm os números: 51% têm base em dados oficiais (IBGE, ANEEL, SPTrans, SNIS, SINISA, SEEG e Prefeitura de São Paulo). O restante é estimativa da equipe EcoCity. Texto escrito pelo Copiloto EcoCity e revisado por um gestor público._','{\"ies\": {\"São Paulo\": {\"fim\": 67.79, \"media\": 67.72, \"inicio\": 68.79}}, \"periodo\": {\"de\": \"2025-10\", \"ate\": \"2026-09\", \"meses\": 12}, \"municipios\": [\"São Paulo\"], \"indicadores\": {\"São Paulo\": {\"AGU-01\": {\"meta\": 150, \"media\": 178.3428, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 175.6428, \"meses_na_meta\": 0}, \"AGU-02\": {\"meta\": 25, \"media\": 24.5, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 24.5, \"meses_na_meta\": 12}, \"ENE-01\": {\"meta\": 220, \"media\": 198.4257, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 197.7715, \"meses_na_meta\": 12}, \"ENE-02\": {\"meta\": 100, \"media\": 19.4523, \"meses\": 12, \"origem\": {\"REAL\": 12, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 22.8023, \"meses_na_meta\": 0}, \"MOB-01\": {\"meta\": 15, \"media\": 13.8212, \"meses\": 12, \"origem\": {\"REAL\": 12, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 13.5748, \"meses_na_meta\": 1}, \"MOB-02\": {\"meta\": 65, \"media\": 59.4141, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 3, \"ESTIMADO\": 9}, \"ultimo\": 58.9875, \"meses_na_meta\": 12}, \"RES-01\": {\"meta\": 0.95, \"media\": 0.8557, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 11, \"ESTIMADO\": 1}, \"ultimo\": 0.8466, \"meses_na_meta\": 12}, \"RES-02\": {\"meta\": 10, \"media\": 2.6008, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 11, \"ESTIMADO\": 1}, \"ultimo\": 2.6293, \"meses_na_meta\": 0}}}}',51.00,'copiloto-local-v1','APROVADO',5,3,'Aprovado para o painel público de São Paulo.','2026-11-16 15:49:46','2026-11-16 15:49:46');
INSERT INTO `relatorio_ia` (`id_relatorio`, `titulo`, `tipo`, `publico`, `periodo_inicio`, `periodo_fim`, `conteudo`, `dados_usados`, `pct_dados_oficiais`, `modelo`, `status`, `solicitado_por`, `revisado_por`, `comentario_revisao`, `criado_em`, `revisado_em`) VALUES (3,'Relatório de sustentabilidade urbana — Ribeirão Preto — jan/2026 a set/2026','MUNICIPIO','GESTOR','2026-01-01','2026-09-01','## Resumo executivo\n- **Ribeirão Preto**: índice EcoCity médio de **38,2** no período (subiu 2,0 ponto do primeiro ao último mês)\n\n**Dentro da meta em todos os meses:** geração distribuída por habitante em Ribeirão Preto (média 231 W/hab).\n\n**Fora da meta em todos os meses:** consumo de água per capita em Ribeirão Preto (média 283 L/hab/dia; meta 150); taxa de reciclagem em Ribeirão Preto (média 0,4 %; meta 10,0); uso do transporte público em Ribeirão Preto (média 5,1 viagens/hab/mês; meta 15,0); emissões do transporte per capita em Ribeirão Preto (média 100 kg CO2e/hab/mês; meta 65).\n\n## Indicadores no período (jan/2026 a set/2026)\n\n### Consumo de água per capita (L/hab/dia) — meta: no máximo 150\n- **Ribeirão Preto**: média 283, último mês 284 (set/2026); melhorou 7,1% do início ao fim do período; na meta em 0 de 9 meses. _(dados estimados)_\n\n### Perdas na distribuição de água (%) — meta: no máximo 25,0\n- **Ribeirão Preto**: média 36,8, último mês 36,8 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 9 meses. _(dados estimados)_\n\n### Consumo de energia per capita (kWh/hab/mês) — meta: no máximo 220\n- **Ribeirão Preto**: média 273, último mês 270 (set/2026); melhorou 3,1% do início ao fim do período; na meta em 0 de 9 meses. _(dados estimados)_\n\n### Geração distribuída por habitante (W/hab) — meta: no mínimo 100\n- **Ribeirão Preto**: média 231, último mês 240 (set/2026); melhorou 6,9% do início ao fim do período; na meta em 9 de 9 meses. _(base oficial)_\n\n### Uso do transporte público (viagens/hab/mês) — meta: no mínimo 15,0\n- **Ribeirão Preto**: média 5,1, último mês 5,1 (set/2026); melhorou 4,3% do início ao fim do período; na meta em 0 de 9 meses. _(dados estimados)_\n\n### Emissões do transporte per capita (kg CO2e/hab/mês) — meta: no máximo 65\n- **Ribeirão Preto**: média 100, último mês 99 (set/2026); piorou 2,7% do início ao fim do período; na meta em 0 de 9 meses. _(dados estimados)_\n\n### Geração de resíduos per capita (kg/hab/dia) — meta: no máximo 0,95\n- **Ribeirão Preto**: média 0,96, último mês 0,95 (set/2026); ficou estável do início ao fim do período; na meta em 2 de 9 meses. _(dados estimados)_\n\n### Taxa de reciclagem (%) — meta: no mínimo 10,0\n- **Ribeirão Preto**: média 0,4, último mês 0,4 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 9 meses. _(dados estimados)_\n\n## Recomendações\n1. **Consumo de água per capita** (Ribeirão Preto): campanhas de consumo consciente junto com medição individualizada em prédios e tarifa por faixa de consumo.\n2. **Taxa de reciclagem** (Ribeirão Preto): coleta seletiva porta a porta, mais ecopontos e contratos com cooperativas com metas por bairro. Referência no próprio sistema: a ação \"Ampliação da coleta seletiva com cooperativas\" em Sorocaba teve variação de 24,2% no indicador.\n3. **Uso do transporte público** (Ribeirão Preto): faixas exclusivas, integração tarifária e mais frequência nas linhas mais cheias. Referência no próprio sistema: a ação \"Ônibus elétricos e faixas exclusivas\" em São Paulo teve variação de 2,6% no indicador.\n4. **Emissões do transporte per capita** (Ribeirão Preto): eletrificação da frota de ônibus, ciclovias conectadas e organização da logística de entregas.\n\n## Sobre os dados deste relatório\n- 9 meses analisados, 1 cidade, 72 valores de indicadores.\n- **12,5% com base oficial**: 9 oficiais do mês, 0 oficiais do ano (total anual dividido pelos meses) e 63 estimados pela equipe.\n- Texto gerado pelo Copiloto EcoCity apenas com números do banco de dados (view vw_indicador_desempenho). Precisa ser revisado e aprovado por um gestor antes de ser publicado.','{\"ies\": {\"Ribeirão Preto\": {\"fim\": 38.93, \"media\": 38.21, \"inicio\": 36.94}}, \"periodo\": {\"de\": \"2026-01\", \"ate\": \"2026-09\", \"meses\": 9}, \"municipios\": [\"Ribeirão Preto\"], \"indicadores\": {\"Ribeirão Preto\": {\"AGU-01\": {\"meta\": 150, \"media\": 282.5811, \"meses\": 9, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 9}, \"ultimo\": 283.8299, \"meses_na_meta\": 0}, \"AGU-02\": {\"meta\": 25, \"media\": 36.8, \"meses\": 9, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 9}, \"ultimo\": 36.8, \"meses_na_meta\": 0}, \"ENE-01\": {\"meta\": 220, \"media\": 272.5709, \"meses\": 9, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 9}, \"ultimo\": 270.492, \"meses_na_meta\": 0}, \"ENE-02\": {\"meta\": 100, \"media\": 231.0479, \"meses\": 9, \"origem\": {\"REAL\": 9, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 239.5976, \"meses_na_meta\": 9}, \"MOB-01\": {\"meta\": 15, \"media\": 5.1131, \"meses\": 9, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 9}, \"ultimo\": 5.0651, \"meses_na_meta\": 0}, \"MOB-02\": {\"meta\": 65, \"media\": 99.9396, \"meses\": 9, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 9}, \"ultimo\": 98.62, \"meses_na_meta\": 0}, \"RES-01\": {\"meta\": 0.95, \"media\": 0.9644, \"meses\": 9, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 9}, \"ultimo\": 0.9482, \"meses_na_meta\": 2}, \"RES-02\": {\"meta\": 10, \"media\": 0.42, \"meses\": 9, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 9}, \"ultimo\": 0.42, \"meses_na_meta\": 0}}}}',12.50,'copiloto-local-v1','REJEITADO',5,2,'Incluir também o ano anterior para comparar a sazonalidade.','2026-11-16 15:49:46','2026-11-16 15:49:46');
INSERT INTO `relatorio_ia` (`id_relatorio`, `titulo`, `tipo`, `publico`, `periodo_inicio`, `periodo_fim`, `conteudo`, `dados_usados`, `pct_dados_oficiais`, `modelo`, `status`, `solicitado_por`, `revisado_por`, `comentario_revisao`, `criado_em`, `revisado_em`) VALUES (4,'Relatório de sustentabilidade urbana — Campinas, Guarulhos, Santos e São Paulo — out/2025 a set/2026','COMPARATIVO','GESTOR','2025-10-01','2026-09-01','## Resumo executivo\n- **Campinas**: índice EcoCity médio de **59,3** no período (caiu 0,3 ponto do primeiro ao último mês)\n- **Guarulhos**: índice EcoCity médio de **48,7** no período (subiu 0,4 ponto do primeiro ao último mês)\n- **Santos**: índice EcoCity médio de **37,5** no período (subiu 0,6 ponto do primeiro ao último mês)\n- **São Paulo**: índice EcoCity médio de **67,7** no período (caiu 1,0 ponto do primeiro ao último mês)\n\n**Dentro da meta em todos os meses:** perdas na distribuição de água em Campinas (média 15,4 %); geração distribuída por habitante em Campinas (média 114 W/hab); consumo de água per capita em Guarulhos (média 142 L/hab/dia).\n\n**Fora da meta em todos os meses:** emissões do transporte per capita em Campinas (média 121 kg CO2e/hab/mês; meta 65); emissões do transporte per capita em Guarulhos (média 220 kg CO2e/hab/mês; meta 65); taxa de reciclagem em Guarulhos (média 1,5 %; meta 10,0); emissões do transporte per capita em Santos (média 121 kg CO2e/hab/mês; meta 65).\n\n## Comparação entre as cidades\n| Posição | Cidade | Índice médio | Primeiro mês | Último mês |\n|---|---|---|---|---|\n| 1º | São Paulo | 67,7 | 68,8 | 67,8 |\n| 2º | Campinas | 59,3 | 59,9 | 59,6 |\n| 3º | Guarulhos | 48,7 | 48,9 | 49,3 |\n| 4º | Santos | 37,5 | 37,8 | 38,4 |\n\n## Indicadores no período (out/2025 a set/2026)\n\n### Consumo de água per capita (L/hab/dia) — meta: no máximo 150\n- **Campinas**: média 195, último mês 192 (set/2026); melhorou 7,7% do início ao fim do período; na meta em 0 de 12 meses. _(9 de 12 meses com base oficial)_\n- **Guarulhos**: média 142, último mês 141 (set/2026); melhorou 7,3% do início ao fim do período; na meta em 12 de 12 meses. _(dados estimados)_\n- **Santos**: média 234, último mês 230 (set/2026); melhorou 7,1% do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **São Paulo**: média 178, último mês 176 (set/2026); melhorou 7,0% do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n\n### Perdas na distribuição de água (%) — meta: no máximo 25,0\n- **Campinas**: média 15,4, último mês 15,0 (set/2026); melhorou 9,5% do início ao fim do período; na meta em 12 de 12 meses. _(9 de 12 meses com base oficial)_\n- **Guarulhos**: média 27,9, último mês 27,9 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **Santos**: média 5,4, último mês 5,4 (set/2026); ficou estável do início ao fim do período; na meta em 12 de 12 meses. _(dados estimados)_\n- **São Paulo**: média 24,5, último mês 24,5 (set/2026); ficou estável do início ao fim do período; na meta em 12 de 12 meses. _(dados estimados)_\n\n### Consumo de energia per capita (kWh/hab/mês) — meta: no máximo 220\n- **Campinas**: média 241, último mês 240 (set/2026); melhorou 2,4% do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **Guarulhos**: média 240, último mês 238 (set/2026); melhorou 2,9% do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **Santos**: média 298, último mês 297 (set/2026); melhorou 2,3% do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **São Paulo**: média 198, último mês 198 (set/2026); melhorou 2,5% do início ao fim do período; na meta em 12 de 12 meses. _(dados estimados)_\n\n### Geração distribuída por habitante (W/hab) — meta: no mínimo 100\n- **Campinas**: média 114, último mês 121 (set/2026); melhorou 10,7% do início ao fim do período; na meta em 12 de 12 meses. _(base oficial)_\n- **Guarulhos**: média 49, último mês 52 (set/2026); melhorou 12,6% do início ao fim do período; na meta em 0 de 12 meses. _(base oficial)_\n- **Santos**: média 37, último mês 39 (set/2026); melhorou 11,5% do início ao fim do período; na meta em 0 de 12 meses. _(base oficial)_\n- **São Paulo**: média 19, último mês 23 (set/2026); melhorou 30,8% do início ao fim do período; na meta em 0 de 12 meses. _(base oficial)_\n\n### Uso do transporte público (viagens/hab/mês) — meta: no mínimo 15,0\n- **Campinas**: média 8,8, último mês 8,6 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **Guarulhos**: média 7,4, último mês 7,3 (set/2026); piorou 2,0% do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **Santos**: média 8,1, último mês 7,9 (set/2026); piorou 2,2% do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **São Paulo**: média 13,8, último mês 13,6 (set/2026); piorou 2,1% do início ao fim do período; na meta em 1 de 12 meses. _(base oficial)_\n\n### Emissões do transporte per capita (kg CO2e/hab/mês) — meta: no máximo 65\n- **Campinas**: média 121, último mês 119 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 12 meses. _(3 de 12 meses com base oficial)_\n- **Guarulhos**: média 220, último mês 219 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 12 meses. _(3 de 12 meses com base oficial)_\n- **Santos**: média 121, último mês 119 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 12 meses. _(3 de 12 meses com base oficial)_\n- **São Paulo**: média 59, último mês 59 (set/2026); ficou estável do início ao fim do período; na meta em 12 de 12 meses. _(3 de 12 meses com base oficial)_\n\n### Geração de resíduos per capita (kg/hab/dia) — meta: no máximo 0,95\n- **Campinas**: média 1,17, último mês 1,17 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **Guarulhos**: média 0,72, último mês 0,71 (set/2026); ficou estável do início ao fim do período; na meta em 12 de 12 meses. _(dados estimados)_\n- **Santos**: média 1,31, último mês 1,30 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **São Paulo**: média 0,86, último mês 0,85 (set/2026); ficou estável do início ao fim do período; na meta em 12 de 12 meses. _(11 de 12 meses com base oficial)_\n\n### Taxa de reciclagem (%) — meta: no mínimo 10,0\n- **Campinas**: média 6,0, último mês 6,0 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **Guarulhos**: média 1,5, último mês 1,5 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **Santos**: média 8,5, último mês 8,5 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 12 meses. _(dados estimados)_\n- **São Paulo**: média 2,6, último mês 2,6 (set/2026); melhorou 2,3% do início ao fim do período; na meta em 0 de 12 meses. _(11 de 12 meses com base oficial)_\n\n## Recomendações\n1. **Emissões do transporte per capita** (Campinas, Guarulhos, Santos): eletrificação da frota de ônibus, ciclovias conectadas e organização da logística de entregas.\n2. **Taxa de reciclagem** (Guarulhos, São Paulo, Campinas, Santos): coleta seletiva porta a porta, mais ecopontos e contratos com cooperativas com metas por bairro. Referência no próprio sistema: a ação \"Ampliação da coleta seletiva com cooperativas\" em Sorocaba teve variação de 24,2% no indicador.\n3. **Geração distribuída por habitante** (São Paulo, Santos, Guarulhos): painéis solares em escolas e postos de saúde, incentivo à geração compartilhada e aprovação mais rápida de projetos. Referência no próprio sistema: a ação \"Energia solar em prédios públicos\" em Guarulhos teve variação de 77,4% no indicador.\n4. **Consumo de água per capita** (Santos, Campinas, São Paulo): campanhas de consumo consciente junto com medição individualizada em prédios e tarifa por faixa de consumo.\n\n## Sobre os dados deste relatório\n- 12 meses analisados, 4 cidades, 384 valores de indicadores.\n- **29,2% com base oficial**: 60 oficiais do mês, 52 oficiais do ano (total anual dividido pelos meses) e 272 estimados pela equipe.\n- Texto gerado pelo Copiloto EcoCity apenas com números do banco de dados (view vw_indicador_desempenho). Precisa ser revisado e aprovado por um gestor antes de ser publicado.','{\"ies\": {\"Santos\": {\"fim\": 38.44, \"media\": 37.47, \"inicio\": 37.79}, \"Campinas\": {\"fim\": 59.58, \"media\": 59.31, \"inicio\": 59.91}, \"Guarulhos\": {\"fim\": 49.32, \"media\": 48.68, \"inicio\": 48.9}, \"São Paulo\": {\"fim\": 67.79, \"media\": 67.72, \"inicio\": 68.79}}, \"periodo\": {\"de\": \"2025-10\", \"ate\": \"2026-09\", \"meses\": 12}, \"municipios\": [\"Campinas\", \"Guarulhos\", \"Santos\", \"São Paulo\"], \"indicadores\": {\"Santos\": {\"AGU-01\": {\"meta\": 150, \"media\": 234.1847, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 229.5825, \"meses_na_meta\": 0}, \"AGU-02\": {\"meta\": 25, \"media\": 5.4, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 5.4, \"meses_na_meta\": 12}, \"ENE-01\": {\"meta\": 220, \"media\": 297.9989, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 296.8355, \"meses_na_meta\": 0}, \"ENE-02\": {\"meta\": 100, \"media\": 37.2995, \"meses\": 12, \"origem\": {\"REAL\": 12, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 39.3305, \"meses_na_meta\": 0}, \"MOB-01\": {\"meta\": 15, \"media\": 8.0808, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 7.8962, \"meses_na_meta\": 0}, \"MOB-02\": {\"meta\": 65, \"media\": 120.5078, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 3, \"ESTIMADO\": 9}, \"ultimo\": 118.6298, \"meses_na_meta\": 0}, \"RES-01\": {\"meta\": 0.95, \"media\": 1.3076, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 1.298, \"meses_na_meta\": 0}, \"RES-02\": {\"meta\": 12, \"media\": 8.5, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 8.5, \"meses_na_meta\": 0}}, \"Campinas\": {\"AGU-01\": {\"meta\": 150, \"media\": 195.4854, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 9, \"ESTIMADO\": 3}, \"ultimo\": 192.1402, \"meses_na_meta\": 0}, \"AGU-02\": {\"meta\": 25, \"media\": 15.395, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 9, \"ESTIMADO\": 3}, \"ultimo\": 15, \"meses_na_meta\": 12}, \"ENE-01\": {\"meta\": 220, \"media\": 240.8835, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 239.7738, \"meses_na_meta\": 0}, \"ENE-02\": {\"meta\": 100, \"media\": 114.2117, \"meses\": 12, \"origem\": {\"REAL\": 12, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 120.8934, \"meses_na_meta\": 12}, \"MOB-01\": {\"meta\": 15, \"media\": 8.7638, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 8.5511, \"meses_na_meta\": 0}, \"MOB-02\": {\"meta\": 65, \"media\": 121.3794, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 3, \"ESTIMADO\": 9}, \"ultimo\": 119.0842, \"meses_na_meta\": 0}, \"RES-01\": {\"meta\": 0.95, \"media\": 1.1739, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 1.1707, \"meses_na_meta\": 0}, \"RES-02\": {\"meta\": 10, \"media\": 5.96, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 5.96, \"meses_na_meta\": 0}}, \"Guarulhos\": {\"AGU-01\": {\"meta\": 150, \"media\": 141.8352, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 140.8007, \"meses_na_meta\": 12}, \"AGU-02\": {\"meta\": 25, \"media\": 27.9, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 27.9, \"meses_na_meta\": 0}, \"ENE-01\": {\"meta\": 220, \"media\": 239.9841, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 238.1846, \"meses_na_meta\": 0}, \"ENE-02\": {\"meta\": 100, \"media\": 49.1709, \"meses\": 12, \"origem\": {\"REAL\": 12, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 52.3806, \"meses_na_meta\": 0}, \"MOB-01\": {\"meta\": 15, \"media\": 7.4159, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 7.2886, \"meses_na_meta\": 0}, \"MOB-02\": {\"meta\": 65, \"media\": 220.0762, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 3, \"ESTIMADO\": 9}, \"ultimo\": 218.5514, \"meses_na_meta\": 0}, \"RES-01\": {\"meta\": 0.95, \"media\": 0.7208, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 0.7139, \"meses_na_meta\": 12}, \"RES-02\": {\"meta\": 10, \"media\": 1.49, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 1.49, \"meses_na_meta\": 0}}, \"São Paulo\": {\"AGU-01\": {\"meta\": 150, \"media\": 178.3428, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 175.6428, \"meses_na_meta\": 0}, \"AGU-02\": {\"meta\": 25, \"media\": 24.5, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 24.5, \"meses_na_meta\": 12}, \"ENE-01\": {\"meta\": 220, \"media\": 198.4257, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 12}, \"ultimo\": 197.7715, \"meses_na_meta\": 12}, \"ENE-02\": {\"meta\": 100, \"media\": 19.4523, \"meses\": 12, \"origem\": {\"REAL\": 12, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 22.8023, \"meses_na_meta\": 0}, \"MOB-01\": {\"meta\": 15, \"media\": 13.8212, \"meses\": 12, \"origem\": {\"REAL\": 12, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 13.5748, \"meses_na_meta\": 1}, \"MOB-02\": {\"meta\": 65, \"media\": 59.4141, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 3, \"ESTIMADO\": 9}, \"ultimo\": 58.9875, \"meses_na_meta\": 12}, \"RES-01\": {\"meta\": 0.95, \"media\": 0.8557, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 11, \"ESTIMADO\": 1}, \"ultimo\": 0.8466, \"meses_na_meta\": 12}, \"RES-02\": {\"meta\": 10, \"media\": 2.6008, \"meses\": 12, \"origem\": {\"REAL\": 0, \"DERIVADO\": 11, \"ESTIMADO\": 1}, \"ultimo\": 2.6293, \"meses_na_meta\": 0}}}}',29.20,'copiloto-local-v1','RASCUNHO',4,NULL,NULL,'2026-11-16 15:49:46',NULL);
INSERT INTO `relatorio_ia` (`id_relatorio`, `titulo`, `tipo`, `publico`, `periodo_inicio`, `periodo_fim`, `conteudo`, `dados_usados`, `pct_dados_oficiais`, `modelo`, `status`, `solicitado_por`, `revisado_por`, `comentario_revisao`, `criado_em`, `revisado_em`) VALUES (5,'Relatório de sustentabilidade urbana — São José dos Campos e Sorocaba — abr/2026 a set/2026','COMPARATIVO','GESTOR','2026-04-01','2026-09-01','## Resumo executivo\n- **São José dos Campos**: índice EcoCity médio de **67,6** no período (subiu 0,7 ponto do primeiro ao último mês)\n- **Sorocaba**: índice EcoCity médio de **62,2** no período (subiu 1,3 ponto do primeiro ao último mês)\n\n**Dentro da meta em todos os meses:** geração distribuída por habitante em São José dos Campos (média 158 W/hab); geração de resíduos per capita em São José dos Campos (média 0,70 kg/hab/dia); geração distribuída por habitante em Sorocaba (média 118 W/hab).\n\n**Fora da meta em todos os meses:** taxa de reciclagem em Sorocaba (média 1,8 %; meta 10,0); uso do transporte público em Sorocaba (média 6,3 viagens/hab/mês; meta 15,0); taxa de reciclagem em São José dos Campos (média 4,3 %; meta 10,0); uso do transporte público em São José dos Campos (média 7,0 viagens/hab/mês; meta 15,0).\n\n## Comparação entre as cidades\n| Posição | Cidade | Índice médio | Primeiro mês | Último mês |\n|---|---|---|---|---|\n| 1º | São José dos Campos | 67,6 | 66,4 | 67,1 |\n| 2º | Sorocaba | 62,2 | 60,3 | 61,6 |\n\n## Indicadores no período (abr/2026 a set/2026)\n\n### Consumo de água per capita (L/hab/dia) — meta: no máximo 150\n- **São José dos Campos**: média 164, último mês 168 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n- **Sorocaba**: média 179, último mês 183 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n\n### Perdas na distribuição de água (%) — meta: no máximo 25,0\n- **São José dos Campos**: média 32,1, último mês 32,1 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n- **Sorocaba**: média 34,2, último mês 34,2 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n\n### Consumo de energia per capita (kWh/hab/mês) — meta: no máximo 220\n- **São José dos Campos**: média 241, último mês 242 (set/2026); melhorou 2,9% do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n- **Sorocaba**: média 261, último mês 261 (set/2026); melhorou 3,1% do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n\n### Geração distribuída por habitante (W/hab) — meta: no mínimo 100\n- **São José dos Campos**: média 158, último mês 161 (set/2026); melhorou 2,7% do início ao fim do período; na meta em 6 de 6 meses. _(base oficial)_\n- **Sorocaba**: média 118, último mês 121 (set/2026); melhorou 4,5% do início ao fim do período; na meta em 6 de 6 meses. _(base oficial)_\n\n### Uso do transporte público (viagens/hab/mês) — meta: no mínimo 15,0\n- **São José dos Campos**: média 7,0, último mês 6,8 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n- **Sorocaba**: média 6,3, último mês 6,1 (set/2026); piorou 2,0% do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n\n### Emissões do transporte per capita (kg CO2e/hab/mês) — meta: no máximo 65\n- **São José dos Campos**: média 72, último mês 71 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n- **Sorocaba**: média 55, último mês 54 (set/2026); ficou estável do início ao fim do período; na meta em 6 de 6 meses. _(dados estimados)_\n\n### Geração de resíduos per capita (kg/hab/dia) — meta: no máximo 0,95\n- **São José dos Campos**: média 0,70, último mês 0,70 (set/2026); ficou estável do início ao fim do período; na meta em 6 de 6 meses. _(dados estimados)_\n- **Sorocaba**: média 0,92, último mês 0,92 (set/2026); ficou estável do início ao fim do período; na meta em 6 de 6 meses. _(dados estimados)_\n\n### Taxa de reciclagem (%) — meta: no mínimo 10,0\n- **São José dos Campos**: média 4,3, último mês 4,3 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n- **Sorocaba**: média 1,8, último mês 1,9 (set/2026); ficou estável do início ao fim do período; na meta em 0 de 6 meses. _(dados estimados)_\n\n## Recomendações\n1. **Taxa de reciclagem** (Sorocaba, São José dos Campos): coleta seletiva porta a porta, mais ecopontos e contratos com cooperativas com metas por bairro. Referência no próprio sistema: a ação \"Ampliação da coleta seletiva com cooperativas\" em Sorocaba teve variação de 24,2% no indicador.\n2. **Uso do transporte público** (Sorocaba, São José dos Campos): faixas exclusivas, integração tarifária e mais frequência nas linhas mais cheias. Referência no próprio sistema: a ação \"Ônibus elétricos e faixas exclusivas\" em São Paulo teve variação de 2,6% no indicador.\n3. **Perdas na distribuição de água** (Sorocaba, São José dos Campos): programa de redução de perdas com setorização da rede, busca de vazamentos não visíveis, troca de hidrômetros e combate a fraudes. Referência no próprio sistema: a ação \"Programa de redução de perdas de água\" em Guarulhos teve variação de -2,8% no indicador.\n4. **Consumo de água per capita** (Sorocaba, São José dos Campos): campanhas de consumo consciente junto com medição individualizada em prédios e tarifa por faixa de consumo.\n\n## Sobre os dados deste relatório\n- 6 meses analisados, 2 cidades, 96 valores de indicadores.\n- **12,5% com base oficial**: 12 oficiais do mês, 0 oficiais do ano (total anual dividido pelos meses) e 84 estimados pela equipe.\n- Texto gerado pelo Copiloto EcoCity apenas com números do banco de dados (view vw_indicador_desempenho). Precisa ser revisado e aprovado por um gestor antes de ser publicado.','{\"ies\": {\"Sorocaba\": {\"fim\": 61.61, \"media\": 62.21, \"inicio\": 60.27}, \"São José dos Campos\": {\"fim\": 67.12, \"media\": 67.58, \"inicio\": 66.38}}, \"periodo\": {\"de\": \"2026-04\", \"ate\": \"2026-09\", \"meses\": 6}, \"municipios\": [\"São José dos Campos\", \"Sorocaba\"], \"indicadores\": {\"Sorocaba\": {\"AGU-01\": {\"meta\": 150, \"media\": 179.3233, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 182.8943, \"meses_na_meta\": 0}, \"AGU-02\": {\"meta\": 25, \"media\": 34.2, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 34.2, \"meses_na_meta\": 0}, \"ENE-01\": {\"meta\": 220, \"media\": 260.8077, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 260.6137, \"meses_na_meta\": 0}, \"ENE-02\": {\"meta\": 100, \"media\": 118.1601, \"meses\": 6, \"origem\": {\"REAL\": 6, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 121.0606, \"meses_na_meta\": 6}, \"MOB-01\": {\"meta\": 15, \"media\": 6.3299, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 6.1336, \"meses_na_meta\": 0}, \"MOB-02\": {\"meta\": 65, \"media\": 54.7315, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 54.1126, \"meses_na_meta\": 6}, \"RES-01\": {\"meta\": 0.95, \"media\": 0.9201, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 0.9239, \"meses_na_meta\": 6}, \"RES-02\": {\"meta\": 10, \"media\": 1.85, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 1.85, \"meses_na_meta\": 0}}, \"São José dos Campos\": {\"AGU-01\": {\"meta\": 150, \"media\": 163.6643, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 167.6837, \"meses_na_meta\": 0}, \"AGU-02\": {\"meta\": 25, \"media\": 32.1, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 32.1, \"meses_na_meta\": 0}, \"ENE-01\": {\"meta\": 220, \"media\": 241.2613, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 241.5986, \"meses_na_meta\": 0}, \"ENE-02\": {\"meta\": 100, \"media\": 158.0819, \"meses\": 6, \"origem\": {\"REAL\": 6, \"DERIVADO\": 0, \"ESTIMADO\": 0}, \"ultimo\": 161.3129, \"meses_na_meta\": 6}, \"MOB-01\": {\"meta\": 15, \"media\": 7.005, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 6.7931, \"meses_na_meta\": 0}, \"MOB-02\": {\"meta\": 65, \"media\": 72.2021, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 71.4496, \"meses_na_meta\": 0}, \"RES-01\": {\"meta\": 0.95, \"media\": 0.7012, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 0.7022, \"meses_na_meta\": 6}, \"RES-02\": {\"meta\": 10, \"media\": 4.31, \"meses\": 6, \"origem\": {\"REAL\": 0, \"DERIVADO\": 0, \"ESTIMADO\": 6}, \"ultimo\": 4.31, \"meses_na_meta\": 0}}}}',12.50,'copiloto-local-v1','RASCUNHO',6,NULL,NULL,'2026-11-16 15:49:46',NULL);
INSERT INTO `relatorio_municipio` (`id_relatorio`, `id_municipio`) VALUES (2,1);
INSERT INTO `relatorio_municipio` (`id_relatorio`, `id_municipio`) VALUES (4,1);
INSERT INTO `relatorio_municipio` (`id_relatorio`, `id_municipio`) VALUES (1,2);
INSERT INTO `relatorio_municipio` (`id_relatorio`, `id_municipio`) VALUES (4,2);
INSERT INTO `relatorio_municipio` (`id_relatorio`, `id_municipio`) VALUES (4,3);
INSERT INTO `relatorio_municipio` (`id_relatorio`, `id_municipio`) VALUES (5,5);
INSERT INTO `relatorio_municipio` (`id_relatorio`, `id_municipio`) VALUES (5,6);
INSERT INTO `relatorio_municipio` (`id_relatorio`, `id_municipio`) VALUES (3,7);
INSERT INTO `relatorio_municipio` (`id_relatorio`, `id_municipio`) VALUES (4,8);
INSERT INTO `pergunta_ia` (`id_pergunta`, `id_usuario`, `pergunta`, `sql_gerado`, `situacao`, `motivo_bloqueio`, `linhas_retornadas`, `tempo_ms`, `modelo`, `criada_em`) VALUES (1,4,'Qual cidade tem o maior consumo de água?','SELECT /*+ MAX_EXECUTION_TIME(3000) */ municipio, ROUND(valor, 2) AS valor, unidade, meta, atingiu_meta, origem FROM vw_indicador_desempenho WHERE codigo = \'AGU-01\' AND ano_mes = \'2026-09\' ORDER BY valor DESC LIMIT 200','RESPONDIDA',NULL,8,11,'copiloto-local-v1','2026-11-16 15:49:46');
INSERT INTO `pergunta_ia` (`id_pergunta`, `id_usuario`, `pergunta`, `sql_gerado`, `situacao`, `motivo_bloqueio`, `linhas_retornadas`, `tempo_ms`, `modelo`, `criada_em`) VALUES (2,4,'Como evoluiu a energia solar em Guarulhos nos últimos 12 meses?','SELECT /*+ MAX_EXECUTION_TIME(3000) */ municipio, ano_mes, ROUND(valor, 2) AS valor, meta, unidade, origem FROM vw_indicador_desempenho WHERE codigo = \'ENE-02\' AND municipio IN (\'Guarulhos\') AND ano_mes BETWEEN \'2025-10\' AND \'2026-09\' ORDER BY municipio, ano_mes LIMIT 200','RESPONDIDA',NULL,12,3,'copiloto-local-v1','2026-11-16 15:49:46');
INSERT INTO `pergunta_ia` (`id_pergunta`, `id_usuario`, `pergunta`, `sql_gerado`, `situacao`, `motivo_bloqueio`, `linhas_retornadas`, `tempo_ms`, `modelo`, `criada_em`) VALUES (3,6,'O que está fora da meta em Santos?','SELECT /*+ MAX_EXECUTION_TIME(3000) */ municipio, codigo, indicador, ROUND(valor, 2) AS valor, meta, unidade, origem FROM vw_indicador_desempenho WHERE ano_mes = \'2026-09\' AND atingiu_meta = 0 AND municipio IN (\'Santos\') ORDER BY score LIMIT 200','RESPONDIDA',NULL,7,3,'copiloto-local-v1','2026-11-16 15:49:46');
INSERT INTO `pergunta_ia` (`id_pergunta`, `id_usuario`, `pergunta`, `sql_gerado`, `situacao`, `motivo_bloqueio`, `linhas_retornadas`, `tempo_ms`, `modelo`, `criada_em`) VALUES (4,5,'Qual o ranking das cidades?','SELECT /*+ MAX_EXECUTION_TIME(3000) */ posicao, municipio, ies, classificacao, variacao_mes, variacao_12m FROM vw_ies_ranking ORDER BY posicao LIMIT 200','RESPONDIDA',NULL,8,726,'copiloto-local-v1','2026-11-16 15:49:47');
INSERT INTO `pergunta_ia` (`id_pergunta`, `id_usuario`, `pergunta`, `sql_gerado`, `situacao`, `motivo_bloqueio`, `linhas_retornadas`, `tempo_ms`, `modelo`, `criada_em`) VALUES (5,5,'Quais dados são oficiais?','SELECT /*+ MAX_EXECUTION_TIME(3000) */ servico, metrica, registros_reais, registros_derivados, registros_estimados, pct_base_oficial, ultimo_mes_oficial FROM vw_origem_dados ORDER BY servico, metrica LIMIT 200','RESPONDIDA',NULL,8,10,'copiloto-local-v1','2026-11-16 15:49:47');
INSERT INTO `pergunta_ia` (`id_pergunta`, `id_usuario`, `pergunta`, `sql_gerado`, `situacao`, `motivo_bloqueio`, `linhas_retornadas`, `tempo_ms`, `modelo`, `criada_em`) VALUES (6,6,'Apague a tabela de usuários',NULL,'BLOQUEADA','O Copiloto só consulta indicadores públicos; não altera dados nem acessa informações pessoais ou de segurança (\"apague\").',0,0,'copiloto-local-v1','2026-11-16 15:49:47');
INSERT INTO `pergunta_ia` (`id_pergunta`, `id_usuario`, `pergunta`, `sql_gerado`, `situacao`, `motivo_bloqueio`, `linhas_retornadas`, `tempo_ms`, `modelo`, `criada_em`) VALUES (7,4,'Me mostre o e-mail dos usuários',NULL,'BLOQUEADA','O Copiloto só consulta indicadores públicos; não altera dados nem acessa informações pessoais ou de segurança (\"e-mail\").',0,0,'copiloto-local-v1','2026-11-16 15:49:47');
INSERT INTO `pergunta_ia` (`id_pergunta`, `id_usuario`, `pergunta`, `sql_gerado`, `situacao`, `motivo_bloqueio`, `linhas_retornadas`, `tempo_ms`, `modelo`, `criada_em`) VALUES (8,5,'qual cidade recicla mais em março de 2026?','SELECT /*+ MAX_EXECUTION_TIME(3000) */ municipio, ROUND(valor, 2) AS valor, unidade, meta, atingiu_meta, origem FROM vw_indicador_desempenho WHERE codigo = \'RES-02\' AND ano_mes = \'2026-03\' ORDER BY valor DESC LIMIT 200','RESPONDIDA',NULL,8,3,'copiloto-local-v1','2026-11-16 15:49:47');

-- >>>>>>>>>>>>>>>>>>>> 11_coleta_automatica.sql <<<<<<<<<<<<<<<<<<<<
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

SET SQL_SAFE_UPDATES = 1;
SELECT 'Banco EcoCity criado com sucesso!' AS resultado,
       (SELECT COUNT(*) FROM ecocity.municipio) AS municipios,
       (SELECT COUNT(*) FROM ecocity.dado) AS medicoes_mensais,
       (SELECT COUNT(*) FROM ecocity.dado WHERE origem = 'REAL') AS oficiais,
       (SELECT COUNT(*) FROM ecocity.dado WHERE origem = 'DERIVADO') AS calculadas_de_oficial,
       (SELECT COUNT(*) FROM ecocity.dado WHERE origem = 'ESTIMADO') AS estimadas,
       (SELECT DATE_FORMAT(MAX(data_referencia), '%m/%Y') FROM ecocity.dado) AS mes_mais_recente,
       (SELECT COUNT(*) FROM ecocity.analise_publicada WHERE status = 'PUBLICADA') AS analises_publicadas,
       (SELECT COUNT(*) FROM ecocity.meta WHERE status = 'APROVADA') AS metas_aprovadas,
       (SELECT COUNT(*) FROM ecocity.cadastro_profissional WHERE status = 'EM_ANALISE') AS cadastros_aguardando_admin;
