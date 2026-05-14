# PowerShell build and deploy script for Lambda Authorizer
# Target: .NET 10 (requires .NET SDK 10+)
# Builds the Lambda function and deploys it to LocalStack
# Usage: ./build-and-deploy.ps1

param()

$ErrorActionPreference = "Stop"

Write-Host "[deploy] Checking .NET SDK version..."
$dotnetVersion = dotnet --version
Write-Host "[deploy] .NET SDK version: $dotnetVersion"

Write-Host "[deploy] Moving solution file..."
Move-Item -Path "lambda-authorizer.sln" -Destination "..\" -Force

Write-Host "[deploy] Generating Lambda package (.NET 10)..."
dotnet lambda package -o function.zip

Write-Host "[deploy] Restoring solution file..."
Move-Item -Path "..\lambda-authorizer.sln" -Destination ".\" -Force

Write-Host "[deploy] Moving function.zip to parent directory..."
Move-Item -Path "function.zip" -Destination "..\" -Force

Write-Host "[deploy] Executing LocalStack API Gateway setup script..."
docker exec localstack bash -lc "/etc/localstack/init/ready.d/create-api-gateway.sh"

Write-Host "[deploy] Build and deploy process completed!"