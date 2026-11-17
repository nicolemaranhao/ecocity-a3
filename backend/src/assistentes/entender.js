// Entende a pergunta: quais cidades, indicadores, período e números foram citados.
const { consulta: query } = require('../db');

const norm = (s) => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

const PALAVRAS = [
  ['AGU-02', /(perda|vazament|desperdicio na rede)/],
  ['AGU-01', /(consumo de agua|agua per capita|agua por pessoa|litros|uso de agua|gasto de agua|conta de agua)/],
  ['ENE-02', /(solar|geracao distribuida|paine(l|is)|fotovolt)/],
  ['ENE-01', /(consumo de energia|energia per capita|energia por pessoa|kwh|conta de luz|consumo eletric)/],
  ['RES-02', /(recicl|coleta seletiva)/],
  ['RES-01', /(geracao de (lixo|residuo)|lixo gerado|lixo por pessoa|residuos? per capita|quantidade de lixo)/],
  ['MOB-01', /(onibus|transporte publico|passageir|viage)/],
  ['MOB-02', /(emiss|co2|carbono|poluic|gases)/],
];
const AREAS = [
  [['AGU-01', 'AGU-02'], /\bagua\b|saneamento|hidric/],
  [['ENE-01', 'ENE-02'], /\benergia\b|eletric|\bluz\b/],
  [['RES-01', 'RES-02'], /\blixo\b|residuo/],
  [['MOB-01', 'MOB-02'], /mobilidade|transporte|transito/],
];

function indicadores(t) {
  const achou = PALAVRAS.filter(([, re]) => re.test(t)).map(([c]) => c);
  if (achou.length) return achou;
  for (const [cods, re] of AREAS) if (re.test(t)) return cods;
  return [];
}

let cacheCid = null;
async function cidades(t) {
  cacheCid ||= await query('SELECT id_municipio, nome FROM municipio ORDER BY LENGTH(nome) DESC');
  const achou = []; let resto = t;
  for (const c of cacheCid) { const k = norm(c.nome); if (resto.includes(k)) { achou.push(c); resto = resto.replace(k, ' '); } }
  return achou;
}
async function todasCidades() { cacheCid ||= await query('SELECT id_municipio, nome FROM municipio ORDER BY LENGTH(nome) DESC'); return cacheCid; }

const somar = (am, k) => { const d = new Date(Number(am.slice(0, 4)), Number(am.slice(5, 7)) - 1 + k, 1); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`; };
function periodo(t, ultimo) {
  const ano = t.match(/\b(20\d\d)\b/);
  const n = t.match(/(\d{1,2})\s*mes/);
  if (/(24 meses|2 anos|dois anos|tudo|serie completa|historico)/.test(t)) return { de: somar(ultimo, -23), ate: ultimo, txt: 'últimos 24 meses' };
  if (n) return { de: somar(ultimo, -(Number(n[1]) - 1)), ate: ultimo, txt: `últimos ${n[1]} meses` };
  if (ano) { const a = ano[1]; const ate = `${a}-12` > ultimo ? ultimo : `${a}-12`; return { de: `${a}-01`, ate, txt: `${a}` }; }
  if (/(ultimo mes|este mes|mes atual)/.test(t)) return { de: ultimo, ate: ultimo, txt: 'último mês' };
  return { de: somar(ultimo, -11), ate: ultimo, txt: 'últimos 12 meses' };
}

// "para 25%" (valor-alvo) · "reduzir 10%" / "aumentar 20%" (variação relativa) · "dobrar"
function cenario(t) {
  const alvo = t.match(/para\s+(\d+(?:[.,]\d+)?)/);
  if (alvo) return { tipo: 'ALVO', valor: Number(alvo[1].replace(',', '.')) };
  const red = t.match(/(reduz|diminu|cair|caia|cairem|baix|cort)\w*\s+(?:em\s+)?(\d+(?:[.,]\d+)?)\s*%/);
  if (red) return { tipo: 'REL', valor: -Number(red[2].replace(',', '.')) };
  const aum = t.match(/(aument|sub|cresc|ampli|elev)\w*\s+(?:em\s+)?(\d+(?:[.,]\d+)?)\s*%/);
  if (aum) return { tipo: 'REL', valor: Number(aum[2].replace(',', '.')) };
  const mel = t.match(/(melhor|pior)\w*\s+(?:em\s+)?(\d+(?:[.,]\d+)?)\s*%/);
  if (mel) return { tipo: mel[1] === 'melhor' ? 'MELHORA' : 'PIORA', valor: Number(mel[2].replace(',', '.')) };
  if (/dobr/.test(t)) return { tipo: 'REL', valor: 100 };
  return null;
}

// mesma regra da função fn_score do banco
function score(valor, meta, sentido) {
  const desvio = sentido === 'MAIOR_MELHOR' ? ((meta - valor) / meta) * 100 : ((valor - meta) / meta) * 100;
  return Math.round(Math.min(100, Math.max(0, 100 - 1.5 * Math.max(desvio, 0))) * 100) / 100;
}

module.exports = { norm, indicadores, cidades, todasCidades, periodo, cenario, score, somar };
