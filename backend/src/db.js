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
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: true } : undefined,
};

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
