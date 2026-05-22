# PowerShell build and deploy script for Lambda Authorizer
# Target: .NET 10 (requires .NET SDK 10+)
# Builds the Lambda function and deploys it to LocalStack
# Usage: ./build-and-deploy.ps1

param(
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

Push-Location -Path $PSScriptRoot

try {

Write-Host "[deploy] Checking .NET SDK version..."
$dotnetVersion = dotnet --version
Write-Host "[deploy] .NET SDK version: $dotnetVersion"

Write-Host "[deploy] Moving solution file..."
Move-Item -Path "lambda-authorizer.sln" -Destination "..\" -Force

Write-Host "[deploy] Generating Lambda package (.NET 10)..."
dotnet lambda package -o function.zip

Write-Host "[deploy] Restoring solution file..."
Move-Item -Path "..\lambda-authorizer.sln" -Destination ".\" -Force

Write-Host "[deploy] Moving function.zip to localstack-init directory..."
Move-Item -Path "function.zip" -Destination "..\" -Force

Write-Host "[deploy] Copying function.zip to Terraform lambda directory..."
$terraformLambdaDir = Join-Path $PSScriptRoot "..\..\infra\terraform\localstack\lambda"
New-Item -ItemType Directory -Force -Path $terraformLambdaDir | Out-Null
Copy-Item -Path "..\function.zip" -Destination "$terraformLambdaDir\function.zip" -Force
Write-Host "[deploy] function.zip copiado para $terraformLambdaDir"

if ($BuildOnly) {
    Write-Host "[deploy] Modo build-only: pulando deploy no LocalStack via Docker."
    Write-Host "[deploy] Para deploy no Kubernetes: execute 'terraform apply' em infra/terraform/localstack"
} else {
    Write-Host "[deploy] Normalizing create-api-gateway.sh line endings in LocalStack..."
    docker exec localstack sh -lc "sed -i 's/\r$//' /etc/localstack/init/ready.d/create-api-gateway.sh && chmod +x /etc/localstack/init/ready.d/create-api-gateway.sh"

    Write-Host "[deploy] Executing LocalStack API Gateway setup script..."
    docker exec localstack bash -lc "/etc/localstack/init/ready.d/create-api-gateway.sh"

    Write-Host "[deploy] Build and deploy process completed!"
}
}
finally {
    Pop-Location
}