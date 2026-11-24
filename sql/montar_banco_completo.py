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

# ---------------------------------------------------------------------------------------------
# Versão para bancos GERENCIADOS na nuvem (Aiven, e parecidos): o usuário administrador
# (avnadmin) não tem o privilégio ROLE_ADMIN, então não consegue "dar um papel" a um usuário
# (GRANT r_gestor TO ecocity_api). Os papéis continuam sendo criados com as permissões, e as
# MESMAS permissões são dadas também direto a cada usuário. O resultado de acesso é o mesmo.
import re
USUARIOS_DO_PAPEL = {   # inclui a herança: r_bi -> r_analista -> r_gestor -> ecocity_api
    'r_cidadao': ["'ecocity_api'@'%'"], 'r_gestor': ["'ecocity_api'@'%'"], 'r_analista': ["'ecocity_api'@'%'"],
    'r_bi': ["'ecocity_bi'@'%'", "'ecocity_api'@'%'"], 'r_etl': ["'ecocity_etl'@'%'"], 'r_dba': ["'ecocity_dba'@'%'"], 'r_ia': ["'ecocity_ia'@'%'"],
}
seg = (P / '06_seguranca.sql').read_text(encoding='utf-8')
# separa em comandos (terminam com ';' no fim da linha)
cmds, atual = [], []
for linha in seg.splitlines(keepends=True):
    atual.append(linha)
    if re.search(r";\s*(--.*)?$", linha.rstrip('\n')):
        cmds.append(''.join(atual)); atual = []
cmds.append(''.join(atual))
grants_de_papel, saida = [], []
for c in cmds:
    corpo = re.sub(r'--[^\n]*', '', c).strip()
    if re.match(r'(?is)^GRANT\s+r_\w+(\s*,\s*r_\w+)*\s+TO\b', corpo) or re.match(r'(?is)^SET\s+DEFAULT\s+ROLE', corpo):
        saida.append('-- (Aiven) ' + c.strip().replace('\n', '\n-- ') + '\n'); continue
    saida.append(c)
    m = re.match(r'(?is)^(GRANT\s+.+?\s+TO\s+)(r_\w+)\s*;$', corpo)
    if m and m.group(2) in USUARIOS_DO_PAPEL:
        for u in USUARIOS_DO_PAPEL[m.group(2)]:
            grants_de_papel.append(f"{m.group(1)}{u};")
seg_aiven = ''.join(saida).replace("SHOW GRANTS FOR 'ecocity_api'@'%' USING r_gestor, r_cidadao;", "SHOW GRANTS FOR 'ecocity_api'@'%';").replace("SHOW GRANTS FOR 'ecocity_ia'@'%' USING r_ia;", "SHOW GRANTS FOR 'ecocity_ia'@'%';")
# as permissões dos papéis vão direto para os usuários logo depois que eles são criados
marca = "GRANT EXECUTE ON PROCEDURE ecocity.sp_registrar_login TO 'ecocity_api'@'%';"
assert marca in seg_aiven
seg_aiven = seg_aiven.replace(marca, "-- (Aiven) mesmas permissões dos papéis, dadas direto a cada usuário\n" + "\n".join(grants_de_papel) + "\n" + marca, 1)
CAB_AIVEN = CAB.replace("BANCO COMPLETO EM UM ÚNICO ARQUIVO (para o MySQL Workbench)", "BANCO COMPLETO PARA A NUVEM (Aiven for MySQL)") \
    .replace("--  Como usar: File > Open SQL Script... > escolha este arquivo > clique no raio",
             "--  Como usar: conecte no Workbench com o usuário avnadmin (SSL obrigatório) > abra este arquivo > raio.\n"
             "--  Diferença para a versão local: os papéis (roles) são criados, mas as permissões também vão\n"
             "--  direto para cada usuário, porque o avnadmin não pode conceder papéis (falta ROLE_ADMIN).")
MODO = "SET SESSION sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';   -- mesmo modo do MySQL local (o da nuvem pode ser diferente)\n"
partes_a = [CAB_AIVEN + MODO]
for a in ARQS:
    partes_a.append(f"\n-- >>>>>>>>>>>>>>>>>>>> {a} <<<<<<<<<<<<<<<<<<<<\n")
    txt = (P / a).read_text(encoding='utf-8')
    if a == '06_seguranca.sql':
        txt = seg_aiven
    else:   # nos outros scripts os usuários já existem: repete cada GRANT de papel logo em seguida para os usuários
        def repete(m):
            return m.group(0) + ''.join(f"\n{m.group(1)}{u};   -- (Aiven) direto ao usuário" for u in USUARIOS_DO_PAPEL.get(m.group(2), []))
        txt = re.sub(r'(?m)^(GRANT\s+[^;]+?\s+TO\s+)(r_\w+)\s*;', repete, txt)
    partes_a.append(txt)
partes_a.append(ROD)
(P / 'ecocity_banco_aiven.sql').write_text(''.join(partes_a), encoding='utf-8')
print('ok')
