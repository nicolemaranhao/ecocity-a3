// Login com e-mail e senha (uma etapa). Quem decide o resultado de cada tentativa é o BANCO
// (sp_registrar_login): ele registra no acesso_log, conta os erros e bloqueia por 15 min no 5º.
//
//  POST /auth/login   e-mail + senha  -> token
//  ADMIN: além da senha, digita a CHAVE DE ADMINISTRADOR individual (entregue pelo DBA), na mesma tela.
//
//  Cadastro:
//   POST /auth/cadastro/cidadao      simples (nome, e-mail, telefone opcional, cidade, senha) -> entra na hora
//   POST /auth/cadastro/profissional analista ou gestor: dados completos -> fica EM_ANALISE até o ADMIN aprovar
//   (não existe cadastro de ADMIN pelo site)
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { query, pool } = require('../db');

const r = express.Router();
const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);

const MENSAGEM = {
  SENHA_ERRADA: [401, 'E-mail ou senha incorretos.'],
  BLOQUEADO: [423, 'Conta bloqueada por 15 minutos após 5 tentativas erradas.'],
  INATIVO: [403, 'Usuário desativado. Procure o administrador.'],
  SENHA_EXPIRADA: [403, 'Sua senha venceu. Peça ao administrador para redefini-la.'],
  CHAVE_ADMIN_ERRADA: [401, 'Chave de administrador incorreta.'],
  CADASTRO_EM_ANALISE: [403, 'Seu cadastro ainda está em análise pelo administrador. Você receberá a resposta no e-mail institucional.'],
};

async function registrar(email, senhaOk, mfaOk, ip, chaveOk = false) {
  const [sets] = await pool.query('CALL sp_registrar_login(?,?,?,?,?)', [email, senhaOk, mfaOk, chaveOk, ip]);
  return sets[0][0];   // { resultado, precisa_configurar_mfa }
}

async function buscar(email) {
  const [u] = await query(
    `SELECT u.id_usuario, u.nome, u.email, u.senha_hash, u.id_municipio, u.mfa_ativo, u.status_cadastro, u.chave_admin_hash,
            p.nome AS perfil, p.exige_mfa
     FROM usuario u JOIN perfil p USING (id_perfil) WHERE u.email = ?`, [email]);
  return u;
}

const tokenFinal = (u) => jwt.sign({ id: u.id_usuario, nome: u.nome, perfil: u.perfil, municipio: u.id_municipio },
  process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES || '8h' });
const resposta = (u) => ({ token: tokenFinal(u), usuario: { id: u.id_usuario, nome: u.nome, perfil: u.perfil, municipio: u.id_municipio } });

// Só o ADMIN tem chave: compara com o hash bcrypt guardado no banco (a chave em si nunca é guardada)
async function chaveConfere(email, chave) {
  const u = await buscar(email);
  if (!u || u.perfil !== 'ADMIN' || !u.chave_admin_hash || !chave) return false;
  return bcrypt.compare(String(chave), u.chave_admin_hash);
}

function falha(res, resultado) {
  const [st, msg] = MENSAGEM[resultado] || [401, 'Não foi possível entrar.'];
  return res.status(st).json({ erro: msg, resultado });
}

// ---------------- Login: e-mail e senha ----------------
r.post('/login', wrap(async (req, res) => {
  const email = String(req.body?.email || '').toLowerCase().trim();
  const senha = String(req.body?.senha || '');
  if (!email || !senha) return res.status(400).json({ erro: 'Informe e-mail e senha.' });

  const u = await buscar(email);
  const senhaOk = !!u && await bcrypt.compare(senha, u.senha_hash);

  if (!senhaOk) return falha(res, (await registrar(email, false, false, req.ip)).resultado);

  // Analista/gestor com cadastro em análise, recusado ou suspenso: o banco registra e recusa
  if (u.status_cadastro !== 'ATIVO') return falha(res, (await registrar(email, true, false, req.ip)).resultado);

  const [b] = await query('SELECT bloqueado_ate > NOW() AS bloqueado FROM usuario WHERE id_usuario = ?', [u.id_usuario]);
  if (b.bloqueado) return falha(res, (await registrar(email, true, false, req.ip)).resultado);

  // Administrador: a chave individual vai junto com a senha, na mesma tela
  if (u.perfil === 'ADMIN' && !req.body?.chave_admin)
    return res.json({ etapa: 'CHAVE', mensagem: 'Digite também a sua chave de administrador.' });

  const chaveOk = u.perfil === 'ADMIN' ? await chaveConfere(email, req.body.chave_admin) : false;
  const out = await registrar(email, true, true, req.ip, chaveOk);
  if (out.resultado !== 'SUCESSO') return falha(res, out.resultado);
  res.json(resposta(u));
}));

// ================================ CADASTRO ================================
const exigir = (b, campos) => {
  const falta = campos.filter((k) => b[k] === undefined || b[k] === null || String(b[k]).trim() === '');
  if (falta.length) { const e = new Error(`Preencha: ${falta.join(', ')}`); e.status = 400; throw e; }
};
// Cidadão: senha de 8+ com letra e número. Analista/gestor: 12+ com maiúscula, minúscula, número e símbolo.
function senhaForte(senha, profissional) {
  const ok = profissional
    ? senha.length >= 12 && /[a-z]/.test(senha) && /[A-Z]/.test(senha) && /\d/.test(senha) && /[^A-Za-z0-9]/.test(senha)
    : senha.length >= 8 && /[A-Za-z]/.test(senha) && /\d/.test(senha);
  if (!ok) {
    const e = new Error(profissional ? 'Senha: mínimo 12 caracteres, com maiúscula, minúscula, número e símbolo.'
                                     : 'Senha: mínimo 8 caracteres, com letras e números.');
    e.status = 400; throw e;
  }
}

r.post('/cadastro/cidadao', wrap(async (req, res) => {
  const b = req.body || {};
  exigir(b, ['nome', 'email', 'id_municipio', 'senha']);
  senhaForte(String(b.senha), false);
  const hash = await bcrypt.hash(String(b.senha), 10);
  const [sets] = await pool.query('CALL sp_cadastrar_cidadao(?,?,?,?,?)', [b.nome, b.email, b.telefone || null, Number(b.id_municipio), hash]);
  res.status(201).json({ ...sets[0][0], mensagem: 'Cadastro feito! Já pode entrar.' });
}));

r.post('/cadastro/profissional', wrap(async (req, res) => {
  const b = req.body || {};
  exigir(b, ['perfil', 'nome', 'cpf', 'email_institucional', 'telefone', 'senha', 'orgao', 'cargo', 'matricula', 'formacao',
             'documento_url', 'justificativa', 'aceite_termo']);
  senhaForte(String(b.senha), true);
  const hash = await bcrypt.hash(String(b.senha), 10);
  const [sets] = await pool.query('CALL sp_solicitar_acesso(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [
    String(b.perfil).toUpperCase(), b.nome, b.cpf, b.email_institucional, b.telefone, hash, b.orgao, b.cargo, b.matricula, b.formacao,
    b.registro_conselho || null, b.portaria_nomeacao || null, b.id_municipio ? Number(b.id_municipio) : null,
    b.documento_url, b.justificativa, b.aceite_termo === true, req.ip]);
  res.status(201).json({ ...sets[0][0], mensagem: 'Pedido enviado. O administrador vai conferir seus documentos antes de liberar o acesso.' });
}));

module.exports = r;
