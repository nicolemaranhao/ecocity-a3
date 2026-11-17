# EcoCity — passo a passo (Windows)

## 1. Colocar o banco no MySQL
1. Abra o **MySQL Workbench**.
2. Clique em **Local instance MySQL80** e digite a senha do root.
3. Menu **File → Open SQL Script...** e escolha `sql/ecocity_banco_completo.sql`.
4. Clique no **raio ⚡** (primeiro raio da barra).
5. No fim aparece: **Banco EcoCity criado com sucesso!** com **2880 medições mensais** (405 oficiais do mês, 1240 oficiais do ano, 1235 estimadas) e mês mais recente **09/2026**, **2 análises publicadas** e **9 metas aprovadas**.
6. No painel da esquerda (**Schemas**), clique com o botão direito e escolha **Refresh All**. Vai aparecer o banco **ecocity**.

## 2. Ver os dados (para os prints)
- Abrir uma tabela: Schemas → ecocity → Tables → botão direito na tabela → **Select Rows**.
- Consultas prontas: File → Open SQL Script → `sql/08_consultas_relatorios.sql`. Clique numa consulta e aperte **Ctrl + Enter** para rodar só ela.

## 3. Diagrama do banco (DER) no Workbench
1. Menu **Database → Reverse Engineer...**
2. **Next** → digite a senha → **Next**.
3. Marque **ecocity** → **Next** → **Next** → **Execute** → **Next** → **Close**.
4. O diagrama aparece. Arraste as tabelas para organizar.
5. Para salvar a imagem: **File → Export → Export as PNG...**

## 4. Ligar o site
Na pasta `backend`, abra o cmd (clique na barra de endereço, digite `cmd`, Enter):
```
npm install
npm start
```
Abra **http://localhost:3000**. Não feche o cmd.

Agora **todo mundo precisa de conta** (até o cidadão). Contas de teste, senha `EcoCity@2026`:

| Perfil | E-mail | O que vê |
|---|---|---|
| Cidadão | joao.pereira@email.com | Visão geral, O que mudou no mês, Alertas, Água, Energia, Lixo e reciclagem, Transporte, Comparar cidades, Mapa, Entenda os dados, Economize em casa, Desafios verdes |
| Analista | rafael.nunes@ecocity.local ou lucia.andrade@ecocity.local | Laboratório, Assistente de relatórios, Análises, Metas, Radar de riscos + Explorar (ver uma cidade, comparar, mapa, mês a mês, entenda os dados) |
| Gestor | marina.duarte@ecocity.local | Sala de situação, Conselheiro IA, Simulador de metas, Ações e resultados, Metas, Radar, Laboratório, Análises + Explorar |
| Admin | admin@ecocity.local (chave `ADM-EcoCity-2026`) | tudo do gestor + Administração (coleta automática e cadastros) |

**Sem código de celular:** todos entram só com e-mail e senha. O admin também digita a chave `ADM-EcoCity-2026` (o campo aparece depois da senha).

**Cadastro:** em "Criar conta" escolha o perfil.
- Cidadão: formulário curto, entra na hora.
- Analista e gestor: 4 etapas (dados, vínculo, comprovante, senha). Fica **em análise** até o admin aprovar em **Central do sistema → Cadastros**.

## 5. Trocar um dado estimado pelo oficial
No Workbench, rode (mudando os valores):
```sql
CALL sp_atualizar_dado_real('Campinas', 2026, 3, 'AGUA_CONSUMIDA', 7012345, 'SANASA mar/2026');
```
(cidade, ano, mês, métrica, valor, fonte)

## 6. Copiloto com IA generativa (opcional)
Sem configurar nada, o Copiloto usa o modelo local. Para usar a IA da Anthropic, coloque a chave no arquivo `backend/.env`:
```
ANTHROPIC_API_KEY=sua-chave
```

## 7. Robô de coleta: o banco se atualiza quando os sites oficiais mudam
O robô entra nos sites dos órgãos públicos, confere se publicaram algo novo e grava no banco **só o que é novo ou foi revisado**.

| Fonte | O que ele pega | Como |
|---|---|---|
| **ANEEL** | energia solar das 8 cidades, **mês a mês** | baixa o arquivo oficial (.zip, ~110 MB) — no máximo 1 vez por semana |
| **SPTrans** | ônibus de São Paulo, **mês a mês** | lê o PDF diário e soma cada mês |
| **EPE** | energia do Estado de SP, mês a mês | lê a planilha oficial (usada para estimar as cidades) |
| **SEEG** | emissões do transporte, **por ano** | pergunta à API (GraphQL) |
| **SNIS/SINISA** (Painel Saneamento) | água: consumo e perdas, **por ano** | baixa a planilha de cada cidade |
| **SINISA** | lixo e reciclagem, **por ano** | procura o arquivo do ano novo no site do Ministério (se vier em .rar, ele avisa) |
| **IBGE** | população | API, quando o painel ganha um ano novo |

**Testar se os sites respondem** (não grava nada no banco), na pasta `backend`:
```
npm run testar-fontes
```
(Para pular o arquivo grande da ANEEL: `npm run testar-fontes -- --sem-aneel`.)

**Atualizar agora**: no site, entre como admin → **Administração → Conferir as fontes agora**. Ou, na pasta `backend`:
```
npm run coletar
```
Para baixar tudo de novo mesmo sem novidade: marque **baixar tudo de novo** na tela, ou `npm run coletar -- --forcar`.

**Ligar o robô sozinho** (no `backend/.env`):
```
COLETA_AUTOMATICA=true
COLETA_INTERVALO_HORAS=24
COLETA_MODO=mensal
```
- Com o site ligado (`npm start`), ele confere as fontes a cada 24 horas. Para funcionar o tempo todo, o servidor precisa ficar ligado (ex.: na nuvem).
- **Modo mensal** (padrão): o painel avança todo mês que a ANEEL e a SPTrans publicam; o que ainda não saiu (água, lixo) fica **estimado** a partir do último dado oficial, e é trocado sozinho quando o órgão publicar.
- **Modo oficial** (`COLETA_MODO=oficial`): o painel só ganha um ano novo quando a água (SNIS) e as emissões (SEEG) daquele ano saírem.

Na tela de Administração aparece, para cada fonte: quando foi conferida, se o site mudou e o que entrou no banco. Isso também fica na tabela **coleta_verificacao** (view `vw_coleta_fontes`).

**Planilhas manuais** (opcional): um CSV com `;` na pasta `dados_reais/entrada` entra na próxima conferência:
```
fonte;metrica;municipio;mes;valor;origem;referencia
3;ENERGIA_CONSUMIDA;Campinas;2024-03;512345;REAL;CPFL mar/2024
```
Quando um dado oficial chega, ele **substitui** o estimado. Um estimado **nunca** substitui um oficial (o banco recusa).

## 8. IA de riscos e alertas
Roda sozinha depois de cada coleta. Para rodar na mão: `npm run alertas`.
Ela avisa quando: a cidade fica 3 meses fora da meta, piora em relação ao ano passado, a previsão dos próximos 3 meses mostra que vai sair da meta, ou aparece um valor muito fora do normal.

## 9. Assistentes (um para cada perfil)
Botão redondo no canto da tela. Cada perfil conversa com um assistente diferente:
- **Cidadão (Eco):** "Como economizar água?", "Como diminuir a conta de luz?", "De onde vêm os dados de água?", "Quais os alertas da minha cidade?".
- **Analista (Eco Analista)** — também em página inteira, menu **Assistente de relatórios**: "Relatório de reciclagem em Sorocaba nos últimos 12 meses", "Compare as perdas de água das 8 cidades", "Fonte do consumo de água em Campinas". O rascunho vira uma análise com o botão **Abrir como nova análise**.
- **Gestor (Conselheiro)** — também em página inteira, menu **Conselheiro IA**: "Onde devo agir primeiro?", "E se as perdas de água de Guarulhos caírem para 20%?", "Que ações melhoram isso?", "O que funcionou nas ações já feitas?". Ele lembra a cidade e o tema da conversa.

Todos respondem a **fonte** dos números e recusam pedidos para alterar o banco ou ver dados pessoais. Com `ANTHROPIC_API_KEY` no `.env`, as respostas ficam mais elaboradas (sempre usando só os números do banco).

## 10. Toda informação mostra a fonte (dentro do próprio dado)
Embaixo de cada número aparece a linha **📎 Fonte: … · ver detalhes**. Ele mostra quem publicou (ex.: SNIS, ANEEL, IBGE), se o dado é **oficial**, **calculado de oficial** ou **estimado**, o texto de referência e o link do site oficial. No Laboratório, clique em qualquer valor da tabela.

## Importante: banco atualizado
Se você ainda não rodou a versão com o script 11 (coleta automática), **rode `sql/ecocity_banco_completo.sql` de novo no Workbench** (passo 1) antes de ligar o site. A versão 12 do site não muda o banco.


## 11. Fotos e vídeos de vocês
Cada área tem um desenho animado em linhas finas. Para trocar por uma foto ou vídeo de vocês, coloque o arquivo em `frontend/assets/midia` e escreva o nome dele no `midia.json` (o passo a passo está em `frontend/assets/midia/LEIA-ME.txt`). Use só fotos/vídeos de vocês ou com licença livre, com o crédito.


## Cidadão x profissionais (o que cada um vê)
- **Cidadão**: vê os números da sua cidade comparados com a **média das 8 cidades** ("melhor que a média", "pior que a média") e a posição entre as 8. **Não vê meta nem nota**.
- **Analista e gestor**: veem a meta e a **Nota EcoCity** (0 a 100). Onde aparece nota, meta ou risco tem um botão **?** que explica a conta.
- Todo número tem um selo: **Oficial do mês**, **Oficial do ano** (total oficial do ano dividido pelos meses) ou **Estimado**.

## Fotos
As fotos da página inicial e das áreas vêm do Unsplash (licença livre) e precisam de **internet**. Sem internet aparece o desenho animado no lugar. Os créditos estão em `frontend/assets/midia/midia.json`.
