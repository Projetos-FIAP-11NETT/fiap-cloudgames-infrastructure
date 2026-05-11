# Lambda Authorizer - Clean Architecture CQRS

Este projeto implementa um **Lambda Authorizer** para validação de tokens JWT e autorização de rotas no API Gateway (LocalStack).

## Arquitetura

```
FiapCloudGames.Lambda.Authorizer/
├── Domain/
│   ├── AuthorizationRule.cs         # Regra de autorização
│   └── AuthorizationResult.cs       # Resultado da validação
├── Application/
│   └── Queries/
│       ├── AuthorizeTokenQuery.cs      # Query CQRS
│       └── AuthorizeTokenQueryHandler.cs # Handler da Query
├── Infrastructure/
│   ├── IJwtTokenService.cs          # Interface para JWT
│   ├── JwtTokenService.cs           # Implementação (valida JWT via JWKS do Firebase)
│   ├── IAuthorizationRulesService.cs # Interface de regras
│   ├── AuthorizationRulesService.cs  # Implementação das regras
│   ├── IIamPolicyBuilder.cs         # Interface para policy
│   └── IamPolicyBuilder.cs          # Implementação da policy
├── Program.cs                       # Entry point e DI
└── build.sh                         # Script de build
```

## Como Funciona

### 1. Fluxo de Autorização

```
API Gateway (evento)
    ↓
Lambda Authorizer (recebe token)
    ↓
JWT Token Service (decodifica token)
    ↓
Authorization Rules Service (verifica permissões)
    ↓
IAM Policy Builder (constrói policy)
    ↓
API Gateway (Allow/Deny)
```

### 2. Regras de Autorização

Definidas em `AuthorizationRulesService.InitializeRules()`:

- **Catalog API**: GET público, POST/PUT/DELETE apenas admin
- **Users API**: Admin only (GET, POST, PUT, DELETE)
- **Payments API**: Autenticado (GET/POST), admin (PUT/DELETE)
- **Notification API**: Autenticado (GET/POST), admin (DELETE)
- **Health**: Endpoints públicos

### 3. Claims JWT Esperados

O token deve conter:

```json
{
  "sub": "user-id",
  "roles": ["user", "admin"],
  "system_user_id": "guid-do-usuario",
  ...outros claims
}
```

## Build Local

### Pré-requisitos (Windows)

- **.NET SDK** instalado e disponível no `PATH` (comando `dotnet --version` precisa funcionar)
- Para este projeto, o target é **`net8.0`** (Lambda `dotnet8`). Você pode ter só o **SDK 10** instalado e ainda assim compilar para `net8.0` (desde que os runtimes/packs do .NET 8 estejam disponíveis).
- (Opcional) **Git Bash / WSL** se você quiser rodar o `create-api-gateway.sh` diretamente no Windows
- Docker + LocalStack (seu fluxo do repositório)

### Gerar `function.zip` (Windows)

No PowerShell:

```powershell
cd localstack-init\lambda-authorizer
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

Isso gera o pacote e copia para `localstack-init/function.zip` (arquivo usado pelo bootstrap do LocalStack).

## Integração com API Gateway

Quando `create-api-gateway.sh` é executado:

1. Compila e empacota o Lambda
2. Cria função Lambda no LocalStack
3. Cria authorizer **TOKEN** baseado no Lambda
4. Vincula authorizer a todas as rotas com `--authorization-type CUSTOM`

## Desenvolvimento Local

### Validação do token no Firebase (como funciona)

O `JwtTokenService` valida o JWT **contra o JWKS do Firebase** obtido via OpenID Connect:

- **Issuer** esperado: `https://securetoken.google.com/<FIREBASE_PROJECT_ID>`
- **Audience** esperada: `<FIREBASE_PROJECT_ID>`
- **Chaves**: `SigningKeys` retornadas pelo endpoint OpenID (`.well-known/openid-configuration`)

Variáveis de ambiente suportadas:

- `FIREBASE_PROJECT_ID` (**recomendado**): id do projeto Firebase (ex.: `fiapcloudgames-eaced`)
- `JWKS_METADATA_ADDRESS` (opcional): sobrescreve a URL do OpenID configuration
- `ALLOW_DEV_STAGE_BYPASS` (opcional): quando `true`, o script cria rotas com `authorization-type NONE` (sem authorizer)

Em caso de token ausente/inválido, o authorizer retorna **policy IAM com Deny**, e o API Gateway **não chama** a integração do serviço.

## Subir e testar no LocalStack

### 1) Build do pacote

```powershell
cd localstack-init\lambda-authorizer
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

### 2) Subir o bootstrap do API Gateway/Authorizer

O script de bootstrap fica em `localstack-init/create-api-gateway.sh` e precisa ser executado no ambiente que já sobe o LocalStack (normalmente dentro do container de init, ou via Git Bash/WSL).

Exemplo via bash (Git Bash / WSL), a partir da raiz do repositório:

```bash
export FIREBASE_PROJECT_ID="fiapcloudgames-eaced"  # ajuste para o seu projeto
export ALLOW_DEV_STAGE_BYPASS="false"
bash localstack-init/create-api-gateway.sh
```

### 3) Teste rápido de token inválido

Na raiz `localstack-init`, rode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test-invalid-token.ps1
```

Se o token for inválido/ausente, o esperado é receber **403** (Deny) e o backend não é invocado.

### Modificar Regras

Edite `AuthorizationRulesService.InitializeRules()` para adicionar/remover rotas.

Exemplo (permitir leitura pública de catalog):

```csharp
new() { Method = "GET", Path = "/catalog*", AllowAnonymous = true },
```

## Testing

A estrutura suporta testes unitários (adicionar `FiapCloudGames.Lambda.Authorizer.Tests`):

```csharp
public class AuthorizeTokenQueryHandlerTests
{
    [Fact]
    public async Task Should_Allow_Admin_To_Access_Catalog_Post()
    {
        // Arrange
        var handler = new AuthorizeTokenQueryHandler(...);
        var query = new AuthorizeTokenQuery 
        { 
            Token = "token-com-role-admin",
            HttpMethod = "POST",
            ResourcePath = "/catalog"
        };

        // Act
        var result = await handler.Handle(query, CancellationToken.None);

        // Assert
        Assert.True(result.IsAuthorized);
    }
}
```

## Dependências

- `Amazon.Lambda.Core` - SDK do Lambda
- `System.IdentityModel.Tokens.Jwt` - Parse JWT
- `MediatR` - CQRS
- `Microsoft.Extensions.DependencyInjection` - DI

## Próximos Passos

- [ ] Ajustar gateway response (401/403) se quiser mensagens personalizadas
- [ ] Implementar cache de autenticação (Redis)
- [ ] Adicionar testes unitários
- [ ] Centralizar regras em configuração (appsettings.json)
- [ ] Log estruturado com Serilog
