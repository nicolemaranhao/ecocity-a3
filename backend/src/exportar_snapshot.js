// Gera frontend/data.js com um retrato do banco — permite abrir o painel
// mesmo sem a API no ar (modo demonstração / apresentação).
// Não inclui senhas: a consulta de usuários não lê a coluna senha_hash.
const fs = require('fs');
const path = require('path');
const { dadosCidadao, dadosAnalise, dadosAdmin } = require('./dashboard');
const { pool, poolIA } = require('./db');

(async () => {
  const d = { ...(await dadosCidadao()), ...(await dadosAnalise()), ...(await dadosAdmin()), modo: 'demonstracao' };
  const destino = path.join(__dirname, '..', '..', 'frontend', 'data.js');
  fs.writeFileSync(destino, '// Gerado por backend/src/exportar_snapshot.js — retrato do banco EcoCity\nwindow.ECOCITY_SNAPSHOT = ' + JSON.stringify(d) + ';\n');
  console.log('Snapshot salvo em', destino, `(${(fs.statSync(destino).size / 1024).toFixed(1)} KB)`);
  await pool.end(); await poolIA.end();
})().catch((e) => { console.error(e); process.exit(1); });
