const express = require('express');
const { query, pool } = require('../db');
const { autenticar, exigirPerfil } = require('../middleware/auth');
const { dadosCidadao, dadosAnalise, dadosAdmin } = require('../dashboard');
const copiloto = require('../copiloto_servico');
const chat = require('../chat');
const ia = require('../ia/alertas');
const coleta = require('../coleta/coletor');
const perfis = require('../perfis');
const fontes = require('../fontes');

const r = express.Router();
const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);

// ------------------------------ AUTENTICAÇÃO (e-mail e senha) ------------------------------
r.use('/auth', require('./auth'));

// ------------------- PÚBLICO: só o resumo da página inicial -------------------
// (os painéis exigem login: só entra quem tem cadastro)
r.get('/public/resumo', wrap(async (_req, res) => {
  const [n] = await query(`SELECT (SELECT COUNT(*) FROM municipio) AS cidades, (SELECT COUNT(*) FROM dado) AS medicoes,
                                  (SELECT COUNT(DISTINCT data_referencia) FROM dado) AS meses, (SELECT COUNT(*) FROM indicador) AS indicadores,
                                  (SELECT COUNT(*) FROM analise_publicada WHERE status='PUBLICADA') AS analises`);
  const ranking = await query('SELECT posicao, municipio, ies, classificacao FROM vw_ies_ranking ORDER BY posicao');
  const [m] = await query("SELECT DATE_FORMAT(MAX(periodo), '%Y-%m') AS mes FROM indicador_valor");
  const municipios = await query(`SELECT m.id_municipio, m.nome, p.populacao FROM municipio m JOIN populacao_anual p ON p.id_municipio = m.id_municipio
                                  WHERE p.ano = (SELECT MAX(ano) FROM populacao_anual) ORDER BY m.nome`);
  // dados públicos da página inicial: média das 8 cidades no último mês (sem metas) e quanto do banco é oficial
  const L = require('../linguagem');
  const medias = (await query(`SELECT codigo, servico, unidade, AVG(valor) AS media FROM vw_indicador_desempenho WHERE ano_mes = ? GROUP BY codigo, servico, unidade ORDER BY codigo`, [m.mes]))
    .map((x) => ({ codigo: x.codigo, servico: x.servico, unidade: x.unidade, media: Number(x.media), simples: L.IND[x.codigo]?.simples, frase: L.IND[x.codigo]?.frase(Number(x.media)) }));
  const origem = await query('SELECT origem, COUNT(*) AS n FROM dado GROUP BY origem');
  res.json({ ...n, mes: m.mes, ranking, municipios, medias, origem });
}));

// --------------------------- ÁREA AUTENTICADA ---------------------------
r.use(autenticar);

// Painel geral das 8 cidades (analista, gestor e admin)
r.get('/cidadao', exigirPerfil('ANALISTA'), wrap(async (_req, res) => res.json(await dadosCidadao())));

// Minha cidade: o cidadão vê SÓ a sua cidade; os outros perfis podem escolher
const cidadeDo = (req) => (req.usuario.perfil === 'CIDADAO' ? req.usuario.municipio : Number(req.query.municipio) || req.usuario.municipio || 1);
r.get('/minha-cidade', wrap(async (req, res) => {
  if (!cidadeDo(req)) return res.status(400).json({ erro: 'Seu cadastro não tem cidade.' });
  const d = await perfis.minhaCidade(cidadeDo(req));
  res.json(req.usuario.perfil === 'CIDADAO' ? perfis.paraCidadao(d) : d);
}));

// Explorar os dados das 8 cidades: mapa, comparar, mês a mês, simulador (todos os perfis)
r.get('/explorar', wrap(async (req, res) => {
  const d = await perfis.explorar();
  if (req.usuario.perfil === 'CIDADAO') {   // sem metas e sem nota para o cidadão
    d.indicadores = d.indicadores.map(({ meta, peso_ies, ...i }) => i);
    d.serie = d.serie.map(({ s, ...x }) => x); delete d.ies;
  }
  res.json(d);
}));

// Fontes: catálogo e detalhe de um valor (todos os perfis)
r.get('/fontes', wrap(async (_req, res) => res.json(await fontes.catalogo())));
r.get('/fontes/valor', wrap(async (req, res) => {
  const mes = String(req.query.mes || ''); const cod = String(req.query.codigo || '');
  if (!/^\d{4}-\d{2}$/.test(mes) || !/^[A-Z]{3}-\d{2}$/.test(cod)) return res.status(400).json({ erro: 'Informe mes (AAAA-MM) e codigo.' });
  res.json(await fontes.deUmValor(cidadeDo(req), cod, mes));
}));

// IA: riscos e alertas — o cidadão recebe SÓ a cidade dele
r.get('/riscos', wrap(async (req, res) => {
  const x = await ia.riscos();
  if (req.usuario.perfil === 'CIDADAO') x.cidades = x.cidades.filter((c) => c.id_municipio === req.usuario.municipio).map(({ id_municipio, municipio, nivel, criticos, atencao }) => ({ id_municipio, municipio, nivel, criticos, atencao }));
  res.json(x);
}));
r.get('/alertas', wrap(async (req, res) => {
  const mun = req.usuario.perfil === 'CIDADAO' ? req.usuario.municipio : (req.query.municipio ? Number(req.query.municipio) : null);
  res.json(await query(`
    SELECT a.id_analise, a.tipo, a.severidade, a.titulo, a.descricao, a.confianca, a.status, a.modelo_versao,
           DATE_FORMAT(a.gerada_em,'%Y-%m-%d') AS gerada_em, r.nome AS municipio, a.id_municipio, i.codigo AS indicador, s.nome AS servico
    FROM analise_ia a JOIN municipio r USING (id_municipio) JOIN indicador i USING (id_indicador) JOIN servico_publico s ON s.id_servico = i.id_servico
    WHERE a.status <> 'DESCARTADA' ${mun ? 'AND a.id_municipio = ?' : ''}
    ORDER BY FIELD(a.status,'NOVA','EM_ANALISE','VALIDADA'), FIELD(a.severidade,'CRITICO','ATENCAO','INFO'), a.gerada_em DESC LIMIT 80`, mun ? [mun] : []));
}));

// Assistente Eco (cada perfil tem o seu)
r.post('/chat', wrap(async (req, res) => {
  const pergunta = String(req.body?.pergunta || '').slice(0, 800);
  const historico = Array.isArray(req.body?.historico) ? req.body.historico.slice(-10) : [];
  const contexto = req.body?.contexto && typeof req.body.contexto === 'object' ? req.body.contexto : {};
  res.json(await chat.responder(pergunta, req.usuario, historico, contexto));
}));

// Dicas para economizar (página "Economize em casa")
r.get('/dicas/:tema', (req, res) => {
  const d = require('../assistentes/cidadao').DICAS[req.params.tema];
  if (!d) return res.status(404).json({ erro: 'Tema não encontrado.' });
  res.json({ titulo: d.titulo, itens: d.itens, conta: d.conta() });
});

// Analista: laboratório de dados · Gestor: sala de situação
r.get('/laboratorio', exigirPerfil('ANALISTA'), wrap(async (_req, res) => res.json(await perfis.laboratorio())));
r.get('/sala', exigirPerfil('GESTOR'), wrap(async (req, res) => res.json(await perfis.salaSituacao(req.query.municipio ? Number(req.query.municipio) : null))));

// Análises publicadas: só analistas, gestores e admin
r.get('/publicas/analises', exigirPerfil('ANALISTA'), wrap(async (_req, res) => res.json(await query('SELECT * FROM vw_analises_publicadas ORDER BY publicada_em DESC'))));
r.get('/publicas/analises/:id', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const n = Number(req.params.id);
  const [a] = await query(`SELECT a.id_analise_pub, a.titulo, a.resumo, a.conteudo, a.nivel_confianca, a.pct_base_oficial, a.versao,
                                  DATE_FORMAT(a.periodo_inicio,'%Y-%m') AS de, DATE_FORMAT(a.periodo_fim,'%Y-%m') AS ate,
                                  DATE_FORMAT(a.publicada_em,'%Y-%m-%d') AS publicada_em, s.nome AS servico, u.nome AS autor, v.nome AS revisor
                           FROM analise_publicada a JOIN servico_publico s USING (id_servico) JOIN usuario u ON u.id_usuario = a.id_autor
                           LEFT JOIN usuario v ON v.id_usuario = a.revisado_por WHERE a.id_analise_pub = ? AND a.status = 'PUBLICADA'`, [n]);
  if (!a) return res.status(404).json({ erro: 'Análise não encontrada.' });
  res.json({ ...a,
    municipios: await query('SELECT m.nome FROM analise_municipio am JOIN municipio m USING (id_municipio) WHERE am.id_analise_pub = ?', [n]),
    evidencias: await query(`SELECT e.tipo, i.codigo AS indicador, m.nome AS municipio, e.url, e.descricao FROM analise_evidencia e
                             LEFT JOIN indicador i USING (id_indicador) LEFT JOIN municipio m USING (id_municipio) WHERE e.id_analise_pub = ?`, [n]),
    comentarios: await query(`SELECT c.texto, u.nome AS autor, DATE_FORMAT(c.criado_em,'%Y-%m-%d %H:%i') AS criado_em
                              FROM analise_comentario c JOIN usuario u USING (id_usuario) WHERE c.id_analise_pub = ? ORDER BY c.criado_em`, [n]) });
}));

// Coleta automática (administrador): status e "executar agora"
r.get('/admin/coleta', exigirPerfil('ADMIN'), wrap(async (_req, res) => res.json(await coleta.status())));
// a coleta pode levar alguns minutos (o arquivo da ANEEL tem ~110 MB): começa em segundo plano e a tela acompanha
r.post('/admin/coleta', exigirPerfil('ADMIN'), wrap(async (req, res) => {
  const st = await coleta.status();
  if (st.rodando) return res.status(409).json({ erro: 'A coleta já está rodando. Aguarde terminar.' });
  coleta.atualizar({ origem: `manual (${req.usuario.nome})`, forcar: req.body?.forcar === true }).catch(() => {});
  res.status(202).json({ iniciado: true });
}));

// Analista e gestor: séries mensais, IES, ações, alertas, fontes, Copiloto
r.get('/dados', exigirPerfil('ANALISTA'), wrap(async (_req, res) => res.json(await dadosAnalise())));

// Administrador: banco, usuários, cargas, auditoria e uso do Copiloto
r.get('/admin', exigirPerfil('ADMIN'), wrap(async (_req, res) => res.json({ ...(await dadosAnalise()), ...(await dadosAdmin()) })));

// Raio-x de um município (stored procedure com 3 result sets)
r.get('/municipios/:id', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const [sets] = await pool.query('CALL sp_dashboard_municipio(?)', [Number(req.params.id)]);
  res.json({ resumo: sets[0][0] || null, indicadores: sets[1], alertas: sets[2] });
}));

// Análises da IA: o analista valida ou descarta
r.patch('/alertas/:id', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const status = req.body?.status;
  if (!['EM_ANALISE', 'VALIDADA', 'DESCARTADA'].includes(status)) return res.status(400).json({ erro: 'Status inválido' });
  const r1 = await query('UPDATE analise_ia SET status = ?, revisada_por = ? WHERE id_analise = ?', [status, req.usuario.id, Number(req.params.id)]);
  res.json({ atualizado: r1.affectedRows === 1 });
}));

// Ações e resultados
r.post('/acoes', exigirPerfil('GESTOR'), wrap(async (req, res) => {
  const b = req.body || {};
  const obrig = ['titulo', 'descricao', 'id_municipio', 'id_indicador_alvo', 'data_inicio', 'data_fim_prevista'];
  const falta = obrig.filter((k) => b[k] === undefined || b[k] === '');
  if (falta.length) return res.status(400).json({ erro: `Campos obrigatórios: ${falta.join(', ')}` });
  const out = await query(
    `INSERT INTO acao (titulo, descricao, id_municipio, id_indicador_alvo, id_responsavel, id_analise, data_inicio, data_fim_prevista, orcamento)
     VALUES (?,?,?,?,?,?,?,?,?)`,
    [b.titulo, b.descricao, b.id_municipio, b.id_indicador_alvo, req.usuario.id, b.id_analise ?? null, b.data_inicio, b.data_fim_prevista, b.orcamento ?? 0]);
  res.status(201).json({ id_acao: out.insertId });
}));

r.post('/acoes/:id/resultado', exigirPerfil('GESTOR'), wrap(async (req, res) => {
  const { data_avaliacao, observacao } = req.body || {};
  const [sets] = await pool.query('CALL sp_registrar_resultado(?,?,?,?)', [Number(req.params.id), data_avaliacao, observacao ?? null, req.usuario.id]);
  res.status(201).json(sets[0][0]);
}));

// ------------- METAS, ANÁLISES, CREDENCIAIS, FONTES E SEGURANÇA DO LOGIN -------------
r.use(require('./governanca'));

// ------------------------------ COPILOTO ------------------------------
r.post('/copiloto/perguntar', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const pergunta = String(req.body?.pergunta || '').slice(0, 500);
  if (!pergunta.trim()) return res.status(400).json({ erro: 'Escreva uma pergunta.' });
  res.json(await copiloto.perguntar(pergunta, req.usuario.id));
}));

r.post('/copiloto/relatorios', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  res.status(201).json(await copiloto.gerarRelatorio(req.body || {}, req.usuario.id));
}));

// Revisão humana: só gestor (e nunca quem pediu o relatório — regra no trigger do banco)
r.patch('/copiloto/relatorios/:id', exigirPerfil('GESTOR'), wrap(async (req, res) => {
  const { decisao, comentario } = req.body || {};
  const [sets] = await pool.query('CALL sp_revisar_relatorio(?,?,?,?)', [Number(req.params.id), decisao, req.usuario.id, comentario ?? null]);
  res.json(sets[0][0]);
}));

module.exports = r;
