"""Post do CP2 no mesmo estilo visual do post do CP1 (papel quadriculado, título serifado, cartões).
Gera 2 imagens em paisagem: 1) progresso do projeto  2) DER preliminar."""
import pathlib, re
from playwright.sync_api import sync_playwright

OUT = pathlib.Path(__file__).parent
DOCS = OUT.parent
LOGO = (DOCS / 'marca/EcoCity_logo.svg').read_text()
corpo = re.search(r'<svg[^>]*>(.*)</svg>', LOGO, re.S).group(1)
LOGO_FULL = f'<svg viewBox="30 30 340 430" width="118">{corpo}</svg>'
DER = OUT / 'der_simples.png'

W, H = 1600, 860
CSS = f"""
*{{box-sizing:border-box;margin:0;padding:0}}
body{{width:{W}px;height:{H}px;font-family:Inter,sans-serif;color:#2B2B2B;overflow:hidden;
 background-color:#FBF8F6;
 background-image:linear-gradient(#ECE6E3 1px,transparent 1px),linear-gradient(90deg,#ECE6E3 1px,transparent 1px);
 background-size:32px 32px}}
.top{{position:relative;text-align:center;padding-top:34px}}
.logo{{position:absolute;left:46px;top:26px}}
h1{{font-family:Lora,serif;font-weight:500;font-size:54px;line-height:1.04;color:#111}}
.rosa{{color:#E0479E;font-weight:700;letter-spacing:.05em;font-size:21px;margin-top:16px}}
.h{{font-size:20px;font-weight:800;letter-spacing:.04em;display:flex;align-items:center;gap:10px;margin-bottom:14px}}
.card{{background:#fff;border-radius:16px;box-shadow:0 2px 10px rgba(0,0,0,.07);padding:18px 22px}}
.serif{{font-family:Lora,serif}}
ul{{list-style:none}}
li{{font-size:19px;line-height:1.35;padding:6px 0 6px 30px;position:relative}}
li:before{{content:'✔';position:absolute;left:0;color:#2F8F3F;font-weight:800}}
.chip{{display:inline-block;font-size:17px;font-weight:600;border-radius:10px;padding:9px 14px;margin:0 8px 10px 0}}
.flow{{display:flex;align-items:center;gap:14px}}
.flow .b{{font-family:Lora,serif;font-weight:700;font-size:18px;text-align:center;border-radius:10px;padding:16px 14px;flex:1;line-height:1.2}}
.flow .b small{{display:block;font-family:Inter;font-weight:600;font-size:13px;margin-top:4px}}
.flow .s{{font-size:26px;color:#333}}
"""

def pagina(corpo_html):
    return f"<!doctype html><html><head><meta charset=utf-8><style>{CSS}</style></head><body>{corpo_html}</body></html>"

TOPO = f"""<div class=top><div class=logo>{LOGO_FULL}</div>
<h1>BD para Comunidades Sustentáveis<br>(Cidades Inteligentes)</h1>
<div class=rosa>CHECKPOINT 2 · O PROJETO ECOCITY ESTÁ EVOLUINDO</div></div>"""

IMG1 = pagina(TOPO + """
<div style="display:grid;grid-template-columns:1fr 1fr;gap:34px;padding:40px 60px 0">
 <div>
  <div class=h>🏁 O QUE JÁ FOI FEITO</div>
  <div class=card style="border:2px solid #F3B5D6"><ul>
   <li>Requisitos do sistema priorizados</li>
   <li>DER preliminar (modelo de dados)</li>
   <li>Dados reais mês a mês de 8 cidades de SP</li>
   <li>Banco criado no MySQL</li>
   <li>API no ar, com cadastro por perfil e login em 2 etapas</li>
  </ul></div>
  <div class=h style="margin-top:24px">⚠️ PRINCIPAL DESAFIO</div>
  <p class=serif style="font-size:19px;line-height:1.4;color:#444">Muitas fontes só publicam dados por ano. Por isso, cada número no banco mostra se é <b>oficial</b> ou <b>estimado</b>.</p>
 </div>
 <div>
  <div class=h>🛠️ FERRAMENTAS</div>
  <div>
   <span class=chip style="background:#DDEBF7">🐬 MySQL</span><span class=chip style="background:#FDE7D2">☁️ Oracle Cloud</span><span class=chip style="background:#DFF1E1">🟢 Node.js</span><span class=chip style="background:#EEE6F7">📐 draw.io</span>
  </div>
  <div class=h style="margin-top:16px">🚀 PRÓXIMOS PASSOS</div>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
   <div class=card><div class=serif style="font-weight:700;font-size:19px">🧩 DER final</div><div class=serif style="font-size:16px;color:#555;margin-top:6px">E o modelo lógico do banco.</div></div>
   <div class=card><div class=serif style="font-weight:700;font-size:19px">📏 Normalização</div><div class=serif style="font-size:16px;color:#555;margin-top:6px">Até a 3ª forma normal.</div></div>
   <div class=card><div class=serif style="font-weight:700;font-size:19px">🖥️ Telas do sistema</div><div class=serif style="font-size:16px;color:#555;margin-top:6px">Para cada tipo de usuário.</div></div>
   <div class=card><div class=serif style="font-weight:700;font-size:19px">☁️ Publicação</div><div class=serif style="font-size:16px;color:#555;margin-top:6px">Banco na Oracle Cloud.</div></div>
  </div>
 </div>
</div>
<div style="padding:40px 60px 0">
 <div class=h>📊 ANDAMENTO DO PROJETO</div>
 <div class=flow>
  <div class=b style="background:#DFF1E1">FONTES DE DADOS<small>✔ pronto</small></div><span class=s>→</span>
  <div class=b style="background:#BBD7F0">BANCO MySQL<small>✔ pronto</small></div><span class=s>→</span>
  <div class=b style="background:#DFF1E1">API<small>✔ pronta</small></div><span class=s>→</span>
  <div class=b style="background:#FCEFD9">TELAS<small>em desenvolvimento</small></div><span class=s>→</span>
  <div class=b style="background:#EEF0F2">DECISÕES<small>próximas etapas</small></div>
 </div>
</div>""")

IMG2 = pagina(TOPO.replace('O PROJETO ECOCITY ESTÁ EVOLUINDO', 'DER PRELIMINAR · COMO AS INFORMAÇÕES SE LIGAM') + f"""
<div style="padding:26px 60px 0">
 <div class=card style="padding:16px"><img src="file://{DER}" style="width:100%;display:block;max-height:520px;object-fit:contain"></div>
 <div style="display:flex;gap:28px;justify-content:center;margin-top:20px;font-size:19px" class=serif>
  <span>▭ <b>Retângulo</b> = tabela</span><span>◇ <b>Losango</b> = ligação</span><span><b>(1,N)</b> = mínimo e máximo</span><span>🏙️ O <b>município</b> é o centro</span>
 </div>
</div>""")

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': W, 'height': H}, device_scale_factor=2)
    for i, h in enumerate([IMG1, IMG2], 1):
        f = OUT / f'cp2_estilo_cp1_{i}.html'; f.write_text(h, encoding='utf-8')
        pg.goto(f'file://{f}'); pg.wait_for_timeout(400)
        pg.screenshot(path=str(OUT / f'EcoCity_CP2_LinkedIn_{i}.png'))
    b.close()
print('ok')
