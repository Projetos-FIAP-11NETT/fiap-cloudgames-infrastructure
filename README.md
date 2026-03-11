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
   - PgAdmin: `5050`

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
   kubectl apply -R -f
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