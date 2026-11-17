"""Gera EcoCity_dados_municipios_SP.xlsx a partir do banco: dados MENSAIS, com a origem de cada número em cor."""
import calendar
import pymysql
from openpyxl import Workbook
from openpyxl.comments import Comment
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

F = "Arial"; thin = Side(style="thin", color="BFBFBF"); borda = Border(top=thin, bottom=thin, left=thin, right=thin)
COR = {"REAL": "C6EFCE", "DERIVADO": "DDEBF7", "ESTIMADO": "FCE4D6"}
cab = PatternFill("solid", fgColor="1F3864"); cab2 = PatternFill("solid", fgColor="375623"); calc_fill = PatternFill("solid", fgColor="EDEDED")

con = pymysql.connect(unix_socket="/var/run/mysqld/mysqld.sock", user="root", database="ecocity", charset="utf8mb4")
cu = con.cursor()
METRICAS = ["AGUA_PRODUZIDA", "AGUA_CONSUMIDA", "ENERGIA_CONSUMIDA", "GD_POTENCIA", "RESIDUOS_COLETADOS", "RESIDUOS_RECICLADOS", "TP_PASSAGEIROS", "CO2_TRANSPORTE"]
NOMES = ["Água produzida (m³/mês)", "Água consumida (m³/mês)", "Energia consumida (MWh/mês)", "Geração distribuída (kW acumulado)",
         "Resíduos coletados (t/mês)", "Resíduos reciclados (t/mês)", "Passageiros de ônibus (mês)", "Emissões transporte (t CO2e/mês)"]
cu.execute("""SELECT m.nome, DATE_FORMAT(d.data_referencia, '%Y-%m'), me.codigo, d.valor, d.origem, d.referencia_origem, pa.populacao
              FROM dado d JOIN municipio m USING (id_municipio) JOIN metrica me USING (id_metrica)
              JOIN populacao_anual pa ON pa.id_municipio = d.id_municipio AND pa.ano = YEAR(d.data_referencia)
              ORDER BY m.id_municipio, d.data_referencia""")
linhas = {}
for nome, mes, cod, v, o, ref, pop in cu.fetchall():
    linhas.setdefault((nome, mes), {"pop": pop})[cod] = (float(v), o, ref)

wb = Workbook(); ws = wb.active; ws.title = "Dados mensais"
ws["A1"] = "EcoCity — 8 municípios de SP, dados mensais de out/2024 a set/2026"; ws["A1"].font = Font(name=F, bold=True, size=14)
ws["A2"] = ("VERDE = OFICIAL do mês · AZUL = CALCULADO a partir de total oficial (ano/semestre) · LARANJA = ESTIMADO pela equipe. "
            "Passe o mouse na célula para ver a fonte. Colunas cinza = indicadores calculados por fórmula.")
ws["A2"].font = Font(name=F, italic=True, size=9, color="595959")
H = 4
cols = ["Município", "Mês", "População (IBGE, ano)"] + NOMES
calc = [("AGU-01 Água (L/hab/dia)", "=IFERROR(E{r}*1000/C{r}/{d},\"\")", "0.0"),
        ("AGU-02 Perdas (%)", "=IFERROR((D{r}-E{r})/D{r},\"\")", "0.0%"),
        ("ENE-01 Energia (kWh/hab/mês)", "=IFERROR(F{r}*1000/C{r},\"\")", "0.0"),
        ("ENE-02 Solar (W/hab)", "=IFERROR(G{r}*1000/C{r},\"\")", "0.0"),
        ("RES-01 Lixo (kg/hab/dia)", "=IFERROR(H{r}*1000/C{r}/{d},\"\")", "0.00"),
        ("RES-02 Reciclagem (%)", "=IFERROR(I{r}/H{r},\"\")", "0.0%"),
        ("MOB-01 Ônibus (viagens/hab/mês)", "=IFERROR(J{r}/C{r},\"\")", "0.0"),
        ("MOB-02 CO2 (kg/hab/mês)", "=IFERROR(K{r}*1000/C{r},\"\")", "0.0")]
for i, h in enumerate(cols + [c[0] for c in calc], start=1):
    c = ws.cell(H, i, h); c.font = Font(name=F, bold=True, color="FFFFFF", size=9)
    c.fill = cab if i <= len(cols) else cab2; c.alignment = Alignment(wrap_text=True, vertical="center")
    ws.column_dimensions[get_column_letter(i)].width = 18 if i == 1 else 9 if i == 2 else 14
ws.row_dimensions[H].height = 46
r = H + 1
for (nome, mes), m in linhas.items():
    a, mm = int(mes[:4]), int(mes[5:]); dias = calendar.monthrange(a, mm)[1]
    ws.cell(r, 1, nome); ws.cell(r, 2, mes); ws.cell(r, 3, m["pop"]).number_format = "#,##0"
    for j, cod in enumerate(METRICAS, start=4):
        v, o, ref = m[cod]
        c = ws.cell(r, j, round(v, 2)); c.fill = PatternFill("solid", fgColor=COR[o]); c.number_format = "#,##0"
        c.comment = Comment(f"{o}: {ref}", "EcoCity")
    for j, (_, f, fmt) in enumerate(calc, start=len(cols) + 1):
        c = ws.cell(r, j, f.format(r=r, d=dias)); c.fill = calc_fill; c.number_format = fmt
    for j in range(1, len(cols) + len(calc) + 1):
        ws.cell(r, j).font = Font(name=F, size=9); ws.cell(r, j).border = borda
    r += 1
ws.freeze_panes = "C5"; ws.auto_filter.ref = f"A{H}:{get_column_letter(len(cols) + len(calc))}{r - 1}"

fs = wb.create_sheet("Onde achar os dados")
for col, w in zip("ABCD", (34, 16, 55, 60)): fs.column_dimensions[col].width = w
fs.append(["Dado", "Origem no banco", "Fonte", "Como foi usado"])
for c in fs[1]: c.font = Font(name=F, bold=True, color="FFFFFF"); c.fill = cab
for linha in [
    ("Geração distribuída (painéis solares)", "OFICIAL do mês", "ANEEL Dados Abertos — Relação de empreendimentos de GD (base de 10/10/2026)", "Potência somada por município e mês de cadastro, acumulada. Até jul/2026 (ago/2026 em 2 cidades); meses seguintes estimados."),
    ("Passageiros de ônibus de São Paulo", "OFICIAL do mês", "SPTrans — 'Situação dos ônibus / Adequação da oferta' (PDF de 02/10/2026)", "Soma diária das viagens de passageiros por mês, até set/2026."),
    ("Energia elétrica (Estado de SP)", "base OFICIAL mensal", "EPE — Consumo mensal de energia elétrica por classe (planilha por UF)", "A variação mensal oficial do Estado multiplica o consumo per capita ESTIMADO de cada cidade."),
    ("Água consumida e perdas", "CALCULADO (2024) / ESTIMADO", "SNIS/SINISA via Painel Saneamento Brasil", "Total anual oficial de 2024 distribuído pelos meses; 2025-2026 estimados (SINISA ref. 2025 ainda não publicado)."),
    ("Resíduos (7 cidades)", "CALCULADO (2024) / ESTIMADO", "SINISA — Resíduos Sólidos (IRS1004 e IRS3010)", "Per capita oficial de 2024 x dias do mês; 2025-2026 estimados. São José dos Campos 2024 inconsistente: usado 2023."),
    ("Resíduos de São Paulo", "CALCULADO", "SP Regula — página Quantitativos (Prefeitura de SP)", "Totais oficiais de 2024, 2025, 1º semestre e jan-ago/2026 divididos pelos dias; set/2026 estimado."),
    ("Emissões do transporte", "CALCULADO (2024) / ESTIMADO", "SEEG Municípios (coleção 13)", "Total anual oficial de 2024 dividido pelos dias; 2025-2026 estimados."),
    ("População", "OFICIAL (anual)", "IBGE — estimativas da população (2024; 2025 e 2026 publicadas em 28/08/2026)", "Cada mês usa a população do seu ano."),
]:
    fs.append(list(linha))
for row in fs.iter_rows(min_row=2):
    for c in row: c.font = Font(name=F, size=10); c.alignment = Alignment(wrap_text=True, vertical="top")

tr = wb.create_sheet("Como trocar por dado real")
tr.column_dimensions["A"].width = 110
for t in ["Quando sair um número oficial para um mês, rode no MySQL Workbench:",
          "CALL sp_atualizar_dado_real('Campinas', 2026, 3, 'AGUA_CONSUMIDA', 7012345, 'SANASA - relatório mensal mar/2026');",
          "Parâmetros: município, ano, mês (1 a 12), código da métrica, valor, fonte.",
          "O banco troca o valor, marca como OFICIAL, recalcula os indicadores do mês e atualiza o Data Warehouse.",
          "Códigos: AGUA_PRODUZIDA, AGUA_CONSUMIDA, ENERGIA_CONSUMIDA, GD_POTENCIA, RESIDUOS_COLETADOS, RESIDUOS_RECICLADOS, TP_PASSAGEIROS, CO2_TRANSPORTE."]:
    tr.append([t])
for row in tr.iter_rows():
    for c in row: c.font = Font(name="Consolas" if c.value and c.value.startswith("CALL") else F, size=10)
wb.save("EcoCity_dados_municipios_SP.xlsx")
print("ok", r - H - 1, "linhas")
