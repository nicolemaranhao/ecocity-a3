"""Preenche o template oficial do 2º Checkpoint mantendo o layout original."""
import copy
import sys
from pathlib import Path

import docx
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

BASE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BASE / "docs"))
import conteudo as C  # noqa: E402

TEMPLATE, SAIDA = sys.argv[1], sys.argv[2]
EVID, DIAG = BASE / "docs/evidencias", BASE / "docs/diagramas"
d = docx.Document(TEMPLATE)
P = d.paragraphs
T_MEMBROS, T_CAB_CRONO, T_CRONO = d.tables[1], d.tables[2], d.tables[3]

OURO, OURO2 = "806000", "BF8F00"
SVC = {"AGU": "0284C7", "ENE": "D97706", "RES": "16A34A", "MOB": "9333EA"}
PRIO = {"Alta": ("FDE2E4", "B91C1C"), "Média": ("FEF3C7", "92400E"), "Baixa": ("DCFCE7", "166534")}


# ----------------------------------------------------------------- utilitários
def shade(cell, fill):
    tcPr = cell._tc.get_or_add_tcPr()
    for old in tcPr.findall(qn("w:shd")):
        tcPr.remove(old)
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear"); shd.set(qn("w:color"), "auto"); shd.set(qn("w:fill"), fill)
    tcPr.append(shd)


def margins(cell, top=50, bottom=50, left=80, right=80):
    tcPr = cell._tc.get_or_add_tcPr()
    m = OxmlElement("w:tcMar")
    for k, v in (("top", top), ("bottom", bottom), ("start", left), ("end", right)):
        e = OxmlElement(f"w:{k}"); e.set(qn("w:w"), str(v)); e.set(qn("w:type"), "dxa"); m.append(e)
    tcPr.append(m)


def borders(table, color="BFBFBF"):
    tblPr = table._tbl.tblPr
    b = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        e = OxmlElement(f"w:{edge}")
        e.set(qn("w:val"), "single"); e.set(qn("w:sz"), "4"); e.set(qn("w:space"), "0"); e.set(qn("w:color"), color)
        b.append(e)
    tblPr.append(b)


def write(cell, text, bold=False, size=9, color=None, align=None, font=None):
    cell.text = ""
    p = cell.paragraphs[0]
    p.paragraph_format.space_after = Pt(0); p.paragraph_format.space_before = Pt(0)
    if align: p.alignment = align
    r = p.add_run(text); r.bold = bold; r.font.size = Pt(size)
    if color: r.font.color.rgb = RGBColor.from_string(color)
    if font: r.font.name = font
    return r


class Cursor:
    """Insere blocos em sequência logo após um parágrafo âncora."""
    def __init__(self, anchor):
        self.last = anchor._p

    def _place(self, el):
        self.last.addnext(el); self.last = el

    def para(self, text="", bold=False, size=10.5, italic=False, color=None, indent=0.63, align=None, after=6, runs=None):
        p = d.add_paragraph()
        p.paragraph_format.left_indent = Cm(indent); p.paragraph_format.space_after = Pt(after)
        p.paragraph_format.line_spacing = 1.15
        if align: p.alignment = align
        for t, b in (runs or [(text, bold)]):
            r = p.add_run(t); r.bold = b; r.italic = italic; r.font.size = Pt(size)
            if color: r.font.color.rgb = RGBColor.from_string(color)
        self._place(p._p); return p

    def bullet(self, text, lead=None):
        return self.para(runs=([(lead, True)] if lead else []) + [(text, False)], indent=1.0, size=10, after=3) if lead \
            else self.para("• " + text, indent=1.0, size=10, after=3)

    def image(self, path, width_cm, caption=None):
        p = d.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(2)
        p.add_run().add_picture(str(path), width=Cm(width_cm))
        self._place(p._p)
        if caption:
            self.para(caption, italic=True, size=8.5, color="595959", align=WD_ALIGN_PARAGRAPH.CENTER, indent=0, after=10)

    def table(self, header, rows, widths, header_fill=OURO, size=8.5, fmt=None):
        t = d.add_table(rows=1 + len(rows), cols=len(header))
        t.alignment = WD_TABLE_ALIGNMENT.CENTER; t.autofit = False
        borders(t)
        for i, h in enumerate(header):
            c = t.rows[0].cells[i]; shade(c, header_fill); margins(c)
            write(c, h, bold=True, size=size, color="FFFFFF")
        for ri, row in enumerate(rows, start=1):
            for ci, val in enumerate(row):
                c = t.rows[ri].cells[ci]; margins(c)
                if ri % 2 == 0: shade(c, "F7F4EA")
                write(c, val, size=size)
                if fmt: fmt(c, ri - 1, ci, val)
        for row in t.rows:
            for i, w in enumerate(widths):
                row.cells[i].width = Cm(w)
        tblPr = t._tbl.tblPr
        lay = OxmlElement("w:tblLayout"); lay.set(qn("w:type"), "fixed"); tblPr.append(lay)
        tw = tblPr.find(qn("w:tblW"))
        if tw is None:
            tw = OxmlElement("w:tblW"); tblPr.append(tw)
        tw.set(qn("w:w"), str(int(sum(widths) * 567))); tw.set(qn("w:type"), "dxa")
        for gc, w in zip(t._tbl.tblGrid.findall(qn("w:gridCol")), widths):
            gc.set(qn("w:w"), str(int(w * 567)))
        # repete cabeçalho em quebra de página
        trPr = t.rows[0]._tr.get_or_add_trPr(); h = OxmlElement("w:tblHeader"); h.set(qn("w:val"), "true"); trPr.append(h)
        self._place(t._tbl)
        self.para("", after=4, size=4)
        return t


# ----------------------------------------------------------------- cabeçalho e identificação
for r in P[0].runs:
    r.text = r.text.replace("__/__/____", C.DATA_CP2)
txt = "".join(r.text for r in P[0].runs)
if C.DATA_CP2 not in txt:  # data estava fragmentada em vários runs
    for r in P[0].runs[1:]:
        r.text = ""
    P[0].runs[0].text = "\nData da entrega: " + C.DATA_CP2 + "\n"

tm = T_MEMBROS
for i, (nome, ra) in enumerate(C.INTEGRANTES, start=1):
    write(tm.rows[i].cells[0], f"{i}. {nome}", size=11)
    write(tm.rows[i].cells[1], ra, size=11)
tm._tbl.remove(tm.rows[3]._tr)  # dupla: remove a 3ª linha

# 2. Título
cur = Cursor(P[4])
cur.para(C.PROJETO, bold=True, size=12, color=OURO, after=2)
cur.para(C.TEMA + ". Problema: falta de integração de dados entre serviços públicos (água, energia, transporte e resíduos) "
         "e decisões baseadas em dados incompletos. Solução: Data Warehouse com dados integrados de múltiplos serviços públicos, "
         "dashboards para gestores e indicadores de sustentabilidade urbana.", size=10, after=8)

# 3. Requisitos priorizados
cur = Cursor(P[6])
cur.para("Prioridade: Alta = essencial para o sistema funcionar; Média = agrega valor; Baixa = complementar.", size=10)
cur.para("3.1 Requisitos funcionais", bold=True, size=10.5, after=4)


def fmt_prio(c, ri, ci, val):
    if ci == 3:
        bg, fg = PRIO[val]; shade(c, bg); write(c, val, bold=True, size=8.5, color=fg, align=WD_ALIGN_PARAGRAPH.CENTER)
    if ci == 0:
        write(c, val, bold=True, size=8.5, color=OURO)


cur.table(["ID", "Requisito", "Uso do banco de dados", "Prioridade"],
          [(a, b, c, p) for a, b, c, p, _ in C.RF], [1.2, 6.6, 5.6, 1.6], fmt=fmt_prio)
cur.para("3.2 Requisitos não funcionais", bold=True, size=10.5, after=4)
cur.table(["ID", "Requisito", "Onde é atendido", "Prioridade"], C.RNF, [1.4, 7.6, 4.4, 1.6], fmt=fmt_prio)
cur.para(C.NOTA_REQUISITOS, size=10)

# 4. DER preliminar
PR = Path(__file__).resolve().parent / "prints"


def secao(orient):
    """Quebra de seção: tudo ANTES deste parágrafo usa a orientação atual do documento; 'orient' vale para o bloco seguinte."""
    # o template tem 2 seções: a 1ª em retrato (texto) e a última em paisagem (cronograma)
    sp = copy.deepcopy(d.sections[0]._sectPr if orient == "retrato" else d.sections[-1]._sectPr)
    for t in sp.findall(qn("w:type")):
        sp.remove(t)
    tp = OxmlElement("w:type"); tp.set(qn("w:val"), "nextPage"); sp.insert(0, tp)
    p = d.add_paragraph(); p.paragraph_format.space_after = Pt(0)
    p._p.get_or_add_pPr().append(sp)
    return p


cur = Cursor(P[8])
cur.para("Modelo conceitual completo feito no draw.io (notação de Chen): 22 entidades com seus atributos principais e 37 relacionamentos, sem linhas cruzando. "
         "O par (mín,máx) junto de cada entidade indica com quantas ocorrências ela participa do relacionamento. "
         "Ex.: cada fonte é publicada por 1 órgão; cada órgão publica de 0 a N fontes. "
         "As tabelas técnicas (carga de dados, unidades, log de acesso, auditoria e Data Warehouse) entram no modelo lógico (Checkpoint 3).", size=10, after=4)
cur._place(secao("retrato")._p)                       # fecha a seção em retrato
cur.image(PR / "print1_der.png", 24.0, "Figura 1 — DER do EcoCity (modelo conceitual completo, notação de Chen com cardinalidade mín/máx), feito no draw.io.")
cur._place(secao("paisagem")._p)                      # fecha a página em paisagem

# 5. SGBD e tecnologias
cur = Cursor(P[10])
cur.para(runs=[("SGBD escolhido: MySQL 8.0, ", True), ("publicado na Oracle Cloud (MySQL HeatWave), conforme exigido na A3.", False)], size=10)


def fmt_tec(c, ri, ci, val):
    if ci == 0:
        write(c, val, bold=True, size=8.5, color=OURO)


cur.table(["Camada", "Tecnologia", "Por que foi escolhida"], C.TECNOLOGIAS, [3.0, 5.4, 6.6], fmt=fmt_tec)

# 6. Artefatos
cur = Cursor(P[12])
cur.para("Banco de dados e backend criados e testados; frontend em desenvolvimento.", size=10)


def fmt_art(c, ri, ci, val):
    if ci == 1:
        cor = {"Banco de dados": "0284C7", "Backend": "D97706", "Frontend": "16A34A"}.get(val, "595959")
        write(c, val, bold=True, size=8.5, color=cor)
    if ci == 2:
        write(c, val, size=8, font="Consolas")
    if ci == 3:
        write(c, val, bold=True, size=8.5, color="166534" if val == "Concluído" else "0369A1")


cur.table(["Artefato", "Camada", "Onde está", "Situação"], C.ARTEFATOS, [6.2, 2.4, 4.0, 2.4], fmt=fmt_art)
for img, w, cap in [
    ("print2_planilha.png", 16.0, "Figura 2 — Dados reais mensais levantados (trecho da planilha: São Paulo e Campinas, abr a set/2026). A planilha completa tem 8 cidades × 24 meses; a cor indica se o número é oficial, calculado de total oficial ou estimado."),
    ("print3_tabelas.png", 6.5, "Figura 3 — Banco de dados: banco ecocity criado no MySQL Workbench, com as tabelas e a mensagem de sucesso do script."),
    ("print4_bloqueio_recorte.png", 16.0, "Figura 4 — Banco de dados: regra de segurança funcionando. A tentativa de criar um administrador direto na tabela é bloqueada pelo trigger (só o DBA cria admin, com chave individual)."),
    ("print5_api.png", 14.0, "Figura 5 — Backend: API do EcoCity no ar, respondendo em http://localhost:3000/api/health."),
]:
    cur.image(PR / img, w, cap)

# 7. LinkedIn: links e print entram depois que os posts forem publicados

# ----------------------------------------------------------------- cronograma
cab = T_CAB_CRONO.rows[0].cells[0]
for p in cab.paragraphs:
    for r in p.runs:
        r.text = r.text.replace("__/__/____", C.DATA_CP2)
if C.DATA_CP2 not in cab.text:
    first = cab.paragraphs[0].runs
    for r in first[1:]:
        r.text = ""
    first[0].text = "CHECKPOINT 2: data da entrega " + C.DATA_CP2

ct = T_CRONO
modelo = copy.deepcopy(ct.rows[1]._tr)
while len(ct.rows) > 1:
    ct._tbl.remove(ct.rows[1]._tr)
for item in C.CRONOGRAMA:
    tr = copy.deepcopy(modelo); ct._tbl.append(tr)
    row = ct.rows[-1]
    for ci, val in enumerate(item[:5]):
        write(row.cells[ci], val, size=7.5).font.name = "Calibri"
        row.cells[ci].paragraphs[0].paragraph_format.line_spacing = 1.0
    nome, cor = C.STATUS[item[5]]
    c = row.cells[5]; c.text = ""
    p = c.paragraphs[0]; p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = 1.0
    r = p.add_run("●"); r.font.size = Pt(10); r.font.color.rgb = RGBColor.from_string(cor); r.font.name = "Arial"

for row in ct.rows[1:]:
    trPr = row._tr.get_or_add_trPr()
    hh = OxmlElement("w:trHeight"); hh.set(qn("w:val"), "245"); hh.set(qn("w:hRule"), "atLeast"); trPr.append(hh)
    for c in row.cells:
        margins(c, top=0, bottom=0, left=60, right=60)

# legenda com o mesmo símbolo (Webdings "n" não existe fora do Windows)
for p in d.paragraphs:
    for r in p.runs:
        if r.font.name == "Webdings" and r.text.strip() == "n":
            r.text = "●"; r.font.name = "Arial"

# remove parágrafos vazios entre o item 7 e o cronograma (sem quebra de seção)
for p in P[17:23] + P[26:29]:
    if not p.text.strip() and p._p.find('.//' + qn('w:sectPr')) is None and not p._p.findall('.//' + qn('w:drawing')):
        p._p.getparent().remove(p._p)

d.save(SAIDA)
print("salvo", SAIDA)
