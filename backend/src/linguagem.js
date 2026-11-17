// Traduz os números do EcoCity para frases que qualquer pessoa entende.
// Usado pelo painel do cidadão, pelos chatbots e pelos relatórios.
const n = (v, d = 1) => (v == null || isNaN(v) ? '—' : Number(v).toLocaleString('pt-BR', { minimumFractionDigits: d, maximumFractionDigits: d }));
const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
const mesLongo = (am) => (am ? `${MESES[Number(am.slice(5, 7)) - 1]} de ${am.slice(0, 4)}` : '');
const ORIGEM = {
  REAL: { rotulo: 'Oficial do mês', curto: 'oficial do mês', explica: 'Número publicado pela fonte oficial para este mês.' },
  DERIVADO: { rotulo: 'Oficial do ano', curto: 'oficial do ano', explica: 'A fonte oficial publica o total do ano; o EcoCity divide esse total pelos meses.' },
  ESTIMADO: { rotulo: 'Estimado', curto: 'estimado', explica: 'Não existe número oficial da cidade para este mês. O EcoCity estimou a partir de uma série oficial maior (ex.: energia do Estado de SP).' },
};

// Para cada indicador: nome simples, frase do valor, comparação concreta e por que importa.
const IND = {
  'AGU-01': {
    simples: 'Água usada por pessoa', icone: '💧', unidadeSimples: 'litros por pessoa por dia',
    frase: (v) => `Cada morador usa em média **${n(v, 0)} litros de água por dia**.`,
    compara: (v) => `É como encher **${n(v / 20, 0)} galões de 20 litros** todos os dias.`,
    meta: (m) => `O ideal é até ${n(m, 0)} litros por pessoa por dia.`,
    importa: 'Usar menos água deixa mais água nas represas para os meses secos e diminui a conta.',
  },
  'AGU-02': {
    simples: 'Água perdida no caminho', icone: '🚰', unidadeSimples: '% da água tratada',
    frase: (v) => `De cada 100 litros tratados, **${n(v, 0)} litros se perdem** em vazamentos e ligações irregulares antes de chegar às casas.`,
    compara: (v) => `É água limpa que foi tratada e paga, mas ninguém usou.`,
    meta: (m) => `O ideal é perder no máximo ${n(m, 0)} de cada 100 litros.`,
    importa: 'Menos vazamento = menos necessidade de captar água dos rios e represas.',
  },
  'ENE-01': {
    simples: 'Energia usada por pessoa', icone: '⚡', unidadeSimples: 'kWh por pessoa por mês',
    frase: (v) => `A cidade usa **${n(v, 0)} kWh de energia por morador por mês** (casas, comércio e indústria juntos).`,
    compara: (v) => `Dá para deixar **${n(v / 0.01 / 24 / 30, 0)} lâmpadas LED** (10 W) acesas o mês inteiro, por pessoa.`,
    meta: (m) => `O ideal é até ${n(m, 0)} kWh por pessoa por mês.`,
    importa: 'Gastar menos energia reduz a conta de luz e a necessidade de novas usinas.',
  },
  'ENE-02': {
    simples: 'Energia solar na cidade', icone: '☀️', unidadeSimples: 'watts de painel solar por pessoa',
    frase: (v) => `A cidade tem **${n(v, 0)} watts de painéis solares para cada morador**.`,
    compara: (v) => (v > 0 ? `É como ter **1 painel solar** (550 W) para cada **${n(550 / v, 0)} moradores**.` : 'Ainda quase não há painéis solares.'),
    meta: (m) => `A meta é chegar a ${n(m, 0)} watts por pessoa.`,
    importa: 'Energia solar é limpa e gerada perto de quem usa, sem queimar combustível.',
  },
  'RES-01': {
    simples: 'Lixo gerado por pessoa', icone: '🗑️', unidadeSimples: 'kg por pessoa por dia',
    frase: (v) => `Cada morador gera em média **${n(v, 2)} kg de lixo por dia**.`,
    compara: (v) => `São cerca de **${n(v * 30, 0)} kg por pessoa por mês**.`,
    meta: (m) => `O ideal é até ${n(m, 2)} kg por pessoa por dia.`,
    importa: 'Menos lixo = aterros durando mais e menos caminhões rodando.',
  },
  'RES-02': {
    simples: 'Lixo reciclado', icone: '♻️', unidadeSimples: '% do lixo coletado',
    frase: (v) => `**${n(v, 1)}% do lixo** coletado vai para a reciclagem.`,
    compara: (v) => `De cada 100 kg de lixo, **${n(v, 1)} kg** são reciclados; o resto vai para o aterro.`,
    meta: (m) => `A meta é reciclar pelo menos ${n(m, 0)}%.`,
    importa: 'Reciclar gera renda para cooperativas e economiza matéria-prima.',
  },
  'MOB-01': {
    simples: 'Uso do ônibus', icone: '🚌', unidadeSimples: 'viagens por pessoa por mês',
    frase: (v) => `Cada morador faz em média **${n(v, 1)} viagens de ônibus por mês**.`,
    compara: (v) => `É como se cada pessoa pegasse ônibus **${n(v / 4.3, 1)} vezes por semana**.`,
    meta: (m) => `A meta é chegar a ${n(m, 0)} viagens por pessoa por mês.`,
    importa: 'Mais gente no ônibus = menos carros, menos trânsito e menos poluição.',
  },
  'MOB-02': {
    simples: 'Poluição do transporte', icone: '🌫️', unidadeSimples: 'kg de CO₂ por pessoa por mês',
    frase: (v) => `O transporte da cidade emite **${n(v, 0)} kg de CO₂ por morador por mês**.`,
    compara: (v) => `É o mesmo que cada pessoa dirigir **${n(v / 0.12, 0)} km de carro** no mês.`,
    meta: (m) => `O ideal é até ${n(m, 0)} kg por pessoa por mês.`,
    importa: 'O CO₂ esquenta o planeta; os outros gases do escapamento fazem mal à saúde.',
  },
};

function situacao(score) {
  if (score >= 100) return { nivel: 'BOM', rotulo: 'Dentro da meta', cor: 'verde' };
  if (score >= 70) return { nivel: 'ATENCAO', rotulo: 'Perto da meta', cor: 'laranja' };
  return { nivel: 'CRITICO', rotulo: 'Longe da meta', cor: 'critico' };
}
function situacaoArea(score) {
  if (score >= 85) return { nivel: 'BOM', rotulo: 'Bom' };
  if (score >= 55) return { nivel: 'ATENCAO', rotulo: 'Atenção' };
  return { nivel: 'CRITICO', rotulo: 'Crítico' };
}
function tendencia(atual, anterior, sentido) {
  if (anterior == null || !anterior) return null;
  const var_ = ((atual - anterior) / anterior) * 100;
  if (Math.abs(var_) < 1) return { texto: 'igual ao ano passado', melhor: null, var_ };
  const melhor = sentido === 'MAIOR_MELHOR' ? var_ > 0 : var_ < 0;
  return { texto: `${melhor ? 'melhor' : 'pior'} que há 1 ano (${var_ > 0 ? '+' : ''}${n(var_, 0)}%)`, melhor, var_ };
}

// Alerta da IA em linguagem simples (para o cidadão)
function alertaSimples(a) {
  const T = IND[a.indicador] || { simples: a.indicador };
  const bom = /melhora/i.test(a.titulo);
  const t = bom ? `${T.simples}: está melhorando` : {
    ALERTA_META: `${T.simples} está longe da meta`, TENDENCIA: `${T.simples} piorou em relação ao ano passado`,
    PREVISAO: `${T.simples} pode piorar nos próximos meses`, ANOMALIA: `${T.simples}: valor fora do normal neste mês`,
  }[a.tipo] || a.titulo;
  return { ...a, simples: t, bom, icone: T.icone };
}

module.exports = { alertaSimples, IND, ORIGEM, situacao, situacaoArea, tendencia, n, mesLongo };
