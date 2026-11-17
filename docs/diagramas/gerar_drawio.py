"""Gera o DER do EcoCity no formato do draw.io (diagrams.net), lendo o banco real.

Saída: docs/diagramas/EcoCity_DER.drawio  (6 páginas: Figura 1 a Figura 6)
Abra em https://app.diagrams.net  (Arquivo > Abrir do dispositivo) ou no draw.io desktop.
Cada tabela é uma caixa com as colunas (PK, FK, UK); cada relacionamento é uma linha
saindo da PK da tabela "1" até a FK da tabela "N", com os rótulos 1 e N nas pontas.
"""
import json
import pathlib
import subprocess
from xml.sax.saxutils import escape as _esc


def escape(s):
    return _esc(s, {'"': '&quot;'})

import pymysql

OUT = pathlib.Path(__file__).parent
con = pymysql.connect(unix_socket='/var/run/mysqld/mysqld.sock', user='root', database='information_schema', charset='utf8mb4')
cur = con.cursor()
cur.execute("""SELECT table_name, column_name, column_type, column_key, is_nullable FROM columns
               WHERE table_schema='ecocity' ORDER BY table_name, ordinal_position""")
cols = {}
for t, c, ty, k, n in cur.fetchall():
    cols.setdefault(t, []).append((c, ty, k, n))
cur.execute("""SELECT table_name, column_name, referenced_table_name, referenced_column_name FROM key_column_usage
               WHERE table_schema='ecocity' AND referenced_table_name IS NOT NULL ORDER BY table_name, column_name""")
fks = cur.fetchall()
fkcols = {(t, c) for t, c, _, _ in fks}

COR = {  # cor do cabeçalho por assunto
    'municipio': '#0EA5E9', 'populacao_anual': '#334155', 'orgao': '#0EA5E9', 'fonte_dados': '#0EA5E9',
    'servico_publico': '#64748B', 'unidade_medida': '#64748B', 'metrica': '#4F46E5', 'dado': '#4F46E5',
    'lote_carga': '#DB2777', 'stg_medicao_bruta': '#DB2777', 'indicador': '#16A34A', 'indicador_valor': '#16A34A',
    'meta': '#B45309', 'perfil': '#475569', 'usuario': '#475569', 'acesso_log': '#475569', 'auditoria': '#475569',
    'credencial_analista': '#7C3AED', 'analise_publicada': '#BE185D', 'analise_municipio': '#BE185D',
    'analise_evidencia': '#BE185D', 'analise_comentario': '#BE185D', 'analise_ia': '#9333EA',
    'acao': '#D97706', 'resultado': '#D97706', 'relatorio_ia': '#0D9488', 'relatorio_municipio': '#0D9488', 'pergunta_ia': '#0D9488',
}
PAGINAS = [
    ('Figura 1 - Dados e metas', ['orgao', 'fonte_dados', 'servico_publico', 'unidade_medida', 'metrica', 'lote_carga', 'stg_medicao_bruta',
                                  'municipio', 'populacao_anual', 'dado', 'indicador', 'indicador_valor', 'meta']),
    ('Figura 2 - Usuários e segurança', ['perfil', 'usuario', 'acesso_log', 'credencial_analista', 'servico_publico', 'municipio', 'auditoria']),
    ('Figura 3 - Análises dos analistas', ['usuario', 'municipio', 'indicador', 'servico_publico', 'analise_publicada', 'analise_municipio',
                                          'analise_evidencia', 'analise_comentario']),
    ('Figura 4 - Alertas da IA e ações', ['usuario', 'municipio', 'indicador', 'analise_ia', 'acao', 'resultado']),
    ('Figura 5 - Copiloto', ['usuario', 'municipio', 'relatorio_ia', 'relatorio_municipio', 'pergunta_ia']),
    ('Figura 6 - Data Warehouse', ['dim_tempo', 'dim_municipio', 'dim_servico', 'dim_metrica', 'dim_indicador', 'fato_medicao', 'fato_indicador']),
]
W, CAB, LIN = 270, 30, 22
CONTEXTO = {  # em cada figura, tabelas que só aparecem como referência (resumidas)
    'Figura 2 - Usuários e segurança': {'municipio', 'servico_publico'},
    'Figura 3 - Análises dos analistas': {'usuario', 'municipio', 'indicador', 'servico_publico'},
    'Figura 4 - Alertas da IA e ações': {'usuario', 'municipio', 'indicador'},
    'Figura 5 - Copiloto': {'usuario', 'municipio'},
}


def tipo_curto(ty):
    return ty.split('(')[0].replace(' unsigned', '').upper()


def colunas(t, ctx):
    if t not in ctx:
        return cols[t]
    return [x for x in cols[t] if x[2] == 'PRI' or x[0] in ('nome', 'codigo')]


def layout(tabs, arestas, ctx):
    """Usa o Graphviz só para calcular posições sem sobreposição."""
    dot = 'digraph G { graph [rankdir=LR, nodesep=0.6, ranksep=1.6]; node [shape=box, fixedsize=true];\n'
    for t in tabs:
        h = CAB + LIN * len(colunas(t, ctx))
        dot += f'"{t}" [width={W / 72:.2f}, height={h / 72:.2f}];\n'
    for a, b in arestas:
        dot += f'"{a}" -> "{b}";\n'
    dot += '}'
    j = json.loads(subprocess.run(['dot', '-Tjson'], input=dot, capture_output=True, text=True, check=True).stdout)
    alt = float(j['bb'].split(',')[3])
    pos = {}
    for o in j['objects']:
        x, y = map(float, o['pos'].split(','))
        h = CAB + LIN * len(colunas(o['name'], ctx))
        pos[o['name']] = (round(x - W / 2) + 40, round(alt - y - h / 2) + 70)
    return pos


def pagina(nome, tabs, idx):
    ctx = CONTEXTO.get(nome, set())
    arestas = [(ref, t) for t, c, ref, _ in fks if t in tabs and ref in tabs and t not in ctx]
    pos = layout(tabs, arestas, ctx)
    cel = []
    nid = [0]

    def novo():
        nid[0] += 1
        return f'p{idx}c{nid[0]}'
    linha_id = {}
    titulo = novo()
    cel.append(f'<mxCell id="{titulo}" value="{escape(nome.replace(" - ", " — "))}" style="text;html=1;fontSize=22;fontStyle=1;align=left;verticalAlign=middle;fillColor=none;strokeColor=none;fontColor=#0F172A;" vertex="1" parent="1"><mxGeometry x="40" y="10" width="900" height="40" as="geometry"/></mxCell>')
    for t in tabs:
        x, y = pos[t]
        h = CAB + LIN * len(colunas(t, ctx))
        tid = novo()
        borda = 'dashed=1;' if t in ctx else ''
        cor = COR.get(t, '#0F766E' if t.startswith('fato') else '#334155')
        # caixa da tabela (container): o cabeçalho e as linhas são filhos, então tudo se move junto
        cel.append(f'<mxCell id="{tid}" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#94A3B8;{borda}container=1;collapsible=0;recursiveResize=0;" '
                   f'vertex="1" parent="1"><mxGeometry x="{x}" y="{y}" width="{W}" height="{h}" as="geometry"/></mxCell>')
        cel.append(f'<mxCell id="{novo()}" value="{t.upper() + (' (resumida)' if t in ctx else '')}" style="rounded=0;whiteSpace=wrap;html=1;fillColor={cor};strokeColor=none;fontColor=#FFFFFF;fontStyle=1;fontSize=13;connectable=0;" '
                   f'vertex="1" parent="{tid}"><mxGeometry width="{W}" height="{CAB}" as="geometry"/></mxCell>')
        for i, (c, ty, k, n) in enumerate(colunas(t, ctx)):
            tag = 'PK' if k == 'PRI' else ('FK' if (t, c) in fkcols else ('UK' if k == 'UNI' else ''))
            if k == 'PRI' and (t, c) in fkcols:
                tag = 'PK,FK'
            estilo = 'fontStyle=1;' if 'PK' in tag else ('fontStyle=4;' if tag == 'FK' else '')
            yy = CAB + LIN * i
            fundo = '#F8FAFC' if i % 2 else '#FFFFFF'
            rid = novo()
            linha_id[(t, c)] = rid
            cel.append(f'<mxCell id="{rid}" value="{escape(c)}" style="text;html=1;fillColor={fundo};strokeColor=none;align=left;verticalAlign=middle;spacingLeft=52;'
                       f'fontSize=11;fontColor=#1E293B;{estilo}points=[[0,0.5],[1,0.5]];portConstraint=eastwest;" vertex="1" parent="{tid}">'
                       f'<mxGeometry y="{yy}" width="{W}" height="{LIN}" as="geometry"/></mxCell>')
            if tag:
                cel.append(f'<mxCell id="{novo()}" value="{tag}" style="text;html=1;fillColor=none;strokeColor=none;align=left;verticalAlign=middle;spacingLeft=6;'
                           f'fontSize=10;fontStyle=1;fontColor=#B45309;connectable=0;" vertex="1" parent="{tid}"><mxGeometry y="{yy}" width="48" height="{LIN}" as="geometry"/></mxCell>')
            cel.append(f'<mxCell id="{novo()}" value="{tipo_curto(ty)}{"" if n == "YES" else " NN"}" style="text;html=1;fillColor=none;strokeColor=none;align=right;verticalAlign=middle;'
                       f'spacingRight=6;fontSize=9;fontColor=#64748B;connectable=0;" vertex="1" parent="{tid}"><mxGeometry x="{W - 110}" y="{yy}" width="110" height="{LIN}" as="geometry"/></mxCell>')
    tabelas_xml = cel
    cel = []
    for t, c, ref, refc in fks:
        if t not in tabs or ref not in tabs or t in ctx:
            continue
        pks = [cc for cc, _ty, k, _n in cols[t] if k == 'PRI']
        lado_filho = '1' if pks == [c] else 'N'
        eid = novo()
        cel.append(f'<mxCell id="{eid}" style="edgeStyle=entityRelationEdgeStyle;html=1;endArrow=none;startArrow=none;strokeColor=#64748B;strokeWidth=1.3;" '
                   f'edge="1" parent="1" source="{linha_id[(ref, refc)]}" target="{linha_id[(t, c)]}"><mxGeometry relative="1" as="geometry"/></mxCell>')
        for xr, txt in ((-1, '1'), (1, lado_filho)):
            cel.append(f'<mxCell id="{novo()}" value="{txt}" style="edgeLabel;html=1;resizable=0;fontSize=14;fontStyle=1;fontColor=#B45309;labelBackgroundColor=#FFFFFF;" '
                       f'vertex="1" connectable="0" parent="{eid}"><mxGeometry x="{xr * 0.85}" relative="1" as="geometry"><mxPoint as="offset"/></mxGeometry></mxCell>')
    larg = max(x for x, _ in pos.values()) + W + 80
    alt = max(y + CAB + LIN * len(colunas(t, ctx)) for t, (_x, y) in pos.items()) + 60
    return (f'<diagram id="pag{idx}" name="{escape(nome)}"><mxGraphModel dx="{larg}" dy="{alt}" grid="1" gridSize="10" guides="1" tooltips="1" '
            f'connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="{larg}" pageHeight="{alt}" math="0" shadow="0"><root>'
            f'<mxCell id="0"/><mxCell id="1" parent="0"/>{"".join(cel)}{"".join(tabelas_xml)}</root></mxGraphModel></diagram>')


xml = '<mxfile host="EcoCity" version="24.0.0">' + ''.join(pagina(n, t, i) for i, (n, t) in enumerate(PAGINAS, 1)) + '</mxfile>'
(OUT / 'EcoCity_DER.drawio').write_text(xml, encoding='utf-8')
print('ok', OUT / 'EcoCity_DER.drawio')
