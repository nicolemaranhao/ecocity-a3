# Requisitos priorizados — EcoCity — Data Warehouse para Comunidades Sustentáveis (Cidades Inteligentes)

Tema 18 · BD para Comunidades Sustentáveis (Cidades Inteligentes)

Prioridade: **Alta** = essencial para o MVP · **Média** = entra na entrega final · **Baixa** = complementar.

## Requisitos funcionais

| ID | Requisito | Uso do banco de dados | Prioridade | Por quê |
|---|---|---|---|---|
| RF01 | Integrar em um único banco, MÊS A MÊS, os dados de água, energia, resíduos e mobilidade de 8 cidades de SP (jan/2023 a dez/2024), vindos de fontes e formatos diferentes (IBGE, ANEEL, EPE, SPTrans, SNIS/SINISA, SEEG, Prefeitura de SP; APIs, planilhas, parquet e PDFs). | Tabelas stg_medicao_bruta, lote_carga, fonte_dados, orgao e dado; procedure sp_processar_staging. | Alta | É o problema central do tema: dados fragmentados. |
| RF02 | Validar cada dado recebido e rejeitar, com o motivo registrado, valores inválidos, municípios ou métricas desconhecidos e datas fora do padrão. | CHECK constraints, trigger trg_dado_bi (marca SUSPEITO) e coluna erro no staging. | Alta | Decisões só são boas com dados confiáveis. |
| RF03 | Identificar a origem de cada número (OFICIAL do mês, CALCULADO a partir de total oficial ou ESTIMADO), com a fonte, e permitir trocar pelo oficial quando ele for publicado. | Colunas dado.origem e referencia_origem; view vw_origem_dados; procedure sp_atualizar_dado_real. | Alta | Transparência: o gestor sabe o quanto pode confiar em cada número. |
| RF04 | Calcular TODO MÊS 8 indicadores de sustentabilidade por município (ISO 37120 / ODS 6, 7, 11, 12 e 13), usando a população oficial do ano. | Tabelas indicador, indicador_valor (um valor por mês) e populacao_anual; procedure sp_calcular_indicadores. | Alta | Transforma dado bruto em informação comparável entre cidades. |
| RF05 | Definir as METAS por formulário, com responsáveis claros: o GESTOR propõe (valor, cidade ou todas, início, justificativa e referência técnica), um ANALISTA credenciado da área dá parecer técnico e OUTRO gestor aprova. A meta vale a partir de uma data e a anterior fica no histórico. | Tabela meta (vigência e status); procedures sp_propor_meta, sp_parecer_meta e sp_decidir_meta (transação); função fn_meta_vigente; view vw_metas; trigger trg_meta_bu. | Alta | As metas são a régua do índice: precisam de dono, justificativa e histórico. |
| RF06 | Gerar o Índice EcoCity de Sustentabilidade (IES, 0 a 100) de cada mês e o ranking, com variação contra o mês anterior e o mesmo mês do ano passado. | Funções fn_score e fn_classe_ies; views vw_ies_municipio_mensal e vw_ies_ranking (LAG 1 e 12). | Alta | Resume o desempenho da cidade em um número. |
| RF07 | Manter um Data Warehouse com grão MENSAL (24 meses) para os painéis. | Modelo estrela com dim_tempo mensal (mês, trimestre, semestre, ano), 5 dimensões e 2 fatos; sp_carga_dw; evento ev_pipeline_mensal. | Alta | Entrega prevista no tema 18. |
| RF08 | Oferecer uma página PRÓPRIA para cada perfil, com visual e conteúdo diferentes: cidadão (Minha cidade), analista (Laboratório de dados), gestor (Sala de situação) e administrador (Central do sistema). | Views de consumo por perfil + API REST com login JWT; rotas /public/cidadao, /dados e /admin. | Alta | Cada público precisa de um nível de detalhe. |
| RF09 | Cadastro diferente por perfil. CIDADÃO: simples (nome, e-mail, telefone opcional, cidade e senha) e entra na hora. ANALISTA e GESTOR: cadastro completo (CPF válido, e-mail institucional do órgão, telefone, órgão, cargo, matrícula, formação, registro no conselho ou portaria de nomeação, documento de vínculo, justificativa e aceite do termo) que fica EM ANÁLISE até o ADMINISTRADOR conferir e aprovar, com validade de 1 ano. ADMINISTRADOR: não se cadastra pelo site; só o DBA cria, com uma CHAVE INDIVIDUAL exigida no login. | Tabela cadastro_profissional (CPF guardado só como hash); colunas status_cadastro, telefone e chave_admin_hash em usuario; procedures sp_cadastrar_cidadao, sp_solicitar_acesso, sp_analisar_cadastro e sp_criar_admin; função fn_cpf_valido; triggers trg_usuario_bi/bu; view vw_cadastros_profissionais. | Alta | Só pessoas identificadas e com vínculo comprovado acessam dados de gestão e publicam informações. |
| RF10 | Registrar ações e medir o resultado de cada uma (mês anterior ao início × último mês) para saber o que funcionou. | Tabelas acao e resultado; procedure transacional sp_registrar_resultado; view vw_acoes_resultados. | Alta | Fecha o ciclo dado → decisão → resultado. |
| RF11 | Emitir alertas automáticos quando um indicador ficar mais de 40% distante da meta. | Trigger trg_indicador_valor_ai chama sp_avaliar_alerta_meta e grava em analise_ia (ALERTA_META). | Média | Agiliza a reação a problemas. |
| RF12 | Gerar análises de IA sobre as séries mensais (tendência contra o mesmo mês do ano anterior, previsão e mudança brusca), validadas por um analista. | Tabela analise_ia com status e revisada_por; módulo Python lê as séries do banco. | Média | Apoia a análise sem substituir o analista. |
| RF13 | Credenciar os analistas: órgão de vínculo, registro profissional, área e nível, conferidos pelo administrador e com validade anual. Só analista com cadastro aprovado E credencial verificada publica análises e dá parecer em metas. | Tabela credencial_analista; procedure sp_verificar_credencial; função fn_analista_habilitado; view vw_confiabilidade_analista. | Média | Garante que só profissionais identificados assinem análises. |
| RF14 | Permitir que analistas PUBLIQUEM análises para os colegas, com evidências do banco, nível de confiança calculado e revisão por outra pessoa antes de aparecer para todos; colegas podem comentar. | Tabelas analise_publicada, analise_municipio, analise_evidencia e analise_comentario; procedures sp_enviar_analise e sp_revisar_analise; views vw_analises_publicadas e vw_fila_revisao_analises. | Média | Compartilha conhecimento entre analistas sem perder a confiabilidade. |
| RF15 | Copiloto EcoCity — relatório automático: o usuário ESCOLHE as cidades (uma ou várias) e o intervalo de MESES/anos; a IA escreve o relatório em português (versão gestor ou cidadão), só com dados do banco, avisando o que é estimado; publica só após aprovação de outra pessoa. | Tabelas relatorio_ia e relatorio_municipio (N:N); sp_copiloto_dados, sp_salvar_relatorio (transação) e sp_revisar_relatorio; trigger trg_relatorio_bu. | Média | Diferencial do projeto: poupa horas do gestor e leva a informação ao cidadão. |
| RF16 | Copiloto EcoCity — perguntas em português: o analista ou gestor pergunta, a IA gera um SELECT, o banco responde e a tela mostra a resposta e a consulta usada. | Tabela pergunta_ia (pergunta, SQL gerado, resposta, bloqueada, motivo); usuário ecocity_ia só com SELECT nas views. | Média | Diferencial: quem não sabe SQL também consegue consultar o banco. |
| RF17 | Oferecer ao cidadão um painel público MUITO SIMPLES, sem gráficos complexos: nota de 0 a 100, sinal verde/amarelo/vermelho, frases do dia a dia, comparação com o ano passado e dicas, sem dados pessoais. | View vw_painel_cidadao (sinal, frase e comparação de 12 meses) e vw_relatorios_publicados; papel r_cidadao só com leitura delas. | Média | Transparência e engajamento da comunidade. |
| RF18 | Monitorar a qualidade e a atualização de cada fonte de dados (governança). | View vw_qualidade_fontes; histórico em lote_carga. | Média | Mostra onde os dados estão incompletos. |
| RF19 | Emitir relatórios comparativos com filtro de cidades e de intervalo de meses (drill-down mês → trimestre → ano). | Consultas com variáveis de filtro, GROUP BY ROLLUP, LAG e média móvel de 3 meses sobre o DW (script 08). | Baixa | Complementa os dashboards. |

## Requisitos não funcionais

| ID | Requisito | Onde é atendido | Prioridade |
|---|---|---|---|
| RNF01 | SGBD MySQL 8 com o banco publicado na Oracle Cloud (MySQL HeatWave). | Requisito de entrega da A3. | Alta |
| RNF02 | Integridade: camada core em 3FN, com PK, FK, UNIQUE, CHECK e ENUM em todas as tabelas. | DER + script 01. | Alta |
| RNF03 | Segurança: papéis do MySQL com menor privilégio e segregação de funções (quem cria não aprova: metas, análises e relatórios), conexão com TLS. | Script 06 + JWT na API. | Alta |
| RNF04 | Login seguro: senha com hash bcrypt (cidadão: 8+ caracteres; analista e gestor: 12+ com maiúscula, número e símbolo), 2ª etapa obrigatória (código do aplicativo autenticador) para analista, gestor e admin, chave individual extra para o admin, bloqueio de 15 min após 5 erros, validade da senha por perfil e registro de toda tentativa. | Tabela acesso_log; colunas de segurança em usuario e perfil; procedure sp_registrar_login. | Alta |
| RNF05 | IA segura: o Copiloto só lê views permitidas; toda consulta gerada é checada (apenas SELECT, sem ponto e vírgula extra, com LIMIT e tempo máximo) e as bloqueadas ficam registradas. | Usuário ecocity_ia + validação na API + tabela pergunta_ia. | Alta |
| RNF06 | Transparência: todo número exibido ou citado pela IA indica se é oficial ou estimado e a fonte. | dado.origem, indicador_valor.origem e views. | Alta |
| RNF07 | Transações ACID: procedures críticas com START TRANSACTION, COMMIT e ROLLBACK automático. | Script 05. | Alta |
| RNF08 | Auditoria: toda alteração de dados, ações, metas, análises e relatórios da IA fica registrada (quem, quando, antes e depois). | Triggers + tabela auditoria (JSON). | Alta |
| RNF09 | Rastreabilidade: cada dado mensal ligado à sua fonte, ao lote de carga e à referência de origem; cada relatório da IA guarda os números que usou. | FKs id_fonte e id_lote em dado; relatorio_ia.dados_usados. | Alta |
| RNF10 | Recuperação: backup diário com retenção de 35 dias e PITR; RPO ≤ 24 h (≈ 5 min com PITR) e RTO ≤ 1 h. | Plano de backup (script 09). | Alta |
| RNF11 | LGPD: coletar o mínimo de dados pessoais; cidadão vê apenas dados agregados. | Views públicas sem dados pessoais. | Alta |
| RNF12 | Desempenho: consultas dos dashboards em menos de 2 s. | Índices compostos + DW pré-agregado. | Média |
| RNF13 | Escalabilidade: incluir nova cidade, fonte, métrica ou indicador sem alterar a estrutura das tabelas. | Modelo orientado a metadados. | Média |
| RNF14 | Usabilidade: páginas diferentes por perfil, para desktop, acessíveis (fonte Atkinson Hyperlegible no painel do cidadão), com tema claro e escuro. | Frontend. | Média |

## SGBD e tecnologias

| Camada | Tecnologia | Justificativa |
|---|---|---|
| Banco de dados | MySQL 8.0 (InnoDB, utf8mb4) | Exigido pela A3. Tem transações ACID, FKs, CHECK, triggers, procedures, eventos, CTEs, window functions e papéis (roles). |
| Nuvem | Oracle Cloud Infrastructure: MySQL HeatWave + Compute + Object Storage + Vault | Exigido pela A3. HeatWave é o MySQL gerenciado da Oracle, com backup automático e PITR. |
| Modelagem | draw.io (DER conceitual, notação de Chen com (mín,máx)) + MySQL Workbench | draw.io é gratuito e online; o Workbench cria e testa os scripts no banco. |
| Integração (ETL) | Staging no próprio MySQL + stored procedures + Event Scheduler | A validação acontece dentro do banco, com transação e rastreio por lote. |
| Backend | Node.js 22 + Express, mysql2, JWT, bcrypt, Helmet, rate limit | API leve, consultas parametrizadas (evita SQL injection) e controle por perfil. |
| Frontend | HTML, CSS e JavaScript, gráficos em SVG próprios | Sem bibliotecas extras; abre em qualquer navegador. |
| Inteligência Artificial | Python 3 + NumPy (tendência, anomalia e previsão) + Copiloto (perguntas em português viram SQL; API Claude opcional) | Técnicas simples e explicáveis; o resultado volta para o banco e todo relatório da IA precisa de aprovação humana. |
| Versionamento | Git + GitHub | Repositório exigido na entrega (scripts SQL, código e documentação). |
