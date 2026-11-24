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
  cpf_hash            CHAR(64)     NULL,                 -- (opcional) SHA-256 do CPF: impede cadastro duplicado sem guardar o número (LGPD)
  cpf_final           CHAR(2)      NULL,                 -- 2 últimos dígitos, só para conferência visual
  email_institucional VARCHAR(120) NOT NULL,             -- e-mail do órgão (gmail, hotmail etc. são recusados)
  telefone_institucional VARCHAR(20) NULL,              -- (opcional)
  orgao               VARCHAR(120) NOT NULL,             -- prefeitura, secretaria, concessionária, universidade...
  cargo               VARCHAR(80)  NOT NULL,
  matricula           VARCHAR(30)  NULL,                 -- (opcional) matrícula funcional no órgão
  formacao            VARCHAR(120) NULL,                 -- (opcional) ex.: Engenharia Ambiental (USP, 2018)
  registro_conselho   VARCHAR(40)  NULL,                 -- CREA, CRQ, CRBio, CORECON... (analista)
  portaria_nomeacao   VARCHAR(120) NULL,                 -- (opcional) ato de nomeação no Diário Oficial
  id_municipio_atuacao SMALLINT UNSIGNED NULL,           -- cidade onde atua (obrigatório para gestor)
  documento_url       VARCHAR(300) NULL,                 -- (opcional) declaração de vínculo assinada pelo órgão (PDF)
  justificativa       VARCHAR(600) NULL,                 -- (opcional) para que vai usar o acesso
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
  descricao        VARCHAR(300) NULL,                    -- a meta ESCRITA: "Reduzir de 192 para 182 L por pessoa por dia até dez/2027"
  linha_base       DECIMAL(12,4) NULL,                   -- valor de partida (último valor da cidade quando a meta foi proposta)
  prazo            DATE NULL,                            -- até quando a meta deve ser atingida
  como_atingir     VARCHAR(2000) NULL,                   -- plano: projetos e ações (um por linha)
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
  CONSTRAINT ck_meta_aprovada  CHECK (status NOT IN ('APROVADA','SUBSTITUIDA') OR (parecer_por IS NOT NULL AND aprovada_por IS NOT NULL)),
  CONSTRAINT ck_meta_prazo     CHECK (prazo IS NULL OR prazo >= vigencia_inicio)
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
