"""
EcoCity — Camada de IA (apoio à decisão)
-----------------------------------------
Lê a série histórica dos indicadores no MySQL e gera insights na tabela
`analise_ia`. Os insights NÃO substituem o especialista: entram com status
'NOVA' e precisam ser validados ou descartados por um especialista/gestor.

Técnicas (leves, explicáveis e auditáveis), sobre a série MENSAL:
  * TENDENCIA  -> compara os 3 últimos meses com os MESMOS meses do ano anterior
                  (assim a sazonalidade — verão, férias — não engana a análise) e
                  exige que a direção se repita na maioria dos 12 meses comparáveis
  * PREVISAO   -> projeção linear: em quantos meses a meta será atingida
  * ANOMALIA   -> z-score da variação anual do último mês contra as anteriores

Uso:
  pip install pymysql numpy
  set ECOCITY_DB_HOST / ECOCITY_DB_USER / ECOCITY_DB_PASS (usuário ecocity_etl)
  python analise_ia.py            # grava no banco
  python analise_ia.py --dry-run  # só mostra os insights
"""
import os
import sys
from collections import defaultdict

import numpy as np
import pymysql

MODELO = "ecocity-ia-v1.0-mensal"
DRY = "--dry-run" in sys.argv

conn = pymysql.connect(
    host=os.getenv("ECOCITY_DB_HOST", "127.0.0.1"),
    user=os.getenv("ECOCITY_DB_USER", "ecocity_etl"),
    password=os.getenv("ECOCITY_DB_PASS", "Etl#EcoCity2026!"),
    database="ecocity",
    charset="utf8mb4",
)
cur = conn.cursor(pymysql.cursors.DictCursor)

MAX_INSIGHTS = 12   # só os mais relevantes, para não poluir a fila do especialista
cur.execute("""
    SELECT i.id_indicador, i.codigo, i.nome, i.meta, i.sentido, u.sigla AS unidade,
           r.id_municipio, r.nome AS municipio, iv.periodo, iv.valor, iv.origem
    FROM indicador_valor iv
    JOIN indicador i ON i.id_indicador = iv.id_indicador
    JOIN unidade_medida u ON u.id_unidade = i.id_unidade
    JOIN municipio r ON r.id_municipio = iv.id_municipio
    ORDER BY i.id_indicador, r.id_municipio, iv.periodo
""")
series = defaultdict(list)
meta_info = {}
estimado = {}
for row in cur.fetchall():
    k = (row["id_indicador"], row["id_municipio"])
    series[k].append(float(row["valor"]))
    meta_info[k] = row
    estimado.setdefault(k, []).append(row["origem"])

MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
insights = []
for k, ys in series.items():
    if len(ys) < 15:         # precisa de 12 meses + 3 meses para comparar ano contra ano
        continue
    info = meta_info[k]
    y = np.array(ys)
    meta = float(info["meta"])
    bom_sobe = info["sentido"] == "MAIOR_MELHOR"
    nome, cidade, un = info["nome"], info["municipio"], info["unidade"]
    ult = info["periodo"]                                   # último mês da série
    origens = estimado[k][-15:]
    pct_ofic = 100 * sum(o != "ESTIMADO" for o in origens) / len(origens)
    aviso = (f" Base: {pct_ofic:.0f}% de dados oficiais ou calculados de dado oficial."
             + (" Atenção: maioria de dados ESTIMADOS — confirmar antes de agir." if pct_ofic < 50 else ""))
    fator_conf = 1.0 if pct_ofic >= 50 else 0.7

    # --- Tendência: últimos 3 meses x mesmos meses do ano anterior ---
    atual, anterior = y[-3:].mean(), y[-15:-12].mean()
    var12 = (atual - anterior) / (abs(anterior) or 1) * 100
    yoy = y[12:] / np.where(y[:-12] == 0, 1, y[:-12]) - 1           # variação de cada mês contra o mesmo mês do ano anterior
    consist = float(np.mean(np.sign(yoy) == np.sign(var12))) if var12 != 0 else 0
    melhora = (var12 > 0) == bom_sobe
    if abs(var12) >= 2 and consist >= 0.75:
        insights.append(dict(
            k=k, tipo="TENDENCIA", sev="INFO" if melhora else "ATENCAO", conf=round(consist * 100 * fator_conf, 2),
            titulo=f"{nome}: tendência de {'melhora' if melhora else 'piora'} em {cidade}",
            desc=(f"Nos 3 últimos meses a média foi {atual:.2f} {un}, {var12:+.1f}% em relação aos mesmos meses do ano "
                  f"anterior ({anterior:.2f}). A direção se repetiu em {consist*100:.0f}% dos meses comparáveis. "
                  f"Meta: {meta:g} {un}." + aviso)))

        # --- Previsão: em quantos meses atinge a meta? ---
        fora = (y[-1] < meta) if bom_sobe else (y[-1] > meta)
        passo = (atual - anterior) / 12                           # variação média por mês
        if fora and melhora and passo != 0:
            n = int(np.ceil((meta - y[-1]) / passo))
            if 0 < n <= 60:
                ano, mes = ult.year + (ult.month - 1 + n) // 12, (ult.month - 1 + n) % 12
                insights.append(dict(
                    k=k, tipo="PREVISAO", sev="INFO", conf=round(consist * 80 * fator_conf, 2),
                    titulo=f"{cidade} deve atingir a meta de {nome.lower()} por volta de {MESES[mes]}/{ano}",
                    desc=(f"Mantido o ritmo dos últimos 12 meses ({passo:+.3f} {un} por mês), a projeção linear indica "
                          f"a meta de {meta:g} {un} em cerca de {n} meses." + aviso)))

    # --- Anomalia: a variação anual do último mês foge do padrão? ---
    hist = yoy[:-1]
    sd = hist.std(ddof=1) if len(hist) >= 6 else 0
    if sd > 0:
        z = (yoy[-1] - hist.mean()) / sd
        if abs(z) >= 3 and abs(yoy[-1] - hist.mean()) >= 0.05:
            ruim = (z < 0) == bom_sobe
            insights.append(dict(
                k=k, tipo="ANOMALIA", sev="CRITICO" if ruim else "INFO", conf=round(min(99, 50 + abs(z) * 8) * fator_conf, 2),
                titulo=f"Mudança brusca de {nome.lower()} em {cidade}",
                desc=(f"Em {MESES[ult.month-1]}/{ult.year} o valor ({y[-1]:.2f} {un}) variou {yoy[-1]*100:+.1f}% contra o mesmo mês "
                      f"do ano anterior, fora do padrão dos meses anteriores (média {hist.mean()*100:+.1f}%, z = {z:.1f}). "
                      f"Verificar a fonte de dados." + aviso)))

# prioridade: atenção/crítico primeiro, depois maior confiança
ordem = {"CRITICO": 0, "ATENCAO": 1, "INFO": 2}
insights.sort(key=lambda i: (ordem[i["sev"]], -i["conf"]))
por_ind, por_cid, escolhidos = defaultdict(int), defaultdict(int), []
for i in insights:                      # variedade: no máximo 2 por indicador e 2 por cidade
    if por_ind[i["k"][0]] < 2 and por_cid[i["k"][1]] < 2:
        por_ind[i["k"][0]] += 1
        por_cid[i["k"][1]] += 1
        escolhidos.append(i)
insights = escolhidos[:MAX_INSIGHTS]
print(f"{len(insights)} insights gerados pelo modelo {MODELO}")
for i in insights:
    print(f" [{i['tipo']:<9}|{i['sev']:<7}] {i['titulo']}")

if not DRY:
    for i in insights:
        cur.execute("""INSERT INTO analise_ia (id_indicador, id_municipio, tipo, titulo, descricao,
                       confianca, severidade, modelo_versao) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (i["k"][0], i["k"][1], i["tipo"], i["titulo"][:150], i["desc"], i["conf"], i["sev"], MODELO))
    conn.commit()
    print("Gravado em analise_ia.")
conn.close()
