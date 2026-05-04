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
│   ├── JwtTokenService.cs           # Implementação (decode sem validação de assinatura)
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

```bash
cd localstack-init/lambda-authorizer
bash build.sh
```

Gera `build/function.zip` pronto para deploy.

## Integração com API Gateway

Quando `create-api-gateway.sh` é executado:

1. Compila e empacota o Lambda
2. Cria função Lambda no LocalStack
3. Cria authorizer REQUEST baseado no Lambda
4. Vincula authorizer a todas as rotas com `--authorization-type CUSTOM`

## Desenvolvimento Local

### Decodificação de Token

A implementação atual (`JwtTokenService`) **não valida assinatura** (ideal para dev local).

Para validação com JWKS do Firebase em produção, adicione:

```csharp
// Fetch JWKS
var jwksUrl = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";
var handler = new JwtSecurityTokenHandler();
// ... validar contra JWKS
```

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

- [ ] Adicionar validação de assinatura JWT com JWKS
- [ ] Implementar cache de autenticação (Redis)
- [ ] Adicionar testes unitários
- [ ] Centralizar regras em configuração (appsettings.json)
- [ ] Log estruturado com Serilog
