// Pools de conexão MySQL (mysql2/promise) — consultas SEMPRE parametrizadas
const mysql = require('mysql2/promise');
require('dotenv').config();

const base = {
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 3306),
  database: process.env.DB_NAME || 'ecocity',
  charset: 'utf8mb4',
  decimalNumbers: true,
  dateStrings: true,
  ssl: sslConfig(),
};

// SSL (obrigatório em bancos na nuvem como Aiven e Oracle Cloud).
// DB_SSL_CA pode ser o CAMINHO do arquivo ca.pem ou o CONTEÚDO do certificado (útil no Render).
function sslConfig() {
  if (process.env.DB_SSL !== 'true') return undefined;
  const ca = process.env.DB_SSL_CA;
  if (!ca) return { rejectUnauthorized: true };
  const fs = require('fs');
  const texto = ca.includes('BEGIN CERTIFICATE') ? ca.replace(/\\n/g, '\n') : fs.readFileSync(require('path').resolve(ca), 'utf8');
  return { ca: texto, rejectUnauthorized: true };
}

// API: perfis gestor/analista/cidadão (papéis r_gestor + r_cidadao no MySQL)
const pool = mysql.createPool({ ...base, user: process.env.DB_USER, password: process.env.DB_PASS, connectionLimit: 10 });

// Copiloto: usuário ecocity_ia, que SÓ consegue ler as views de indicadores.
// Mesmo que uma consulta perigosa passasse pela validação, o MySQL recusaria.
const poolIA = mysql.createPool({
  ...base, user: process.env.DB_IA_USER || 'ecocity_ia', password: process.env.DB_IA_PASS, connectionLimit: 3,
});

// Robô de coleta e IA de alertas: usuário ecocity_etl (só carga, cálculo dos indicadores e gravação de alertas)
const poolETL = mysql.createPool({
  ...base, user: process.env.DB_ETL_USER || 'ecocity_etl', password: process.env.DB_ETL_PASS || 'Etl#EcoCity2026!', connectionLimit: 3,
});

// Mesmo "sql_mode" do MySQL local em toda conexão (o banco na nuvem pode usar outro modo por padrão)
const MODO = "SET SESSION sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'";
for (const p of [pool, poolIA, poolETL]) p.pool.on('connection', (c) => c.query(MODO));

async function query(sql, params = []) {
  const [rows] = await pool.execute(sql, params);
  return rows;
}

// Igual a query(), mas aceita listas em "IN (?)" (o driver escapa cada valor)
async function consulta(sql, params = []) {
  const [rows] = await pool.query(sql, params);
  return rows;
}

module.exports = { pool, poolIA, poolETL, query, consulta };
