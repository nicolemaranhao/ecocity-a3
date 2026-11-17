"""Gera o DER (core 3FN) e o modelo estrela (DW) a partir do banco real (information_schema)."""
import pymysql, subprocess, pathlib
OUT = pathlib.Path(__file__).parent
c = pymysql.connect(host='127.0.0.1', user='root', database='information_schema', charset='utf8mb4', unix_socket='/var/run/mysqld/mysqld.sock')
cur = c.cursor()
cur.execute("""SELECT table_name, column_name, column_type, column_key, is_nullable FROM columns
               WHERE table_schema='ecocity' ORDER BY table_name, ordinal_position""")
cols = {}
for t, col, typ, key, nul in cur.fetchall():
    cols.setdefault(t, []).append((col, typ, key, nul))
cur.execute("""SELECT table_name, column_name, referenced_table_name FROM key_column_usage
               WHERE table_schema='ecocity' AND referenced_table_name IS NOT NULL""")
fks = cur.fetchall()
fkcols = {(t, col) for t, col, _ in fks}
cur.execute("SELECT table_name FROM views WHERE table_schema='ecocity'")
views = {r[0] for r in cur.fetchall()}

COR = {'municipio': '#0EA5E9', 'dado': '#4F46E5', 'indicador': '#22C55E', 'indicador_valor': '#22C55E', 'analise_ia': '#A855F7',
       'acao': '#F59E0B', 'resultado': '#F59E0B', 'usuario': '#64748B', 'perfil': '#64748B', 'fonte_dados': '#0EA5E9', 'orgao': '#0EA5E9',
       'metrica': '#4F46E5', 'unidade_medida': '#94A3B8', 'servico_publico': '#94A3B8', 'lote_carga': '#EC4899', 'stg_medicao_bruta': '#EC4899', 'auditoria': '#475569',
       'relatorio_ia': '#0D9488', 'relatorio_municipio': '#0D9488', 'pergunta_ia': '#0D9488',
       'meta': '#B45309', 'credencial_analista': '#7C3AED', 'acesso_log': '#475569', 'analise_publicada': '#BE185D', 'analise_municipio': '#BE185D', 'analise_evidencia': '#BE185D', 'analise_comentario': '#BE185D'}

def node(t, color, compact=False):
    rows = ''
    for col, typ, key, nul in cols[t]:
        if compact and key != 'PRI' and (t, col) not in fkcols and col not in ('nome', 'valor', 'codigo', 'data_referencia', 'periodo', 'status', 'meta', 'score', 'titulo'):
            continue
        tag = 'PK' if key == 'PRI' else ('FK' if (t, col) in fkcols else ('UK' if key == 'UNI' else ''))
        if key == 'PRI' and (t, col) in fkcols: tag = 'PK,FK'
        b1, b2 = ('<B>', '</B>') if 'PK' in tag else ('', '')
        typ_s = typ.split('(')[0].replace(' unsigned', '').upper()
        rows += f'<TR><TD ALIGN="LEFT"><FONT COLOR="#6B7280" POINT-SIZE="8">{tag or " "}</FONT></TD><TD ALIGN="LEFT">{b1}{col}{b2}</TD><TD ALIGN="LEFT"><FONT COLOR="#6B7280" POINT-SIZE="8">{typ_s}{"" if nul=="YES" else " NN"}</FONT></TD></TR>'
    return (f'"{t}" [label=<<TABLE BORDER="1" COLOR="#CBD5E1" CELLBORDER="0" CELLSPACING="0" CELLPADDING="3" BGCOLOR="white">'
            f'<TR><TD COLSPAN="3" BGCOLOR="{color}"><FONT COLOR="white"><B>{t.upper()}</B></FONT></TD></TR>{rows}</TABLE>>];\n')

def gerar(nome, tabelas, titulo, rankdir='LR', compact=False):
    dot = f'digraph G {{ graph [rankdir={rankdir}, fontname="Helvetica", fontsize=20, labelloc=t, label="{titulo}", pad=0.4, nodesep=0.5, ranksep=0.9, bgcolor="white", splines=spline];\n'
    dot += 'node [shape=plaintext, fontname="Helvetica", fontsize=10]; edge [color="#64748B", dir=none, penwidth=1.2, fontname="Helvetica-Bold", fontsize=13, fontcolor="#B45309", labeldistance=1.6, labelangle=25];\n'
    for t in tabelas:
        dot += node(t, COR.get(t, '#0F766E' if t.startswith('fato') else '#334155'), compact)
    for t, col, ref in fks:
        if t in tabelas and ref in tabelas:
            pks = [c for c, _ty, k, _n in cols[t] if k == 'PRI']
            um_para_um = pks == [col]          # a FK é a própria PK inteira -> 1:1
            dot += f'"{ref}" -> "{t}" [taillabel="1", headlabel="{"1" if um_para_um else "N"}", tooltip="{col}"];\n'
    dot += '}'
    (OUT / f'{nome}.dot').write_text(dot)
    subprocess.run(['dot', '-Tpng', '-Gdpi=170', str(OUT / f'{nome}.dot'), '-o', str(OUT / f'{nome}.png')], check=True)
    subprocess.run(['dot', '-Tsvg', str(OUT / f'{nome}.dot'), '-o', str(OUT / f'{nome}.svg')], check=True)

GRUPOS = {
    'der_1_dados_indicadores': (['orgao', 'fonte_dados', 'servico_publico', 'unidade_medida', 'metrica', 'lote_carga', 'stg_medicao_bruta',
                                 'municipio', 'populacao_anual', 'dado', 'indicador', 'indicador_valor', 'meta'],
                                'Figura 1 — Integração, medições mensais, indicadores e metas'),
    'der_2_pessoas_analises': (['perfil', 'usuario', 'acesso_log', 'credencial_analista', 'servico_publico', 'municipio', 'indicador',
                                'analise_publicada', 'analise_municipio', 'analise_evidencia', 'analise_comentario', 'analise_ia',
                                'acao', 'resultado', 'auditoria'],
                               'Figura 2 — Usuários, segurança, análises dos analistas e ações'),
    'der_3_copiloto': (['usuario', 'municipio', 'relatorio_ia', 'relatorio_municipio', 'pergunta_ia'],
                       'Figura 3 — Copiloto EcoCity (relatórios e perguntas da IA)'),
}
for nome, (tabs, tit) in GRUPOS.items():
    gerar(nome, tabs, tit)
core = sorted({t for tabs, _ in GRUPOS.values() for t in tabs})
gerar('der_core_3fn', core, 'EcoCity — DER completo da camada relacional (3FN) — MySQL 8')
dw = ['dim_tempo', 'dim_municipio', 'dim_servico', 'dim_metrica', 'dim_indicador', 'fato_medicao', 'fato_indicador']
gerar('der_dw_estrela', dw, 'Figura 4 — Data Warehouse em modelo estrela (grão mensal)')
print('ok', sorted(p.name for p in OUT.glob('*.png')))
