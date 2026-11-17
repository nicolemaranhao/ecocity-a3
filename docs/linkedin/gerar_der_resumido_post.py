"""Imagem 2 do post (celular): DER resumido com as 8 entidades principais, letras grandes."""
import pathlib, re, html
from playwright.sync_api import sync_playwright
base = pathlib.Path(__file__).with_name('gerar_post_cp2_moderno.py').read_text()
exec(base.split('IMG1 = pagina')[0])

BW, BH, DWW, DHH = 240, 96, 124, 62
COR = {'dados': '#E0E7FF', 'ind': '#DCFCE7', 'acao': '#FEF3C7', 'pessoas': '#F1F5F9'}
E = {'FONTE_DADOS': (150, 120, 'dados', 'id_fonte'), 'DADO': (590, 120, 'dados', 'id_dado'),
     'MUNICIPIO': (590, 370, 'dados', 'id_municipio'), 'INDICADOR_VALOR': (1030, 370, 'ind', 'id_indicador_valor'),
     'INDICADOR': (1030, 120, 'ind', 'id_indicador'), 'META': (1470, 120, 'ind', 'id_meta'),
     'ACAO': (1030, 620, 'acao', 'id_acao'), 'USUARIO': (1470, 620, 'pessoas', 'id_usuario')}
def b(e, lado):
    x, y = E[e][:2]
    return {'r': (x + BW/2, y), 'l': (x - BW/2, y), 't': (x, y - BH/2), 'b': (x, y + BH/2)}[lado]
# (A, verbo, B, cardA, cardB, pontos, centro do losango)
R = [('FONTE_DADOS', 'fornece', 'DADO', '(1,1)', '(0,N)', [b('FONTE_DADOS', 'r'), b('DADO', 'l')]),
     ('DADO', 'é de', 'MUNICIPIO', '(0,N)', '(1,1)', [b('DADO', 'b'), b('MUNICIPIO', 't')]),
     ('MUNICIPIO', 'obtém', 'INDICADOR_VALOR', '(1,1)', '(0,N)', [b('MUNICIPIO', 'r'), b('INDICADOR_VALOR', 'l')]),
     ('INDICADOR_VALOR', 'calcula', 'INDICADOR', '(0,N)', '(1,1)', [b('INDICADOR_VALOR', 't'), b('INDICADOR', 'b')]),
     ('INDICADOR', 'tem', 'META', '(1,1)', '(0,N)', [b('INDICADOR', 'r'), b('META', 'l')]),
     ('MUNICIPIO', 'recebe', 'ACAO', '(1,1)', '(0,N)', [b('MUNICIPIO', 'b'), (590, 620), b('ACAO', 'l')]),
     ('ACAO', 'cuida de', 'USUARIO', '(0,N)', '(1,1)', [b('ACAO', 'r'), b('USUARIO', 'l')]),
     ('USUARIO', 'propõe', 'META', '(1,1)', '(0,N)', [b('USUARIO', 't'), b('META', 'b')])]
s = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 30 1640 680" width="1520" font-family="Inter, Arial">']
for a, v, bb, ca, cb, pts in R:
    s.append('<polyline fill="none" stroke="#334155" stroke-width="3" points="' + ' '.join(f'{x},{y}' for x, y in pts) + '"/>')
for a, v, bb, ca, cb, pts in R:
    p, q = (pts[-2], pts[-1]) if len(pts) > 2 else (pts[0], pts[1])
    if len(pts) > 2: p, q = pts[1], pts[2]
    dx, dy = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
    w = max(DWW, 12 * len(v) + 44)
    s.append(f'<polygon points="{dx},{dy-DHH/2} {dx+w/2},{dy} {dx},{dy+DHH/2} {dx-w/2},{dy}" fill="white" stroke="#1E293B" stroke-width="2.5"/>')
    s.append(f'<text x="{dx}" y="{dy+7}" text-anchor="middle" font-size="20" font-weight="600" fill="#163E6E">{html.escape(v)}</text>')
    for card, p0, p1 in ((ca, pts[0], pts[1]), (cb, pts[-1], pts[-2])):
        ux, uy = (p1[0] > p0[0]) - (p1[0] < p0[0]), (p1[1] > p0[1]) - (p1[1] < p0[1])
        if uy == 0:
            s.append(f'<text x="{p0[0]+ux*34}" y="{p0[1]-24}" text-anchor="middle" font-size="22" font-weight="800" fill="#B45309">{card}</text>')
        else:
            s.append(f'<text x="{p0[0]+12}" y="{p0[1]+uy*30+8}" font-size="22" font-weight="800" fill="#B45309">{card}</text>')
for e, (x, y, g, i) in E.items():
    s.append(f'<rect x="{x-BW/2}" y="{y-BH/2}" width="{BW}" height="{BH}" rx="6" fill="{COR[g]}" stroke="#1E293B" stroke-width="3"/>')
    s.append(f'<text x="{x}" y="{y-6}" text-anchor="middle" font-size="{25 if len(e) < 14 else 21}" font-weight="800" fill="#0F172A">{e}</text>')
    s.append(f'<text x="{x}" y="{y+28}" text-anchor="middle" font-size="20" text-decoration="underline" fill="#334155">{i}</text>')
s.append('</svg>')
SVG = '\n'.join(s)

LEG = (f'<div style="margin-left:auto;align-self:center;display:flex;flex-direction:column;gap:8px;font-size:18px;color:#2C4462;text-align:left">'
       f'<div><b>Retângulo</b> = tabela &nbsp;·&nbsp; <b>Losango</b> = ligação</div>'
       f'<div><b style="color:#B45309">(1,N)</b> = mínimo e máximo de cada lado</div></div>')
IMG = f"""<!doctype html><html><head><meta charset=utf-8><style>{CSS}</style></head><body>
<div class=head style="padding:30px 44px 0">{ICONE.replace('width="96"', 'width="80"')}<div><h1 style="font-size:38px">Como os dados se ligam</h1>
<div class=sub style="font-size:17px">DER · AS 8 ENTIDADES PRINCIPAIS DO ECOCITY</div></div>{LEG}</div>
<div class=card style="margin:18px 40px 0;padding:14px 20px;height:640px;display:flex;align-items:center;justify-content:center">{SVG}</div>
<div style="text-align:center;margin-top:16px;font-size:18px;color:#2C4462">O DER completo tem <b>22 entidades</b> e <b>37 relacionamentos</b> e está no documento do checkpoint.</div>
</body></html>"""
with sync_playwright() as p:
    br = p.chromium.launch(); pg = br.new_page(viewport={'width': W, 'height': H}, device_scale_factor=3)
    f = OUT / 'cp2_der_resumido.html'; f.write_text(IMG, encoding='utf-8')
    pg.goto(f'file://{f}'); pg.wait_for_timeout(500); pg.screenshot(path=str(OUT / 'EcoCity_CP2_post_2.png')); br.close()
print('ok')
