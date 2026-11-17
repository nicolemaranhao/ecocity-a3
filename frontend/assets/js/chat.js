/* EcoCity — assistente "Eco": botão flutuante (todos) e página inteira (analista: relatórios · gestor: conselheiro).
   Cada perfil fala com um assistente diferente; a conversa e o contexto (cidade/tema) ficam guardados enquanto a pessoa navega. */
const Chat = (() => {
  const { $, $$, esc, ico, logo, num } = UI;
  const conversa = []; let contexto = {}; let aberto = false; let alvo = null;   // alvo = elemento onde as mensagens são desenhadas
  const NOME = { CIDADAO: ['Eco', 'dicas e a sua cidade'], ANALISTA: ['Eco Analista', 'relatórios e dados'], GESTOR: ['Conselheiro', 'apoio à decisão'], ADMIN: ['Conselheiro', 'apoio à decisão'] };
  const PAGINA_PROPRIA = ['assistente', 'conselheiro'];

  function montar() {
    const raiz = $('#chat-raiz');
    const rota = location.hash.replace(/^#\/?app\/?/, '');
    if (!API.logado || PAGINA_PROPRIA.includes(rota)) { raiz.innerHTML = ''; aberto = false; return; }
    if (raiz.childElementCount) return;
    const [n] = NOME[API.usuario.perfil] || NOME.CIDADAO;
    raiz.innerHTML = `<button class="chat-botao" id="chatBotao" aria-label="Abrir o assistente ${n}">${ico('chat', '#fff')}<span class="balao">Pergunte ao ${n} 💬</span></button>`;
    $('#chatBotao').onclick = abrir;
  }
  function desmontar() { $('#chat-raiz').innerHTML = ''; aberto = false; conversa.length = 0; contexto = {}; }

  // ------------------------------------------------------------ desenho de uma mensagem
  function html(m) {
    if (m.de === 'eu') return esc(m.texto);
    let h = UI.mdc(m.texto);
    if (m.cartao?.tipo === 'cidade') h += `<div class="mini-cidade">${m.cartao.areas.map((a) => `<div class="nivel-${a.nivel}">${num(a.score, 0)}<small>${esc(a.servico)}</small></div>`).join('')}</div>`;
    if (m.grafico) h += UI.linha(m.grafico.series.map((s, i) => ({ nome: s.nome, valores: s.valores, cor: ['#1D5FA8', '#2F8F3F', '#E8892B'][i] })), { altura: 220, largura: 520, rotulos: m.grafico.rotulos.map(UI.mesTxt), meta: m.grafico.meta });
    if (m.tabela?.length && !m.rascunho) {
      const cols = Object.keys(m.tabela[0]).filter((c) => !/^id_|sql/.test(c)).slice(0, 6);
      h += `<div class="md-tab"><table><tr>${cols.map((c) => `<th>${esc(c.replace(/_/g, ' '))}</th>`).join('')}</tr>${m.tabela.slice(0, 24).map((l) => `<tr>${cols.map((c) => `<td>${typeof l[c] === 'number' ? num(l[c], Math.abs(l[c]) < 20 ? 2 : 1) : esc(l[c] ?? '—')}</td>`).join('')}</tr>`).join('')}</table></div>`;
    }
    if (m.rascunho) {
      h += `<div class="rascunho"><span class="chip verde"><i></i>Rascunho de relatório</span><h4>${esc(m.rascunho.titulo)}</h4><p class="r-res">${esc(m.rascunho.resumo)}</p>
        <details><summary>Ver o texto completo</summary><div class="r-corpo">${UI.mdc(m.rascunho.conteudo)}</div></details>
        <div class="r-acoes"><button class="btn verde sm" data-usar="${m.id}">Abrir como nova análise</button><button class="btn fantasma sm" data-copiar="${m.id}">Copiar texto</button></div></div>`;
    }
    if (m.fontes?.length) h += `<div class="msg-fontes">${ico('fonte')}<span>Fontes:</span>${m.fontes.slice(0, 5).map((f) => (f.url ? `<a href="${esc(f.url)}" target="_blank" rel="noopener">${esc(f.fonte)}</a>` : `<span>${esc(f.fonte)}</span>`)).join('')}</div>`;
    if (m.link) h += `<a class="btn sm" style="margin-top:10px" href="${esc(m.link.href)}">${esc(m.link.texto)}</a>`;
    return h;
  }
  function desenhar(m, animar = true) {
    if (!alvo) return;
    const el = document.createElement('div'); el.className = `msg ${m.de}`; if (!animar) el.style.animation = 'none';
    el.innerHTML = html(m); alvo.append(el); UI.ativarGraficos(el); alvo.scrollTop = 1e9;
    $$('[data-usar]', el).forEach((b) => (b.onclick = () => { fechar(); Pro.novaAnaliseDoRascunho(m.rascunho); }));
    $$('[data-copiar]', el).forEach((b) => (b.onclick = async () => { try { await navigator.clipboard.writeText(`# ${m.rascunho.titulo}\n\n${m.rascunho.conteudo}`); UI.toast('Texto copiado', 'ok'); } catch { UI.toast('Não foi possível copiar', 'erro'); } }));
  }
  let sugEl = null;
  function sugestoes(lista = []) {
    if (!sugEl) return;
    sugEl.innerHTML = lista.map((s) => `<button type="button">${esc(s)}</button>`).join('');
    [...sugEl.children].forEach((b) => (b.onclick = () => enviar(b.textContent)));
  }
  function enviar(texto) {
    texto = String(texto || '').trim(); if (!texto) return;
    const inp = $('#chatTxt'); if (inp) inp.value = '';
    const m = { de: 'eu', texto }; conversa.push(m); desenhar(m); perguntar(texto);
  }
  async function perguntar(texto) {
    const dig = document.createElement('div'); dig.className = 'msg eco digitando'; dig.innerHTML = '<i></i><i></i><i></i>';
    alvo?.append(dig); if (alvo) alvo.scrollTop = 1e9;
    const t0 = Date.now(); let r;
    const historico = conversa.slice(-9, -1).map((x) => ({ de: x.de, texto: String(x.texto).slice(0, 1500) }));
    try { r = await API.post('/chat', { pergunta: texto, historico, contexto }, { silencioso: true }); } catch (e) { r = { texto: `Ops: ${e.message}` }; }
    await new Promise((ok) => setTimeout(ok, Math.max(0, 600 - (Date.now() - t0))));
    dig.remove();
    if (r.contexto) { contexto = r.contexto; atualizarContexto(); }
    const m = { de: 'eco', id: conversa.length, ...r }; conversa.push(m); desenhar(m); sugestoes(r.sugestoes);
  }
  let aoMudarContexto = null;
  function atualizarContexto() { aoMudarContexto?.(contexto); }

  // ------------------------------------------------------------ janela flutuante
  function abrir(perguntaInicial) {
    if (aberto) return; aberto = true;
    const [n, s] = NOME[API.usuario.perfil] || NOME.CIDADAO;
    const p = document.createElement('section'); p.className = 'chat-painel'; p.id = 'chatPainel'; p.setAttribute('aria-label', `Assistente ${n}`);
    p.innerHTML = `<header class="chat-cab"><div class="av">${logo()}</div><div><b>${n}</b><small>${s}</small></div><button aria-label="Fechar" id="chatFechar">×</button></header>
      <div class="chat-msgs" id="msgs" aria-live="polite"></div><div class="chat-sug" id="sug"></div>
      <form class="chat-form" id="chatForm"><input id="chatTxt" placeholder="Escreva sua pergunta…" autocomplete="off" maxlength="800"><button aria-label="Enviar">${ico('enviar', '#fff')}</button></form>`;
    $('#chat-raiz').append(p); $('#chatBotao').style.display = 'none';
    alvo = $('#msgs', p); sugEl = $('#sug', p);
    $('#chatFechar').onclick = fechar;
    $('#chatForm').onsubmit = (e) => { e.preventDefault(); enviar($('#chatTxt').value); };
    conversa.forEach((m) => desenhar(m, false));
    if (typeof perguntaInicial === 'string') enviar(perguntaInicial);
    else if (!conversa.length) perguntar('oi');
    setTimeout(() => $('#chatTxt')?.focus(), 300);
  }
  function fechar() {
    const p = $('#chatPainel'); if (!p) return;
    p.classList.add('fecha'); setTimeout(() => { p.remove(); aberto = false; alvo = null; const b = $('#chatBotao'); if (b) b.style.display = ''; }, 280);
  }

  // ------------------------------------------------------------ página inteira (assistente / conselheiro)
  function pagina(el, { placeholder, aoContexto, pergunta } = {}) {
    el.innerHTML = `<div class="chat-pagina"><div class="chat-msgs" id="msgsP" aria-live="polite"></div><div class="chat-sug" id="sugP"></div>
      <form class="chat-form grande" id="chatForm"><textarea id="chatTxt" rows="1" placeholder="${esc(placeholder || 'Escreva…')}" maxlength="800"></textarea><button class="btn" aria-label="Enviar">${ico('enviar', '#fff')}<span>Enviar</span></button></form></div>`;
    alvo = $('#msgsP', el); sugEl = $('#sugP', el); aoMudarContexto = aoContexto;
    const ta = $('#chatTxt', el);
    ta.oninput = () => { ta.style.height = 'auto'; ta.style.height = `${Math.min(160, ta.scrollHeight)}px`; };
    ta.onkeydown = (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); enviar(ta.value); } };
    $('#chatForm', el).onsubmit = (e) => { e.preventDefault(); enviar(ta.value); };
    conversa.forEach((m) => desenhar(m, false));
    if (pergunta) enviar(pergunta); else if (!conversa.length) perguntar('oi');
    else sugestoes(conversa.filter((m) => m.de === 'eco').pop()?.sugestoes);
    atualizarContexto();
    return { enviar, definirContexto: (c) => { contexto = { ...contexto, ...c }; }, limpar: () => { conversa.length = 0; contexto = {}; alvo.innerHTML = ''; perguntar('oi'); } };
  }

  return { montar, desmontar, abrir, pagina, get contexto() { return contexto; } };
})();
