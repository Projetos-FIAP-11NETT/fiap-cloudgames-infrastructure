# MailHog no EKS (fiapcloudgames-cluster)

Manifests para subir o MailHog no namespace `apps`, para captura de e-mails
em ambiente de teste (SMTP fake com UI web).

## Arquivos
- `deployment.yaml` — Deployment com o container `mailhog/mailhog:v1.0.1`, expõe as portas 1025 (SMTP) e 8025 (HTTP/UI).
- `service.yaml` — Service `ClusterIP` interno, para as APIs (`catalog-api`, `users-api`, `payments-api`) enviarem e-mail via SMTP dentro do cluster.
- `service-lb-ui.yaml` — Service `LoadBalancer` opcional (NLB interno) só para a UI web, no mesmo padrão dos NLBs internos já usados pelo cluster. Use apenas se quiser acessar a UI sem port-forward.
- `kustomization.yaml` — aplica os manifests de uma vez com `kubectl apply -k`.

## Deploy

```bash
kubectl apply -k .
# ou, sem kustomize:
kubectl apply -f deployment.yaml -f service.yaml
```

Verifique:

```bash
kubectl get pods -n apps -l app=mailhog
kubectl get svc -n apps -l app=mailhog
```

## Configurar as APIs para usar o MailHog

Dentro do cluster, aponte o SMTP das aplicações (`catalog-api`, `users-api`,
`payments-api`) para:

```
SMTP_HOST=mailhog.apps.svc.cluster.local
SMTP_PORT=1025
```

Nenhuma autenticação é necessária — o MailHog aceita qualquer e-mail e não
envia de verdade, só armazena para inspeção.

## Acessar a UI web

**Opção 1 — port-forward (recomendado no AWS Academy, não gasta NLB):**

```bash
kubectl port-forward svc/mailhog 8025:8025 -n apps
```

Depois acesse http://localhost:8025

**Opção 2 — NLB interno (`service-lb-ui.yaml`):**

Descomente o resource no `kustomization.yaml` e aplique novamente. Isso cria
um Network Load Balancer interno — lembre que o AWS Academy Lab tem cota
limitada de recursos, então use com moderação.

## Observações

- O MailHog guarda os e-mails apenas em memória; se o pod reiniciar, o
  histórico é perdido (não há PVC configurado). Se precisar persistência,
  dá para trocar o storage do MailHog para MongoDB, mas geralmente não vale
  a pena em ambiente de teste.
- `replicas: 1` e `strategy: Recreate` porque o MailHog não foi feito para
  rodar com múltiplas réplicas (cada uma teria sua própria caixa de e-mails).
