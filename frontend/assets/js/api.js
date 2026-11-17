/* EcoCity — conversa com a API (Express + MySQL). O token fica só nesta aba do navegador. */
const API = (() => {
  const CHAVE = 'ecocity.sessao';
  let sessao = null;
  try { sessao = JSON.parse(sessionStorage.getItem(CHAVE) || 'null'); } catch { sessao = null; }

  async function req(metodo, caminho, corpo, { silencioso = false } = {}) {
    if (!silencioso) UI.progresso(true);
    try {
      const r = await fetch(`/api${caminho}`, {
        method: metodo,
        headers: { 'content-type': 'application/json', ...(sessao?.token ? { authorization: `Bearer ${sessao.token}` } : {}) },
        body: corpo ? JSON.stringify(corpo) : undefined,
      });
      const j = await r.json().catch(() => ({}));
      if (r.status === 401 && sessao && !caminho.startsWith('/auth')) { sair(); location.hash = '#/entrar'; UI.toast('Sua sessão expirou. Entre de novo.', 'erro'); }
      if (!r.ok) throw Object.assign(new Error(j.erro || 'Algo deu errado. Tente de novo.'), { status: r.status, dados: j });
      return j;
    } catch (e) {
      if (e instanceof TypeError) throw new Error('Sem conexão com o servidor. Ele está ligado (npm start)?');
      throw e;
    } finally { if (!silencioso) UI.progresso(false); }
  }

  function entrar(r) { sessao = { token: r.token, usuario: r.usuario }; sessionStorage.setItem(CHAVE, JSON.stringify(sessao)); }
  function sair() { sessao = null; sessionStorage.removeItem(CHAVE); }

  // cache simples para não buscar os mesmos dados a cada troca de página
  const cache = {};
  const pegar = async (caminho, forcar) => { if (forcar || !cache[caminho]) cache[caminho] = req('GET', caminho).catch((e) => { delete cache[caminho]; throw e; }); return cache[caminho]; };
  const limpar = (prefixo = '') => Object.keys(cache).forEach((k) => k.startsWith(prefixo) && delete cache[k]);

  return {
    get: (c, o) => req('GET', c, null, o), post: (c, b, o) => req('POST', c, b, o), patch: (c, b) => req('PATCH', c, b), put: (c, b) => req('PUT', c, b),
    pegar, limpar, entrar, sair,
    get usuario() { return sessao?.usuario || null; },
    get logado() { return !!sessao?.token; },
  };
})();
