#
# IAM ROLE
#
# O AWS Academy Lab bloqueia iam:CreateRole, então reaproveitamos a
# LabRole pré-existente na conta em vez de criar uma role nova.
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

#
# LAMBDA
#
resource "aws_lambda_function" "authorizer" {
  function_name    = var.lambda_name
  filename         = "${path.module}/lambda/function.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/function.zip")
  role             = data.aws_iam_role.lab_role.arn
  runtime          = "dotnet10"
  handler          = "FiapCloudGames.Lambda.Authorizer::FiapCloudGames.Lambda.Authorizer.AuthorizerFunction::FunctionHandler"
  timeout          = 60
  memory_size      = 1024

  snap_start {
    apply_on = "None"
  }

  environment {
    variables = merge(
      {
        ALLOW_DEV_STAGE_BYPASS = var.allow_dev_stage_bypass
      },
      var.firebase_project_id != "" ? {
        FIREBASE_PROJECT_ID = var.firebase_project_id
      } : {},
      var.jwks_metadata_address != "" ? {
        JWKS_METADATA_ADDRESS = var.jwks_metadata_address
      } : {}
    )
  }
}

#
# API GATEWAY
#
resource "aws_api_gateway_rest_api" "main" {
  name = var.api_name
}

#
# AUTHORIZER
#
resource "aws_api_gateway_authorizer" "lambda_authorizer" {
  name                             = "lambda-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.main.id
  type                             = "TOKEN"
  authorizer_uri                   = aws_lambda_function.authorizer.invoke_arn
  identity_source                  = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 0
}

locals {
  methods = toset(["GET", "POST", "PUT", "DELETE", "PATCH"])

  dev_stage_bypass_enabled = var.allow_dev_stage_bypass == "true"

  authorization_type = local.dev_stage_bypass_enabled ? "NONE" : "CUSTOM"

  authorizer_id = local.dev_stage_bypass_enabled ? null : aws_api_gateway_authorizer.lambda_authorizer.id

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

  service_method_routes = merge([
    for service_key, service in local.services : {
      for method in local.methods : "${service_key}:${method}" => {
        service_key  = service_key
        service_name = service.service_name
        path_prefix  = service.path_prefix
        method       = method
      }
    }
  ]...)

  public_users_enabled = !local.dev_stage_bypass_enabled
}

#
# SERVIÇOS KUBERNETES (type=LoadBalancer) -> dispara a criação automática
# do NLB interno pelo AWS Load Balancer Controller no EKS
#
# resource "aws_security_group" "nlb_ingress" {
#   for_each    = local.services
#   name        = "${each.value.service_name}-nlb-sg"
#   description = "Permite trafego apenas do VPC Link do API Gateway"
#   vpc_id      = var.vpc_id
#
#   ingress {
#     from_port   = tonumber(var.container_port)
#     to_port     = tonumber(var.container_port)
#     protocol    = "tcp"
#     cidr_blocks = [var.vpc_cidr] # idealmente restrinja à subnet do VPC Link
#   }
#
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

resource "kubernetes_service_v1" "internal_nlb" {
  for_each = local.services

  metadata {
    name      = each.value.service_name
    namespace = "apps"
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internal"
      "service.beta.kubernetes.io/aws-load-balancer-name"            = "${each.value.service_name}-nlb"
    }
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = each.value.service_name
    }

    port {
      port        = tonumber(var.container_port)
      target_port = tonumber(var.container_port)
      protocol    = "TCP"
    }
  }
}

#
# VPC LINKS (API Gateway -> NLBs internos na subnet privada do EKS)
#
# O nome do NLB é fixado pela annotation aws-load-balancer-name acima,
# então localizamos o LB por nome em vez de exigir o ARN manualmente.
data "aws_lb" "service" {
  for_each   = local.services
  name       = "${each.value.service_name}-nlb"
  depends_on = [kubernetes_service_v1.internal_nlb]
}

resource "aws_api_gateway_vpc_link" "service" {
  for_each    = local.services
  name        = "${each.value.service_name}-vpc-link"
  target_arns = [data.aws_lb.service[each.key].arn]
}

locals {
  service_nlb_dns = {
    for key, svc in local.services : key => data.aws_lb.service[key].dns_name
  }
}

resource "aws_api_gateway_resource" "service" {
  for_each    = local.services
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = each.value.path_prefix
}

resource "aws_api_gateway_resource" "service_proxy" {
  for_each    = local.services
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.service[each.key].id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "service_methods" {
  for_each      = local.service_method_routes
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.service[each.value.service_key].id
  http_method   = each.value.method
  authorization = local.authorization_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "service_integrations" {
  for_each                = local.service_method_routes
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.service[each.value.service_key].id
  http_method             = aws_api_gateway_method.service_methods[each.key].http_method
  integration_http_method = each.value.method
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.service[each.value.service_key].id
  uri                     = "http://${local.service_nlb_dns[each.value.service_key]}:${var.container_port}"
}

resource "aws_api_gateway_method" "service_proxy_methods" {
  for_each      = local.service_method_routes
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.service_proxy[each.value.service_key].id
  http_method   = each.value.method
  authorization = local.authorization_type
  authorizer_id = local.authorizer_id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "service_proxy_integrations" {
  for_each                = local.service_method_routes
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.service_proxy[each.value.service_key].id
  http_method             = aws_api_gateway_method.service_proxy_methods[each.key].http_method
  integration_http_method = each.value.method
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.service[each.value.service_key].id
  uri                     = "http://${local.service_nlb_dns[each.value.service_key]}:${var.container_port}/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_method" "service_options" {
  for_each      = local.services
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.service[each.key].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "service_options_integrations" {
  for_each    = local.services
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.service[each.key].id
  http_method = aws_api_gateway_method.service_options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\":200}"
  }
}

resource "aws_api_gateway_method" "service_proxy_options" {
  for_each      = local.services
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.service_proxy[each.key].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "service_proxy_options_integrations" {
  for_each    = local.services
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.service_proxy[each.key].id
  http_method = aws_api_gateway_method.service_proxy_options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\":200}"
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*/*"
}

# ========================
# PUBLIC RESOURCES: /users/api/v1/User
# ========================

resource "aws_api_gateway_resource" "users_api_public" {
  count       = local.public_users_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.service["users"].id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "users_v1_public" {
  count       = local.public_users_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.users_api_public[0].id
  path_part   = "v1"
}

resource "aws_api_gateway_resource" "users_user_public" {
  count       = local.public_users_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.users_v1_public[0].id
  path_part   = "User"
}

resource "aws_api_gateway_method" "users_user_public_post" {
  count         = local.public_users_enabled ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users_user_public[0].id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "users_user_public_post_200" {
  count       = local.public_users_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users_user_public[0].id
  http_method = aws_api_gateway_method.users_user_public_post[0].http_method
  status_code = "200"
}

resource "aws_api_gateway_integration" "users_user_public_post" {
  count                   = local.public_users_enabled ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.users_user_public[0].id
  http_method             = aws_api_gateway_method.users_user_public_post[0].http_method
  integration_http_method = "POST"
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.service["users"].id
  uri                     = "http://${local.service_nlb_dns["users"]}:${var.container_port}/api/v1/User"
  content_handling        = "CONVERT_TO_TEXT"
}

resource "aws_api_gateway_integration_response" "users_user_public_post_200" {
  count       = local.public_users_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users_user_public[0].id
  http_method = aws_api_gateway_method.users_user_public_post[0].http_method
  status_code = aws_api_gateway_method_response.users_user_public_post_200[0].status_code

  depends_on = [aws_api_gateway_integration.users_user_public_post]
}

resource "aws_api_gateway_method" "users_user_public_options" {
  count         = local.public_users_enabled ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users_user_public[0].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "users_user_public_options" {
  count       = local.public_users_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users_user_public[0].id
  http_method = aws_api_gateway_method.users_user_public_options[0].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\":200}"
  }
}

# ========================
# PUBLIC RESOURCES: /users/api/v1/User/Login
# ========================

resource "aws_api_gateway_resource" "users_login_public" {
  count       = local.public_users_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.users_user_public[0].id
  path_part   = "Login"
}

resource "aws_api_gateway_method" "users_login_public_post" {
  count         = local.public_users_enabled ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users_login_public[0].id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "users_login_public_post_200" {
  count       = local.public_users_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users_login_public[0].id
  http_method = aws_api_gateway_method.users_login_public_post[0].http_method
  status_code = "200"
}

resource "aws_api_gateway_integration" "users_login_public_post" {
  count                   = local.public_users_enabled ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.users_login_public[0].id
  http_method             = aws_api_gateway_method.users_login_public_post[0].http_method
  integration_http_method = "POST"
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.service["users"].id
  uri                     = "http://${local.service_nlb_dns["users"]}:${var.container_port}/api/v1/User/Login"
  content_handling        = "CONVERT_TO_TEXT"
}

resource "aws_api_gateway_integration_response" "users_login_public_post_200" {
  count       = local.public_users_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users_login_public[0].id
  http_method = aws_api_gateway_method.users_login_public_post[0].http_method
  status_code = aws_api_gateway_method_response.users_login_public_post_200[0].status_code

  depends_on = [aws_api_gateway_integration.users_login_public_post]
}

resource "aws_api_gateway_method" "users_login_public_options" {
  count         = local.public_users_enabled ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users_login_public[0].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "users_login_public_options" {
  count       = local.public_users_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users_login_public[0].id
  http_method = aws_api_gateway_method.users_login_public_options[0].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\":200}"
  }
}

# ========================
# DEPLOYMENT
# ========================

resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.service_integrations,
    aws_api_gateway_integration.service_proxy_integrations,
    aws_api_gateway_integration.service_options_integrations,
    aws_api_gateway_integration.service_proxy_options_integrations,
    aws_lambda_permission.api_gateway,
    aws_api_gateway_integration.users_user_public_post,
    aws_api_gateway_integration.users_user_public_options,
    aws_api_gateway_integration.users_login_public_post,
    aws_api_gateway_integration.users_login_public_options,
    aws_api_gateway_integration_response.users_user_public_post_200,
    aws_api_gateway_integration_response.users_login_public_post_200,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.deploy.id
  stage_name    = var.stage_name
}