"""Post do CP2 (versão final): 2 imagens em alta resolução (4800x2700) resumindo o projeto.
1) jornada do projeto + o que foi feito + desafio + ferramentas + próximos passos
2) DER completo (vetorial, nítido no zoom)"""
import pathlib, re
from playwright.sync_api import sync_playwright

base = pathlib.Path(__file__).with_name('gerar_post_cp2_moderno.py').read_text()
exec(base.split('IMG1 = pagina')[0])          # reaproveita cores, CSS, logo e funções do post anterior
DERSVG = DOCS / 'der/EcoCity_DER_completo_simples.svg'

CSS2 = f"""
.tag{{display:inline-block;font-size:13px;font-weight:700;border-radius:20px;padding:3px 10px;margin-left:8px;white-space:nowrap}}
.g{{background:#E3EDF8;color:{AZUL}}} .n{{background:#E6F3E8;color:{VERDE}}}
.row{{display:flex;align-items:center;justify-content:space-between;font-size:19px;padding:13px 0;border-bottom:1px solid #EEF2F7}}
.row:last-child{{border-bottom:0}}
.chip{{display:inline-flex;align-items:center;gap:8px;font-size:15px;font-weight:600;padding:6px 12px;border-radius:10px;background:#F3F6FA;margin:0 6px 8px 0}}
.chip i{{width:14px;height:14px;border-radius:4px}}
.num b{{display:block;font-family:'Inter Display';font-weight:800;font-size:30px;line-height:1}}
.num span{{font-size:13px;color:#5B6F8A}}
.tl{{display:flex;position:relative}}
.tl .p{{flex:1;text-align:center;position:relative;padding-top:52px}}
.tl .p .c{{position:absolute;left:50%;top:0;transform:translateX(-50%);width:42px;height:42px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-weight:800;color:#fff;font-size:17px;z-index:2}}
.tl .p b{{font-size:17px;display:block}}
.tl .p small{{display:block;font-size:14px;color:#5B6F8A;margin-top:3px;line-height:1.3}}
.aqui{{position:absolute;left:50%;top:-30px;transform:translateX(-50%);font-size:12px;font-weight:800;letter-spacing:.08em;color:#fff;background:{AZUL};padding:3px 9px;border-radius:12px;white-space:nowrap}}
"""

def feito(t, quem):
    cls = 'n' if quem == 'Nicole' else 'g'
    return f'<div class=row><span style="display:flex;align-items:center;gap:12px"><span class=ok></span>{t}</span><span class="tag {cls}">{quem}</span></div>'

IMG1 = pagina('ECOCITY · O PROJETO ESTÁ EVOLUINDO', f"""<style>{CSS2}</style>
<div style="display:grid;grid-template-columns:450px 1fr 400px;gap:22px;padding:26px 56px 0;grid-template-rows:500px">
 <div style="display:flex;flex-direction:column;gap:18px">
  <div class=card style="flex:1">
   <div class=lbl>O desafio</div>
   <p style="font-size:17px;line-height:1.4;color:#2C4462">Os dados das cidades ficam espalhados, cada um num site e num formato.</p>
   <div style="margin-top:10px"><span class=chip><i style="background:{CEU}"></i>Água</span><span class=chip><i style="background:{LARANJA}"></i>Energia</span><span class=chip><i style="background:{VERDE}"></i>Resíduos</span><span class=chip><i style="background:{AZUL}"></i>Mobilidade</span></div>
   <div class=lbl style="margin-top:8px;margin-bottom:10px">Nossa solução</div>
   <p style="font-size:17px;line-height:1.4;color:#2C4462">Um banco de dados que junta tudo, <b>mês a mês</b>, e dá uma <b>nota de 0 a 100</b> para cada cidade.</p>
  </div>
  <div class=card style="border-left:6px solid {LARANJA};padding:20px 24px">
   <div class=lbl style="color:{LARANJA}">Principal desafio</div>
   <p style="font-size:17px;line-height:1.45;color:#2C4462">Muitas fontes só publicam dados por ano. Por isso, cada número mostra se é <b>oficial</b> ou <b>estimado</b>.</p>
  </div>
 </div>
 <div class=card style="display:flex;flex-direction:column">
  <div class=lbl>O que já foi feito</div>
  {feito('Requisitos priorizados', 'Gabriela')}
  {feito('Dados reais de 8 cidades de SP', 'Nicole')}
  {feito('Escolha do MySQL e das tecnologias', 'Gabriela')}
  {feito('DER completo no draw.io', 'Nicole')}
  {feito('Banco de dados criado no MySQL', 'Gabriela')}
  {feito('Back-end (API) com login em 2 etapas', 'Nicole')}
  <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-top:auto;padding-top:14px;border-top:2px solid #EEF2F7">
   <div class=num><b style="color:{AZUL}">8</b><span>cidades</span></div>
   <div class=num><b style="color:{CEU}">24</b><span>meses</span></div>
   <div class=num><b style="color:{VERDE}">1.536</b><span>medições</span></div>
   <div class=num><b style="color:{LARANJA}">22</b><span>entidades</span></div>
  </div>
 </div>
 <div style="display:flex;flex-direction:column;gap:18px">
  <div class=card>
   <div class=lbl>Ferramentas</div>
   <span class=pill><i style="background:{AZUL}"></i>MySQL</span><span class=pill><i style="background:{LARANJA}"></i>Oracle Cloud</span>
   <span class=pill><i style="background:{VERDE}"></i>Node.js + Express</span><span class=pill><i style="background:{CEU}"></i>draw.io</span>
   <span class=pill><i style="background:#8B5CF6"></i>Python</span>
  </div>
  <div class=card style="flex:1">
   <div class=lbl>Próximos passos</div>
   <div class=item><b style="color:{AZUL};width:22px">1</b><span><b>Modelo lógico</b> do banco</span></div>
   <div class=item><b style="color:{AZUL};width:22px">2</b><span><b>Normalização</b> até a 3ª forma normal</span></div>
   <div class=item><b style="color:{AZUL};width:22px">3</b><span><b>Telas</b> para cada tipo de usuário</span></div>
  </div>
 </div>
</div>
<div class=card style="margin:22px 56px 0;padding:34px 30px 16px;position:relative">
 <div style="position:absolute;left:14.5%;right:14.5%;top:55px;height:4px;border-radius:2px;background:linear-gradient(90deg,{VERDE} 0 34%,#D9E1EA 34% 100%)"></div>
 <div class=tl>
  <div class=p><div class=c style="background:{VERDE};top:0">✓</div><b>Checkpoint 1 · 01/09</b><small>tema, problema e entidades</small></div>
  <div class=p><div class=aqui>ESTAMOS AQUI</div><div class=c style="background:{VERDE}">✓</div><b>Checkpoint 2 · 20/10</b><small>requisitos, DER, banco e API</small></div>
  <div class=p><div class=c style="background:#fff;border:3px solid {AZUL};color:{AZUL}">3</div><b>Checkpoint 3 · 24/11</b><small>modelo lógico e telas</small></div>
  <div class=p><div class=c style="background:#fff;border:3px solid #9AAAC0;color:#9AAAC0">4</div><b>Entrega final · 30/11</b><small>sistema completo e apresentação</small></div>
 </div>
</div>""")

LEG = (f'<div style="margin-left:auto;align-self:center;display:flex;flex-direction:column;gap:7px;font-size:14px;color:#2C4462">'
       f'<div><span style="display:inline-block;width:22px;height:13px;border:2.5px solid {AZUL};border-radius:2px;vertical-align:-2px"></span>&nbsp; <b>Retângulo</b> = entidade (tabela) e seus atributos</div>'
       f'<div><span style="display:inline-block;width:13px;height:13px;border:2.5px solid {LARANJA};transform:rotate(45deg);margin:0 5px 0 4px;vertical-align:-2px"></span>&nbsp; <b>Losango</b> = relacionamento &nbsp;·&nbsp; <span style="background:#FDE68A;padding:0 5px">amarelo</span> = N:N</div>'
       f'<div><b style="color:#B45309">(1,N)</b> = mínimo e máximo &nbsp;·&nbsp; <u>sublinhado</u> = identificador</div></div>')
IMG2 = f"""<!doctype html><html><head><meta charset=utf-8><style>{CSS}</style></head><body>
<div class=head style="padding:26px 40px 0">{ICONE.replace('width="96"', 'width="72"')}<div><h1 style="font-size:34px">EcoCity · DER completo</h1>
<div class=sub style="font-size:16px">MODELO CONCEITUAL · 22 ENTIDADES · 37 RELACIONAMENTOS · CHECKPOINT 2</div></div>{LEG}</div>
<div class=card style="margin:16px 40px 0;padding:10px;height:760px;display:flex;align-items:center;justify-content:center">
<img src="file://{DERSVG}" style="max-width:100%;max-height:100%;display:block"></div></body></html>"""

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': W, 'height': H}, device_scale_factor=3)
    for i, h in enumerate([IMG1], 1):   # a imagem 2 agora é gerada por gerar_arquitetura_post.py
        f = OUT / f'cp2_final_{i}.html'; f.write_text(h, encoding='utf-8')
        pg.goto(f'file://{f}'); pg.wait_for_timeout(600)
        pg.screenshot(path=str(OUT / f'EcoCity_CP2_post_{i}.png'))
    b.close()
print('ok')
