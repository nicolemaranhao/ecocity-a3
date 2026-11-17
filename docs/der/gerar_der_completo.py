"""DER COMPLETO do EcoCity (Checkpoint 2) — modelo conceitual, notação de Chen com (mín,máx).
Todas as entidades do banco operacional e todos os relacionamentos que cabem sem cruzar linhas.
Layout e traçado feitos à mão; o script confere se alguma linha cruza outra ou passa por cima de uma caixa.
Gera: EcoCity_DER_completo.drawio, link_drawio.txt, EcoCity_DER_completo.svg (documento) e
      EcoCity_DER_completo_simples.svg (slide: nome + identificador)."""
import base64, html, pathlib, urllib.parse, zlib, itertools, sys

OUT = pathlib.Path(__file__).parent
DW, DH = 88, 44
COR = {'dados': '#E0E7FF', 'ind': '#DCFCE7', 'acao': '#FEF3C7', 'pessoas': '#F1F5F9', 'analise': '#FCE7F3'}
H = 64
Y = 100  # deslocamento vertical (espaço para os canais de cima)

# nome: (cx, cy, largura, altura, grupo, identificador)
ENT = {
 'ORGAO':               (560, 120, 200, H, 'dados', 'id_orgao'),
 'FONTE_DADOS':         (980, 120, 200, H, 'dados', 'id_fonte'),
 'SERVICO_PUBLICO':     (2240, 120, 240, H, 'dados', 'id_servico'),
 'DADO':                (980, 340, 200, H, 'dados', 'id_dado'),
 'METRICA':             (1560, 340, 200, H, 'dados', 'id_metrica'),
 'INDICADOR':           (2240, 340, 320, H, 'ind', 'id_indicador'),
 'META':                (2760, 340, 200, H, 'ind', 'id_meta'),
 'POPULACAO_ANUAL':     (150, 470, 200, H, 'dados', 'ano'),
 'MUNICIPIO':           (980, 590, 560, 100, 'dados', 'id_municipio'),
 'INDICADOR_VALOR':     (1540, 590, 200, H, 'ind', 'id_indicador_valor'),
 'ANALISE_IA':          (1860, 590, 200, H, 'ind', 'id_analise'),
 'ACAO':                (2240, 590, 200, H, 'acao', 'id_acao'),
 'RESULTADO':           (2680, 590, 200, H, 'acao', 'id_resultado'),
 'ANALISE_EVIDENCIA':   (150, 720, 200, H, 'analise', 'id_evidencia'),
 'ANALISE_PUBLICADA':   (380, 900, 220, H, 'analise', 'id_analise_pub'),
 'RELATORIO_IA':        (880, 900, 200, H, 'analise', 'id_relatorio'),
 'CADASTRO_PROFISSIONAL': (1460, 860, 260, H, 'pessoas', 'id_usuario'),
 'ANALISE_COMENTARIO':  (380, 1260, 220, H, 'analise', 'id_comentario'),
 'USUARIO':             (1460, 1150, 800, 100, 'pessoas', 'id_usuario'),
 'CREDENCIAL_ANALISTA': (2420, 1150, 220, H, 'pessoas', 'id_usuario'),
 'PERGUNTA_IA':         (820, 1400, 200, H, 'analise', 'id_pergunta'),
 'PERFIL':              (1300, 1400, 200, H, 'pessoas', 'id_perfil'),
}
# atributos principais (nomes iguais às colunas do banco; chaves estrangeiras não entram no conceitual)
ATR = {
 'ORGAO': ['nome', 'sigla', 'tipo'], 'FONTE_DADOS': ['nome', 'frequencia', 'confiabilidade'],
 'SERVICO_PUBLICO': ['nome', 'descricao'], 'DADO': ['data_referencia', 'valor', 'origem'],
 'METRICA': ['codigo', 'nome'], 'INDICADOR': ['codigo', 'nome', 'formula', 'peso_ies'],
 'META': ['valor', 'vigencia_inicio', 'status'], 'POPULACAO_ANUAL': ['populacao', 'fonte'],
 'MUNICIPIO': ['nome', 'codigo_ibge', 'uf'], 'INDICADOR_VALOR': ['periodo', 'valor', 'origem'],
 'ANALISE_IA': ['tipo', 'titulo', 'severidade'], 'ACAO': ['titulo', 'orcamento', 'status'],
 'RESULTADO': ['valor_antes', 'valor_depois', 'avaliacao'], 'ANALISE_PUBLICADA': ['titulo', 'status', 'nivel_confianca'],
 'RELATORIO_IA': ['titulo', 'tipo', 'status'], 'CADASTRO_PROFISSIONAL': ['cpf_hash', 'orgao', 'cargo'],
 'ANALISE_COMENTARIO': ['texto', 'criado_em'], 'USUARIO': ['nome', 'email', 'senha_hash'],
 'CREDENCIAL_ANALISTA': ['registro_profissional', 'nivel', 'valida_ate'], 'PERFIL': ['nome', 'exige_mfa'],
 'PERGUNTA_IA': ['pergunta', 'situacao'], 'ANALISE_EVIDENCIA': ['tipo', 'url', 'descricao'],
}
ENT = {k: (cx, cy + Y, w, 36 + 17 * (1 + len(ATR[k])), g, i) for k, (cx, cy, w, h, g, i) in ENT.items()}


def box(e):
    cx, cy, w, h, *_ = ENT[e]
    return cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2


def P(e, lado, d=0):
    """ponto na borda: lado t/b/l/r, deslocamento d a partir do centro"""
    x0, y0, x1, y1 = box(e)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return {'t': (cx + d, y0), 'b': (cx + d, y1), 'l': (x0, cy + d), 'r': (x1, cy + d)}[lado]


def y_(v): return v + Y


def reta(a, la, b, lb, da=0, db=0):
    return [P(a, la, da), P(b, lb, db)]


def L(a, la, da, b, lb, db, *meio):
    return [P(a, la, da)] + [(x, y_(y)) for x, y in meio] + [P(b, lb, db)]

# Relacionamentos: (A, verbo, B, card junto de A, card junto de B, rota, segmento do losango, posição no segmento)
# Leitura do (mín,máx): junto de uma entidade = quantas ocorrências DELA se ligam a UMA do outro lado.
R = []
def rel(a, v, b, ca, cb, rota, seg=None, f=0.5):
    R.append(dict(a=a, v=v, b=b, ca=ca, cb=cb, rota=rota, seg=seg, f=f))

# ---- cidades, fontes e dados
rel('ORGAO', 'publica', 'FONTE_DADOS', '(1,1)', '(0,N)', reta('ORGAO', 'r', 'FONTE_DADOS', 'l'))
rel('FONTE_DADOS', 'fornece', 'DADO', '(1,1)', '(0,N)', reta('FONTE_DADOS', 'b', 'DADO', 't', 30, 30))
rel('DADO', 'refere-se a', 'METRICA', '(0,N)', '(1,1)', reta('DADO', 'r', 'METRICA', 'l'))
rel('METRICA', 'pertence a', 'SERVICO_PUBLICO', '(0,N)', '(1,1)', L('METRICA', 't', 0, 'SERVICO_PUBLICO', 'l', 0, (1560, 120)), seg=1)
rel('FONTE_DADOS', 'trata de', 'SERVICO_PUBLICO', '(0,N)', '(1,1)', L('FONTE_DADOS', 't', 0, 'SERVICO_PUBLICO', 't', -60, (980, 30), (2180, 30)), seg=1)
rel('SERVICO_PUBLICO', 'agrupa', 'INDICADOR', '(1,1)', '(1,N)', reta('SERVICO_PUBLICO', 'b', 'INDICADOR', 't'))
rel('DADO', 'é de', 'MUNICIPIO', '(0,N)', '(1,1)', reta('DADO', 'b', 'MUNICIPIO', 't'))
rel('POPULACAO_ANUAL', 'de', 'MUNICIPIO', '(1,N)', '(1,1)', L('POPULACAO_ANUAL', 'b', 0, 'MUNICIPIO', 'l', -25, (150, 565)), seg=1, f=0.55)
# ---- indicadores, metas e ações
rel('MUNICIPIO', 'obtém', 'INDICADOR_VALOR', '(1,1)', '(0,N)', reta('MUNICIPIO', 'r', 'INDICADOR_VALOR', 'l'))
rel('INDICADOR_VALOR', 'é de', 'INDICADOR', '(0,N)', '(1,1)', L('INDICADOR_VALOR', 't', 0, 'INDICADOR', 'b', -130, (1540, 440), (2110, 440)), seg=1, f=0.45)
rel('INDICADOR', 'gera alerta', 'ANALISE_IA', '(1,1)', '(0,N)', L('INDICADOR', 'b', -70, 'ANALISE_IA', 't', 0, (2170, 500), (1860, 500)), seg=1, f=0.5)
rel('METRICA', 'é base de', 'INDICADOR', '(0,N)', '(0,N)', reta('METRICA', 'r', 'INDICADOR', 'l')) if False else None
rel('INDICADOR', 'tem', 'META', '(1,1)', '(0,N)', reta('INDICADOR', 'r', 'META', 'l'))
rel('ACAO', 'melhora', 'INDICADOR', '(0,N)', '(1,1)', reta('ACAO', 't', 'INDICADOR', 'b'))
rel('RESULTADO', 'mede', 'INDICADOR', '(0,N)', '(1,1)', L('RESULTADO', 't', 0, 'INDICADOR', 'b', 100, (2680, 470), (2340, 470)), seg=1)
rel('ANALISE_IA', 'é sobre', 'MUNICIPIO', '(0,N)', '(1,1)', L('ANALISE_IA', 'b', 0, 'MUNICIPIO', 'b', 250, (1860, 690), (1230, 690)), seg=1, f=0.45)
rel('ANALISE_IA', 'motiva', 'ACAO', '(0,1)', '(0,N)', reta('ANALISE_IA', 'r', 'ACAO', 'l'))
rel('MUNICIPIO', 'recebe', 'ACAO', '(1,1)', '(0,N)', L('MUNICIPIO', 'b', 200, 'ACAO', 'b', -40, (1180, 740), (2200, 740)), seg=1, f=0.72)
rel('ACAO', 'produz', 'RESULTADO', '(1,1)', '(0,N)', reta('ACAO', 'r', 'RESULTADO', 'l'))
# ---- análises e relatórios
rel('MUNICIPIO', 'é tratado em', 'ANALISE_PUBLICADA', '(1,N)', '(0,N)', L('MUNICIPIO', 'b', -260, 'ANALISE_PUBLICADA', 't', 40, (720, 790), (420, 790)), seg=1)
rel('ANALISE_EVIDENCIA', 'cita', 'MUNICIPIO', '(0,N)', '(0,1)', L('ANALISE_EVIDENCIA', 'r', 0, 'MUNICIPIO', 'l', 25, (420, 720), (420, 615)), seg=2, f=0.55)
rel('ANALISE_PUBLICADA', 'apoiada por', 'ANALISE_EVIDENCIA', '(1,1)', '(0,N)', L('ANALISE_PUBLICADA', 't', -60, 'ANALISE_EVIDENCIA', 'b', 0, (320, 820), (150, 820)), seg=1)
rel('SERVICO_PUBLICO', 'é tema de', 'ANALISE_PUBLICADA', '(1,1)', '(0,N)', L('SERVICO_PUBLICO', 't', 60, 'ANALISE_PUBLICADA', 'l', 0, (2300, -30), (-40, -30), (-40, 900)), seg=1, f=0.3)
rel('MUNICIPIO', 'é abrangido', 'RELATORIO_IA', '(1,N)', '(0,N)', reta('MUNICIPIO', 'b', 'RELATORIO_IA', 't', -100, 0))
rel('ANALISE_PUBLICADA', 'recebe', 'ANALISE_COMENTARIO', '(1,1)', '(0,N)', reta('ANALISE_PUBLICADA', 'b', 'ANALISE_COMENTARIO', 't'))
# ---- pessoas
rel('USUARIO', 'solicita', 'RELATORIO_IA', '(1,1)', '(0,N)', L('USUARIO', 'l', -35, 'RELATORIO_IA', 'b', 0, (880, 1115)), seg=1, f=0.5)
rel('USUARIO', 'escreve', 'ANALISE_PUBLICADA', '(1,1)', '(0,N)', L('USUARIO', 'l', -5, 'ANALISE_PUBLICADA', 'b', 60, (440, 1145)), seg=0, f=0.62)
rel('USUARIO', 'comenta', 'ANALISE_COMENTARIO', '(1,1)', '(0,N)', L('USUARIO', 'l', 30, 'ANALISE_COMENTARIO', 'r', 0, (1000, 1180), (1000, 1260)), seg=2, f=0.5)
rel('USUARIO', 'faz', 'PERGUNTA_IA', '(1,1)', '(0,N)', L('USUARIO', 'b', -300, 'PERGUNTA_IA', 'r', 0, (1160, 1400)), seg=1)
rel('MUNICIPIO', 'é cidade de', 'USUARIO', '(0,1)', '(0,N)', reta('MUNICIPIO', 'b', 'USUARIO', 't', 100, -380), f=0.78)
rel('MUNICIPIO', 'é atendido por', 'CADASTRO_PROFISSIONAL', '(0,1)', '(0,N)', L('MUNICIPIO', 'b', 150, 'CADASTRO_PROFISSIONAL', 'l', 0, (1130, 860)), seg=1)
rel('USUARIO', 'comprova', 'CADASTRO_PROFISSIONAL', '(1,1)', '(0,1)', reta('USUARIO', 't', 'CADASTRO_PROFISSIONAL', 'b'))
rel('PERFIL', 'define', 'USUARIO', '(1,1)', '(0,N)', reta('PERFIL', 't', 'USUARIO', 'b', 0, -160))
rel('USUARIO', 'possui', 'CREDENCIAL_ANALISTA', '(1,1)', '(0,1)', reta('USUARIO', 'r', 'CREDENCIAL_ANALISTA', 'l'))
rel('CREDENCIAL_ANALISTA', 'atua em', 'SERVICO_PUBLICO', '(0,N)', '(0,1)', L('CREDENCIAL_ANALISTA', 'r', 0, 'SERVICO_PUBLICO', 'r', 0, (3000, 1150), (3000, 120)), seg=1)
rel('USUARIO', 'é responsável', 'ACAO', '(1,1)', '(0,N)', L('USUARIO', 't', 140, 'ACAO', 'b', 40, (1600, 990), (2280, 990)), seg=1, f=0.6)
rel('USUARIO', 'registra', 'RESULTADO', '(1,1)', '(0,N)', L('USUARIO', 't', 220, 'RESULTADO', 'b', 0, (1680, 1030), (2680, 1030)), seg=1, f=0.55)
rel('USUARIO', 'propõe', 'META', '(1,1)', '(0,N)', L('USUARIO', 't', 300, 'META', 'b', 80, (1760, 1070), (2840, 1070)), seg=1, f=0.75)


# ------------------------------------------------------------------ conferência
def segs(r):
    p = r['rota']
    return [(p[i], p[i + 1]) for i in range(len(p) - 1)]


def dw(r): return max(DW, 7.2 * len(r['v']) + 34)


def diamante(r):
    s = segs(r)
    k = r['seg'] if r['seg'] is not None else max(range(len(s)), key=lambda i: abs(s[i][0][0]-s[i][1][0])+abs(s[i][0][1]-s[i][1][1]))
    (x1, y1), (x2, y2) = s[k]
    return x1 + (x2 - x1) * r['f'], y1 + (y2 - y1) * r['f'], k


def cruza(s, t):
    (a, b), (c, d) = s, t
    h1, h2 = a[1] == b[1], c[1] == d[1]
    if h1 == h2:
        if h1 and a[1] == c[1]:
            return max(min(a[0], b[0]), min(c[0], d[0])) < min(max(a[0], b[0]), max(c[0], d[0]))
        if not h1 and a[0] == c[0]:
            return max(min(a[1], b[1]), min(c[1], d[1])) < min(max(a[1], b[1]), max(c[1], d[1]))
        return False
    if not h1:
        (a, b), (c, d) = (c, d), (a, b)
    x, y = c[0], a[1]
    return min(a[0], b[0]) <= x <= max(a[0], b[0]) and min(c[1], d[1]) <= y <= max(c[1], d[1])


def dentro(pt_a, pt_b, e, folga=6):
    x0, y0, x1, y1 = box(e)
    x0 -= folga; y0 -= folga; x1 += folga; y1 += folga
    (ax, ay), (bx, by) = pt_a, pt_b
    if ay == by:
        return y0 < ay < y1 and max(min(ax, bx), x0) < min(max(ax, bx), x1)
    return x0 < ax < x1 and max(min(ay, by), y0) < min(max(ay, by), y1)


erros = []
for r in R:
    for s in segs(r):
        if s[0][0] != s[1][0] and s[0][1] != s[1][1]:
            erros.append(f"diagonal em {r['a']}-{r['b']}")
        for e in ENT:
            if e in (r['a'], r['b']):
                continue
            if dentro(*s, e):
                erros.append(f"{r['a']}-{r['b']} passa por {e}")
for r1, r2 in itertools.combinations(R, 2):
    for s in segs(r1):
        for t in segs(r2):
            if cruza(s, t):
                comum = set(s) & set(t)
                if not comum:
                    erros.append(f"cruza: {r1['a']}-{r1['b']}  x  {r2['a']}-{r2['b']}")
# losango não pode tocar caixa nem outra linha
for r in R:
    dx, dy, _ = diamante(r)
    for e in ENT:
        x0, y0, x1, y1 = box(e)
        if x0 - dw(r) / 2 < dx < x1 + dw(r) / 2 and y0 - DH / 2 < dy < y1 + DH / 2:
            erros.append(f"losango {r['v']} ({r['a']}) encosta em {e}")
    for r2 in R:
        if r2 is r:
            continue
        for (a, b) in segs(r2):
            if dentro(a, b, None, 0) if False else (
                    (a[1] == b[1] and abs(a[1] - dy) < DH / 2 + 4 and min(a[0], b[0]) < dx + dw(r) / 2 and max(a[0], b[0]) > dx - dw(r) / 2) or
                    (a[0] == b[0] and abs(a[0] - dx) < dw(r) / 2 + 4 and min(a[1], b[1]) < dy + DH / 2 and max(a[1], b[1]) > dy - DH / 2)):
                erros.append(f"losango {r['v']} ({r['a']}) encosta na linha {r2['a']}-{r2['b']}")
    for r2 in R:
        if r2 is r:
            continue
        ex, ey, _ = diamante(r2)
        if abs(ex - dx) < (dw(r) + dw(r2)) / 2 + 4 and abs(ey - dy) < DH + 4:
            erros.append(f"losangos {r['v']} e {r2['v']} sobrepostos")
print(len(ENT), 'entidades,', len(R), 'relacionamentos')
for e in sorted(set(erros)):
    print('  !', e)

# ------------------------------------------------------------------ SVG
def svg(simples=True, legenda=True):
    W = 3200; Hh = 1640
    f = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{Hh}" viewBox="-110 -20 {W} {Hh}" font-family="Arial, Helvetica, sans-serif">',
         '<style>.card{font-size:15px;font-weight:bold;fill:#B45309}.nome{font-size:14px;font-weight:bold}.id{font-size:13px;text-decoration:underline}.at{font-size:13px}.verbo{font-size:12px}</style>',
         f'<rect x="-110" y="-20" width="{W}" height="{Hh}" fill="white"/>']
    for r in R:
        f.append('<polyline fill="none" stroke="#334155" stroke-width="1.7" points="' +
                 ' '.join(f'{x:.0f},{y:.0f}' for x, y in r['rota']) + '"/>')
    for r in R:
        dx, dy, _ = diamante(r)
        nn = r['ca'].endswith('N)') and r['cb'].endswith('N)')
        f.append(f'<polygon points="{dx},{dy-DH/2} {dx+dw(r)/2},{dy} {dx},{dy+DH/2} {dx-dw(r)/2},{dy}" fill="{"#FDE68A" if nn else "white"}" stroke="#1E293B" stroke-width="1.3"/>')
        f.append(f'<text x="{dx}" y="{dy+4}" text-anchor="middle" class="verbo">{html.escape(r["v"])}</text>')
        for card, p, q in ((r['ca'], r['rota'][0], r['rota'][1]), (r['cb'], r['rota'][-1], r['rota'][-2])):
            ux, uy = (q[0] > p[0]) - (q[0] < p[0]), (q[1] > p[1]) - (q[1] < p[1])
            x, y = p[0] + ux * 26, p[1] + uy * 20
            if uy == 0:
                f.append(f'<text x="{x:.0f}" y="{y - 7:.0f}" text-anchor="middle" class="card">{card}</text>')
            else:
                f.append(f'<text x="{x + 6:.0f}" y="{y + 5:.0f}" class="card">{card}</text>')
    for e, (cx, cy, w, h, g, i) in ENT.items():
        x0, y0 = cx - w / 2, cy - h / 2
        f.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="{COR[g]}" stroke="#1E293B" stroke-width="1.8"/>')
        f.append(f'<text x="{cx}" y="{y0 + 19}" text-anchor="middle" class="nome">{e}</text>')
        f.append(f'<line x1="{x0}" y1="{y0 + 27}" x2="{x0 + w}" y2="{y0 + 27}" stroke="#1E293B" stroke-width="1"/>')
        for k, a in enumerate([i] + ATR[e]):
            f.append(f'<text x="{x0 + 10}" y="{y0 + 45 + 17 * k}" class="{"id" if k == 0 else "at"}">{a}</text>')
    f.append('</svg>')
    return '\n'.join(f)

(OUT / 'EcoCity_DER_completo_preview.svg').write_text(svg(), encoding='utf-8')
if erros and '--forcar' not in sys.argv:
    sys.exit(1)

# ------------------------------------------------------------------ figura final (documento / slide)
NOTA = ['Fora do DER conceitual (entram no modelo lógico do CP3):',
        'tabelas técnicas LOTE_CARGA, STG_MEDICAO_BRUTA, UNIDADE_MEDIDA, ACESSO_LOG,',
        'AUDITORIA e o Data Warehouse (dim_* e fato_*), além de vínculos secundários',
        '(quem revisa, aprova ou avalia).']
def figura(com_textos=True):
    s = svg()
    if not com_textos:
        return s
    extra = []
    # legenda (canto inferior direito)
    lx, ly = 2080, 1360
    extra.append(f'<rect x="{lx}" y="{ly}" width="900" height="150" rx="10" fill="white" stroke="#94A3B8"/>')
    linhas = [('Como ler', True), ('Retângulo = entidade (vira tabela), com seus atributos   ·   sublinhado = identificador   ·   Losango = relacionamento', False),
              ('(mín,máx) junto da entidade = quantas vezes ELA aparece para UMA do outro lado', False),
              ('Losango amarelo = relacionamento N:N (vira tabela associativa)', False)]
    for k, (txt, b) in enumerate(linhas):
        extra.append(f'<text x="{lx+18}" y="{ly+32+k*30}" font-size="{17 if b else 15}" {"font-weight=\"bold\"" if b else ""}>{html.escape(txt)}</text>')
    nx_, ny_ = 2080, 1530
    extra.append(f'<rect x="{nx_}" y="{ny_}" width="900" height="112" rx="10" fill="#F8FAFC" stroke="#CBD5E1" stroke-dasharray="6,4"/>')
    for k, txt in enumerate(NOTA):
        extra.append(f'<text x="{nx_+18}" y="{ny_+28+k*24}" font-size="{15 if k == 0 else 14}" {"font-weight=\"bold\"" if k == 0 else ""}>{html.escape(txt)}</text>')
    return s.replace('</svg>', '\n'.join(extra) + '\n</svg>')

(OUT / 'EcoCity_DER_completo.svg').write_text(figura().replace('height="1640" viewBox="-110 -20 3200 1640"', 'height="1700" viewBox="-110 -20 3200 1700"'), encoding='utf-8')
(OUT / 'EcoCity_DER_completo_simples.svg').write_text(svg().replace('viewBox="-110 -20 3200 1640"', 'viewBox="-70 45 3120 1510"').replace('width="3200" height="1640"', 'width="3120" height="1510"'), encoding='utf-8')

# ------------------------------------------------------------------ draw.io
cells, nid = [], [1]
def novo():
    nid[0] += 1; return f'c{nid[0]}'
esc = lambda s: html.escape(s, quote=True)
ids = {}
for e, (cx, cy, w, h, g, i) in ENT.items():
    k = novo(); ids[e] = k
    val = f'<div style="text-align:center"><b>{e}</b></div><hr size="1"><u>{i}</u><br>' + '<br>'.join(ATR[e])
    st = f'rounded=0;whiteSpace=wrap;html=1;fontSize=12;align=left;verticalAlign=top;spacingLeft=8;spacingTop=0;fillColor={COR[g]};strokeColor=#1E293B;strokeWidth=1.5;'
    cells.append(f'<mxCell id="{k}" value="{esc(val)}" style="{st}" vertex="1" parent="1"><mxGeometry x="{cx-w/2:.0f}" y="{cy-h/2:.0f}" width="{w}" height="{h}" as="geometry"/></mxCell>')

def frac(e, p):
    x0, y0, x1, y1 = box(e)
    return round((p[0] - x0) / (x1 - x0), 4), round((p[1] - y0) / (y1 - y0), 4)

def aresta(src, tgt, ex, en, pts, card, pos):
    k = novo()
    st = 'endArrow=none;html=1;rounded=0;strokeColor=#334155;strokeWidth=1.3;'
    if ex: st += f'exitX={ex[0]};exitY={ex[1]};exitDx=0;exitDy=0;'
    if en: st += f'entryX={en[0]};entryY={en[1]};entryDx=0;entryDy=0;'
    arr = ('<Array as="points">' + ''.join(f'<mxPoint x="{x:.0f}" y="{y:.0f}"/>' for x, y in pts) + '</Array>') if pts else ''
    cells.append(f'<mxCell id="{k}" style="{st}" edge="1" parent="1" source="{src}" target="{tgt}"><mxGeometry relative="1" as="geometry">{arr}</mxGeometry></mxCell>')
    j = novo()
    cells.append(f'<mxCell id="{j}" value="{card}" style="edgeLabel;html=1;align=center;verticalAlign=middle;resizable=0;points=[];fontStyle=1;fontSize=11;fontColor=#B45309;labelBackgroundColor=#FFFFFF;" vertex="1" connectable="0" parent="{k}"><mxGeometry x="{pos}" relative="1" as="geometry"><mxPoint as="offset"/></mxGeometry></mxCell>')

def lado_d(d, p):
    dx, dy = p[0] - d[0], p[1] - d[1]
    if abs(dx) > abs(dy): return (0, 0.5) if dx < 0 else (1, 0.5)
    return (0.5, 0) if dy < 0 else (0.5, 1)

for r in R:
    dx, dy, k = diamante(r)
    nn = r['ca'].endswith('N)') and r['cb'].endswith('N)')
    di = novo(); w = dw(r)
    cells.append(f'<mxCell id="{di}" value="{esc(r["v"])}" style="rhombus;whiteSpace=wrap;html=1;fontSize=10;fillColor={"#FDE68A" if nn else "#FFFFFF"};strokeColor=#1E293B;" vertex="1" parent="1"><mxGeometry x="{dx-w/2:.0f}" y="{dy-DH/2:.0f}" width="{w:.0f}" height="{DH}" as="geometry"/></mxCell>')
    p = r['rota']
    antes, depois = p[1:k + 1], p[k + 1:-1]
    aresta(ids[r['a']], di, frac(r['a'], p[0]), lado_d((dx, dy), antes[-1] if antes else p[0]), antes, r['ca'], -0.6)
    aresta(di, ids[r['b']], lado_d((dx, dy), depois[0] if depois else p[-1]), frac(r['b'], p[-1]), depois, r['cb'], 0.6)

def caixa_txt(x, y, w, h, val, st):
    k = novo()
    cells.append(f'<mxCell id="{k}" value="{esc(val)}" style="{st}" vertex="1" parent="1"><mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
caixa_txt(-40, -130, 1600, 70, '<b style="font-size:24px">EcoCity — DER (modelo conceitual)</b><br><span style="font-size:14px">A3 Banco de Dados · Checkpoint 2 · notação de Chen com cardinalidade (mín,máx)</span>',
          'text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;')
caixa_txt(2080, 1360, 900, 150, '<b>Como ler</b><br>Retângulo = entidade (vira tabela), com seus atributos · <u>sublinhado</u> = identificador · Losango = relacionamento<br>'
          '<b style="color:#B45309">(mín,máx)</b> junto da entidade = quantas vezes ELA aparece para UMA do outro lado<br>'
          '<span style="background:#FDE68A">&nbsp;Losango amarelo&nbsp;</span> = relacionamento N:N (vira tabela associativa)',
          'text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;fontSize=13;fillColor=#FFFFFF;strokeColor=#94A3B8;spacing=12;rounded=1;arcSize=6;')
caixa_txt(2080, 1530, 900, 112, '<b>' + NOTA[0] + '</b><br>' + ' '.join(NOTA[1:]),
          'text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;fontSize=12;fillColor=#F8FAFC;strokeColor=#CBD5E1;dashed=1;spacing=12;rounded=1;arcSize=6;')
xml = ('<mxfile host="app.diagrams.net"><diagram id="der" name="DER EcoCity">'
       '<mxGraphModel dx="1600" dy="1000" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" '
       'page="1" pageScale="1" pageWidth="3300" pageHeight="1900" math="0" shadow="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/>'
       + ''.join(cells) + '</root></mxGraphModel></diagram></mxfile>')
(OUT / 'EcoCity_DER_completo.drawio').write_text(xml, encoding='utf-8')
raw = urllib.parse.quote(xml, safe="~()*!.'-_")
comp = zlib.compressobj(9, zlib.DEFLATED, -15)
dados = comp.compress(raw.encode()) + comp.flush()
link = 'https://app.diagrams.net/#R' + urllib.parse.quote(base64.b64encode(dados).decode(), safe='')
(OUT / 'link_drawio.txt').write_text(link)
print('link', len(link))
