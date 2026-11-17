// Eco para o CIDADÃO: dicas para economizar, como está a SUA cidade, alertas da SUA cidade e de onde vêm os dados.
const E = require('./entender');
const L = require('../linguagem');
const perfis = require('../perfis');
const { consulta: query } = require('../db');

// Valores médios usados nas contas (aproximados, para dar noção de tamanho)
const TARIFA_AGUA = 12;      // R$ por m³ (água + esgoto, faixa residencial típica em SP)
const TARIFA_LUZ = 0.85;     // R$ por kWh (com impostos, média residencial em SP)

const DICAS = {
  agua: { titulo: '💧 Como economizar água', itens: [
    ['Banho de 5 minutos', 'Cada minuto a menos no chuveiro economiza cerca de 9 litros. Passar de 15 para 5 minutos economiza ~90 litros por banho.'],
    ['Torneira fechada', 'Fechar a torneira ao escovar os dentes economiza ~12 litros por escovação.'],
    ['Louça de molho', 'Ensaboar tudo com a torneira fechada e enxaguar de uma vez economiza ~100 litros por lavagem.'],
    ['Vassoura no lugar da mangueira', 'Lavar a calçada com mangueira por 15 minutos gasta ~280 litros. Use vassoura e balde.'],
    ['Caça-vazamento', 'Feche todas as torneiras e veja se o relógio d\'água continua girando. Uma descarga vazando perde até 140 litros por dia.'],
    ['Reaproveite', 'A água da máquina de lavar serve para lavar o quintal e o carro.'],
  ], conta: () => `Economizar 50 litros por dia em casa dá **1,5 m³ por mês**, cerca de **R$ ${L.n(1.5 * TARIFA_AGUA, 0)} a menos na conta** (valor aproximado).` },
  energia: { titulo: '⚡ Como economizar energia', itens: [
    ['Chuveiro no "verão"', 'O chuveiro elétrico é o campeão da conta. Na posição verão ele gasta ~30% menos. Um banho de 10 min no inverno (5.500 W) custa ~R$ 0,78.'],
    ['Troque por LED', 'Uma lâmpada LED de 9 W ilumina como uma incandescente de 60 W e gasta 85% menos.'],
    ['Tire da tomada', 'Aparelhos em espera (TV, micro-ondas, carregadores) somam até 12% da conta.'],
    ['Geladeira bem usada', 'Não guarde comida quente, confira a borracha da porta e deixe 15 cm de espaço atrás.'],
    ['Ar-condicionado em 23 °C', 'Cada grau a menos aumenta ~8% o consumo. Feche portas e janelas.'],
    ['Junte a roupa', 'Use a máquina de lavar e o ferro de passar com carga cheia, poucas vezes por semana.'],
  ], conta: () => `Reduzir 5 minutos de chuveiro por dia (5.500 W) economiza **~14 kWh por mês**, cerca de **R$ ${L.n(13.75 * TARIFA_LUZ, 0)}** (valor aproximado).` },
  lixo: { titulo: '♻️ Como reduzir e separar o lixo', itens: [
    ['Separe em 2', 'Seco (plástico, papel, metal, vidro, limpos) e úmido (restos de comida). Só isso já ajuda as cooperativas.'],
    ['Lave rapidinho', 'Embalagem com resto de comida estraga o reciclável. Use a água da louça.'],
    ['Composte', 'Metade do lixo de casa é orgânico. Uma composteira pequena transforma isso em adubo.'],
    ['Leve aos ecopontos', 'Óleo de cozinha, pilhas, eletrônicos e móveis vão para os ecopontos da prefeitura, não para o lixo comum.'],
    ['Evite descartáveis', 'Sacola retornável, garrafinha e marmita reduzem muito o lixo do mês.'],
  ], conta: () => 'Uma família de 3 pessoas que separa os recicláveis tira cerca de **15 kg por mês** do aterro.' },
  transporte: { titulo: '🚌 Como se locomover poluindo menos', itens: [
    ['Ônibus e metrô', 'Por pessoa, o ônibus emite cerca de 1/3 do CO₂ de um carro com uma pessoa só.'],
    ['Até 3 km, vá a pé ou de bike', 'É mais rápido do que parece e não polui nada.'],
    ['Carona', 'Dividir o carro com mais 2 pessoas divide também o combustível e a poluição.'],
    ['Calibre os pneus', 'Pneu murcho aumenta o consumo do carro em até 3%.'],
  ], conta: () => 'Trocar 10 km de carro por dia pelo ônibus evita cerca de **25 kg de CO₂ por mês** e economiza ~**R$ 150** de combustível (valores aproximados).' },
};
const TEMA = [['agua', /(agua|banho|chuveiro|torneira|descarga|vazament)/], ['energia', /(energia|luz|eletric|lampada|geladeira|ar.condicionado|tomada)/],
  ['lixo', /(lixo|recicl|residuo|compost|separar|ecoponto)/], ['transporte', /(transporte|onibus|carro|bicicleta|bike|carona|poluic|co2)/]];

const SUG = ['Como economizar água?', 'Como diminuir a conta de luz?', 'Como está minha cidade?', 'De onde vêm os dados?'];
const fonteTxt = (f) => (f ? `\n\n📎 **Fonte:** ${f.fontes.map((x) => `${x.fonte}`).filter((v, i, a) => a.indexOf(v) === i).join(' · ')} — ${f.origemTxt.toLowerCase()}.` : '');

async function responder(pergunta, usuario) {
  const t = E.norm(pergunta).trim();
  const idMun = usuario.municipio;
  if (!idMun) return { texto: 'Seu cadastro não tem cidade. Atualize o cadastro para eu mostrar os dados da sua cidade.', sugestoes: SUG };
  const c = perfis.paraCidadao(await perfis.minhaCidade(idMun));   // sem nota e sem meta para o cidadão
  const nome = c.municipio.nome;

  if (!t || /^(oi|ola|bom dia|boa tarde|boa noite|e ai|hey|ajuda)\b/.test(t))
    return { texto: `Oi! Eu sou o **Eco** 🌱. Posso te ajudar a **economizar água e energia em casa**, contar **como está ${nome}**, mostrar os **alertas da sua cidade** e explicar **de onde vem cada número**.`, sugestoes: SUG };

  if (/(calculadora|simular minha casa|quanto eu gasto|quanto gasto)/.test(t))
    return { texto: 'Na página **Economize em casa** você mexe nos controles (pessoas, minutos de banho, aparelhos…) e vê quanto sua casa gasta de água, luz, lixo e transporte, e quanto dá para economizar.', link: { texto: 'Abrir calculadora', href: '#/app/economize' }, sugestoes: SUG };

  // De onde vêm os dados (com o tema citado ou geral)
  if (/(fonte|de onde|origem|oficial|confiavel|confiar|estimad|verdade)/.test(t)) {
    const cods = E.indicadores(t);
    const lista = (cods.length ? c.indicadores.filter((i) => cods.includes(i.codigo)) : c.indicadores);
    const linhas = lista.map((i) => `• **${i.simples}** — ${[...new Set(i.fonte.fontes.map((f) => f.fonte))].join(' + ')} · _${i.fonte.origemTxt.toLowerCase()}_`).join('\n');
    const exemplo = lista[0]?.fonte.fontes.find((f) => f.metrica !== 'POPULACAO');
    return { texto: `Dados de **${nome}** em ${c.mesTxt}:\n${linhas}\n\n**Oficial do mês** = publicado pela fonte para o mês. **Oficial do ano** = total oficial do ano dividido pelos meses. **Estimado** = não há número oficial da cidade; o EcoCity estima a partir de uma série oficial maior.${exemplo ? `\n\nExemplo (${lista[0].simples}): _${exemplo.referencia}_` : ''}`,
      fontes: lista.flatMap((i) => i.fonte.fontes).filter((f, k, a) => a.findIndex((x) => x.fonte === f.fonte) === k).map((f) => ({ fonte: f.fonte, url: f.url })),
      sugestoes: ['Como está minha cidade?', 'Como economizar água?'] };
  }

  // Dicas para economizar
  const tema = TEMA.find(([, re]) => re.test(t));
  if (tema && /(econom|gastar menos|reduz|diminu|dica|como (eu )?posso|ajudar|conta|separar|o que fazer|poupar)/.test(t)) {
    const d = DICAS[tema[0]];
    const ind = { agua: 'AGU-01', energia: 'ENE-01', lixo: 'RES-02', transporte: 'MOB-01' }[tema[0]];
    const i = c.indicadores.find((x) => x.codigo === ind);
    return { texto: `**${d.titulo}**\n\n${d.itens.map(([a, b]) => `• **${a}:** ${b}`).join('\n')}\n\n💰 ${d.conta()}${i ? `\n\nEm ${nome}: ${i.frase} ${i.mediaTxt}` : ''}${fonteTxt(i?.fonte)}`,
      sugestoes: ['Abrir a calculadora de economia', ...SUG.filter((s) => !s.toLowerCase().includes(tema[0])).slice(0, 2)], link: { texto: 'Abrir calculadora', href: '#/app/economize' } };
  }

  // Alertas e riscos (só da cidade do usuário)
  if (/(risco|alerta|perigo|problema|preocup)/.test(t)) {
    const outras = (await E.cidades(t)).filter((x) => x.id_municipio !== idMun);
    const aviso = outras.length ? `Eu mostro os alertas da **sua** cidade (${nome}).\n\n` : '';
    if (!c.alertas.length) return { texto: `${aviso}Boa notícia: não há alertas abertos para ${nome} agora. ✅`, sugestoes: SUG };
    const top = c.alertas.slice(0, 5).map((a) => `• ${a.bom ? '🟢' : a.severidade === 'CRITICO' ? '🔴' : '🟠'} **${a.simples}** — ${a.explicacao}`).join('\n');
    const pior = [...c.areas].sort((a, b) => a.score - b.score)[0];
    return { texto: `${aviso}**Alertas de ${nome}** (${c.mesTxt}):\n${top}\n\nA área que mais precisa de atenção é **${pior.servico}**. Quer dicas do que você pode fazer em casa?`,
      sugestoes: [`Como economizar ${pior.servico === 'Água' ? 'água' : pior.servico === 'Energia' ? 'energia' : pior.servico === 'Resíduos' ? 'separando o lixo' : 'no transporte'}?`, 'De onde vêm os dados?'] };
  }

  // Um indicador específico da cidade
  const cods = E.indicadores(t);
  if (cods.length) {
    const lista = c.indicadores.filter((i) => cods.includes(i.codigo));
    const txt = lista.map((i) => `${i.icone} **${i.simples}** — ${i.frase} ${i.compara} ${i.mediaTxt} ${i.tendencia ? `Está ${i.tendencia.texto}.` : ''}${fonteTxt(i.fonte)}`).join('\n\n');
    return { texto: `Em **${nome}** (${c.mesTxt}):\n\n${txt}`, sugestoes: ['Como economizar água?', 'Como diminuir a conta de luz?', 'De onde vêm os dados?'] };
  }

  // Outra cidade citada: compara os dados das duas (sem nota)
  const cits = await E.cidades(t);
  if (cits.length && cits[0].id_municipio !== idMun) {
    const o = perfis.paraCidadao(await perfis.minhaCidade(cits[0].id_municipio));
    const linhas = c.indicadores.map((i) => { const j = o.indicadores.find((x) => x.codigo === i.codigo); const melhor = i.sentido === 'MAIOR_MELHOR' ? i.valor > j.valor : i.valor < j.valor;
      return `• **${i.simples}:** ${nome} ${L.n(i.valor, i.valor < 20 ? 2 : 0)} × ${o.municipio.nome} ${L.n(j.valor, j.valor < 20 ? 2 : 0)} ${i.unidade} ${melhor ? '(sua cidade está melhor)' : ''}`; });
    return { texto: `**${nome}** × **${o.municipio.nome}** em ${c.mesTxt}:\n${linhas.join('\n')}`, sugestoes: SUG };
  }

  // Como está a minha cidade (resposta padrão)
  if (/(minha cidade|como esta|nota|ranking|lugar|posicao|resumo|situacao|cidade)/.test(t)) {
    const bons = c.indicadores.filter((i) => i.situacao.nivel === 'BOM');
    const ruins = c.indicadores.filter((i) => i.situacao.nivel === 'CRITICO');
    return { texto: `**${nome}** em ${c.mesTxt}, comparada com as outras 7 cidades:\n\n${bons.length ? `✅ **Melhor que a média:** ${bons.map((i) => i.simples.toLowerCase()).join(', ')}.\n` : ''}${ruins.length ? `⚠️ **Pior que a média:** ${ruins.map((i) => i.simples.toLowerCase()).join(', ')}.\n` : ''}${ruins.slice(0, 2).map((i) => `\n• ${i.frase} ${i.mediaTxt}`).join('')}`,
      sugestoes: ['Quais os alertas da minha cidade?', 'Como economizar água?', 'De onde vêm os dados?'] };
  }

  return { texto: 'Posso ajudar com: **dicas para economizar** (água, luz, lixo, transporte), **como está sua cidade**, **alertas** e **de onde vêm os dados**. Tente uma das sugestões 👇', sugestoes: SUG };
}

module.exports = { responder, SUG, DICAS };
