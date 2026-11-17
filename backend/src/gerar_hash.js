// Para o DBA criar um administrador: gera o hash bcrypt de uma senha ou chave.
//   npm run hash -- "MinhaChaveSecreta"
// Depois, no MySQL (como DBA):  CALL sp_criar_admin('Nome', 'email@orgao.gov.br', '<hash da senha>', '<hash da chave>');
const bcrypt = require('bcryptjs');
const texto = process.argv[2];
if (!texto) { console.log('Uso: npm run hash -- "texto"'); process.exit(1); }
console.log(bcrypt.hashSync(texto, 10));
