"""Junta os scripts 01..07c num único arquivo para abrir no MySQL Workbench (ecocity_banco_completo.sql)."""
import pathlib
P = pathlib.Path(__file__).parent
ARQS = ['01_create_database_tabelas.sql', '02_indices.sql', '03_funcoes_views.sql', '04_triggers.sql',
        '05_procedures_eventos.sql', '06_seguranca.sql', '07_dados_teste.sql', '07b_insights_ia.sql', '07c_copiloto_exemplos.sql', '11_coleta_automatica.sql']
CAB = """-- =====================================================================
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
"""
ROD = """
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
"""
partes = [CAB]
for a in ARQS:
    partes.append(f"\n-- >>>>>>>>>>>>>>>>>>>> {a} <<<<<<<<<<<<<<<<<<<<\n")
    partes.append((P / a).read_text(encoding='utf-8'))
partes.append(ROD)
(P / 'ecocity_banco_completo.sql').write_text(''.join(partes), encoding='utf-8')
print('ok')
