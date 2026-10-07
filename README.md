# ToggleMaster — Fase 2 (Microsserviços)

Plataforma de gerenciamento de Feature Flags dividida em 5 microsserviços, conteinerizados com Docker e orquestrados localmente com Docker Compose. Projeto do Tech Challenge da Fase 2 da POSTECH DevOps.

## Arquitetura

| Serviço | Linguagem | Porta | Responsabilidade | Data store |
|---|---|---|---|---|
| `auth-service` | Go | 8001 | Criação e validação de chaves de API | PostgreSQL (`auth_db`) |
| `flag-service` | Python | 8002 | CRUD das feature flags | PostgreSQL (`flags_db`) |
| `targeting-service` | Python | 8003 | Regras de segmentação (ex: porcentagem) | PostgreSQL (`targeting_db`) |
| `evaluation-service` | Go | 8004 | Hot path: decide `true`/`false` e publica eventos | Redis (cache) + SQS (produtor) |
| `analytics-service` | Python | 8005 | Worker: consome eventos e grava análises | SQS (consumidor) + DynamoDB |

Fluxo: o cliente chama `/evaluate` → o `evaluation-service` busca a flag no Redis (ou, em caso de cache miss, no `flag-service` e no `targeting-service`, que validam a chave no `auth-service`) → responde e envia um evento para a fila → o `analytics-service` consome o evento e grava no DynamoDB.

### Contêineres do ambiente local

| Contêiner | Imagem | Porta no host | Papel |
|---|---|---|---|
| `postgres-auth` | `postgres:16-alpine` | 5432 | Banco do `auth-service` |
| `postgres-app` | `postgres:16-alpine` | 5433 | Bancos do `flag-service` e do `targeting-service` |
| `redis` | `redis:7-alpine` | 6379 | Cache do `evaluation-service` |
| `dynamodb-local` | `amazon/dynamodb-local` | 8000 | Tabela `ToggleMasterAnalytics` |
| `elasticmq` | `softwaremill/elasticmq-native` | 9324 | Emulador de SQS (fila `togglemaster-events`) |
| `dynamodb-init` | `amazon/aws-cli` | — | Cria a tabela e encerra (`Exited (0)`) |
| 5 microsserviços | build local (`*:dev`) | 8001–8005 | Aplicação |

O desafio pede 9 contêineres (5 apps + 4 data stores). O `elasticmq` é um 10º contêiner porque a AWS SQS não tem versão local oficial. Com ele, o ambiente roda 100% offline, sem credenciais da AWS. Para usar a SQS real, veja [Usando a SQS real da AWS](#usando-a-sqs-real-da-aws).

## Pré-requisitos

- Docker Desktop com integração WSL ativada (Settings → Resources → WSL Integration), ou Docker Engine + Compose v2
- `curl`
- Go 1.21+ (só para regenerar `go.sum`, se necessário)
- AWS CLI v2 (opcional; também é possível usar a CLI via contêiner, como nos exemplos abaixo)

## Estrutura do projeto

```
togglemaster/
├── docker-compose.yml
├── .env.example
├── .gitignore
├── local/
│   ├── elasticmq/elasticmq.conf        # cria a fila togglemaster-events
│   ├── postgres-app/init-dbs.sh        # cria flags_db e targeting_db + schemas
│   └── postgres-auth/02-seed.sql       # chave de serviço pré-cadastrada (só local)
├── auth-service/
├── flag-service/
├── targeting-service/
├── evaluation-service/
└── analytics-service/
```

Cada serviço contém seu próprio `Dockerfile`, `.dockerignore` e `db/init.sql` (quando usa PostgreSQL).

## Como rodar

```bash
cd ~/togglemaster
cp .env.example .env              # apenas na primeira vez
docker compose up --build -d
docker compose ps
```

Resultado esperado: todos os contêineres `Up` (os Postgres, o Redis e os serviços Python como `healthy`) e o `dynamodb-init` como `Exited (0)`.

## Como testar

### 1. Health check dos 5 serviços

```bash
for p in 8001 8002 8003 8004 8005; do curl -s localhost:$p/health; echo; done
```

Saída esperada: `{"status":"ok"}` cinco vezes.

### 2. (Opcional) Criar uma nova chave de API

```bash
curl -s -X POST localhost:8001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer admin-secreto-123" \
  -d '{"name":"demo"}'
```

### 3. Criar flag, regra e avaliar

Os exemplos usam a chave pré-cadastrada pelo seed local.

```bash
KEY=tm_key_local_evaluation_service_dev

curl -s -X POST localhost:8002/flags \
  -H "Content-Type: application/json" -H "Authorization: Bearer $KEY" \
  -d '{"name":"enable-new-dashboard","is_enabled":true}'

curl -s -X POST localhost:8003/rules \
  -H "Content-Type: application/json" -H "Authorization: Bearer $KEY" \
  -d '{"flag_name":"enable-new-dashboard","rules":{"type":"PERCENTAGE","value":50}}'

curl -s "localhost:8004/evaluate?user_id=user-123&flag_name=enable-new-dashboard"
curl -s "localhost:8004/evaluate?user_id=user-123&flag_name=enable-new-dashboard"   # 2ª chamada: Cache HIT
```

### 4. Verificar cache e fila

```bash
docker compose logs evaluation-service | grep -E "Cache (HIT|MISS)|SQS"
docker compose logs analytics-service | grep -E "Recebidas|salvo no DynamoDB"
```

### 5. Verificar os dados no DynamoDB

```bash
docker run --rm --network togglemaster_default \
  -e AWS_ACCESS_KEY_ID=local -e AWS_SECRET_ACCESS_KEY=local -e AWS_DEFAULT_REGION=us-east-1 \
  amazon/aws-cli dynamodb scan --table-name ToggleMasterAnalytics \
  --endpoint-url http://dynamodb-local:8000
```

Com a AWS CLI instalada no WSL, o equivalente é:

```bash
AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=local \
aws dynamodb scan --table-name ToggleMasterAnalytics \
  --endpoint-url http://localhost:8000 --region us-east-1
```

## Parar e resetar

```bash
docker compose down        # para os contêineres e mantém os dados
docker compose down -v     # apaga os volumes: init.sql e seed são reaplicados no próximo up
```

Os scripts em `/docker-entrypoint-initdb.d/` do Postgres só rodam na primeira criação do volume. Após alterar qualquer `init.sql`, use `docker compose down -v`.

## Usando a SQS real da AWS

Para manter exatamente 9 contêineres, remova o serviço `elasticmq` do compose e preencha no `.env`:

```bash
AWS_SQS_URL=https://sqs.us-east-1.amazonaws.com/<ACCOUNT_ID>/<FILA>
AWS_SQS_ENDPOINT_URL=
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_SESSION_TOKEN=...        # obrigatório no AWS Academy
```

`AWS_SQS_ENDPOINT_URL` vazio faz os serviços usarem o endpoint oficial da AWS. As credenciais do AWS Academy expiram a cada sessão do lab.

## Correções e modificações nos arquivos originais

Os repositórios originais não compilavam ou não rodavam localmente. As alterações abaixo foram necessárias.

### auth-service (Go)

| Arquivo | Mudança | Motivo |
|---|---|---|
| `go.mod` | Removida a linha `github.com/jackc/pgx/v4/stdlib v4.18.3 // indirect` | `stdlib` é um pacote dentro do módulo `pgx/v4`, não um módulo separado; o `go mod tidy` falhava |
| `go.sum` | Gerado com `go mod tidy` | Não existia; o `COPY go.mod go.sum` do Dockerfile falhava |
| `main.go` | Removido o import `fmt`; `pgx/v4/stdlib` virou blank import (`_`) | Imports sem uso são erro de compilação em Go; o `_` registra o driver `"pgx"` usado no `sql.Open` |
| `key.go` | Removido o import `fmt` | Import sem uso |
| `handlers.go` | Removidos os imports `crypto/sha256` e `encoding/hex` | Sem uso; o hash é feito por `hashAPIKey()` em `key.go` |
| `Dockerfile` | Novo: multi-stage `golang:1.22-alpine` → `distroless/static:nonroot` | Requisito do desafio; imagem pequena, sem shell, executada como não-root |
| `.dockerignore` | Novo | Impede que `.env` e `.git` entrem na imagem |

### evaluation-service (Go)

| Arquivo | Mudança | Motivo |
|---|---|---|
| `go.sum` | Regenerado com `go mod tidy` | Estava corrompido (era uma cópia do `go.mod`) |
| `evaluator.go` | Import `context` trocado por `os` | `context` não era usado e `os.Getenv` era chamado sem o import |
| `main.go` | Suporte opcional a `AWS_SQS_ENDPOINT_URL` | Permite usar o ElasticMQ localmente; vazio na nuvem, sem mudança de comportamento |
| `Dockerfile` | Novo, igual ao do `auth-service` | A imagem distroless já traz os CA certificates necessários para HTTPS com a SQS real |
| `.dockerignore` | Novo | Mesmo motivo do `auth-service` |

### analytics-service (Python)

| Arquivo | Mudança | Motivo |
|---|---|---|
| `app.py` | `endpoint_url` lido de `AWS_SQS_ENDPOINT_URL` e `AWS_DYNAMODB_ENDPOINT_URL` nos clientes boto3 | O `boto3==1.26.50` ignora `AWS_ENDPOINT_URL` e sempre acessava a AWS real (`InvalidClientTokenId`) |
| `requirements.txt` | Adicionado `Werkzeug==2.2.3` | O `Flask==2.2.2` é incompatível com o Werkzeug 3.x (`Worker failed to boot`) |
| `Dockerfile` | Novo: multi-stage `python:3.11-slim`, `--workers 1 --threads 2` | Um consumidor SQS por pod, para que o HPA escale por número de pods |
| `.dockerignore` | Novo | Mesmo motivo dos demais |

### flag-service e targeting-service (Python)

| Arquivo | Mudança | Motivo |
|---|---|---|
| `requirements.txt` | Adicionado `Werkzeug==2.2.3` | Mesma incompatibilidade do `analytics-service` |
| `Dockerfile` | Novo: multi-stage `python:3.11-slim`, `--workers 2` sem threads | O `SimpleConnectionPool` do psycopg2 não é thread-safe; a concorrência vem de processos (até 10 conexões por pod) |
| `.dockerignore` | Novo | Mesmo motivo dos demais |

### Raiz do projeto (arquivos novos)

| Arquivo | Função |
|---|---|
| `docker-compose.yml` | Sobe os 5 serviços e os data stores, com healthchecks e ordem de inicialização (`depends_on` + `service_healthy`) |
| `.env.example` | Modelo de configuração (senhas e alternativa de SQS real) |
| `.gitignore` | Impede o commit do `.env` |
| `local/postgres-app/init-dbs.sh` | Cria `flags_db` e `targeting_db` na mesma instância e aplica os schemas |
| `local/postgres-auth/02-seed.sql` | Pré-cadastra a chave `tm_key_local_evaluation_service_dev` |
| `local/elasticmq/elasticmq.conf` | Cria a fila `togglemaster-events` |

## Observações de segurança

- A chave `tm_key_local_evaluation_service_dev` e as senhas padrão do `.env.example` existem **apenas para o ambiente local**. Na nuvem, gere uma chave real via `POST /admin/keys` e injete todas as credenciais por Secrets.
- O `.env` está no `.gitignore` e nos `.dockerignore`; nunca o versione nem o copie para as imagens.
- Todas as imagens rodam com usuário não-root.

## Solução de problemas

| Sintoma | Causa provável | Solução |
|---|---|---|
| Serviço Python em `Restarting (3)` | Erro de import (ex: Werkzeug incompatível) | `docker compose run --rm --no-deps --entrypoint python <serviço> -c "import app"` mostra o erro real |
| `"/go.sum": not found` ou `malformed go.sum` | `go.sum` ausente ou corrompido | `cd <serviço> && rm -f go.sum && go mod tidy` |
| `imported and not used` no build Go | Correções de import não aplicadas | Ver a seção de correções acima |
| `InvalidClientTokenId` no analytics/evaluation | Serviço acessando a AWS real em vez do emulador | Conferir `AWS_SQS_ENDPOINT_URL` e o `endpoint_url` no `app.py` |
| Tabelas ou chave de seed ausentes | Volume criado antes dos scripts de init | `docker compose down -v && docker compose up -d` |
