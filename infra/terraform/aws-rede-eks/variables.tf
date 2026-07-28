variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "fiapcloudgames"
}

#
# REDE
#

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# Mínimo 2 AZs (requisito do EKS); 3 recomendado para produção.
variable "az_count" {
  type    = number
  default = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count deve ser 2 ou 3."
  }
}

# true  = 1 único NAT Gateway (economia — dev/homologação/lab)
# false = 1 NAT Gateway por AZ (produção — uma AZ caindo não afeta as outras)
variable "single_nat_gateway" {
  type    = bool
  default = true
}

# ECR
variable "ecr_repositories" {
  description = "Lista de repositórios ECR a serem criados"
  type        = list(string)
  default = [
    "projetofiap/catalog-api",
    "projetofiap/payments-api",
    "projetofiap/users-api",
  ]
}

#
# EKS
#

variable "cluster_name" {
  type    = string
  default = "fiapcloudgames-cluster"
}

variable "cluster_version" {
  type    = string
  default = "1.30"
}

# As roles do EKS já existem no lab AWS Academy (não é permitido criar IAM roles lá).
# Copie os NOMES exatos do console IAM para o terraform.tfvars (ver terraform.tfvars.example).
variable "cluster_role_name" {
  type        = string
  description = "Nome da IAM Role do cluster EKS (ex.: c216...-LabEksClusterRole-xxxx)"
}

variable "node_role_name" {
  type        = string
  description = "Nome da IAM Role dos worker nodes (ex.: c216...-LabEksNodeRole-xxxx)"
}

#
# NODE GROUP
#

variable "node_group_name" {
  type    = string
  default = "ng-apps"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_ami_type" {
  type    = string
  default = "AL2023_x86_64_STANDARD"
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "node_disk_size" {
  type    = number
  default = 20
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 2
}
