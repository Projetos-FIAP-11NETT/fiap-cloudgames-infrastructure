# FIAP Cloud Games — Infrastructure

Este repositório contém toda a infraestrutura do FIAP Cloud Games: manifestos Kubernetes, Terraform para provisionar recursos no LocalStack (simulação AWS local) e o Lambda Authorizer em .NET 10.

---

## Visão Geral da Arquitetura

```
Cliente (JWT)
    │
    ▼
API Gateway REST v1 (LocalStack — K8s NodePort :30466)
    │
    ├─► Lambda Authorizer (.NET 10)
    │       └─► Valida JWT + roles → retorna IAM Policy
    │
    ▼ (Allow)
┌──────────────────────────────────────────────────────┐
│  users-api :30082  │  payments-api :30081             │
│  catalog-api :30083 │  (notification futuramente)     │
└──────────────────────────────────────────────────────┘
    │           │           │           │
  PostgreSQL  MongoDB     Redis      RabbitMQ / SQS / SNS
 (por serviço) (shared)  (shared)    (LocalStack)
```

---

## Pré-requisitos

| Ferramenta | Versão mínima | Uso |
|---|---|---|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | 4.x | Runtime de containers + Kubernetes local |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.28+ | Gerenciar o cluster |
| [.NET SDK](https://dotnet.microsoft.com/download/dotnet/10.0) | 10.0 | Compilar o Lambda Authorizer |
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.5+ | Provisionar recursos no LocalStack |
| [AWS CLI](https://aws.amazon.com/cli/) | 2.x | Interagir com o LocalStack (opcional) |
| PowerShell | 5.1+ | Scripts de build |

**Kubernetes local**: habilite o Kubernetes no Docker Desktop em **Settings → Kubernetes → Enable Kubernetes**.

---

## Estrutura do Repositório

```
fiap-cloudgames-infrastructure/
├── infra/terraform/localstack/   # Provisiona Lambda + API Gateway no LocalStack
│   ├── main.tf
│   ├── provider.tf               # Endpoint: http://localhost:30466 (K8s NodePort)
│   ├── variables.tf
│   └── outputs.tf
├── k8s/                          # Manifestos Kubernetes
│   ├── shared/                   # MongoDB, Redis, RabbitMQ, PgAdmin, RedisInsight
│   ├── localstack/               # LocalStack (NodePort 30466)
│   ├── catalog/                  # Catalog API + PostgreSQL próprio
│   ├── users/                    # Users API + PostgreSQL próprio
│   └── payments/                 # Payments API + PostgreSQL próprio
└── localstack-init/
    ├── create-api-gateway.sh     # Bootstrap alternativo via shell
    └── lambda-authorizer/        # Código-fonte do Lambda Authorizer (.NET 10)
        └── build.ps1             # Gera function.zip
```

---

## Subindo a Infraestrutura

### Passo 1 — Configurar o contexto do Kubernetes

```bash
kubectl config use-context docker-desktop
```

---

### Passo 2 — Criar os Secrets

Os Secrets não são versionados e **não devem ser commitados**. Crie um arquivo local (ex.: `k8s/shared/shared-secret.yaml`) baseado no modelo abaixo, preencha os valores e aplique com `kubectl apply`.

> O arquivo segue o padrão dos demais manifestos do projeto — use `stringData` para não precisar codificar os valores em base64 manualmente.

**Modelo — `shared-secret.yaml`**

```yaml
apiVersion: v1
kind: Secret

metadata:
  name: shared-secret
  labels:
    app: shared
  annotations:
    description: "Secret compartilhado para as APIs de Notificações, Usuário, Catálogo e Pagamento."

type: Opaque

stringData:
  # RabbitMQ
  RABBITMQ_USERNAME: "admin"
  RABBITMQ_PASSWORD: "password"

  # MongoDB
  MONGO_ROOT_USER: "mongoAdmin"
  MONGO_ROOT_PASSWORD: "mongoPassword"
  MONGO_EXPRESS_USER: "admin"
  MONGO_EXPRESS_PASSWORD: "password"
  MONGO_CONNECTION_STRING: "mongodb://mongoAdmin:mongoPassword@mongodb:27017/"
  MONGO_DATABASE_CATALOG: "catalog-db"
  MONGO_EXPRESS_URL: "mongodb://mongoAdmin:mongoPassword@mongodb:27017/"

  # Redis
  REDIS_PASSWORD: "redisPassword"
  REDIS_CONNECTION_STRING: "redis:6379,password=redisPassword,abortConnect=false"

  # New Relic
  NEW_RELIC_LICENSE_KEY_LAMBDA: "<sua-chave>"
  NEW_RELIC_LICENSE_KEY: "<sua-chave>"
  NEW_RELIC_APP_NAME_PAYMENTS: "FiapCloudGames-Payments-Logs"
  NEW_RELIC_APP_NAME_CATALOGS: "FiapCloudGames-Catalog-Logs"
  NEW_RELIC_APP_NAME_USERS: "FiapCloudGames-User-Logs"

  # PostgreSQL
  POSTGRES_USER: "postgresAdmin"
  POSTGRES_PASSWORD: "postgresAdmin"

  # SQS (LocalStack)
  SQS_REGION: "us-east-1"
  SQS_ACCESS_KEY: "test"
  SQS_SECRET_KEY: "test"

  # Firebase
  FIREBASE_CREDENTIAL_PATH: "/app/firebase-service-account.json"
  FIREBASE_APIKEY: "<sua-chave>"
```

Após preencher, aplique:

```bash
kubectl apply -f k8s/shared/shared-secret.yaml
```

Outros Secrets (LocalStack, PgAdmin, secrets individuais de cada API) seguem o mesmo padrão — consulte o time de infra para obter os arquivos correspondentes.

---

### Passo 3 — Aplicar os manifestos Kubernetes

Na raiz do repositório, aplique todos os manifestos de uma vez:

```bash
kubectl apply -R -f k8s/
```

Acompanhe a inicialização dos pods:

```bash
kubectl get pods -w
```

Aguarde todos os pods ficarem com status `Running` antes de continuar.

---

### Passo 4 — Aguardar o LocalStack

O LocalStack precisa estar `Running` e com os serviços ativos antes do Terraform. Verifique o health check via NodePort:

```bash
curl http://localhost:30466/_localstack/health
```

O retorno deve conter `"apigateway": "running"` e `"lambda": "running"`. O pod do LocalStack tem um startup probe de até 120 tentativas (10s cada), portanto pode levar alguns minutos na primeira vez.

---

### Passo 5 — Compilar e implantar o Lambda Authorizer

O Lambda Authorizer é um projeto .NET 10 que precisa ser compilado localmente e depois provisionado no LocalStack via Terraform.

**5.1 — Compilar**

```powershell
cd localstack-init\lambda-authorizer
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
cd ..\..
```

O script gera `function.zip` no diretório do Lambda. Copie-o para o diretório do Terraform:

```powershell
Copy-Item "localstack-init\lambda-authorizer\function.zip" `
          "infra\terraform\localstack\lambda\function.zip"
```

**5.2 — Implantar no LocalStack com Terraform**

O Terraform conecta ao LocalStack via `http://localhost:30466` (NodePort do K8s).

```bash
cd infra/terraform/localstack

# Somente na primeira execução
terraform init

# Provisionar
terraform apply -auto-approve
```

Recursos criados no LocalStack:

| Recurso | Nome |
|---|---|
| IAM Role | `lambda-authorizer-role` |
| Lambda Function | `fiap-api-authorizer` (runtime: `dotnet10`) |
| API Gateway REST v1 | `local-api-gateway-v1` |
| Lambda Authorizer | tipo TOKEN — header `Authorization: Bearer <jwt>` |
| Stage | `dev` |

Ao final, o Terraform exibe:

```
api_id     = "<ID gerado>"
invoke_url = "http://localhost.localstack.cloud:30466/_aws/execute-api/<ID>/dev"
```

---

## Referência de Serviços (NodePorts)

| Serviço | NodePort | Endereço |
|---|---|---|
| LocalStack | 30466 | `http://localhost:30466` |
| Users API | 30082 | `http://localhost:30082` |
| Payments API | 30081 | `http://localhost:30081` |
| Catalog API | 30083 | `http://localhost:30083` |
| PostgreSQL (catalog) | — | interno ao cluster |
| PostgreSQL (users) | — | interno ao cluster |
| PostgreSQL (payments) | — | interno ao cluster |
| PgAdmin | 30050 | `http://localhost:30050` |
| MongoDB | 30017 | `localhost:30017` |
| Mongo Express | 30081 | `http://localhost:30081` |
| Redis | 30379 | `localhost:30379` |
| RedisInsight | 30001 | `http://localhost:30001` |
| RabbitMQ AMQP | 30672 | `localhost:30672` |
| RabbitMQ Management | 31672 | `http://localhost:31672` |

---

## API Gateway — Uso

### Obter o ID da API

```bash
kubectl exec -it deployment/localstack -- \
  awslocal apigateway get-rest-apis \
  --query "items[?name=='local-api-gateway-v1'].id | [0]" \
  --output text
```

### Regras de Autorização

| Rota | Método | Acesso |
|---|---|---|
| `/catalog` | GET | Público (sem token) |
| `/catalog` | POST / PUT / DELETE | Admin |
| `/users` | Qualquer | Admin |
| `/payments` | GET / POST | Autenticado (`user` ou `admin`) |
| `/payments` | PUT / DELETE | Admin |

### Exemplos de requisição

```bash
API_ID="<id-da-api>"
TOKEN="seu-jwt-aqui"
BASE="http://localhost.localstack.cloud:30466/_aws/execute-api/$API_ID/dev"

# GET /catalog — público
curl "$BASE/catalog"

# GET /payments — requer autenticação
curl -H "Authorization: Bearer $TOKEN" "$BASE/payments"

# POST /catalog — requer admin
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Game"}' \
  "$BASE/catalog"
```

Token sem a role necessária retorna `HTTP 403 Forbidden`.

---

## Lambda Authorizer

Código em `localstack-init/lambda-authorizer/` — **.NET 10, Clean Architecture + CQRS**:

```
├── Domain/               # Regras de autorização e resultado de validação
├── Application/          # CQRS Query + Handler
├── Infrastructure/       # JWT parsing (JWKS Firebase), IAM policy builder
├── AuthorizerFunction.cs # Handler invocado pelo API Gateway
├── Program.cs            # DI com MediatR
└── build.ps1             # Gera function.zip
```

Para modificar regras de acesso, edite `Infrastructure/AuthorizationRulesService.cs` e recompile (Passo 5 + Passo 6).

---

## Imagens Docker

As APIs são publicadas em `docker.io/projetofiap/<servico>:latest`. Veja as imagens disponíveis em [Docker Hub — projetofiap](https://app.docker.com/accounts/projetofiap).

Para usar uma tag específica, edite o campo `image` no manifest correspondente em `k8s/`:

```yaml
image: projetofiap/users-api:1.2.0
```

---

## Solução de Problemas

| Sintoma | Causa provável | Solução |
|---|---|---|
| Pod `ImagePullBackOff` | Tag da imagem não existe no registry | Verifique a tag no Docker Hub e corrija o manifest |
| LocalStack `CrashLoopBackOff` | `LOCALSTACK_AUTH_TOKEN` ausente ou inválido | Recrie o secret `localstack-secret` com um token válido |
| Terraform falha em `apply` | LocalStack ainda inicializando | Aguarde o health check em `localhost:30466` responder |
| `403 Forbidden` inesperado | Role incorreta no payload JWT | Verifique o claim `roles` no token |
| `ImagePullBackOff` após update | Cache do nó com imagem antiga | `kubectl rollout restart deployment/<nome>` |
| Pod em `Pending` | PVC sem PersistentVolume disponível | Verifique `kubectl describe pvc` e o storage class |

---

Dúvidas ou problemas? Abra uma issue ou contate a equipe de infraestrutura.
