variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "stage_name" {
  type    = string
  default = "dev"
}

variable "api_name" {
  type    = string
  default = "local-api-gateway-v1"
}

variable "lambda_name" {
  type    = string
  default = "fiap-api-authorizer"
}

variable "allow_dev_stage_bypass" {
  type    = string
  default = "false"
}

variable "container_port" {
  type    = string
  default = "8080"
}

variable "firebase_project_id" {
  type    = string
  default = ""
}

variable "jwks_metadata_address" {
  type    = string
  default = ""
}