#!/bin/bash
set -euo pipefail

AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

API_NAME="local-api-gateway-v1"
STAGE_NAME="dev"

LAMBDA_NAME="fiap-api-authorizer"

ALLOW_DEV_STAGE_BYPASS="${ALLOW_DEV_STAGE_BYPASS:-false}"

FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-}"
JWKS_METADATA_ADDRESS="${JWKS_METADATA_ADDRESS:-}"

#
# comunicação entre containers docker
# usa SEMPRE porta interna
#
CONTAINER_PORT="${CONTAINER_PORT:-8080}"

ROLE_ARN="arn:aws:iam::000000000000:role/lambda-authorizer-role"

echo "[localstack-init] waiting LocalStack..."

timeout=60

while ! awslocal sts get-caller-identity >/dev/null 2>&1; do
  sleep 1
  timeout=$((timeout-1))

  if [ $timeout -le 0 ]; then
    echo "[localstack-init] timeout waiting LocalStack"
    exit 1
  fi
done

echo "[localstack-init] LocalStack ready"

#
# CHECK SERVICES
#
for svc in iam lambda apigateway; do
  if ! awslocal "$svc" help >/dev/null 2>&1; then
    echo "[localstack-init] missing service: $svc"
    exit 1
  fi
done

#
# IAM ROLE
#
echo "[localstack-init] creating IAM role..."

awslocal iam create-role \
  --role-name lambda-authorizer-role \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[
      {
        "Effect":"Allow",
        "Principal":{
          "Service":"lambda.amazonaws.com"
        },
        "Action":"sts:AssumeRole"
      }
    ]
  }' >/dev/null 2>&1 || true

#
# LAMBDA ENV
#
AUTHOR_ENV_VARS="ALLOW_DEV_STAGE_BYPASS=$ALLOW_DEV_STAGE_BYPASS"

if [ -n "$FIREBASE_PROJECT_ID" ]; then
  AUTHOR_ENV_VARS+=",FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID"
fi

if [ -n "$JWKS_METADATA_ADDRESS" ]; then
  AUTHOR_ENV_VARS+=",JWKS_METADATA_ADDRESS=$JWKS_METADATA_ADDRESS"
fi

#
# CREATE / UPDATE LAMBDA
#
echo "[localstack-init] creating/updating lambda..."

if awslocal lambda get-function \
  --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then

  echo "[localstack-init] updating lambda code..."

  awslocal lambda update-function-code \
    --function-name "$LAMBDA_NAME" \
    --zip-file fileb:///etc/localstack/init/ready.d/function.zip >/dev/null

  echo "[localstack-init] updating lambda config..."

  awslocal lambda update-function-configuration \
    --function-name "$LAMBDA_NAME" \
    --runtime dotnet10 \
    --timeout 60 \
    --memory-size 1024 \
    --environment "Variables={${AUTHOR_ENV_VARS}}" >/dev/null

else

  echo "[localstack-init] creating lambda..."

  awslocal lambda create-function \
    --function-name "$LAMBDA_NAME" \
    --runtime dotnet10 \
    --role "$ROLE_ARN" \
    --handler "FiapCloudGames.Lambda.Authorizer::FiapCloudGames.Lambda.Authorizer.AuthorizerFunction::FunctionHandler" \
    --timeout 60 \
    --memory-size 1024 \
    --environment "Variables={${AUTHOR_ENV_VARS}}" \
    --zip-file fileb:///etc/localstack/init/ready.d/function.zip >/dev/null

fi

echo "[localstack-init] waiting lambda become active..."

sleep 8

LAMBDA_ARN=$(awslocal lambda get-function \
  --function-name "$LAMBDA_NAME" \
  --query 'Configuration.FunctionArn' \
  --output text)

echo "[localstack-init] lambda arn: $LAMBDA_ARN"

#
# DELETE OLD API
#
echo "[localstack-init] deleting previous api if exists..."

EXISTING_API_ID=$(awslocal apigateway get-rest-apis \
  --query "items[?name=='$API_NAME'].id | [0]" \
  --output text 2>/dev/null || true)

if [ -n "$EXISTING_API_ID" ] && [ "$EXISTING_API_ID" != "None" ]; then

  awslocal apigateway delete-rest-api \
    --rest-api-id "$EXISTING_API_ID"

fi

#
# CREATE API
#
echo "[localstack-init] creating api gateway..."

API_ID=$(awslocal apigateway create-rest-api \
  --name "$API_NAME" \
  --query 'id' \
  --output text)

ROOT_RESOURCE_ID=$(awslocal apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query "items[?path=='/'].id | [0]" \
  --output text)

echo "[localstack-init] api id: $API_ID"

#
# AUTHORIZER
#
echo "[localstack-init] creating authorizer..."

AUTHOR_URI="arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

AUTH_ID=$(awslocal apigateway create-authorizer \
  --rest-api-id "$API_ID" \
  --name "lambda-authorizer" \
  --type TOKEN \
  --authorizer-uri "$AUTHOR_URI" \
  --identity-source "method.request.header.Authorization" \
  --authorizer-result-ttl-in-seconds 0 \
  --query 'id' \
  --output text)

echo "[localstack-init] authorizer id: $AUTH_ID"

echo "[localstack-init] adding lambda invoke permission..."

awslocal lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "apigw-authorizer-${API_ID}" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:000000000000:${API_ID}/*/*/*" \
  >/dev/null 2>&1 || true

AUTHORIZATION_TYPE="CUSTOM"
AUTHORIZER_ARGS=(--authorizer-id "$AUTH_ID")

if [ "$ALLOW_DEV_STAGE_BYPASS" = "true" ]; then

  echo "[localstack-init] bypass enabled"

  AUTHORIZATION_TYPE="NONE"
  AUTHORIZER_ARGS=()

fi

#
# OPTIONS MOCK
#
create_options_method() {

  local resource_id=$1

  awslocal apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$resource_id" \
    --http-method OPTIONS \
    --authorization-type NONE \
    >/dev/null

  awslocal apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$resource_id" \
    --http-method OPTIONS \
    --type MOCK \
    --request-templates '{"application/json":"{\"statusCode\":200}"}' \
    >/dev/null

}

#
# DEFAULT PROXY METHOD
#
create_proxy_method() {

  local resource_id=$1
  local method=$2
  local auth_type=$3
  local service_uri=$4

  shift 4

  local auth_args=("$@")

  awslocal apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$resource_id" \
    --http-method "$method" \
    --authorization-type "$auth_type" \
    "${auth_args[@]}" \
    >/dev/null

  awslocal apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$resource_id" \
    --http-method "$method" \
    --type HTTP_PROXY \
    --integration-http-method "$method" \
    --uri "$service_uri" \
    --passthrough-behavior WHEN_NO_MATCH \
    >/dev/null

}

#
# RESOURCE ROUTES
#
create_resource_routes() {

  local service_name=$1
  local path_prefix=$2

  #
  # usa porta INTERNA do container
  #
  local service_uri="http://${service_name}:${CONTAINER_PORT}"

  echo "[localstack-init] mapping /${path_prefix} -> ${service_uri}"

  #
  # ROOT RESOURCE
  #
  resource_id=$(awslocal apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$ROOT_RESOURCE_ID" \
    --path-part "$path_prefix" \
    --query 'id' \
    --output text)

  #
  # ROOT METHODS
  #
  for method in GET POST PUT DELETE PATCH; do

    create_proxy_method \
      "$resource_id" \
      "$method" \
      "$AUTHORIZATION_TYPE" \
      "$service_uri" \
      "${AUTHORIZER_ARGS[@]}"

  done

  create_options_method "$resource_id"

  #
  # PROXY RESOURCE
  #
  proxy_resource_id=$(awslocal apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$resource_id" \
    --path-part "{proxy+}" \
    --query 'id' \
    --output text)

  for method in GET POST PUT DELETE PATCH; do

    awslocal apigateway put-method \
      --rest-api-id "$API_ID" \
      --resource-id "$proxy_resource_id" \
      --http-method "$method" \
      --authorization-type "$AUTHORIZATION_TYPE" \
      "${AUTHORIZER_ARGS[@]}" \
      --request-parameters "method.request.path.proxy=true" \
      >/dev/null

    awslocal apigateway put-integration \
      --rest-api-id "$API_ID" \
      --resource-id "$proxy_resource_id" \
      --http-method "$method" \
      --type HTTP_PROXY \
      --integration-http-method "$method" \
      --uri "${service_uri}/{proxy}" \
      --request-parameters "integration.request.path.proxy=method.request.path.proxy" \
      --passthrough-behavior WHEN_NO_MATCH \
      >/dev/null

  done

  create_options_method "$proxy_resource_id"

  #
  # USERS PUBLIC ROUTES
  #
  if [ "$service_name" = "users-api" ] && [ "$AUTHORIZATION_TYPE" = "CUSTOM" ]; then

    echo "[localstack-init] creating public routes"

    api_res_id=$(awslocal apigateway create-resource \
      --rest-api-id "$API_ID" \
      --parent-id "$resource_id" \
      --path-part "api" \
      --query 'id' \
      --output text)

    v1_res_id=$(awslocal apigateway create-resource \
      --rest-api-id "$API_ID" \
      --parent-id "$api_res_id" \
      --path-part "v1" \
      --query 'id' \
      --output text)

    user_res_id=$(awslocal apigateway create-resource \
      --rest-api-id "$API_ID" \
      --parent-id "$v1_res_id" \
      --path-part "User" \
      --query 'id' \
      --output text)

    #
    # PUBLIC REGISTER
    #
    create_proxy_method \
      "$user_res_id" \
      "POST" \
      "NONE" \
      "${service_uri}/api/v1/User"

    create_options_method "$user_res_id"

    #
    # LOGIN
    #
    login_res_id=$(awslocal apigateway create-resource \
      --rest-api-id "$API_ID" \
      --parent-id "$user_res_id" \
      --path-part "Login" \
      --query 'id' \
      --output text)

    create_proxy_method \
      "$login_res_id" \
      "POST" \
      "NONE" \
      "${service_uri}/api/v1/User/Login"

    create_options_method "$login_res_id"

    echo "[localstack-init] public routes created"

  fi

}

#
# SERVICES
#
create_resource_routes "catalog-api"      "catalog"
create_resource_routes "users-api"        "users"
create_resource_routes "payments-api"     "payments"
create_resource_routes "notification-api" "notification"

#
# DEPLOY
#
echo "[localstack-init] deploying api..."

awslocal apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name "$STAGE_NAME" >/dev/null

echo ""
echo "=================================================="
echo "API READY"
echo "=================================================="
echo "API ID: $API_ID"
echo ""
echo "Invoke URL:"
echo "http://localhost.localstack.cloud:4566/restapis/${API_ID}/${STAGE_NAME}/_user_request_"
echo ""
echo "PUBLIC ROUTES:"
echo "POST /users/api/v1/User"
echo "POST /users/api/v1/User/Login"
echo ""
echo "PROTECTED ROUTES:"
echo "/payments/*"
echo "/catalog/*"
echo "/notification/*"
echo "=================================================="

exit 0