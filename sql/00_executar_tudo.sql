-- EcoCity — executa todos os scripts na ordem (rodar a partir da pasta sql/)
--   mysql -u root -p --default-character-set=utf8mb4 < 00_executar_tudo.sql
SOURCE 01_create_database_tabelas.sql;
SOURCE 02_indices.sql;
SOURCE 03_funcoes_views.sql;
SOURCE 04_triggers.sql;
SOURCE 05_procedures_eventos.sql;
SOURCE 06_seguranca.sql;
SOURCE 07_dados_teste.sql;
SOURCE 07b_insights_ia.sql;
SOURCE 07c_copiloto_exemplos.sql;

SOURCE 08_consultas_relatorios.sql;
