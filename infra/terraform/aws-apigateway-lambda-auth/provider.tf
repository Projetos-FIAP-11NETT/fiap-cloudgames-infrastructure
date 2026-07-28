terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.90.0" # verifica qual é a mais recente
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.31.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Credenciais reais: usar as do AWS Academy Lab (via aws configure,
  # variáveis de ambiente AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN,
  # ou o profile configurado). Nunca hardcode credenciais aqui.
}

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}