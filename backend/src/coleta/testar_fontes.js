// Testa a conexão com cada fonte oficial SEM gravar nada no banco.
//   npm run testar-fontes                 (todas)
//   npm run testar-fontes -- --sem-aneel  (pula o arquivo grande da ANEEL, ~110 MB)
// Mostra, para cada fonte: se o site respondeu, a versão publicada, quantos números
// vieram e até que mês/ano vão os dados.
require('dotenv').config({ path: require('path').join(__dirname, '..', '..', '.env') });
const C = require('./conectores');

const MUNICIPIOS = [   // usados se o banco não estiver ligado
  ['São Paulo', '3550308'], ['Campinas', '3509502'], ['Guarulhos', '3518800'], ['Santo André', '3547809'],
  ['São José dos Campos', '3549904'], ['Sorocaba', '3552205'], ['Ribeirão Preto', '3543402'], ['Santos', '3548500'],
].map(([nome, codigo_ibge], i) => ({ id_municipio: i + 1, nome, codigo_ibge }));
const POP = { 'São Paulo': 11895578, Campinas: 1185977, Guarulhos: 1345364, 'Santo André': 778711, 'São José dos Campos': 724756, Sorocaba: 757459, 'Ribeirão Preto': 728400, Santos: 429567 };

(async () => {
  const ctx = { forcar: true, municipios: MUNICIPIOS, desde: '2023-01', ultimaVersao: () => null, populacao: (n) => POP[n] };
  const testes = [
    ['SNIS/SINISA – água (Painel Saneamento)', () => C.snisAgua(ctx)],
    ['SEEG – emissões (API GraphQL)', () => C.seeg(ctx)],
    ['SINISA – resíduos (gov.br)', () => C.sinisaResiduos(ctx)],
    ['SPTrans – ônibus de SP (PDF)', () => C.sptrans(ctx)],
    ['EPE – energia do Estado (planilha)', () => C.epe(ctx)],
    ['IBGE – população (API)', async () => { const p = await C.ibgePopulacao(new Date().getFullYear() - 1, MUNICIPIOS); return { versao: `${p.length} cidades`, linhas: [], detalhe: p.map((x) => `${x.codigo_ibge}: ${x.populacao}`).join(', ') }; }],
  ];
  if (!process.argv.includes('--sem-aneel')) testes.push(['ANEEL – energia solar (zip ~110 MB)', () => C.aneelGD(ctx)]);
  let falhas = 0;
  for (const [nome, fn] of testes) {
    const t0 = Date.now();
    process.stdout.write(`\n▶ ${nome} ... `);
    try {
      const r = await fn();
      const meses = [...new Set((r.linhas || []).map((x) => x.mes))].sort();
      console.log(`OK (${Math.round((Date.now() - t0) / 1000)} s)`);
      console.log(`   versão publicada: ${r.versao || '-'}`);
      if (r.detalhe) console.log(`   ${r.detalhe}`);
      if (meses.length) console.log(`   ${r.linhas.length} números, de ${meses[0]} a ${meses[meses.length - 1]}`);
      const ex = (r.linhas || []).filter((x) => x.municipio === 'Campinas' || x.municipio === 'São Paulo').slice(-1)[0];
      if (ex) console.log(`   exemplo: ${ex.municipio} ${ex.mes} ${ex.metrica} = ${Number(ex.valor).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} (${ex.origem})`);
      if (r.aviso) console.log(`   AVISO: ${r.aviso}`);
    } catch (e) { falhas++; console.log(`FALHOU (${Math.round((Date.now() - t0) / 1000)} s)\n   ${e.message}`); }
  }
  console.log(`\n${falhas ? `${falhas} fonte(s) falharam — veja as mensagens acima.` : 'Todas as fontes responderam.'}`);
  process.exit(falhas ? 1 : 0);
})();
