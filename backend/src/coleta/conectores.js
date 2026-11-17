// Conectores das fontes oficiais do EcoCity (v17).
// Cada conector entra no site do órgão público, baixa o arquivo ou chama a API,
// e devolve os números no formato da tabela de entrada (staging):
//   { fonte, metrica, municipio, mes: 'AAAA-MM', valor, origem, referencia }
//     origem REAL     = número oficial daquele mês
//            DERIVADO = total oficial do ano dividido pelos meses
//            ESTIMADO = estimativa (não existe número oficial da cidade)
// Cada conector também devolve a "versão" publicada (data do arquivo, último ano...).
// Se a versão não mudou desde a última verificação, o robô não baixa de novo.
//
// Ferramentas: fetch (Node 18+), yauzl (abrir .zip), xlsx/SheetJS (planilhas),
// pdfjs-dist (ler o PDF da SPTrans). Tudo roda no servidor do EcoCity.
const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');
const { Readable } = require('stream');
const { pipeline } = require('stream/promises');

const TIMEOUT = Number(process.env.COLETA_TIMEOUT_MS || 120_000);
const ENTRADA = path.join(__dirname, '..', '..', '..', 'dados_reais', 'entrada');
const UA = { 'user-agent': 'Mozilla/5.0 (EcoCity-coleta/2.0; projeto academico)' };
const NOME_MES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const MES_NUM = Object.fromEntries(NOME_MES.map((m, i) => [m, i + 1]));
const rot = (mes) => `${NOME_MES[Number(mes.slice(5, 7)) - 1]}/${mes.slice(0, 4)}`;
const dias = (a, m) => new Date(a, m, 0).getDate();
const diasAno = (a) => (a % 4 === 0 && (a % 100 !== 0 || a % 400 === 0) ? 366 : 365);
const ym = (a, m) => `${a}-${String(m).padStart(2, '0')}`;
const host = (u) => { try { return new URL(u).host; } catch { return u; } };
// perfil sazonal do consumo de água (verão maior) — o mesmo usado na carga inicial
const SAZ_AGUA = [1.06, 1.05, 1.04, 1.00, 0.96, 0.94, 0.94, 0.96, 0.99, 1.02, 1.03, 1.06];

// IDs das fontes (tabela fonte_dados)
const FONTE = { AGUA_CONSUMO: 1, AGUA_PERDAS: 2, EPE: 3, ANEEL: 4, SINISA: 5, SPREGULA: 6, SPTRANS: 7, SEEG: 8 };

async function pegar(url, opcoes = {}) {
  let r;
  try {
    r = await fetch(url, { ...opcoes, signal: AbortSignal.timeout(opcoes.timeout || TIMEOUT), headers: { ...UA, ...(opcoes.headers || {}) } });
  } catch (e) { throw new Error(`sem conexão com ${host(url)} (${e.cause?.code || e.name})`); }
  if (!r.ok) throw new Error(`${host(url)} respondeu ${r.status}`);
  return r;
}
const getJSON = async (url, op) => (await pegar(url, op)).json();
const getTexto = async (url, op) => (await pegar(url, op)).text();
const getBuffer = async (url, op) => Buffer.from(await (await pegar(url, op)).arrayBuffer());
let ultimoErroHead = null;
async function versaoArquivo(url) {     // data/tamanho do arquivo publicado, sem baixar tudo
  const r = await pegar(url, { method: 'HEAD', timeout: 30_000 }).catch((e) => { ultimoErroHead = e; return null; });
  if (!r) return null;
  return [r.headers.get('last-modified'), r.headers.get('content-length')].filter(Boolean).join(' · ') || null;
}
async function baixarParaArquivo(url, nome) {
  const r = await pegar(url, { timeout: Number(process.env.COLETA_TIMEOUT_GRANDE_MS || 15 * 60_000) });
  const destino = path.join(os.tmpdir(), `ecocity_${Date.now()}_${nome}`);
  await pipeline(Readable.fromWeb(r.body), fs.createWriteStream(destino));
  return destino;
}
const numBR = (s) => {
  if (typeof s === 'number') return s;
  const t = String(s ?? '').trim();
  if (!t || t === '-') return NaN;
  return Number(t.replace(/\./g, '').replace(',', '.'));
};

// =============================================================================
// 1) ANEEL — Geração distribuída (painéis solares) — dado OFICIAL do mês.
//    Dados abertos da ANEEL (CKAN): arquivo .zip com o CSV de todos os sistemas do
//    Brasil (~110 MB, atualizado pela ANEEL quase todo dia). O robô soma a potência
//    (kW) de cada cidade pela data de cadastro e acumula mês a mês.
// =============================================================================
async function aneelGD(ctx) {
  const base = process.env.ANEEL_CKAN || 'https://dadosabertos.aneel.gov.br';
  const pac = await getJSON(`${base}/api/3/action/package_show?id=relacao-de-empreendimentos-de-geracao-distribuida`);
  const rec = (pac.result?.resources || []).find((r) => /^empreendimento-geracao-distribuida\.zip$/i.test(r.name || ''))
    || (pac.result?.resources || []).find((r) => /geracao-distribuida\.zip$/i.test(r.url || ''));
  if (!rec) throw new Error('ANEEL: arquivo empreendimento-geracao-distribuida.zip não encontrado no catálogo');
  const versao = `arquivo de ${String(rec.last_modified || rec.metadata_modified || '').slice(0, 10)}`;
  if (!ctx.forcar && ctx.ultimaVersao(FONTE.ANEEL) === versao) return { fonte: FONTE.ANEEL, versao, semNovidade: true, linhas: [] };

  const yauzl = require('yauzl');
  const arq = await baixarParaArquivo(rec.url, 'aneel_gd.zip');
  const cods = new Map(ctx.municipios.map((m) => [String(m.codigo_ibge), m.nome]));
  const porCidadeMes = {};             // cod -> { 'AAAA-MM': kW novos }
  let periodo = null; let linhasLidas = 0;
  try {
    await new Promise((ok, falha) => {
      yauzl.open(arq, { lazyEntries: true }, (e, zip) => {
        if (e) return falha(e);
        zip.readEntry();
        zip.on('entry', (ent) => {
          if (!/\.csv$/i.test(ent.fileName)) return zip.readEntry();
          zip.openReadStream(ent, (e2, st) => {
            if (e2) return falha(e2);
            const rl = readline.createInterface({ input: st, crlfDelay: Infinity });
            let col = null;
            rl.on('line', (l) => {
              const c = l.split(';').map((x) => x.replace(/^"|"$/g, ''));
              if (!col) { col = Object.fromEntries(c.map((n, i) => [n.trim(), i])); return; }
              linhasLidas++;
              if (!periodo) periodo = c[col.AnmPeriodoReferencia];
              const cod = c[col.CodMunicipioIbge];
              if (!cods.has(cod)) return;
              const mes = String(c[col.DthAtualizaCadastralEmpreend] || '').slice(0, 7);
              const kw = numBR(c[col.MdaPotenciaInstaladaKW]);
              if (!/^\d{4}-\d{2}$/.test(mes) || !(kw > 0)) return;
              (porCidadeMes[cod] ||= {})[mes] = (porCidadeMes[cod][mes] || 0) + kw;
            });
            rl.on('close', () => { zip.close(); ok(); });
            st.on('error', falha);
          });
        });
        zip.on('end', ok);
        zip.on('error', falha);
      });
    });
  } finally { fs.rm(arq, () => {}); }
  if (!linhasLidas) throw new Error('ANEEL: o CSV veio vazio');

  // último mês COMPLETO = mês anterior ao período de referência do arquivo (ex.: "11/2026" -> 2026-10)
  const [pm, pa] = String(periodo || '').split('/').map(Number);
  const ultimo = pm && pa ? ym(pm === 1 ? pa - 1 : pa, pm === 1 ? 12 : pm - 1) : null;
  if (!ultimo) throw new Error('ANEEL: período de referência do arquivo não encontrado');
  const dataBase = String(rec.last_modified || '').slice(0, 10).split('-').reverse().join('/');
  const linhas = [];
  for (const [cod, nome] of cods) {
    const m = porCidadeMes[cod] || {};
    let acum = 0;
    const meses = Object.keys(m).sort();
    let i = 0;
    for (let a = 2000; ; a++) {
      let fim = false;
      for (let k = 1; k <= 12; k++) {
        const chave = ym(a, k);
        while (i < meses.length && meses[i] <= chave) acum += m[meses[i++]];
        if (chave >= ctx.desde && chave <= ultimo) {
          linhas.push({ fonte: FONTE.ANEEL, metrica: 'GD_POTENCIA', municipio: nome, mes: chave, valor: acum, origem: 'REAL',
            referencia: `ANEEL - geração distribuída: potência acumulada até o fim de ${rot(chave)} (${Math.round(acum).toLocaleString('pt-BR')} kW). Base de ${dataBase}.` });
        }
        if (chave >= ultimo) { fim = true; break; }
      }
      if (fim) break;
    }
  }
  return { fonte: FONTE.ANEEL, versao, linhas, ultimoMes: ultimo, detalhe: `${linhasLidas.toLocaleString('pt-BR')} sistemas lidos; dados até ${rot(ultimo)}` };
}

// =============================================================================
// 2) IBGE — população estimada (anual). API de agregados do IBGE.
// =============================================================================
async function ibgePopulacao(ano, municipios) {
  const cods = municipios.map((m) => m.codigo_ibge).join(',');
  const j = await getJSON(`https://servicodados.ibge.gov.br/api/v3/agregados/6579/periodos/${ano}/variaveis/9324?localidades=N6[${cods}]`);
  const series = j?.[0]?.resultados?.[0]?.series || [];
  return series.map((s) => ({ codigo_ibge: String(s.localidade.id), populacao: Number(s.serie?.[ano]) })).filter((r) => r.populacao > 0);
}

// =============================================================================
// 3) SPTrans — passageiros de ônibus de São Paulo (OFICIAL do mês).
//    A SPTrans publica um PDF ("Situação dos Ônibus na Cidade de São Paulo") com uma
//    linha por dia desde 2020. O robô lê todas as páginas e soma a coluna
//    "viagens de passageiros" de cada mês.
//    Onde está o PDF: o robô procura o link nas páginas da SPTrans; se não achar,
//    usa o último endereço que já funcionou ou o SPTRANS_PDF_URL do .env.
// =============================================================================
const SPTRANS_PADRAO = 'https://www.sptrans.com.br/media/18358/atualizacao-site-02102026.pdf';
async function sptransAcharPDF(ctx) {
  const paginas = (process.env.SPTRANS_PAGINAS || 'https://www.sptrans.com.br/,https://www.sptrans.com.br/noticias/,https://www.sptrans.com.br/informativos/,https://www.sptrans.com.br/sptrans/')
    .split(',').map((s) => s.trim()).filter(Boolean);
  const achados = [];
  for (const p of paginas) {
    try {
      const html = await getTexto(p, { timeout: 30_000 });
      for (const m of html.matchAll(/["'(]((?:https?:\/\/www\.sptrans\.com\.br)?\/media\/\d+\/[^"'()?\s]*(?:atualizacao-site|situacao[^"']*onibus)[^"'()?\s]*\.pdf)/gi)) {
        achados.push(new URL(m[1], 'https://www.sptrans.com.br').href);
      }
    } catch { /* página fora do ar: tenta as outras */ }
  }
  // o mais novo tem o maior número de mídia
  achados.sort((a, b) => Number(b.match(/media\/(\d+)/)[1]) - Number(a.match(/media\/(\d+)/)[1]));
  const anterior = (ctx.ultimaVersao(FONTE.SPTRANS) || '').split(' | ')[0];
  return [...new Set([...achados, process.env.SPTRANS_PDF_URL, anterior.startsWith('http') ? anterior : null, SPTRANS_PADRAO].filter(Boolean))];
}

function sptransSomarMeses(paginasTexto) {
  const soma = {}; let ano = null;
  for (const t of paginasTexto) {
    for (let i = 0; i < t.length; i++) {
      const h = t[i].match(/Adequa..o da Oferta\s*-\s*(\d{4})/i);
      if (h) { ano = Number(h[1]); continue; }
      const d = t[i].match(/^(\d{2})\/([a-zç]{3})$/i);
      if (!d || !ano || !MES_NUM[d[2].toLowerCase()]) continue;
      // linha do dia: data | frota | variação | % frota | pessoas | % pessoas | VIAGENS | % viagens | linhas
      const v = numBR(t[i + 6]);
      if (!(v > 0)) continue;
      const k = ym(ano, MES_NUM[d[2].toLowerCase()]);
      (soma[k] ||= { viagens: 0, dias: 0 });
      soma[k].viagens += v; soma[k].dias += 1;
    }
  }
  return soma;
}

async function sptrans(ctx) {
  const candidatos = await sptransAcharPDF(ctx);
  let url = null; let lm = null;
  for (const c of candidatos) { lm = await versaoArquivo(c); if (lm) { url = c; break; } }
  if (!url) throw new Error(/sem conexão/.test(ultimoErroHead?.message || '') ? ultimoErroHead.message : 'SPTrans: nenhum PDF encontrado (confira SPTRANS_PDF_URL no .env)');
  const versao = `${url} | ${lm}`.slice(0, 120);
  // sempre lê o PDF (2 MB): a série também serve para estimar os ônibus das outras cidades
  const semNovidade = !ctx.forcar && ctx.ultimaVersao(FONTE.SPTRANS) === versao;

  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const dados = new Uint8Array(await getBuffer(url));
  const doc = await pdfjs.getDocument({ data: dados, useSystemFonts: true, isEvalSupported: false }).promise;
  const paginas = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const tc = await (await doc.getPage(p)).getTextContent();
    paginas.push(tc.items.map((i) => String(i.str).trim()).filter(Boolean));
  }
  const atualizado = (paginas.flat().join(' ').match(/Atualizado em (\d{2}\/\d{2}\/\d{4})/i) || [])[1] || '';
  const soma = sptransSomarMeses(paginas);
  const meses = Object.keys(soma).sort();
  if (!meses.length) throw new Error('SPTrans: não consegui ler a tabela do PDF (o formato mudou?)');
  const ultimo = meses[meses.length - 1];
  const linhas = [];
  for (const k of meses) {
    if (k < ctx.desde) continue;
    const d = dias(Number(k.slice(0, 4)), Number(k.slice(5)));
    const { viagens, dias: dd } = soma[k];
    if (dd < d - 3) continue;                       // mês ainda incompleto no PDF: espera a próxima atualização
    const valor = viagens * d / dd;                 // completa 1 a 3 dias sem registro pela média do mês
    const ref = `SPTrans ${rot(k)}: soma diária das viagens de passageiros (${dd} de ${d} dias publicados${dd === d ? '' : '; dias faltantes completados pela média do mês'}). PDF atualizado em ${atualizado}.`;
    linhas.push({ fonte: FONTE.SPTRANS, metrica: 'TP_PASSAGEIROS', municipio: 'São Paulo', mes: k, valor, origem: 'REAL', referencia: ref });
  }
  const ultimoCompleto = linhas.length ? linhas[linhas.length - 1].mes : null;
  return { fonte: FONTE.SPTRANS, versao, semNovidade, linhas, ultimoMes: ultimoCompleto, serie: Object.fromEntries(meses.map((k) => [k, soma[k]])),
    detalhe: `${doc.numPages} páginas lidas; dias até ${rot(ultimo)} (PDF de ${atualizado || '?'})` };
}

// =============================================================================
// 4) EPE — consumo mensal de energia elétrica do Estado de SP (planilha oficial).
//    A EPE só publica por ESTADO. O robô usa a variação oficial do Estado para
//    estimar o consumo de cada cidade nos meses novos (origem ESTIMADO).
// =============================================================================
const EPE_URL = 'https://www.epe.gov.br/sites-pt/publicacoes-dados-abertos/publicacoes/Documents/CONSUMO%20MENSAL%20DE%20ENERGIA%20EL%C3%89TRICA%20POR%20CLASSE.xlsx';
async function epe(ctx) {
  const url = process.env.EPE_XLSX_URL || EPE_URL;
  const lm = await versaoArquivo(url);
  const versao = `planilha ${lm || 'sem data'}`.slice(0, 120);
  const semNovidade = !ctx.forcar && !!lm && ctx.ultimaVersao(FONTE.EPE) === versao;   // lê mesmo assim: serve para estimar meses novos
  const XLSX = require('xlsx');
  const wb = XLSX.read(await getBuffer(url), { type: 'buffer' });
  const ws = wb.Sheets['CONSUMO POR UF'];
  if (!ws) throw new Error('EPE: aba "CONSUMO POR UF" não encontrada (o formato mudou?)');
  const rows = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true });
  const iAno = rows.findIndex((r) => r.filter((x) => /^\d{4}/.test(String(x))).length > 12);
  const anos = rows[iAno]; const meses = rows[iAno + 1];
  const sp = rows.find((r) => /^s[aã]o paulo$/i.test(String(r[0] || '').trim()));
  if (!sp) throw new Error('EPE: linha "Sao Paulo" não encontrada');
  const MES3 = { JAN: 1, FEV: 2, MAR: 3, ABR: 4, MAI: 5, JUN: 6, JUL: 7, AGO: 8, SET: 9, OUT: 10, NOV: 11, DEZ: 12 };
  const serieSP = {};
  for (let c = 1; c < sp.length; c++) {
    const a = parseInt(String(anos[c]), 10); const m = MES3[String(meses[c] || '').trim().toUpperCase().slice(0, 3)];
    if (a && m && Number(sp[c]) > 0) serieSP[ym(a, m)] = Number(sp[c]);
  }
  const ks = Object.keys(serieSP).sort();
  return { fonte: FONTE.EPE, versao, semNovidade, linhas: [], serieSP, ultimoMes: ks[ks.length - 1], detalhe: `Estado de SP: ${ks.length} meses, até ${rot(ks[ks.length - 1])}` };
}

// =============================================================================
// 5) SEEG — emissões do transporte por cidade (oficial ANUAL). API GraphQL pública.
//    Setor Energia (477), categoria Transportes (755), emissão (1), CO2e GWP-AR5 (8).
//    O total do ano é dividido pelos dias de cada mês (origem DERIVADO).
// =============================================================================
async function seeg(ctx) {
  const api = process.env.SEEG_GRAPHQL || 'https://api.plataforma.seeg.eco.br/graphql';
  const gql = async (query, variables) => {
    const j = await getJSON(api, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ query, variables }) });
    if (j.errors) throw new Error(`SEEG: ${j.errors[0].message}`);
    return j.data;
  };
  const ids = {};
  for (const m of ctx.municipios) {
    const d = await gql('query($n:String){ areas(nameCont:$n){ id code } }', { n: m.nome });
    const a = (d.areas || []).find((x) => String(x.code) === String(m.codigo_ibge));
    if (a) ids[a.id] = m;
  }
  if (!Object.keys(ids).length) throw new Error('SEEG: cidades não encontradas na API');
  const anoAtual = new Date().getFullYear();
  const anos = []; for (let a = Number(ctx.desde.slice(0, 4)); a <= anoAtual; a++) anos.push(a);
  const d = await gql(`query($t:[Int!],$y:[Int!]){ emissionsSummary(sectorId:[477],categoryId:[755],emissionTypeId:[1],gasId:[8],
      territoriesIds:$t, years:$y, grouping:City, ranking:City){ data } }`, { t: Object.keys(ids).map(Number), y: anos });
  const porCidade = {};
  for (const s of d.emissionsSummary?.data || []) {
    const m = ctx.municipios.find((x) => s.name.startsWith(`${x.nome} (`));
    if (m) porCidade[m.nome] = Object.fromEntries((s.data || []).filter((v) => v.value > 0).map((v) => [v.year, v.value]));
  }
  // um ano só conta quando as 8 cidades já têm o número
  const anosCompletos = anos.filter((a) => ctx.municipios.every((m) => porCidade[m.nome]?.[a] > 0));
  const ultimoAno = anosCompletos[anosCompletos.length - 1];
  const versao = `anos ${anosCompletos[0]}-${ultimoAno}; total ${Math.round(anosCompletos.reduce((s, a) => s + ctx.municipios.reduce((t, m) => t + porCidade[m.nome][a], 0), 0))}`;
  if (!ctx.forcar && ctx.ultimaVersao(FONTE.SEEG) === versao) return { fonte: FONTE.SEEG, versao, semNovidade: true, linhas: [], ultimoAno };
  const linhas = [];
  for (const a of anosCompletos) {
    for (const m of ctx.municipios) {
      const total = porCidade[m.nome][a];
      for (let k = 1; k <= 12; k++) {
        linhas.push({ fonte: FONTE.SEEG, metrica: 'CO2_TRANSPORTE', municipio: m.nome, mes: ym(a, k), valor: total * dias(a, k) / diasAno(a), origem: 'DERIVADO',
          referencia: `SEEG Municípios ${a}: ${Math.round(total).toLocaleString('pt-BR')} t CO2e no ano (oficial) dividido pelos dias do mês` });
      }
    }
  }
  return { fonte: FONTE.SEEG, versao, linhas, ultimoAno, detalhe: `anos com as 8 cidades: ${anosCompletos.join(', ')}` };
}

// =============================================================================
// 6) SNIS/SINISA — água (oficial ANUAL), pelo Painel Saneamento Brasil.
//    Para cada cidade o robô baixa a planilha "exportar" do Painel (xlsx) e lê:
//      "Volume de água consumida (mil m³)"  e  "Índice de perdas na distribuição (%)".
//    O total do ano é distribuído pelos meses com o perfil sazonal (DERIVADO).
// =============================================================================
async function snisAgua(ctx) {
  const XLSX = require('xlsx');
  const base = process.env.PAINEL_SANEAMENTO || 'https://www.painelsaneamento.org.br';
  const porCidade = {};
  for (const m of ctx.municipios) {
    const cod6 = String(m.codigo_ibge).slice(0, 6);
    const buf = await getBuffer(`${base}/explore/localidade?SE%5Bl%5D=${cod6}&SE%5Bo%5D=e`);
    const wb = XLSX.read(buf, { type: 'buffer' });
    const rows = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, raw: true });
    const cab = rows.find((r) => String(r[0]).trim() === 'Indicador');
    if (!cab) throw new Error(`Painel Saneamento: planilha de ${m.nome} sem cabeçalho de anos`);
    const linha = (re) => rows.find((r) => re.test(String(r[0])));
    const cons = linha(/^Volume de água consumida \(mil m³\)/i);
    const perd = linha(/^Índice de perdas na distribuição/i);
    if (!cons || !perd) throw new Error(`Painel Saneamento: indicadores de água não encontrados para ${m.nome}`);
    porCidade[m.nome] = {};
    cab.forEach((a, c) => {
      const ano = Number(a); const v = Number(cons[c]); let p = Number(perd[c]);
      if (!ano || !(v > 0) || !(p > 0)) return;
      if (p < 1) p *= 100;                          // o Painel guarda 0,175 = 17,5%
      porCidade[m.nome][ano] = { consumo: v * 1000, perdas: p };
    });
  }
  const anosCompletos = [...new Set(Object.values(porCidade).flatMap((o) => Object.keys(o).map(Number)))].sort()
    .filter((a) => a >= Number(ctx.desde.slice(0, 4)) && ctx.municipios.every((m) => porCidade[m.nome]?.[a]));
  const ultimoAno = anosCompletos[anosCompletos.length - 1];
  const versao = `anos até ${ultimoAno}; ${anosCompletos.map((a) => Math.round(ctx.municipios.reduce((s, m) => s + porCidade[m.nome][a].consumo, 0) / 1e3)).join('/')}`.slice(0, 120);
  if (!ctx.forcar && ctx.ultimaVersao(FONTE.AGUA_CONSUMO) === versao) return { fonte: FONTE.AGUA_CONSUMO, versao, semNovidade: true, linhas: [], ultimoAno };
  const linhas = [];
  const FT = 'SNIS/SINISA via Painel Saneamento Brasil (Instituto Trata Brasil)';
  for (const a of anosCompletos) {
    const peso = Array.from({ length: 12 }, (_, i) => dias(a, i + 1) * SAZ_AGUA[i]).reduce((s, x) => s + x, 0);
    for (const m of ctx.municipios) {
      const { consumo, perdas } = porCidade[m.nome][a];
      for (let k = 1; k <= 12; k++) {
        const agua = consumo * dias(a, k) * SAZ_AGUA[k - 1] / peso;
        linhas.push({ fonte: FONTE.AGUA_CONSUMO, metrica: 'AGUA_CONSUMIDA', municipio: m.nome, mes: ym(a, k), valor: agua, origem: 'DERIVADO',
          referencia: `SNIS ${a}: consumo anual oficial de ${(consumo / 1e6).toLocaleString('pt-BR', { maximumFractionDigits: 2 })} milhões de m³ distribuído pelos meses (perfil sazonal). ${FT}` });
        linhas.push({ fonte: FONTE.AGUA_PERDAS, metrica: 'AGUA_PRODUZIDA', municipio: m.nome, mes: ym(a, k), valor: agua / (1 - perdas / 100), origem: 'DERIVADO',
          referencia: `SNIS ${a}: índice de perdas oficial de ${perdas.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}% aplicado ao consumo do mês. ${FT}` });
      }
    }
  }
  return { fonte: FONTE.AGUA_CONSUMO, versao, linhas, ultimoAno, detalhe: `anos com as 8 cidades: ${anosCompletos.join(', ')}` };
}

// =============================================================================
// 7) SINISA — resíduos sólidos (oficial ANUAL). O Ministério das Cidades publica um
//    arquivo por ano (zip/rar com planilhas). O robô procura o link do ano mais novo
//    nas páginas do SINISA. Se for .zip ou .xlsx, lê os indicadores IRS1004
//    (kg por pessoa por dia) e IRS3010 (% reciclado). Se for .rar, avisa o
//    administrador para baixar e colocar a planilha na pasta dados_reais/entrada.
// =============================================================================
const SINISA_PAGINAS = [
  'https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/resultados-sinisa',
  'https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/planilhas-de-informacoes-e-indicadores',
];
async function sinisaResiduos(ctx) {
  const links = []; let erro = null; let lidas = 0;
  for (const p of (process.env.SINISA_PAGINAS ? process.env.SINISA_PAGINAS.split(',') : SINISA_PAGINAS)) {
    try {
      const html = await getTexto(p.trim(), { timeout: 45_000 }); lidas++;
      for (const m of html.matchAll(/href="([^"]*RESIDUOS[^"]*?(20\d\d)[^"]*?\.(zip|rar|xlsx))"/gi)) links.push({ url: new URL(m[1], p).href, ano: Number(m[2]), tipo: m[3].toLowerCase() });
    } catch (e) { erro = e; /* tenta a outra página */ }
  }
  if (!lidas && erro) throw erro;
  if (!links.length) throw new Error('SINISA: nenhum arquivo de resíduos encontrado nas páginas do Ministério');
  links.sort((a, b) => b.ano - a.ano || (a.tipo === 'zip' ? -1 : 1));
  const novo = links[0];
  const versao = `ano ${novo.ano} · ${path.basename(novo.url)}`.slice(0, 120);
  if (!ctx.forcar && ctx.ultimaVersao(FONTE.SINISA) === versao) return { fonte: FONTE.SINISA, versao, semNovidade: true, linhas: [], ultimoAno: novo.ano };
  // o ano mais novo publicado já está no banco: nada a fazer
  if (!ctx.forcar && ctx.temAnoOficial?.('RESIDUOS_COLETADOS', novo.ano)) {
    return { fonte: FONTE.SINISA, versao, linhas: [], ultimoAno: novo.ano, detalhe: `o ano mais novo publicado (${novo.ano}) já está no banco` };
  }
  if (novo.tipo === 'rar') {
    return { fonte: FONTE.SINISA, versao, linhas: [], ultimoAno: null, aviso: `O SINISA publicou os resíduos de ${novo.ano} em .rar (${novo.url}). Baixe, abra a planilha de indicadores e coloque os valores na pasta dados_reais/entrada.` };
  }
  const XLSX = require('xlsx');
  let livros = [];
  const buf = await getBuffer(novo.url, { timeout: 10 * 60_000 });
  if (novo.tipo === 'xlsx') livros = [XLSX.read(buf, { type: 'buffer' })];
  else {
    const arq = path.join(os.tmpdir(), `ecocity_sinisa_${Date.now()}.zip`);
    fs.writeFileSync(arq, buf);
    const yauzl = require('yauzl');
    try {
      livros = await new Promise((ok, falha) => {
        const lista = [];
        yauzl.open(arq, { lazyEntries: true }, (e, zip) => {
          if (e) return falha(e);
          zip.readEntry();
          zip.on('entry', (ent) => {
            if (!/indicador.*\.xlsx$/i.test(ent.fileName)) return zip.readEntry();
            zip.openReadStream(ent, (e2, st) => {
              if (e2) return falha(e2);
              const partes = []; st.on('data', (c) => partes.push(c));
              st.on('end', () => { lista.push(XLSX.read(Buffer.concat(partes), { type: 'buffer' })); zip.readEntry(); });
            });
          });
          zip.on('end', () => ok(lista)); zip.on('error', falha);
        });
      });
    } finally { fs.rm(arq, () => {}); }
  }
  const valores = {};          // nome -> { IRS1004, IRS3010 }
  const cods = new Map(ctx.municipios.map((m) => [String(m.codigo_ibge), m.nome]));
  for (const wb of livros) {
    for (const nomeAba of wb.SheetNames) {
      const rows = XLSX.utils.sheet_to_json(wb.Sheets[nomeAba], { header: 1, raw: true });
      const iCab = rows.findIndex((r) => r.some((x) => /IRS1004|IRS3010/.test(String(x))));
      if (iCab < 0) continue;
      const cab = rows[iCab].map((x) => String(x || ''));
      const cIbge = cab.findIndex((x) => /ibge|c[oó]d.*mun/i.test(x));
      const c1004 = cab.findIndex((x) => /IRS1004/.test(x)); const c3010 = cab.findIndex((x) => /IRS3010/.test(x));
      if (cIbge < 0) continue;
      for (const r of rows.slice(iCab + 1)) {
        const cod = String(r[cIbge] || '').replace(/\D/g, '');
        const nome = cods.get(cod) || cods.get([...cods.keys()].find((k) => k.startsWith(cod) && cod.length === 6));
        if (!nome) continue;
        valores[nome] ||= {};
        if (c1004 >= 0 && Number(numBR(r[c1004])) > 0) valores[nome].IRS1004 = numBR(r[c1004]);
        if (c3010 >= 0 && Number(numBR(r[c3010])) >= 0) valores[nome].IRS3010 = numBR(r[c3010]);
      }
    }
  }
  const linhas = [];
  const a = novo.ano;
  for (const m of ctx.municipios) {
    const v = valores[m.nome];
    if (!v || !(v.IRS1004 > 0) || v.IRS1004 > 5 || !(v.IRS3010 >= 0)) continue;   // valor inconsistente fica de fora
    const pop = ctx.populacao(m.nome, a);
    if (!pop) continue;
    for (let k = 1; k <= 12; k++) {
      const col = v.IRS1004 * pop * dias(a, k) / 1000;
      const ref = `SINISA (ano-base ${a}): IRS1004 = ${v.IRS1004} kg/hab/dia e IRS3010 = ${v.IRS3010}% (oficiais) x população IBGE x dias do mês`;
      linhas.push({ fonte: FONTE.SINISA, metrica: 'RESIDUOS_COLETADOS', municipio: m.nome, mes: ym(a, k), valor: col, origem: 'DERIVADO', referencia: ref });
      linhas.push({ fonte: FONTE.SINISA, metrica: 'RESIDUOS_RECICLADOS', municipio: m.nome, mes: ym(a, k), valor: col * v.IRS3010 / 100, origem: 'DERIVADO', referencia: ref });
    }
  }
  return { fonte: FONTE.SINISA, versao, linhas, ultimoAno: linhas.length ? a : null,
    detalhe: `arquivo do ano ${a}: ${Object.keys(valores).length} das 8 cidades encontradas` };
}

// =============================================================================
// 8) Planilhas oficiais deixadas na pasta dados_reais/entrada (CSV com ;)
//      fonte;metrica;municipio;mes;valor[;origem;referencia]
//      3;ENERGIA_CONSUMIDA;Campinas;2024-03;512345;REAL;CPFL mar/2024
// =============================================================================
function planilhasDaPasta() {
  if (!fs.existsSync(ENTRADA)) return [];
  return fs.readdirSync(ENTRADA).filter((f) => /\.csv$/i.test(f)).map((f) => {
    const linhas = fs.readFileSync(path.join(ENTRADA, f), 'utf8').split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    const dados = linhas.filter((l) => !/^fonte;/i.test(l)).map((l) => {
      const [fonte, metrica, municipio, mes, valor, origem, referencia] = l.split(';').map((c) => c.trim());
      return { fonte: Number(fonte), metrica, municipio, mes, valor, origem: origem || 'REAL', referencia: referencia || `Planilha ${f}` };
    });
    return { arquivo: f, dados };
  });
}
function arquivarPlanilha(arquivo) {
  const destino = path.join(ENTRADA, 'processados');
  fs.mkdirSync(destino, { recursive: true });
  fs.renameSync(path.join(ENTRADA, arquivo), path.join(destino, `${Date.now()}_${arquivo}`));
}

module.exports = {
  FONTE, aneelGD, ibgePopulacao, sptrans, sptransSomarMeses, epe, seeg, snisAgua, sinisaResiduos,
  planilhasDaPasta, arquivarPlanilha, ENTRADA, ym, dias, rot,
};
