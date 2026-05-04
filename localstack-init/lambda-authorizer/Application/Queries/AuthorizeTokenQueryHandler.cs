using FiapCloudGames.Lambda.Authorizer.Domain;
using FiapCloudGames.Lambda.Authorizer.Infrastructure;

namespace FiapCloudGames.Lambda.Authorizer.Application.Queries;

public sealed class AuthorizeTokenQueryHandler
    (
        IJwtTokenService jwtService,
        IAuthorizationRulesService rulesService
    )
{
    public async Task<AuthorizationResult> Handle(AuthorizeTokenQuery request, CancellationToken cancellationToken)
    {
        try
        {
            if (IsDevStageBypassEnabled() && string.Equals(request.Stage, "dev", StringComparison.OrdinalIgnoreCase))
            {
                return new AuthorizationResult
                {
                    PrincipalId = "dev-bypass",
                    IsAuthorized = true,
                    Context = new Dictionary<string, object>
                    {
                        { "userId", "dev-bypass" },
                        { "roles", "dev" }
                    },
                    Roles = new List<string> { "dev" }
                };
            }

            // Extract token from "Bearer <token>"
            var token = ExtractToken(request.Token);
            
            if (string.IsNullOrEmpty(token))
            {
                return new AuthorizationResult
                {
                    PrincipalId = "user",
                    IsAuthorized = false
                };
            }

            // Decode token (without signature validation in dev mode)
            var claims = jwtService.DecodeToken(token);
            
            if (claims == null)
            {
                return new AuthorizationResult
                {
                    PrincipalId = "user",
                    IsAuthorized = false
                };
            }

            var userId = claims.ContainsKey("sub") ? claims["sub"].ToString() : "unknown";
            var roles = claims.ContainsKey("roles") 
                ? ((System.Collections.IEnumerable)claims["roles"]).Cast<object>().Select(r => r.ToString() ?? "").ToList()
                : new List<string>();

            // Check authorization rules
            var routeKey = $"{request.HttpMethod} {request.ResourcePath}";
            var isAuthorized = rulesService.IsAuthorized(routeKey, roles);

            return new AuthorizationResult
            {
                PrincipalId = userId ?? "user",
                IsAuthorized = isAuthorized,
                Context = new Dictionary<string, object>
                {
                    { "userId", userId ?? "" },
                    { "roles", string.Join(",", roles) }
                },
                Roles = roles
            };
        }
        catch (Exception ex)
        {
            return new AuthorizationResult
            {
                PrincipalId = "user",
                IsAuthorized = false,
                Context = new Dictionary<string, object>
                {
                    { "error", ex.Message }
                }
            };
        }
    }

    private string ExtractToken(string authorizationHeader)
    {
        if (string.IsNullOrEmpty(authorizationHeader))
            return string.Empty;

        const string bearer = "Bearer ";
        if (authorizationHeader.StartsWith(bearer, StringComparison.OrdinalIgnoreCase))
            return authorizationHeader.Substring(bearer.Length);

        return authorizationHeader;
    }

    private static bool IsDevStageBypassEnabled()
    {
        var value = Environment.GetEnvironmentVariable("ALLOW_DEV_STAGE_BYPASS");
        return string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
    }
}
