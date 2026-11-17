"""Imagem 2 do post: como o EcoCity funciona (arquitetura), letras grandes para o celular."""
import pathlib
from playwright.sync_api import sync_playwright
base = pathlib.Path(__file__).with_name('gerar_post_cp2_moderno.py').read_text()
exec(base.split('IMG1 = pagina')[0])

def ico(tipo, cor):
    s = {'doc': f'<rect x="14" y="8" width="36" height="48" rx="5" fill="none" stroke="{cor}" stroke-width="5"/><path d="M22 22h20M22 32h20M22 42h12" stroke="{cor}" stroke-width="5" stroke-linecap="round"/>',
         'db': f'<ellipse cx="32" cy="16" rx="20" ry="8" fill="none" stroke="{cor}" stroke-width="5"/><path d="M12 16v32c0 4.4 9 8 20 8s20-3.6 20-8V16M12 32c0 4.4 9 8 20 8s20-3.6 20-8" fill="none" stroke="{cor}" stroke-width="5"/>',
         'api': f'<rect x="10" y="12" width="44" height="16" rx="4" fill="none" stroke="{cor}" stroke-width="5"/><rect x="10" y="36" width="44" height="16" rx="4" fill="none" stroke="{cor}" stroke-width="5"/><circle cx="20" cy="20" r="3" fill="{cor}"/><circle cx="20" cy="44" r="3" fill="{cor}"/>',
         'tela': f'<rect x="8" y="10" width="48" height="34" rx="5" fill="none" stroke="{cor}" stroke-width="5"/><path d="M24 54h16M32 44v10" stroke="{cor}" stroke-width="5" stroke-linecap="round"/>'}[tipo]
    return f'<svg viewBox="0 0 64 64" width="54" height="54">{s}</svg>'

def etapa(n, tipo, cor, titulo, tec, linhas, status, ok=True):
    st = (f'<span style="background:#E6F3E8;color:{VERDE}">✓ pronto</span>' if ok else
          f'<span style="background:#EEF2F7;color:#5B6F8A">próxima etapa</span>')
    li = ''.join(f'<div style="font-size:21px;line-height:1.35;color:#2C4462;margin-top:8px">{l}</div>' for l in linhas)
    return f"""<div class=card style="flex:1;padding:24px 22px;border-top:8px solid {cor};display:flex;flex-direction:column">
 <div style="display:flex;align-items:center;justify-content:space-between"><div style="background:{cor}1A;border-radius:16px;padding:8px">{ico(tipo, cor)}</div>
 <div style="font-size:15px;font-weight:800">{st.replace('<span ', '<span style="border-radius:20px;padding:5px 12px;" ', 1) if False else st}</div></div>
 <div style="font-size:15px;font-weight:800;color:{cor};letter-spacing:.1em;margin-top:16px">ETAPA {n}</div>
 <div style="font-family:'Inter Display';font-size:30px;font-weight:800;margin-top:4px;line-height:1.1">{titulo}</div>
 <div style="font-size:19px;font-weight:700;color:{cor};margin-top:6px;line-height:1.3">{tec}</div>
 <div style="margin-top:10px">{li}</div></div>"""

SETA = f'<div style="align-self:center;font-size:40px;color:#9AAAC0;font-weight:300;margin:0 -4px">→</div>'
def perfil(nome, cor, txt):
    return f'<div style="flex:1;display:flex;align-items:center;gap:14px"><span style="background:{cor};color:#fff;font-weight:800;font-size:17px;border-radius:12px;padding:8px 14px">{nome}</span><span style="font-size:19px;color:#2C4462;line-height:1.3">{txt}</span></div>'

IMG = f"""<!doctype html><html><head><meta charset=utf-8><style>{CSS}
.card span{{border-radius:20px;padding:6px 12px}}</style></head><body>
<div class=head style="padding:34px 56px 0">{ICONE.replace('width="96"', 'width="84"')}<div><h1 style="font-size:42px">Como o EcoCity funciona</h1>
<div class=sub style="font-size:18px">ARQUITETURA DO SISTEMA · DO DADO OFICIAL ATÉ A DECISÃO</div></div><div class=ck2>CHECKPOINT 2</div></div>
<div style="display:flex;gap:14px;padding:26px 56px 0;height:420px">
 {etapa(1, 'doc', VERDE, 'Dados oficiais', 'ANEEL · EPE · SNIS · SPTrans · SEEG · IBGE', ['Água, energia, lixo e transporte', '8 cidades de SP, mês a mês'], '')}
 {SETA}
 {etapa(2, 'db', AZUL, 'Banco de dados', 'MySQL 8 · Oracle Cloud', ['36 tabelas e 1.536 medições', 'Regras que protegem os dados', 'Nota de 0 a 100 por cidade'], '')}
 {SETA}
 {etapa(3, 'api', LARANJA, 'Back-end (API)', 'Node.js + Express', ['A ponte entre as telas e o banco', 'Login em 2 etapas', 'Cadastro por perfil'], '')}
 {SETA}
 {etapa(4, 'tela', CEU, 'Telas do sistema', 'HTML · CSS · JavaScript', ['Painel de cada cidade', 'Metas, ações e análises'], '', ok=False)}
</div>
<div class=card style="margin:20px 56px 0;padding:20px 28px">
 <div class=lbl style="margin-bottom:14px">Quem usa o sistema</div>
 <div style="display:flex;gap:24px">
  {perfil('Cidadão', VERDE, 'vê a nota da sua cidade')}
  {perfil('Analista', CEU, 'publica análises')}
  {perfil('Gestor', LARANJA, 'define metas e ações')}
  {perfil('Admin', AZUL, 'aprova os cadastros')}
 </div>
</div>
<div style="display:flex;gap:18px;margin:20px 56px 0">
 <div class=card style="flex:1;padding:18px 24px;display:flex;align-items:baseline;gap:12px"><b style="font-family:'Inter Display';font-size:46px;color:{AZUL}">8</b><span style="font-size:20px">cidades de SP</span></div>
 <div class=card style="flex:1;padding:18px 24px;display:flex;align-items:baseline;gap:12px"><b style="font-family:'Inter Display';font-size:46px;color:{CEU}">24</b><span style="font-size:20px">meses de dados</span></div>
 <div class=card style="flex:1;padding:18px 24px;display:flex;align-items:baseline;gap:12px"><b style="font-family:'Inter Display';font-size:46px;color:{VERDE}">1.536</b><span style="font-size:20px">medições</span></div>
 <div class=card style="flex:1;padding:18px 24px;display:flex;align-items:baseline;gap:12px"><b style="font-family:'Inter Display';font-size:46px;color:{LARANJA}">4</b><span style="font-size:20px">perfis de acesso</span></div>
</div>
</body></html>"""
with sync_playwright() as p:
    br = p.chromium.launch(); pg = br.new_page(viewport={'width': W, 'height': H}, device_scale_factor=3)
    f = OUT / 'cp2_arquitetura.html'; f.write_text(IMG, encoding='utf-8')
    pg.goto(f'file://{f}'); pg.wait_for_timeout(500); pg.screenshot(path=str(OUT / 'EcoCity_CP2_post_2.png')); br.close()
print('ok')
