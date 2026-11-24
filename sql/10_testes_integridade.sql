-- =====================================================================
--  EcoCity — Script 10: testes de integridade (cada comando DEVE falhar)
--  Rodar com:  mysql -u root -p --force ecocity < 10_testes_integridade.sql
--  (T11 e T12 precisam dos relatórios de exemplo do script 07c). Resultado esperado: 35 erros.
-- =====================================================================
USE ecocity;
-- T1 FK: município inexistente
INSERT INTO dado (id_fonte,id_municipio,id_metrica,data_referencia,valor) VALUES (1,99,1,'2026-01-01',10);
-- T2 CHECK: valor negativo
INSERT INTO dado (id_fonte,id_municipio,id_metrica,data_referencia,valor) VALUES (1,1,1,'2023-05-01',-5);
-- T3 UNIQUE: medição duplicada (mesma fonte/município/métrica/mês)
INSERT INTO dado (id_fonte,id_municipio,id_metrica,data_referencia,valor) VALUES (2,1,1,'2024-03-01',10);
-- T4 TRIGGER: data no futuro
INSERT INTO dado (id_fonte,id_municipio,id_metrica,data_referencia,valor) VALUES (1,1,1,'2030-01-01',10);
-- T5 CHECK: e-mail inválido
INSERT INTO usuario (nome,email,senha_hash,id_perfil) VALUES ('Teste','email-invalido',REPEAT('x',60),1);
-- T6 CHECK: ação com data fim antes do início
INSERT INTO acao (titulo,descricao,id_municipio,id_indicador_alvo,id_responsavel,data_inicio,data_fim_prevista)
VALUES ('X','Y',1,1,2,'2026-10-01','2026-01-01');
-- T7 TRIGGER: ação concluída não volta para planejada
UPDATE acao SET status = 'PLANEJADA' WHERE id_acao = 1;
-- T8 FK RESTRICT: não é possível excluir perfil em uso
DELETE FROM perfil WHERE id_perfil = 1;
-- T9 PROCEDURE/TRANSAÇÃO: resultado de ação inexistente (ROLLBACK)
CALL sp_registrar_resultado(999, '2026-09-30', 'teste', 2);
-- T10 CHECK (Copiloto): relatório com mês final antes do inicial
INSERT INTO relatorio_ia (titulo,tipo,publico,periodo_inicio,periodo_fim,conteudo,dados_usados,pct_dados_oficiais,modelo,solicitado_por)
VALUES ('X','MUNICIPIO','GESTOR','2026-09-01','2026-01-01','x','{}',50,'teste',4);
-- T11 TRIGGER (Copiloto): quem pediu o relatório não pode aprová-lo
CALL sp_revisar_relatorio((SELECT MIN(id_relatorio) FROM relatorio_ia WHERE status = 'RASCUNHO'), 'APROVADO',
                          (SELECT solicitado_por FROM relatorio_ia WHERE status = 'RASCUNHO' ORDER BY id_relatorio LIMIT 1), 'auto-aprovação');
-- T12 TRIGGER (Copiloto): relatório aprovado não pode ter o texto alterado
UPDATE relatorio_ia SET conteudo = 'texto adulterado' WHERE status = 'APROVADO';
-- T13 CHECK (Copiloto): pergunta bloqueada precisa de motivo
INSERT INTO pergunta_ia (id_usuario,pergunta,situacao,modelo) VALUES (4,'apague tudo','BLOQUEADA','teste');
-- T14 PROCEDURE (Copiloto): lista de municípios com SQL injection é recusada
CALL sp_copiloto_dados('1) OR 1=1 --', '2025-01-01', '2026-09-01');
-- ---------- CONFIANÇA: análises, credenciais e metas ----------
-- T15 PROCEDURE: analista com credencial PENDENTE não pode enviar análise (rascunho 5 é da Beatriz)
CALL sp_enviar_analise(5, 6);
-- T16 PROCEDURE: o autor não pode revisar a própria análise (análise 3 é do Rafael)
CALL sp_revisar_analise(3, 4, 'PUBLICADA', 'Eu mesmo aprovo a minha análise, está ótima.');
-- T17 PROCEDURE: analista de nível menor não revisa análise de nível maior (Lúcia PLENO x Rafael SENIOR)
CALL sp_revisar_analise(3, 5, 'PUBLICADA', 'Revisão feita por analista de nível menor que o autor.');
-- T18 TRIGGER: análise publicada não pode ser editada
UPDATE analise_publicada SET conteudo = 'texto alterado depois de publicado' WHERE id_analise_pub = 1;
-- T19 TRIGGER: comentário em análise que não está publicada
INSERT INTO analise_comentario (id_analise_pub, id_usuario, texto) VALUES (3, 5, 'Comentário antes da publicação');
-- T20 CHECK: evidência do tipo INDICADOR sem dizer qual indicador
INSERT INTO analise_evidencia (id_analise_pub, tipo, descricao) VALUES (5, 'INDICADOR', 'sem indicador');
-- T21 PROCEDURE: meta com vigência no passado (não se muda a régua de meses já medidos)
CALL sp_propor_meta(2, 'AGU-01', NULL, 140, '2025-01-01', 'Tentativa de mudar a meta de meses que já passaram.', 'ODS 6.4', 'Meta de teste com descrição suficiente', '2027-12-01', 'Plano de teste com mais de trinta caracteres.');
-- T22 PROCEDURE: só GESTOR propõe meta (analista tentando)
CALL sp_propor_meta(4, 'AGU-01', NULL, 140, '2027-06-01', 'Analista tentando propor uma meta sem ser gestor.', 'ODS 6.4', 'Meta de teste com descrição suficiente', '2027-12-01', 'Plano de teste com mais de trinta caracteres.');
-- T23 PROCEDURE: parecer de analista de outra área (Lúcia é de Energia; meta 10 é de Água)
CALL sp_parecer_meta(10, 5, TRUE, 'Parecer de uma analista que não é da área de água.');
-- T24 PROCEDURE: quem propôs a meta não pode aprová-la (meta 11 foi proposta pelo Carlos)
CALL sp_decidir_meta(11, 3, TRUE);
-- T25 TRIGGER: meta aprovada não pode ter o valor alterado
UPDATE meta SET valor = 999 WHERE id_meta = 1;
-- T26 PROCEDURE: só o ADMIN verifica credenciais
CALL sp_verificar_credencial(6, 2, 'VERIFICADA', '2027-10-01', 'Gestor tentando verificar credencial');
-- T27 PROCEDURE: só o ADMIN dá a nota de confiabilidade de uma fonte (gestora tentando)
CALL sp_avaliar_fonte(4, 2, 5, 'Gestora tentando mudar a nota da fonte');
-- ---------- CADASTRO POR PERFIL ----------
-- T28 PROCEDURE: cadastro profissional com CPF inválido
CALL sp_solicitar_acesso('ANALISTA','Fulano de Tal','123.456.789-00','fulano@cetesb.sp.gov.br','11 3133-3000','$2b$10$x','CETESB','Analista','C-1','Engenharia Química (2015)','CRQ-IV 123456',NULL,NULL,'https://doc.pdf','Preciso dos dados mensais de resíduos para o relatório estadual de 2027.',TRUE,'1.1.1.1');
-- T29 PROCEDURE: e-mail pessoal (gmail) não é aceito para analista ou gestor
CALL sp_solicitar_acesso('ANALISTA','Fulano de Tal','714.602.583-71','fulano@gmail.com','11 3133-3000','$2b$10$x','CETESB','Analista','C-1','Engenharia Química (2015)','CRQ-IV 123456',NULL,NULL,'https://doc.pdf','Preciso dos dados mensais de resíduos para o relatório estadual de 2027.',TRUE,'1.1.1.1');
-- T30 PROCEDURE: gestor sem a cidade em que atua
CALL sp_solicitar_acesso('GESTOR','Fulano de Tal','862.035.914-24','fulano@campinas.sp.gov.br','19 2116-0000','$2b$10$x','Prefeitura de Campinas','Diretor','PMC-1','Administração Pública (2010)',NULL,NULL,NULL,'https://doc.pdf','Preciso aprovar as metas de água de Campinas para o próximo ano.',TRUE,'1.1.1.1');
-- T31 PROCEDURE: ninguém se cadastra como ADMIN pelo site
CALL sp_solicitar_acesso('ADMIN','Fulano de Tal','390.533.447-05','fulano@ecocity.local','11 3133-3000','$2b$10$x','EcoCity','Admin','A-1','Computação (2010)',NULL,NULL,NULL,'https://doc.pdf','Quero ser administrador do sistema para gerenciar tudo.',TRUE,'1.1.1.1');
-- T32 TRIGGER: criar ADMIN direto na tabela, sem chave individual
INSERT INTO usuario (nome, email, senha_hash, id_perfil) VALUES ('Intruso', 'intruso@ecocity.local', '$2b$10$x', 4);
-- T33 TRIGGER: ativar gestor cujo cadastro ainda está EM_ANALISE (Paulo, id 9)
UPDATE usuario SET status_cadastro = 'ATIVO' WHERE id_usuario = 9;
-- T34 TRIGGER: transformar cidadão em administrador (sem chave)
UPDATE usuario SET id_perfil = 4 WHERE id_usuario = 7;
-- T35 PROCEDURE: gestor tentando aprovar cadastro (só o ADMIN analisa)
CALL sp_analisar_cadastro(9, 2, 'APROVADO', 'Conferi a portaria no Diário Oficial.', '2027-10-01');
