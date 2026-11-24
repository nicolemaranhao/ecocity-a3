"""Monta o 3º Checkpoint usando o documento do 2º Checkpoint como base (mesmo layout do template)."""
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

BASE_DOCX, SAIDA = sys.argv[1], sys.argv[2]
DER, DIAG = BASE / "docs/der", BASE / "docs/diagramas"
DATA = "24/11/2026"
OURO = "806000"

d = docx.Document(BASE_DOCX)
body = d.element.body
EL = list(body)


def txt(el):
    return "".join(t.text or "" for t in el.iter(qn("w:t")))


# ----------------------------------------------------------------- utilitários (iguais aos do CP2)
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


def fix_widths(t, widths):
    for row in t.rows:
        trPr = row._tr.get_or_add_trPr(); cs = OxmlElement("w:cantSplit"); cs.set(qn("w:val"), "true"); trPr.insert(0, cs)
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


HEAD_MODELO = None  # parágrafo de título numerado (copiado do CP2)


class Cursor:
    def __init__(self, anchor_el):
        self.last = anchor_el

    def _place(self, el):
        self.last.addnext(el); self.last = el

    def titulo(self, texto):
        p = copy.deepcopy(HEAD_MODELO)
        rs = p.findall(qn("w:r"))
        for r in rs[1:]:
            p.remove(r)
        for t in rs[0].findall(qn("w:t"))[1:]:
            rs[0].remove(t)
        rs[0].find(qn("w:t")).text = texto
        self._place(p)

    def para(self, text="", bold=False, size=10.5, italic=False, color=None, indent=0.63, align=None, after=6, runs=None, keep=False):
        p = d.add_paragraph()
        p.paragraph_format.left_indent = Cm(indent); p.paragraph_format.space_after = Pt(after)
        p.paragraph_format.line_spacing = 1.15
        if keep: p.paragraph_format.keep_with_next = True
        if align: p.alignment = align
        for t, b in (runs or [(text, bold)]):
            r = p.add_run(t); r.bold = b; r.italic = italic; r.font.size = Pt(size)
            if color: r.font.color.rgb = RGBColor.from_string(color)
        self._place(p._p); return p

    def sub(self, texto):
        return self.para(texto, bold=True, size=11, color=OURO, after=4, keep=True)

    def bullet(self, text, lead=None):
        return self.para(runs=([("• " + lead, True), (text, False)] if lead else [("• " + text, False)]), indent=1.0, size=10, after=3)

    def image(self, path, width_cm, caption=None):
        p = d.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(2); p.paragraph_format.keep_with_next = True
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
        fix_widths(t, widths)
        trPr = t.rows[0]._tr.get_or_add_trPr(); h = OxmlElement("w:tblHeader"); h.set(qn("w:val"), "true"); trPr.append(h)
        self._place(t._tbl)
        self.para("", after=4, size=4)
        return t

    def caixa(self, titulo, texto, fill="FFF8E1", borda="BF8F00"):
        """Quadro 'Para explicar na apresentação' — fala curta, do nosso jeito."""
        t = d.add_table(rows=1, cols=1); t.alignment = WD_TABLE_ALIGNMENT.CENTER; t.autofit = False
        borders(t, borda)
        c = t.rows[0].cells[0]; shade(c, fill); margins(c, 90, 90, 140, 140)
        c.text = ""
        p = c.paragraphs[0]; p.paragraph_format.space_after = Pt(2)
        r = p.add_run(titulo); r.bold = True; r.font.size = Pt(9.5); r.font.color.rgb = RGBColor.from_string(OURO)
        for linha in texto if isinstance(texto, list) else [texto]:
            p = c.add_paragraph(); p.paragraph_format.space_after = Pt(2); p.paragraph_format.line_spacing = 1.1
            r = p.add_run(linha); r.font.size = Pt(9.5); r.italic = True
        fix_widths(t, [16.0])
        self._place(t._tbl)
        self.para("", after=4, size=4)

    def codigo(self, linhas, size=7.5):
        t = d.add_table(rows=1, cols=1); t.alignment = WD_TABLE_ALIGNMENT.CENTER; t.autofit = False
        borders(t, "D9D9D9")
        c = t.rows[0].cells[0]; shade(c, "F4F4F4"); margins(c, 70, 70, 120, 120)
        c.text = ""
        for i, linha in enumerate(linhas):
            p = c.paragraphs[0] if i == 0 else c.add_paragraph()
            p.paragraph_format.space_after = Pt(0); p.paragraph_format.line_spacing = 1.0
            r = p.add_run(linha); r.font.size = Pt(size); r.font.name = "Courier New"
            r._element.rPr.rFonts.set(qn("w:eastAsia"), "Courier New")
        fix_widths(t, [16.0])
        self._place(t._tbl)
        self.para("", after=4, size=4)


# ----------------------------------------------------------------- cabeçalho e data
for t in EL[0].iter(qn("w:t")):
    if (t.text or "") == "2":
        t.text = "3"; break
for t in EL[1].iter(qn("w:t")):
    if "20/10/2026" in (t.text or ""):
        t.text = t.text.replace("20/10/2026", DATA)
assert "3º" in txt(EL[0]) and DATA in txt(EL[1]), "cabeçalho/data não trocados"

# guarda modelos e remove o miolo do CP2 (requisitos, DER preliminar, SGBD, artefatos)
HEAD_MODELO = copy.deepcopy(EL[10])
SECT_RETRATO = copy.deepcopy(EL[22])
SECT_PAISAGEM = copy.deepcopy(EL[25])
assert "Requisitos" in txt(EL[10]) and "Post no LinkedIn" in txt(EL[45])
for el in EL[10:45]:
    body.remove(el)

cur = Cursor(EL[9])

# ================================================================= 4. O que mudou desde o Checkpoint 2
cur.titulo("O que mudou desde o Checkpoint 2")
cur.para("No Checkpoint 2 entregamos o DER preliminar e as primeiras tabelas. De lá para cá, o projeto cresceu e o desenho "
         "precisou de alguns ajustes. Resumindo o que fizemos neste mês:", size=10)
cur.bullet(" o DER foi revisado e ficou completo (27 entidades em 4 figuras), incluindo o cadastro profissional, que tinha ficado de fora, "
           "e a nova entidade COLETA_VERIFICACAO.", "DER finalizado:")
cur.bullet(" criamos um “robô de coleta” que, todo mês, confere os sites oficiais (ANEEL, SPTrans, EPE, SEEG, SNIS/SINISA, IBGE) "
           "e grava os números novos. Para isso o banco ganhou uma tabela que registra cada conferência e duas colunas na área de entrada (staging).", "Atualização automática:")
cur.bullet(" encontramos dados oficiais mais recentes de energia por cidade (Anuário de Energéticos da SEMIL-SP) e de água de Campinas (SANASA). "
           "Elas entraram como novas LINHAS nas tabelas orgao e fonte_dados, sem mudar nenhuma tabela. Isso mostrou para a gente que o modelo estava bem feito.", "Duas fontes oficiais novas:")
cur.bullet(" passamos o desenho para tabelas (modelo lógico), revisamos a normalização até a 3ª Forma Normal e "
           "organizamos o script SQL (CREATE + INSERT) em arquivos numerados, já no GitHub.", "Modelo lógico e script:")
cur.para("", after=2, size=4)

# ================================================================= 5. DER finalizado
cur.titulo("DER finalizado")
cur.para("O DER é o “desenho” do banco. Os retângulos são as coisas que queremos guardar (entidades), a lista dentro de cada um são as "
         "informações dela (atributos; o sublinhado é o identificador) e os losangos mostram como elas se ligam (relacionamentos). "
         "Como o desenho inteiro ficaria pequeno demais para ler, dividimos em 4 figuras por assunto. "
         "Quando uma entidade aparece com borda tracejada, é porque ela é detalhada em outra figura e só está ali para mostrar a ligação.", size=10)
cur.para(runs=[("Como ler os números (mín,máx): ", True),
               ("o par escrito junto de uma entidade diz quantas vezes ela aparece para UMA ocorrência do outro lado. "
                "Exemplo da Figura 1: FONTE_DADOS (1,1) — fornece — (0,N) DADO. Lemos assim: cada número guardado vem de exatamente uma fonte; "
                "e uma fonte pode ter fornecido nenhum ou vários números.", False)], size=10)
cur.para("Notação usada: Peter Chen, com cardinalidade mínima e máxima. Os arquivos editáveis (draw.io) estão no GitHub, na pasta docs/der.",
         size=9.5, italic=True, color="595959")
cur._place(copy.deepcopy(SECT_RETRATO))
cur.image(DER / "der_1_dados_indicadores.png", 22.5,
          "Figura 1 — Dados, indicadores e metas: de onde vem cada número (órgão → fonte → lote de carga) e onde ele é guardado (DADO), "
          "ligado à cidade e à métrica. Em rosa, a parte de coleta; em azul, cidades e medições; em verde, indicadores e metas.")
cur._place(copy.deepcopy(SECT_PAISAGEM))
cur.image(DER / "der_2_pessoas_seguranca.png", 16.0,
          "Figura 2 — Pessoas e segurança: cada usuário tem um perfil (cidadão, gestor, analista ou administrador). "
          "Gestores comprovam o vínculo com o órgão (CADASTRO_PROFISSIONAL); analistas têm credencial por serviço.")
cur.image(DER / "der_3_analises.png", 16.0,
          "Figura 3 — Análises: as escritas pelos analistas (com evidências e comentários) e os alertas automáticos da IA (ANALISE_IA).")
cur.image(DER / "der_4_acoes_copiloto.png", 16.0,
          "Figura 4 — Ações e resultados (o que a prefeitura fez para melhorar um indicador e o que mudou), relatórios e perguntas ao Copiloto (IA).")
cur.sub("Principais regras de negócio que o DER garante")
for lead, t in [
    ("Todo número tem dono: ", "um DADO sempre pertence a 1 cidade, 1 métrica e 1 fonte oficial — não existe número “solto”."),
    ("Um número por mês: ", "a mesma fonte não pode mandar duas vezes o mesmo número para a mesma cidade, métrica e mês."),
    ("Cada métrica tem uma unidade só: ", "por exemplo, energia sempre em MWh e água sempre em m³, para não misturar."),
    ("Meta passa por aprovação: ", "um gestor propõe, um analista dá parecer e o gestor responsável aprova."),
    ("Relações muitos-para-muitos: ", "uma análise publicada pode falar de várias cidades e uma cidade aparece em várias análises (o losango amarelo indica esses casos)."),
]:
    cur.bullet(t, lead)
cur.caixa("Para explicar na apresentação",
          "“O DER é a planta do nosso banco. No centro está o DADO: cada número que mostramos no site é uma linha dele, "
          "e ele sempre está ligado a uma cidade, a uma métrica e à fonte oficial de onde veio. Em volta disso ficam as pessoas, as metas, as análises e as ações.”")

# ================================================================= 6. Modelo lógico
cur.titulo("Modelo lógico")
cur.para("O modelo lógico é o DER “traduzido” para tabelas do MySQL. Para fazer essa tradução seguimos quatro regras simples:", size=10)
for lead, t in [
    ("Entidade vira tabela: ", "MUNICIPIO virou a tabela municipio, com uma chave primária (PK) que identifica cada linha (id_municipio)."),
    ("Relacionamento 1 para N vira chave estrangeira (FK): ", "a FK fica do lado do “N”. Ex.: uma cidade tem vários dados, então a tabela dado guarda id_municipio."),
    ("Relacionamento N para N vira uma tabela no meio: ", "análise ↔ cidade virou analise_municipio; relatório ↔ cidade virou relatorio_municipio."),
    ("Relacionamento 1 para 1 usa a mesma chave: ", "o cadastro profissional usa o próprio id_usuario como chave (cada usuário tem no máximo um)."),
]:
    cur.bullet(t, lead)
cur.para("Além das tabelas que vêm do DER, criamos tabelas “técnicas”: a área de entrada dos dados (staging), o registro do robô de coleta, "
         "o log de acesso, a auditoria e o Data Warehouse (dimensões e fatos), usado pelos painéis. No total são 37 tabelas, "
         "com 37 chaves primárias, 65 chaves estrangeiras, 21 regras UNIQUE e 40 regras CHECK.", size=10)
cur.sub("As 37 tabelas, por assunto")
GR = [
    ("Fontes e coleta", [("orgao", "id_orgao", "—", "Órgãos públicos que publicam os dados (ANEEL, EPE, SPTrans…)"),
                         ("fonte_dados", "id_fonte", "id_orgao, id_servico, avaliada_por", "Cada base/arquivo oficial, com link e frequência"),
                         ("lote_carga", "id_lote", "id_fonte", "Cada vez que um arquivo é carregado"),
                         ("stg_medicao_bruta", "id_stg", "id_lote", "Área de entrada: o dado chega como texto e é validado"),
                         ("coleta_verificacao", "id_verificacao", "id_fonte, id_lote", "Cada conferência do robô de coleta (novo no CP3)")]),
    ("Cidades e medições", [("servico_publico", "id_servico", "—", "Água, energia, mobilidade e resíduos"),
                            ("unidade_medida", "id_unidade", "—", "m³, MWh, kW, toneladas…"),
                            ("metrica", "id_metrica", "id_servico, id_unidade", "O que é medido (ex.: energia consumida)"),
                            ("municipio", "id_municipio", "—", "As 8 cidades, com código do IBGE"),
                            ("populacao_anual", "id_municipio + ano", "id_municipio", "População de cada cidade por ano (IBGE)"),
                            ("dado", "id_dado", "id_fonte, id_municipio, id_metrica, id_lote", "O número em si: cidade + métrica + mês + valor + origem")]),
    ("Indicadores e metas", [("indicador", "id_indicador", "id_servico, id_unidade", "Indicadores (ex.: litros por habitante por dia)"),
                             ("indicador_valor", "id_indicador_valor", "id_indicador, id_municipio", "Valor do indicador calculado por mês"),
                             ("meta", "id_meta", "id_indicador, id_municipio, proposta_por, parecer_por, aprovada_por", "Metas com fluxo de aprovação"),
                             ("analise_ia", "id_analise", "id_indicador, id_municipio, revisada_por", "Alertas automáticos (ex.: consumo subiu muito)")]),
    ("Pessoas e segurança", [("perfil", "id_perfil", "—", "Cidadão, gestor, analista, administrador"),
                             ("usuario", "id_usuario", "id_perfil, id_municipio", "Contas de acesso (senha guardada só como hash)"),
                             ("cadastro_profissional", "id_usuario", "id_usuario, id_municipio_atuacao, analisado_por", "Comprovação do vínculo do gestor"),
                             ("credencial_analista", "id_usuario", "id_usuario, id_servico, verificado_por", "Credencial do analista por serviço"),
                             ("acesso_log", "id_acesso", "id_usuario", "Tentativas de login (certas e erradas)"),
                             ("auditoria", "id_auditoria", "— (de propósito)", "Histórico de alterações, preenchido por triggers")]),
    ("Ações", [("acao", "id_acao", "id_analise, id_indicador_alvo, id_municipio, id_responsavel", "O que a prefeitura fez"),
               ("resultado", "id_resultado", "id_acao, id_indicador, registrado_por", "O efeito medido da ação")]),
    ("Análises e Copiloto", [("analise_publicada", "id_analise_pub", "id_autor, revisado_por, id_servico", "Análises escritas pelos analistas"),
                             ("analise_evidencia", "id_evidencia", "id_analise_pub, id_indicador, id_municipio", "Números que embasam a análise"),
                             ("analise_comentario", "id_comentario", "id_analise_pub, id_usuario", "Comentários dos leitores"),
                             ("analise_municipio", "id_analise_pub + id_municipio", "as duas", "Tabela do N:N análise ↔ cidade"),
                             ("relatorio_ia", "id_relatorio", "solicitado_por, revisado_por", "Relatórios gerados pelo Copiloto"),
                             ("relatorio_municipio", "id_relatorio + id_municipio", "as duas", "Tabela do N:N relatório ↔ cidade"),
                             ("pergunta_ia", "id_pergunta", "id_usuario", "Perguntas feitas ao Copiloto")]),
    ("Data Warehouse (painéis)", [("dim_tempo, dim_municipio, dim_metrica, dim_indicador, dim_servico", "sk_… (chave substituta)", "—", "Dimensões: os “filtros” dos painéis"),
                                  ("fato_medicao", "sk_tempo + sk_municipio + sk_metrica", "as dimensões", "Medições prontas para gráfico"),
                                  ("fato_indicador", "sk_tempo + sk_municipio + sk_indicador", "as dimensões", "Indicadores prontos para gráfico")]),
]
linhas = []
for g, ts in GR:
    linhas.append((g.upper(), "", "", ""))
    linhas.extend(ts)


def fmt_grupo(c, ri, ci, val):
    if linhas[ri][1] == "":
        shade(c, "EDE3C3")
        if ci == 0:
            write(c, val, bold=True, size=8, color=OURO)
    elif ci == 0:
        write(c, val, bold=True, size=8)


cur.table(["Tabela", "Chave primária (PK)", "Chaves estrangeiras (FK)", "Para que serve"], linhas, [3.6, 3.2, 4.4, 4.8], size=8, fmt=fmt_grupo)
cur.sub("Exemplo detalhado: a tabela dado (o coração do banco)")
cur.para("Cada linha é UM número: uma cidade, uma métrica, um mês. Os tipos foram escolhidos para guardar exatamente o necessário:", size=10)
cur.table(["Coluna", "Tipo", "Regra", "Em palavras simples"], [
    ("id_dado", "BIGINT", "PK, automático", "Número de identificação da linha"),
    ("id_fonte", "SMALLINT", "FK → fonte_dados, NOT NULL", "De qual fonte oficial veio"),
    ("id_municipio", "SMALLINT", "FK → municipio, NOT NULL", "De qual cidade é"),
    ("id_metrica", "SMALLINT", "FK → metrica, NOT NULL", "O que foi medido (e, pela métrica, a unidade)"),
    ("id_lote", "INT", "FK → lote_carga (pode ser nulo)", "Em qual carga entrou"),
    ("data_referencia", "DATE", "CHECK: sempre dia 1", "O mês do dado (guardamos 01/06/2026 para junho)"),
    ("valor", "DECIMAL(16,4)", "CHECK: valor ≥ 0", "O número. DECIMAL não arredonda errado como FLOAT"),
    ("origem", "ENUM", "REAL, DERIVADO ou ESTIMADO", "Oficial do mês, oficial do ano (dividido pelos meses) ou estimado"),
    ("referencia_origem", "VARCHAR(300)", "texto", "Explica de onde saiu o número ou como foi estimado"),
    ("(fonte, cidade, métrica, mês)", "—", "UNIQUE", "Impede gravar o mesmo número duas vezes"),
], [3.4, 2.6, 4.2, 5.8], size=8)
cur.para("Escolhemos guardar a origem de cada número porque várias fontes oficiais só publicam por ano. Assim o site sempre mostra, "
         "ao lado do valor, se ele é oficial ou estimado — e de onde veio.", size=10)
cur.image(DER / "der_5_dw_estrela.png", 9.5,
          "Figura 5 — Data Warehouse em estrela: os fatos (no meio) ligados às dimensões (tempo, cidade, métrica, indicador e serviço). "
          "É preenchido a partir das tabelas normalizadas pelo procedimento sp_pipeline_mensal.")
cur.caixa("Para explicar na apresentação",
          "“No modelo lógico, cada retângulo do DER virou uma tabela e cada ligação virou uma chave estrangeira. "
          "Quando a ligação é de muitos para muitos, criamos uma tabela no meio. A tabela dado é a principal: "
          "cada linha é um número de uma cidade em um mês, e as regras do banco não deixam gravar número negativo, repetido ou sem fonte.”")

# ================================================================= 7. Normalização
cur.titulo("Normalização aplicada (até a 3ª Forma Normal)")
cur.para("Normalizar é organizar as tabelas para não repetir informação. Quando algo se repete, uma hora alguém corrige em um lugar "
         "e esquece do outro, e o banco passa a ter duas “verdades”. Vamos mostrar o passo a passo com um exemplo real do nosso banco: "
         "Campinas, junho de 2026.", size=10)
cur.sub("Ponto de partida: a “planilhona”")
cur.para("Se tivéssemos guardado tudo como vem dos sites, numa planilha só, ficaria mais ou menos assim:", size=10)
cur.table(["Cidade", "Cód. IBGE", "Região", "Mês", "Medições do mês"], [
    ("Campinas", "3509502", "RM de Campinas", "06/2026",
     "água 6.518.544 m³ (SANASA – SANASA); energia 273.769 MWh (EPE – EPE); solar 140.334 kW (ANEEL – ANEEL); ônibus 10.218.567 passageiros…"),
], [2.0, 1.8, 2.6, 1.4, 8.2], size=8)
cur.para("Problema: a última coluna tem vários valores dentro da mesma célula. Para somar a energia de todas as cidades, "
         "seria preciso “recortar” o texto. Isso não dá para fazer direito com SQL.", size=10)
cur.sub("1ª Forma Normal (1FN): um valor por célula")
cur.para("Regra: cada célula guarda um valor só, e não há listas nem colunas repetidas (como “água jan”, “água fev”…). "
         "Então separamos: uma linha para cada número.", size=10)
cur.table(["Cidade", "Cód. IBGE", "Região", "Mês", "Métrica", "Unidade", "Valor", "Fonte", "Órgão", "Origem"], [
    ("Campinas", "3509502", "RM de Campinas", "06/2026", "Água consumida", "m³", "6.518.544", "SANASA – Relatórios…", "SANASA", "DERIVADO"),
    ("Campinas", "3509502", "RM de Campinas", "06/2026", "Energia consumida", "MWh", "273.769", "EPE – Consumo mensal…", "EPE", "ESTIMADO"),
    ("Campinas", "3509502", "RM de Campinas", "06/2026", "Potência solar", "kW", "140.334", "ANEEL – Geração Distribuída", "ANEEL", "REAL"),
], [1.5, 1.4, 1.9, 1.2, 1.9, 1.1, 1.4, 2.4, 1.3, 1.9], size=7)
cur.para("Melhorou, mas agora “Campinas / 3509502 / RM de Campinas” se repete em toda linha. Com 8 métricas e 45 meses, "
         "isso dá 360 repetições só para Campinas.", size=10)
cur.sub("2ª Forma Normal (2FN): cada informação depende da chave inteira")
cur.para("A chave dessa tabela é o conjunto (cidade + métrica + mês + fonte): é isso que identifica um número. "
         "Mas o código do IBGE e a região dependem só da cidade, e a unidade depende só da métrica — ou seja, de um PEDAÇO da chave. "
         "Pela 2FN, essas informações vão para tabelas próprias:", size=10)
cur.bullet("municipio (id_municipio, nome, codigo_ibge, regiao_metropolitana, …) — os dados da cidade ficam escritos uma vez só;")
cur.bullet("metrica (id_metrica, codigo, nome, …) — a descrição da métrica fica escrita uma vez só;")
cur.bullet("dado (id_fonte, id_municipio, id_metrica, data_referencia, valor, origem) — guarda só o número e os “ponteiros” (FKs).")
cur.sub("3ª Forma Normal (3FN): nada depende de outra coluna que não seja a chave")
cur.para("Ainda sobrou dependência “indireta”: na métrica, o nome da unidade (“metro cúbico”) depende da unidade, não da métrica; "
         "na fonte, o nome do órgão depende do órgão, não da fonte. Pela 3FN, cada uma vira sua própria tabela:", size=10)
cur.table(["Antes (dependência indireta)", "Depois (3FN)"], [
    ("metrica → unidade → “m³ – metro cúbico”", "metrica.id_unidade → unidade_medida (sigla, descrição)"),
    ("fonte → órgão → “Agência Nacional de Energia Elétrica”", "fonte_dados.id_orgao → orgao (nome, sigla, tipo)"),
    ("métrica/fonte → serviço → “Água”", "id_servico → servico_publico (nome, descrição)"),
], [7.6, 8.4], size=8.5)
cur.para("Resultado: se um dia a ANEEL mudar de nome, mudamos UMA linha na tabela orgao e todo o site já mostra o nome novo. "
         "Foi exatamente isso que aconteceu quando incluímos a SEMIL e a SANASA: bastou inserir linhas, sem mexer na estrutura.", size=10)
cur.sub("E o Data Warehouse? Desnormalizado de propósito")
cur.para("As tabelas dim_ e fato_ repetem alguns nomes de propósito (modelo estrela), porque assim os gráficos do painel carregam rápido, "
         "sem precisar juntar muitas tabelas. Isso não gera bagunça porque o Data Warehouse não é editado à mão: ele é sempre "
         "recalculado a partir das tabelas normalizadas.", size=10)
cur.caixa("Para explicar na apresentação",
          ["“Na 1FN tiramos as listas de dentro das células: virou uma linha por número.",
           "Na 2FN tiramos o que dependia só de um pedaço da chave: os dados da cidade foram para municipio e os da métrica para metrica.",
           "Na 3FN tiramos o que dependia de outra coluna: a unidade foi para unidade_medida e o órgão para orgao.",
           "No fim, cada informação está escrita em um lugar só.”"])

# ================================================================= 8. Script SQL inicial
cur.titulo("Script SQL inicial (CREATE + INSERT)")
cur.para(runs=[("Repositório no GitHub: ", True), ("[colar aqui o link do repositório]", False),
               ("  — o acesso foi compartilhado com a professora.", False)], size=10)
cur.para("O script está dividido em arquivos numerados, para dar para rodar por partes e entender cada etapa. "
         "Para este checkpoint, os principais são o 01 (CREATE) e o 07 (INSERT); os outros já adiantam o que vem no relatório final.", size=10)
cur.table(["Arquivo", "O que faz"], [
    ("01_create_database_tabelas.sql", "CREATE DATABASE ecocity e CREATE TABLE das 37 tabelas, com PK, FK, NOT NULL, UNIQUE e CHECK"),
    ("02_indices.sql", "Índices para as consultas mais usadas ficarem rápidas"),
    ("03_funcoes_views.sql", "Funções e 18 views (consultas prontas para o site e os relatórios)"),
    ("04_triggers.sql", "Triggers de auditoria e de regras (ex.: só o DBA cria administrador)"),
    ("05_procedures_eventos.sql", "Procedures de carga e cálculo (validação da staging, indicadores, Data Warehouse)"),
    ("06_seguranca.sql", "Usuários do banco e permissões (CREATE USER, GRANT, REVOKE)"),
    ("07_dados_teste.sql (+07b, 07c)", "INSERTs: cidades, órgãos, fontes, métricas, usuários e 2.880 números de jan/2023 a set/2026"),
    ("08 a 11", "Consultas de relatório, backup/monitoramento, testes de integridade e coleta automática"),
    ("00_executar_tudo.sql / ecocity_banco_completo.sql", "Rodam tudo na ordem certa (o segundo é um arquivo único)"),
], [5.6, 10.4], size=8.5)
cur.sub("Trecho do CREATE TABLE (arquivo 01)")
cur.codigo([
    "CREATE TABLE dado (",
    "  id_dado          BIGINT UNSIGNED AUTO_INCREMENT,",
    "  id_fonte         SMALLINT UNSIGNED NOT NULL,",
    "  id_municipio     SMALLINT UNSIGNED NOT NULL,",
    "  id_metrica       SMALLINT UNSIGNED NOT NULL,",
    "  id_lote          INT UNSIGNED NULL,",
    "  data_referencia  DATE NOT NULL,                 -- sempre o 1º dia do mês",
    "  valor            DECIMAL(16,4) NOT NULL,",
    "  origem           ENUM('REAL','DERIVADO','ESTIMADO') NOT NULL DEFAULT 'REAL',",
    "  referencia_origem VARCHAR(300) NULL,            -- de onde veio o número",
    "  CONSTRAINT pk_dado PRIMARY KEY (id_dado),",
    "  CONSTRAINT uq_dado_chave UNIQUE (id_fonte, id_municipio, id_metrica, data_referencia),",
    "  CONSTRAINT fk_dado_fonte     FOREIGN KEY (id_fonte)     REFERENCES fonte_dados (id_fonte),",
    "  CONSTRAINT fk_dado_municipio FOREIGN KEY (id_municipio) REFERENCES municipio (id_municipio),",
    "  CONSTRAINT fk_dado_metrica   FOREIGN KEY (id_metrica)   REFERENCES metrica (id_metrica),",
    "  CONSTRAINT ck_dado_valor CHECK (valor >= 0),",
    "  CONSTRAINT ck_dado_mes   CHECK (DAY(data_referencia) = 1)",
    ") ENGINE=InnoDB;",
])
cur.sub("Trecho dos INSERTs (arquivo 07)")
cur.codigo([
    "INSERT INTO municipio (nome, codigo_ibge, regiao_metropolitana, area_km2, populacao, fonte_populacao) VALUES",
    "  ('São Paulo', '3550308', 'RM de São Paulo', 1521.202, 11451999, 'IBGE - Censo 2022'),",
    "  ('Campinas',  '3509502', 'RM de Campinas',   794.571,  1139047, 'IBGE - Censo 2022');",
    "",
    "INSERT INTO dado (id_fonte, id_municipio, id_metrica, id_lote, data_referencia, valor, origem, referencia_origem) VALUES",
    "  (7, 1, 7, 7, '2026-06-01', 162608085.0000, 'REAL',",
    "   'SPTrans jun/2026: soma diária das viagens de passageiros (30 de 30 dias publicados)'),",
    "  (4, 2, 4, 4, '2026-06-01', 140333.8600, 'REAL',",
    "   'ANEEL - geração distribuída: potência acumulada até o fim de jun/2026');",
])
cur.para("Os INSERTs não são números inventados: foram montados a partir dos arquivos baixados dos sites oficiais. "
         "Hoje o banco tem 2.880 números das 8 cidades, de jan/2023 a set/2026:", size=10)
cur.table(["Origem do número", "Quantidade", "%", "O que significa"], [
    ("Oficial do mês (REAL)", "405", "14%", "A fonte publica o número daquele mês"),
    ("Oficial do ano (DERIVADO)", "1.240", "43%", "A fonte publica o total do ano; dividimos pelos meses"),
    ("Estimado (ESTIMADO)", "1.235", "43%", "Ainda não saiu dado oficial; calculamos e avisamos no site"),
    ("Total", "2.880", "100%", "57% são oficiais"),
], [4.4, 2.2, 1.4, 8.0], size=8.5)
cur.para(runs=[("Como testar: ", True),
               ("no MySQL Workbench, abrir o arquivo ecocity_banco_completo.sql e executar (raio). Depois, por exemplo: ", False),
               ("SELECT origem, COUNT(*) FROM dado GROUP BY origem;", False)], size=10)
cur.caixa("Para explicar na apresentação",
          "“Primeiro rodamos o CREATE, que monta as tabelas com as regras. Depois os INSERTs, que colocam as cidades, as fontes "
          "e os números reais. Se alguém tentar gravar um valor negativo ou um mês repetido, o próprio banco recusa.”")

# ================================================================= 9. Dificuldades e aprendizados
cur.titulo("Dificuldades e o que aprendemos")
for lead, t in [
    ("Dados que só saem por ano: ", "a maior dificuldade. Muitos órgãos publicam água, resíduos e emissões só uma vez por ano, com atraso. "
     "Em vez de esconder isso, criamos a coluna origem e mostramos no site o que é oficial e o que é estimado."),
    ("Cada site publica de um jeito: ", "PDF (SPTrans), planilha (EPE), arquivo compactado (ANEEL), API (IBGE e SEEG). "
     "Por isso tudo entra primeiro na staging, como texto, e só vai para a tabela dado depois de validado."),
    ("Entender cardinalidade: ", "no começo achávamos que o DER era só um desenho. Quando criamos as tabelas, vimos que cada (0,N) virava uma FK — e aí fez sentido."),
    ("Normalização na prática: ", "percebemos o valor dela quando entraram as duas fontes novas: não precisamos mudar nenhuma tabela."),
]:
    cur.bullet(t, lead)
cur.sub("Próximos passos até a entrega final (30/11)")
for t in ["publicar o banco na Oracle Cloud (MySQL HeatWave);",
          "escrever o relatório final no template da A3 (backup, segurança e impacto sustentável);",
          "preparar os slides e gravar o vídeo de até 20 minutos com as duas integrantes;",
          "publicar o 3º post no LinkedIn."]:
    cur.bullet(t)
cur.para("", after=2, size=4)

# ----------------------------------------------------------------- cronograma
cron_cab = [t for t in body.iter(qn("w:tbl")) if "CHECKPOINT 2: data da entrega" in txt(t)][0]
for t in cron_cab.iter(qn("w:t")):
    if t.text:
        t.text = t.text.replace("CHECKPOINT 2", "CHECKPOINT 3").replace("20/10/2026", DATA)
CRONO = [it for it in C.CRONOGRAMA]
CRONO[6] = ('7. Backend (API com login, cadastros, metas e análises)',) + CRONO[6][1:]
CRONO += [
    ('9. Frontend (site público, painel do cidadão, do gestor e do analista)', '13/11/2026', 'Gabriela e Nicole', 'Backend', '', 'C'),
    ('10. Robô de coleta mensal das fontes oficiais (atualização automática)', '16/11/2026', 'Nicole', 'Banco + backend', 'Sites de alguns órgãos mudam o formato dos arquivos', 'C'),
    ('11. DER finalizado (4 figuras, notação de Chen)', '17/11/2026', 'Nicole', 'DER preliminar', '', 'C'),
    ('12. Modelo lógico e normalização até a 3FN', '18/11/2026', 'Gabriela', 'DER finalizado', '', 'C'),
    ('13. Script SQL inicial (CREATE + INSERT) no GitHub', '20/11/2026', 'Gabriela e Nicole', 'Modelo lógico', '', 'C'),
    ('14. Entrega do Checkpoint 3 + post no LinkedIn', DATA, 'Gabriela e Nicole', 'Atividades 11 a 13', '', 'D'),
    ('15. Publicação do banco na Oracle Cloud (MySQL HeatWave)', '27/11/2026', 'Gabriela', 'Script SQL', '', 'N'),
    ('16. Relatório final (template A3)', '30/11/2026', 'Gabriela e Nicole', 'Atividades 1 a 15', '', 'N'),
    ('17. Slides e vídeo demonstrativo (até 20 min)', '30/11/2026', 'Gabriela e Nicole', 'Relatório final', '', 'N'),
    ('18. 3º post no LinkedIn', '30/11/2026', 'Nicole', 'Vídeo', '', 'N'),
]
T = [t for t in d.tables if t.rows[0].cells[0].text.strip().startswith("Atividades")][0]
modelo = copy.deepcopy(T.rows[1]._tr)
while len(T.rows) > 1:
    T._tbl.remove(T.rows[1]._tr)
for item in CRONO:
    tr = copy.deepcopy(modelo); T._tbl.append(tr)
    row = T.rows[-1]
    for ci, val in enumerate(item[:5]):
        write(row.cells[ci], val, size=7.5).font.name = "Calibri"
        row.cells[ci].paragraphs[0].paragraph_format.line_spacing = 1.0
    nome, cor = C.STATUS[item[5]]
    c = row.cells[5]; c.text = ""
    p = c.paragraphs[0]; p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(0); p.paragraph_format.line_spacing = 1.0
    r = p.add_run("●"); r.font.size = Pt(10); r.font.color.rgb = RGBColor.from_string(cor); r.font.name = "Arial"

d.core_properties.title = "3º Checkpoint A3 — EcoCity"
d.save(SAIDA)
print("ok", SAIDA)
