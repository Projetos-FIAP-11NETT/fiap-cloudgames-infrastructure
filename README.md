# FIAP Cloud Games — Infrastructure

Este repositório contém toda a infraestrutura do FIAP Cloud Games: manifestos Kubernetes, Terraform para provisionar recursos no LocalStack (simulação AWS local) **e** na AWS real via **AWS Academy** (VPC + EKS, API Gateway + Lambda Authorizer), além do código-fonte do Lambda Authorizer em .NET 10.

O repositório suporta dois modos de execução:

- **Local (LocalStack):** todo o ambiente roda no Kubernetes local (Docker Desktop), incluindo o API Gateway e o Lambda Authorizer simulados via LocalStack.
- **AWS real (AWS Academy):** cluster **EKS** provisionado no lab AWS Academy (`infra/terraform/aws-rede-eks`), API Gateway + Lambda Authorizer reais (`infra/terraform/aws-apigateway-lambda-auth`), imagens publicadas no ECR/Docker Hub. Veja [Deploy na AWS real (AWS Academy)](#deploy-na-aws-real-aws-academy).

---

## Visão Geral da Arquitetura

```
Cliente (JWT)
    │
    ▼
API Gateway REST v1 (LocalStack :30466 — ou AWS real via AWS Academy)
    │
    ├─► Lambda Authorizer (.NET 10)
    │       └─► Valida JWT + roles → retorna IAM Policy
    │
    ▼ (Allow)
┌──────────────────────────────────────────────────────┐
│  users-api :30082  │  payments-api :30081             │
│  catalog-api :30083 │  (notification via SQS)         │
└──────────────────────────────────────────────────────┘
    │           │           │            │           │
  PostgreSQL  MongoDB     Redis    Elasticsearch  RabbitMQ / SQS
 (por serviço) (shared)  (shared)    (shared)      + MailHog (e-mail)
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
├── infra/terraform/
│   ├── localstack/                    # Provisiona Lambda + API Gateway no LocalStack
│   │   ├── main.tf
│   │   ├── provider.tf                # Endpoint: http://localhost:30466 (K8s NodePort)
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── aws-rede-eks/                  # AWS real (AWS Academy): VPC + EKS
│   │   └── README.md                  # Passo a passo, IAM roles do lab, custos
│   └── aws-apigateway-lambda-auth/    # AWS real (AWS Academy): API Gateway + Lambda Authorizer
├── k8s/                                # Manifestos Kubernetes
│   ├── shared/                         # MongoDB, Redis, Elasticsearch, RabbitMQ, MailHog, PgAdmin, RedisInsight
│   ├── localstack/                     # LocalStack (NodePort 30466)
│   ├── catalog/                        # Catalog API + PostgreSQL próprio
│   ├── users/                          # Users API + PostgreSQL próprio
│   ├── payments/                       # Payments API + PostgreSQL próprio
│   ├── app-services/                   # Services (ClusterIP/NLB) das APIs, separados dos manifests de app
│   ├── secrets-configs/                # ConfigMaps/Secrets de exemplo (gitignored quando sensíveis)
│   └── register-secrets-configs.ps1    # Script para recriar ConfigMaps/Secrets no cluster (ex.: pós AWS Academy reset)
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
| Elasticsearch | — | `ClusterIP` interno (`elasticsearch:9200`) — sem NodePort; use `kubectl port-forward` para acessar de fora do cluster |
| MailHog SMTP | — | `ClusterIP` interno (`mailhog:1025`) — usado pelas APIs para enviar e-mail dentro do cluster |
| MailHog UI | 8025 (via port-forward) | `kubectl port-forward svc/mailhog 8025:8025 -n apps` — recomendado no AWS Academy para não gastar cota de NLB |

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


## Deploy na AWS real (AWS Academy)

Além do LocalStack, o projeto também sobe (fase 4) na **AWS real, usando uma conta de lab do AWS Academy**. Isso muda algumas premissas em relação a uma conta AWS normal:

| Particularidade do AWS Academy | Como o repositório se adapta |
|---|---|
| Credenciais são **temporárias** (expiram a cada sessão de lab) | Sempre copie o bloco **AWS Details → AWS CLI** do lab para `~/.aws/credentials` antes de rodar Terraform/kubectl — nenhuma credencial é versionada no repo |
| Não é possível criar roles/usuários IAM (`iam:CreateRole` bloqueado) | Terraform reaproveita a role pré-criada do lab (**`LabRole`** para Lambdas, `LabEksClusterRole`/`LabEksNodeRole` — nomes fornecidos via `terraform.tfvars`, mudam a cada sessão) em vez de criar roles novas |
| Algumas ações de serviço são bloqueadas na plataforma (ex.: `ses:*`) | Serviços afetados usam alternativa local — ver [`fiap-cloudgames-notifications-lambda`](../fiap-cloudgames-notifications-lambda), que troca AWS SES por MailHog no cluster |
| Orçamento e tempo de sessão limitados | **Sempre rode `terraform destroy` ao final da sessão** — EKS e NAT Gateway cobram por hora |

### Passo a passo

**1. Atualizar credenciais da sessão AWS Academy**

Copie o bloco do lab (**AWS Details → AWS CLI**) para `~/.aws/credentials`.

**2. Atualizar o Account ID da AWS** nos manifests de deployment (o Account ID muda por conta de lab):

```
k8s/catalog/api/catalog-deployment.yaml
k8s/payments/api/payments-deployment.yaml
k8s/users/api/users-deployment.yaml
```

```yaml
image: [ACCOUNT_ID].dkr.ecr.us-east-1.amazonaws.com/projetofiap/users-api:1
```

**3. Provisionar a infra via Terraform** — primeiro a rede/cluster, depois o API Gateway + Lambda Authorizer (veja também o [README do módulo `aws-rede-eks`](infra/terraform/aws-rede-eks/README.md) para o detalhamento completo, custos e decisões):

```bash
cd infra/terraform/aws-rede-eks
terraform init      # apenas na primeira vez
cp terraform.tfvars.example terraform.tfvars   # preencha cluster_role_name / node_role_name do lab
terraform plan
terraform apply

cd ../aws-apigateway-lambda-auth
terraform init
cp terraform.tfvars.example terraform.tfvars
terraform plan
terraform apply
```

**4. Conectar o `kubectl` ao cluster EKS:**

```bash
aws eks update-kubeconfig --name fiapcloudgames-cluster --region us-east-1
kubectl get nodes
```

**5. Criar Secrets e ConfigMaps:**

```powershell
Set-ExecutionPolicy -Scope Process Bypass   # habilita execução de scripts, se necessário
./k8s/register-secrets-configs.ps1
```

> Como as credenciais/roles do AWS Academy mudam a cada sessão, é comum precisar re-rodar este script (e reaplicar os manifests) sempre que o lab reseta.

**6. Subir os manifestos compartilhados** (Postgres, MongoDB, Redis, Elasticsearch, RabbitMQ, MailHog, PgAdmin, RedisInsight):

```bash
kubectl apply -R -f k8s/shared
```

Em seguida aplique os manifests de cada serviço (`k8s/catalog`, `k8s/users`, `k8s/payments`, `k8s/app-services`) da mesma forma.

**7. Ao encerrar a sessão do lab:**

```bash
cd infra/terraform/aws-apigateway-lambda-auth && terraform destroy
cd ../aws-rede-eks && terraform destroy
```