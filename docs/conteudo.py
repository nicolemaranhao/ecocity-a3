"""Conteúdo compartilhado entre a documentação (Markdown) e o Checkpoint 2 (DOCX)."""

PROJETO = "EcoCity — Data Warehouse para Comunidades Sustentáveis (Cidades Inteligentes)"
TEMA = "Tema 18 · BD para Comunidades Sustentáveis (Cidades Inteligentes)"
INTEGRANTES = [("Gabriela Sant’Ana Merces Assis", "12525218204"), ("Nicole Maranhão Assis", "12525141079")]
DATA_CP2 = "20/10/2026"

# (id, requisito, uso do banco de dados, prioridade, justificativa da prioridade)
RF = [
    ('RF01', 'Integrar em um único banco, MÊS A MÊS, os dados de água, energia, resíduos e mobilidade de 8 cidades de SP (out/2024 a set/2026), vindos de fontes e formatos diferentes (IBGE, ANEEL, EPE, SPTrans, SNIS/SINISA, SEEG, Prefeitura de SP; APIs, planilhas, parquet e PDFs).', 'Tabelas stg_medicao_bruta, lote_carga, fonte_dados, orgao e dado; procedure sp_processar_staging.', 'Alta', 'É o problema central do tema: dados fragmentados.'),
    ('RF02', 'Validar cada dado recebido e rejeitar, com o motivo registrado, valores inválidos, municípios ou métricas desconhecidos e datas fora do padrão.', 'CHECK constraints, trigger trg_dado_bi (marca SUSPEITO) e coluna erro no staging.', 'Alta', 'Decisões só são boas com dados confiáveis.'),
    ('RF03', 'Identificar a origem de cada número (OFICIAL do mês, CALCULADO a partir de total oficial ou ESTIMADO), com a fonte, e permitir trocar pelo oficial quando ele for publicado.', 'Colunas dado.origem e referencia_origem; view vw_origem_dados; procedure sp_atualizar_dado_real.', 'Alta', 'Transparência: o gestor sabe o quanto pode confiar em cada número.'),
    ('RF04', 'Calcular TODO MÊS 8 indicadores de sustentabilidade por município (ISO 37120 / ODS 6, 7, 11, 12 e 13), usando a população oficial do ano.', 'Tabelas indicador, indicador_valor (um valor por mês) e populacao_anual; procedure sp_calcular_indicadores.', 'Alta', 'Transforma dado bruto em informação comparável entre cidades.'),
    ('RF05', 'Definir as METAS por formulário, com responsáveis claros: o GESTOR propõe (valor, cidade ou todas, início, justificativa e referência técnica), um ANALISTA credenciado da área dá parecer técnico e OUTRO gestor aprova. A meta vale a partir de uma data e a anterior fica no histórico.', 'Tabela meta (vigência e status); procedures sp_propor_meta, sp_parecer_meta e sp_decidir_meta (transação); função fn_meta_vigente; view vw_metas; trigger trg_meta_bu.', 'Alta', 'As metas são a régua do índice: precisam de dono, justificativa e histórico.'),
    ('RF06', 'Gerar o Índice EcoCity de Sustentabilidade (IES, 0 a 100) de cada mês e o ranking, com variação contra o mês anterior e o mesmo mês do ano passado.', 'Funções fn_score e fn_classe_ies; views vw_ies_municipio_mensal e vw_ies_ranking (LAG 1 e 12).', 'Alta', 'Resume o desempenho da cidade em um número.'),
    ('RF07', 'Manter um Data Warehouse com grão MENSAL (24 meses) para os painéis.', 'Modelo estrela com dim_tempo mensal (mês, trimestre, semestre, ano), 5 dimensões e 2 fatos; sp_carga_dw; evento ev_pipeline_mensal.', 'Alta', 'Entrega prevista no tema 18.'),
    ('RF08', 'Oferecer uma página PRÓPRIA para cada perfil, com visual e conteúdo diferentes: cidadão (Minha cidade), analista (Laboratório de dados), gestor (Sala de situação) e administrador (Central do sistema).', 'Views de consumo por perfil + API REST com login JWT; rotas /public/cidadao, /dados e /admin.', 'Alta', 'Cada público precisa de um nível de detalhe.'),
    ('RF09', 'Cadastro diferente por perfil. CIDADÃO: simples (nome, e-mail, telefone opcional, cidade e senha) e entra na hora. ANALISTA e GESTOR: cadastro completo (CPF válido, e-mail institucional do órgão, telefone, órgão, cargo, matrícula, formação, registro no conselho ou portaria de nomeação, documento de vínculo, justificativa e aceite do termo) que fica EM ANÁLISE até o ADMINISTRADOR conferir e aprovar, com validade de 1 ano. ADMINISTRADOR: não se cadastra pelo site; só o DBA cria, com uma CHAVE INDIVIDUAL exigida no login.', 'Tabela cadastro_profissional (CPF guardado só como hash); colunas status_cadastro, telefone e chave_admin_hash em usuario; procedures sp_cadastrar_cidadao, sp_solicitar_acesso, sp_analisar_cadastro e sp_criar_admin; função fn_cpf_valido; triggers trg_usuario_bi/bu; view vw_cadastros_profissionais.', 'Alta', 'Só pessoas identificadas e com vínculo comprovado acessam dados de gestão e publicam informações.'),
    ('RF10', 'Registrar ações e medir o resultado de cada uma (mês anterior ao início × último mês) para saber o que funcionou.', 'Tabelas acao e resultado; procedure transacional sp_registrar_resultado; view vw_acoes_resultados.', 'Alta', 'Fecha o ciclo dado → decisão → resultado.'),
    ('RF11', 'Emitir alertas automáticos quando um indicador ficar mais de 40% distante da meta.', 'Trigger trg_indicador_valor_ai chama sp_avaliar_alerta_meta e grava em analise_ia (ALERTA_META).', 'Média', 'Agiliza a reação a problemas.'),
    ('RF12', 'Gerar análises de IA sobre as séries mensais (tendência contra o mesmo mês do ano anterior, previsão e mudança brusca), validadas por um analista.', 'Tabela analise_ia com status e revisada_por; módulo Python lê as séries do banco.', 'Média', 'Apoia a análise sem substituir o analista.'),
    ('RF13', 'Credenciar os analistas: órgão de vínculo, registro profissional, área e nível, conferidos pelo administrador e com validade anual. Só analista com cadastro aprovado E credencial verificada publica análises e dá parecer em metas.', 'Tabela credencial_analista; procedure sp_verificar_credencial; função fn_analista_habilitado; view vw_confiabilidade_analista.', 'Média', 'Garante que só profissionais identificados assinem análises.'),
    ('RF14', 'Permitir que analistas PUBLIQUEM análises para os colegas, com evidências do banco, nível de confiança calculado e revisão por outra pessoa antes de aparecer para todos; colegas podem comentar.', 'Tabelas analise_publicada, analise_municipio, analise_evidencia e analise_comentario; procedures sp_enviar_analise e sp_revisar_analise; views vw_analises_publicadas e vw_fila_revisao_analises.', 'Média', 'Compartilha conhecimento entre analistas sem perder a confiabilidade.'),
    ('RF15', 'Copiloto EcoCity — relatório automático: o usuário ESCOLHE as cidades (uma ou várias) e o intervalo de MESES/anos; a IA escreve o relatório em português (versão gestor ou cidadão), só com dados do banco, avisando o que é estimado; publica só após aprovação de outra pessoa.', 'Tabelas relatorio_ia e relatorio_municipio (N:N); sp_copiloto_dados, sp_salvar_relatorio (transação) e sp_revisar_relatorio; trigger trg_relatorio_bu.', 'Média', 'Diferencial do projeto: poupa horas do gestor e leva a informação ao cidadão.'),
    ('RF16', 'Copiloto EcoCity — perguntas em português: o analista ou gestor pergunta, a IA gera um SELECT, o banco responde e a tela mostra a resposta e a consulta usada.', 'Tabela pergunta_ia (pergunta, SQL gerado, resposta, bloqueada, motivo); usuário ecocity_ia só com SELECT nas views.', 'Média', 'Diferencial: quem não sabe SQL também consegue consultar o banco.'),
    ('RF17', 'Oferecer ao cidadão um painel público MUITO SIMPLES, sem gráficos complexos: nota de 0 a 100, sinal verde/amarelo/vermelho, frases do dia a dia, comparação com o ano passado e dicas, sem dados pessoais.', 'View vw_painel_cidadao (sinal, frase e comparação de 12 meses) e vw_relatorios_publicados; papel r_cidadao só com leitura delas.', 'Média', 'Transparência e engajamento da comunidade.'),
    ('RF18', 'Monitorar a qualidade e a atualização de cada fonte de dados (governança).', 'View vw_qualidade_fontes; histórico em lote_carga.', 'Média', 'Mostra onde os dados estão incompletos.'),
    ('RF19', 'Emitir relatórios comparativos com filtro de cidades e de intervalo de meses (drill-down mês → trimestre → ano).', 'Consultas com variáveis de filtro, GROUP BY ROLLUP, LAG e média móvel de 3 meses sobre o DW (script 08).', 'Baixa', 'Complementa os dashboards.'),
]

RNF = [
    ('RNF01', 'SGBD MySQL 8 com o banco publicado na Oracle Cloud (MySQL HeatWave).', 'Requisito de entrega da A3.', 'Alta'),
    ('RNF02', 'Integridade: camada core em 3FN, com PK, FK, UNIQUE, CHECK e ENUM em todas as tabelas.', 'DER + script 01.', 'Alta'),
    ('RNF03', 'Segurança: papéis do MySQL com menor privilégio e segregação de funções (quem cria não aprova: metas, análises e relatórios), conexão com TLS.', 'Script 06 + JWT na API.', 'Alta'),
    ('RNF04', 'Login seguro: senha com hash bcrypt (cidadão: 8+ caracteres; analista e gestor: 12+ com maiúscula, número e símbolo), 2ª etapa obrigatória (código do aplicativo autenticador) para analista, gestor e admin, chave individual extra para o admin, bloqueio de 15 min após 5 erros, validade da senha por perfil e registro de toda tentativa.', 'Tabela acesso_log; colunas de segurança em usuario e perfil; procedure sp_registrar_login.', 'Alta'),
    ('RNF05', 'IA segura: o Copiloto só lê views permitidas; toda consulta gerada é checada (apenas SELECT, sem ponto e vírgula extra, com LIMIT e tempo máximo) e as bloqueadas ficam registradas.', 'Usuário ecocity_ia + validação na API + tabela pergunta_ia.', 'Alta'),
    ('RNF06', 'Transparência: todo número exibido ou citado pela IA indica se é oficial ou estimado e a fonte.', 'dado.origem, indicador_valor.origem e views.', 'Alta'),
    ('RNF07', 'Transações ACID: procedures críticas com START TRANSACTION, COMMIT e ROLLBACK automático.', 'Script 05.', 'Alta'),
    ('RNF08', 'Auditoria: toda alteração de dados, ações, metas, análises e relatórios da IA fica registrada (quem, quando, antes e depois).', 'Triggers + tabela auditoria (JSON).', 'Alta'),
    ('RNF09', 'Rastreabilidade: cada dado mensal ligado à sua fonte, ao lote de carga e à referência de origem; cada relatório da IA guarda os números que usou.', 'FKs id_fonte e id_lote em dado; relatorio_ia.dados_usados.', 'Alta'),
    ('RNF10', 'Recuperação: backup diário com retenção de 35 dias e PITR; RPO ≤ 24 h (≈ 5 min com PITR) e RTO ≤ 1 h.', 'Plano de backup (script 09).', 'Alta'),
    ('RNF11', 'LGPD: coletar o mínimo de dados pessoais; cidadão vê apenas dados agregados.', 'Views públicas sem dados pessoais.', 'Alta'),
    ('RNF12', 'Desempenho: consultas dos dashboards em menos de 2 s.', 'Índices compostos + DW pré-agregado.', 'Média'),
    ('RNF13', 'Escalabilidade: incluir nova cidade, fonte, métrica ou indicador sem alterar a estrutura das tabelas.', 'Modelo orientado a metadados.', 'Média'),
    ('RNF14', 'Usabilidade: páginas diferentes por perfil, para desktop, acessíveis (fonte Atkinson Hyperlegible no painel do cidadão), com tema claro e escuro.', 'Frontend.', 'Média'),
]

NOTA_REQUISITOS = ("Os nomes citados na coluna “Uso do banco de dados” são objetos reais do banco ecocity "
                   "(scripts na pasta sql/ do repositório) e aparecem com evidências na seção 6.")

TECNOLOGIAS = [
    ("Banco de dados", "MySQL 8.0", "Exigido pela A3; garante dados corretos e controle de acesso."),
    ("Nuvem", "Oracle Cloud (MySQL HeatWave)", "Exigido pela A3; MySQL gerenciado com backup automático."),
    ("Modelagem", "draw.io + MySQL Workbench", "draw.io para o DER; Workbench para criar e testar os scripts."),
    ("Carga dos dados", "Procedures + evento mensal no MySQL", "Os dados são conferidos dentro do banco e carregados todo mês."),
    ("Backend", "Node.js + Express", "Liga as telas ao banco, com login seguro."),
    ("Frontend", "HTML, CSS e JavaScript", "Simples e abre em qualquer navegador."),
    ("Inteligência Artificial", "Python + Copiloto", "Gera alertas e relatórios; nada é publicado sem aprovação."),
    ("Versionamento", "Git + GitHub", "Guarda os scripts e códigos do projeto."),
]

# (artefato, camada, arquivo(s), situação)
ARTEFATOS = [
    ("DER preliminar (modelo conceitual, notação de Chen com cardinalidade mín/máx)", "Banco de dados", "draw.io", "Concluído"),
    ("Levantamento dos dados reais: 8 cidades de SP, mês a mês (out/2024 a set/2026), com a fonte de cada número", "Banco de dados", "dados_reais/EcoCity_dados_municipios_SP.xlsx", "Concluído"),
    ("Banco ecocity no MySQL: tabelas, chaves, regras (CHECK), índices, views, triggers e procedures", "Banco de dados", "sql/01 a 06", "Concluído"),
    ("Carga dos dados mensais (1.536 medições) e consultas de relatório", "Banco de dados", "sql/07 e sql/08", "Concluído"),
    ("Testes de integridade (as regras bloqueiam dados errados)", "Banco de dados", "sql/10_testes_integridade.sql", "Concluído"),
    ("API: login seguro, dados por perfil, metas, análises, alertas, ações e Copiloto", "Backend", "backend/src", "Concluído"),
    ("Telas por perfil (cidadão, analista, gestor e administrador)", "Frontend", "frontend/index.html", "Em desenvolvimento"),
]

# Cronograma do Checkpoint 2: só o que foi feito até agora (o consolidado até o fim vai no Checkpoint 3)
# (atividade, data, responsável, dependência, impedimentos, status)
# status: C=Concluído, D=Em desenvolvimento, P=Pendente, X=Cancelado, N=Não iniciado
CRONOGRAMA = [
    ('1. Escolha do tema, diagnóstico e entidades principais (Checkpoint 1 + LinkedIn)', '01/09/2026', 'Gabriela e Nicole', '—', '', 'C'),
    ('2. Levantamento e priorização dos requisitos', '10/10/2026', 'Gabriela', 'Checkpoint 1', '', 'C'),
    ('3. Coleta dos dados reais mensais (ANEEL, SPTrans, EPE, SNIS/SINISA, SEEG, IBGE)', '15/10/2026', 'Nicole', 'Requisitos', 'Algumas fontes só publicam dados anuais (usamos estimativas identificadas)', 'C'),
    ('4. Definição do SGBD (MySQL) e das tecnologias', '10/10/2026', 'Gabriela', 'Requisitos', '', 'C'),
    ('5. DER (modelo conceitual completo, draw.io)', '16/10/2026', 'Nicole', 'Requisitos + entidades', '', 'C'),
    ('6. Criação do banco no MySQL (tabelas, regras, views, triggers, procedures)', '16/10/2026', 'Gabriela', 'DER preliminar', '', 'C'),
    ('7. Backend (API com login em 2 etapas, cadastros, metas e análises)', '16/10/2026', 'Nicole', 'Banco criado', '', 'C'),
    ('8. Entrega do Checkpoint 2 + post no LinkedIn', '20/10/2026', 'Gabriela e Nicole', 'Atividades 2 a 7', '', 'C'),
]
STATUS = {"C": ("Concluído", "00B050"), "D": ("Em desenvolvimento", "00B0F0"), "P": ("Pendente", "EE0000"),
          "X": ("Cancelado", "7030A0"), "N": ("Não iniciado", "BFBFBF")}
