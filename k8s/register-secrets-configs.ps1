param(
    [string]$Namespace = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "Aplicando recursos no namespace '$Namespace'..." -ForegroundColor Cyan

# ConfigMap compartilhado
$sharedConfigArgs = @(
    "create", "configmap", "shared-config", "-n", $Namespace,
    "--from-literal=RABBITMQ_ADDRESS=rabbitmq",
    "--from-literal=RABBITMQ_PORT=5672",
    "--from-literal=RABBITMQ_VIRTUAL_HOST=/",
    "--from-literal=MONGODB_ADDRESS=mongodb",
    "--from-literal=MONGODB_PORT=27017",
    "--from-literal=REDIS_ADDRESS=redis",
    "--from-literal=REDIS_PORT=6379",
    "--from-literal=NEW_RELIC_LOG=stdout",
    "--from-literal=NEW_RELIC_LOG_LEVEL=debug",
    "--from-literal=NEW_RELIC_APPLICATION_LOGGING_ENABLED=true",
    "--from-literal=NEW_RELIC_APPLICATION_LOGGING_FORWARDING_ENABLED=true",
    "--from-literal=NEW_RELIC_APPLICATION_LOGGING_LOCAL_DECORATING_ENABLED=true",
    "--from-literal=NEW_RELIC_DISTRIBUTED_TRACING_ENABLED=true",
    "--from-literal=LOCALSTACK_ENDPOINT=http://localstack:4566/",
    # SQS_SERVICE_URL vazio = AWS real: os apps caem no credential chain padrao
    # do SDK (IAM role do node via IMDS) em vez de credenciais fixas, que nao
    # funcionam com as credenciais temporarias do AWS Academy.
    "--from-literal=SQS_SERVICE_URL=",
    "--from-literal=SQS_EMAIL_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/375157863909/notification-queue",
    "--from-literal=ELASTICSEARCH_URI=http://elasticsearch:9200",
    "--from-literal=ELASTICSEARCH_INDEX=games",
    "--dry-run=client", "-o", "yaml"
)
kubectl @sharedConfigArgs | kubectl apply -f -

# ConfigMap Payments
$paymentsConfigArgs = @(
    "create", "configmap", "payments-configmap", "-n", $Namespace,
    "--from-literal=PAYMENT_APPROVAL_RATE=0.9",
    "--dry-run=client", "-o", "yaml"
)
kubectl @paymentsConfigArgs | kubectl apply -f -

# Secret compartilhado
$sharedSecretArgs = @(
    "create", "secret", "generic", "shared-secret", "-n", $Namespace,
    "--type=Opaque",
    "--from-literal=RABBITMQ_USERNAME=admin",
    "--from-literal=RABBITMQ_PASSWORD=password",
    "--from-literal=MONGO_ROOT_USER=mongoAdmin",
    "--from-literal=MONGO_ROOT_PASSWORD=mongoPassword",
    "--from-literal=MONGO_EXPRESS_USER=admin",
    "--from-literal=MONGO_EXPRESS_PASSWORD=password",
    "--from-literal=MONGO_CONNECTION_STRING=mongodb://mongoAdmin:mongoPassword@mongodb:27017/",
    "--from-literal=MONGO_DATABASE_CATALOG=catalog-db",
    "--from-literal=MONGO_EXPRESS_URL=mongodb://mongoAdmin:mongoPassword@mongodb:27017/",
    "--from-literal=REDIS_PASSWORD=redisPassword",
    "--from-literal=REDIS_CONNECTION_STRING=redis:6379,password=redisPassword,abortConnect=false",
    "--from-literal=NEW_RELIC_LICENSE_KEY_LAMBDA=4f8eab81ae33b9bdcf1dc52569843322e51eNRAL",
    "--from-literal=NEW_RELIC_LICENSE_KEY=72e69c1c608f4ad9078c39b76d4ca3b1FFFFNRAL",
    "--from-literal=NEW_RELIC_APP_NAME_PAYMENTS=FiapCloudGames-Payments-Logs",
    "--from-literal=NEW_RELIC_APP_NAME_CATALOGS=FiapCloudGames-Catalog-Logs",
    "--from-literal=NEW_RELIC_APP_NAME_USERS=FiapCloudGames-User-Logs",
    "--from-literal=POSTGRES_USER=postgresAdmin",
    "--from-literal=POSTGRES_PASSWORD=postgresAdmin",
    "--from-literal=SQS_REGION=us-east-1",
    "--from-literal=SQS_ACCESS_KEY=test",
    "--from-literal=SQS_SECRET_KEY=test",
    "--from-literal=FIREBASE_CREDENTIAL_PATH=/app/firebase-service-account.json",
    "--from-literal=FIREBASE_APIKEY=AIzaSyCP88H3UcP8q3sl4Yh9Kf6IEePA_5KwTEs",
    "--dry-run=client", "-o", "yaml"
)
kubectl @sharedSecretArgs | kubectl apply -f -

# Secret da API de Usuários
$usersSecretArgs = @(
    "create", "secret", "generic", "users-secret", "-n", $Namespace,
    "--type=Opaque",
    "--from-literal=DB_USER_CONNECTION_STRING=Host=postgresdb-users;Port=5432;Database=users-db;Username=postgresAdmin;Password=postgresAdmin;",
    "--from-literal=FIREBASE_CREDENTIAL_PATH=/app/firebase-service-account.json",
    "--from-literal=FIREBASE_API_KEY=AIzaSyCP88H3UcP8q3sl4Yh9Kf6IEePA_5KwTEs",
    "--dry-run=client", "-o", "yaml"
)
kubectl @usersSecretArgs | kubectl apply -f -

# Secret da API de Pagamentos
$paymentsSecretArgs = @(
    "create", "secret", "generic", "payments-secret", "-n", $Namespace,
    "--type=Opaque",
    "--from-literal=DB_USER_CONNECTION_STRING=Host=postgresdb-payments;Port=5432;Database=payments-db;Username=postgresAdmin;Password=postgresAdmin;",
    "--dry-run=client", "-o", "yaml"
)
kubectl @paymentsSecretArgs | kubectl apply -f -

# Secret da API de Catálogo
$catalogSecretArgs = @(
    "create", "secret", "generic", "catalog-secret", "-n", $Namespace,
    "--type=Opaque",
    "--from-literal=DB_USER_CONNECTION_STRING=Host=postgresdb-catalog;Port=5432;Database=catalog-db;Username=postgresAdmin;Password=postgresAdmin;",
    "--dry-run=client", "-o", "yaml"
)
kubectl @catalogSecretArgs | kubectl apply -f -

# Secret PGAdmin 
$pgadminSecretArgs = @(
    "create", "secret", "generic", "pgadmin-secret", "-n", $Namespace,
    "--type=Opaque",
    "--from-literal=PGADMIN_DEFAULT_EMAIL=admin@admin.com",
    "--from-literal=PGADMIN_DEFAULT_PASSWORD=admin123",
    "--dry-run=client", "-o", "yaml"
)
kubectl @pgadminSecretArgs | kubectl apply -f -

Write-Host "Recursos aplicados com sucesso." -ForegroundColor Green