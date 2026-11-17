"""Monta frontend/index.html (servido pela API) e o arquivo único de demonstração (artifact)."""
import pathlib, sys
src = pathlib.Path(__file__).parent
out = src.parent
css, body = (src / 'app.css').read_text(), (src / 'app.body.html').read_text()
js = (src / 'copiloto.js').read_text() + '\n' + (src / 'app.js').read_text()
fonts = ('<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
         '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:wght@400;700&family=Baloo+2:wght@600;700'
         '&family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=IBM+Plex+Sans:wght@400;500;600&family=JetBrains+Mono:wght@500;600&display=swap">')
title = '<title>EcoCity Painel Urbano</title><meta name="claude:viewport-fit-sides" content="cover">'
# 1) index.html do repositório (com API; sem API abre em modo demonstração com data.js)
(out / 'index.html').write_text(f'''<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
{title}{fonts}<style>{css}</style></head>
<body>{body}
<script src="data.js"></script>
<script>window.ECOCITY_API = location.protocol.startsWith('http') ? '/api' : null;</script>
<script>{js}</script></body></html>''')
# 2) arquivo único (dados embutidos) para demonstração / artifact
data = (out / 'data.js').read_text()
target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else out / 'ecocity_demo.html'
target.write_text(f'''{title}{fonts}<style>{css}</style>
{body}
<script>{data}</script>
<script>{js}</script>''')
print('ok', target)
