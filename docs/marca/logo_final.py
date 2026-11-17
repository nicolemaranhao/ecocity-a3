import math
W = "#FFFFFF"
VERDE, AZUL, AMBAR, ROXO = "#2E8B3E", "#1E6FC2", "#F2A21B", "#7B3FA0"
sw = 11
def rays(cx, cy, r1, r2, n=8):
    out = []
    for k in range(n):
        a = math.pi * 2 * k / n + math.pi / 8
        out.append(f'<line x1="{cx+r1*math.cos(a):.1f}" y1="{cy+r1*math.sin(a):.1f}" x2="{cx+r2*math.cos(a):.1f}" y2="{cy+r2*math.sin(a):.1f}"/>')
    return ''.join(out)

ICONE = f'''
<rect x="20" y="20" width="170" height="170" rx="26" fill="{VERDE}"/>
<rect x="206" y="20" width="170" height="170" rx="26" fill="{AZUL}"/>
<rect x="20" y="206" width="170" height="170" rx="26" fill="{AMBAR}"/>
<rect x="206" y="206" width="170" height="170" rx="26" fill="{ROXO}"/>
<g fill="none" stroke="{W}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
  <!-- resíduos / natureza: folha -->
  <path d="M52 160 C46 98 92 52 162 50 C164 118 120 164 52 160Z"/>
  <path d="M56 156 C88 124 110 102 134 78"/>
  <!-- água: gota com onda -->
  <path d="M291 48 C291 48 247 100 247 128 A44 44 0 0 0 335 128 C335 100 291 48 291 48Z"/>
  <path d="M268 132 Q276 150 296 152"/>
  <!-- energia: sol -->
  <circle cx="105" cy="291" r="28"/>
  {rays(105, 291, 46, 64)}
  <!-- mobilidade / cidade: prédios -->
  <path d="M228 346 H354"/>
  <path d="M240 346 V292 H266 V346"/>
  <path d="M266 346 V252 H300 V346"/>
  <path d="M300 346 V306 H330 V346"/>
</g>
<g fill="{W}"><rect x="276" y="270" width="14" height="14" rx="3"/><rect x="276" y="296" width="14" height="14" rx="3"/><rect x="276" y="322" width="14" height="14" rx="3"/></g>
'''
icone = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 396 396" width="396" height="396">{ICONE}</svg>'
vertical = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 396 500" width="396" height="500">{ICONE}
<text x="198" y="468" text-anchor="middle" font-family="Inter" font-weight="800" font-size="70" letter-spacing="-1"><tspan fill="#1F2937">Eco</tspan><tspan fill="{VERDE}">City</tspan></text></svg>'''
horizontal = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1060 396" width="1060" height="396"><g>{ICONE}</g>
<text x="430" y="232" font-family="Inter" font-weight="800" font-size="150" letter-spacing="-3"><tspan fill="#1F2937">Eco</tspan><tspan fill="{VERDE}">City</tspan></text>
<text x="436" y="300" font-family="Inter" font-weight="500" font-size="34" fill="#6B7280">dados para cidades sustentáveis</text></svg>'''
for n, s in (('icone', icone), ('vertical', vertical), ('horizontal', horizontal)):
    open(f'ecocity_logo_{n}.svg', 'w').write(s)
