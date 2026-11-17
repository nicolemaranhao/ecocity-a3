"""DER preliminar do EcoCity (Checkpoint 2) — UMA figura, notação de Chen/Heuser com (mín,máx).
Layout feito à mão em grade para que nenhuma linha cruze outra.
Gera: EcoCity_DER_preliminar.drawio, link_drawio.txt (abre direto no draw.io) e preview.svg (conferência)."""
import base64, html, pathlib, urllib.parse, zlib

OUT = pathlib.Path(__file__).parent
CW, RH = 380, 250                    # distância entre colunas e entre linhas da grade
X0, Y0 = 140, 190                    # centro da coluna 0 / linha 0
EW = 200                             # largura das entidades
DW, DH = 96, 50                      # tamanho dos losangos

COR = {'dados': '#E0E7FF', 'ind': '#DCFCE7', 'acao': '#FEF3C7', 'pessoas': '#F1F5F9', 'analise': '#FCE7F3'}

# nome: (coluna, linha, grupo, atributos)  — '#' = identificador (sublinhado)
ENT = {
 'ORGAO':               (0, 0, 'dados', ['#id_orgao', 'nome', 'sigla']),
 'FONTE_DADOS':         (1, 0, 'dados', ['#id_fonte', 'nome', 'frequência', 'confiabilidade (1 a 5)']),
 'DADO':                (2, 0, 'dados', ['#id_dado', 'mês de referência', 'valor', 'origem']),
 'METRICA':             (3, 0, 'dados', ['#id_metrica', 'código', 'nome']),
 'SERVICO_PUBLICO':     (4, 0, 'dados', ['#id_servico', 'nome', 'descrição']),
 'POPULACAO_ANUAL':     (1, 1, 'dados', ['#ano', 'população']),
 'MUNICIPIO':           (2, 1, 'dados', ['#id_municipio', 'nome', 'código IBGE', 'área (km²)']),
 'INDICADOR_VALOR':     (3, 1, 'ind',   ['#id_indicador_valor', 'mês', 'valor', 'origem']),
 'INDICADOR':           (4, 1, 'ind',   ['#id_indicador', 'código', 'nome', 'fórmula', 'peso no índice']),
 'ANALISE_IA':          (5, 1, 'ind',   ['#id_analise', 'tipo', 'severidade', 'status']),
 'ANALISE_PUBLICADA':   (2, 2, 'analise', ['#id_analise_pub', 'título', 'texto', 'nível de confiança', 'status']),
 'RELATORIO_IA':        (3, 2, 'analise', ['#id_relatorio', 'título', 'período', 'status']),
 'META':                (4, 2, 'ind',   ['#id_meta', 'valor', 'vigência', 'status']),
 'ACAO':                (5, 2, 'acao',  ['#id_acao', 'título', 'orçamento', 'status']),
 'RESULTADO':           (6, 2, 'acao',  ['#id_resultado', 'valor antes', 'valor depois', 'avaliação']),
 'CREDENCIAL_ANALISTA': (1, 3, 'pessoas', ['registro profissional', 'nível', 'status', 'válida até']),
 'USUARIO':             (2, 3, 'pessoas', ['#id_usuario', 'nome', 'e-mail', 'telefone', 'senha (hash)', 'situação do cadastro']),
 'CADASTRO_PROFISSIONAL': (3, 4, 'pessoas', ['#id_usuario', 'CPF (protegido)', 'e-mail institucional', 'órgão e cargo', 'documento de vínculo', 'status (aprovado pelo admin)']),
 'PERFIL':              (2, 4, 'pessoas', ['#id_perfil', 'nome']),
}

def geo(e):
    c, r, _, at = ENT[e]
    h = 30 + 18 * len(at)
    cx, cy = X0 + CW * c, Y0 + RH * r
    return cx - EW / 2, cy - h / 2, EW, h

def ponto(e, fx, fy):
    x, y, w, h = geo(e)
    return x + w * fx, y + h * fy

# (A, verbo, B, card. junto de A, card. junto de B, saída de A (fx,fy), entrada em B (fx,fy), pontos de dobra, centro do losango)
# None nos pontos = linha reta entre os centros; losango no meio.
# Leitura: o (mín,máx) junto de uma entidade = quantas ocorrências DELA se ligam a UMA do outro lado.
REL = [
 ('ORGAO', 'publica', 'FONTE_DADOS', '(1,1)', '(0,N)'),
 ('FONTE_DADOS', 'fornece', 'DADO', '(1,1)', '(0,N)'),
 ('DADO', 'refere-se a', 'METRICA', '(0,N)', '(1,1)'),
 ('METRICA', 'pertence a', 'SERVICO_PUBLICO', '(0,N)', '(1,1)'),
 ('DADO', 'é de', 'MUNICIPIO', '(0,N)', '(1,1)'),
 ('POPULACAO_ANUAL', 'de', 'MUNICIPIO', '(1,N)', '(1,1)'),
 ('MUNICIPIO', 'obtém', 'INDICADOR_VALOR', '(1,1)', '(0,N)'),
 ('INDICADOR_VALOR', 'calcula', 'INDICADOR', '(0,N)', '(1,1)'),
 ('SERVICO_PUBLICO', 'agrupa', 'INDICADOR', '(1,1)', '(1,N)'),
 ('INDICADOR', 'gera alerta', 'ANALISE_IA', '(1,1)', '(0,N)'),
 ('INDICADOR', 'tem', 'META', '(1,1)', '(0,N)'),
 ('ANALISE_IA', 'motiva', 'ACAO', '(0,1)', '(0,N)'),
 ('ACAO', 'produz', 'RESULTADO', '(1,1)', '(0,N)'),
 ('MUNICIPIO', 'é tratado em', 'ANALISE_PUBLICADA', '(1,N)', '(0,N)'),
 ('MUNICIPIO', 'é abrangido', 'RELATORIO_IA', '(1,N)', '(0,N)',
  (0.85, 1), (0.5, 0), 'abr'),
 ('ANALISE_PUBLICADA', 'escreve', 'USUARIO', '(0,N)', '(1,1)'),
 ('RELATORIO_IA', 'solicita', 'USUARIO', '(0,N)', '(1,1)', (0.5, 1), (1, 0.2), 'sol'),
 ('CREDENCIAL_ANALISTA', 'possui', 'USUARIO', '(0,1)', '(1,1)'),
 ('PERFIL', 'define', 'USUARIO', '(1,1)', '(0,N)'),
 ('META', 'propõe', 'USUARIO', '(0,N)', '(1,1)', (0.5, 1), (1, 0.45), 'pro'),
 ('ACAO', 'é responsável', 'USUARIO', '(0,N)', '(1,1)', (0.5, 1), (1, 0.9), 'res'),
 ('USUARIO', 'comprova', 'CADASTRO_PROFISSIONAL', '(1,1)', '(0,1)', (0.9, 1), (0.5, 0), 'cad'),
]

def tracado(rel):
    """Devolve (pA, pontos A->losango, centro do losango, pontos losango->B, pB, orientação de cada ponta)."""
    a, _, b, *_ = rel
    if len(rel) == 5:                                   # reta
        ax, ay, aw, ah = geo(a); bx, by, bw, bh = geo(b)
        acx, acy, bcx, bcy = ax + aw / 2, ay + ah / 2, bx + bw / 2, by + bh / 2
        if abs(acy - bcy) < 1:                          # horizontal
            pa, pb = ((ax + aw, acy), (bx, bcy)) if acx < bcx else ((ax, acy), (bx + bw, bcy))
            ori = ('h', 'h')
        else:
            pa, pb = ((acx, ay + ah), (bcx, by)) if acy < bcy else ((acx, ay), (bcx, by + bh))
            ori = ('v', 'v')
        d = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2)
        return pa, [], d, [], pb, ori
    _, _, _, _, _, sa, eb, kind = rel
    pa, pb = ponto(a, *sa), ponto(b, *eb)
    if kind == 'abr':      # desce de MUNICIPIO, vai à direita, desce em RELATORIO_IA
        ym = (geo('MUNICIPIO')[1] + geo('MUNICIPIO')[3] + geo('ANALISE_PUBLICADA')[1]) / 2
        d = ((pa[0] + pb[0]) / 2, ym)
        return pa, [(pa[0], ym)], d, [(pb[0], ym)], pb, ('v', 'v')
    if kind == 'cad':      # desce de USUARIO pela direita da base, vai à direita e desce no CADASTRO
        ym = pa[1] + 40
        d = ((pa[0] + pb[0]) / 2 + 10, ym)
        return pa, [(pa[0], ym)], d, [(pb[0], ym)], pb, ('v', 'v')
    if kind == 'sol':      # desce de RELATORIO_IA e entra pela direita de USUARIO
        d = (pa[0], (pa[1] + pb[1]) / 2 - 8)
        return pa, [], d, [(pa[0], pb[1])], pb, ('v', 'h')
    # 'pro' e 'res': saem pela direita de USUARIO (lado B), sobem até a entidade A
    xa = pa[0]
    if kind == 'pro':
        d = ((pb[0] + xa) / 2 + 20, pb[1])
    else:
        d = ((ponto('META', 0.5, 1)[0] + xa) / 2, pb[1])
    return pa, [(xa, pb[1])], d, [], pb, ('v', 'h')

# ---------------------------------------------------------------- draw.io
cells, nid = [], [1]
def novo():
    nid[0] += 1; return f'c{nid[0]}'
def esc(s): return html.escape(s, quote=True)

def rotulo(e):
    at = ''.join(f'<u>{a[1:]}</u><br>' if a.startswith('#') else f'{html.escape(a)}<br>' for a in ENT[e][3])
    return f'<div style="text-align:center"><b>{e}</b></div><hr size="1">{at[:-4]}'

ids = {}
for e, (c, r, g, at) in ENT.items():
    x, y, w, h = geo(e); i = novo(); ids[e] = i
    st = (f'rounded=0;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacingLeft=8;spacingTop=2;fontSize=11;'
          f'fillColor={COR[g]};strokeColor=#1E293B;strokeWidth=1.5;')
    cells.append(f'<mxCell id="{i}" value="{esc(rotulo(e))}" style="{st}" vertex="1" parent="1">'
                 f'<mxGeometry x="{x:.0f}" y="{y:.0f}" width="{w}" height="{h:.0f}" as="geometry"/></mxCell>')

def edge(src, tgt, pts, ex, en, label, lab_pos, lab_ori):
    i = novo()
    st = 'endArrow=none;html=1;rounded=0;strokeColor=#334155;strokeWidth=1.3;'
    st += f'exitX={ex[0]};exitY={ex[1]};exitDx=0;exitDy=0;entryX={en[0]};entryY={en[1]};entryDx=0;entryDy=0;'
    pts_xml = ''.join(f'<mxPoint x="{x:.0f}" y="{y:.0f}"/>' for x, y in pts)
    arr = f'<Array as="points">{pts_xml}</Array>' if pts else ''
    cells.append(f'<mxCell id="{i}" style="{st}" edge="1" parent="1" source="{src}" target="{tgt}">'
                 f'<mxGeometry relative="1" as="geometry">{arr}</mxGeometry></mxCell>')
    # cardinalidade: rótulo da própria linha, encostado na entidade (x=-0.6 perto da origem / 0.6 perto do destino)
    off = '<mxPoint x="0" y="-11" as="offset"/>' if lab_ori == 'h' else '<mxPoint x="20" y="0" as="offset"/>'
    j = novo()
    cells.append(f'<mxCell id="{j}" value="{label}" style="edgeLabel;html=1;align=center;verticalAlign=middle;resizable=0;'
                 f'points=[];fontStyle=1;fontSize=11;fontColor=#B45309;labelBackgroundColor=#FFFFFF;" vertex="1" connectable="0" parent="{i}">'
                 f'<mxGeometry x="{lab_pos}" relative="1" as="geometry">{off}</mxGeometry></mxCell>')

def frac(e, p):
    x, y, w, h = geo(e)
    return round((p[0] - x) / w, 3), round((p[1] - y) / h, 3)

preview_rel = []
for rel in REL:
    a, verbo, b, ca, cb = rel[:5]
    pa, p1, d, p2, pb, ori = tracado(rel)
    nn = ca.endswith('N)') and cb.endswith('N)')
    di = novo()
    cells.append(f'<mxCell id="{di}" value="{esc(verbo)}" style="rhombus;whiteSpace=wrap;html=1;fontSize=10;'
                 f'fillColor={"#FDE68A" if nn else "#FFFFFF"};strokeColor=#1E293B;" vertex="1" parent="1">'
                 f'<mxGeometry x="{d[0]-DW/2:.0f}" y="{d[1]-DH/2:.0f}" width="{DW}" height="{DH}" as="geometry"/></mxCell>')
    # entrada/saída do losango: lado voltado para o trecho
    def lado(prev):
        dx, dy = prev[0] - d[0], prev[1] - d[1]
        if abs(dx) > abs(dy): return (0, 0.5) if dx < 0 else (1, 0.5)
        return (0.5, 0) if dy < 0 else (0.5, 1)
    ultimo_a = p1[-1] if p1 else pa
    prim_b = p2[0] if p2 else pb
    if len(rel) > 5 and rel[7] in ('pro', 'res'):   # A fica acima: chega ao losango vindo de cima (dobra) e sai à esquerda para USUARIO
        edge(ids[a], di, [], frac(a, pa), (1, 0.5) if False else lado(ultimo_a), ca, -0.55, 'v')
        # dobra fica no 1º trecho: A desce até a altura do losango
        cells[-2] = cells[-2].replace('<mxGeometry relative="1" as="geometry">',
                                      f'<mxGeometry relative="1" as="geometry"><Array as="points"><mxPoint x="{pa[0]:.0f}" y="{pb[1]:.0f}"/></Array>')
        edge(di, ids[b], [], (0, 0.5), frac(b, pb), cb, 0.75, 'h')
    else:
        edge(ids[a], di, p1, frac(a, pa), lado(ultimo_a), ca, -0.55, ori[0])
        edge(di, ids[b], p2, lado(prim_b), frac(b, pb), cb, 0.55, ori[1])
    preview_rel.append((a, verbo, b, ca, cb, pa, p1, d, p2, pb, nn, rel))

# título, legenda e nota
def texto(x, y, w, h, val, st):
    i = novo()
    cells.append(f'<mxCell id="{i}" value="{esc(val)}" style="{st}" vertex="1" parent="1">'
                 f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
texto(40, 20, 1500, 60, '<b style="font-size:22px">EcoCity — DER preliminar (modelo conceitual)</b><br>'
      '<span style="font-size:13px">A3 Banco de Dados · Checkpoint 2 · notação de Chen com cardinalidade (mín,máx)</span>',
      'text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;')
LEG = ('<b>Como ler</b><br>'
       '▭ <b>Retângulo</b> = entidade (vira tabela)<br>'
       '◇ <b>Losango</b> = relacionamento (verbo)<br>'
       '<u>sublinhado</u> = identificador (chave)<br>'
       '<b style="color:#B45309">(mín,máx)</b> junto da entidade = quantas<br>'
       'vezes ELA aparece para UMA do outro lado<br>'
       '<span style="background:#FDE68A">&nbsp;losango amarelo&nbsp;</span> = N:N (vira tabela associativa)<br><br>'
       '<b>Exemplo:</b> ORGAO (1,1) — publica — (0,N) FONTE_DADOS<br>'
       'Cada fonte é publicada por 1 órgão;<br>cada órgão publica de 0 a N fontes.')
texto(40, Y0 + RH * 1 - 70, 260, 250, LEG,
      'text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;fontSize=11;fillColor=#FFFFFF;strokeColor=#94A3B8;spacing=10;rounded=1;arcSize=4;')
NOTA = ('<b>Fica para o modelo lógico (Checkpoint 3)</b><br>'
        'Tabelas de apoio: UNIDADE_MEDIDA, LOTE_CARGA, STG_MEDICAO_BRUTA, ACESSO_LOG, AUDITORIA, '
        'ANALISE_EVIDENCIA, ANALISE_COMENTARIO, PERGUNTA_IA e o Data Warehouse (dim_* e fato_*).<br>'
        'Também no CP3: chaves estrangeiras, tipos de dado e os vínculos extras '
        '(quem dá parecer e aprova a meta, quem revisa análises, quem avalia a fonte, qual admin aprovou o cadastro).')
texto(40, Y0 + RH * 3 - 40, 260, 250, NOTA,
      'text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;fontSize=11;fillColor=#F8FAFC;strokeColor=#CBD5E1;dashed=1;spacing=10;rounded=1;arcSize=4;')
# faixas de grupo (legenda de cores)
gx = X0 + CW * 4 - EW / 2; gy = Y0 + RH * 4 - 70
for k, (g, nome) in enumerate([('dados', 'Cidades, fontes e dados mensais'), ('ind', 'Indicadores, metas e alertas'),
                               ('analise', 'Análises e relatórios'), ('acao', 'Ações e resultados'), ('pessoas', 'Pessoas e acesso')]):
    texto(gx, gy + k * 30, 22, 18, '', f'rounded=0;fillColor={COR[g]};strokeColor=#1E293B;')
    texto(gx + 30, gy + k * 30 - 3, 300, 24, nome, 'text;html=1;align=left;verticalAlign=middle;fontSize=12;')

xml = ('<mxfile host="app.diagrams.net"><diagram id="der" name="DER preliminar">'
       '<mxGraphModel dx="1600" dy="1000" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" '
       'page="1" pageScale="1" pageWidth="2600" pageHeight="1400" math="0" shadow="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/>'
       + ''.join(cells) + '</root></mxGraphModel></diagram></mxfile>')
(OUT / 'EcoCity_DER_preliminar.drawio').write_text(xml, encoding='utf-8')

raw = urllib.parse.quote(xml, safe="~()*!.'-_")      # = encodeURIComponent
comp = zlib.compressobj(9, zlib.DEFLATED, -15)
dados = comp.compress(raw.encode()) + comp.flush()
link = 'https://app.diagrams.net/#R' + urllib.parse.quote(base64.b64encode(dados).decode(), safe='')
(OUT / 'link_drawio.txt').write_text(link)

# ---------------------------------------------------------------- preview SVG (só para conferir cruzamentos)
s = ['<svg xmlns="http://www.w3.org/2000/svg" width="2700" height="1350" font-family="Helvetica" font-size="11"><rect width="100%" height="100%" fill="white"/>']
for a, verbo, b, ca, cb, pa, p1, d, p2, pb, nn, rel in preview_rel:
    if len(rel) > 5 and rel[7] in ('pro', 'res'):
        pts = [pa, (pa[0], pb[1]), pb]
    else:
        pts = [pa] + p1 + [d] + p2 + [pb]
    s.append('<polyline fill="none" stroke="#334155" stroke-width="1.3" points="' + ' '.join(f'{x:.0f},{y:.0f}' for x, y in pts) + '"/>')
    s.append(f'<polygon points="{d[0]},{d[1]-DH/2} {d[0]+DW/2},{d[1]} {d[0]},{d[1]+DH/2} {d[0]-DW/2},{d[1]}" fill="{"#FDE68A" if nn else "white"}" stroke="#1E293B"/>')
    s.append(f'<text x="{d[0]}" y="{d[1]+4}" text-anchor="middle" font-size="10">{html.escape(verbo)}</text>')
    s.append(f'<text x="{pa[0]+14}" y="{pa[1]+16}" fill="#B45309" font-weight="bold">{ca}</text>')
    s.append(f'<text x="{pb[0]+4}" y="{pb[1]-14}" fill="#B45309" font-weight="bold">{cb}</text>')
for e in ENT:
    x, y, w, h = geo(e)
    s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{COR[ENT[e][2]]}" stroke="#1E293B" stroke-width="1.5"/>')
    s.append(f'<text x="{x+w/2}" y="{y+18}" text-anchor="middle" font-weight="bold">{e}</text>')
    for k, at in enumerate(ENT[e][3]):
        s.append(f'<text x="{x+8}" y="{y+44+18*k}" {"text-decoration=\"underline\"" if at.startswith("#") else ""}>{html.escape(at.lstrip("#"))}</text>')
s.append('</svg>')
(OUT / 'preview.svg').write_text('\n'.join(s), encoding='utf-8')
print('link', len(link), 'chars')

# ---------------------------------------------------------------- figura em alta resolução (para o documento)
def _pts(rel_t):
    a, verbo, b, ca, cb, pa, p1, d, p2, pb, nn, rel = rel_t
    if len(rel) > 5 and rel[7] in ('pro', 'res'):
        return [pa, (pa[0], pb[1]), d, pb]
    return [pa] + p1 + [d] + p2 + [pb]

def _rot(p, q, txt):            # rótulo (mín,máx) encostado na entidade, ao lado da linha
    dx, dy = q[0] - p[0], q[1] - p[1]
    n = max((dx * dx + dy * dy) ** 0.5, 1)
    ux, uy = dx / n, dy / n
    x, y = p[0] + ux * 24, p[1] + uy * 24
    if abs(ux) > abs(uy):  # trecho horizontal: rótulo acima
        return f'<text x="{x:.0f}" y="{y - 7:.0f}" text-anchor="middle" class="card">{txt}</text>'
    return f'<text x="{x + 8:.0f}" y="{y + 5:.0f}" text-anchor="start" class="card">{txt}</text>'

LARG, ALT = 2580, 1310
f = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{LARG}" height="{ALT}" viewBox="0 0 {LARG} {ALT}" font-family="Arial, Helvetica, sans-serif">',
     '<style>.card{font-size:15px;font-weight:bold;fill:#B45309}.at{font-size:13px}.nome{font-size:13px;font-weight:bold}.verbo{font-size:12px}</style>',
     '<rect width="100%" height="100%" fill="white"/>',
     '<text x="40" y="52" font-size="30" font-weight="bold">EcoCity — DER preliminar (modelo conceitual)</text>',
     '<text x="40" y="82" font-size="17" fill="#334155">A3 Banco de Dados · Checkpoint 2 · notação de Chen com cardinalidade (mín,máx)</text>']
for t in preview_rel:
    pts = _pts(t)
    f.append('<polyline fill="none" stroke="#334155" stroke-width="1.6" points="' + ' '.join(f'{x:.0f},{y:.0f}' for x, y in pts) + '"/>')
for t in preview_rel:
    a, verbo, b, ca, cb, pa, p1, d, p2, pb, nn, rel = t
    pts = _pts(t)
    f.append(f'<polygon points="{d[0]},{d[1]-DH/2} {d[0]+DW/2},{d[1]} {d[0]},{d[1]+DH/2} {d[0]-DW/2},{d[1]}" fill="{"#FDE68A" if nn else "white"}" stroke="#1E293B" stroke-width="1.3"/>')
    f.append(f'<text x="{d[0]}" y="{d[1]+4}" text-anchor="middle" class="verbo">{html.escape(verbo)}</text>')
    f.append(_rot(pts[0], pts[1], ca))
    f.append(_rot(pts[-1], pts[-2], cb))
for e in ENT:
    x, y, w, h = geo(e)
    f.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{COR[ENT[e][2]]}" stroke="#1E293B" stroke-width="1.8"/>')
    f.append(f'<text x="{x+w/2}" y="{y+19}" text-anchor="middle" class="nome">{e}</text>')
    f.append(f'<line x1="{x}" y1="{y+27}" x2="{x+w}" y2="{y+27}" stroke="#1E293B"/>')
    for k, at in enumerate(ENT[e][3]):
        f.append(f'<text x="{x+8}" y="{y+44+18*k}" class="at" {"text-decoration=\"underline\"" if at.startswith("#") else ""}>{html.escape(at.lstrip("#"))}</text>')
# legenda e nota
lx, ly = 40, Y0 + RH * 1 - 70
leg = ['Como ler', '▭ Retângulo = entidade (vira tabela)', '◇ Losango = relacionamento (verbo)', 'sublinhado = identificador (chave)',
       '(mín,máx) junto da entidade = quantas vezes', 'ELA aparece para UMA do outro lado', 'Losango amarelo = N:N (vira tabela associativa)', '',
       'Exemplo: ORGAO (1,1) — publica — (0,N) FONTE_DADOS', 'Cada fonte é publicada por 1 órgão;', 'cada órgão publica de 0 a N fontes.']
f.append(f'<rect x="{lx}" y="{ly}" width="300" height="245" rx="8" fill="white" stroke="#94A3B8"/>')
for k, t in enumerate(leg):
    f.append(f'<text x="{lx+12}" y="{ly+26+20*k}" font-size="{14 if k == 0 else 12.5}" {"font-weight=\"bold\"" if k in (0, 8) else ""}>{html.escape(t)}</text>')
ny = Y0 + RH * 3 - 40
nota = ['Fica para o modelo lógico (Checkpoint 3)', 'Tabelas de apoio: UNIDADE_MEDIDA,', 'LOTE_CARGA, STG_MEDICAO_BRUTA,', 'ACESSO_LOG, AUDITORIA,',
        'ANALISE_EVIDENCIA, ANALISE_COMENTARIO,', 'PERGUNTA_IA e o Data Warehouse.', 'Também no CP3: chaves estrangeiras,',
        'tipos de dado e os vínculos extras', '(aprovação da meta, revisão de análises,', 'avaliação das fontes e do cadastro).']
f.append(f'<rect x="{lx}" y="{ny}" width="290" height="225" rx="8" fill="#F8FAFC" stroke="#CBD5E1" stroke-dasharray="5,4"/>')
for k, t in enumerate(nota):
    f.append(f'<text x="{lx+12}" y="{ny+26+20*k}" font-size="{13.5 if k == 0 else 12.5}" {"font-weight=\"bold\"" if k == 0 else ""}>{html.escape(t)}</text>')
gx, gy = X0 + CW * 4 - EW / 2, Y0 + RH * 4 - 70
for k, (g, nome) in enumerate([('dados', 'Cidades, fontes e dados mensais'), ('ind', 'Indicadores, metas e alertas'),
                               ('analise', 'Análises e relatórios'), ('acao', 'Ações e resultados'), ('pessoas', 'Pessoas, cadastro e acesso')]):
    f.append(f'<rect x="{gx}" y="{gy + k*30}" width="24" height="18" fill="{COR[g]}" stroke="#1E293B"/>')
    f.append(f'<text x="{gx+34}" y="{gy + k*30 + 14}" font-size="14">{nome}</text>')
f.append('</svg>')
(OUT / 'EcoCity_DER_preliminar.svg').write_text('\n'.join(f), encoding='utf-8')
