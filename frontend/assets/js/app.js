/* EcoCity — rotas da página (#/...) e proteção: a área #/app só abre para quem fez login, e cada perfil vê as suas páginas */
const Router = (() => {
  let limpar = null;
  const ROTAS = {
    '': Publico.inicio, entrar: Publico.entrar, cadastro: Publico.cadastro,
    // cidadão
    'app/painel': Painel.painel, 'app/alertas': Painel.alertas, 'app/economize': Painel.economize, 'app/mes': Painel.mes, 'app/desafios': Painel.desafios,
    'app/agua': (a) => Painel.area(a, 'agua'), 'app/energia': (a) => Painel.area(a, 'energia'), 'app/lixo': (a) => Painel.area(a, 'lixo'), 'app/transporte': (a) => Painel.area(a, 'transporte'),
    'app/comparar': Painel.comparar, 'app/mapa': Painel.mapa, 'app/aprenda': Painel.aprenda, 'app/simulador': Pro.simulador,
    // analista / gestor / admin
    'app/cidade': (app) => Painel.painel(app, null, 'cidade'), 'app/laboratorio': Pro.laboratorio, 'app/assistente': Pro.assistente,
    'app/riscos': Pro.riscos, 'app/analises': Pro.analises, 'app/metas': Pro.metas,
    'app/sala': Pro.sala, 'app/conselheiro': Pro.conselheiro, 'app/acoes': Pro.acoes, 'app/admin': Pro.admin,
  };
  // perfil mínimo de cada página (o servidor também confere)
  const RESTRITO = { 'app/cidade': 'ANALISTA', 'app/laboratorio': 'ANALISTA', 'app/assistente': 'ANALISTA', 'app/riscos': 'ANALISTA', 'app/analises': 'ANALISTA', 'app/metas': 'ANALISTA',
    'app/sala': 'GESTOR', 'app/conselheiro': 'GESTOR', 'app/simulador': 'GESTOR', 'app/acoes': 'GESTOR', 'app/admin': 'ADMIN' };
  const SO_CIDADAO = { 'app/painel': 'app/cidade', 'app/alertas': 'app/riscos', 'app/fontes': 'app/cidade' };   // páginas do cidadão -> equivalente profissional

  async function ir() {
    let rota = location.hash.replace(/^#\/?/, '');
    const partes = rota.split('/');
    const [base, extra] = rota.startsWith('cadastro') ? ['cadastro', partes[1]] : partes[0] === 'app' ? [`app/${partes[1] || ''}`, partes[2]] : [rota, null];
    if (base.startsWith('app') && !API.logado) { location.hash = '#/entrar'; return; }      // só entra quem tem cadastro e login
    if (base.startsWith('cadastro') && API.logado) { location.hash = `#/app/${Painel.INICIO[API.usuario.perfil]}`; return; }
    if (base === 'app/') { location.hash = `#/app/${Painel.INICIO[API.usuario.perfil]}`; return; }
    if (RESTRITO[base] && !Painel.pode(RESTRITO[base])) { location.hash = `#/app/${Painel.INICIO[API.usuario.perfil]}`; return; }
    if (SO_CIDADAO[base] && API.usuario?.perfil !== 'CIDADAO') { location.hash = `#/${SO_CIDADAO[base]}`; return; }
    const pagina = ROTAS[base];
    if (!pagina) { location.hash = '#/'; return; }
    limpar?.(); limpar = null;
    const app = UI.$('#app');
    if (!base.startsWith('app')) { app.className = 'pagina'; void app.offsetWidth; } else app.className = '';
    scrollTo({ top: 0, behavior: 'instant' });
    Chat.montar();
    try { limpar = await pagina(app, extra); }
    catch (e) { console.error(e); UI.toast(e.message, 'erro'); }
    document.title = base.startsWith('app') ? `EcoCity · ${UI.$('.lateral nav a.ativo .tx')?.textContent || 'Painel'}` : 'EcoCity · Dados que cuidam da cidade';
  }
  addEventListener('hashchange', ir);
  addEventListener('DOMContentLoaded', ir);
  return { ir };
})();
