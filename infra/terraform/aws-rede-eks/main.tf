#
# VPC E SUBNETS (Passos 1 a 6 do passo a passo — .claude/Passo-a-passo-infra.md)
#

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Sufixo "1a"/"1b"/"1c" para os Name tags, igual ao passo a passo.
  az_suffixes = [for az in local.azs : substr(az, length(az) - 2, 2)]

  nat_gateway_count = var.single_nat_gateway ? 1 : var.az_count

  # Tags obrigatórias para o EKS/Load Balancer Controller descobrirem as subnets (Passo 6).
  cluster_tag = { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }

  services = {
    catalog = {
      service_name = "catalog-api"
      path_prefix  = "catalog"
    }
    users = {
      service_name = "users-api"
      path_prefix  = "users"
    }
    payments = {
      service_name = "payments-api"
      path_prefix  = "payments"
    }
  }
}

#
# PASSO 1 — VPC
#
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Obrigatório para o EKS resolver os endpoints internos do cluster.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

#
# PASSO 2 — INTERNET GATEWAY
#
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

#
# PASSO 3 — SUBNETS
# Públicas:  10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24
# Privadas: 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24
#
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)

  # "Enable auto-assign public IPv4 address"
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name                     = "${var.project_name}-public-${local.az_suffixes[count.index]}"
      "kubernetes.io/role/elb" = "1"
    },
    local.cluster_tag
  )
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)

  tags = merge(
    {
      Name                              = "${var.project_name}-private-${local.az_suffixes[count.index]}"
      "kubernetes.io/role/internal-elb" = "1"
    },
    local.cluster_tag
  )
}

#
# PASSO 4 — NAT GATEWAY(S)
# Nodes nas subnets privadas saem para a internet (pull de imagens etc.) via NAT,
# sem exposição direta. NAT fica sempre em subnet pública.
#
resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${local.az_suffixes[count.index]}"
  }
}

resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  subnet_id         = aws_subnet.public[count.index].id
  allocation_id     = aws_eip.nat[count.index].id
  connectivity_type = "public"

  tags = {
    Name = "${var.project_name}-nat-${local.az_suffixes[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

#
# PASSO 5.1 — ROUTE TABLE PÚBLICA
#
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#
# PASSO 5.2 — ROUTE TABLE(S) PRIVADA(S)
# single_nat_gateway = true  -> 1 route table apontando para o único NAT
# single_nat_gateway = false -> 1 route table por AZ, cada uma para o NAT da própria AZ
#
resource "aws_route_table" "private" {
  count = local.nat_gateway_count

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = var.single_nat_gateway ? "${var.project_name}-rt-private" : "${var.project_name}-rt-private-${local.az_suffixes[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

# ECR
resource "aws_ecr_repository" "this" {
  for_each = toset(var.ecr_repositories)

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false 
  }

  tags = {
    Project     = "FIAP Cloud Games"
    Environment = "dev"
  }
}

#
# EKS (Passos 7 da rede + Passos 1–5 do EKS — .claude/Passo-a-passo-infra.md)
#

# PASSOS 1 e 2 (EKS) — as IAM Roles já existem no lab AWS Academy; apenas referenciamos.
data "aws_iam_role" "cluster" {
  name = var.cluster_role_name
}

data "aws_iam_role" "nodes" {
  name = var.node_role_name
}

#
# PASSO 7 (rede) — SECURITY GROUP DOS NODES
#
resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "SG para worker nodes do EKS"
  vpc_id      = aws_vpc.main.id

  # Comunicação entre nodes/pods (o próprio SG como origem)
  ingress {
    description = "Node-to-node / pod-to-pod"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Saida liberada"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-nodes-sg"
  }
}

# HTTPS 443 a partir do SG do Control Plane — só existe depois do cluster criado,
# por isso é uma rule separada (evita ciclo de dependência).
resource "aws_security_group_rule" "nodes_https_from_control_plane" {
  type                     = "ingress"
  description              = "HTTPS do Control Plane do EKS"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

#
# PASSO 3 (EKS) — CLUSTER
#
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = data.aws_iam_role.cluster.arn

  vpc_config {
    # Todas as subnets (públicas + privadas), como no passo a passo.
    subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
}

#
# PASSO 5 (EKS) — NODE GROUP
#
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.node_group_name}-lt-"

  # Hop limit 1 (padrão do launch template automático do EKS) bloqueia o
  # acesso ao IMDS de dentro dos Pods (rede do container fica a 2 hops do
  # IMDS, não 1). Sem isso, addons como o EBS CSI Driver não conseguem
  # credenciais via role do node.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # disk_size não pode ser definido no aws_eks_node_group quando um
  # launch_template é usado — precisa vir daqui.
  # Ajuste device_name se o ami_type não for AL2/AL2023 (ex: Bottlerocket
  # usa /dev/xvdb para o volume de dados).
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = var.node_disk_size
      volume_type = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = var.node_group_name
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "apps" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = var.node_group_name
  node_role_arn   = data.aws_iam_role.nodes.arn

  # Apenas as subnets PRIVADAS, como no passo a passo.
  subnet_ids = aws_subnet.private[*].id

  ami_type       = var.node_ami_type
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Garante que rotas/NAT existem antes dos nodes tentarem se registrar no cluster.
  depends_on = [aws_route_table_association.private]
}

#  EBS ADDON
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name                = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Garante que o cluster e os nodes ja estao prontos antes de criar o addon
  # (sem isso o Terraform nao tem edge de dependencia e tenta criar em paralelo,
  # falhando com "No cluster found" enquanto o cluster ainda esta subindo).
  depends_on = [aws_eks_node_group.apps]
}