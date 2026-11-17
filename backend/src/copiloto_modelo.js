/* =====================================================================
 * Copiloto EcoCity — motor de relatórios e de perguntas em português
 * ---------------------------------------------------------------------
 * Usado em dois lugares (mesmo código):
 *   - na API (Node.js), que busca os dados no MySQL e grava o resultado;
 *   - no navegador, no modo demonstração (sem servidor).
 *
 * Regras de ouro:
 *   1. Só escreve com os números que recebe do banco (não inventa dados).
 *   2. Todo número diz se é oficial, calculado de oficial ou estimado.
 *   3. As perguntas viram SELECT apenas nas views liberadas; qualquer outra
 *      coisa é bloqueada aqui E no banco (usuário ecocity_ia só lê).
 *   4. O relatório nasce como RASCUNHO e só é publicado após aprovação humana.
 * ===================================================================== */
(function (raiz, fabrica) {
  if (typeof module === 'object' && module.exports) module.exports = fabrica();
  else raiz.Copiloto = fabrica();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const MODELO_LOCAL = 'copiloto-local-v1';
  const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  const MESES_LONGOS = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

  const rotulo = (am) => `${MESES[+am.slice(5, 7) - 1]}/${am.slice(0, 4)}`;
  const rotuloLongo = (am) => `${MESES_LONGOS[+am.slice(5, 7) - 1]} de ${am.slice(0, 4)}`;
  const num = (v, casas = 1) => Number(v).toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas });
  const casasDe = (cod) => (cod === 'RES-01' ? 2 : cod === 'ENE-01' || cod === 'AGU-01' || cod === 'MOB-02' || cod === 'ENE-02' ? 0 : 1);
  const fmt = (cod, v) => num(v, casasDe(cod));
  const ORIGEM_TXT = { REAL: 'oficial', DERIVADO: 'oficial do ano (total anual dividido pelos meses)', ESTIMADO: 'estimado' };

  // ---------------- textos por indicador ----------------
  const IND = {
    'AGU-01': {
      simples: (v) => `Cada pessoa usou, em média, **${v} litros de água por dia**.`, ideal: 'até 150 litros',
      dica: 'Banhos de até 5 minutos e torneira fechada ao escovar os dentes economizam dezenas de litros por dia.',
      rec: 'campanhas de consumo consciente junto com medição individualizada em prédios e tarifa por faixa de consumo',
    },
    'AGU-02': {
      simples: (v) => `De cada 100 litros de água tratada, **${v} se perderam no caminho** até as casas (vazamentos e ligações irregulares).`, ideal: 'até 25 litros',
      dica: 'Viu água vazando na rua? Avise a empresa de água da sua cidade: cada vazamento consertado conta.',
      rec: 'programa de redução de perdas com setorização da rede, busca de vazamentos não visíveis, troca de hidrômetros e combate a fraudes',
    },
    'ENE-01': {
      simples: (v) => `A cidade consumiu **${v} kWh de energia por morador** no mês (casas, comércio e indústria).`, ideal: 'até 220 kWh',
      dica: 'Lâmpadas LED e aparelhos com selo Procel A gastam bem menos energia.',
      rec: 'eficiência energética em prédios públicos, iluminação pública LED e incentivo à modernização de equipamentos',
    },
    'ENE-02': {
      simples: (v) => `Há **${v} watts de energia solar** (e outras fontes próprias) instalados para cada morador.`, ideal: '100 watts ou mais',
      dica: 'Condomínios e pequenos comércios podem gerar a própria energia com painéis solares e reduzir a conta.',
      rec: 'painéis solares em escolas e postos de saúde, incentivo à geração compartilhada e aprovação mais rápida de projetos',
    },
    'RES-01': {
      simples: (v) => `Cada pessoa gerou **${v} kg de lixo por dia**.`, ideal: 'até 0,95 kg',
      dica: 'Restos de comida podem virar adubo na compostagem. Planejar as compras também evita desperdício.',
      rec: 'redução na fonte com compostagem de orgânicos, cobrança dos grandes geradores e combate ao desperdício de alimentos',
    },
    'RES-02': {
      simples: (v) => `**${v}% do lixo** coletado foi para a reciclagem.`, ideal: '10% ou mais',
      dica: 'Separe papel, plástico, vidro e metal limpos e entregue na coleta seletiva ou num ecoponto.',
      rec: 'coleta seletiva porta a porta, mais ecopontos e contratos com cooperativas com metas por bairro',
    },
    'MOB-01': {
      simples: (v) => `Cada morador fez, em média, **${v} viagens de ônibus** no mês.`, ideal: '15 ou mais',
      dica: 'Trocar o carro pelo ônibus, mesmo alguns dias por semana, reduz o trânsito e a poluição.',
      rec: 'faixas exclusivas, integração tarifária e mais frequência nas linhas mais cheias',
    },
    'MOB-02': {
      simples: (v) => `O transporte emitiu **${v} kg de gás carbônico por morador** no mês.`, ideal: 'até 65 kg',
      dica: 'Caminhar, pedalar, dar carona e usar ônibus diminuem a poluição do ar.',
      rec: 'eletrificação da frota de ônibus, ciclovias conectadas e organização da logística de entregas',
    },
  };

  const atingiu = (r) => (r.sentido === 'MAIOR_MELHOR' ? r.valor >= r.meta : r.valor <= r.meta);
  const melhorou = (sentido, antes, depois) => (sentido === 'MAIOR_MELHOR' ? depois > antes : depois < antes);
  const media = (xs) => xs.reduce((a, b) => a + b, 0) / (xs.length || 1);

  // ======================================================================
  //  1) RELATÓRIOS
  // ======================================================================
  /**
   * @param {object} p
   *   linhas: [{id_municipio, municipio, codigo, indicador, servico, ano_mes, valor, meta, unidade, sentido, score, atingiu_meta, origem}]
   *   ies:    [{id_municipio, municipio, ano_mes, ies}]
   *   inicio, fim: 'AAAA-MM';  publico: 'GESTOR' | 'CIDADAO';  acoes (opcional): linhas de vw_acoes_resultados
   */
  function gerarRelatorio(p) {
    const linhas = p.linhas.map((r) => ({ ...r, valor: +r.valor, meta: +r.meta, score: +r.score }));
    if (!linhas.length) throw new Error('Não há dados para as cidades e meses escolhidos.');
    const cidades = [...new Set(linhas.map((r) => r.municipio))];
    const meses = [...new Set(linhas.map((r) => r.ano_mes))].sort();
    const de = meses[0], ate = meses[meses.length - 1];
    const codigos = [...new Set(linhas.map((r) => r.codigo))].sort();

    // ---- números usados (vão para relatorio_ia.dados_usados) ----
    const dados = { municipios: cidades, periodo: { de, ate, meses: meses.length }, indicadores: {}, ies: {} };
    const cont = { REAL: 0, DERIVADO: 0, ESTIMADO: 0 };
    for (const r of linhas) cont[r.origem] = (cont[r.origem] || 0) + 1;
    const pctOficial = Math.round((100 * (cont.REAL + cont.DERIVADO)) / linhas.length * 10) / 10;

    const resumo = {};   // resumo[cidade][codigo]
    for (const c of cidades) {
      resumo[c] = {};
      for (const cod of codigos) {
        const s = linhas.filter((r) => r.municipio === c && r.codigo === cod).sort((a, b) => a.ano_mes.localeCompare(b.ano_mes));
        if (!s.length) continue;
        const k = Math.min(3, Math.floor(s.length / 2)) || 1;
        const ini = media(s.slice(0, k).map((r) => r.valor)), fim = media(s.slice(-k).map((r) => r.valor));
        const o = { REAL: 0, DERIVADO: 0, ESTIMADO: 0 };
        s.forEach((r) => o[r.origem]++);
        resumo[c][cod] = {
          nome: s[0].indicador, unidade: s[0].unidade, meta: s[0].meta, sentido: s[0].sentido, servico: s[0].servico,
          media: media(s.map((r) => r.valor)), ultimo: s[s.length - 1].valor, ultimoMes: s[s.length - 1].ano_mes,
          inicio: ini, fim, variacao: ini ? ((fim - ini) / Math.abs(ini)) * 100 : 0,
          mesesNaMeta: s.filter(atingiu).length, meses: s.length, scoreMedio: media(s.map((r) => r.score)), origem: o,
        };
      }
      dados.indicadores[c] = Object.fromEntries(Object.entries(resumo[c]).map(([cod, x]) => [cod, {
        media: +x.media.toFixed(4), ultimo: +x.ultimo.toFixed(4), meta: x.meta, meses_na_meta: x.mesesNaMeta, meses: x.meses, origem: x.origem,
      }]));
      const iesC = (p.ies || []).filter((r) => r.municipio === c).sort((a, b) => a.ano_mes.localeCompare(b.ano_mes));
      if (iesC.length) dados.ies[c] = { inicio: +iesC[0].ies, fim: +iesC[iesC.length - 1].ies, media: +media(iesC.map((r) => +r.ies)).toFixed(2) };
    }

    const periodoTxt = de === ate ? rotuloLongo(de) : `${rotulo(de)} a ${rotulo(ate)}`;
    const nomeCidades = cidades.length === 1 ? cidades[0] : cidades.slice(0, -1).join(', ') + ' e ' + cidades[cidades.length - 1];
    const titulo = p.publico === 'CIDADAO'
      ? `Como está ${nomeCidades} — ${periodoTxt}`
      : `Relatório de sustentabilidade urbana — ${nomeCidades} — ${periodoTxt}`;

    const md = p.publico === 'CIDADAO'
      ? textoCidadao({ cidades, resumo, dados, periodoTxt, pctOficial, codigos })
      : textoGestor({ cidades, resumo, dados, periodoTxt, pctOficial, cont, codigos, acoes: p.acoes || [], meses });

    return {
      titulo, tipo: cidades.length > 1 ? 'COMPARATIVO' : 'MUNICIPIO', publico: p.publico,
      inicio: de, fim: ate, conteudo: md, dadosUsados: dados, pctOficial, modelo: MODELO_LOCAL,
    };
  }

  function textoGestor({ cidades, resumo, dados, periodoTxt, pctOficial, cont, codigos, acoes, meses }) {
    const L = [];
    L.push(`## Resumo executivo`);
    const iesTxt = cidades.filter((c) => dados.ies[c]).map((c) => {
      const x = dados.ies[c], d = x.fim - x.inicio;
      return `**${c}**: índice EcoCity médio de **${num(x.media, 1)}** no período (${d >= 0 ? 'subiu' : 'caiu'} ${num(Math.abs(d), 1)} ponto${Math.abs(d) >= 2 ? 's' : ''} do primeiro ao último mês)`;
    });
    if (iesTxt.length) L.push(iesTxt.map((t) => `- ${t}`).join('\n'));
    // pontos fortes e fracos
    const todos = [];
    for (const c of cidades) for (const cod of codigos) if (resumo[c][cod]) todos.push({ c, cod, ...resumo[c][cod] });
    const fortes = todos.filter((x) => x.mesesNaMeta === x.meses).sort((a, b) => b.scoreMedio - a.scoreMedio).slice(0, 3);
    const fracos = todos.filter((x) => x.mesesNaMeta === 0).sort((a, b) => a.scoreMedio - b.scoreMedio).slice(0, 4);
    if (fortes.length) L.push(`\n**Dentro da meta em todos os meses:** ${fortes.map((x) => `${x.nome.toLowerCase()} em ${x.c} (média ${fmt(x.cod, x.media)} ${x.unidade})`).join('; ')}.`);
    if (fracos.length) L.push(`\n**Fora da meta em todos os meses:** ${fracos.map((x) => `${x.nome.toLowerCase()} em ${x.c} (média ${fmt(x.cod, x.media)} ${x.unidade}; meta ${fmt(x.cod, x.meta)})`).join('; ')}.`);

    if (cidades.length > 1 && Object.keys(dados.ies).length > 1) {
      L.push(`\n## Comparação entre as cidades`);
      L.push(`| Posição | Cidade | Índice médio | Primeiro mês | Último mês |\n|---|---|---|---|---|`);
      Object.entries(dados.ies).sort((a, b) => b[1].media - a[1].media).forEach(([c, x], i) =>
        L.push(`| ${i + 1}º | ${c} | ${num(x.media, 1)} | ${num(x.inicio, 1)} | ${num(x.fim, 1)} |`));
    }

    L.push(`\n## Indicadores no período (${periodoTxt})`);
    for (const cod of codigos) {
      const x0 = Object.values(resumo).find((r) => r[cod]);
      if (!x0) continue;
      const r0 = x0[cod];
      L.push(`\n### ${r0.nome} (${r0.unidade}) — meta: ${r0.sentido === 'MAIOR_MELHOR' ? 'no mínimo' : 'no máximo'} ${fmt(cod, r0.meta)}`);
      for (const c of cidades) {
        const x = resumo[c][cod];
        if (!x) continue;
        const dir = Math.abs(x.variacao) < 2 ? 'ficou estável' : `${melhorou(x.sentido, x.inicio, x.fim) ? 'melhorou' : 'piorou'} ${num(Math.abs(x.variacao), 1)}%`;
        const base = x.origem.ESTIMADO === x.meses ? ' _(dados estimados)_' : x.origem.ESTIMADO > 0 ? ` _(${x.origem.REAL + x.origem.DERIVADO} de ${x.meses} meses com base oficial)_` : ' _(base oficial)_';
        L.push(`- **${c}**: média ${fmt(cod, x.media)}, último mês ${fmt(cod, x.ultimo)} (${rotulo(x.ultimoMes)}); ${dir} do início ao fim do período; na meta em ${x.mesesNaMeta} de ${x.meses} meses.${base}`);
      }
    }

    L.push(`\n## Recomendações`);
    const prioridades = todos.filter((x) => x.mesesNaMeta < x.meses / 2).sort((a, b) => a.scoreMedio - b.scoreMedio);
    const vistos = new Set();
    let n = 0;
    for (const x of prioridades) {
      if (vistos.has(x.cod) || n >= 4) continue;
      vistos.add(x.cod); n++;
      const cid = prioridades.filter((y) => y.cod === x.cod).map((y) => y.c);
      const exemplo = acoes.find((a) => a.indicador_alvo === x.cod && a.efeito === 'MELHOROU');
      L.push(`${n}. **${x.nome}** (${cid.join(', ')}): ${IND[x.cod].rec}.` +
        (exemplo ? ` Referência no próprio sistema: a ação "${exemplo.titulo}" em ${exemplo.municipio} teve variação de ${num(exemplo.variacao_pct, 1)}% no indicador.` : ''));
    }
    if (!n) L.push('Todos os indicadores estiveram na meta na maior parte do período. Recomenda-se manter o monitoramento mensal.');

    L.push(`\n## Sobre os dados deste relatório`);
    L.push(`- ${meses.length} ${meses.length > 1 ? 'meses analisados' : 'mês analisado'}, ${cidades.length} ${cidades.length > 1 ? 'cidades' : 'cidade'}, ${cont.REAL + cont.DERIVADO + cont.ESTIMADO} valores de indicadores.`);
    L.push(`- **${num(pctOficial, 1)}% com base oficial**: ${cont.REAL} oficiais do mês, ${cont.DERIVADO} oficiais do ano (total anual dividido pelos meses) e ${cont.ESTIMADO} estimados pela equipe.`);
    L.push(`- Texto gerado pelo Copiloto EcoCity apenas com números do banco de dados (view vw_indicador_desempenho). Precisa ser revisado e aprovado por um gestor antes de ser publicado.`);
    return L.join('\n');
  }

  function textoCidadao({ cidades, resumo, dados, periodoTxt, pctOficial, codigos }) {
    const L = [];
    for (const c of cidades) {
      if (cidades.length > 1) L.push(`## ${c}`);
      const x = dados.ies[c];
      if (x) {
        const cl = x.media >= 85 ? 'excelente' : x.media >= 70 ? 'boa' : x.media >= 55 ? 'regular' : 'que precisa melhorar';
        L.push(`No período (${periodoTxt}), a nota de sustentabilidade de ${c} foi **${num(x.media, 0)} de 100**, uma situação **${cl}**.`);
      }
      const bons = [], ruins = [];
      for (const cod of codigos) {
        const r = resumo[c][cod];
        if (!r) continue;
        (r.mesesNaMeta >= r.meses / 2 ? bons : ruins).push({ cod, ...r });
      }
      if (bons.length) {
        L.push(`\n**O que está indo bem**`);
        bons.forEach((r) => L.push(`- ${IND[r.cod].simples(fmt(r.cod, r.media))} O ideal é ${IND[r.cod].ideal}.`));
      }
      if (ruins.length) {
        L.push(`\n**O que precisa melhorar**`);
        ruins.forEach((r) => L.push(`- ${IND[r.cod].simples(fmt(r.cod, r.media))} O ideal é ${IND[r.cod].ideal}.`));
        L.push(`\n**Como você pode ajudar**`);
        ruins.slice(0, 3).forEach((r) => L.push(`- ${IND[r.cod].dica}`));
      }
      L.push('');
    }
    L.push(`_De onde vêm os números: ${num(pctOficial, 0)}% têm base em dados oficiais (IBGE, ANEEL, SPTrans, SNIS, SINISA, SEEG e Prefeitura de São Paulo). O restante é estimativa da equipe EcoCity. Texto escrito pelo Copiloto EcoCity e revisado por um gestor público._`);
    return L.join('\n');
  }

  // ======================================================================
  //  2) PERGUNTAS EM PORTUGUÊS -> SQL SOMENTE LEITURA
  // ======================================================================
  const VIEWS_LIBERADAS = ['vw_indicador_desempenho', 'vw_ies_municipio_mensal', 'vw_ies_ranking', 'vw_origem_dados',
    'vw_acoes_resultados', 'vw_dw_tendencia_servico', 'vw_dw_cidade_indicador'];

  const PALAVRAS_PROIBIDAS = /\b(insert|update|delete|drop|alter|create|grant|revoke|truncate|replace|rename|call|execute|prepare|handler|load_file|outfile|dumpfile|sleep|benchmark|information_schema|performance_schema|mysql\.|sys\.)\b/i;

  /** Valida um SQL antes de executar. Retorna {ok, sql, motivo}. */
  function validarSQL(sqlBruto) {
    let sql = String(sqlBruto || '').trim().replace(/;\s*$/, '');
    if (!/^select\b/i.test(sql)) return { ok: false, motivo: 'Só consultas de leitura (SELECT) são permitidas.' };
    if (sql.includes(';')) return { ok: false, motivo: 'Mais de um comando na mesma consulta não é permitido.' };
    if (/--|\/\*|#/.test(sql)) return { ok: false, motivo: 'Comentários dentro da consulta não são permitidos.' };
    const proib = sql.match(PALAVRAS_PROIBIDAS);
    if (proib) return { ok: false, motivo: `Comando ou recurso não permitido: ${proib[0].toUpperCase()}.` };
    const tabelas = [...sql.matchAll(/\b(?:from|join)\s+`?([a-z_][a-z0-9_]*)`?/gi)].map((m) => m[1].toLowerCase());
    const fora = tabelas.filter((t) => !VIEWS_LIBERADAS.includes(t));
    if (!tabelas.length) return { ok: false, motivo: 'A consulta precisa ler uma das views liberadas.' };
    if (fora.length) return { ok: false, motivo: `Acesso negado a: ${[...new Set(fora)].join(', ')}. O Copiloto só lê as views de indicadores.` };
    const lim = sql.match(/\blimit\s+(\d+)\s*$/i);
    if (!lim) sql += ' LIMIT 200';
    else if (+lim[1] > 200) sql = sql.replace(/\blimit\s+\d+\s*$/i, 'LIMIT 200');
    sql = sql.replace(/^select\b/i, 'SELECT /*+ MAX_EXECUTION_TIME(3000) */');
    return { ok: true, sql };
  }

  // vocabulário: palavras que o cidadão/analista usa -> código do indicador
  const SINONIMOS = [
    ['AGU-02', /perda|vazamento|desperdicio de agua|agua perdida/],
    ['AGU-01', /agua|consumo de agua|litros/],
    ['ENE-02', /solar|placa|painel|paineis|geracao distribuida|geracao propria|renovavel/],
    ['ENE-01', /energia|eletricidade|luz|kwh/],
    ['RES-02', /recicla|seletiva/],
    ['RES-01', /lixo|residuo|coleta/],
    ['MOB-02', /emiss|co2|carbono|poluicao|gas/],
    ['MOB-01', /onibus|transporte publico|passageiro|viagens|mobilidade/],
  ];
  const tirarAcento = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const BLOQUEIO_PEDIDO = /\b(apag|delet|remov|exclu|drop|alter[ae]|insir|inser|grant|senha|password|hash|token|e-?mail|cpf|usuario|usuarios|auditoria)\w*/;

  /**
   * Interpreta a pergunta. Retorna um "plano":
   *   {situacao:'RESPONDIDA'|'BLOQUEADA'|'SEM_RESPOSTA', sql, motivo, intencao, params}
   * @param ctx {municipios:[nomes], ultimoMes:'AAAA-MM', indicadores:{codigo:{nome,unidade}}}
   */
  function interpretar(pergunta, ctx) {
    const t = tirarAcento(String(pergunta || '')).trim();
    if (t.length < 4) return { situacao: 'SEM_RESPOSTA', motivo: 'Pergunta muito curta.' };
    const bl = t.match(BLOQUEIO_PEDIDO);
    if (bl) return { situacao: 'BLOQUEADA', motivo: `O Copiloto só consulta indicadores públicos; não altera dados nem acessa informações pessoais ou de segurança ("${bl[0]}").` };

    const cidades = ctx.municipios.filter((m) => t.includes(tirarAcento(m)));
    const codigo = (SINONIMOS.find(([, re]) => re.test(t)) || [])[0];
    const mes = lerMes(t, ctx.ultimoMes);
    const ultimos = t.match(/ultimos?\s+(\d{1,2})\s+mes/);
    const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
    const inCidades = cidades.length ? ` AND municipio IN (${cidades.map(q).join(', ')})` : '';

    // ---- intenções ----
    if (/origem|oficia|estimad|confiav|fonte/.test(t) && !codigo) {
      return plano('ORIGEM', `SELECT servico, metrica, registros_reais, registros_derivados, registros_estimados, pct_base_oficial, ultimo_mes_oficial FROM vw_origem_dados ORDER BY servico, metrica`, {});
    }
    if (/acao|acoes|funcionou|funcionaram|resultado|projeto/.test(t)) {
      return plano('ACOES', `SELECT titulo, municipio, indicador_alvo, status, efeito, variacao_pct FROM vw_acoes_resultados${cidades.length ? ` WHERE municipio IN (${cidades.map(q).join(', ')})` : ''} ORDER BY FIELD(efeito,'MELHOROU','ESTAVEL','PIOROU','AGUARDANDO_AVALIACAO')`, {});
    }
    if ((/ranking|classifica|mais sustentavel|menos sustentavel|melhor cidade|pior cidade|indice|nota/.test(t)) && !codigo) {
      if (cidades.length && /evolu|historico|mes a mes|ao longo|variou|mudou/.test(t)) {
        return plano('IES_SERIE', `SELECT municipio, ano_mes, ies FROM vw_ies_municipio_mensal WHERE 1=1${inCidades} ORDER BY municipio, ano_mes`, { cidades });
      }
      return plano('RANKING', `SELECT posicao, municipio, ies, classificacao, variacao_mes, variacao_12m FROM vw_ies_ranking ORDER BY posicao`, {});
    }
    if (/fora da meta|nao (atingiu|bateu|cumpriu)|abaixo da meta|precisa melhorar|problema/.test(t)) {
      return plano('FORA_META', `SELECT municipio, codigo, indicador, ROUND(valor, 2) AS valor, meta, unidade, origem FROM vw_indicador_desempenho WHERE ano_mes = ${q(mes)} AND atingiu_meta = 0${inCidades}${codigo ? ` AND codigo = ${q(codigo)}` : ''} ORDER BY score`, { mes });
    }
    if (/dentro da meta|atingiu|bateu a meta|cumpriu/.test(t)) {
      return plano('NA_META', `SELECT municipio, codigo, indicador, ROUND(valor, 2) AS valor, meta, unidade, origem FROM vw_indicador_desempenho WHERE ano_mes = ${q(mes)} AND atingiu_meta = 1${inCidades}${codigo ? ` AND codigo = ${q(codigo)}` : ''} ORDER BY municipio`, { mes });
    }
    if (!codigo) {
      return { situacao: 'SEM_RESPOSTA', motivo: 'Não entendi qual indicador você quer. Fale de água, perdas, energia, energia solar, lixo, reciclagem, ônibus ou emissões.' };
    }
    if (/evolu|historico|mes a mes|ao longo|tendencia|variou|mudou|serie|grafico/.test(t) || ultimos || (cidades.length && !/maior|menor|mais|menos|qual cidade|quais cidades/.test(t))) {
      const n = ultimos ? Math.min(24, +ultimos[1]) : 12;
      const ini = somarMeses(ctx.ultimoMes, -(n - 1));
      return plano('SERIE', `SELECT municipio, ano_mes, ROUND(valor, 2) AS valor, meta, unidade, origem FROM vw_indicador_desempenho WHERE codigo = ${q(codigo)}${inCidades} AND ano_mes BETWEEN ${q(ini)} AND ${q(ctx.ultimoMes)} ORDER BY municipio, ano_mes`, { codigo, cidades, ini, fim: ctx.ultimoMes });
    }
    const menor = /menor|menos|pior em|mais baix|economiz/.test(t) && !/mais alt|maior/.test(t);
    return plano('RANKING_INDICADOR', `SELECT municipio, ROUND(valor, 2) AS valor, unidade, meta, atingiu_meta, origem FROM vw_indicador_desempenho WHERE codigo = ${q(codigo)} AND ano_mes = ${q(mes)}${inCidades} ORDER BY valor ${menor ? 'ASC' : 'DESC'}`, { codigo, mes, menor });

    function plano(intencao, sql, params) {
      const v = validarSQL(sql);
      return v.ok ? { situacao: 'RESPONDIDA', intencao, sql: v.sql, params } : { situacao: 'BLOQUEADA', motivo: v.motivo, sql };
    }
  }

  function lerMes(t, padrao) {
    const m = t.match(/\b(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)[a-z]*\s*(?:\/|de)?\s*(20\d\d)/);
    if (m) {
      const am = `${m[2]}-${String(MESES.indexOf(m[1]) + 1).padStart(2, '0')}`;
      return am <= padrao ? am : padrao;
    }
    return padrao;
  }
  function somarMeses(am, n) {
    const x = +am.slice(0, 4) * 12 + (+am.slice(5, 7) - 1) + n;
    return `${Math.floor(x / 12)}-${String((x % 12) + 1).padStart(2, '0')}`;
  }

  /** Escreve a resposta em português a partir das linhas que o banco devolveu. */
  function responder(plano, linhas, ctx) {
    if (plano.situacao !== 'RESPONDIDA') return plano.motivo;
    if (!linhas.length) return 'A consulta não encontrou dados para esse filtro.';
    const ind = (c) => ctx.indicadores[c] || { nome: c, unidade: '' };
    const r0 = linhas[0];
    switch (plano.intencao) {
      case 'RANKING':
        return `No último mês, a cidade mais sustentável pelo índice EcoCity é **${r0.municipio}** (${num(r0.ies, 1)} pontos), e a última é **${linhas[linhas.length - 1].municipio}** (${num(linhas[linhas.length - 1].ies, 1)}).`;
      case 'IES_SERIE': {
        const por = {};
        linhas.forEach((r) => (por[r.municipio] = por[r.municipio] || []).push(r));
        return Object.entries(por).map(([c, s]) => `**${c}**: de ${num(s[0].ies, 1)} em ${rotulo(s[0].ano_mes)} para ${num(s[s.length - 1].ies, 1)} em ${rotulo(s[s.length - 1].ano_mes)}.`).join(' ');
      }
      case 'RANKING_INDICADOR': {
        const i = ind(plano.params.codigo);
        return `Em ${rotulo(plano.params.mes)}, ${plano.params.menor ? 'o menor valor' : 'o maior valor'} de ${i.nome.toLowerCase()} foi de **${r0.municipio}**: ${fmt(plano.params.codigo, r0.valor)} ${r0.unidade} (dado ${ORIGEM_TXT[r0.origem]}). Meta: ${fmt(plano.params.codigo, r0.meta)}.`;
      }
      case 'SERIE': {
        const i = ind(plano.params.codigo);
        const por = {};
        linhas.forEach((r) => (por[r.municipio] = por[r.municipio] || []).push(r));
        return Object.entries(por).slice(0, 4).map(([c, s]) => {
          const a = +s[0].valor, b = +s[s.length - 1].valor;
          return `**${c}**: ${i.nome.toLowerCase()} foi de ${fmt(plano.params.codigo, a)} (${rotulo(s[0].ano_mes)}) para ${fmt(plano.params.codigo, b)} ${s[0].unidade} (${rotulo(s[s.length - 1].ano_mes)}).`;
        }).join(' ') + (Object.keys(por).length > 4 ? ' Veja as demais cidades na tabela.' : '');
      }
      case 'FORA_META':
        return `Em ${rotulo(plano.params.mes)} havia **${linhas.length} indicador${linhas.length > 1 ? 'es' : ''} fora da meta**. O mais distante: ${r0.indicador.toLowerCase()} em ${r0.municipio} (${num(r0.valor, 2)} ${r0.unidade}; meta ${num(r0.meta, 2)}).`;
      case 'NA_META':
        return `Em ${rotulo(plano.params.mes)}, **${linhas.length}** indicador${linhas.length > 1 ? 'es estavam' : ' estava'} dentro da meta.`;
      case 'ORIGEM': {
        const tot = linhas.reduce((a, r) => a + +r.registros_reais + +r.registros_derivados + +r.registros_estimados, 0);
        const of = linhas.reduce((a, r) => a + +r.registros_reais, 0), de = linhas.reduce((a, r) => a + +r.registros_derivados, 0);
        return `De ${tot} medições mensais, **${of} são oficiais do mês**, ${de} são calculadas a partir de dado oficial e ${tot - of - de} são estimativas. A tabela mostra cada métrica.`;
      }
      case 'ACOES': {
        const ok = linhas.filter((r) => r.efeito === 'MELHOROU');
        return ok.length ? `**${ok.length} ${ok.length > 1 ? 'ações melhoraram' : 'ação melhorou'}** o indicador-alvo, por exemplo "${ok[0].titulo}" em ${ok[0].municipio} (${num(ok[0].variacao_pct, 1)}%).` : 'Nenhuma ação avaliada melhorou o indicador-alvo até agora.';
      }
      default:
        return `${linhas.length} linha(s) encontradas.`;
    }
  }

  // ---------- execução local (modo demonstração, sem banco) ----------
  // Reproduz as views do banco a partir do retrato de dados (data.js).
  function executarLocal(plano, base) {
    const sql = plano.sql;
    const fonte = /from vw_ies_ranking/i.test(sql) ? base.vw_ies_ranking
      : /from vw_ies_municipio_mensal/i.test(sql) ? base.vw_ies_municipio_mensal
        : /from vw_origem_dados/i.test(sql) ? base.vw_origem_dados
          : /from vw_acoes_resultados/i.test(sql) ? base.vw_acoes_resultados
            : base.vw_indicador_desempenho;
    let rows = fonte.slice();
    const lits = (re) => { const m = sql.match(re); return m ? m[1] : null; };
    const cod = lits(/codigo = '([A-Z]{3}-\d\d)'/), mes = lits(/ano_mes = '(\d{4}-\d\d)'/);
    const entre = sql.match(/ano_mes BETWEEN '(\d{4}-\d\d)' AND '(\d{4}-\d\d)'/);
    const inM = sql.match(/municipio IN \(([^)]*)\)/);
    const cid = inM ? [...inM[1].matchAll(/'((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'")) : null;
    if (cod) rows = rows.filter((r) => r.codigo === cod);
    if (mes) rows = rows.filter((r) => r.ano_mes === mes);
    if (entre) rows = rows.filter((r) => r.ano_mes >= entre[1] && r.ano_mes <= entre[2]);
    if (cid) rows = rows.filter((r) => cid.includes(r.municipio));
    if (/atingiu_meta = 0/.test(sql)) rows = rows.filter((r) => !+r.atingiu_meta);
    if (/atingiu_meta = 1/.test(sql)) rows = rows.filter((r) => +r.atingiu_meta);
    if (/ORDER BY valor DESC/.test(sql)) rows.sort((a, b) => b.valor - a.valor);
    else if (/ORDER BY valor ASC/.test(sql)) rows.sort((a, b) => a.valor - b.valor);
    else if (/ORDER BY score/.test(sql)) rows.sort((a, b) => a.score - b.score);
    else if (/ORDER BY posicao/.test(sql)) rows.sort((a, b) => a.posicao - b.posicao);
    else if (/ORDER BY municipio, ano_mes/.test(sql)) rows.sort((a, b) => a.municipio.localeCompare(b.municipio) || a.ano_mes.localeCompare(b.ano_mes));
    const cols = sql.replace(/^SELECT \/\*\+[^*]*\*\/\s*/i, '').split(/\sFROM\s/i)[0].split(',').map((c) => {
      const s = c.trim(); const as = s.match(/\bAS\s+(\w+)$/i);
      return as ? as[1] : s.replace(/^ROUND\((\w+).*$/i, '$1');
    });
    return rows.slice(0, 200).map((r) => Object.fromEntries(cols.map((c) => [c, typeof r[c] === 'number' ? Math.round(r[c] * 100) / 100 : r[c]])));
  }

  return { MODELO_LOCAL, VIEWS_LIBERADAS, gerarRelatorio, interpretar, validarSQL, responder, executarLocal, rotulo, rotuloLongo, IND };
});
