/* EcoCity — motivos visuais animados (SVG em linhas finas), discretos, para dar movimento sem roubar a atenção dos dados.
   Se houver foto ou vídeo da equipe em assets/midia (listados em midia.json), eles aparecem no lugar do motivo. */
const Cenas = (() => {
  const COR = { agua: '#2E8FCB', energia: '#D9822B', lixo: '#3E9A4E', transporte: '#2B4C8C' };
  const onda = (y, amp, fase, cor, op, dur, k) => {
    let d = `M-40 ${y}`; for (let x = -40; x <= 680; x += 40) d += ` Q${x + 20} ${y + (((x / 40 + fase) % 2) ? amp : -amp)} ${x + 40} ${y}`;
    return `<path class="mv-fluxo" style="--dur:${dur}s;--atraso:${-k * 1.3}s" d="${d}" fill="none" stroke="${cor}" stroke-opacity="${op}" stroke-width="1.4"/>`;
  };
  const M = {
    // capa: linhas de fluxo nas 4 cores do logo
    cidade: () => [...Array(14)].map((_, k) => onda(40 + k * 17, 10 + (k % 4) * 4, k, ['#3E9A4E', '#2E8FCB', '#D9822B', '#2B4C8C'][k % 4], 0.22 + (k % 3) * 0.12, 9 + (k % 5) * 2, k)).join(''),
    agua: () => `${[0, 1, 2, 3, 4].map((k) => `<circle class="mv-anel" style="--atraso:${k * 1.2}s" cx="420" cy="150" r="40" fill="none" stroke="${COR.agua}" stroke-width="1.4"/>`).join('')}
      <circle cx="420" cy="150" r="5" fill="${COR.agua}"/>${[0, 1, 2, 3].map((k) => onda(205 + k * 16, 6, k, COR.agua, 0.25 + k * 0.1, 8 + k * 2, k)).join('')}`,
    energia: () => `<g transform="translate(420 150)"><g class="mv-gira">${[...Array(36)].map((_, k) => `<line x1="0" y1="-${k % 2 ? 58 : 50}" x2="0" y2="-${k % 3 ? 96 : 120}" stroke="${COR.energia}" stroke-opacity="${k % 3 ? 0.35 : 0.8}" stroke-width="1.4" transform="rotate(${k * 10})"/>`).join('')}</g>
      <circle r="34" fill="none" stroke="${COR.energia}" stroke-width="1.4"/><circle class="mv-pulsa" r="14" fill="${COR.energia}"/>
      <circle r="140" fill="none" stroke="${COR.energia}" stroke-opacity=".25" stroke-dasharray="2 7"/></g>`,
    lixo: () => `<g transform="translate(420 150)"><g class="mv-gira lento">${[0, 120, 240].map((r) => `<path transform="rotate(${r})" d="M0 -78 A78 78 0 0 1 67.5 39" fill="none" stroke="${COR.lixo}" stroke-width="1.6" stroke-linecap="round"/><path transform="rotate(${r})" d="M60 30 L67.5 39 L72 27" fill="none" stroke="${COR.lixo}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>`).join('')}</g>
      <g class="mv-gira reverso">${[...Array(12)].map((_, k) => `<circle cx="0" cy="-118" r="${k % 3 ? 2 : 3.5}" fill="${COR.lixo}" fill-opacity="${k % 3 ? 0.4 : 0.9}" transform="rotate(${k * 30})"/>`).join('')}</g></g>`,
    transporte: () => [0, 1, 2, 3, 4].map((k) => {
      const d = `M-20 ${70 + k * 40} C 180 ${40 + k * 40}, 360 ${120 + k * 32}, 640 ${80 + k * 38}`;
      return `<path d="${d}" fill="none" stroke="${COR.transporte}" stroke-opacity=".14" stroke-width="10" stroke-linecap="round"/><path class="mv-faixa" style="--dur:${5 + k}s" d="${d}" fill="none" stroke="${COR.transporte}" stroke-opacity="${0.4 + k * 0.12}" stroke-width="2" stroke-dasharray="18 26" stroke-linecap="round"/>`;
    }).join(''),
  };

  let manifesto = null;
  const carregar = () => (manifesto ||= fetch('assets/midia/midia.json').then((r) => (r.ok ? r.json() : {})).catch(() => ({}))).then((m) => m || {});

  function cena(tipo, { classe = '' } = {}) {
    const id = `cn${Math.random().toString(36).slice(2, 7)}`;
    carregar().then((m) => {
      const item = m[tipo]; const el = document.getElementById(id); if (!item || !el) return;
      const src = /^https?:\/\//.test(item.arquivo) ? item.arquivo : `assets/midia/${item.arquivo}`;   // arquivo local ou foto com licença livre na internet
      const media = /\.(mp4|webm)(\?|$)/i.test(item.arquivo) ? `<video src="${UI.esc(src)}" autoplay muted loop playsinline></video>` : `<img src="${UI.esc(src)}" alt="${UI.esc(item.descricao || tipo)}" loading="lazy" decoding="async">`;
      el.insertAdjacentHTML('beforeend', `<div class="cena-midia">${media}${item.credito ? `<small>${UI.esc(item.credito)}</small>` : ''}</div>`);
      const md = el.querySelector('.cena-midia img, .cena-midia video');
      const ok = () => el.classList.add('com-midia'); const falhou = () => el.querySelector('.cena-midia')?.remove();   // sem internet: fica o desenho animado
      md.addEventListener(md.tagName === 'VIDEO' ? 'loadeddata' : 'load', ok); md.addEventListener('error', falhou);
    });
    return `<figure class="motivo ${classe}" id="${id}" aria-hidden="true"><svg viewBox="0 0 600 300" preserveAspectRatio="xMidYMid slice">${(M[tipo] || M.cidade)()}</svg></figure>`;
  }
  const AREA = { 'Água': 'agua', 'Energia': 'energia', 'Resíduos': 'lixo', 'Mobilidade': 'transporte' };
  return { cena, AREA, COR };
})();
