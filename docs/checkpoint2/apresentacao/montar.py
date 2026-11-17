"""Preenche o modelo da professora (ModeloCP2-bancodedados.pptx) com o conteúdo do EcoCity."""
import copy
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from pptx.oxml.ns import qn

DIR = '/tmp/claude-0/-home-claude/1c6b68db-97a3-5a09-8184-4096558091c3/scratchpad/cp2ppt/'
PR = '/home/claude/ecocity/docs/checkpoint2/prints/'
LI = '/home/claude/ecocity/docs/linkedin/'

ESC = RGBColor(0x26, 0x26, 0x26)      # texto escuro (mesmo tom do modelo)
CINZA = RGBColor(0x59, 0x59, 0x59)
VERDE = RGBColor(0x1D, 0x5F, 0xA8)    # destaque (azul da logo)
FUNDO = RGBColor(0xEE, 0xF4, 0xFB)    # cartões (azul bem claro)
OURO = RGBColor(0x80, 0x60, 0x00)     # cabeçalho da tabela do modelo
OURO2 = RGBColor(0xBF, 0x8F, 0x00)

prs = Presentation(DIR + 'modelo2.pptx')   # modelo + 1 slide de status a mais
S = prs.slides


def shape(slide, name):
    return next(s for s in slide.shapes if s.name == name)


def remove(sh):
    sh._element.getparent().remove(sh._element)


def titulo(slide, texto):
    """Caixa 'Título do Slide: X' do modelo -> só X (mantém fonte e posição)."""
    tf = shape(slide, 'CaixaDeTexto 14').text_frame
    runs = tf.paragraphs[0].runs
    runs[0].text = texto
    for r in runs[1:]:
        r.text = ''
    runs[0].font.bold = True


def caixa(slide, x, y, w, h, fill=None, radius=True, name=None):
    sp = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE if radius else MSO_SHAPE.RECTANGLE,
                                Inches(x), Inches(y), Inches(w), Inches(h))
    if radius:
        sp.adjustments[0] = 0.08
    if fill:
        sp.fill.solid(); sp.fill.fore_color.rgb = fill
    else:
        sp.fill.background()
    sp.line.fill.background()
    sp.shadow.inherit = False
    if name:
        sp.name = name
    sp.text_frame.text = ''
    return sp


def texto(slide, x, y, w, h, linhas, size=14, name=None, anchor=MSO_ANCHOR.TOP, margin=0.08):
    """linhas: lista de (texto, {bold, color, size, bullet, after})."""
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    if name:
        tb.name = name
    tf = tb.text_frame; tf.word_wrap = True; tf.vertical_anchor = anchor
    for side in ('left', 'right', 'top', 'bottom'):
        setattr(tf, f'margin_{side}', Inches(margin))
    for i, (t, o) in enumerate(linhas):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.space_after = Pt(o.get('after', 4))
        if o.get('align'):
            p.alignment = o['align']
        if o.get('bullet'):
            pPr = p._p.get_or_add_pPr()
            pPr.set('marL', str(Emu(Inches(0.22)))); pPr.set('indent', str(-Emu(Inches(0.2))))
            bu = pPr.makeelement(qn('a:buChar'), {'char': '•'}); pPr.append(bu)
        partes = t if isinstance(t, list) else [(t, o.get('bold', False))]
        for txt, b in partes:
            r = p.add_run(); r.text = txt
            r.font.size = Pt(o.get('size', size)); r.font.bold = b
            r.font.color.rgb = o.get('color', ESC)
    return tb


def foto(slide, path, x, y, w=None, h=None, name=None):
    pic = slide.shapes.add_picture(path, Inches(x), Inches(y), Inches(w) if w else None, Inches(h) if h else None)
    if name:
        pic.name = name
    return pic


def notas(slide, t):
    slide.notes_slide.notes_text_frame.text = t


# ============================== SLIDE 2: capa do checkpoint
s2 = S[1]
tf = shape(s2, 'CaixaDeTexto 9').text_frame
ps = tf.paragraphs
ps[1].runs[0].text = 'EcoCity'
ps[2].runs and None
r = ps[2].add_run(); r.text = 'Banco de dados para cidades inteligentes e sustentáveis'
r.font.size = Pt(16); r.font.color.rgb = CINZA
tf2 = shape(s2, 'CaixaDeTexto 4').text_frame
nomes = ['Gabriela Sant’Ana Merces Assis', 'Nicole Maranhão Assis']
p_al = tf2.paragraphs
for i, n in enumerate(nomes, start=1):
    p_al[i].runs[0].text = n
    for rr in p_al[i].runs[1:]:
        rr.text = ''
    for rr in p_al[i].runs:
        rr.font.size = Pt(18)
p_al[3]._p.getparent().remove(p_al[3]._p)
ras = texto(s2, 7.87, 4.05, 4.2, 0.5, [('RA 12525218204 · RA 12525141079', {'size': 12, 'color': CINZA})], name='RAs')
notas(s2, 'GABRIELA (15 s): Bom dia! Nós somos a Gabriela e a Nicole e vamos apresentar o checkpoint 2 do nosso projeto, o EcoCity: '
          'um banco de dados para cidades inteligentes e sustentáveis.')

NOTA3 = ('NICOLE (1 min): Essa é a nossa logo: a folha é a natureza e o lixo, a gota é a água, o sol é a energia e os prédios são a cidade. Os desenhos se ligam, como o nosso banco liga os dados. O EcoCity nasceu de um problema: os dados de água, energia, lixo e transporte das cidades ficam espalhados, '
          'cada um num site e num formato. Sem eles juntos, o gestor decide com informação pela metade e o cidadão não entende como está a cidade. '
          'A nossa solução é um banco de dados que junta tudo, mês a mês, para 8 cidades de São Paulo, e calcula uma nota de 0 a 100 para cada cidade. '
          'Dos requisitos, os três mais importantes são: juntar os dados mostrando de onde veio cada número, calcular os indicadores todo mês '
          'e garantir um acesso seguro, com cadastro diferente para cada tipo de pessoa.')
NOTA4 = ('GABRIELA (1 min): Este é o nosso DER completo, feito no draw.io. Cada retângulo é uma tabela e cada losango é uma ligação entre elas. '
          'O município é o centro: ele recebe os dados de cada mês, os indicadores, as ações e as análises. Embaixo fica o usuário, ligado a tudo o que ele faz: metas, ações, análises e relatórios. '
          'Os números entre parênteses mostram o mínimo e o máximo: por exemplo, cada fonte de dados vem de 1 órgão, e um órgão pode ter várias fontes. '
          'O banco escolhido é o MySQL, que vai ficar na Oracle Cloud. Para o sistema usamos Node.js com Express no back-end, HTML, CSS e JavaScript nas telas, e Python na parte de IA.')
NOTA5 = ('NICOLE (1 min): Aqui está o que já fizemos. Criamos o banco no MySQL, com todas as tabelas. Este segundo print mostra uma regra do banco funcionando: '
          'tentamos criar um administrador direto na tabela e o próprio banco bloqueou. E aqui a nossa API, que liga o banco às telas, já está no ar. '
          'Tivemos dois impedimentos: algumas fontes só publicam dados por ano, então marcamos o que é estimado; '
          'Para a próxima entrega vamos fazer o DER final, o modelo lógico, a normalização e as telas. Ao lado está o nosso post no LinkedIn.')
NOTA5A = ('NICOLE (30 s): Aqui está o que já está pronto. À esquerda, o nosso banco no MySQL, com as tabelas. À direita, a lista: o banco foi criado, os dados reais das 8 cidades já estão guardados, as regras de segurança funcionam e o back-end, que é a ponte entre as telas e o banco, está pronto.')
NOTA5S = ('NICOLE (25 s): Aqui um teste de segurança. Tentamos criar um administrador direto na tabela, sem a chave de administrador. O próprio banco recusou e mostrou o erro: administrador só pode ser criado pelo DBA, com chave individual. Assim ninguém vira administrador escondido.')
NOTA5A_OLD = ('NICOLE (40 s): Aqui está o que já está pronto. À esquerda, o banco criado no MySQL com as tabelas. Em cima, a nossa API, que liga o banco às telas, já está no ar. Embaixo, uma regra de segurança: tentamos criar um administrador intruso direto no banco e o próprio banco bloqueou.')
NOTA5B = ('NICOLE (30 s): Tivemos um impedimento: algumas fontes só publicam dados por ano, e nós queríamos mês a mês. Por isso, marcamos no banco o que é dado oficial e o que é estimado. Na próxima entrega vamos fazer o modelo lógico, a normalização e as telas. Aqui ao lado está o nosso post no LinkedIn.')
NOTA6 = ('GABRIELA (40 s): Este é o cronograma desta entrega. Tudo está concluído, por isso todas as bolinhas estão verdes. Dividimos as tarefas entre nós duas: eu fiquei com os requisitos, as tecnologias e a criação do banco, e a Nicole com a coleta dos dados reais, o DER e o back-end. A entrega do checkpoint e o post no LinkedIn fizemos juntas.')

# ============================== layout comum
MX, TOPO, BASE = 0.6, 1.2, 6.25          # margem lateral, topo e base da área útil (o rodapé do modelo fica em 6.86")
LARG = 13.333 - 2 * MX
BRANCO = RGBColor(255, 255, 255)


def rotulo(slide, x, y, w, t, name):
    texto(slide, x, y, w, 0.4, [(t, {'bold': True, 'size': 16, 'color': VERDE, 'after': 0})], name=name, margin=0)


def cartao(slide, x, y, w, h, titulo_txt, linhas, name, size=13, hsize=15, anchor=MSO_ANCHOR.TOP, gap=4):
    caixa(slide, x, y, w, h, FUNDO, name=name)
    corpo = [(titulo_txt, {'bold': True, 'size': hsize, 'color': VERDE, 'after': gap + 4})] + \
            [(l, {'bullet': True, 'size': size, 'after': gap}) for l in linhas]
    texto(slide, x + 0.25, y + 0.15, w - 0.5, h - 0.3, corpo, name=name + ' texto', margin=0, anchor=anchor)


def imagem_centrada(slide, path, x, y, w, h, name):
    from PIL import Image
    iw, ih = Image.open(path).size
    esc = min(w / iw, h / ih)
    fw, fh = iw * esc, ih * esc
    return foto(slide, path, x + (w - fw) / 2, y + (h - fh) / 2, w=fw, name=name)


# ============================== SLIDE 3: nome do projeto
s3 = S[2]
titulo(s3, 'EcoCity')
remove(shape(s3, 'CaixaDeTexto 10'))
caixa(s3, MX, TOPO, 3.4, BASE - TOPO, FUNDO, name='Painel logo')
imagem_centrada(s3, DIR + 'logos4/ecocity_logo.png', MX + 0.4, TOPO + 0.35, 2.6, 3.15, 'Logo EcoCity')
texto(s3, MX + 0.25, 4.85, 2.9, 1.2, [('Água, energia, lixo e transporte de 8 cidades de SP, mês a mês, num só banco.',
                                        {'size': 13, 'align': PP_ALIGN.CENTER, 'color': CINZA})], name='Frase', margin=0)
X2 = MX + 3.4 + 0.35; W2 = 13.333 - MX - X2
meia = (W2 - 0.3) / 2
cartao(s3, X2, TOPO, meia, 1.95, 'Problema', ['Os dados da cidade estão espalhados em sites e formatos diferentes.',
                                             'O gestor decide com informação incompleta.'], 'Card problema', 14)
cartao(s3, X2 + meia + 0.3, TOPO, meia, 1.95, 'Solução', ['Um banco de dados que junta tudo, mês a mês, e dá uma nota de 0 a 100 para cada cidade.'], 'Card solução', 14)
rotulo(s3, X2, 3.35, W2, 'Requisitos prioritários (Must Have)', 'H requisitos')
REQ = [('1', 'Juntar os dados', '4 serviços, 8 cidades, com a origem de cada número'),
       ('2', 'Calcular indicadores', 'Índice EcoCity de 0 a 100, todo mês'),
       ('3', 'Acesso seguro', 'Cadastro por perfil e login em 2 etapas')]
cw = (W2 - 0.6) / 3
for k, (n, h, d) in enumerate(REQ):
    x = X2 + k * (cw + 0.3)
    caixa(s3, x, 3.8, cw, BASE - 3.8, FUNDO, name=f'Card req {n}')
    c = s3.shapes.add_shape(MSO_SHAPE.OVAL, Inches(x + 0.25), Inches(4.0), Inches(0.55), Inches(0.55))
    c.fill.solid(); c.fill.fore_color.rgb = VERDE; c.line.fill.background(); c.shadow.inherit = False; c.name = f'Num req {n}'
    c.text_frame.text = n
    rr = c.text_frame.paragraphs[0].runs[0]; rr.font.size = Pt(18); rr.font.bold = True; rr.font.color.rgb = BRANCO
    c.text_frame.paragraphs[0].alignment = PP_ALIGN.CENTER
    texto(s3, x + 0.25, 4.7, cw - 0.5, 1.45, [(h, {'bold': True, 'size': 16, 'after': 8}), (d, {'size': 14, 'color': CINZA})], name=f'Req {n} texto', margin=0)
notas(s3, NOTA3)

# ============================== SLIDE 4: modelagem e SGBD
s4 = S[3]
titulo(s4, 'Modelagem de Dados e SGBD')
remove(shape(s4, 'CaixaDeTexto 10')); remove(shape(s4, 'CaixaDeTexto 4'))
WD = 8.85
caixa(s4, MX, TOPO, WD, BASE - TOPO, RGBColor(0xFA, 0xFB, 0xFA), name='Moldura DER')
imagem_centrada(s4, DIR + 'der_simples.png', MX + 0.15, TOPO + 0.15, WD - 0.3, BASE - TOPO - 0.3, 'DER preliminar')
XT = MX + WD + 0.3; WT = 13.333 - MX - XT
caixa(s4, XT, TOPO, WT, BASE - TOPO, FUNDO, name='Painel tecnologias')
TEC = [('Banco de dados', 'MySQL 8 · Oracle Cloud'), ('Modelagem', 'draw.io · Workbench'),
       ('Back-end', 'Node.js + Express'), ('Front-end', 'HTML, CSS e JS'), ('IA', 'Python')]
for k, (h, d) in enumerate(TEC):
    y = TOPO + 0.25 + k * 0.98
    texto(s4, XT + 0.25, y, WT - 0.5, 0.35, [(h, {'bold': True, 'size': 13, 'color': VERDE, 'after': 0})], name=f'Tec {k} título', margin=0)
    texto(s4, XT + 0.25, y + 0.33, WT - 0.5, 0.4, [(d, {'size': 14, 'after': 0})], name=f'Tec {k} valor', margin=0)
notas(s4, NOTA4)

# ============================== SLIDE 5: status (1/2) — o que já está pronto (simples)
s5 = S[4]
titulo(s5, 'Status do Projeto (CP 2)')
remove(shape(s5, 'CaixaDeTexto 10'))
rotulo(s5, MX, TOPO - 0.05, 6, 'O que já está pronto', 'H pronto')
Y = TOPO + 0.45
WTB = 3.6
caixa(s5, MX, Y, WTB, BASE - Y, FUNDO, name='Card tabelas')
imagem_centrada(s5, DIR + 'print3_lista.png', MX + 0.2, Y + 0.2, WTB - 0.4, BASE - Y - 0.85, 'Print tabelas')
texto(s5, MX + 0.15, BASE - 0.55, WTB - 0.3, 0.4, [('Nosso banco no MySQL', {'bold': True, 'size': 15, 'align': PP_ALIGN.CENTER, 'after': 0})], name='Leg tabelas', margin=0)
XR = MX + WTB + 0.3; WR = 13.333 - MX - XR
PRONTO = [('Banco de dados criado', 'no MySQL, com 36 tabelas'),
          ('Dados reais guardados', '8 cidades de SP, mês a mês'),
          ('Regras de segurança', 'cada perfil só faz o que pode'),
          ('Back-end pronto', 'a ponte entre as telas e o banco')]
HL = (BASE - Y - 0.25 * (len(PRONTO) - 1)) / len(PRONTO)
for k, (h, d) in enumerate(PRONTO):
    y = Y + k * (HL + 0.25)
    feito = True
    caixa(s5, XR, y, WR, HL, FUNDO, name=f'Pronto {k}')
    c = s5.shapes.add_shape(MSO_SHAPE.OVAL, Inches(XR + 0.3), Inches(y + (HL - 0.5) / 2), Inches(0.5), Inches(0.5))
    c.fill.solid(); c.fill.fore_color.rgb = RGBColor(0x2F, 0x8F, 0x3F) if feito else RGBColor(0xE8, 0x89, 0x2B)
    c.line.fill.background(); c.shadow.inherit = False; c.name = f'Marca {k}'
    c.text_frame.text = '✓' if feito else '…'
    rr = c.text_frame.paragraphs[0].runs[0]; rr.font.size = Pt(18); rr.font.bold = True; rr.font.color.rgb = BRANCO
    c.text_frame.paragraphs[0].alignment = PP_ALIGN.CENTER
    texto(s5, XR + 1.05, y, WR - 1.3, HL, [([(h, True), ('  ·  ' + d, False)], {'size': 18, 'after': 0})],
          name=f'Pronto {k} texto', anchor=MSO_ANCHOR.MIDDLE, margin=0)
notas(s5, NOTA5A)

# ============================== SLIDE 6: status (2/2) — impedimentos, próximos passos e LinkedIn
s5b = S[5]
titulo(s5b, 'Status do Projeto (CP 2)')
remove(shape(s5b, 'CaixaDeTexto 10'))
WL = (LARG - 0.3) / 2
hcard = (BASE - TOPO - 0.3) / 2
cartao(s5b, MX, TOPO, WL, hcard, 'Impedimentos', ['Algumas fontes só publicam dados por ano: marcamos o que é estimado.'], 'Card impedimentos', 19, 20, MSO_ANCHOR.MIDDLE, 10)
cartao(s5b, MX, TOPO + hcard + 0.3, WL, hcard, 'Próxima entrega', ['Modelo lógico (tabelas, colunas e chaves)', 'Normalização até a 3ª forma normal',
                                                                    'Telas do sistema'], 'Card próximos', 19, 20, MSO_ANCHOR.MIDDLE, 10)
XL = MX + WL + 0.3
caixa(s5b, XL, TOPO, WL, BASE - TOPO, FUNDO, name='Área LinkedIn (colar print e QR code)')
texto(s5b, XL + 0.2, TOPO + 0.15, WL - 0.4, 0.4, [('Post no LinkedIn', {'bold': True, 'size': 20, 'color': VERDE, 'after': 0})], name='H LinkedIn', margin=0)
notas(s5b, NOTA5B)

# ============================== SLIDE 6: cronograma
s6 = S[6]
titulo(s6, 'Cronograma e Divisão de Tarefas')
remove(shape(s6, 'Imagem 11'))
import sys
sys.path.insert(0, '/home/claude/ecocity/docs')
import conteudo as C
CURTO = [  # versão curta das atividades para caber bem no slide (o documento tem a versão completa)
    ('Tema, diagnóstico e entidades (CP1)', '01/09', 'Gabriela e Nicole', '—', ''),
    ('Requisitos priorizados', '10/10', 'Gabriela', 'Checkpoint 1', ''),
    ('Coleta dos dados reais mensais', '15/10', 'Nicole', 'Requisitos', 'Fontes só com dados anuais'),
    ('Definição do MySQL e tecnologias', '10/10', 'Gabriela', 'Requisitos', ''),
    ('DER completo', '16/10', 'Nicole', 'Requisitos', ''),
    ('Criação do banco no MySQL', '16/10', 'Gabriela', 'DER', ''),
    ('Back-end (API)', '16/10', 'Nicole', 'Banco criado', ''),
    ('Entrega do CP2 + LinkedIn', '20/10', 'Gabriela e Nicole', 'Atividades 2 a 7', ''),
]
cols = ['Atividade', 'Entrega', 'Responsável', 'Depende de', 'Impedimentos', 'Status']
larg = [3.75, 1.0, 2.05, 1.85, 2.6, 0.88]
n = len(CURTO)
tb = s6.shapes.add_table(n + 2, len(cols), Inches(MX), Inches(TOPO), Inches(sum(larg)), Inches(0.4 * (n + 2))).table
for j, w in enumerate(larg):
    tb.columns[j].width = Inches(w)


def cel(c, t, size=12, bold=False, color=ESC, fill=None, align=None):
    c.text = ''
    p = c.text_frame.paragraphs[0]
    r = p.add_run(); r.text = t; r.font.size = Pt(size); r.font.bold = bold; r.font.color.rgb = color
    if align:
        p.alignment = align
    c.margin_left = c.margin_right = Inches(0.1); c.margin_top = c.margin_bottom = Inches(0.04)
    c.vertical_anchor = MSO_ANCHOR.MIDDLE
    if fill is not None:
        c.fill.solid(); c.fill.fore_color.rgb = fill


topo = tb.cell(0, 0); topo.merge(tb.cell(0, len(cols) - 1))
cel(topo, 'CHECKPOINT 2: data da entrega 20/10/2026', 13, True, BRANCO, OURO, PP_ALIGN.CENTER)
for j, h in enumerate(cols):
    cel(tb.cell(1, j), h, 12, True, BRANCO, OURO2, PP_ALIGN.CENTER if j in (1, 5) else None)
COR = {k: RGBColor.from_string(v[1]) for k, v in C.STATUS.items()}
for i, (row, st) in enumerate(zip(CURTO, ['C'] * len(CURTO)), start=2):
    bg = BRANCO if i % 2 else RGBColor(0xF7, 0xF4, 0xEA)
    for j, v in enumerate(row):
        cel(tb.cell(i, j), v, 13, False, CINZA if j == 4 else ESC, bg, PP_ALIGN.CENTER if j == 1 else None)
    cel(tb.cell(i, 5), '●', 16, False, COR[st], bg, PP_ALIGN.CENTER)
for r_ in tb.rows:
    r_.height = Inches(0.45)
leg = texto(s6, MX, 5.95, LARG, 0.35, [([('Status:  ', True)] + sum([[('● ', False), (nome + '      ', False)] for nome, _ in C.STATUS.values()], []), {'size': 12})], name='Legenda status', margin=0)
runs = leg.text_frame.paragraphs[0].runs
for k, (_, cor) in enumerate(C.STATUS.values()):
    runs[1 + 2 * k].font.color.rgb = RGBColor.from_string(cor)
notas(s6, NOTA6)

# ============================== SLIDE 7: obrigada
s7 = S[7]
tf = shape(s7, 'CaixaDeTexto 7').text_frame
ps = tf.paragraphs
for i, nm in enumerate(nomes):
    ps[i].runs[0].text = nm
    for rr in ps[i].runs[1:]:
        rr.text = ''
for p in ps[2:]:
    p._p.getparent().remove(p._p)
cx = shape(s7, 'CaixaDeTexto 7')
cx.left = Inches(8.3); cx.width = Inches(4.6)
notas(s7, 'NICOLE (10 s): Obrigada! Ficamos à disposição para perguntas.')
notas(S[0], 'GABRIELA (5 s): Projeto da A3 de Banco de Dados, com a professora Cássia Assis.')

prs.save(DIR + 'CP2_EcoCity_Gabriela_Nicole.pptx')
print('ok')
