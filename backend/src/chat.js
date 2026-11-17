// Chatbot "Eco" — um assistente diferente para cada perfil:
//   CIDADÃO  -> dicas para economizar, a SUA cidade, alertas da sua cidade e fontes dos dados
//   ANALISTA -> rascunhos de relatório, comparações, séries e fonte de cada dado
//   GESTOR / ADMIN -> conselheiro para decisões (diagnóstico, simulação, ações, metas)
const cidadao = require('./assistentes/cidadao');
const analista = require('./assistentes/analista');
const gestor = require('./assistentes/gestor');

const MODO = { CIDADAO: 'cidadao', ANALISTA: 'analista', GESTOR: 'gestor', ADMIN: 'gestor' };

// Pedidos para alterar o banco ou ver dados pessoais são recusados em qualquer perfil
const PROIBIDO = /\b(apag\w*|delet\w*|drop|truncat\w*|exclu(a|ir|i)\b|remov\w*\s+(a |o |os |as )?(tabela|dado|registro|usuario)|alter(e|ar)\s+(a |o |os |as )?(tabela|dado|valor|registro)|insir\w*|inser(ir|a)\b|grant|senha|password|hash|token|cpf)/i;
const norm = (s) => String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');

async function responder(pergunta, usuario, historico = [], contexto = {}) {
  const modo = MODO[usuario.perfil] || 'cidadao';
  if (PROIBIDO.test(norm(pergunta))) return { modo, texto: 'Não posso fazer isso. O assistente só **lê** os dados públicos dos indicadores: não altera o banco e não mostra dados pessoais (senhas, CPF, e-mails).', sugestoes: [] };
  const r = modo === 'cidadao' ? await cidadao.responder(pergunta, usuario)
    : modo === 'analista' ? await analista.responder(pergunta, usuario)
      : await gestor.responder(pergunta, usuario, historico, contexto);
  return { modo, ...r };
}

module.exports = { responder };
