"""Carrossel do LinkedIn (CP2), versão com a logo final. 7 imagens 1080x1350."""
import pathlib, re
from playwright.sync_api import sync_playwright

OUT = pathlib.Path(__file__).parent
DOCS = OUT.parent
CP = pathlib.Path('/tmp/claude-0/-home-claude/1c6b68db-97a3-5a09-8184-4096558091c3/scratchpad/cp2ppt')
LOGO_SVG = (DOCS / 'marca/EcoCity_logo.svg').read_text()
corpo_logo = re.search(r'<svg[^>]*>(.*)</svg>', LOGO_SVG, re.S).group(1)
icone_corpo = re.sub(r'<text.*?</text>', '', corpo_logo, flags=re.S)

def logo(w):        # logo completa (ícone + nome)
    return f'<svg viewBox="30 30 340 430" width="{w}">{corpo_logo}</svg>'

def icone(w):       # só os 4 quadrados
    return f'<svg viewBox="30 30 340 340" width="{w}">{icone_corpo}</svg>'

DER = DOCS / 'linkedin/der_simples.png'
TAB = CP / 'print3_lista.png'
API = DOCS / 'checkpoint2/prints/print5_api.png'
COD = CP / 'print4_codigo3.png'
MSG = CP / 'print4_msg.png'

NAVY, AZUL, VERDE, LARANJA, CEU = '#163E6E', '#1D5FA8', '#2F8F3F', '#E8892B', '#4FB3E3'

CSS = f"""
*{{box-sizing:border-box;margin:0;padding:0}}
body{{width:1080px;height:1350px;font-family:Inter,sans-serif;background:#F6F8FB;color:{NAVY};position:relative;overflow:hidden}}
.faixa{{position:absolute;left:0;right:0;top:0;height:14px;display:flex}}
.faixa i{{flex:1}}
.pad{{padding:96px 76px 170px;height:1350px;display:flex;flex-direction:column;justify-content:center}}
.tag{{align-self:flex-start;font-size:24px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:{AZUL};background:#E3EDF8;border-radius:40px;padding:12px 26px}}
h1{{font-family:'Inter Display',Inter;font-weight:800;font-size:84px;line-height:1.04;letter-spacing:-.02em;margin-top:36px}}
h2{{font-family:'Inter Display',Inter;font-weight:800;font-size:64px;line-height:1.08;letter-spacing:-.015em;margin-top:30px}}
.sub{{font-size:33px;line-height:1.42;color:#3E5675;margin-top:26px}}
.az{{color:{AZUL}}} .vd{{color:{VERDE}}}
.foot{{position:absolute;left:76px;right:76px;bottom:56px;display:flex;align-items:center;justify-content:space-between;font-size:22px;color:#6B7F99;border-top:2px solid #DCE4EE;padding-top:22px}}
.foot .marca{{display:flex;align-items:center;gap:14px;font-weight:600;color:{NAVY}}}
.card{{background:#fff;border:2px solid #E1E8F1;border-radius:28px;padding:30px 34px}}
.grid2{{display:grid;grid-template-columns:1fr 1fr;gap:22px}}
.num{{font-family:'Inter Display';font-weight:800;font-size:74px;line-height:1}}
.lab{{font-size:26px;color:#3E5675;margin-top:10px}}
ul.ck{{list-style:none;margin-top:30px}}
ul.ck li{{font-size:36px;line-height:1.35;padding:28px 0 28px 70px;position:relative;border-bottom:2px solid #E1E8F1}}
ul.ck li:before{{content:'';position:absolute;left:0;top:33px;width:42px;height:42px;border-radius:12px;background:{VERDE}}}
ul.ck li:after{{content:'';position:absolute;left:14px;top:41px;width:12px;height:20px;border:solid #fff;border-width:0 5px 5px 0;transform:rotate(45deg)}}
.foto{{background:#fff;border:2px solid #E1E8F1;border-radius:24px;padding:16px;margin-top:30px}}
.foto img{{width:100%;display:block;border-radius:10px}}
.cap{{font-size:25px;color:#3E5675;margin-top:14px;text-align:center;font-weight:600}}
.svc{{display:flex;align-items:center;gap:28px;font-size:34px;padding:22px 0;border-bottom:2px solid #E1E8F1}}
.sq{{width:62px;height:62px;border-radius:16px;flex:0 0 auto}}
.svc small{{display:block;font-size:25px;color:#6B7F99;margin-top:4px}}
.step{{display:flex;gap:24px;align-items:flex-start;padding:20px 0;border-bottom:2px solid #E1E8F1}}
.badge{{flex:0 0 auto;font-size:23px;font-weight:700;padding:10px 0;border-radius:12px;color:#fff;width:170px;text-align:center}}
.step p{{font-size:29px;line-height:1.38;color:#2C4462}}
.chip{{display:inline-block;font-size:26px;font-weight:600;border-radius:14px;padding:12px 20px;margin:10px 10px 0 0;background:#fff;border:2px solid #E1E8F1}}
"""

FAIXA = f'<div class=faixa><i style="background:{VERDE}"></i><i style="background:{AZUL}"></i><i style="background:{LARANJA}"></i><i style="background:{CEU}"></i></div>'

def pagina(n, corpo):
    return f"""<!doctype html><html><head><meta charset=utf-8><style>{CSS}</style></head><body>{FAIXA}
<div class=pad>{corpo}</div>
<div class=foot><span class=marca>{icone(40)}<span>EcoCity · A3 Banco de Dados · Anhembi Morumbi</span></span><span>{n}/7</span></div></body></html>"""

SLIDES = [
# 1 capa
pagina(1, f"""<div style="display:flex;justify-content:center;margin-bottom:6px">{logo(330)}</div>
<span class=tag style="align-self:center;margin-top:30px">2º checkpoint · A3</span>
<h1 style="text-align:center;font-size:76px">O banco de dados do EcoCity <span class=az>saiu do papel</span>.</h1>
<p class=sub style="text-align:center">Água, energia, lixo e transporte de 8 cidades de São Paulo, mês a mês, num só banco.</p>
<p class=sub style="text-align:center;font-size:27px;margin-top:40px;color:#6B7F99">Gabriela Sant’Ana Merces Assis · Nicole Maranhão Assis</p>"""),
# 2 problema
pagina(2, f"""<span class=tag>O problema</span>
<h2>Os dados da cidade existem. <span class=az>Só não conversam entre si.</span></h2>
<div style="margin-top:34px">
 <div class=svc><div class=sq style="background:{CEU}"></div><div><b>Água</b><small>SNIS / SINISA</small></div></div>
 <div class=svc><div class=sq style="background:{LARANJA}"></div><div><b>Energia</b><small>ANEEL e EPE</small></div></div>
 <div class=svc><div class=sq style="background:{VERDE}"></div><div><b>Resíduos</b><small>SINISA e Prefeitura</small></div></div>
 <div class=svc><div class=sq style="background:{AZUL}"></div><div><b>Mobilidade</b><small>SPTrans e SEEG</small></div></div>
</div>
<p class=sub style="margin-top:40px">Cada um num site e num formato. O EcoCity junta tudo num <b class=az>banco MySQL</b> e dá, todo mês, uma nota de 0 a 100 para cada cidade.</p>"""),
# 3 o que fizemos
pagina(3, f"""<span class=tag>O que já fizemos</span>
<h2>Do planejamento ao <span class=vd>banco funcionando</span>.</h2>
<ul class=ck>
 <li>Requisitos do sistema priorizados</li>
 <li>DER preliminar no draw.io</li>
 <li>Dados reais de fontes oficiais, mês a mês</li>
 <li>Banco no MySQL com regras que se protegem sozinhas</li>
 <li>API com cadastro por perfil e login em 2 etapas</li>
</ul>"""),
# 4 DER
pagina(4, f"""<span class=tag>Modelo de dados</span>
<h2>O DER preliminar: <span class=az>como as informações se ligam</span>.</h2>
<div class=foto><img src="file://{DER}"></div>
<div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:18px;margin-top:26px">
 <div class=card style="padding:24px"><div style="width:90px;height:44px;border:4px solid #1D5FA8;border-radius:6px;background:#E3EDF8"></div><p style="font-size:26px;margin-top:16px"><b>Retângulo</b><br>é uma tabela</p></div>
 <div class=card style="padding:24px"><div style="width:44px;height:44px;border:4px solid #E8892B;background:#FDF0E2;transform:rotate(45deg);margin:2px 0 0 22px"></div><p style="font-size:26px;margin-top:20px"><b>Losango</b><br>é uma ligação</p></div>
 <div class=card style="padding:24px"><div style="font-size:38px;font-weight:800;color:#2F8F3F;height:44px">(1,N)</div><p style="font-size:26px;margin-top:16px"><b>Mínimo e máximo</b><br>de cada ligação</p></div>
</div>
<p class=sub style="font-size:30px">O <b>município</b> é o centro: recebe os dados de cada mês e os indicadores.</p>"""),
# 5 banco + API
pagina(5, f"""<span class=tag>Status</span>
<h2>Banco criado e <span class=vd>API no ar</span>.</h2>
<div style="display:grid;grid-template-columns:300px 1fr;gap:22px;margin-top:30px;align-items:stretch">
 <div class=foto style="margin:0;display:flex;flex-direction:column;justify-content:center"><img src="file://{TAB}"><div class=cap>Tabelas no MySQL</div></div>
 <div style="display:flex;flex-direction:column;gap:22px">
  <div class=foto style="margin:0"><img src="file://{API}"><div class=cap>API respondendo</div></div>
  <div class=grid2 style="gap:16px">
   <div class=card style="padding:22px 26px"><div class=num style="font-size:58px;color:{AZUL}">36</div><div class=lab>tabelas</div></div>
   <div class=card style="padding:22px 26px"><div class=num style="font-size:58px;color:{VERDE}">1.536</div><div class=lab>medições</div></div>
   <div class=card style="padding:22px 26px"><div class=num style="font-size:58px;color:{LARANJA}">8</div><div class=lab>cidades</div></div>
   <div class=card style="padding:22px 26px"><div class=num style="font-size:58px;color:{CEU}">24</div><div class=lab>meses de dados</div></div>
  </div>
 </div>
</div>"""),
# 6 segurança
pagina(6, f"""<span class=tag>Segurança</span>
<h2>Cada perfil com seu <span class=az>nível de acesso</span>.</h2>
<div style="margin-top:22px">
 <div class=step><span class=badge style="background:{VERDE}">Cidadão</span><p>Cadastro simples. Vê os dados da sua cidade.</p></div>
 <div class=step><span class=badge style="background:{CEU}">Analista</span><p>Cadastro completo, aprovado pelo administrador.</p></div>
 <div class=step><span class=badge style="background:{LARANJA}">Gestor</span><p>Propõe metas, que outro gestor aprova.</p></div>
 <div class=step><span class=badge style="background:{AZUL}">Admin</span><p>Chave individual + código do aplicativo.</p></div>
</div>
<div class=foto style="margin-top:28px"><img src="file://{COD}"><img src="file://{MSG}" style="margin-top:12px"></div>
<p class=cap style="text-align:left;margin-top:16px">Teste: tentamos criar um administrador direto na tabela e o próprio banco bloqueou.</p>"""),
# 7 próximos passos
pagina(7, f"""<span class=tag>Ferramentas e próximos passos</span>
<h2>O que usamos e <span class=az>o que vem a seguir</span>.</h2>
<div style="margin-top:26px">
 <span class=chip>MySQL 8</span><span class=chip>Oracle Cloud</span><span class=chip>Node.js + Express</span><span class=chip>Python</span><span class=chip>draw.io</span><span class=chip>MySQL Workbench</span>
</div>
<div class=card style="margin-top:40px">
 <p style="font-size:30px;font-weight:700;color:{AZUL}">Próximo checkpoint</p>
 <ul class=ck style="margin-top:4px"><li>DER final e modelo lógico</li><li>Normalização até a 3ª forma normal</li><li style="border:0">Telas do sistema e publicação na Oracle Cloud</li></ul>
</div>
<div style="display:flex;align-items:center;gap:30px;margin-top:40px">{icone(110)}<p class=sub style="margin:0">Tem alguma sugestão para a próxima etapa? <b class=az>Conta pra gente nos comentários!</b></p></div>"""),
]

# ---------- páginas extras pedidas pelo guia do CP2 (arquitetura e backlog)
def camada(cor, titulo, tec, itens, status=''):
    st = f'<span style="float:right;font-size:21px;font-weight:700;color:{cor};background:#fff;border:2px solid {cor};border-radius:30px;padding:6px 16px">{status}</span>' if status else ''
    return f"""<div style="background:#fff;border:2px solid #E1E8F1;border-left:14px solid {cor};border-radius:22px;padding:26px 30px">
 {st}<div style="font-size:36px;font-weight:800">{titulo}</div>
 <div style="font-size:27px;color:{cor};font-weight:700;margin-top:4px">{tec}</div>
 <div style="font-size:25px;color:#3E5675;margin-top:10px">{itens}</div></div>"""

SETA = f'<div style="text-align:center;font-size:44px;line-height:1;color:#9AAAC0;margin:6px 0">⇅</div>'

ARQ = pagina(0, f"""<span class=tag>Arquitetura</span>
<h2>Como o EcoCity <span class=az>funciona por dentro</span>.</h2>
<div style="margin-top:30px">
{camada(CEU, 'Telas do sistema', 'HTML, CSS e JavaScript', 'Cidadão, analista, gestor e administrador', 'em desenvolvimento')}
{SETA}
{camada(LARANJA, 'API (back-end)', 'Node.js + Express', 'Login em 2 etapas · cadastro por perfil · metas e análises', 'pronto')}
{SETA}
{camada(AZUL, 'Banco de dados', 'MySQL 8 · Oracle Cloud', '36 tabelas · views, triggers e procedures que protegem as regras', 'pronto')}
<div style="text-align:center;font-size:44px;line-height:1;color:#9AAAC0;margin:6px 0">↑</div>
{camada(VERDE, 'Dados reais', 'Fontes oficiais + Python', 'ANEEL, EPE, SNIS, SPTrans, SEEG e IBGE, mês a mês', 'pronto')}
</div>""")

TAREFAS = [('Requisitos priorizados', 'Gabriela'), ('Coleta dos dados reais mensais', 'Nicole'),
           ('Definição do MySQL e tecnologias', 'Gabriela'), ('DER preliminar', 'Nicole'),
           ('Criação do banco no MySQL', 'Gabriela'), ('Back-end (API)', 'Nicole'),
           ('Entrega do CP2 + LinkedIn', 'Gabriela e Nicole')]
linhas = ''.join(f"""<div style="display:flex;align-items:center;gap:22px;padding:19px 0;border-bottom:2px solid #E1E8F1">
 <div style="width:40px;height:40px;border-radius:11px;background:{VERDE};position:relative;flex:0 0 auto"><div style="position:absolute;left:13px;top:6px;width:11px;height:19px;border:solid #fff;border-width:0 5px 5px 0;transform:rotate(45deg)"></div></div>
 <div style="flex:1;font-size:31px">{a}</div><div style="font-size:24px;color:#6B7F99">{r}</div></div>""" for a, r in TAREFAS)
BACKLOG = pagina(0, f"""<span class=tag>Backlog do CP2</span>
<h2>Tudo o que planejamos <span class=vd>foi entregue</span>.</h2>
<div class=card style="margin-top:30px;padding:10px 34px">{linhas}</div>
<p class=sub style="font-size:29px;margin-top:30px"><b>Próximo passo:</b> DER final, normalização até a 3ª forma normal e as telas do sistema.</p>""")
SLIDES += [ARQ, BACKLOG]

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': 1080, 'height': 1350}, device_scale_factor=2)
    ESCOLHA = [0, 7, 3, 8]       # guia do CP2: capa, arquitetura, DER (modelo de dados) e backlog
    for k, idx in enumerate(ESCOLHA, 1):
        h = re.sub(r'<span>\d+/7</span>', f'<span>{k}/{len(ESCOLHA)}</span>', SLIDES[idx])
        f = OUT / f'curto_slide{k}.html'; f.write_text(h, encoding='utf-8')
        pg.goto(f'file://{f}'); pg.wait_for_timeout(300)
        pg.screenshot(path=str(OUT / f'EcoCity_CP2_post_final_{k}.png'))
    b.close()
print('ok')
