# build-and-deploy.ps1

Write-Host "Movendo solução..."
Move-Item -Path "lambda-authorizer.sln" -Destination "..\" -Force

Write-Host "Gerando pacote Lambda..."
dotnet lambda package -o function.zip

Write-Host "Retornando solução..."
Move-Item -Path "..\lambda-authorizer.sln" -Destination ".\" -Force

Write-Host "Movendo function.zip..."
Move-Item -Path "function.zip" -Destination "..\" -Force

Write-Host "Executando script no LocalStack..."
docker exec localstack bash -lc "/etc/localstack/init/ready.d/create-api-gateway.sh"

Write-Host "Processo finalizado!"