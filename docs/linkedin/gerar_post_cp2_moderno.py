"""Post do CP2 — visual moderno, fundo quadriculado (como no CP1), destaques no azul do projeto.
Gera 2 imagens 1600x900: 1) progresso + print do banco  2) DER preliminar."""
import pathlib, re
from playwright.sync_api import sync_playwright

OUT = pathlib.Path(__file__).parent
DOCS = OUT.parent
CP = pathlib.Path('/home/claude/ecocity/docs/checkpoint2/apresentacao')
LOGO = (DOCS / 'marca/EcoCity_logo.svg').read_text()
corpo = re.search(r'<svg[^>]*>(.*)</svg>', LOGO, re.S).group(1)
icone_corpo = re.sub(r'<text.*?</text>', '', corpo, flags=re.S)
ICONE = f'<svg viewBox="30 30 340 340" width="96">{icone_corpo}</svg>'
DER = OUT / 'der_simples.png'
TAB = CP / 'print3_lista.png'
API = DOCS / 'checkpoint2/prints/print5_api.png'

NAVY, AZUL, VERDE, LARANJA, CEU = '#163E6E', '#1D5FA8', '#2F8F3F', '#E8892B', '#4FB3E3'
W, H = 1600, 900

CSS = f"""
*{{box-sizing:border-box;margin:0;padding:0}}
body{{width:{W}px;height:{H}px;font-family:Inter,sans-serif;color:{NAVY};overflow:hidden;
 background-color:#FBF8F6;
 background-image:linear-gradient(#ECE6E3 1px,transparent 1px),linear-gradient(90deg,#ECE6E3 1px,transparent 1px);
 background-size:32px 32px}}
.head{{display:flex;align-items:center;gap:26px;padding:40px 56px 0}}
.head h1{{font-family:'Inter Display',Inter;font-weight:800;font-size:44px;line-height:1.08;letter-spacing:-.015em}}
.head .sub{{font-size:19px;font-weight:700;letter-spacing:.12em;color:{AZUL};margin-top:10px}}
.ck2{{margin-left:auto;align-self:flex-start;background:{AZUL};color:#fff;font-weight:700;font-size:17px;letter-spacing:.06em;border-radius:40px;padding:11px 22px;margin-top:14px}}
.card{{background:#fff;border-radius:20px;box-shadow:0 1px 2px rgba(22,62,110,.06),0 8px 24px rgba(22,62,110,.07);padding:24px 26px}}
.lbl{{font-size:15px;font-weight:800;letter-spacing:.12em;color:{AZUL};margin-bottom:14px;text-transform:uppercase}}
.item{{display:flex;align-items:flex-start;gap:14px;font-size:19px;line-height:1.35;padding:9px 0}}
.ok{{flex:0 0 auto;width:26px;height:26px;border-radius:8px;background:{VERDE};position:relative;margin-top:1px}}
.ok:after{{content:'';position:absolute;left:9px;top:4px;width:6px;height:12px;border:solid #fff;border-width:0 3px 3px 0;transform:rotate(45deg)}}
.pill{{display:inline-flex;align-items:center;gap:9px;font-size:16px;font-weight:600;background:#F3F6FA;border-radius:30px;padding:8px 15px;margin:0 7px 9px 0}}
.pill i{{width:10px;height:10px;border-radius:50%}}
.win{{background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 1px 2px rgba(22,62,110,.06),0 8px 24px rgba(22,62,110,.08)}}
.bar{{display:flex;align-items:center;gap:7px;padding:10px 14px;background:#F1F4F8;font-size:13px;font-weight:600;color:#6B7F99}}
.bar i{{width:10px;height:10px;border-radius:50%;background:#D5DCE5}}
.stat b{{display:block;font-family:'Inter Display';font-size:40px;font-weight:800;line-height:1}}
.stat span{{font-size:15px;color:#5B6F8A}}
.step{{flex:1;display:flex;flex-direction:column;align-items:center;text-align:center;position:relative}}
.dot{{width:40px;height:40px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-weight:800;font-size:17px;position:relative;z-index:2}}
.step b{{font-size:17px;margin-top:10px}}
.step small{{font-size:14px;color:#5B6F8A;margin-top:2px}}
"""

def pagina(sub, corpo_html):
    return f"""<!doctype html><html><head><meta charset=utf-8><style>{CSS}</style></head><body>
<div class=head>{ICONE}<div><h1>BD para Comunidades Sustentáveis<br>(Cidades Inteligentes)</h1><div class=sub>{sub}</div></div>
<div class=ck2>CHECKPOINT 2</div></div>{corpo_html}</body></html>"""

def ok(t):
    return f'<div class=item><span class=ok></span><span>{t}</span></div>'

def stat(v, rot, cor):
    return f'<div class=stat><b style="color:{cor}">{v}</b><span>{rot}</span></div>'

def passo(n, nome, st, cor, feito=True):
    dot = f'<div class=dot style="background:{cor}">{"✓" if feito else n}</div>' if feito else \
          f'<div class=dot style="background:#fff;border:3px solid {cor};color:{cor}">{n}</div>'
    return f'<div class=step>{dot}<b>{nome}</b><small>{st}</small></div>'

IMG1 = pagina('ECOCITY · O PROJETO ESTÁ EVOLUINDO', f"""
<div style="display:grid;grid-template-columns:500px 1fr 420px;gap:24px;padding:28px 56px 0;grid-template-rows:520px">
 <div style="display:flex;flex-direction:column;gap:20px">
  <div class=card style="flex:1">
   <div class=lbl>O que já foi feito</div>
   {ok('Requisitos do sistema priorizados')}
   {ok('DER preliminar (modelo de dados)')}
   {ok('Dados reais mês a mês de 8 cidades de SP')}
   {ok('Banco de dados criado no MySQL')}
   {ok('API no ar, com login em 2 etapas')}
  </div>
  <div class=card style="border-left:6px solid {AZUL}">
   <div class=lbl>Principal desafio</div>
   <p style="font-size:18px;line-height:1.45;color:#2C4462">Muitas fontes só publicam dados por ano. Por isso, cada número no banco mostra se é <b>oficial</b> ou <b>estimado</b>.</p>
  </div>
 </div>
 <div class=card style="display:flex;flex-direction:column;padding:22px">
  <div class=lbl>Banco funcionando</div>
  <div style="display:flex;gap:18px;height:262px">
   <div class=win style="flex:0 0 190px;display:flex;flex-direction:column"><div class=bar><i></i><i></i><i></i>MySQL</div>
    <img src="file://{TAB}" style="width:100%;flex:1;object-fit:cover;object-position:top;display:block;min-height:0"></div>
   <div style="display:flex;flex-direction:column;justify-content:space-between;padding:4px 0">
    {stat('36', 'tabelas', AZUL)}{stat('24', 'procedures', LARANJA)}{stat('1.536', 'medições', VERDE)}
   </div>
  </div>
  <div class=win style="margin-top:16px"><div class=bar><i></i><i></i><i></i>API no ar · localhost:3000/api/health</div>
   <img src="file://{API}" style="width:100%;height:118px;object-fit:cover;object-position:top;display:block"></div>
 </div>
 <div style="display:flex;flex-direction:column;gap:20px">
  <div class=card>
   <div class=lbl>Ferramentas</div>
   <span class=pill><i style="background:{AZUL}"></i>MySQL</span><span class=pill><i style="background:{LARANJA}"></i>Oracle Cloud</span>
   <span class=pill><i style="background:{VERDE}"></i>Node.js + Express</span><span class=pill><i style="background:{CEU}"></i>draw.io</span>
  </div>
  <div class=card style="flex:1">
   <div class=lbl>Próximos passos</div>
   <div class=item><b style="color:{AZUL};width:26px">1</b><span><b>DER final</b> e modelo lógico</span></div>
   <div class=item><b style="color:{AZUL};width:26px">2</b><span><b>Normalização</b> até a 3ª forma normal</span></div>
   <div class=item><b style="color:{AZUL};width:26px">3</b><span><b>Telas</b> para cada tipo de usuário</span></div>
   <div class=item><b style="color:{AZUL};width:26px">4</b><span><b>Publicação</b> na Oracle Cloud</span></div>
  </div>
 </div>
</div>
<div class=card style="margin:24px 56px 0;padding:20px 30px 18px;position:relative">
 <div style="position:absolute;left:12%;right:12%;top:39px;height:4px;background:linear-gradient(90deg,{VERDE} 0 62%,#D9E1EA 62% 100%);border-radius:2px"></div>
 <div style="display:flex">
  {passo(1, 'Fontes de dados', 'pronto', VERDE)}{passo(2, 'Banco MySQL', 'pronto', VERDE)}{passo(3, 'API', 'pronta', VERDE)}
  {passo(4, 'Telas', 'em desenvolvimento', LARANJA, False)}{passo(5, 'Decisões', 'próximas etapas', '#9AAAC0', False)}
 </div>
</div>""")

IMG2 = pagina('DER PRELIMINAR · COMO AS INFORMAÇÕES SE LIGAM', f"""
<div class=card style="margin:30px 56px 0;padding:18px"><img src="file://{DER}" style="width:100%;height:560px;object-fit:contain;display:block"></div>
<div style="display:flex;gap:16px;justify-content:center;margin-top:22px">
 <span class=pill style="background:#fff;font-size:17px"><span style="width:26px;height:15px;border:3px solid {AZUL};border-radius:3px"></span><span><b>Retângulo</b> = tabela</span></span>
 <span class=pill style="background:#fff;font-size:17px"><span style="width:15px;height:15px;border:3px solid {LARANJA};transform:rotate(45deg)"></span><span><b>Losango</b> = ligação</span></span>
 <span class=pill style="background:#fff;font-size:17px"><span><b style="color:{VERDE}">(1,N)</b> = mínimo e máximo</span></span>
 <span class=pill style="background:#fff;font-size:17px"><span>O <b>município</b> é o centro do modelo</span></span>
</div>""")

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': W, 'height': H}, device_scale_factor=2)
    for i, h in enumerate([IMG1, IMG2], 1):
        f = OUT / f'cp2_moderno_{i}.html'; f.write_text(h, encoding='utf-8')
        pg.goto(f'file://{f}'); pg.wait_for_timeout(400)
        pg.screenshot(path=str(OUT / f'EcoCity_CP2_LinkedIn_{i}.png'))
    b.close()
print('ok')
