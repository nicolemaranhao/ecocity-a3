"""DER conceitual (notação de Peter Chen com cardinalidade mínima e máxima) do EcoCity.
Gera: der_conceitual.png (para o documento) e der_conceitual.drawio (editável no draw.io).
Leitura da cardinalidade: o par (mín,máx) escrito JUNTO de uma entidade diz quantas ocorrências
DELA se ligam a UMA ocorrência da entidade do outro lado do losango."""
import json, subprocess, pathlib, html
OUT = pathlib.Path(__file__).parent

# entidade: (grupo, rótulo)
ENT = {
 'ORGAO': 'A', 'FONTE_DADOS': 'A', 'LOTE_CARGA': 'A', 'STG_MEDICAO_BRUTA': 'A', 'COLETA_VERIFICACAO': 'A',
 'SERVICO_PUBLICO': 'B', 'UNIDADE_MEDIDA': 'B', 'METRICA': 'B', 'DADO': 'B', 'MUNICIPIO': 'B', 'POPULACAO_ANUAL': 'B',
 'INDICADOR': 'C', 'INDICADOR_VALOR': 'C', 'META': 'C', 'ANALISE_IA': 'C',
 'PERFIL': 'D', 'USUARIO': 'D', 'CREDENCIAL_ANALISTA': 'D', 'CADASTRO_PROFISSIONAL': 'D', 'ACESSO_LOG': 'D', 'AUDITORIA': 'D',
 'ACAO': 'E', 'RESULTADO': 'E',
 'ANALISE_PUBLICADA': 'F', 'ANALISE_EVIDENCIA': 'F', 'ANALISE_COMENTARIO': 'F',
 'RELATORIO_IA': 'G', 'PERGUNTA_IA': 'G',
}
GRUPO = {'A': ('Fontes e cargas', '#FCE7F3'), 'B': ('Cidades e medições', '#E0E7FF'), 'C': ('Indicadores e metas', '#DCFCE7'),
         'D': ('Pessoas e segurança', '#F1F5F9'), 'E': ('Ações', '#FEF3C7'), 'F': ('Análises dos analistas', '#FCE7F3'),
         'G': ('Copiloto (IA)', '#CCFBF1')}


# Atributos principais de cada entidade (DER conceitual: identificador + principais; FKs ficam no modelo lógico/CP3)
ATR = {
 'ORGAO': ['#id_orgao', 'nome', 'sigla', 'tipo'],
 'FONTE_DADOS': ['#id_fonte', 'nome', 'formato', 'frequência', 'link', 'confiabilidade'],
 'LOTE_CARGA': ['#id_lote', 'início / fim', 'lidos / válidos / rejeitados', 'status'],
 'STG_MEDICAO_BRUTA': ['#id_stg', 'métrica, cidade, data e valor (texto)', 'origem e referência informadas', 'erro'],
 'CADASTRO_PROFISSIONAL': ['#id_usuario (é o próprio usuário)', 'órgão, cargo e matrícula', 'documento comprobatório', 'status da análise', 'válido até'],
 'COLETA_VERIFICACAO': ['#id_verificacao', 'quando conferiu', 'versão publicada', 'situação', 'mensagem'],
 'SERVICO_PUBLICO': ['#id_servico', 'nome', 'descrição'],
 'UNIDADE_MEDIDA': ['#id_unidade', 'sigla', 'descrição'],
 'METRICA': ['#id_metrica', 'código', 'nome'],
 'DADO': ['#id_dado', 'mês de referência', 'valor', 'qualidade', 'origem', 'referência da origem'],
 'MUNICIPIO': ['#id_municipio', 'nome', 'código IBGE', 'região metropolitana', 'área'],
 'POPULACAO_ANUAL': ['#ano', 'população', 'fonte'],
 'INDICADOR': ['#id_indicador', 'código', 'nome', 'fórmula', 'sentido', 'ODS', 'peso'],
 'INDICADOR_VALOR': ['#id_indicador_valor', 'mês', 'valor', 'origem'],
 'META': ['#id_meta', 'meta escrita (descrição)', 'valor e ponto de partida', 'vigência e prazo', 'como atingir (projetos)', 'justificativa e referência', 'status e parecer'],
 'ANALISE_IA': ['#id_analise', 'tipo', 'título', 'descrição', 'confiança', 'severidade', 'status'],
 'PERFIL': ['#id_perfil', 'nome', 'validade da senha'],
 'USUARIO': ['#id_usuario', 'nome', 'e-mail', 'senha (hash)', 'ativo', 'situação do cadastro', 'bloqueado até'],
 'CREDENCIAL_ANALISTA': ['órgão de vínculo', 'registro profissional', 'nível', 'status', 'válida até'],
 'ACESSO_LOG': ['#id_acesso', 'e-mail tentado', 'resultado', 'IP', 'data/hora'],
 'AUDITORIA': ['#id_auditoria', 'tabela', 'operação', 'usuário do banco', 'antes / depois', 'data/hora'],
 'ACAO': ['#id_acao', 'título', 'descrição', 'início / fim previsto', 'orçamento', 'status'],
 'RESULTADO': ['#id_resultado', 'valor antes', 'valor depois', 'data', 'avaliação'],
 'ANALISE_PUBLICADA': ['#id_analise_pub', 'título', 'resumo', 'texto', 'período', 'status', 'nível de confiança', 'versão'],
 'ANALISE_EVIDENCIA': ['#id_evidencia', 'tipo', 'consulta SQL / link', 'descrição'],
 'ANALISE_COMENTARIO': ['#id_comentario', 'texto', 'data'],
 'RELATORIO_IA': ['#id_relatorio', 'título', 'público', 'período', 'texto', 'dados usados', '% base oficial', 'status'],
 'PERGUNTA_IA': ['#id_pergunta', 'pergunta', 'SQL gerado', 'situação', 'motivo do bloqueio'],
}

def rotulo_html(e, externa=False):
    if externa:
        return f'<<B>{e}</B>>'
    linhas = ''.join(f'<TR><TD ALIGN="LEFT"><FONT POINT-SIZE="10">{"<U>"+a[1:]+"</U> (id)" if a.startswith("#") else html.escape(a)}</FONT></TD></TR>' for a in ATR[e])
    return f'<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="2"><TR><TD><B>{e}</B></TD></TR><HR/>{linhas}</TABLE>>'

# (entidade A, verbo, entidade B, cardinalidade junto de A, cardinalidade junto de B)
# Ex.: ('ORGAO','publica','FONTE_DADOS','(1,1)','(0,N)') = cada fonte é publicada por (1,1) órgão;
#      cada órgão publica (0,N) fontes.
REL = [
 ('ORGAO', 'publica', 'FONTE_DADOS', '(1,1)', '(0,N)'),
 ('SERVICO_PUBLICO', 'abrange', 'FONTE_DADOS', '(1,1)', '(0,N)'),
 ('FONTE_DADOS', 'gera', 'LOTE_CARGA', '(1,1)', '(0,N)'),
 ('LOTE_CARGA', 'recebe', 'STG_MEDICAO_BRUTA', '(1,1)', '(0,N)'),
 ('FONTE_DADOS', 'é conferida em', 'COLETA_VERIFICACAO', '(1,1)', '(0,N)'),
 ('LOTE_CARGA', 'resulta de', 'COLETA_VERIFICACAO', '(0,1)', '(0,N)'),
 ('SERVICO_PUBLICO', 'classifica', 'METRICA', '(1,1)', '(0,N)'),
 ('UNIDADE_MEDIDA', 'expressa', 'METRICA', '(1,1)', '(0,N)'),
 ('FONTE_DADOS', 'fornece', 'DADO', '(1,1)', '(0,N)'),
 ('LOTE_CARGA', 'carrega', 'DADO', '(0,1)', '(0,N)'),
 ('METRICA', 'é medida em', 'DADO', '(1,1)', '(0,N)'),
 ('MUNICIPIO', 'tem', 'DADO', '(1,1)', '(0,N)'),
 ('MUNICIPIO', 'tem', 'POPULACAO_ANUAL', '(1,1)', '(0,N)'),
 ('SERVICO_PUBLICO', 'agrupa', 'INDICADOR', '(1,1)', '(0,N)'),
 ('UNIDADE_MEDIDA', 'expressa', 'INDICADOR', '(1,1)', '(0,N)'),
 ('INDICADOR', 'resulta em', 'INDICADOR_VALOR', '(1,1)', '(0,N)'),
 ('MUNICIPIO', 'obtém', 'INDICADOR_VALOR', '(1,1)', '(0,N)'),
 ('INDICADOR', 'tem', 'META', '(1,1)', '(0,N)'),
 ('MUNICIPIO', 'tem meta própria', 'META', '(0,1)', '(0,N)'),
 ('USUARIO', 'propõe', 'META', '(1,1)', '(0,N)'),
 ('USUARIO', 'dá parecer', 'META', '(0,1)', '(0,N)'),
 ('USUARIO', 'aprova', 'META', '(0,1)', '(0,N)'),
 ('INDICADOR', 'é analisado', 'ANALISE_IA', '(1,1)', '(0,N)'),
 ('MUNICIPIO', 'é analisado', 'ANALISE_IA', '(1,1)', '(0,N)'),
 ('USUARIO', 'valida', 'ANALISE_IA', '(0,1)', '(0,N)'),
 ('PERFIL', 'define', 'USUARIO', '(1,1)', '(0,N)'),
 ('USUARIO', 'comprova vínculo', 'CADASTRO_PROFISSIONAL', '(1,1)', '(0,1)'),
 ('MUNICIPIO', 'é atendido por', 'CADASTRO_PROFISSIONAL', '(0,1)', '(0,N)'),
 ('MUNICIPIO', 'é de interesse', 'USUARIO', '(0,1)', '(0,N)'),
 ('USUARIO', 'possui', 'CREDENCIAL_ANALISTA', '(1,1)', '(0,1)'),
 ('SERVICO_PUBLICO', 'habilita', 'CREDENCIAL_ANALISTA', '(0,1)', '(0,N)'),
 ('USUARIO', 'verifica', 'CREDENCIAL_ANALISTA', '(0,1)', '(0,N)'),
 ('USUARIO', 'avalia', 'FONTE_DADOS', '(0,1)', '(0,N)'),
 ('USUARIO', 'tenta entrar', 'ACESSO_LOG', '(0,1)', '(0,N)'),
 ('MUNICIPIO', 'recebe', 'ACAO', '(1,1)', '(0,N)'),
 ('INDICADOR', 'é alvo de', 'ACAO', '(1,1)', '(0,N)'),
 ('USUARIO', 'é responsável', 'ACAO', '(1,1)', '(0,N)'),
 ('ANALISE_IA', 'motiva', 'ACAO', '(0,1)', '(0,N)'),
 ('ACAO', 'produz', 'RESULTADO', '(1,1)', '(0,N)'),
 ('INDICADOR', 'mede', 'RESULTADO', '(1,1)', '(0,N)'),
 ('USUARIO', 'registra', 'RESULTADO', '(1,1)', '(0,N)'),
 ('SERVICO_PUBLICO', 'classifica', 'ANALISE_PUBLICADA', '(1,1)', '(0,N)'),
 ('USUARIO', 'escreve', 'ANALISE_PUBLICADA', '(1,1)', '(0,N)'),
 ('USUARIO', 'revisa', 'ANALISE_PUBLICADA', '(0,1)', '(0,N)'),
 ('ANALISE_PUBLICADA', 'trata de', 'MUNICIPIO', '(0,N)', '(0,N)'),       # N:N (tabela analise_municipio)
 ('ANALISE_PUBLICADA', 'comprova', 'ANALISE_EVIDENCIA', '(1,1)', '(0,N)'),
 ('INDICADOR', 'é citado', 'ANALISE_EVIDENCIA', '(0,1)', '(0,N)'),
 ('ANALISE_PUBLICADA', 'recebe', 'ANALISE_COMENTARIO', '(1,1)', '(0,N)'),
 ('USUARIO', 'comenta', 'ANALISE_COMENTARIO', '(1,1)', '(0,N)'),
 ('USUARIO', 'solicita', 'RELATORIO_IA', '(1,1)', '(0,N)'),
 ('USUARIO', 'aprova', 'RELATORIO_IA', '(0,1)', '(0,N)'),
 ('RELATORIO_IA', 'abrange', 'MUNICIPIO', '(0,N)', '(1,N)'),             # N:N (tabela relatorio_municipio)
 ('USUARIO', 'pergunta', 'PERGUNTA_IA', '(1,1)', '(0,N)'),
]


FIGURAS = [
 ('der_1_dados_indicadores', 'Figura 1 — Dados, indicadores e metas',
  ['ORGAO', 'FONTE_DADOS', 'LOTE_CARGA', 'STG_MEDICAO_BRUTA', 'COLETA_VERIFICACAO', 'SERVICO_PUBLICO', 'UNIDADE_MEDIDA', 'METRICA', 'DADO',
   'MUNICIPIO', 'POPULACAO_ANUAL', 'INDICADOR', 'INDICADOR_VALOR', 'META'], []),
 ('der_2_pessoas_seguranca', 'Figura 2 — Pessoas, segurança e responsáveis pelas metas',
  ['PERFIL', 'USUARIO', 'CADASTRO_PROFISSIONAL', 'CREDENCIAL_ANALISTA', 'ACESSO_LOG', 'AUDITORIA'], ['SERVICO_PUBLICO', 'FONTE_DADOS', 'META', 'MUNICIPIO']),
 ('der_3_analises', 'Figura 3 — Análises (dos analistas e automáticas da IA)',
  ['ANALISE_PUBLICADA', 'ANALISE_EVIDENCIA', 'ANALISE_COMENTARIO', 'ANALISE_IA'],
  ['USUARIO', 'INDICADOR', 'MUNICIPIO', 'SERVICO_PUBLICO']),
 ('der_4_acoes_copiloto', 'Figura 4 — Ações, resultados e Copiloto (IA)',
  ['ACAO', 'RESULTADO', 'RELATORIO_IA', 'PERGUNTA_IA'],
  ['USUARIO', 'INDICADOR', 'MUNICIPIO', 'ANALISE_IA']),
]

def figura(nome, titulo, principais, externas):
    todas = principais + externas
    rels = [(i, r) for i, r in enumerate(REL) if r[0] in todas and r[2] in todas and (r[0] in principais or r[2] in principais)]
    g = ['graph DER {', f'graph [layout=dot, rankdir=LR, nodesep=0.35, ranksep=0.55, splines=true, pad=0.35, fontname="Helvetica", '
         f'label="{titulo}\\nNotação de Chen — (mín,máx) escrito no traço de cada entidade", labelloc=t, fontsize=22];',
         'node [fontname="Helvetica"]; edge [fontname="Helvetica-Bold", fontsize=13, fontcolor="#B45309", color="#475569", penwidth=1.4];']
    for e in todas:
        if e in externas:
            g.append(f'"{e}" [shape=box, style="dashed,filled", fillcolor="#F8FAFC", color="#94A3B8", fontcolor="#64748B", fontsize=13, width=2.2, height=0.55, label={rotulo_html(e, True)}];')
        else:
            g.append(f'"{e}" [shape=box, style="filled,bold", fillcolor="{GRUPO[ENT[e]][1]}", color="#1E293B", fontsize=13, margin="0.1,0.05", label={rotulo_html(e)}];')
    for i, (a, v, b, ca, cb) in rels:
        r = f'R{i}'
        nn = ca.endswith('N)') and cb.endswith('N)')
        g.append(f'"{r}" [shape=diamond, label="{v}", style=filled, fillcolor="{"#FDE68A" if nn else "#FFFFFF"}", color="#1E293B", fontsize=11, width=1.5, height=0.65, margin=0.02];')
        g.append(f'"{a}" -- "{r}" [label="{ca}"];')
        g.append(f'"{r}" -- "{b}" [label="{cb}"];')
    if 'AUDITORIA' in principais:
        g.append('"nota_aud" [shape=note, fontsize=11, color="#94A3B8", fontcolor="#475569", label="AUDITORIA não se liga por FK:\\nguarda o histórico de alterações\\nde qualquer tabela (via triggers)"];')
        g.append('"AUDITORIA" -- "nota_aud" [style=dotted, color="#94A3B8"];')
    g.append('}')
    src = '\n'.join(g)
    (OUT / f'{nome}.dot').write_text(src)
    subprocess.run(['dot', '-Tpng', '-Gdpi=150', '-o', str(OUT / f'{nome}.png')], input=src.encode(), check=True)
    subprocess.run(['dot', '-Tsvg', '-o', str(OUT / f'{nome}.svg')], input=src.encode(), check=True)
    return json.loads(subprocess.run(['dot', '-Tjson'], input=src.encode(), check=True, capture_output=True).stdout), rels

def pagina_drawio(nome, titulo, principais, externas, lay, rels):
    bb = [float(x) for x in lay['bb'].split(',')]
    H = bb[3]
    pos = {}
    for o in lay['objects']:
        if 'pos' in o:
            x, y = map(float, o['pos'].split(','))
            pos[o['name']] = (x, H - y, float(o['width']) * 72, float(o['height']) * 72)
    cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
    cid, ids = [2], {}
    def nid():
        cid[0] += 1
        return cid[0]
    cells.append(f'<mxCell id="{nid()}" value="{html.escape(titulo)} — notação de Chen, (mín,máx) escrito no traço de cada entidade" style="text;fontSize=20;fontStyle=1;align=left;" vertex="1" parent="1"><mxGeometry x="0" y="-50" width="1100" height="36" as="geometry"/></mxCell>')
    for e in principais + externas:
        x, y, w, h = pos[e]
        ids[e] = nid()
        estilo = ('dashed=1;fillColor=#F8FAFC;strokeColor=#94A3B8;fontColor=#64748B;' if e in externas
                  else f'fillColor={GRUPO[ENT[e]][1]};strokeColor=#1E293B;strokeWidth=2;fontStyle=1;')
        val = e if e in externas else '<b>' + e + '</b><hr>' + '<br>'.join(('<u>' + a[1:] + '</u> (id)') if a.startswith('#') else html.escape(a) for a in ATR[e])
        cells.append(f'<mxCell id="{ids[e]}" value="{html.escape(val)}" style="rounded=0;whiteSpace=wrap;html=1;fontSize=12;align=left;verticalAlign=top;spacingLeft=6;{estilo}" vertex="1" parent="1"><mxGeometry x="{x-w/2:.0f}" y="{y-h/2:.0f}" width="{w:.0f}" height="{h:.0f}" as="geometry"/></mxCell>')
    for i, (a, v, b, ca, cb) in rels:
        r = f'R{i}'
        x, y, w, h = pos[r]
        nn = ca.endswith('N)') and cb.endswith('N)')
        ids[r] = nid()
        cells.append(f'<mxCell id="{ids[r]}" value="{html.escape(v)}" style="rhombus;whiteSpace=wrap;html=1;fillColor={"#FDE68A" if nn else "#FFFFFF"};strokeColor=#1E293B;fontSize=11;" vertex="1" parent="1"><mxGeometry x="{x-w/2:.0f}" y="{y-h/2:.0f}" width="{w:.0f}" height="{h:.0f}" as="geometry"/></mxCell>')
        for ent, card, xl in ((a, ca, -0.65), (b, cb, 0.65)):
            src, tgt = (ids[ent], ids[r]) if ent == a else (ids[r], ids[ent])
            eid = nid()
            cells.append(f'<mxCell id="{eid}" style="endArrow=none;html=1;strokeColor=#475569;strokeWidth=1.4;" edge="1" parent="1" source="{src}" target="{tgt}"><mxGeometry relative="1" as="geometry"/></mxCell>')
            cells.append(f'<mxCell id="{nid()}" value="{card}" style="edgeLabel;html=1;fontStyle=1;fontColor=#B45309;fontSize=13;labelBackgroundColor=#FFFFFF;" vertex="1" connectable="0" parent="{eid}"><mxGeometry x="{xl}" relative="1" as="geometry"><mxPoint as="offset"/></mxGeometry></mxCell>')
    return f'<diagram name="{html.escape(titulo.split(" — ")[0])}"><mxGraphModel grid="1" gridSize="10" page="0"><root>' + ''.join(cells) + '</root></mxGraphModel></diagram>'

paginas = []
for nome, titulo, princ, ext in FIGURAS:
    lay, rels = figura(nome, titulo, princ, ext)
    paginas.append(pagina_drawio(nome, titulo, princ, ext, lay, rels))
(OUT / 'EcoCity_DER.drawio').write_text('<mxfile host="app.diagrams.net">' + ''.join(paginas) + '</mxfile>', encoding='utf-8')
print('ok')
