"""Gera 7 imagens (1080x1350, formato carrossel do LinkedIn) para o post do Checkpoint 2."""
import pathlib
OUT = pathlib.Path(__file__).parent
DER = (OUT.parent / 'checkpoint2/prints/print1_der.png').resolve()
PLAN = (OUT.parent / 'checkpoint2/prints/print2_planilha.png').resolve()

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{width:1080px;height:1350px;font-family:Inter,sans-serif;background:#0E2A27;color:#F1F5F2;position:relative;overflow:hidden}
.pad{padding:70px 76px 150px;height:1350px;display:flex;flex-direction:column;justify-content:center}
.pad>*{flex:0 0 auto}
.tag{align-self:flex-start}
.tag{display:inline-block;font-size:24px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:#9BE7B5;border:2px solid #2F6B5C;border-radius:40px;padding:10px 24px}
h1{font-family:'Inter Display',Inter;font-weight:800;font-size:92px;line-height:1.02;letter-spacing:-.02em;margin-top:40px}
h2{font-family:'Inter Display',Inter;font-weight:800;font-size:66px;line-height:1.06;letter-spacing:-.015em;margin-top:34px}
.sub{font-size:34px;line-height:1.4;color:#C9DCD5;margin-top:28px}
.acc{color:#9BE7B5}
.foot{position:absolute;left:76px;right:76px;bottom:56px;display:flex;justify-content:space-between;font-size:22px;color:#8DB3A8;border-top:2px solid #24514A;padding-top:22px}
.card{background:#163B36;border:2px solid #24514A;border-radius:28px;padding:34px 38px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:24px}
.num{font-family:'Inter Display';font-weight:800;font-size:76px;color:#9BE7B5;line-height:1}
.lab{font-size:26px;color:#C9DCD5;margin-top:10px}
ul.ck{list-style:none;margin-top:30px}
ul.ck li{font-size:32px;line-height:1.35;padding:20px 0 20px 64px;position:relative;border-bottom:2px solid #1E4842}
ul.ck li:before{content:'';position:absolute;left:0;top:24px;width:40px;height:40px;border-radius:50%;background:#9BE7B5}
ul.ck li:after{content:'';position:absolute;left:13px;top:33px;width:12px;height:19px;border:solid #0E2A27;border-width:0 5px 5px 0;transform:rotate(45deg)}
.white{background:#fff;border-radius:22px;padding:14px;margin-top:34px}
.white img{width:100%;display:block;border-radius:10px}
.chip{display:inline-block;font-size:24px;font-weight:600;border-radius:12px;padding:10px 18px;margin:8px 10px 0 0;color:#0E2A27}
.svc{display:flex;align-items:center;gap:26px;font-size:34px;padding:24px 0;border-bottom:2px solid #1E4842}
.dot{width:66px;height:66px;border-radius:18px;display:flex;align-items:center;justify-content:center;font-size:36px}
.flow{display:flex;flex-direction:column;gap:20px;margin-top:36px}
.step{display:flex;gap:26px;align-items:flex-start}
.badge{flex:0 0 auto;font-size:22px;font-weight:700;padding:10px 16px;border-radius:12px;background:#9BE7B5;color:#0E2A27;min-width:150px;text-align:center}
.step p{font-size:29px;line-height:1.38;color:#E2EEE9}
"""

def pagina(n, corpo):
    return f"""<!doctype html><html><head><meta charset=utf-8><style>{CSS}</style></head><body>
<div class=pad>{corpo}</div>
<div class=foot><span>EcoCity · A3 Banco de Dados · Anhembi Morumbi</span><span>{n}/7</span></div></body></html>"""

SLIDES = [
# 1 capa
pagina(1, """<span class=tag>2º checkpoint · A3</span>
<h1>O banco de dados do <span class=acc>EcoCity</span> saiu do papel.</h1>
<p class=sub>Água, energia, lixo e transporte de 8 cidades de São Paulo, mês a mês, num só banco — com indicadores de sustentabilidade para gestores e cidadãos.</p>
<div class=grid2 style="margin-top:56px">
 <div class=card><div class=num>8</div><div class=lab>cidades de SP</div></div>
 <div class=card><div class=num>24</div><div class=lab>meses de dados (out/24 a set/26)</div></div>
 <div class=card><div class=num>1.536</div><div class=lab>medições mensais</div></div>
 <div class=card><div class=num>4</div><div class=lab>serviços públicos integrados</div></div>
</div>
<p class=sub style="font-size:28px;margin-top:44px">Gabriela Sant’Ana Merces Assis · Nicole Maranhão Assis</p>"""),
# 2 problema
pagina(2, """<span class=tag>O problema</span>
<h2>Os dados da cidade existem. <span class=acc>Só não conversam entre si.</span></h2>
<div style="margin-top:40px">
 <div class=svc><div class=dot style="background:#7DD3FC">💧</div><div><b>Água</b> — SNIS/SINISA</div></div>
 <div class=svc><div class=dot style="background:#FCD34D">⚡</div><div><b>Energia</b> — ANEEL e EPE</div></div>
 <div class=svc><div class=dot style="background:#86EFAC">♻️</div><div><b>Resíduos</b> — SINISA e Prefeitura</div></div>
 <div class=svc><div class=dot style="background:#D8B4FE">🚌</div><div><b>Mobilidade</b> — SPTrans e SEEG</div></div>
</div>
<p class=sub style="margin-top:44px">Cada um num site, num formato e num ritmo diferente. O EcoCity junta tudo em <span class=acc><b>um banco MySQL</b></span> e calcula todo mês um índice de 0 a 100 por cidade.</p>"""),
# 3 o que fizemos
pagina(3, """<span class=tag>O que já fizemos</span>
<h2>Do planejamento ao <span class=acc>banco funcionando</span>.</h2>
<ul class=ck>
 <li>Requisitos funcionais e não funcionais priorizados</li>
 <li>DER preliminar (modelo conceitual) no draw.io</li>
 <li>Dados reais de fontes oficiais, mês a mês</li>
 <li>Banco no MySQL com regras, views, triggers e procedures</li>
 <li>API com cadastro por perfil e login em duas etapas</li>
</ul>"""),
# 4 DER
pagina(4, f"""<span class=tag>Modelo de dados</span>
<h2>O DER preliminar: <span class=acc>19 entidades</span> e como se ligam.</h2>
<div class=white><img src="file://{DER}"></div>
<p class=sub style="font-size:28px">Notação de Chen com cardinalidade (mín,máx). Ex.: cada fonte é publicada por <b>1</b> órgão; cada órgão publica de <b>0 a N</b> fontes.</p>"""),
# 5 dados reais
pagina(5, f"""<span class=tag>Desafio nº 1</span>
<h2>Queríamos dados <span class=acc>mês a mês</span>. Muitas fontes só publicam por ano.</h2>
<div class=white><img src="file://{PLAN}"></div>
<p class=sub style="font-size:29px">Solução: cada número no banco diz de onde veio.</p>
<div><span class=chip style="background:#C6EFCE">Oficial do mês</span><span class=chip style="background:#DDEBF7">Calculado de total oficial</span><span class=chip style="background:#FCE4D6">Estimado pela equipe</span></div>"""),
# 6 confiança
pagina(6, """<span class=tag>Desafio nº 2</span>
<h2>Quem pode <span class=acc>publicar e decidir</span>?</h2>
<div class=flow>
 <div class=step><span class=badge>Cidadão</span><p>Cadastro simples (nome, e-mail, cidade). Vê o painel da sua cidade.</p></div>
 <div class=step><span class=badge>Analista</span><p>Cadastro completo com vínculo comprovado, aprovado pelo administrador. Análises passam por revisão antes de publicar.</p></div>
 <div class=step><span class=badge>Gestor</span><p>Propõe metas; um analista dá parecer e <b>outro</b> gestor aprova.</p></div>
 <div class=step><span class=badge>Admin</span><p>Não se cadastra pelo site: chave individual + código do aplicativo.</p></div>
</div>
<p class=sub style="font-size:28px;margin-top:36px">E quem garante as regras é o <span class=acc><b>próprio banco</b></span>: triggers e procedures bloqueiam o que não pode.</p>"""),
# 7 tecnologias e próximos passos
pagina(7, """<span class=tag>Ferramentas e próximos passos</span>
<h2>O que usamos e <span class=acc>o que vem a seguir</span>.</h2>
<div style="margin-top:34px">
 <span class=chip style="background:#9BE7B5">MySQL 8</span><span class=chip style="background:#9BE7B5">Oracle Cloud</span><span class=chip style="background:#9BE7B5">Node.js</span><span class=chip style="background:#9BE7B5">Python</span><span class=chip style="background:#9BE7B5">draw.io</span><span class=chip style="background:#9BE7B5">MySQL Workbench</span>
</div>
<div class=card style="margin-top:44px">
 <p style="font-size:30px;font-weight:700;color:#9BE7B5">Próximo checkpoint</p>
 <ul class=ck style="margin-top:6px"><li>DER final e modelo lógico</li><li>Normalização até a 3ª Forma Normal</li><li>Telas do sistema e publicação na Oracle Cloud</li></ul>
</div>
<p class=sub style="margin-top:40px">Tem alguma sugestão para a próxima etapa? <span class=acc><b>Conta pra gente nos comentários!</b></span></p>"""),
]
for i, h in enumerate(SLIDES, 1):
    (OUT / f'slide{i}.html').write_text(h, encoding='utf-8')
print('ok')
