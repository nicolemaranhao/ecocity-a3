// Metas, análises dos analistas, credenciais e confiabilidade das fontes.
// A API só repassa os dados: TODAS as regras (quem pode, prazos, tamanhos mínimos,
// "quem propõe não aprova") estão nas procedures e triggers do banco.
const express = require('express');
const { query, pool } = require('../db');
const { exigirPerfil } = require('../middleware/auth');

const r = express.Router();
const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);
const id = (v) => { const n = Number(v); if (!Number.isInteger(n) || n <= 0) { const e = new Error('Identificador inválido.'); e.status = 400; throw e; } return n; };
const chamar = async (sql, params) => { const [sets] = await pool.query(sql, params); return sets[0]?.[0] ?? null; };
const obrigatorios = (b, campos) => {
  const falta = campos.filter((k) => b[k] === undefined || b[k] === null || b[k] === '');
  if (falta.length) { const e = new Error(`Campos obrigatórios: ${falta.join(', ')}`); e.status = 400; throw e; }
};

// =============================== METAS ===============================
// Fluxo: GESTOR propõe -> ANALISTA verificado da área dá parecer -> OUTRO gestor aprova ou rejeita.
r.get('/metas', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const st = req.query.status;
  const rows = st
    ? await query('SELECT * FROM vw_metas WHERE status = ? ORDER BY codigo, vigencia_inicio', [String(st)])
    : await query("SELECT * FROM vw_metas ORDER BY FIELD(status,'PROPOSTA','PARECER_EMITIDO','APROVADA','REJEITADA','SUBSTITUIDA'), codigo, vigencia_inicio");
  res.json(rows);
}));

// Formulário "Nova meta"
r.post('/metas', exigirPerfil('GESTOR'), wrap(async (req, res) => {
  const b = req.body || {};
  obrigatorios(b, ['codigo_indicador', 'valor', 'vigencia_inicio', 'justificativa', 'referencia']);
  res.status(201).json(await chamar('CALL sp_propor_meta(?,?,?,?,?,?,?)',
    [req.usuario.id, b.codigo_indicador, b.id_municipio || null, b.valor, b.vigencia_inicio, b.justificativa, b.referencia]));
}));

r.post('/metas/:id/parecer', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const b = req.body || {};
  obrigatorios(b, ['favoravel', 'parecer']);
  res.json(await chamar('CALL sp_parecer_meta(?,?,?,?)', [id(req.params.id), req.usuario.id, !!b.favoravel, b.parecer]));
}));

r.post('/metas/:id/decisao', exigirPerfil('GESTOR'), wrap(async (req, res) => {
  obrigatorios(req.body || {}, ['aprovar']);
  res.json(await chamar('CALL sp_decidir_meta(?,?,?)', [id(req.params.id), req.usuario.id, !!req.body.aprovar]));
}));

// ========================= ANÁLISES DOS ANALISTAS =========================
// Fluxo: RASCUNHO -> (enviar) EM_REVISAO -> (revisor) PUBLICADA ou DEVOLVIDA -> comentários
r.get('/analises', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  res.json({
    publicadas: await query('SELECT * FROM vw_analises_publicadas ORDER BY publicada_em DESC'),
    fila_revisao: await query('SELECT * FROM vw_fila_revisao_analises'),
    minhas: await query(`SELECT a.id_analise_pub, a.titulo, a.status, a.nivel_confianca, a.versao, a.parecer_revisao,
                                DATE_FORMAT(a.criada_em,'%Y-%m-%d') AS criada_em
                         FROM analise_publicada a WHERE a.id_autor = ? ORDER BY a.criada_em DESC`, [req.usuario.id]),
  });
}));

r.get('/analises/:id', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const n = id(req.params.id);
  const [a] = await query(`SELECT a.*, s.nome AS servico, u.nome AS autor, v.nome AS revisor
                           FROM analise_publicada a JOIN servico_publico s USING (id_servico) JOIN usuario u ON u.id_usuario = a.id_autor
                           LEFT JOIN usuario v ON v.id_usuario = a.revisado_por WHERE a.id_analise_pub = ?`, [n]);
  if (!a) return res.status(404).json({ erro: 'Análise não encontrada.' });
  // rascunhos e devolvidas só o autor vê
  if (['RASCUNHO', 'DEVOLVIDA'].includes(a.status) && a.id_autor !== req.usuario.id && req.usuario.perfil !== 'ADMIN')
    return res.status(403).json({ erro: 'Rascunho visível só para o autor.' });
  res.json({
    ...a,
    municipios: await query('SELECT m.id_municipio, m.nome FROM analise_municipio am JOIN municipio m USING (id_municipio) WHERE am.id_analise_pub = ?', [n]),
    evidencias: await query(`SELECT e.id_evidencia, e.tipo, i.codigo AS indicador, m.nome AS municipio, e.consulta_sql, e.url, e.descricao
                             FROM analise_evidencia e LEFT JOIN indicador i USING (id_indicador) LEFT JOIN municipio m USING (id_municipio)
                             WHERE e.id_analise_pub = ?`, [n]),
    comentarios: await query(`SELECT c.texto, u.nome AS autor, DATE_FORMAT(c.criado_em,'%Y-%m-%d %H:%i') AS criado_em
                              FROM analise_comentario c JOIN usuario u USING (id_usuario) WHERE c.id_analise_pub = ? ORDER BY c.criado_em`, [n]),
  });
}));

// Salva cidades e evidências da análise (apaga as antigas e grava as novas)
async function gravarDetalhes(con, idAnalise, b) {
  await con.execute('DELETE FROM analise_municipio WHERE id_analise_pub = ?', [idAnalise]);
  await con.execute('DELETE FROM analise_evidencia WHERE id_analise_pub = ?', [idAnalise]);
  for (const m of b.municipios || []) await con.execute('INSERT INTO analise_municipio (id_analise_pub, id_municipio) VALUES (?,?)', [idAnalise, id(m)]);
  for (const e of b.evidencias || []) {
    await con.execute(`INSERT INTO analise_evidencia (id_analise_pub, tipo, id_indicador, id_municipio, consulta_sql, url, descricao)
                       VALUES (?,?,(SELECT id_indicador FROM indicador WHERE codigo = ?),?,?,?,?)`,
      [idAnalise, e.tipo, e.codigo_indicador ?? null, e.id_municipio ?? null, e.consulta_sql ?? null, e.url ?? null, e.descricao]);
  }
}

// Formulário "Nova análise" (fica como RASCUNHO até o autor enviar)
r.post('/analises', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const b = req.body || {};
  obrigatorios(b, ['titulo', 'resumo', 'conteudo', 'id_servico', 'periodo_inicio', 'periodo_fim']);
  const con = await pool.getConnection();
  try {
    await con.beginTransaction();
    const [out] = await con.execute(
      `INSERT INTO analise_publicada (titulo, resumo, conteudo, id_servico, periodo_inicio, periodo_fim, id_autor) VALUES (?,?,?,?,?,?,?)`,
      [b.titulo, b.resumo, b.conteudo, b.id_servico, b.periodo_inicio, b.periodo_fim, req.usuario.id]);
    await gravarDetalhes(con, out.insertId, b);
    await con.commit();
    res.status(201).json({ id_analise_pub: out.insertId, status: 'RASCUNHO' });
  } catch (e) { await con.rollback(); throw e; } finally { con.release(); }
}));

// Editar rascunho ou análise devolvida (o trigger bloqueia edição de análise em revisão/publicada)
r.put('/analises/:id', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const n = id(req.params.id); const b = req.body || {};
  obrigatorios(b, ['titulo', 'resumo', 'conteudo', 'id_servico', 'periodo_inicio', 'periodo_fim']);
  const con = await pool.getConnection();
  try {
    await con.beginTransaction();
    const [out] = await con.execute(
      `UPDATE analise_publicada SET titulo=?, resumo=?, conteudo=?, id_servico=?, periodo_inicio=?, periodo_fim=?
       WHERE id_analise_pub = ? AND id_autor = ? AND status IN ('RASCUNHO','DEVOLVIDA')`,
      [b.titulo, b.resumo, b.conteudo, b.id_servico, b.periodo_inicio, b.periodo_fim, n, req.usuario.id]);
    if (out.affectedRows === 0) { const e = new Error('Só o autor edita, e apenas rascunhos ou análises devolvidas.'); e.status = 403; throw e; }
    await gravarDetalhes(con, n, b);
    await con.commit();
    res.json({ id_analise_pub: n, atualizado: true });
  } catch (e) { await con.rollback(); throw e; } finally { con.release(); }
}));

r.post('/analises/:id/enviar', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  res.json(await chamar('CALL sp_enviar_analise(?,?)', [id(req.params.id), req.usuario.id]));
}));

r.post('/analises/:id/revisao', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const b = req.body || {};
  obrigatorios(b, ['decisao', 'parecer']);
  res.json(await chamar('CALL sp_revisar_analise(?,?,?,?)', [id(req.params.id), req.usuario.id, b.decisao, b.parecer]));
}));

r.post('/analises/:id/comentarios', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const texto = String(req.body?.texto || '').trim().slice(0, 1000);
  if (texto.length < 5) return res.status(400).json({ erro: 'Escreva um comentário.' });
  await query('INSERT INTO analise_comentario (id_analise_pub, id_usuario, texto) VALUES (?,?,?)', [id(req.params.id), req.usuario.id, texto]);
  res.status(201).json({ ok: true });
}));

// ============================ CREDENCIAIS ============================
// O analista cadastra a própria credencial (fica PENDENTE); só o ADMIN verifica.
r.post('/credenciais', exigirPerfil('ANALISTA'), wrap(async (req, res) => {
  const b = req.body || {};
  obrigatorios(b, ['orgao_vinculo', 'registro_profissional', 'nivel']);
  await query(`INSERT INTO credencial_analista (id_usuario, orgao_vinculo, registro_profissional, id_servico, nivel) VALUES (?,?,?,?,?)`,
    [req.usuario.id, b.orgao_vinculo, b.registro_profissional, b.id_servico || null, b.nivel]);
  res.status(201).json({ status: 'PENDENTE', mensagem: 'Credencial enviada. Aguarde a verificação do administrador.' });
}));

r.get('/credenciais', exigirPerfil('ANALISTA'), wrap(async (_req, res) => res.json(await query('SELECT * FROM vw_confiabilidade_analista'))));

r.patch('/credenciais/:idUsuario', exigirPerfil('ADMIN'), wrap(async (req, res) => {
  const b = req.body || {};
  obrigatorios(b, ['status']);
  await pool.query('CALL sp_verificar_credencial(?,?,?,?,?)', [id(req.params.idUsuario), req.usuario.id, b.status, b.valida_ate || null, b.observacao || null]);
  res.json({ id_usuario: Number(req.params.idUsuario), status: b.status });
}));

// ===================== CONFIABILIDADE DAS FONTES (ADMIN) =====================
r.patch('/fontes/:id/confiabilidade', exigirPerfil('ADMIN'), wrap(async (req, res) => {
  const b = req.body || {};
  obrigatorios(b, ['nota', 'motivo']);
  await pool.query('CALL sp_avaliar_fonte(?,?,?,?)', [id(req.params.id), req.usuario.id, b.nota, b.motivo]);
  const [f] = await query('SELECT id_fonte, nome, confiabilidade, confiabilidade_motivo FROM fonte_dados WHERE id_fonte = ?', [id(req.params.id)]);
  res.json(f);
}));

// ================= CADASTROS DE ANALISTAS E GESTORES (ADMIN) =================
r.get('/cadastros', exigirPerfil('ADMIN'), wrap(async (req, res) => {
  const st = req.query.status;
  res.json(st ? await query('SELECT * FROM vw_cadastros_profissionais WHERE status = ? ORDER BY pedido_em', [String(st)])
              : await query("SELECT * FROM vw_cadastros_profissionais ORDER BY FIELD(status,'EM_ANALISE','SUSPENSO','RECUSADO','APROVADO'), pedido_em"));
}));

r.patch('/cadastros/:idUsuario', exigirPerfil('ADMIN'), wrap(async (req, res) => {
  const b = req.body || {};
  obrigatorios(b, ['decisao', 'motivo']);
  res.json(await chamar('CALL sp_analisar_cadastro(?,?,?,?,?)', [id(req.params.idUsuario), req.usuario.id, b.decisao, b.motivo, b.valido_ate || null]));
}));

// ===================== SEGURANÇA DO LOGIN (ADMIN) =====================
r.get('/acessos', exigirPerfil('ADMIN'), wrap(async (_req, res) => {
  res.json({
    resumo: await query('SELECT resultado, COUNT(*) AS tentativas FROM acesso_log GROUP BY resultado'),
    ultimos: await query(`SELECT email_tentado, resultado, ip, DATE_FORMAT(ocorrido_em,'%Y-%m-%d %H:%i:%s') AS ocorrido_em
                          FROM acesso_log ORDER BY ocorrido_em DESC LIMIT 30`),
    bloqueados: await query('SELECT email, bloqueado_ate FROM usuario WHERE bloqueado_ate > NOW()'),
  });
}));

module.exports = r;
