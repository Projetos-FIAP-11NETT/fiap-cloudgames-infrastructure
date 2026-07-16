# PowerShell build and deploy script for Lambda Authorizer
# Target: .NET 10 (requires .NET SDK 10+)
# Builds the Lambda function and deploys it to LocalStack or copies it for AWS real (Academy Lab)
# Usage: ./build-and-deploy.ps1 [-Target LocalStack|Aws] [-BuildOnly]

param(
    [ValidateSet("LocalStack", "Aws")]
    [string]$Target,

    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

if (-not $Target) {
    Write-Host ""
    Write-Host "Para qual destino voce quer buildar/implantar o Lambda Authorizer?"
    Write-Host "  [1] LocalStack (dev local)"
    Write-Host "  [2] AWS real (AWS Academy Lab)"
    $choice = Read-Host "Escolha (1 ou 2)"

    switch ($choice) {
        "1" { $Target = "LocalStack" }
        "2" { $Target = "Aws" }
        default { throw "Escolha invalida: '$choice'. Informe 1 (LocalStack) ou 2 (Aws)." }
    }
}

Write-Host "[deploy] Target selecionado: $Target"

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

if ($Target -eq "Aws") {
    $terraformLambdaDir = Join-Path $PSScriptRoot "..\..\infra\terraform\aws-apigateway-lambda-auth\lambda"
} else {
    $terraformLambdaDir = Join-Path $PSScriptRoot "..\..\infra\terraform\localstack\lambda"
}

Write-Host "[deploy] Copying function.zip to Terraform lambda directory ($Target)..."
New-Item -ItemType Directory -Force -Path $terraformLambdaDir | Out-Null
Copy-Item -Path "..\function.zip" -Destination "$terraformLambdaDir\function.zip" -Force
Write-Host "[deploy] function.zip copiado para $terraformLambdaDir"

if ($Target -eq "Aws") {
    Write-Host "[deploy] Target Aws: pulando bootstrap via Docker/LocalStack."
    Write-Host "[deploy] Para implantar: cd infra/terraform/aws-apigateway-lambda-auth && terraform apply"
} elseif ($BuildOnly) {
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
