# Publicar o EcoCity na nuvem: banco na Aiven + site no Render

O banco de dados (MySQL) fica na **Aiven**. O site e a API (Node.js) ficam no **Render**, que lê o código direto do GitHub.
A Aiven só hospeda bancos de dados, por isso o site precisa de outro serviço.

Tempo total: uns 40 minutos.

---

## Parte 1 — Banco de dados na Aiven

### 1. Criar a conta e o serviço
1. Entre em <https://console.aiven.io> e crie a conta. O teste grátis dura 30 dias e não pede cartão.
2. Clique em **Create service** → **MySQL**.
3. Escolha o plano **Developer** (o menor). Dê o nome `ecocity-mysql` e clique em **Create service**.
4. Espere o status ficar **Running** (uns 5 minutos).

### 2. Anotar os dados de conexão
Na página do serviço, em **Connection information**, anote:

| Campo | Exemplo |
|---|---|
| Host | `ecocity-mysql-nicole.aivencloud.com` |
| Port | `12345` (não é 3306) |
| User | `avnadmin` |
| Password | (clique no olho para ver) |

E clique em **CA certificate → Download** para baixar o arquivo **`ca.pem`**. Guarde numa pasta fácil.

### 3. Conectar pelo MySQL Workbench
1. No Workbench: **+** (nova conexão).
2. Aba **Parameters**: Hostname = Host, Port = Port, Username = `avnadmin`, **Store in Vault** = a senha.
3. Aba **SSL**: **Use SSL** = `Require and Verify CA` e **SSL CA File** = o arquivo `ca.pem`.
4. **Test Connection** → deve aparecer "Successfully made the MySQL connection".

### 4. Conferir uma configuração (1 minuto)
Na conexão nova, rode:

```sql
SELECT @@log_bin_trust_function_creators AS pode_criar_funcoes;
```

- Deu **1** → siga para o passo 5.
- Deu **0** → no console da Aiven, abra o serviço → **Service settings** → **Advanced configuration** → **Configure** e procure `log_bin_trust_function_creators`. Ligue e salve. Se essa opção não aparecer, o banco não deixa criar as funções e triggers; nesse caso, peça ajuda antes de continuar.

### 5. Criar o banco EcoCity
1. **File → Open SQL Script** → escolha **`sql/ecocity_banco_aiven.sql`** (não é o `ecocity_banco_completo.sql`).
2. Clique no **raio**. Leva uns 2 minutos.
3. No final deve aparecer: `Banco EcoCity criado com sucesso!` com **2880** medições.

> Por que um arquivo diferente? Na Aiven o administrador (`avnadmin`) não pode "dar um papel" (role) a um usuário.
> Esse arquivo cria os papéis igual, mas dá as mesmas permissões direto a cada usuário. O acesso final é o mesmo.

### 6. Trocar as senhas dos usuários do banco (recomendado)
As senhas padrão estão no GitHub, que é público. Troque e **anote as novas** (vão no Render):

```sql
ALTER USER 'ecocity_api'@'%' IDENTIFIED BY 'escolha-uma-senha-forte-1';
ALTER USER 'ecocity_ia'@'%'  IDENTIFIED BY 'escolha-uma-senha-forte-2';
ALTER USER 'ecocity_etl'@'%' IDENTIFIED BY 'escolha-uma-senha-forte-3';
```

---

## Parte 2 — Site no Render

### 1. Atualizar o GitHub
Suba a versão nova do projeto para o GitHub (ela tem o arquivo **`render.yaml`** na raiz).

> Se no seu repositório o projeto está dentro de uma pasta (ex.: `ecocity-a3/backend`), mova o `render.yaml` para a raiz do repositório e troque `rootDir: backend` por `rootDir: ecocity-a3/backend`.

### 2. Criar o site
1. Entre em <https://render.com> com a conta do GitHub.
2. **New → Blueprint** → escolha o repositório do EcoCity → **Connect**.
3. O Render lê o `render.yaml` e pede as variáveis abaixo:

| Variável | O que colocar |
|---|---|
| `DB_HOST` | Host da Aiven |
| `DB_PORT` | Port da Aiven |
| `DB_SSL_CA` | abra o `ca.pem` no Bloco de Notas, copie **tudo** (de `-----BEGIN CERTIFICATE-----` até `-----END CERTIFICATE-----`) e cole |
| `DB_PASS` | senha do `ecocity_api` (padrão: `Api#EcoCity2026!`) |
| `DB_IA_PASS` | senha do `ecocity_ia` (padrão: `Ia#EcoCity2026!`) |
| `DB_ETL_PASS` | senha do `ecocity_etl` (padrão: `Etl#EcoCity2026!`) |

4. Clique em **Apply**. O Render instala e liga o site (uns 5 minutos).
5. O link fica no topo da página, tipo `https://ecocity-xxxx.onrender.com`.

### 3. Testar
- `https://SEU-LINK/api/health` → deve mostrar `{"status":"ok"}`.
- Abra o link e entre com um login de demonstração (senha `EcoCity@2026`): `joao.pereira@email.com` (cidadão), `rafael.nunes@ecocity.local` (analista), `marina.duarte@ecocity.local` (gestora).

---

## Bom saber
- **O site grátis do Render "dorme"** depois de 15 minutos sem visitas. O primeiro acesso depois disso demora cerca de 1 minuto. Abra o site uns minutos antes da apresentação.
- **O teste da Aiven dura 30 dias.** Sem cartão cadastrado, o banco é desligado no fim do teste. Depois disso, o plano Developer custa US$ 5 por mês.
- **Robô de coleta:** na nuvem ele começa desligado (`COLETA_AUTOMATICA=false`), porque o arquivo da ANEEL tem ~110 MB e o servidor grátis tem pouca memória. O administrador pode rodar pelo painel em **Administração → Conferir as fontes agora**.
- **Erro "Access denied" no site:** confira `DB_PASS`, `DB_IA_PASS` e `DB_ETL_PASS` no Render (Environment) e clique em **Manual Deploy**.
- **Erro de certificado/SSL:** confira se o `DB_SSL_CA` foi colado inteiro, com as linhas BEGIN e END.
