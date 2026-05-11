#!/bin/bash
set -euo pipefail

AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
API_NAME="local-api-gateway-v1"
STAGE_NAME="dev"
LAMBDA_NAME="fiap-api-authorizer"
ALLOW_DEV_STAGE_BYPASS="${ALLOW_DEV_STAGE_BYPASS:-false}"
CONTAINER_PORT="${CONTAINER_PORT:-8080}"
NOTIFICATION_API_HOST_PORT="${NOTIFICATION_API_HOST_PORT:-8080}"
PAYMENTS_API_HOST_PORT="${PAYMENTS_API_HOST_PORT:-8081}"
USERS_API_HOST_PORT="${USERS_API_HOST_PORT:-8082}"
CATALOG_API_HOST_PORT="${CATALOG_API_HOST_PORT:-8083}"

echo "[localstack-init] waiting for LocalStack API to be available..."
timeout=60
while ! awslocal sts get-caller-identity >/dev/null 2>&1; do
  sleep 1
  timeout=$((timeout-1))
  if [ $timeout -le 0 ]; then
    echo "[localstack-init] timeout waiting for LocalStack" >&2
    exit 1
  fi
done

echo "[localstack-init] checking required services..."
for svc in iam lambda apigateway; do
  if ! awslocal "$svc" help >/dev/null 2>&1; then
    echo "[localstack-init] required service '$svc' is unavailable. Check LOCALSTACK_SERVICES." >&2
    exit 1
  fi
done

echo "[localstack-init] Creating IAM role for Lambda..."
ROLE_ARN=$(awslocal iam create-role \
  --role-name lambda-authorizer-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }' \
  --query 'Role.Arn' --output text 2>/dev/null || echo "arn:aws:iam::123456789012:role/lambda-authorizer-role")

echo "[localstack-init] Creating/updating Lambda function..."
if awslocal lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
  awslocal lambda update-function-code \
    --function-name "$LAMBDA_NAME" \
    --zip-file "fileb:///etc/localstack/init/ready.d/function.zip" >/dev/null

  awslocal lambda update-function-configuration \
    --function-name "$LAMBDA_NAME" \
    --timeout 30 \
    --environment "Variables={ALLOW_DEV_STAGE_BYPASS=$ALLOW_DEV_STAGE_BYPASS}" >/dev/null
else
  awslocal lambda create-function \
    --function-name "$LAMBDA_NAME" \
    --runtime dotnet10 \
    --role "$ROLE_ARN" \
    --handler "FiapCloudGames.Lambda.Authorizer::FiapCloudGames.Lambda.Authorizer.AuthorizerFunction::FunctionHandler" \
    --memory-size 512 \
    --timeout 30 \
    --environment "Variables={ALLOW_DEV_STAGE_BYPASS=$ALLOW_DEV_STAGE_BYPASS}" \
    --zip-file "fileb:///etc/localstack/init/ready.d/function.zip" >/dev/null
fi

LAMBDA_ARN=$(awslocal lambda get-function --function-name "$LAMBDA_NAME" --query 'Configuration.FunctionArn' --output text)

echo "[localstack-init] Lambda ARN: $LAMBDA_ARN"

PROXY_LAMBDA_NAME="fiap-api-request-proxy"
PROXY_ZIP_FILE="/etc/localstack/init/ready.d/function.zip"

echo "[localstack-init] Creating/updating request proxy Lambda..."
if awslocal lambda get-function --function-name "$PROXY_LAMBDA_NAME" >/dev/null 2>&1; then
  awslocal lambda delete-function --function-name "$PROXY_LAMBDA_NAME" >/dev/null
fi

awslocal lambda create-function \
  --function-name "$PROXY_LAMBDA_NAME" \
  --runtime dotnet10 \
  --role "$ROLE_ARN" \
  --handler "FiapCloudGames.Lambda.Authorizer::FiapCloudGames.Lambda.Authorizer.Infrastructure.RequestProxyFunction::FunctionHandler" \
  --timeout 30 \
  --environment "Variables={USERS_API_HOST_PORT=$USERS_API_HOST_PORT}" \
  --zip-file "fileb://${PROXY_ZIP_FILE}" >/dev/null

PROXY_LAMBDA_ARN=$(awslocal lambda get-function --function-name "$PROXY_LAMBDA_NAME" --query 'Configuration.FunctionArn' --output text)

EXISTING_API_ID=$(awslocal apigateway get-rest-apis --query "items[?name=='$API_NAME'].id | [0]" --output text 2>/dev/null || true)
if [ -n "$EXISTING_API_ID" ] && [ "$EXISTING_API_ID" != "None" ]; then
  echo "[localstack-init] deleting previous API '$API_NAME' ($EXISTING_API_ID)"
  awslocal apigateway delete-rest-api --rest-api-id "$EXISTING_API_ID"
fi

echo "[localstack-init] Creating REST API Gateway v1..."
API_ID=$(awslocal apigateway create-rest-api --name "$API_NAME" --query 'id' --output text)
ROOT_RESOURCE_ID=$(awslocal apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/'].id | [0]" --output text)
echo "[localstack-init] created API $API_NAME -> $API_ID"

awslocal lambda add-permission \
  --function-name "$PROXY_LAMBDA_NAME" \
  --statement-id "apigw-proxy-${API_ID}" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:000000000000:${API_ID}/*/*/*" >/dev/null 2>&1 || true

echo "[localstack-init] Creating authorizer..."
AUTHOR_URI="arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"
AUTH_ID=$(awslocal apigateway create-authorizer \
  --rest-api-id "$API_ID" \
  --name "lambda-authorizer" \
  --type TOKEN \
  --authorizer-uri "$AUTHOR_URI" \
  --identity-source "method.request.header.Authorization" \
  --identity-validation-expression ".+" \
  --authorizer-result-ttl-in-seconds 0 \
  --query 'id' --output text)

awslocal lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "apigw-authorizer-${API_ID}" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:000000000000:${API_ID}/*/*/*" >/dev/null 2>&1 || true

echo "[localstack-init] Authorizer ID: $AUTH_ID"

AUTHORIZATION_TYPE="CUSTOM"
AUTHORIZER_ARGS=(--authorizer-id "$AUTH_ID")
if [ "$ALLOW_DEV_STAGE_BYPASS" = "true" ]; then
  AUTHORIZATION_TYPE="NONE"
  AUTHORIZER_ARGS=()
  echo "[localstack-init] dev bypass enabled: methods will be created with authorization NONE"
fi

create_resource_routes() {
  local service_name=$1
  local path_prefix=$2
  local service_port="${CONTAINER_PORT}"

  case "$service_name" in
    notification-api)
      service_port="${NOTIFICATION_API_HOST_PORT}"
      ;;
    payments-api)
      service_port="${PAYMENTS_API_HOST_PORT}"
      ;;
    users-api)
      service_port="${USERS_API_HOST_PORT}"
      ;;
    catalog-api)
      service_port="${CATALOG_API_HOST_PORT}"
      ;;
  esac

  local service_uri="http://host.docker.internal:${service_port}"

  echo "[localstack-init] configuring /${path_prefix} -> ${service_uri}"
  local resource_id
  resource_id=$(awslocal apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$ROOT_RESOURCE_ID" \
    --path-part "$path_prefix" \
    --query 'id' --output text)

  if [ "$service_name" != "users-api" ]; then
    awslocal apigateway put-method \
      --rest-api-id "$API_ID" \
      --resource-id "$resource_id" \
      --http-method ANY \
      --authorization-type "$AUTHORIZATION_TYPE" \
      "${AUTHORIZER_ARGS[@]}" >/dev/null

    awslocal apigateway put-integration \
      --rest-api-id "$API_ID" \
      --resource-id "$resource_id" \
      --http-method ANY \
      --type HTTP_PROXY \
      --integration-http-method ANY \
      --uri "$service_uri" \
      --passthrough-behavior WHEN_NO_MATCH >/dev/null

    local proxy_resource_id
    proxy_resource_id=$(awslocal apigateway create-resource \
      --rest-api-id "$API_ID" \
      --parent-id "$resource_id" \
      --path-part "{proxy+}" \
      --query 'id' --output text)

    awslocal apigateway put-method \
      --rest-api-id "$API_ID" \
      --resource-id "$proxy_resource_id" \
      --http-method ANY \
      --authorization-type "$AUTHORIZATION_TYPE" \
      "${AUTHORIZER_ARGS[@]}" \
      --request-parameters 'method.request.path.proxy=true' >/dev/null

    awslocal apigateway put-integration \
      --rest-api-id "$API_ID" \
      --resource-id "$proxy_resource_id" \
      --http-method ANY \
      --type HTTP_PROXY \
      --integration-http-method ANY \
      --uri "${service_uri}/{proxy}" \
      --request-parameters 'integration.request.path.proxy=method.request.path.proxy' \
      --passthrough-behavior WHEN_NO_MATCH >/dev/null
  fi

  if [ "$service_name" = "users-api" ]; then
    echo "[localstack-init] creating public routes for /${path_prefix}/api/v1/User and /${path_prefix}/api/v1/User/Login"

    api_res_id=$(awslocal apigateway create-resource \
      --rest-api-id "$API_ID" \
      --parent-id "$resource_id" \
      --path-part "api" \
      --query 'id' --output text 2>/dev/null || awslocal apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/${path_prefix}/api'].id | [0]" --output text)

    if [ -n "$api_res_id" ] && [ "$api_res_id" != "None" ]; then
      v1_res_id=$(awslocal apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$api_res_id" \
        --path-part "v1" \
        --query 'id' --output text 2>/dev/null || awslocal apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/${path_prefix}/api/v1'].id | [0]" --output text)

      if [ -n "$v1_res_id" ] && [ "$v1_res_id" != "None" ]; then
        user_res_id=$(awslocal apigateway create-resource \
          --rest-api-id "$API_ID" \
          --parent-id "$v1_res_id" \
          --path-part "User" \
          --query 'id' --output text 2>/dev/null || awslocal apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/${path_prefix}/api/v1/User'].id | [0]" --output text)

        if [ -n "$user_res_id" ] && [ "$user_res_id" != "None" ]; then
          awslocal apigateway put-method \
            --rest-api-id "$API_ID" \
            --resource-id "$user_res_id" \
            --http-method POST \
            --authorization-type NONE >/dev/null || true

          awslocal apigateway put-integration \
            --rest-api-id "$API_ID" \
            --resource-id "$user_res_id" \
            --http-method POST \
            --type HTTP_PROXY \
            --integration-http-method POST \
            --uri "${service_uri}/api/v1/User" \
            --passthrough-behavior WHEN_NO_MATCH >/dev/null || true

          login_res_id=$(awslocal apigateway create-resource \
            --rest-api-id "$API_ID" \
            --parent-id "$user_res_id" \
            --path-part "Login" \
            --query 'id' --output text 2>/dev/null || awslocal apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/${path_prefix}/api/v1/User/Login'].id | [0]" --output text)

          if [ -n "$login_res_id" ] && [ "$login_res_id" != "None" ]; then
            awslocal apigateway put-method \
              --rest-api-id "$API_ID" \
              --resource-id "$login_res_id" \
              --http-method POST \
              --authorization-type NONE >/dev/null || true

            awslocal apigateway put-integration \
              --rest-api-id "$API_ID" \
              --resource-id "$login_res_id" \
              --http-method POST \
              --type HTTP_PROXY \
              --integration-http-method POST \
              --uri "${service_uri}/api/v1/User/Login" \
              --passthrough-behavior WHEN_NO_MATCH >/dev/null || true
          
          # Create explicit MakeAdmin PUT method (protected) to avoid 404s when a specific
          # sub-resource exists (APIG prefers most-specific resource and may return 404
          # for methods not configured on that resource). This keeps Login/Create public
          # while protecting admin operations.
          makeadmin_res_id=$(awslocal apigateway create-resource \
            --rest-api-id "$API_ID" \
            --parent-id "$user_res_id" \
            --path-part "MakeAdmin" \
            --query 'id' --output text 2>/dev/null || awslocal apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/${path_prefix}/api/v1/User/MakeAdmin'].id | [0]" --output text)

          if [ -n "$makeadmin_res_id" ] && [ "$makeadmin_res_id" != "None" ]; then
            awslocal apigateway put-method \
              --rest-api-id "$API_ID" \
              --resource-id "$makeadmin_res_id" \
              --http-method PUT \
              --authorization-type "$AUTHORIZATION_TYPE" \
              "${AUTHORIZER_ARGS[@]}" >/dev/null || true

            awslocal apigateway put-integration \
              --rest-api-id "$API_ID" \
              --resource-id "$makeadmin_res_id" \
              --http-method PUT \
              --type HTTP_PROXY \
              --integration-http-method PUT \
              --uri "${service_uri}/api/v1/User/MakeAdmin" \
              --passthrough-behavior WHEN_NO_MATCH >/dev/null || true
          fi
          fi
        fi
      fi
    fi
  fi

  # explicit swagger mappings removed per user request
}

# Define services and path prefixes here (container name, path)
create_resource_routes "catalog-api" "catalog"
create_resource_routes "users-api" "users"
create_resource_routes "payments-api" "payments"
create_resource_routes "notification-api" "notification"

echo "[localstack-init] creating deployment and stage"
awslocal apigateway create-deployment --rest-api-id "$API_ID" --stage-name "$STAGE_NAME" >/dev/null

echo "[localstack-init] API Gateway ready. API ID: $API_ID"
echo "[localstack-init] Invoke URL: http://localhost.localstack.cloud:4566/restapis/${API_ID}/${STAGE_NAME}/_user_request_"
echo "[localstack-init] All requests to the gateway will be authorized by Lambda Authorizer"

exit 0
