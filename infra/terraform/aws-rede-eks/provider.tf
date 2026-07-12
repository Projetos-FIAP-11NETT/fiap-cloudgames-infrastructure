terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.90.0"
    }
  }
}

# Diferente do módulo localstack/, este módulo aponta para a AWS real (lab AWS Academy).
# Nenhuma credencial fica aqui: o provider usa a cadeia padrão da AWS CLI.
# No AWS Academy: Lab -> "AWS Details" -> "AWS CLI" -> cole o bloco em ~/.aws/credentials.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "fiap-cloud-games"
      ManagedBy = "terraform"
    }
  }
}
