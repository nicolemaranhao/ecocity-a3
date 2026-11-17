"""
EcoCity — gerador do script 07_dados_teste.sql
8 municípios do Estado de São Paulo, dados MENSAIS de jan/2023 a set/2026 (45 meses).
Cada número usa o ÚLTIMO dado oficial publicado da sua fonte (coleta em 16/11/2026):

  REAL      -> número oficial publicado para aquele mês:
               energia solar das 8 cidades (ANEEL, até set/2026);
               passageiros de ônibus de São Paulo (SPTrans, até set/2026).
  DERIVADO  -> total oficial do ano dividido pelos meses:
               água 2023-2024 (SNIS) e Campinas 2025-jun/2026 (SANASA); resíduos 2023-2024 (SINISA);
               energia por cidade 2024 (e 2023 em SP, Guarulhos e Campinas) — Anuário de Energéticos (SEMIL-SP);
               resíduos de São Paulo 2023-2025, 1º sem. e jul-ago/2026 (SP Regula);
               emissões do transporte 2023-2025 (SEEG).
  ESTIMADO  -> a fonte ainda não publicou o período, ou não existe dado oficial da cidade:
               água e resíduos de 2025-2026 (a partir do último oficial, 2024);
               emissões de 2026 (a partir de 2025); energia por cidade 2025-2026 (último total oficial
               x variação oficial da EPE); passageiros das outras 7 cidades.
  Arquivos brutos: dados_reais/coleta/*.json e dados_reais/coleta_mensal/*.json
  Para trocar um estimado pelo oficial, no MySQL:
     CALL sp_atualizar_dado_real('Campinas', 2024, 3, 'ENERGIA_CONSUMIDA', 512345, 'CPFL mar/2024');

Uso:  python gerar_dados_teste.py > 07_dados_teste.sql
"""
import calendar
import json
import random
from pathlib import Path

random.seed(2026)
BCRYPT_DEMO = "$2b$10$.1cDKKIKtklnRtC9PMoAM.id5ttJSGaMFmnRO8jRiKptX7A5U9Khy"  # senha: EcoCity@2026

# 24 meses: jan/2023 a dez/2024 (últimos 2 anos com todas as fontes oficiais publicadas)
MESES = [(a, m) for a in (2023, 2024, 2025) for m in range(1, 13)] + [(2026, m) for m in range(1, 10)]   # jan/2023 a set/2026
NOME_MES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

# nome, código IBGE, região metropolitana, lat, lon
MUNICIPIOS = [
    ("São Paulo",           "3550308", "RM de São Paulo",       -23.5505, -46.6333),
    ("Campinas",            "3509502", "RM de Campinas",        -22.9056, -47.0608),
    ("Guarulhos",           "3518800", "RM de São Paulo",       -23.4543, -46.5337),
    ("Santo André",         "3547809", "RM de São Paulo",       -23.6639, -46.5383),
    ("São José dos Campos", "3549904", "RM do Vale do Paraíba", -23.1896, -45.8841),
    ("Sorocaba",            "3552205", "RM de Sorocaba",        -23.5015, -47.4526),
    ("Ribeirão Preto",      "3543402", "RM de Ribeirão Preto",  -21.1775, -47.8103),
    ("Santos",              "3548500", "RM da Baixada Santista", -23.9608, -46.3336),
]

BASE = Path(__file__).resolve().parent.parent / "dados_reais"
def carregar(p):
    return json.loads((BASE / p).read_text(encoding="utf-8"))

SNIS = carregar("coleta/painel_saneamento_snis.json")
SEEG = carregar("coleta/seeg_transportes.json")
POP = carregar("coleta/ibge_populacao_estimativas.json")
RSU = carregar("coleta/sinisa_residuos.json")
GD = carregar("coleta_mensal/aneel_gd_mensal.json")["dados"]
SPT = carregar("coleta_mensal/sptrans_mensal.json")["mensal"]
EPE = carregar("coleta_mensal/epe_energia_sp_mensal.json")["consumo_total_mwh"]
SPR = carregar("coleta_mensal/spregula_residuos_sp.json")
ANU = carregar("coleta/anuario_energeticos_sp.json")
SAN = carregar("coleta/sanasa_campinas.json")


def br(v):
    return float(v.replace("%", "").replace(".", "").replace(",", "."))


def snis(cod7, campo, ano):
    v = SNIS[cod7[:6]][campo].get(str(ano))
    return None if v in (None, "-", "") else br(v)


def dias(a, m):
    return calendar.monthrange(a, m)[1]


def ym(a, m):
    return f"{a}-{m:02d}"


def rot(a, m):
    return f"{NOME_MES[m - 1]}/{a}"


def ruido(x, pct=0.01):
    return x * (1 + random.uniform(-pct, pct))


def q(s):
    return "'" + str(s).replace("'", "''") + "'"


def pop(cod, ano):      # IBGE (2024+) ; 2023 = estimativa IBGE publicada no SNIS
    v = POP[cod].get(str(ano))
    return v if v else int(snis(cod, "População(pessoas)", ano))


# Perfil sazonal do consumo de água (verão maior). Usado para distribuir o total anual oficial.
SAZ_AGUA = [1.06, 1.05, 1.04, 1.00, 0.96, 0.94, 0.94, 0.96, 0.99, 1.02, 1.03, 1.06]

# Valores de referência ESTIMADOS pela equipe (não há dado oficial municipal mensal):
#   ENE kWh/hab/mês (todas as classes) e viagens de transporte público/hab/mês
ENE_PC = {"São Paulo": 240, "Campinas": 262, "Guarulhos": 250, "Santo André": 215,
          "São José dos Campos": 305, "Sorocaba": 275, "Ribeirão Preto": 258, "Santos": 224}
TP_PC = {"Campinas": 9.2, "Guarulhos": 7.8, "Santo André": 6.8, "São José dos Campos": 7.3,
         "Sorocaba": 6.6, "Ribeirão Preto": 5.4, "Santos": 8.5}

FONTE_SNIS = "SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)"

out = []
w = out.append
w("-- =====================================================================")
w("--  EcoCity — Script 07: dados (gerado por gerar_dados_teste.py)")
w("--  8 municípios do Estado de São Paulo, dados MENSAIS de jan/2023 a set/2026 (45 meses).")
w("--  Cada número usa o ÚLTIMO dado oficial publicado da sua fonte (coleta em 16/11/2026).")
w("--")
w("--  Coluna dado.origem:")
w("--   REAL     = oficial do mês: energia solar (ANEEL) e ônibus de São Paulo (SPTrans), até set/2026.")
w("--   DERIVADO = total oficial do ano ÷ meses: água e resíduos 2023-2024 (SNIS/SINISA), água de Campinas")
w("--              2025-jun/2026 (SANASA), energia por cidade 2024 (Anuário SEMIL-SP), emissões")
w("--              2023-2025 (SEEG), resíduos de São Paulo até ago/2026 (SP Regula).")
w("--   ESTIMADO = a fonte ainda não publicou ou não há dado da cidade: água e resíduos 2025-2026,")
w("--              emissões 2026, energia por cidade 2025-2026 e ônibus das outras 7 cidades.")
w("--  A coluna referencia_origem explica cada número. Para trocar por um oficial:")
w("--     CALL sp_atualizar_dado_real('Campinas', 2024, 3, 'ENERGIA_CONSUMIDA', 512345, 'CPFL mar/2024');")
w("--  AÇÕES, RESULTADOS e insights históricos são ilustrativos.")
w("--  Senha dos usuários de demonstração: EcoCity@2026")
w("-- =====================================================================")
w("USE ecocity;\nSET NAMES utf8mb4;\n")

w("-- Perfis: quem precisa de login em 2 etapas e de quanto em quanto tempo troca a senha")
w("INSERT INTO perfil (nome, descricao, exige_mfa, validade_senha_dias) VALUES")
w("  ('CIDADAO','Consulta o painel público da sua cidade, em linguagem simples', FALSE, 365),")
w("  ('ANALISTA','Explora os dados, publica análises revisadas por pares, dá parecer em metas e usa o Copiloto', TRUE, 90),")
w("  ('GESTOR','Propõe e aprova metas, decide ações, aprova relatórios e análises', TRUE, 90),")
w("  ('ADMIN','Administra usuários, credenciais, fontes, cargas, segurança e auditoria', TRUE, 60);\n")

w("-- Municípios: dados REAIS do IBGE (código, área e população do Censo 2022)")
w("INSERT INTO municipio (nome, codigo_ibge, regiao_metropolitana, area_km2, populacao, fonte_populacao, latitude, longitude) VALUES")
w(",\n".join(f"  ({q(n)},{q(c)},{q(rm)},{snis(c, 'Área do município(km²)', 2022)},{int(snis(c, 'População(pessoas)', 2022))},'IBGE - Censo 2022',{la},{lo})"
             for n, c, rm, la, lo in MUNICIPIOS) + ";\n")

w("-- População por ano: REAL (IBGE, estimativas da população; 2023 via SNIS; 2025 e 2026 publicadas em 28/08/2026)")
w("INSERT INTO populacao_anual (id_municipio, ano, populacao, fonte) VALUES")
w(",\n".join(f"  ({i},{ano},{pop(c, ano)},{q('IBGE - estimativa publicada em 28/08/2026' if ano > 2024 else f'IBGE - estimativa da população {ano}')})"
             for i, (n, c, *_r) in enumerate(MUNICIPIOS, start=1) for ano in (2023, 2024, 2025, 2026)) + ";\n")

import bcrypt as _bcrypt
CHAVE_ADMIN_DEMO = "ADM-EcoCity-2026"     # chave individual do admin de DEMONSTRAÇÃO (no banco fica só o hash)
CHAVE_ADMIN_HASH = _bcrypt.hashpw(CHAVE_ADMIN_DEMO.encode(), _bcrypt.gensalt(10)).decode()

def cpf_demo(base9):          # CPF fictício com dígitos verificadores válidos (só para teste)
    d = [int(x) for x in base9]
    for n in (10, 11):
        s_ = sum(v * (n - i) for i, v in enumerate(d)); r = s_ % 11
        d.append(0 if r < 2 else 11 - r)
    return "".join(map(str, d))

w("-- Usuários de DEMONSTRAÇÃO. O ADMIN nasce com chave individual (exigida pelo trigger);")
w("-- analistas e gestores nascem EM_ANALISE e só ficam ATIVOS depois do cadastro profissional aprovado (abaixo).")
w("INSERT INTO usuario (nome, email, telefone, senha_hash, id_perfil, id_municipio, chave_admin_hash) VALUES")
users = [
    ("Administrador EcoCity", "admin@ecocity.local", None, 4, None),
    ("Marina Duarte", "marina.duarte@ecocity.local", "1132150001", 3, None),
    ("Carlos Menezes", "carlos.menezes@ecocity.local", "1131240002", 3, 1),
    ("Rafael Nunes", "rafael.nunes@ecocity.local", "1124750003", 2, 3),
    ("Lúcia Andrade", "lucia.andrade@ecocity.local", "1932110004", 2, 7),
    ("Beatriz Rocha", "beatriz.rocha@ecocity.local", "1532380005", 2, 6),
    ("João Pereira", "JOAO.PEREIRA@email.com ", "11987654321", 1, 2),
    ("Ana Lima", "ana.lima@email.com", None, 1, 8),
]
w(",\n".join(f"  ({q(n)},{q(e)},{'NULL' if t is None else q(t)},{q(BCRYPT_DEMO)},{p},{'NULL' if r is None else r},"
              f"{q(CHAVE_ADMIN_HASH) if p == 4 else 'NULL'})" for n, e, t, p, r in users) + ";\n")
w("-- Login em 2 etapas já configurado para analistas, gestores e admin (segredo de DEMONSTRAÇÃO, criptografado com AES)")
w("UPDATE usuario SET mfa_ativo = TRUE, mfa_segredo = AES_ENCRYPT('JBSWY3DPEHPK3PXP', UNHEX(SHA2('chave-demo-ecocity', 256)))")
w("WHERE id_perfil IN (2, 3, 4) AND email <> 'beatriz.rocha@ecocity.local';\n")

w("INSERT INTO servico_publico (nome, descricao) VALUES")
w("  ('Água','Abastecimento, consumo e perdas na rede de distribuição'),")
w("  ('Energia','Consumo de energia elétrica e geração renovável distribuída'),")
w("  ('Resíduos','Coleta, destinação e reciclagem de resíduos sólidos urbanos'),")
w("  ('Mobilidade','Transporte público e emissões do setor de transportes');\n")

w("-- Órgãos e instituições que publicam os dados (REAIS)")
w("INSERT INTO orgao (nome, sigla, tipo, email_contato) VALUES")
w("  ('Ministério das Cidades - SNIS/SINISA','MCID','SECRETARIA',NULL),")
w("  ('Empresa de Pesquisa Energética','EPE','EMPRESA_PUBLICA',NULL),")
w("  ('Agência Nacional de Energia Elétrica','ANEEL','AUTARQUIA',NULL),")
w("  ('São Paulo Transporte S.A.','SPTRANS','EMPRESA_PUBLICA',NULL),")
w("  ('Observatório do Clima - SEEG','SEEG','PARCEIRO',NULL),")
w("  ('Instituto Brasileiro de Geografia e Estatística','IBGE','AUTARQUIA',NULL),")
w("  ('Agência Reguladora de Serviços Públicos de São Paulo','SPREGULA','AUTARQUIA',NULL),")
w("  ('Secretaria de Meio Ambiente, Infraestrutura e Logística de SP','SEMIL','SECRETARIA',NULL),")
w("  ('Sociedade de Abastecimento de Água e Saneamento (Campinas)','SANASA','EMPRESA_PUBLICA',NULL);\n")

# nome, órgão, serviço, tipo, frequência, url, confiabilidade
FONTES = [
    ("SNIS/SINISA - Água (consumo)", 1, 1, "PAGINA_WEB", "ANUAL", "https://www.painelsaneamento.org.br", 5),
    ("SNIS/SINISA - Água (produção e perdas)", 1, 1, "PAGINA_WEB", "ANUAL", "https://www.painelsaneamento.org.br", 5),
    ("EPE - Consumo mensal de energia por UF", 2, 2, "PLANILHA", "MENSAL", "https://www.epe.gov.br/pt/publicacoes-dados-abertos/publicacoes/consumo-de-energia-eletrica", 4),
    ("ANEEL - Geração Distribuída", 3, 2, "ARQUIVO_PARQUET", "MENSAL", "https://dadosabertos.aneel.gov.br/dataset/relacao-de-empreendimentos-de-geracao-distribuida", 5),
    ("SINISA - Resíduos Sólidos", 1, 3, "ARQUIVO_CSV", "ANUAL", "https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa", 4),
    ("SP Regula - Quantitativos de coleta (São Paulo)", 7, 3, "PAGINA_WEB", "SEMESTRAL", "https://prefeitura.sp.gov.br/web/spregula/w/residuos_solidos/menu/185375", 4),
    ("SPTrans - Situação dos ônibus (passageiros)", 4, 4, "PDF", "DIARIA", "https://www.sptrans.com.br", 5),
    ("SEEG Municípios - Transportes", 5, 4, "API_REST", "ANUAL", "https://plataforma.seeg.eco.br", 4),
    ("SEMIL - Anuário de Energéticos por Município", 8, 2, "PDF", "ANUAL", "https://semil.sp.gov.br/anuario-de-energeticos-por-municipios-do-estado-de-sao-paulo/", 4),
    ("SANASA - Relatórios de água de Campinas", 9, 1, "PDF", "MENSAL", "https://www.sanasa.com.br", 4),
]
w("INSERT INTO fonte_dados (nome, id_orgao, id_servico, tipo_integracao, frequencia, endpoint_url) VALUES")
w(",\n".join(f"  ({q(n)},{o},{s},{q(t)},{q(f)},{q(u)})" for n, o, s, t, f, u, c in FONTES) + ";\n")
MOTIVO_CONF = {
    1: (4, "Critério 4: órgão oficial, mas o dado é anual"), 2: (4, "Critério 4: órgão oficial, mas o dado é anual"),
    3: (4, "Critério 4: órgão oficial e mensal, mas só do Estado (não por município)"),
    4: (5, "Critério 5: órgão oficial, dado mensal, atualizado e por município"),
    5: (4, "Critério 4: órgão oficial, mas o dado é anual"),
    6: (3, "Critério 3: dado oficial publicado em imagens na página (extração manual)"),
    7: (3, "Critério 3: dado oficial publicado em PDF (extração manual)"),
    8: (2, "Critério 2: fonte não governamental reconhecida (Observatório do Clima)"),
    9: (4, "Critério 4: órgão oficial e por município, mas o dado é anual"),
    10: (4, "Critério 4: operadora pública oficial, só de Campinas, publicado em PDF"),
}
w("-- Nota de confiabilidade dada pelo ADMINISTRADOR, com o critério aplicado")
for i, (nota, mot) in MOTIVO_CONF.items():
    w(f"CALL sp_avaliar_fonte({i}, 1, {nota}, {q(mot)});")
w("")

UNIDADES = [("m³", "metro cúbico"), ("MWh", "megawatt-hora"), ("t", "tonelada"), ("passageiros", "passageiros transportados"),
            ("t CO2e", "toneladas de CO2 equivalente"), ("L/hab/dia", "litros por habitante por dia"), ("%", "percentual"),
            ("kWh/hab/mês", "quilowatt-hora por habitante por mês"), ("kg/hab/dia", "quilogramas por habitante por dia"),
            ("viagens/hab/mês", "viagens em transporte público por habitante por mês"),
            ("kg CO2e/hab/mês", "kg de CO2 equivalente por habitante por mês"),
            ("kW", "quilowatt de potência instalada"), ("W/hab", "watts de potência instalada por habitante")]
w("INSERT INTO unidade_medida (sigla, descricao) VALUES")
w(",\n".join(f"  ({q(s)},{q(d)})" for s, d in UNIDADES) + ";\n")

METRICAS = [  # codigo, nome, serviço, unidade, fonte padrão
    ("AGUA_PRODUZIDA", "Volume de água produzido no mês", 1, 1, 2),
    ("AGUA_CONSUMIDA", "Volume de água consumido no mês", 1, 1, 1),
    ("ENERGIA_CONSUMIDA", "Energia elétrica consumida no mês (todas as classes)", 2, 2, 3),
    ("GD_POTENCIA", "Potência instalada de micro e minigeração distribuída (acumulada até o fim do mês)", 2, 12, 4),
    ("RESIDUOS_COLETADOS", "Resíduos sólidos domiciliares coletados no mês", 3, 3, 5),
    ("RESIDUOS_RECICLADOS", "Resíduos recuperados pela coleta seletiva no mês", 3, 3, 5),
    ("TP_PASSAGEIROS", "Passageiros transportados por ônibus no mês", 4, 4, 7),
    ("CO2_TRANSPORTE", "Emissões de CO2e do setor de transportes no mês", 4, 5, 8),
]
w("INSERT INTO metrica (codigo, nome, id_servico, id_unidade) VALUES")
w(",\n".join(f"  ({q(c)},{q(n)},{s},{u})" for c, n, s, u, _ in METRICAS) + ";\n")

INDICADORES = [
    ("AGU-01", "Consumo de água per capita", "Litros consumidos por habitante por dia",
     "AGUA_CONSUMIDA*1000 / populacao / dias_do_mes", 1, 6, 150, "MENOR_MELHOR", "ODS 6.4", 1.0),
    ("AGU-02", "Perdas na distribuição de água", "Percentual da água produzida que se perde antes de chegar às casas",
     "(AGUA_PRODUZIDA - AGUA_CONSUMIDA) / AGUA_PRODUZIDA * 100", 1, 7, 25, "MENOR_MELHOR", "ODS 6.4", 1.2),
    ("ENE-01", "Consumo de energia per capita", "kWh consumidos por habitante no mês (todas as classes)",
     "ENERGIA_CONSUMIDA*1000 / populacao", 2, 8, 220, "MENOR_MELHOR", "ODS 7.3", 1.0),
    ("ENE-02", "Geração distribuída por habitante", "Potência de micro e minigeração distribuída (em geral painéis solares) instalada por habitante",
     "GD_POTENCIA*1000 / populacao", 2, 13, 100, "MAIOR_MELHOR", "ODS 7.2", 1.2),
    ("RES-01", "Geração de resíduos per capita", "kg de resíduos domiciliares coletados por habitante por dia",
     "RESIDUOS_COLETADOS*1000 / populacao / dias_do_mes", 3, 9, 0.95, "MENOR_MELHOR", "ODS 12.5", 1.0),
    ("RES-02", "Taxa de reciclagem", "Percentual dos resíduos coletados recuperado pela coleta seletiva",
     "RESIDUOS_RECICLADOS / RESIDUOS_COLETADOS * 100", 3, 7, 10, "MAIOR_MELHOR", "ODS 11.6", 1.3),
    ("MOB-01", "Uso do transporte público", "Viagens de ônibus por habitante no mês",
     "TP_PASSAGEIROS / populacao", 4, 10, 15, "MAIOR_MELHOR", "ODS 11.2", 1.0),
    ("MOB-02", "Emissões do transporte per capita", "kg de CO2e emitidos pelo transporte por habitante no mês",
     "CO2_TRANSPORTE*1000 / populacao", 4, 11, 65, "MENOR_MELHOR", "ODS 13.2", 1.3),
]
w("-- Metas definidas pela equipe a partir de referências do setor (podem ser ajustadas)")
w("INSERT INTO indicador (codigo, nome, descricao, formula, id_servico, id_unidade, meta, sentido, ods, peso_ies) VALUES")
w(",\n".join(f"  ({q(c)},{q(n)},{q(d)},{q(f)},{s},{u},{m},{q(se)},{q(o)},{p})"
             for c, n, d, f, s, u, m, se, o, p in INDICADORES) + ";\n")

MSG_LOTE = {
    1: "Consumo de água: totais OFICIAIS 2023 e 2024 (SNIS) distribuídos pelos meses",
    2: "Produção de água: perdas OFICIAIS 2023 e 2024 (SNIS)",
    3: "Energia: série mensal OFICIAL da EPE (Estado de SP) x consumo per capita ESTIMADO por cidade",
    4: "Geração distribuída: OFICIAL mês a mês em 2024; 2023 calculado do acumulado oficial (ANEEL)",
    5: "Resíduos: per capita OFICIAL 2023 e 2024 (SINISA)",
    6: "Resíduos de São Paulo: totais OFICIAIS 2023 e 2024 (SP Regula)",
    7: "Passageiros: São Paulo OFICIAL (SPTrans); demais cidades ESTIMADAS",
    8: "Emissões: totais OFICIAIS 2023 a 2025 (SEEG) distribuídos pelos dias",
    9: "Energia por cidade: totais OFICIAIS do Anuário de Energéticos (SEMIL-SP) distribuídos pela variação da EPE",
    10: "Água de Campinas 2025 e jan-jun/2026: totais OFICIAIS da SANASA",
}
w("-- Credenciais dos analistas (ILUSTRATIVAS): conferidas pelo administrador; só VERIFICADA e dentro da validade publica")
w("INSERT INTO credencial_analista (id_usuario, orgao_vinculo, registro_profissional, id_servico, nivel, status, verificado_por, verificado_em, valida_ate, observacao) VALUES")
w("  (4, 'Secretaria de Meio Ambiente de Guarulhos (ilustrativo)', 'CREA-SP 5069990001', NULL, 'SENIOR', 'VERIFICADA', 1, '2026-02-10 10:00:00', '2027-02-10', 'Engenheiro sanitarista; atua em todas as áreas'),")
w("  (5, 'Universidade (grupo de pesquisa em energia, ilustrativo)', 'CREA-SP 5069990002', 2, 'PLENO', 'VERIFICADA', 1, '2026-03-05 14:30:00', '2027-03-05', 'Especialista em energia'),")
w("  (6, 'Cooperativa de reciclagem de Sorocaba (ilustrativo)', 'CRQ-IV 4099990003', 3, 'JUNIOR', 'PENDENTE', NULL, NULL, NULL, 'Aguardando envio do diploma');\n")
w("-- Cadastro profissional (ILUSTRATIVO) de gestores e analistas: conferido e aprovado pelo ADMIN")
w("INSERT INTO cadastro_profissional (id_usuario, cpf_hash, cpf_final, email_institucional, telefone_institucional, orgao, cargo, matricula,")
w("       formacao, registro_conselho, portaria_nomeacao, id_municipio_atuacao, documento_url, justificativa, aceite_termo_em, ip_aceite,")
w("       status, analisado_por, analisado_em, motivo_decisao, valido_ate, criado_em) VALUES")
CAD = [  # id, base CPF, e-mail institucional, órgão, cargo, matrícula, formação, conselho, portaria, cidade, pedido, aprovado, validade
    (2, "529982247", "marina.duarte@ecocity.local", "Consórcio Intermunicipal de Sustentabilidade (ilustrativo)", "Coordenadora de Planejamento", "CIS-0412",
     "Gestão Ambiental (Unicamp, 2012)", None, "Portaria CIS nº 18/2025 (Diário Oficial, ilustrativo)", 1, "2026-01-20", "2026-01-27", "2027-01-27"),
    (3, "111444777", "carlos.menezes@ecocity.local", "Prefeitura de São Paulo - Secretaria do Verde (ilustrativo)", "Diretor de Indicadores", "SVMA-77310",
     "Engenharia Civil (Poli-USP, 2005)", None, "Portaria SVMA nº 102/2025 (Diário Oficial, ilustrativo)", 1, "2026-01-21", "2026-01-28", "2027-01-28"),
    (4, "390533447", "rafael.nunes@ecocity.local", "Secretaria de Meio Ambiente de Guarulhos (ilustrativo)", "Engenheiro Sanitarista", "SMA-2290",
     "Engenharia Sanitária (Unesp, 2010)", "CREA-SP 5069990001", None, 3, "2026-02-03", "2026-02-10", "2027-02-10"),
    (5, "123456789", "lucia.andrade@ecocity.local", "Universidade - grupo de pesquisa em energia (ilustrativo)", "Pesquisadora", "UNI-55120",
     "Engenharia Elétrica (Unicamp, 2014)", "CREA-SP 5069990002", None, 7, "2026-02-26", "2026-03-05", "2027-03-05"),
    (6, "987654321", "beatriz.rocha@ecocity.local", "Cooperativa de reciclagem de Sorocaba (ilustrativo)", "Técnica Ambiental", "COOP-0081",
     "Técnico em Meio Ambiente (Etec, 2021)", "CRQ-IV 4099990003", None, 6, "2026-09-01", "2026-09-08", "2027-09-08"),
]
linhas = []
for i, b9, em, org, cargo, mat, form, cons, port, cid, ped, apr, val in CAD:
    c = cpf_demo(b9)
    linhas.append(f"  ({i}, SHA2({q(c)}, 256), {q(c[-2:])}, {q(em)}, (SELECT telefone FROM usuario WHERE id_usuario = {i}), {q(org)}, {q(cargo)}, {q(mat)}, "
                  f"{q(form)}, {'NULL' if cons is None else q(cons)}, {'NULL' if port is None else q(port)}, {cid}, "
                  f"{q('https://drive.ecocity.local/documentos/vinculo_' + str(i) + '.pdf')}, "
                  f"{q('Preciso acompanhar os indicadores mensais da minha área para planejar ações e responder à população.')}, "
                  f"'{ped} 09:00:00', '10.0.0.{10 + i}', 'APROVADO', 1, '{apr} 15:00:00', "
                  f"{q('Declaração de vínculo, matrícula e ' + ('portaria' if port else 'registro no conselho') + ' conferidos.')}, '{val}', '{ped} 09:00:00')")
w(",\n".join(linhas) + ";")
w("UPDATE usuario SET status_cadastro = 'ATIVO' WHERE id_usuario IN (2, 3, 4, 5, 6);\n")

w("-- Pedidos de acesso feitos pelo formulário (procedure): um gestor aguardando o ADMIN e um analista recusado")
w(f"CALL sp_solicitar_acesso('GESTOR', 'Paulo Henrique Souza', {q(cpf_demo('246813579'))}, 'paulo.souza@santos.sp.gov.br', '13 3201-5000', {q(BCRYPT_DEMO)},")
w("     'Prefeitura de Santos - Secretaria de Meio Ambiente', 'Chefe de Departamento de Resíduos', 'PMS-48120', 'Engenharia Ambiental (Unisantos, 2011)',")
w("     NULL, 'Portaria nº 2.311/2026 - Diário Oficial de Santos de 02/10/2026', 8, 'https://drive.ecocity.local/documentos/paulo_portaria.pdf',")
w("     'Fui nomeado para coordenar a coleta seletiva de Santos e preciso propor as metas de reciclagem para 2027.', TRUE, '189.40.12.7');")
w(f"CALL sp_solicitar_acesso('ANALISTA', 'Diego Martins', {q(cpf_demo('135792468'))}, 'diego.martins@consultoriaverde.com.br', '11 4002-8922', {q(BCRYPT_DEMO)},")
w("     'Consultoria Verde Ltda.', 'Consultor', 'CV-001', 'Administração (2019)', 'CRA-SP 0000000', NULL, 2,")
w("     'https://drive.ecocity.local/documentos/diego_declaracao.pdf', 'Quero acessar os dados para oferecer consultoria às prefeituras da região de Campinas.', TRUE, '201.17.3.90');")
w("CALL sp_analisar_cadastro((SELECT id_usuario FROM usuario WHERE email = 'diego.martins@consultoriaverde.com.br'), 1, 'RECUSADO',")
w("     'Declaração sem assinatura do órgão e registro no conselho não confere com a área de atuação.', NULL);\n")


METAS = [  # codigo, valor, justificativa, referência
    ("AGU-01", 150, "Consumo acima de 150 L por pessoa por dia indica desperdício em cidades de grande porte; valor usado como referência pela equipe a partir das médias do SNIS.", "SNIS (IN022) e ODS 6.4"),
    ("AGU-02", 25, "Perdas acima de 25% mostram vazamentos e ligações irregulares em excesso; é o patamar usado nas metas federais de redução de perdas.", "Portaria MDR nº 490/2021 e ODS 6.4"),
    ("ENE-01", 220, "Consumo total por habitante compatível com uso eficiente de energia em cidades paulistas, definido pela equipe a partir da série da EPE.", "EPE e ODS 7.3"),
    ("ENE-02", 100, "100 W de geração própria por habitante equivale a uma parcela relevante da demanda residencial atendida por fonte renovável.", "ANEEL e ODS 7.2"),
    ("RES-01", 0.95, "Valor próximo da média nacional de resíduos coletados por habitante; acima disso indica desperdício ou falta de reaproveitamento.", "SINISA e ODS 12.5"),
    ("RES-02", 10, "Recuperar 10% do que é coletado é um patamar alcançável com coleta seletiva ampla e cooperativas.", "Lei 12.305/2010 (PNRS) e ODS 11.6"),
    ("MOB-01", 15, "Média de uma viagem de ônibus a cada dois dias por habitante, típica de cidades com transporte público bem usado.", "SPTrans e ODS 11.2"),
    ("MOB-02", 65, "Teto de emissões do transporte por habitante compatível com a redução gradual prevista nos compromissos climáticos.", "SEEG e ODS 13.2"),
]
w("-- Metas em vigor desde jan/2023 (proposta: gestora Marina; parecer: analista Rafael; aprovação: gestor Carlos)")
w("INSERT INTO meta (id_indicador, id_municipio, valor, vigencia_inicio, justificativa, referencia, status, proposta_por, parecer_por, parecer_favoravel, parecer, aprovada_por, criada_em, decidida_em) VALUES")
linhas_meta = [f"  ({k},NULL,{v},'2023-01-01',{q(j)},{q(r)},'APROVADA',2,4,TRUE,'Valor coerente com a série histórica e com a referência técnica citada.',3,'2022-12-05 09:00:00','2022-12-15 16:00:00')"
               for k, (c, v, j, r) in enumerate(METAS, start=1)]
linhas_meta.append("  (6,8,12,'2024-07-01','Santos já recicla perto de 9% do que coleta; a meta local mais ambiciosa estimula a ampliação da coleta seletiva.','Plano Municipal de Gestão Integrada de Resíduos (ilustrativo)','APROVADA',3,4,TRUE,'Santos tem a maior taxa de recuperação entre as 8 cidades; 12% é desafiador, mas possível.',2,'2024-05-13 10:00:00','2024-06-03 11:00:00')")
w(",\n".join(linhas_meta) + ";\n")

w("-- Lotes de carga (um por fonte)")
w("INSERT INTO lote_carga (id_fonte, iniciado_em, finalizado_em, registros_lidos, registros_validos, registros_rejeitados, status, mensagem) VALUES")
w(",\n".join(f"  ({i},'2026-10-15 02:00:{i:02d}','2026-10-15 02:01:{i:02d}',0,0,0,'SUCESSO',{q(MSG_LOTE[i])})" for i in range(1, 11)) + ";\n")

# ----------------------------------------------------------------------------------
rows = []                       # (fonte, municipio, metrica, lote, data, valor, origem, ref)
ID_MET = {c: k for k, (c, *_r) in enumerate(METRICAS, start=1)}
FONTE_MET = {c: f for c, _n, _s, _u, f in METRICAS}


def add(mid, cod_m, a, m, valor, origem, ref, fonte=None):
    f = fonte or FONTE_MET[cod_m]
    rows.append(f"({f},{mid},{ID_MET[cod_m]},{f},'{a}-{m:02d}-01',{valor:.4f},'{origem}',{q(ref)})")


# média mensal de 2024 da série estadual da EPE (base para o índice sazonal)
EPE_MEDIA_2024 = sum(EPE[ym(2024, m)] for m in range(1, 13)) / 12
# ônibus de São Paulo: oficial mês a mês (SPTrans, soma diária do PDF)
SPT_MES = {k: v[0] * dias(int(k[:4]), int(k[5:])) / v[1] for k, v in SPT.items()}   # completa dias faltantes
TOT_SPT24 = sum(SPT_MES[ym(2024, m)] for m in range(1, 13))
SPT_MEDIA_2024 = TOT_SPT24 / 12
ULT_EPE = max(EPE)                       # último mês publicado pela EPE

def ult_oficial(serie):                   # último ano com valor oficial
    return max(int(a) for a, v in serie.items() if v)

for mid, (nome, cod, *_r) in enumerate(MUNICIPIOS, start=1):
    # ---------- ÁGUA: SNIS (oficial até 2024). Depois: o último oficial é usado como estimativa ----------
    anos_agua = [a for a in (2023, 2024, 2025, 2026) if snis(cod, "Consumo de água(mil m³)", a)]
    ult_ag = max(anos_agua)
    cons = {a: snis(cod, "Consumo de água(mil m³)", a) * 1000 for a in anos_agua}
    perd = {a: snis(cod, "Perdas na distribuição(%)", a) for a in anos_agua}
    peso = {a: sum(dias(a, m) * SAZ_AGUA[m - 1] for m in range(1, 13)) for a in (2023, 2024, 2025, 2026)}
    ult_cps = None
    pc_ag = cons[ult_ag] / pop(cod, ult_ag)                           # m³ por pessoa no ano (oficial)

    # ---------- GD: ANEEL mês a mês (oficial até set/2026) ----------
    gd = GD[cod]
    acum, gd_mes = gd["ate_2022_12_kw"], {}
    for (a2, m2) in MESES:
        acum += gd["mensal"].get(ym(a2, m2), [0])[0]
        gd_mes[ym(a2, m2)] = acum

    # ---------- RESÍDUOS: SINISA (oficial até 2024) ----------
    RS = {2023: RSU["2023"][cod], 2024: RSU["2024"][cod]}
    base_rs = RS[2023] if RS[2024].get("inconsistente") else RS[2024]
    ano_base_rs = 2023 if RS[2024].get("inconsistente") else 2024

    # ---------- EMISSÕES: SEEG (oficial até 2025) ----------
    seeg = SEEG[cod]["transportes_tCO2e"]
    ult_co2 = ult_oficial(seeg)

    for (a, m) in MESES:
        d, chave, p_ano = dias(a, m), ym(a, m), pop(cod, a)
        dano = 366 if a % 4 == 0 else 365

        # ÁGUA consumida e produzida
        sanasa = None
        if nome == "Campinas" and a == 2025:
            sanasa = (SAN["2025"]["agua_tratada_distribuida_m3"] * d * SAZ_AGUA[m - 1] / peso[2025], SAN["2025"]["ipd_pct"],
                      "SANASA, Relatório de Sustentabilidade 2025: 102,11 milhões de m³ tratados e distribuídos no ano e perdas de 16,58% (oficiais)")
        elif nome == "Campinas" and a == 2026 and m <= 6:
            pesoS = sum(dias(2026, k) * SAZ_AGUA[k - 1] for k in range(1, 7))
            sanasa = (SAN["2026_jan_jun"]["agua_tratada_distribuida_m3"] * d * SAZ_AGUA[m - 1] / pesoS, SAN["2026_jan_jun"]["ipd_pct"],
                      "SANASA em Números (ago/2026): 49,62 milhões de m³ tratados e distribuídos em jan-jun/2026 e perdas acumuladas de 15,00% (oficiais)")
        if sanasa:
            prod, ipd, ref_s = sanasa
            add(mid, "AGUA_PRODUZIDA", a, m, prod, "DERIVADO", f"{ref_s}; total dividido pelos meses (perfil sazonal)", fonte=10)
            add(mid, "AGUA_CONSUMIDA", a, m, prod * (1 - ipd / 100), "DERIVADO", f"{ref_s}; consumo = água distribuída x (1 - perdas)", fonte=10)
            ult_cps = (prod * (1 - ipd / 100), ipd, d)
        elif a in cons:
            agua = cons[a] * d * SAZ_AGUA[m - 1] / peso[a]
            add(mid, "AGUA_CONSUMIDA", a, m, agua, "DERIVADO",
                f"SNIS {a}: consumo anual oficial de {cons[a]/1e6:,.2f} milhões de m³ distribuído pelos meses (perfil sazonal). {FONTE_SNIS}")
            add(mid, "AGUA_PRODUZIDA", a, m, agua / (1 - perd[a] / 100), "DERIVADO",
                f"SNIS {a}: índice de perdas oficial de {perd[a]:.1f}% aplicado ao consumo do mês. {FONTE_SNIS}")
        elif nome == "Campinas" and a == 2026:
            pesoS = sum(dias(2026, k) * SAZ_AGUA[k - 1] for k in range(1, 7))
            base = SAN["2026_jan_jun"]["agua_tratada_distribuida_m3"] / pesoS
            prod = ruido(base * d * SAZ_AGUA[m - 1], 0.006); ipd = SAN["2026_jan_jun"]["ipd_pct"]
            add(mid, "AGUA_CONSUMIDA", a, m, prod * (1 - ipd / 100), "ESTIMADO",
                f"ESTIMADO: média diária oficial de jan-jun/2026 (SANASA em Números, ago/2026) x perfil sazonal. A SANASA ainda não publicou {rot(a, m)}")
            add(mid, "AGUA_PRODUZIDA", a, m, prod, "ESTIMADO",
                f"ESTIMADO: média diária oficial de jan-jun/2026 e perdas acumuladas de {ipd:.2f}% (SANASA). A SANASA ainda não publicou {rot(a, m)}")
        else:
            agua = ruido(pc_ag * p_ano * d * SAZ_AGUA[m - 1] / peso[ult_ag] * (366 if ult_ag % 4 == 0 else 365) / dano, 0.008)
            add(mid, "AGUA_CONSUMIDA", a, m, agua, "ESTIMADO",
                f"ESTIMADO: último dado oficial é o SNIS {ult_ag} ({pc_ag*1000/(366 if ult_ag % 4 == 0 else 365):,.0f} L por pessoa por dia) x população IBGE {a} x perfil sazonal. "
                f"O SNIS/SINISA de {a} ainda não foi publicado")
            add(mid, "AGUA_PRODUZIDA", a, m, agua / (1 - perd[ult_ag] / 100), "ESTIMADO",
                f"ESTIMADO: mantido o último índice de perdas oficial (SNIS {ult_ag}: {perd[ult_ag]:.1f}%). O SNIS/SINISA de {a} ainda não foi publicado")

        # ENERGIA consumida: total OFICIAL do ano por cidade (Anuário de Energéticos, SEMIL) distribuído
        # pela variação mensal OFICIAL do Estado (EPE). Sem total do ano: estimado a partir de 2024.
        def epe_mes(aa, mm):
            k = ym(aa, mm)
            if k in EPE: return EPE[k]
            cres = EPE[ULT_EPE] / EPE[ym(int(ULT_EPE[:4]) - 1, int(ULT_EPE[5:]))]
            return EPE[ym(aa - 1, mm)] * cres
        soma_epe = lambda aa: sum(epe_mes(aa, k) for k in range(1, 13))
        ann24 = ANU["total_kwh"]["2024"][cod] / 1000                                  # MWh
        resumo23 = ANU["total_kwh"]["2023_resumo_twh"].get(cod)
        if a == 2024:
            ener = ann24 * EPE[chave] / soma_epe(2024)
            add(mid, "ENERGIA_CONSUMIDA", a, m, ener, "DERIVADO",
                f"Anuário de Energéticos 2025 (SEMIL-SP): consumo OFICIAL de {ann24/1e6:,.3f} TWh em 2024 na cidade, distribuído pelos meses conforme a variação oficial da EPE (Estado de SP)", fonte=9)
        elif a == 2023 and resumo23:
            ener = resumo23 * 1e6 * EPE[chave] / soma_epe(2023)
            add(mid, "ENERGIA_CONSUMIDA", a, m, ener, "DERIVADO",
                f"Anuário de Energéticos 2024 (SEMIL-SP): consumo OFICIAL de {resumo23:.2f} TWh em 2023 (valor arredondado do resumo), distribuído pelos meses conforme a EPE", fonte=9)
        else:
            ener = ruido(ann24 * epe_mes(a, m) / soma_epe(2024), 0.004)
            ref_e = f"EPE {rot(a, m)}" if chave in EPE else f"EPE ainda não publicou {rot(a, m)}; usado {rot(a - 1, m)} x crescimento recente"
            add(mid, "ENERGIA_CONSUMIDA", a, m, ener, "ESTIMADO",
                f"ESTIMADO: último consumo oficial da cidade (Anuário SEMIL 2024: {ann24/1e6:,.3f} TWh) x variação oficial do Estado ({ref_e}). "
                f"O Anuário de {a} ainda não foi publicado")

        # GERAÇÃO DISTRIBUÍDA (ANEEL) — oficial em todos os meses
        add(mid, "GD_POTENCIA", a, m, gd_mes[chave], "REAL",
            f"ANEEL - geração distribuída: potência acumulada até o fim de {rot(a, m)} ({gd_mes[chave]:,.0f} kW). Base de 16/11/2026.")

        # RESÍDUOS
        if nome == "São Paulo":
            com, sel = SPR["comum"], SPR["seletiva"]
            if str(a) in com:
                col, rec = (com[str(a)] + sel[str(a)]) * d / dano, sel[str(a)] * d / dano
                o_r, ref_r = "DERIVADO", f"SP Regula: total OFICIAL de {a} ({(com[str(a)] + sel[str(a)])/1e6:,.2f} milhões de t, coleta comum + seletiva) dividido pelos dias"
            elif m <= 6:
                col = (com["2026-01_a_2026-06"] + sel["2026-01_a_2026-06"]) * d / 181
                rec = sel["2026-01_a_2026-06"] * d / 181
                o_r, ref_r = "DERIVADO", "SP Regula: total OFICIAL do 1º semestre de 2026 dividido pelos dias"
            elif m <= 8:
                c2 = com["2026-01_a_2026-08"] - com["2026-01_a_2026-06"]; s2 = sel["2026-01_a_2026-08"] - sel["2026-01_a_2026-06"]
                col, rec = (c2 + s2) * d / 62, s2 * d / 62
                o_r, ref_r = "DERIVADO", "SP Regula: total OFICIAL jan-ago/2026 menos o 1º semestre (= jul+ago) dividido pelos dias"
            else:
                c2 = com["2026-01_a_2026-08"] - com["2026-01_a_2026-06"]; s2 = sel["2026-01_a_2026-08"] - sel["2026-01_a_2026-06"]
                col, rec = ruido((c2 + s2) * d / 62, 0.01), ruido(s2 * d / 62, 0.01)
                o_r, ref_r = "ESTIMADO", "ESTIMADO: média diária oficial de jul-ago/2026 (SP Regula, último dado publicado). Setembro ainda não publicado"
            add(mid, "RESIDUOS_COLETADOS", a, m, col, o_r, ref_r, fonte=6)
            add(mid, "RESIDUOS_RECICLADOS", a, m, rec, o_r, ref_r, fonte=6)
        else:
            r = RS.get(a)
            if r and not r.get("inconsistente"):
                col = r["IRS1004"] * p_ano * d / 1000
                rec = col * r["IRS3010"] / 100
                o_r = "DERIVADO"
                ref_c = f"SINISA (ano-base {a}): IRS1004 = {r['IRS1004']} kg/hab/dia (oficial) x população IBGE x dias do mês"
                ref_rc = f"SINISA (ano-base {a}): IRS3010 = {r['IRS3010']}% recuperado (oficial) x coleta do mês"
            else:
                col = ruido(base_rs["IRS1004"] * p_ano * d / 1000, 0.015)
                rec = col * base_rs["IRS3010"] / 100
                o_r = "ESTIMADO"
                motivo = f"o valor oficial do SINISA {a} é inconsistente" if r else f"o SINISA de {a} ainda não foi publicado"
                ref_c = (f"ESTIMADO: {motivo}; usado o último oficial (SINISA {ano_base_rs}: {base_rs['IRS1004']} kg/hab/dia) x população IBGE {a}")
                ref_rc = (f"ESTIMADO: {motivo}; usada a última taxa oficial de reciclagem (SINISA {ano_base_rs}: {base_rs['IRS3010']}%)")
            add(mid, "RESIDUOS_COLETADOS", a, m, col, o_r, ref_c)
            add(mid, "RESIDUOS_RECICLADOS", a, m, rec, o_r, ref_rc)

        # PASSAGEIROS
        if nome == "São Paulo":
            emb, dd = SPT[chave]
            ref_t = f"SPTrans {rot(a, m)}: soma diária das viagens de passageiros ({dd} de {d} dias publicados"
            ref_t += ")" if dd == d else "; dias faltantes completados pela média do mês)"
            add(mid, "TP_PASSAGEIROS", a, m, SPT_MES[chave], "REAL", ref_t)
        else:
            idx_t = SPT_MES[chave] / SPT_MEDIA_2024
            add(mid, "TP_PASSAGEIROS", a, m, ruido(TP_PC[nome] * idx_t * p_ano, 0.01), "ESTIMADO",
                f"ESTIMADO: {TP_PC[nome]} viagens/hab/mês (estimativa da equipe) x variação mensal OFICIAL dos ônibus de São Paulo (SPTrans {rot(a, m)}). "
                f"Não há dado oficial mensal desta cidade")

        # EMISSÕES (SEEG)
        if str(a) in seeg:
            co2 = seeg[str(a)]
            add(mid, "CO2_TRANSPORTE", a, m, co2 * d / dano, "DERIVADO",
                f"SEEG Municípios {a}: {co2:,.0f} t CO2e no ano (oficial) dividido pelos dias do mês")
        else:
            pc = seeg[str(ult_co2)] / pop(cod, ult_co2)
            add(mid, "CO2_TRANSPORTE", a, m, ruido(pc * p_ano * d / (366 if ult_co2 % 4 == 0 else 365), 0.008), "ESTIMADO",
                f"ESTIMADO: emissão por pessoa do último ano oficial (SEEG {ult_co2}) x população IBGE {a}. O SEEG de {a} ainda não foi publicado")

w("-- Medições mensais: 8 municípios x 8 métricas x 45 meses (jan/2023 a set/2026)")
for i in range(0, len(rows), 96):
    w("INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES")
    w(",\n".join("  " + r for r in rows[i:i + 96]) + ";")
w("")
w("-- Atualiza a contagem de registros de cada lote")
w("UPDATE lote_carga l SET registros_lidos = (SELECT COUNT(*) FROM dado d WHERE d.id_lote = l.id_lote),")
w("                        registros_validos = registros_lidos WHERE l.id_lote <= 10;\n")

w("-- Insights históricos (ILUSTRATIVOS) que motivaram ações")
w("INSERT INTO analise_ia (id_indicador, id_municipio, tipo, titulo, descricao, confianca, severidade, modelo_versao, gerada_em, status, revisada_por) VALUES")
w("  (2, 3, 'ANOMALIA', 'Perdas de água muito altas em Guarulhos', 'As perdas na distribuição seguem bem acima da meta de 25% (dado oficial do SNIS). (insight histórico ilustrativo)', 86.00, 'CRITICO', 'ecocity-ia-v0.2', '2023-03-10 08:00:00', 'VALIDADA', 4),")
w("  (6, 6, 'TENDENCIA', 'Reciclagem abaixo da meta em Sorocaba', 'A taxa de reciclagem está bem abaixo da meta de 10%, enquanto Santos se aproxima dela. (insight ilustrativo)', 80.00, 'ATENCAO', 'ecocity-ia-v0.2', '2023-03-12 08:00:00', 'VALIDADA', 6),")
w("  (4, 3, 'CORRELACAO', 'Pouca geração solar em Guarulhos', 'Guarulhos tem uma das menores potências de geração distribuída por habitante (ANEEL). (insight histórico ilustrativo)', 72.00, 'ATENCAO', 'ecocity-ia-v0.2', '2023-03-20 08:00:00', 'VALIDADA', 5);\n")

w("-- Processa os 24 meses: indicadores + carga do Data Warehouse")
for (a, m) in MESES:
    w(f"CALL sp_pipeline_mensal('{a}-{m:02d}-01');")
w("")

w("-- Ações ILUSTRATIVAS (criadas para demonstrar o sistema)")
w("INSERT INTO acao (titulo, descricao, id_municipio, id_indicador_alvo, id_responsavel, id_analise, data_inicio, data_fim_prevista, orcamento, status) VALUES")
acoes = [
    ("Programa de redução de perdas de água", "Setorização da rede, troca de tubulações antigas e combate a fraudes. (ação ilustrativa)", 3, 2, 2, "1", "2023-05-01", "2025-12-31", 18500000, "EM_EXECUCAO"),
    ("Ampliação da coleta seletiva com cooperativas", "Coleta seletiva porta a porta e novos ecopontos. (ação ilustrativa)", 6, 6, 2, "2", "2023-05-01", "2025-12-31", 4200000, "EM_EXECUCAO"),
    ("Energia solar em prédios públicos", "Usinas fotovoltaicas em escolas e unidades de saúde. (ação ilustrativa)", 3, 4, 2, "3", "2023-06-01", "2024-12-31", 6800000, "EM_EXECUCAO"),
    ("Campanha de uso consciente da água", "Campanha educativa em escolas e redes sociais. (ação ilustrativa)", 7, 1, 2, "NULL", "2024-02-01", "2025-03-31", 350000, "EM_EXECUCAO"),
    ("Ônibus elétricos e faixas exclusivas", "Substituição gradual da frota a diesel por ônibus elétricos. (ação ilustrativa)", 1, 7, 3, "NULL", "2024-02-01", "2027-12-31", 95000000, "EM_EXECUCAO"),
    ("Ecopontos e compostagem de orgânicos", "Rede de ecopontos e compostagem de resíduos de feiras. (ação ilustrativa)", 8, 5, 2, "NULL", "2024-06-01", "2025-12-31", 2600000, "EM_EXECUCAO"),
    ("Plano de redução de perdas", "Diagnóstico e plano de redução de perdas na rede de distribuição. (ação ilustrativa)", 7, 2, 2, "NULL", "2027-01-01", "2028-12-31", 22000000, "PLANEJADA"),
]
w(",\n".join(f"  ({q(a)},{q(b)},{c},{d},{e},{f},'{g}','{h}',{i},{q(j)})" for a, b, c, d, e, f, g, h, i, j in acoes) + ";\n")

w("-- Fechamento das ações: a procedure mede ANTES (mês anterior ao início) x DEPOIS (último mês) numa transação")
w("CALL sp_registrar_resultado(1, '2024-12-31', 'Perdas comparadas entre abr/2023 e dez/2024, ambas calculadas do índice OFICIAL do SNIS. A ação é ilustrativa.', 2);")
w("CALL sp_registrar_resultado(2, '2024-12-31', 'Taxa de reciclagem abr/2023 x dez/2024, ambas do SINISA (oficial). A ação é ilustrativa.', 2);")
w("CALL sp_registrar_resultado(3, '2024-12-31', 'Antes e depois vêm da ANEEL (potência por habitante). A ação é ilustrativa.', 2);")
w("CALL sp_registrar_resultado(5, '2024-12-31', 'Passageiros de ônibus de São Paulo: dados da SPTrans (jan/2024 x dez/2024). A ação é ilustrativa.', 3);\n")

w("-- =================== ANÁLISES DOS ANALISTAS (ILUSTRATIVAS) ===================")
w("-- Criadas como rascunho, enviadas pela procedure (que calcula a confiança) e revisadas por outra pessoa")
ANALISES = [
    (4, 1, "2023-01-01", "2024-12-01", "Perdas de água em Guarulhos caem, mas seguem acima da meta",
     "O índice oficial de perdas do SNIS caiu entre 2023 e 2024, mas Guarulhos continua acima da meta de 25%.",
     "Segundo o SNIS, o índice de perdas na distribuição de Guarulhos caiu entre 2023 e 2024. Mesmo assim, a cidade segue acima da meta de 25%. "
     "Todos os meses do período são calculados a partir do índice anual oficial, por isso a análise compara anos e não meses. "
     "Recomenda-se manter a setorização da rede e a troca de hidrômetros e refazer esta análise quando o SINISA publicar o ano-base 2025.",
     [3], [("INDICADOR", 2, 3, None, None, "Série mensal de perdas (AGU-02) de Guarulhos"),
           ("FONTE_EXTERNA", None, None, None, "https://www.painelsaneamento.org.br", "Painel Saneamento Brasil — índice de perdas 2023 e 2024"),
           ("CONSULTA_SQL", None, None, "SELECT ano_mes, valor FROM vw_indicador_desempenho WHERE codigo = 'AGU-02' AND municipio = 'Guarulhos'", None, "Consulta que reproduz a série")],
     ("REVISAR", 2, "PUBLICADA", "Bem fundamentada em dado oficial; a ressalva de que o dado é anual está correta.")),
    (5, 2, "2024-01-01", "2024-12-01", "Energia solar cresce todo mês em Ribeirão Preto e Campinas",
     "Dados oficiais mensais da ANEEL mostram crescimento contínuo: Ribeirão Preto passou da meta de 100 W por habitante e Campinas chegou perto dela.",
     "Ao longo de 2024, a potência de micro e minigeração distribuída por habitante subiu todos os meses em Ribeirão Preto "
     "e em Campinas. Ribeirão Preto terminou o ano bem acima da meta de 100 W por habitante e Campinas passou de cerca de 70 para 92 W. Todos os valores do período são dados oficiais da ANEEL, por mês de cadastro. "
     "As duas cidades servem de referência para Guarulhos e Santos, que estão bem abaixo da meta.",
     [7, 2], [("INDICADOR", 4, 7, None, None, "ENE-02 de Ribeirão Preto"), ("INDICADOR", 4, 2, None, None, "ENE-02 de Campinas"),
              ("FONTE_EXTERNA", None, None, None, "https://dadosabertos.aneel.gov.br/dataset/relacao-de-empreendimentos-de-geracao-distribuida", "Base da ANEEL de 10/10/2026")],
     ("REVISAR", 4, "PUBLICADA", "Análise bem fundamentada em dados oficiais mês a mês.")),
    (4, 4, "2024-01-01", "2024-12-01", "Viagens de ônibus por habitante em São Paulo em 2024",
     "Os dados diários da SPTrans mostram como as viagens de ônibus por habitante variam ao longo do ano.",
     "Somando os dados diários oficiais da SPTrans por mês, as viagens de ônibus por habitante em São Paulo caem nas férias (janeiro e julho) "
     "e sobem nos meses de aula. A cidade segue abaixo da meta de 15 viagens por habitante por mês. Sugere-se cruzar com dados do metrô "
     "antes de concluir que houve migração para o transporte individual.",
     [1], [("INDICADOR", 7, 1, None, None, "MOB-01 de São Paulo"),
           ("FONTE_EXTERNA", None, None, None, "https://www.sptrans.com.br", "Relatório diário 'Situação dos ônibus' da SPTrans")],
     ("ENVIAR",)),
    (5, 2, "2023-01-01", "2024-12-01", "Campinas economizou energia elétrica?",
     "O consumo de energia por habitante em Campinas variou entre 2023 e 2024.",
     "O consumo de energia elétrica por habitante de Campinas variou entre 2023 e 2024. "
     "Isso indicaria resultado das ações de eficiência energética da cidade. Recomenda-se ampliar a troca de iluminação pública por LED e divulgar "
     "o resultado para a população como exemplo de economia de energia no município.",
     [2], [("INDICADOR", 3, 2, None, None, "ENE-01 de Campinas")],
     ("REVISAR", 2, "DEVOLVIDA", "O consumo municipal é ESTIMADO a partir da série estadual da EPE; a variação reflete o Estado, não Campinas. Reescreva deixando essa limitação clara.")),
    (6, 3, "2023-01-01", "2024-12-01", "Reciclagem em Sorocaba segue abaixo de 2%",
     "Rascunho: a taxa de reciclagem de Sorocaba continua muito abaixo da meta.",
     "Rascunho em elaboração. A taxa de recuperação de recicláveis de Sorocaba ficou abaixo de 2% em 2023 e 2024 (SINISA, oficial), muito abaixo da meta de 10%. "
     "Falta incluir a comparação com Santos e as evidências. Esta análise ainda não pode ser enviada porque a credencial da autora está pendente "
     "de verificação pelo administrador do sistema.",
     [6], [("INDICADOR", 6, 6, None, None, "RES-02 de Sorocaba")], None),
]
for k, (autor, serv, ini, fim, tit, res, txt, cids, evs, acao) in enumerate(ANALISES, start=1):
    w(f"INSERT INTO analise_publicada (titulo, resumo, conteudo, id_servico, periodo_inicio, periodo_fim, id_autor, criada_em) VALUES ({q(tit)},{q(res)},{q(txt)},{serv},'{ini}','{fim}',{autor},'2026-10-0{k} 09:00:00');")
    w("INSERT INTO analise_municipio (id_analise_pub, id_municipio) VALUES " + ",".join(f"({k},{c})" for c in cids) + ";")
    w("INSERT INTO analise_evidencia (id_analise_pub, tipo, id_indicador, id_municipio, consulta_sql, url, descricao) VALUES " + ",\n  ".join(
        f"({k},'{t}',{'NULL' if i is None else i},{'NULL' if m is None else m},{'NULL' if sq is None else q(sq)},{'NULL' if u is None else q(u)},{q(d)})" for t, i, m, sq, u, d in evs) + ";")
    if acao:
        w(f"CALL sp_enviar_analise({k}, {autor});")
        if acao[0] == "REVISAR":
            w(f"CALL sp_revisar_analise({k}, {acao[1]}, '{acao[2]}', {q(acao[3])});")
w("INSERT INTO analise_comentario (id_analise_pub, id_usuario, texto) VALUES")
w("  (1, 5, 'Boa leitura. Vale incluir Santo André, que também está acima de 30% de perdas.'),")
w("  (1, 3, 'Vamos usar esta análise na revisão do programa de perdas. Obrigado.'),")
w("  (2, 4, 'Concordo. Guarulhos poderia replicar o programa de painéis em escolas de Ribeirão Preto.'),")
w("  (2, 6, 'Seria interessante cruzar com o número de sistemas instalados por bairro.');\n")

w("-- =================== METAS NOVAS (fluxo completo pelas procedures) ===================")
w("CALL sp_propor_meta(2, 'AGU-01', 7, 220, '2027-01-01', 'Ribeirão Preto consome perto de 280 L por habitante por dia; uma meta intermediária de 220 L é mais realista para 2027.', 'Plano Municipal de Saneamento (ilustrativo) e ODS 6.4');")
w("CALL sp_propor_meta(3, 'AGU-02', 3, 22, '2027-01-01', 'Guarulhos está perto de 25% de perdas; o programa de setorização permite mirar 22% a partir de 2027.', 'Portaria MDR nº 490/2021');")
w("CALL sp_parecer_meta(LAST_INSERT_ID(), 4, TRUE, 'A série oficial de 2023 e 2024 mostra queda; 22% em 2027 é alcançável.');")
w("CALL sp_propor_meta(2, 'ENE-02', 5, 300, '2027-01-01', 'São José dos Campos tem ótima irradiação solar e já passa de 150 W por habitante; queremos triplicar a meta.', 'ODS 7.2');")
w("SET @m = (SELECT MAX(id_meta) FROM meta);")
w("CALL sp_parecer_meta(@m, 5, FALSE, 'O ritmo atual da ANEEL (cerca de 1% ao mês) leva a cidade a uns 230 W/hab em 2027; 300 W/hab não é realista. Sugiro 230.');")
w("CALL sp_decidir_meta(@m, 3, FALSE);\n")

w("-- =================== LOGIN: exemplos registrados pelo banco ===================")
w("CALL sp_registrar_login('rafael.nunes@ecocity.local', TRUE, TRUE, TRUE, '10.0.0.15');")
w("CALL sp_registrar_login('marina.duarte@ecocity.local', TRUE, TRUE, TRUE, '10.0.0.22');")
w("CALL sp_registrar_login('lucia.andrade@ecocity.local', TRUE, FALSE, TRUE, '10.0.0.31');      -- código do autenticador errado")
for i in range(5):
    w("CALL sp_registrar_login('beatriz.rocha@ecocity.local', FALSE, FALSE, TRUE, '177.10.20.30');   -- senha errada")
w("CALL sp_registrar_login('beatriz.rocha@ecocity.local', TRUE, FALSE, TRUE, '177.10.20.30');    -- bloqueada por 15 minutos")
w("CALL sp_registrar_login('nao.existe@ecocity.local', FALSE, FALSE, TRUE, '45.90.1.2');")
w("CALL sp_registrar_login('admin@ecocity.local', TRUE, TRUE, FALSE, '200.150.3.9');          -- senha e código certos, CHAVE do admin errada")
w("CALL sp_registrar_login('paulo.souza@santos.sp.gov.br', TRUE, TRUE, TRUE, '189.40.12.7');   -- cadastro ainda em análise: não entra\n")

w("-- Demonstração do ETL: lote com linhas inválidas (todas rejeitadas pelo banco)")
w("INSERT INTO lote_carga (id_fonte, iniciado_em) VALUES (7, '2026-10-15 03:00:00');")
w("SET @lote = LAST_INSERT_ID();")
w("INSERT INTO stg_medicao_bruta (id_lote, codigo_metrica, nome_municipio, data_texto, valor_texto) VALUES")
w("  (@lote,'TP_PASSAGEIROS','Cidade Fantasma','2024-09-01','150000'),")
w("  (@lote,'TP_PASSAGEIROS','Santos','01/09/2024','abc'),")
w("  (@lote,'AGUA_CONSUMIDA','Santos','2024-09-01','12000');")
w("CALL sp_processar_staging(@lote);")

print("\n".join(out))
