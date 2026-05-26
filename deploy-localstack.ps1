param()

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Push-Location -Path $root

Write-Host "[deploy] Starting docker-compose..."
docker-compose up -d

Write-Host "[deploy] Waiting for LocalStack (port 4566)..."
$timeout = 60
while (-not (Test-NetConnection -ComputerName 'localhost' -Port 4566 -InformationLevel Quiet)) {
    Start-Sleep -Seconds 1
    $timeout = $timeout - 1
    if ($timeout -le 0) {
        Write-Error "Timeout waiting for LocalStack on port 4566"
        Pop-Location
        exit 1
    }
}

Write-Host "[deploy] Building Lambda package (dotnet lambda package)..."
Push-Location -Path ".\localstack-init\lambda-authorizer"

Write-Host "[deploy] Moving solution file to parent to allow packaging..."
Write-Host "[deploy] Restoring NuGet packages for solution..."
dotnet restore "lambda-authorizer.sln"

Write-Host "[deploy] Moving solution file to parent to allow packaging..."
Move-Item -Path "lambda-authorizer.sln" -Destination "..\" -Force

Write-Host "[deploy] Packaging Lambda..."
dotnet lambda package -o function.zip

Write-Host "[deploy] Restoring solution file back to project folder..."
Move-Item -Path "..\lambda-authorizer.sln" -Destination ".\" -Force

Pop-Location

$targetDir = Join-Path $root "infra\terraform\localstack\lambda"
if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

$srcZip = Join-Path $root "localstack-init\lambda-authorizer\function.zip"
if (-not (Test-Path $srcZip)) {
    Write-Error "function.zip not found at $srcZip"
    Pop-Location
    exit 1
}

Move-Item -Path $srcZip -Destination (Join-Path $targetDir "function.zip") -Force

Write-Host "[deploy] Formatting and validating Terraform..."
$tfvarsPath = Join-Path $root "infra\terraform\localstack\terraform.tfvars"
$tfvarsExample = Join-Path $root "infra\terraform\localstack\terraform.tfvars.example"

if (-not (Test-Path $tfvarsPath)) {
    if (Test-Path $tfvarsExample) {
        Copy-Item -Path $tfvarsExample -Destination $tfvarsPath -Force
        Write-Host "[deploy] A terraform.tfvars was created at: $tfvarsPath"
        Write-Host "[deploy] Please edit the file with your values. Opening in Notepad..."
        Start-Process notepad $tfvarsPath
        Read-Host "Press Enter after editing terraform.tfvars to continue"
    } else {
        Write-Host "[deploy] terraform.tfvars.example not found at $tfvarsExample. Continuing without tfvars."
    }
}

Push-Location -Path ".\infra\terraform\localstack"
terraform fmt
terraform init -input=false
terraform validate

Write-Host "[deploy] Applying Terraform (this will create/update Lambda + API Gateway)..."
terraform apply -auto-approve

Pop-Location

Write-Host "[deploy] Deploy finished."

Pop-Location
