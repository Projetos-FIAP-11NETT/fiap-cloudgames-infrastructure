# Terraform — VPC + EKS (Fase 4, AWS Academy)

Implementa em Terraform o passo a passo de console descrito em
`.claude/Passo-a-passo-infra.md`: VPC multi-AZ com subnets públicas/privadas,
Internet Gateway, NAT Gateway(s), route tables, tags de descoberta do EKS,
Security Group dos nodes, cluster EKS e managed node group.

> Este módulo aponta para a **AWS real** (lab AWS Academy) — diferente do módulo
> `../localstack/`, que provisiona Lambda + API Gateway no LocalStack local.

## Mapeamento passo a passo → recursos

| Passo (console) | Arquivo / recurso Terraform |
|---|---|
| 1 — VPC `10.0.0.0/16` | `vpc.tf` → `aws_vpc.main` |
| 2 — Internet Gateway | `vpc.tf` → `aws_internet_gateway.main` |
| 3 — Subnets públicas (`10.0.0-2.0/24`) e privadas (`10.0.10-12.0/24`) + auto-assign IP | `vpc.tf` → `aws_subnet.public` / `aws_subnet.private` |
| 4 — NAT Gateway(s) + Elastic IP | `vpc.tf` → `aws_nat_gateway.main` / `aws_eip.nat` |
| 5 — Route tables pública e privada(s) | `vpc.tf` → `aws_route_table.*` |
| 6 — Tags `kubernetes.io/role/(internal-)elb` e `kubernetes.io/cluster/<nome>` | tags nas subnets em `vpc.tf` |
| 7 — SG dos nodes | `eks.tf` → `aws_security_group.eks_nodes` |
| EKS 1–2 — IAM Roles do lab (já existem) | `eks.tf` → `data.aws_iam_role.*` (nomes via `terraform.tfvars`) |
| EKS 3 — Cluster `fiapcloudgames-cluster` v1.30 | `eks.tf` → `aws_eks_cluster.main` |
| EKS 5 — Node group `ng-apps` (t3.medium, 2 nodes, subnets privadas) | `eks.tf` → `aws_eks_node_group.apps` |

## Como usar

1. **Credenciais** (AWS Academy): no lab, abra **AWS Details → AWS CLI** e cole o
   bloco em `~/.aws/credentials`. Nenhuma credencial vai para o código — mesma
   regra "zero hardcoded" do restante do repositório.

2. **Variáveis**: copie o exemplo e preencha os nomes das roles do lab
   (mudam a cada sessão):

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # edite cluster_role_name e node_role_name
   ```

3. **Provisionar**:

   ```bash
   terraform init
   terraform apply
   ```

   O cluster leva ~10–15 min para ficar `Active` e o node group mais alguns minutos.

4. **Conectar o kubectl** (o comando exato sai no output `update_kubeconfig_command`):

   ```bash
   aws eks update-kubeconfig --region us-east-1 --name fiapcloudgames-cluster
   kubectl get nodes
   ```

## Decisões / custos

- `az_count = 2` por padrão (mínimo do EKS); use `3` para o layout completo do passo a passo.
- `single_nat_gateway = true` por padrão (~USD 0,045/h por NAT + tráfego): 1 NAT
  atende todas as subnets privadas. Em produção, use `false` (1 NAT por AZ).
- O nome do cluster nas tags das subnets é derivado de `var.cluster_name` — se
  mudar o nome do cluster, as tags acompanham automaticamente (no console isso
  teria que ser corrigido à mão).
- **Ao final da sessão do lab, rode `terraform destroy`** — NAT/EKS cobram por hora
  e o lab Academy tem orçamento limitado.
