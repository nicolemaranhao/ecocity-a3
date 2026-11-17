// EcoCity API — Express + MySQL
require('dotenv').config();
const path = require('path');
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const api = require('./routes/api');

const app = express();
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json({ limit: '100kb' }));
app.use('/api/', rateLimit({ windowMs: 60_000, max: 120, message: { erro: 'Muitas requisições. Aguarde um minuto.' } }));            // anti-abuso
app.use('/api/auth', rateLimit({ windowMs: 15 * 60_000, max: Number(process.env.AUTH_RATE_MAX || 20), message: { erro: 'Muitas tentativas de login. Aguarde 15 minutos.' } }));      // anti força-bruta (o banco ainda bloqueia no 5º erro)

app.get('/api/health', (_req, res) => res.json({ status: 'ok', servico: 'ecocity-api' }));
app.use('/api', api);

// Frontend estático (dashboard)
app.use(express.static(path.join(__dirname, '..', '..', 'frontend')));

// Tratamento centralizado de erros (sem vazar detalhes internos)
app.use((err, _req, res, _next) => {
  if (err.sqlState === '45000') return res.status(422).json({ erro: err.sqlMessage }); // regra de negócio (SIGNAL)
  if (err.status) return res.status(err.status).json({ erro: err.message });             // validação da entrada
  if (/Não há dados/.test(err.message)) return res.status(422).json({ erro: err.message });
  console.error(err);
  res.status(500).json({ erro: 'Erro interno' });
});

const PORT = Number(process.env.PORT || 3000);
app.listen(PORT, () => {
  console.log(`EcoCity ouvindo em http://localhost:${PORT}`);
  require('./coleta/coletor').iniciarAgendador();     // coleta automática todo mês
});
