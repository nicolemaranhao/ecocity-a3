# Plano de Segurança e Administração de Dados — EcoCity

## 1. Perfis de acesso (papéis do MySQL)

O banco segue o **princípio do menor privilégio**: nenhum usuário de aplicação acessa tabelas que não precisa. Script: `sql/06_seguranca.sql`.

| Papel | Quem usa | Pode fazer | Não pode fazer |
|---|---|---|---|
| `r_cidadao` | Painel público | `SELECT` em `vw_painel_cidadao`, `vw_ies_ranking`, `vw_origem_dados` e `vw_relatorios_publicados` | Ver dados pessoais, tabelas, ações ou orçamento |
| `r_analista` | Analistas | Ler views analíticas, dados, DW (herda `r_bi`); validar/descartar insights (`UPDATE` só em `status` e `revisada_por` de `analise_ia`); propor ações; pedir relatórios e perguntar ao Copiloto | Excluir dados, alterar medições, mexer em usuários |
| `r_gestor` | Gestores públicos | Tudo do analista + criar/editar ações, registrar resultados (`sp_registrar_resultado`), aprovar relatórios da IA (`sp_revisar_relatorio`) | Alterar estrutura, excluir dados, aprovar o próprio pedido |
| `r_etl` | Serviço de integração e módulo de IA | Inserir no staging, executar procedures do pipeline, gravar insights | Ler usuários, alterar ações |
| `r_bi` | Ferramentas de BI | `SELECT` somente nas tabelas do DW e views do DW | Qualquer escrita |
| `r_ia` | Copiloto EcoCity (SQL gerado pela IA) | `SELECT` em 7 views de indicadores | Qualquer escrita; ler tabelas, usuários, auditoria |
| `r_dba` | Administrador | `ALL PRIVILEGES` no schema | — |

Usuários do banco: `ecocity_api` (papéis gestor + cidadão, mais acesso **por coluna** à tabela `usuario` para login), `ecocity_etl`, `ecocity_bi`, `ecocity_dba` e `ecocity_ia` (somente leitura, máximo de 600 consultas por hora e 3 conexões).

**Copiloto (IA):** a pergunta é recusada antes do banco se pedir alteração ou dado pessoal; o SQL gerado é validado (só `SELECT`, um comando, sem comentários, só views liberadas, `LIMIT 200`, `MAX_EXECUTION_TIME` de 3 s) e executado com `ecocity_ia`. Toda pergunta fica em `pergunta_ia`. Relatórios nascem como `RASCUNHO` e o trigger `trg_relatorio_bu` impede auto-aprovação e alteração do texto depois de revisado.

**Login reforçado (tabela `acesso_log` e procedure `sp_registrar_login`):** analista, gestor e admin precisam da 2ª etapa (código de 6 dígitos de um aplicativo autenticador; o segredo fica criptografado com AES em `usuario.mfa_segredo`). Depois de 5 erros seguidos a conta fica bloqueada por 15 minutos. A senha vence em 90 dias (60 para admin). Toda tentativa é registrada, e o sistema não revela se um e-mail existe.

**Credencial do analista (`credencial_analista`):** órgão de vínculo, registro profissional, área e nível, conferidos pelo administrador (`sp_verificar_credencial`), com validade de até 1 ano. Sem credencial verificada, o analista não envia análises nem dá parecer em metas.

**Segregação de funções:** quem escreve uma análise não a revisa; quem propõe uma meta não a aprova; quem pede um relatório da IA não o aprova. As regras estão no banco (procedures e triggers), então valem mesmo que alguém tente burlar a aplicação.

**Na aplicação:** login com e-mail e senha (hash **bcrypt**), token **JWT** com validade de 8 h e controle por perfil (`CIDADAO < ANALISTA < GESTOR < ADMIN`) em cada rota. Consultas sempre parametrizadas (proteção contra SQL injection), `helmet` (cabeçalhos HTTP seguros) e limite de requisições (10 tentativas de login a cada 15 min).

**Política de senhas do banco:** expiração em 90 dias (60 para DBA), bloqueio após 5 tentativas erradas (3 para DBA). Em produção: `REQUIRE SSL` em todos os usuários e segredos guardados no **OCI Vault** (nunca no código; o `.env` real fica fora do Git).

## 2. Integridade e auditoria

- PK, FK (com `ON DELETE RESTRICT/SET NULL/CASCADE` conforme a regra), `UNIQUE`, `CHECK` e `ENUM` em todas as tabelas.
- Triggers bloqueiam datas futuras e mudanças de status inválidas e marcam valores atípicos como `SUSPEITO`.
- Toda alteração/exclusão de `dado` e mudança de status/orçamento de `acao` é gravada em `auditoria` com usuário do banco, data/hora e valores antes/depois em JSON.
- Procedures críticas usam transação com `ROLLBACK` automático (`DECLARE EXIT HANDLER FOR SQLEXCEPTION`) e `SELECT ... FOR UPDATE` para evitar conflito de concorrência.

## 3. LGPD

- Dados pessoais mínimos: nome, e-mail e perfil. Nenhum dado pessoal nas medições (todas agregadas por região).
- Cidadão acessa apenas views agregadas.
- Retenção: auditoria por 5 anos; staging processado é expurgado após 90 dias (script 09).

## 4. Backup e recuperação de desastres

| Item | Estratégia |
|---|---|
| Backup automático | MySQL HeatWave (OCI): backup diário, retenção de 35 dias |
| Point-in-time recovery | Habilitado (binlog): restaura para qualquer minuto da janela |
| Backup lógico | `mysqldump --single-transaction --routines --triggers --events` semanal, compactado, enviado ao **Object Storage** com versionamento |
| Cópia fora da região | Replicação do bucket de backup para outra região da OCI |
| RPO (perda máxima) | ≤ 5 min com PITR; ≤ 24 h no pior caso |
| RTO (tempo para voltar) | ≤ 1 h (teste de restauração medido: 3 min 12 s) |
| Teste de restauração | Mensal, em ambiente de homologação, registrado em `adm_backup_log` |

**Procedimento de desastre:** (1) declarar incidente e congelar escritas da API; (2) restaurar o último backup ou PITR em nova instância HeatWave; (3) validar com `10_testes_integridade.sql` e contagem de registros; (4) apontar a API para a nova instância (variável `DB_HOST`); (5) reprocessar lotes pendentes do staging; (6) registrar o ocorrido.

## 5. Monitoramento de desempenho

- **OCI Monitoring**: alarmes de CPU > 80%, armazenamento > 75%, conexões > 80% do limite.
- **performance_schema / sys**: consultas mais lentas, índices não usados, conexões por usuário (script 09).
- **Slow query log** ativado com `long_query_time = 1`.
- `EXPLAIN` nas consultas dos dashboards a cada mudança de índice; `ANALYZE TABLE` mensal.
- Saúde do ETL: alerta para fontes sem carga há mais de 35 dias.
