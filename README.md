# Fiap Cloud Games Infrastructure

Este repositório contém a infraestrutura necessária para executar o conjunto de serviços da aplicação Fiap Cloud Games. Ele inclui manifestos Kubernetes, Docker Compose e arquivos de configuração utilizados durante o desenvolvimento.

---

## 🚀 Pré‑requisitos

- Docker Desktop (com Kubernetes habilitado) **ou** Minikube
- Kubectl instalado e configurado
- Imagens publicadas no [Docker Hub](https://app.docker.com/accounts/projetofiap) 

> Caso utilize Minikube, execute `minikube start --driver=docker` ou driver de sua preferência.

---

## 🧩 Variáveis de ambiente

O arquivo `.env` no diretório raiz define as portas e credenciais usadas pelo `docker-compose`. Configure conforme necessário. A maioria das configurações de Kubernetes são estáticas, mas os segredos (credentials) são gerados a partir dos mesmos valores.

* Este arquivo foi adicionado ao .gitignore, caso necessário entre em contato com o nosso time.

---

## 🐳 Executando com Docker Compose

1. Copie o `.env` para a raiz do projeto 
2. Crie a rede:
    ```bash
    docker network create minha-rede-local-docker
    ```
3. Suba os containers:
   ```bash
   docker-compose -p minha-infra up -d
   ```
4. Acesse os serviços via `http://localhost:<porta>` conforme definido no `.env`:
   - Notification API: `8080`
   - Payments API: `8081`
   - Users API: `8082`
   - Catalog API: `8083`
   - RabbitMQ management: `15672`
   - MailHog web: `8025`
   - LocalStack edge: `4566`
   - PgAdmin: `5050`

   ### LocalStack

   O `docker-compose` também sobe o LocalStack para simular serviços AWS em desenvolvimento local.

   Para usar a interface web e os recursos Pro, preencha `LOCALSTACK_AUTH_TOKEN` no arquivo `.env` com o token pessoal gerado na sua conta.

   Credenciais padrão:

   - `LOCALSTACK_AUTH_TOKEN=<seu-token>`
   - `LOCALSTACK_IMAGE_TAG=latest` (ou `2026.3.0`/superior)
   - `AWS_ACCESS_KEY_ID=test`
   - `AWS_SECRET_ACCESS_KEY=test`
   - `AWS_SESSION_TOKEN=test`
   - `AWS_DEFAULT_REGION=us-east-1`

   Endpoint local:

   - `http://localhost.localstack.cloud:4566`

   Interface web:

   - Abra `https://app.localstack.cloud`
   - Permita o acesso à rede local quando o navegador solicitar
   - A interface se conecta ao seu LocalStack em `http://localhost.localstack.cloud:4566`

   Observação:

   - O endereço `http://localhost:4566` é o endpoint da API, não uma página HTML
   - Se você quiser uma experiência mais integrada ao desktop, o LocalStack Desktop também é uma opção

   Serviços habilitados por padrão:

   - `s3`
   - `sqs`
   - `sns`
   - `iam`
   - `sts`

   Exemplo de uso com AWS CLI:

   ```bash
   aws --endpoint-url=http://localhost:4566 s3 ls
   ```

API Gateway com Lambda Authorizer (LocalStack)

Um script de bootstrap (`localstack-init/create-api-gateway.sh`) cria um `REST API` (API Gateway v1 / `apigateway`) com autorização centralizada via Lambda Authorizer. O fluxo é:

1. **REST API Gateway v1** recebe requisições em `http://localhost.localstack.cloud:4566/restapis/<apiId>/dev/_user_request_`
2. **Lambda Authorizer** valida o JWT e verifica permissões baseadas em roles
3. Requisições autorizadas são roteadas aos serviços locais; não autorizadas retornam 403

#### Regras de Autorização

| Rota | Método | Permissão |
|------|--------|-----------|
| `/catalog` | GET | Público |
| `/catalog` | POST/PUT/DELETE | Admin |
| `/users` | Qualquer | Admin |
| `/payments` | GET/POST | Autenticado (user, admin) |
| `/payments` | PUT/DELETE | Admin |
| `/notification` | GET/POST | Autenticado (user, admin) |
| `/notification` | DELETE | Admin |

#### Lambda Authorizer

Implementado em **Clean Architecture + CQRS** (`.NET 10`):

- **Domain**: regras de autorização, resultado de validação
- **Application**: CQRS Query + Handler para processar autorização
- **Infrastructure**: JWT parsing, IAM policy builder
- **Program.cs**: DI com MediatR

Repositório: `localstack-init/lambda-authorizer/`

Build local:
```bash
cd localstack-init/lambda-authorizer
powershell -ExecutionPolicy Bypass -File build.ps1
```

Desenvolvimento:
- Edite regras em `Infrastructure/AuthorizationRulesService.cs`
- O token JWT é decodificado sem validação de assinatura (dev local)
- Para produção, implemente validação via JWKS do Firebase

#### Invoke do Gateway

```bash
# Token com role 'user'
TOKEN="seu-jwt-aqui"

# Descobrir API ID
API_ID=$(docker compose exec localstack awslocal apigateway get-rest-apis --query "items[?name=='local-api-gateway-v1'].id | [0]" --output text)

# GET /catalog (público)
curl -H "Authorization: Bearer $TOKEN" http://localhost.localstack.cloud:4566/restapis/$API_ID/dev/_user_request_/catalog

# POST /catalog (admin required)
curl -X POST -H "Authorization: Bearer $TOKEN" http://localhost.localstack.cloud:4566/restapis/$API_ID/dev/_user_request_/catalog

# GET /users (admin required)
curl -H "Authorization: Bearer $TOKEN" http://localhost.localstack.cloud:4566/restapis/$API_ID/dev/_user_request_/users
```

Se o token não tiver a role necessária, o gateway retorna:
```
HTTP 403 Forbidden
```



5. Para parar:
   ```bash
   docker-compose down
   ```

---

## ☸️ Deploy em Kubernetes

O diretório `k8s/` contém manifestos (Pod, Deployment, Service, Secrets etc.) separados por micro‑serviço.

### Escolhendo um cluster local

- **Docker Desktop**: alterne o contexto com `kubectl config use-context docker-desktop`.
- **Minikube**: use `kubectl config use-context minikube` e execute `minikube tunnel` para expor NodePorts em `localhost`.

### Aplicando os manifests

1. Ajuste a imagem do deployment caso tenha novas tags:
   ```yaml
   image: projetofiap/<servico>:<tag>
   ```
2. Dentro do diretório do projeto, navega para a pasta k8s:
   ```bash
   cd k8s
   ```
3. Aplique os recursos:
   ```bash
   kubectl apply -R -f .
   ```
4. Verifique os objetos:
   ```bash
   kubectl get all
   ```

### Acessando serviços

Se estiver usando Docker Desktop não precisa de túnel; NodePorts já aparecem em `localhost`.
Para Minikube, iniciar túnel numa janela separada:

```bash
minikube tunnel
```

Em seguida, as APIs ficam disponíveis em `http://localhost:<nodePort>` conforme anotado nos manifests (por exemplo, `30080` para notification-api, `30083` para catalog-api).

---

## 📦 Imagens Docker

As aplicações são construídas a partir do código correspondente e empurradas para `projetofiap/<nome>:<tag>`. Certifique-se de que a tag informada nos deployments existe no registry ou substitua-a por uma versão local.

---

## 🧠 Dicas e notas

- Os `PersistentVolumeClaim` estão configurados para 1Gi; ajuste conforme a necessidade.
- Quando encontrar `ImagePullBackOff`, confirme a tag da imagem e a disponibilidade no Docker Hub.
- O `.env` é usado somente pelo `docker-compose`; o Kubernetes lê valores a partir de Secrets/ConfigMaps.
- Para subir novos serviços, crie diretórios em `k8s/` e siga o padrão de manifestos empregados nos demais.

---

Qualquer dúvida, abra uma issue ou contate a equipe de infraestrutura.