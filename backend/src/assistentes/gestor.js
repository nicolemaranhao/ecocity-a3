// Conselheiro do GESTOR: conversa para tomada de decisão — diagnóstico, prioridades, simulação "e se",
// opções de ação com impacto esperado, o que já funcionou, riscos e metas. Lembra a cidade e o indicador da conversa.
// Com ANTHROPIC_API_KEY, a IA generativa aprofunda a conversa usando SÓ o pacote de dados do banco.
const E = require('./entender');
const L = require('../linguagem');
const perfis = require('../perfis');
const fontes = require('../fontes');
const copiloto = require('../copiloto_servico');
const { consulta: query } = require('../db');

const n = L.n;
const casas = (v) => (Math.abs(v) < 20 ? 2 : 1);
const SUG = ['Onde devo agir primeiro?', 'E se as perdas de água de Guarulhos caírem para 25%?', 'Que ações melhoram a reciclagem?', 'O que funcionou nas ações já feitas?'];

// Catálogo de ações típicas (faixas de referência de experiências municipais — validar com a equipe técnica)
const ACOES = {
  'AGU-01': [['Campanha de uso consciente + tarifa progressiva', -5, 'baixo', '6–12 meses'], ['Medição individual em prédios', -10, 'médio', '1–2 anos'], ['Kits economizadores em prédios públicos e escolas', -3, 'baixo', '3–6 meses']],
  'AGU-02': [['Setorização da rede e controle de pressão', -12, 'alto', '1–3 anos'], ['Caça-vazamentos com sensores acústicos', -6, 'médio', '6–18 meses'], ['Troca de hidrômetros antigos e combate a fraudes', -5, 'médio', '1–2 anos']],
  'ENE-01': [['LED e telegestão na iluminação pública', -3, 'médio', '1–2 anos'], ['Eficiência energética em prédios públicos', -2, 'médio', '1 ano'], ['Programa de troca de geladeiras para baixa renda', -2, 'médio', '1–2 anos']],
  'ENE-02': [['Solar em prédios públicos (escolas, UBS)', 20, 'médio', '1–2 anos'], ['IPTU Verde (desconto para quem instala solar)', 15, 'baixo', '1–3 anos'], ['Linha de crédito/consórcio solar para pequenos negócios', 10, 'baixo', '1–2 anos']],
  'RES-01': [['Compostagem de orgânicos (feiras, escolas, condomínios)', -8, 'médio', '1–2 anos'], ['Campanha "lixo zero" e fim de descartáveis em órgãos públicos', -3, 'baixo', '6 meses']],
  'RES-02': [['Coleta seletiva porta a porta com cooperativas', 40, 'médio', '1–2 anos'], ['Mais ecopontos/PEVs', 15, 'baixo', '6–12 meses'], ['Contrato por resultado com cooperativas (pagamento por tonelada)', 25, 'médio', '1 ano']],
  'MOB-01': [['Faixas exclusivas de ônibus', 6, 'baixo', '6–12 meses'], ['Integração tarifária e bilhete único temporal', 8, 'médio', '1 ano'], ['Tarifa zero aos domingos', 5, 'médio', '3–6 meses']],
  'MOB-02': [['Renovação da frota com ônibus elétricos', -8, 'alto', '2–4 anos'], ['Faixas exclusivas (ônibus mais rápido = menos carro)', -3, 'baixo', '1 ano'], ['Ciclovias conectadas às estações', -2, 'médio', '1–2 anos']],
};

async function estadoCidade(idMun, mes) {
  return query(`SELECT codigo, indicador, servico, valor, meta, unidade, sentido, score, atingiu_meta, origem, peso_ies
                FROM vw_indicador_desempenho WHERE id_municipio = ? AND ano_mes = ?`, [idMun, mes]);
}
const iesDe = (linhas) => Math.round((linhas.reduce((a, l) => a + l.score * l.peso_ies, 0) / linhas.reduce((a, l) => a + Number(l.peso_ies), 0)) * 100) / 100;

async function simular(cidade, cod, cen, mes) {
  const est = await estadoCidade(cidade.id_municipio, mes);
  const l = est.find((x) => x.codigo === cod);
  const sinal = l.sentido === 'MAIOR_MELHOR' ? 1 : -1;
  const rel = cen.tipo === 'MELHORA' ? sinal * cen.valor : cen.tipo === 'PIORA' ? -sinal * cen.valor : cen.valor;
  const novo = cen.tipo === 'ALVO' ? cen.valor : l.valor * (1 + rel / 100);
  const novoScore = E.score(novo, Number(l.meta), l.sentido);
  const iesAntes = iesDe(est); const iesDepois = iesDe(est.map((x) => (x.codigo === cod ? { ...x, score: novoScore } : x)));
  const rk = await query('SELECT municipio, ies FROM vw_ies_ranking ORDER BY ies DESC');
  const posAntes = rk.findIndex((r) => r.municipio === cidade.nome) + 1;
  const posDepois = rk.filter((r) => r.municipio !== cidade.nome && r.ies > iesDepois).length + 1;
  return { l, novo, novoScore, iesAntes, iesDepois, posAntes, posDepois };
}

function textoSimulacao(cidade, s) {
  const T = L.IND[s.l.codigo];
  return `### Simulação: ${s.l.indicador} em ${cidade.nome}
| | Hoje | No cenário |
|---|---|---|
| ${s.l.indicador} | ${n(s.l.valor, casas(s.l.valor))} ${s.l.unidade} | **${n(s.novo, casas(s.novo))} ${s.l.unidade}** |
| Nota do indicador | ${n(s.l.score, 0)} | **${n(s.novoScore, 0)}** |
| Nota EcoCity da cidade | ${n(s.iesAntes, 1)} | **${n(s.iesDepois, 1)}** (${s.iesDepois - s.iesAntes >= 0 ? '+' : ''}${n(s.iesDepois - s.iesAntes, 1)}) |
| Posição no ranking | ${s.posAntes}º | **${s.posDepois}º** |

${s.novoScore >= 100 ? '✅ Com esse valor a cidade **atinge a meta** deste indicador.' : `⚠️ Ainda fica **fora da meta** (${n(s.l.meta, casas(s.l.meta))} ${s.l.unidade}).`} ${T ? `Para o cidadão: ${T.frase(s.novo).replace(/\*\*/g, '')}` : ''}

_Como ler: a **nota do indicador** mostra quão perto da meta ele está (100 = na meta; cada 1% longe tira 1,5 ponto). A **nota EcoCity** é a média das 8 notas da cidade (0 a 100). Simulação com a mesma regra do banco, mantendo os outros 7 indicadores como estão hoje._`;
}

async function diagnostico(cidade) {
  const sala = await perfis.salaSituacao(cidade?.id_municipio);
  const top = sala.prioridades.slice(0, 3);
  if (!top.length) return { texto: `Todos os indicadores ${cidade ? `de ${cidade.nome}` : ''} estão na meta. 🎉 Sugestão: elevar as metas onde há folga.` };
  const linhas = top.map((p, i) => `**${i + 1}. ${p.indicador} — ${p.municipio}** (${n(p.distancia_pct, 0)}% longe da meta)\n   Hoje: ${n(p.valor, casas(p.valor))} ${p.unidade} · meta ${n(p.meta, casas(p.meta))} · dado ${L.ORIGEM[p.origem].curto}. ${p.populacao ? `Afeta ${p.populacao >= 1e6 ? `${(p.populacao / 1e6).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} milhões` : `${Math.round(p.populacao / 1e3)} mil`} de pessoas.` : ''}`);
  const p0 = top[0]; const op = ACOES[p0.codigo]?.[0];
  return {
    texto: `## Diagnóstico ${cidade ? `de ${cidade.nome}` : 'das 8 cidades'} — ${sala.mesTxt}
Nota EcoCity média **${n(sala.kpis.ies_medio, 1)}** de 100 (média de quão perto da meta estão os 8 números) · **${sala.kpis.pct_metas}%** das metas cumpridas · **${sala.kpis.criticos}** alertas críticos abertos · ${sala.kpis.pct_oficial}% dos valores com base oficial.

### Onde agir primeiro
Ordem por: distância da meta × peso do indicador na nota × população afetada.

${linhas.join('\n\n')}

### Minha recomendação
Começar por **${p0.indicador} em ${p0.municipio}**. ${op ? `A opção com melhor relação custo/prazo costuma ser **${op[0]}** (efeito típico ${op[1] > 0 ? '+' : ''}${op[1]}% em ${op[3]}, custo ${op[2]}).` : ''}

**Próximo passo:** pergunte "e se ${p0.simples ? p0.simples.toLowerCase() : p0.indicador.toLowerCase()} de ${p0.municipio} melhorar 10%?" para ver o efeito na nota.`,
    contexto: { cidade: cidade?.nome || p0.municipio, codigo: p0.codigo },
  };
}

async function opcoes(cidade, cod, mes) {
  const lista = ACOES[cod] || [];
  const [ind] = await query('SELECT nome, sentido FROM indicador WHERE codigo = ?', [cod]);
  let base = '';
  let sims = [];
  if (cidade) {
    const est = await estadoCidade(cidade.id_municipio, mes); const l = est.find((x) => x.codigo === cod);
    base = `Hoje em **${cidade.nome}**: ${n(l.valor, casas(l.valor))} ${l.unidade} (meta ${n(l.meta, casas(l.meta))}, nota ${n(l.score, 0)}).${l.score >= 100 ? ' ✅ **Já está dentro da meta**: as ações abaixo servem para manter o resultado ou ir além (não mudam a nota).' : ''}\n\n`;
    sims = await Promise.all(lista.map((a) => simular(cidade, cod, { tipo: 'REL', valor: a[1] }, mes)));
  }
  const feitas = await query('SELECT titulo, municipio, efeito, variacao_pct, orcamento FROM vw_acoes_resultados WHERE indicador_alvo = ?', [cod]);
  const tab = `| Ação | Efeito típico | Custo | Prazo |${cidade ? ' Nota da cidade depois |' : ''}\n|---|---|---|---|${cidade ? '---|' : ''}\n${lista.map((a, i) => `| ${a[0]} | ${a[1] > 0 ? '+' : ''}${a[1]}% | ${a[2]} | ${a[3]} |${cidade ? ` ${n(sims[i].iesAntes, 1)} → **${n(sims[i].iesDepois, 1)}** |` : ''}`).join('\n')}`;
  const melhor = cidade && sims.length ? lista[sims.reduce((bi, s, i) => (s.iesDepois - s.iesAntes > sims[bi].iesDepois - sims[bi].iesAntes ? i : bi), 0)] : null;
  return {
    texto: `## Opções para melhorar: ${ind.nome}
${base}${tab}

${feitas.length ? `### O que já foi feito nas cidades\n${feitas.map((f) => `- **${f.titulo}** (${f.municipio}, R$ ${n(f.orcamento / 1e6, 1)} mi): ${f.efeito === 'AGUARDANDO_AVALIACAO' ? 'ainda sem avaliação' : `${f.efeito.toLowerCase()} ${n(f.variacao_pct, 1)}%`}`).join('\n')}\n\n` : ''}${melhor ? `### Recomendação\n**${melhor[0]}** tem o maior efeito na nota de ${cidade.nome}. Combine com uma ação de custo baixo para ter resultado rápido enquanto a principal amadurece.\n\n` : ''}_Efeitos típicos são faixas de referência de experiências municipais; valide com a equipe técnica e com um analista antes de decidir._`,
    contexto: { cidade: cidade?.nome, codigo: cod },
  };
}

async function oQueFuncionou() {
  const a = await query('SELECT * FROM vw_acoes_resultados ORDER BY data_inicio');
  const av = a.filter((x) => x.variacao_pct != null);
  const linhas = a.map((x) => `- **${x.titulo}** · ${x.municipio} · ${x.indicador_nome} · R$ ${n(x.orcamento / 1e6, 1)} mi → ${x.efeito === 'AGUARDANDO_AVALIACAO' ? `_${x.status.toLowerCase().replace('_', ' ')}, sem avaliação ainda_` : `**${x.efeito.toLowerCase()}** (${x.variacao_pct > 0 ? '+' : ''}${n(x.variacao_pct, 1)}%)`}`);
  const efic = av.map((x) => ({ ...x, porMi: Math.abs(x.variacao_pct) / (x.orcamento / 1e6) * (x.efeito === 'MELHOROU' ? 1 : -1) })).sort((p, q) => q.porMi - p.porMi);
  return { texto: `## Ações registradas e resultados\n${linhas.join('\n')}\n\n### Custo-efetividade (melhora por R$ 1 milhão)\n${efic.map((x) => `- ${x.titulo}: ${x.porMi >= 0 ? '' : '−'}${n(Math.abs(x.porMi), 2)}% por R$ mi`).join('\n')}\n\n**Leitura:** ${efic[0] ? `"${efic[0].titulo}" teve o melhor retorno por real investido.` : ''} ${av.find((x) => x.efeito === 'PIOROU') ? `"${av.find((x) => x.efeito === 'PIOROU').titulo}" não melhorou o indicador-alvo: vale pedir uma análise antes de repetir o modelo.` : ''}` };
}

async function riscosCidade(cidade, mes) {
  const r = await (require('../ia/alertas')).riscos();
  const x = r.cidades.find((c) => c.municipio === cidade.nome);
  const al = await query(`SELECT a.severidade, a.tipo, a.titulo, a.descricao FROM analise_ia a WHERE a.id_municipio = ? AND a.status IN ('NOVA','EM_ANALISE','VALIDADA')
                          ORDER BY FIELD(a.severidade,'CRITICO','ATENCAO','INFO'), a.gerada_em DESC LIMIT 6`, [cidade.id_municipio]);
  const prev = al.filter((a) => a.tipo === 'PREVISAO');
  return { texto: `## Riscos de ${cidade.nome} — ${L.mesLongo(mes)}\nRisco geral **${x.nivel.toLowerCase()}** (${x.risco}/100).\n\n| Área | Situação | Metas |\n|---|---|---|\n${x.areas.map((a) => `| ${a.servico} | ${L.situacaoArea(Math.round(a.score)).rotulo} (nota ${n(a.score, 0)}) | ${a.metas} |`).join('\n')}\n\n${al.length ? `### Alertas abertos\n${al.map((a) => `- ${a.severidade === 'CRITICO' ? '🔴' : '🟠'} **${a.titulo}** — ${a.descricao}`).join('\n')}` : 'Sem alertas abertos.'}\n\n${prev.length ? `**Atenção:** ${prev.length} previsão(ões) indicam que a situação deve piorar nos próximos 3 meses se nada mudar.` : ''}`,
    contexto: { cidade: cidade.nome } };
}

async function metaRealista(cidade, cod, mes) {
  const s = await query(`SELECT ano_mes, valor FROM vw_indicador_desempenho WHERE id_municipio = ? AND codigo = ? ORDER BY periodo`, [cidade.id_municipio, cod]);
  const [i] = await query('SELECT nome, meta, sentido, u.sigla AS unidade FROM indicador JOIN unidade_medida u USING (id_unidade) WHERE codigo = ?', [cod]);
  const v = s.map((x) => Number(x.valor)); const k = v.length; const ult = v[k - 1]; const ano = v[k - 13] ?? v[0];
  const ritmo = (ult - ano) / ano;
  const melhorRitmo = i.sentido === 'MAIOR_MELHOR' ? Math.max(ritmo, 0.05) : Math.min(ritmo, -0.03);
  const em12 = ult * (1 + melhorRitmo);
  return { texto: `## Meta realista: ${i.nome} em ${cidade.nome}\nHoje: **${n(ult, casas(ult))} ${i.unidade}** · há 12 meses: ${n(ano, casas(ano))} (${ritmo >= 0 ? '+' : ''}${n(ritmo * 100, 1)}%) · meta geral: ${n(i.meta, casas(i.meta))}.\n\nUma meta **ambiciosa mas alcançável para 12 meses** seria **${n(em12, casas(em12))} ${i.unidade}** (${melhorRitmo >= 0 ? '+' : ''}${n(melhorRitmo * 100, 0)}%), ${(i.sentido === 'MAIOR_MELHOR' ? em12 >= i.meta : em12 <= i.meta) ? 'o que já atinge a meta geral.' : 'como degrau intermediário até a meta geral.'}\n\nPara propor: **Metas → + Propor meta** (um analista dá o parecer e outro gestor aprova).`, contexto: { cidade: cidade.nome, codigo: cod } };
}

// ------------------------------------------------------------- IA generativa (opcional) para conversa aberta
async function conversaIA(pergunta, historico, contexto, local) {
  if (!copiloto.temIA()) return null;
  const mes = await perfis.ultimoMes();
  const cid = contexto.cidade ? (await E.todasCidades()).find((c) => c.nome === contexto.cidade) : null;
  const pacote = { mes, cidade: contexto.cidade || 'todas', indicadores: cid ? await estadoCidade(cid.id_municipio, mes) : undefined,
    prioridades: (await perfis.salaSituacao(cid?.id_municipio)).prioridades.slice(0, 5), acoes: await query('SELECT titulo, municipio, indicador_alvo, efeito, variacao_pct, orcamento FROM vw_acoes_resultados'), catalogo: ACOES };
  const sys = `Você é o Conselheiro EcoCity, assessor de gestores públicos de 8 cidades de SP em água, energia, resíduos e mobilidade.
Responda em português do Brasil, em Markdown, de forma aprofundada e prática: diagnóstico, opções com prós e contras, recomendação, riscos/incertezas e próximos passos.
Use SOMENTE os números do pacote de dados e da análise local. Diga quando um dado é estimado. Não invente valores, leis ou orçamentos.`;
  const msgs = [...historico.slice(-8).map((m) => ({ role: m.de === 'eu' ? 'user' : 'assistant', content: String(m.texto).slice(0, 3000) })),
    { role: 'user', content: `${pergunta}\n\n[Análise local do sistema]\n${local}\n\n[Pacote de dados do banco]\n${JSON.stringify(pacote).slice(0, 12000)}` }];
  try {
    const r = await fetch('https://api.anthropic.com/v1/messages', { method: 'POST',
      headers: { 'content-type': 'application/json', 'x-api-key': process.env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({ model: copiloto.MODELO_IA, max_tokens: 2000, system: sys, messages: msgs }), signal: AbortSignal.timeout(40000) });
    if (!r.ok) return null;
    return (await r.json()).content.map((c) => c.text || '').join('').trim();
  } catch { return null; }
}

async function responder(pergunta, usuario, historico = [], contexto = {}) {
  const t = E.norm(pergunta).trim();
  const mes = await perfis.ultimoMes();
  const todas = await E.todasCidades();
  let cids = await E.cidades(t);
  const cods = E.indicadores(t);
  const ctxCidade = cids[0] || todas.find((c) => c.nome === contexto.cidade) || (usuario.municipio ? todas.find((c) => c.id_municipio === usuario.municipio) : null);
  const ctxCod = cods[0] || contexto.codigo;
  let r;

  if (!t || /^(oi|ola|bom dia|boa tarde|boa noite|ajuda|o que voce faz)/.test(t)) {
    r = { texto: `Olá! Sou o **Conselheiro EcoCity** 🧭. Posso:\n- fazer o **diagnóstico** e dizer **onde agir primeiro**;\n- **simular cenários** ("e se as perdas caírem para 25%?") e mostrar o efeito na nota e no ranking;\n- sugerir **ações com impacto, custo e prazo**;\n- mostrar **o que já funcionou** e o custo-efetividade;\n- apontar **riscos** e sugerir **metas realistas**.\n\nEu lembro da cidade e do tema da conversa — pode perguntar em sequência.` };
  } else if (/(e se|simul|cenario|se (a|o|as|os) .* (cair|caire|reduz|aument|subir|chegar)|para \d)/.test(t) && E.cenario(t)) {
    if (!ctxCidade || !ctxCod) r = { texto: 'Para simular preciso da **cidade** e do **indicador**. Ex.: "e se a reciclagem de Santos subir para 8%?"' };
    else { const s = await simular(ctxCidade, ctxCod, E.cenario(t), mes); r = { texto: textoSimulacao(ctxCidade, s), contexto: { cidade: ctxCidade.nome, codigo: ctxCod } }; }
  } else if (/(funcion|resultado|deu certo|ja fizemos|acoes feitas|acoes registradas|custo.?efetiv|retorno)/.test(t)) {
    r = await oQueFuncionou();
  } else if (/(meta realista|que meta|qual meta|definir meta|propor meta|meta para)/.test(t) && ctxCidade && ctxCod) {
    r = await metaRealista(ctxCidade, ctxCod, mes);
  } else if (/(risco|alerta|previs|piorar|perigo)/.test(t) && ctxCidade) {
    r = await riscosCidade(ctxCidade, mes);
  } else if (/(acao|acoes|o que fazer|como melhorar|como reduzir|como aumentar|opcoes|alternativ|investir|medidas|politica)/.test(t) && ctxCod) {
    r = await opcoes(ctxCidade, ctxCod, mes);
  } else if (/(onde agir|prioridade|priorizar|primeiro|diagnost|panorama|situacao|como estamos|resumo|urgente)/.test(t) || cids.length) {
    r = await diagnostico(cids[0] || (/(todas|geral|8 cidades)/.test(t) ? null : ctxCidade));
  } else if (ctxCod) {
    r = await opcoes(ctxCidade, ctxCod, mes);
  } else {
    r = { texto: 'Posso ajudar com **diagnóstico**, **prioridades**, **simulações**, **opções de ação**, **resultados de ações** e **metas**. Cite uma cidade ou um tema para eu aprofundar.' };
  }
  r.contexto = { cidade: r.contexto?.cidade ?? ctxCidade?.nome ?? contexto.cidade ?? null, codigo: r.contexto?.codigo ?? ctxCod ?? null };
  const ia = await conversaIA(pergunta, historico, r.contexto, r.texto);
  if (ia) { r.texto = ia; r.modelo = copiloto.MODELO_IA; }
  // fontes dos números usados
  if (r.contexto.cidade && r.contexto.codigo) {
    const cid = todas.find((c) => c.nome === r.contexto.cidade);
    const f = cid && (await fontes.deUmValor(cid.id_municipio, r.contexto.codigo, mes));
    if (f) r.fontes = f.fontes.filter((x, k, a) => a.findIndex((y) => y.fonte === x.fonte) === k).map((x) => ({ fonte: x.fonte, url: x.url, origem: x.origem }));
  }
  const c = r.contexto;
  r.sugestoes = c.cidade && c.codigo
    ? [`Que ações melhoram isso em ${c.cidade}?`, `E se melhorar 10%?`, `Quais os riscos de ${c.cidade}?`, `Qual meta realista para ${c.cidade}?`]
    : c.cidade ? [`Onde agir primeiro em ${c.cidade}?`, `Quais os riscos de ${c.cidade}?`, 'O que funcionou nas ações já feitas?'] : SUG;
  return r;
}

module.exports = { responder, SUG, ACOES };
