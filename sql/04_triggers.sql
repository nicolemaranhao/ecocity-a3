-- =====================================================================
--  EcoCity — Script 04: triggers (qualidade de dados, auditoria e alertas)
-- =====================================================================
USE ecocity;

DELIMITER $$

-- ---------------------------------------------------------------------
-- T1: Validação e marcação de qualidade antes de inserir um DADO
--     - data_referencia é normalizada para o 1º dia do mês (dados mensais)
--     - valores 3x acima (ou 70% abaixo) da média dos 3 meses anteriores
--       são marcados como SUSPEITO para revisão (não são descartados)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_dado_bi $$
CREATE TRIGGER trg_dado_bi
BEFORE INSERT ON dado
FOR EACH ROW
BEGIN
  DECLARE v_media DECIMAL(16,4);

  IF NEW.data_referencia > CURRENT_DATE THEN
     SIGNAL SQLSTATE '45000'
       SET MESSAGE_TEXT = 'Data de referência no futuro não é permitida.';
  END IF;

  SET NEW.data_referencia = DATE_FORMAT(NEW.data_referencia, '%Y-%m-01');

  SELECT AVG(valor) INTO v_media
  FROM dado
  WHERE id_municipio  = NEW.id_municipio
    AND id_metrica = NEW.id_metrica
    AND qualidade  = 'VALIDO'
    AND data_referencia BETWEEN DATE_SUB(NEW.data_referencia, INTERVAL 3 MONTH)
                            AND DATE_SUB(NEW.data_referencia, INTERVAL 1 MONTH);

  IF v_media IS NOT NULL AND v_media > 0
     AND (NEW.valor > v_media * 3 OR NEW.valor < v_media * 0.3) THEN
     SET NEW.qualidade = 'SUSPEITO';
  END IF;
END $$

-- T2/T3: Auditoria de alterações e exclusões em DADO
DROP TRIGGER IF EXISTS trg_dado_au $$
CREATE TRIGGER trg_dado_au
AFTER UPDATE ON dado
FOR EACH ROW
BEGIN
  INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
  VALUES ('dado', 'UPDATE', OLD.id_dado, CURRENT_USER(),
          JSON_OBJECT('valor', OLD.valor, 'qualidade', OLD.qualidade, 'origem', OLD.origem),
          JSON_OBJECT('valor', NEW.valor, 'qualidade', NEW.qualidade, 'origem', NEW.origem, 'referencia', NEW.referencia_origem));
END $$

DROP TRIGGER IF EXISTS trg_dado_ad $$
CREATE TRIGGER trg_dado_ad
AFTER DELETE ON dado
FOR EACH ROW
BEGIN
  INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos)
  VALUES ('dado', 'DELETE', OLD.id_dado, CURRENT_USER(),
          JSON_OBJECT('id_municipio', OLD.id_municipio, 'id_metrica', OLD.id_metrica,
                      'data_referencia', OLD.data_referencia, 'valor', OLD.valor));
END $$

-- T4: Auditoria de mudança de status / orçamento das AÇÕES
DROP TRIGGER IF EXISTS trg_acao_au $$
CREATE TRIGGER trg_acao_au
AFTER UPDATE ON acao
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status OR OLD.orcamento <> NEW.orcamento THEN
    INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
    VALUES ('acao', 'UPDATE', OLD.id_acao, CURRENT_USER(),
            JSON_OBJECT('status', OLD.status, 'orcamento', OLD.orcamento),
            JSON_OBJECT('status', NEW.status, 'orcamento', NEW.orcamento));
  END IF;
END $$

-- T5: Impede que uma ação CANCELADA ou CONCLUIDA volte a ser PLANEJADA
DROP TRIGGER IF EXISTS trg_acao_bu $$
CREATE TRIGGER trg_acao_bu
BEFORE UPDATE ON acao
FOR EACH ROW
BEGIN
  IF OLD.status IN ('CONCLUIDA','CANCELADA') AND NEW.status = 'PLANEJADA' THEN
     SIGNAL SQLSTATE '45000'
       SET MESSAGE_TEXT = 'Ação concluída/cancelada não pode voltar para PLANEJADA.';
  END IF;
END $$

-- T6: Alerta automático — se um indicador ficar mais de 40% distante da meta
--     (no sentido ruim) no MÊS MAIS RECENTE, é criado/atualizado um alerta
--     ALERTA_META (CRITICO). Se o indicador melhorar, o alerta automático sai.
DROP PROCEDURE IF EXISTS sp_avaliar_alerta_meta $$
CREATE PROCEDURE sp_avaliar_alerta_meta(IN p_ind SMALLINT UNSIGNED, IN p_mun SMALLINT UNSIGNED,
                                        IN p_periodo DATE, IN p_valor DECIMAL(14,4), IN p_origem VARCHAR(8))
BEGIN
  DECLARE v_meta DECIMAL(12,4);
  DECLARE v_sentido VARCHAR(15);
  DECLARE v_nome VARCHAR(100);
  DECLARE v_desvio DECIMAL(10,2);
  DECLARE v_titulo VARCHAR(150);
  DECLARE v_desc TEXT;

  -- só o mês mais recente do indicador/município gera alerta
  IF NOT EXISTS (SELECT 1 FROM indicador_valor
                 WHERE id_indicador = p_ind AND id_municipio = p_mun AND periodo > p_periodo) THEN

    SELECT sentido, nome INTO v_sentido, v_nome FROM indicador WHERE id_indicador = p_ind;
    SET v_meta = fn_meta_vigente(p_ind, p_mun, p_periodo);      -- meta em vigor naquele mês

    SET v_desvio = CASE WHEN v_sentido = 'MENOR_MELHOR'
                        THEN (p_valor - v_meta) / v_meta * 100
                        ELSE (v_meta - p_valor) / v_meta * 100 END;
    SET v_titulo = CONCAT(v_nome, ': ', ROUND(v_desvio,1), '% distante da meta');
    SET v_desc = CONCAT('Valor ', ROUND(p_valor,2), ' em ', DATE_FORMAT(p_periodo, '%m/%Y'), ' (meta ', ROUND(v_meta,2), ').',
                        CASE p_origem WHEN 'ESTIMADO' THEN ' Atenção: calculado com dado ESTIMADO.'
                                      WHEN 'DERIVADO' THEN ' Calculado a partir de dado oficial de período maior.'
                                      ELSE ' Calculado com dados oficiais do mês.' END,
                        ' Gerado automaticamente por regra de negócio.');

    IF v_desvio > 40 THEN
      IF EXISTS (SELECT 1 FROM analise_ia WHERE id_indicador = p_ind AND id_municipio = p_mun
                   AND tipo = 'ALERTA_META' AND status = 'NOVA') THEN
        UPDATE analise_ia SET titulo = v_titulo, descricao = v_desc, gerada_em = NOW()
        WHERE id_indicador = p_ind AND id_municipio = p_mun AND tipo = 'ALERTA_META' AND status = 'NOVA';
      ELSEIF NOT EXISTS (SELECT 1 FROM analise_ia WHERE id_indicador = p_ind AND id_municipio = p_mun
                           AND tipo = 'ALERTA_META' AND status = 'EM_ANALISE') THEN
        INSERT INTO analise_ia (id_indicador, id_municipio, tipo, titulo, descricao, confianca, severidade, modelo_versao)
        VALUES (p_ind, p_mun, 'ALERTA_META', v_titulo, v_desc, 100.00, 'CRITICO', 'regra-trigger-v3');
      END IF;
    ELSE
      DELETE FROM analise_ia WHERE id_indicador = p_ind AND id_municipio = p_mun
                               AND tipo = 'ALERTA_META' AND status = 'NOVA';
    END IF;
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_indicador_valor_ai $$
CREATE TRIGGER trg_indicador_valor_ai
AFTER INSERT ON indicador_valor
FOR EACH ROW
BEGIN
  CALL sp_avaliar_alerta_meta(NEW.id_indicador, NEW.id_municipio, NEW.periodo, NEW.valor, NEW.origem);
END $$

DROP TRIGGER IF EXISTS trg_indicador_valor_au $$
CREATE TRIGGER trg_indicador_valor_au
AFTER UPDATE ON indicador_valor
FOR EACH ROW
BEGIN
  IF NEW.valor <> OLD.valor OR NEW.origem <> OLD.origem THEN
    CALL sp_avaliar_alerta_meta(NEW.id_indicador, NEW.id_municipio, NEW.periodo, NEW.valor, NEW.origem);
  END IF;
END $$

-- T7: Usuários — e-mail em minúsculas e regras de cadastro por perfil:
--   - ADMIN só existe com chave individual (criado pelo DBA, nunca pelo site);
--   - ANALISTA e GESTOR nascem EM_ANALISE: só entram depois que o ADMIN aprova o cadastro profissional.
DROP TRIGGER IF EXISTS trg_usuario_bi $$
CREATE TRIGGER trg_usuario_bi
BEFORE INSERT ON usuario
FOR EACH ROW
BEGIN
  DECLARE v_perfil VARCHAR(30) DEFAULT (SELECT nome FROM perfil WHERE id_perfil = NEW.id_perfil);
  SET NEW.email = LOWER(TRIM(NEW.email));
  IF v_perfil = 'ADMIN' AND NEW.chave_admin_hash IS NULL THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Administrador só pode ser criado pelo DBA, com chave individual.';
  END IF;
  IF v_perfil IN ('ANALISTA','GESTOR') THEN SET NEW.status_cadastro = 'EM_ANALISE'; END IF;
END $$

DROP TRIGGER IF EXISTS trg_usuario_bu $$
CREATE TRIGGER trg_usuario_bu
BEFORE UPDATE ON usuario
FOR EACH ROW
BEGIN
  DECLARE v_perfil VARCHAR(30) DEFAULT (SELECT nome FROM perfil WHERE id_perfil = NEW.id_perfil);
  IF v_perfil = 'ADMIN' AND NEW.chave_admin_hash IS NULL THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ninguém vira administrador sem chave individual (só o DBA concede).';
  END IF;
  IF v_perfil IN ('ANALISTA','GESTOR') AND NEW.status_cadastro = 'ATIVO'
     AND (OLD.status_cadastro <> 'ATIVO' OR NEW.id_perfil <> OLD.id_perfil)
     AND NOT EXISTS (SELECT 1 FROM cadastro_profissional c WHERE c.id_usuario = NEW.id_usuario
                     AND c.status = 'APROVADO' AND c.valido_ate >= CURRENT_DATE) THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Analista ou gestor só fica ativo com cadastro profissional aprovado pelo administrador.';
  END IF;
END $$

-- T7b: mudança de perfil ou de situação do cadastro vai para a auditoria
DROP TRIGGER IF EXISTS trg_usuario_au $$
CREATE TRIGGER trg_usuario_au
AFTER UPDATE ON usuario
FOR EACH ROW
BEGIN
  IF NEW.id_perfil <> OLD.id_perfil OR NEW.status_cadastro <> OLD.status_cadastro THEN
    INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
    VALUES ('usuario', 'UPDATE', OLD.id_usuario, CURRENT_USER(),
            JSON_OBJECT('id_perfil', OLD.id_perfil, 'status_cadastro', OLD.status_cadastro),
            JSON_OBJECT('id_perfil', NEW.id_perfil, 'status_cadastro', NEW.status_cadastro));
  END IF;
END $$


-- ---------------------------------------------------------------------
-- T8/T9: COPILOTO — revisão humana obrigatória dos relatórios da IA
--   - um relatório APROVADO ou REJEITADO não pode mais ter o texto alterado;
--   - quem pediu o relatório não pode aprová-lo (segregação de funções);
--   - toda mudança de status fica na auditoria.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_relatorio_bu $$
CREATE TRIGGER trg_relatorio_bu
BEFORE UPDATE ON relatorio_ia
FOR EACH ROW
BEGIN
  IF OLD.status <> 'RASCUNHO' AND (NEW.conteudo <> OLD.conteudo OR NEW.dados_usados <> OLD.dados_usados) THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Relatório já revisado não pode ter o texto alterado.';
  END IF;
  IF OLD.status <> 'RASCUNHO' AND NEW.status <> OLD.status THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Relatório já revisado não pode mudar de situação.';
  END IF;
  IF NEW.status <> 'RASCUNHO' AND OLD.status = 'RASCUNHO' THEN
     IF NEW.revisado_por IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe quem revisou o relatório.';
     END IF;
     IF NEW.revisado_por = NEW.solicitado_por THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quem pediu o relatório não pode aprová-lo (revisão por outra pessoa).';
     END IF;
     SET NEW.revisado_em = NOW();
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_relatorio_au $$
CREATE TRIGGER trg_relatorio_au
AFTER UPDATE ON relatorio_ia
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
    VALUES ('relatorio_ia', 'UPDATE', OLD.id_relatorio, CURRENT_USER(),
            JSON_OBJECT('status', OLD.status),
            JSON_OBJECT('status', NEW.status, 'revisado_por', NEW.revisado_por, 'comentario', NEW.comentario_revisao));
  END IF;
END $$


-- ---------------------------------------------------------------------
-- T10/T11: ANÁLISES DOS ANALISTAS
--   - análise em revisão ou publicada não pode ter o texto alterado
--     (para corrigir, o revisor devolve e o autor envia uma nova versão);
--   - toda mudança de situação vai para a auditoria.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_analise_pub_bu $$
CREATE TRIGGER trg_analise_pub_bu
BEFORE UPDATE ON analise_publicada
FOR EACH ROW
BEGIN
  IF OLD.status IN ('EM_REVISAO','PUBLICADA','ARQUIVADA')
     AND (NEW.titulo <> OLD.titulo OR NEW.resumo <> OLD.resumo OR NEW.conteudo <> OLD.conteudo
          OR NEW.periodo_inicio <> OLD.periodo_inicio OR NEW.periodo_fim <> OLD.periodo_fim) THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Análise em revisão ou publicada não pode ser editada.';
  END IF;
  IF NEW.id_autor <> OLD.id_autor THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O autor de uma análise não pode ser trocado.';
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_analise_pub_au $$
CREATE TRIGGER trg_analise_pub_au
AFTER UPDATE ON analise_publicada
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
    VALUES ('analise_publicada', 'UPDATE', OLD.id_analise_pub, CURRENT_USER(),
            JSON_OBJECT('status', OLD.status, 'versao', OLD.versao),
            JSON_OBJECT('status', NEW.status, 'versao', NEW.versao, 'revisado_por', NEW.revisado_por,
                        'nivel_confianca', NEW.nivel_confianca));
  END IF;
END $$

-- T12: comentários só em análises já publicadas
DROP TRIGGER IF EXISTS trg_comentario_bi $$
CREATE TRIGGER trg_comentario_bi
BEFORE INSERT ON analise_comentario
FOR EACH ROW
BEGIN
  IF (SELECT status FROM analise_publicada WHERE id_analise_pub = NEW.id_analise_pub) <> 'PUBLICADA' THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só é possível comentar análises publicadas.';
  END IF;
END $$

-- T13: METAS — meta aprovada não muda de valor nem de vigência de início; mudanças vão para a auditoria
DROP TRIGGER IF EXISTS trg_meta_bu $$
CREATE TRIGGER trg_meta_bu
BEFORE UPDATE ON meta
FOR EACH ROW
BEGIN
  IF OLD.status IN ('APROVADA','SUBSTITUIDA','REJEITADA')
     AND (NEW.valor <> OLD.valor OR NEW.vigencia_inicio <> OLD.vigencia_inicio OR NEW.id_indicador <> OLD.id_indicador
          OR NOT (NEW.id_municipio <=> OLD.id_municipio)) THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Meta já decidida não pode ser alterada. Proponha uma nova meta.';
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_meta_au $$
CREATE TRIGGER trg_meta_au
AFTER UPDATE ON meta
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO auditoria (tabela, operacao, id_registro, usuario_bd, dados_antigos, dados_novos)
    VALUES ('meta', 'UPDATE', OLD.id_meta, CURRENT_USER(),
            JSON_OBJECT('status', OLD.status, 'valor', OLD.valor),
            JSON_OBJECT('status', NEW.status, 'valor', NEW.valor, 'vigencia_fim', NEW.vigencia_fim,
                        'parecer_por', NEW.parecer_por, 'aprovada_por', NEW.aprovada_por));
  END IF;
END $$

DELIMITER ;
