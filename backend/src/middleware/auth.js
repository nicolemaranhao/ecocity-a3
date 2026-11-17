// Autenticação JWT + autorização por perfil (RBAC)
const jwt = require('jsonwebtoken');

function autenticar(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ erro: 'Token ausente' });
  try {
    req.usuario = jwt.verify(token, process.env.JWT_SECRET);
    // "passe" da 1ª etapa do login não abre o sistema: falta o código do aplicativo
    if (req.usuario.etapa) return res.status(401).json({ erro: 'Login incompleto.' });
    next();
  } catch {
    return res.status(401).json({ erro: 'Token inválido ou expirado' });
  }
}

// Hierarquia: ADMIN > GESTOR > ANALISTA > CIDADAO
const NIVEL = { CIDADAO: 1, ANALISTA: 2, GESTOR: 3, ADMIN: 4 };
const exigirPerfil = (minimo) => (req, res, next) =>
  NIVEL[req.usuario?.perfil] >= NIVEL[minimo]
    ? next()
    : res.status(403).json({ erro: `Acesso restrito ao perfil ${minimo} ou superior` });

module.exports = { autenticar, exigirPerfil };
