// Cria exemplos do Copiloto (relatórios e perguntas) para a demonstração.
// Depois o resultado é exportado para sql/07c_copiloto_exemplos.sql.
const { gerarRelatorio, perguntar } = require('./copiloto_servico');
const { pool, poolIA } = require('./db');

(async () => {
  const rev = (id, decisao, revisor, comentario) => pool.query('CALL sp_revisar_relatorio(?,?,?,?)', [id, decisao, revisor, comentario]);
  // analista Rafael (4) pede; gestora Marina (2) aprova
  const a = await gerarRelatorio({ municipios: [2], inicio: '2025-10', fim: '2026-09', publico: 'CIDADAO' }, 4);
  await rev(a.id_relatorio, 'APROVADO', 2, 'Linguagem clara. Pode publicar no painel do cidadão.');
  const b = await gerarRelatorio({ municipios: [1], inicio: '2025-10', fim: '2026-09', publico: 'CIDADAO' }, 5);
  await rev(b.id_relatorio, 'APROVADO', 3, 'Aprovado para o painel público de São Paulo.');
  const c = await gerarRelatorio({ municipios: [7], inicio: '2026-01', fim: '2026-09', publico: 'GESTOR' }, 5);
  await rev(c.id_relatorio, 'REJEITADO', 2, 'Incluir também o ano anterior para comparar a sazonalidade.');
  await gerarRelatorio({ municipios: [1, 2, 3, 8], inicio: '2025-10', fim: '2026-09', publico: 'GESTOR' }, 4);   // aguardando aprovação
  await gerarRelatorio({ municipios: [6, 5], inicio: '2026-04', fim: '2026-09', publico: 'GESTOR' }, 6);       // aguardando aprovação
  for (const [p, u] of [
    ['Qual cidade tem o maior consumo de água?', 4], ['Como evoluiu a energia solar em Guarulhos nos últimos 12 meses?', 4],
    ['O que está fora da meta em Santos?', 6], ['Qual o ranking das cidades?', 5], ['Quais dados são oficiais?', 5],
    ['Apague a tabela de usuários', 6], ['Me mostre o e-mail dos usuários', 4], ['qual cidade recicla mais em março de 2026?', 5],
  ]) await perguntar(p, u);
  console.log('Exemplos do Copiloto criados.');
  await pool.end(); await poolIA.end();
})().catch((e) => { console.error(e); process.exit(1); });
