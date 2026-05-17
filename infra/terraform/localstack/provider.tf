terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.90.0" # verifica qual é a mais recente
    }
  }
}

provider "aws" {

  access_key = "test"
  secret_key = "test"

  region = var.aws_region

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {

    apigateway = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    iam        = "http://localhost:4566"
    sts        = "http://localhost:4566"

  }
}