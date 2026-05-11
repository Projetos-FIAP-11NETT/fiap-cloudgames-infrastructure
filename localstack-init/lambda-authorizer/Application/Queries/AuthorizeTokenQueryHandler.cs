using FiapCloudGames.Lambda.Authorizer.Domain;
using FiapCloudGames.Lambda.Authorizer.Infrastructure;

namespace FiapCloudGames.Lambda.Authorizer.Application.Queries;

public sealed class AuthorizeTokenQueryHandler
(
    IJwtTokenService jwtService
)
{
    public async Task<AuthorizationResult> Handle(AuthorizeTokenQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var token = ExtractToken(request.Token);

            if (string.IsNullOrEmpty(token))
            {
                return new AuthorizationResult
                {
                    PrincipalId = "user",
                    IsAuthorized = false
                };
            }

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
            var roles = ExtractRoles(claims);

            return new AuthorizationResult
            {
                PrincipalId = userId ?? "user",
                IsAuthorized = true,
                Context = new Dictionary<string, object>
                {
                    { "userId", userId ?? "" },
                    { "roles", string.Join(",", roles) }
                },
                Roles = roles
            };
        }
        catch
        {
            return new AuthorizationResult
            {
                PrincipalId = "user",
                IsAuthorized = false
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

    private List<string> ExtractRoles(Dictionary<string, object> claims)
    {
        if (claims.TryGetValue("roles", out var rolesObj))
            return NormalizeRolesList(rolesObj);

        if (claims.TryGetValue("role", out var roleObj))
            return NormalizeRolesList(roleObj);

        return new List<string>();
    }

    private static List<string> NormalizeRolesList(object? rolesObj)
    {
        if (rolesObj == null)
            return new List<string>();

        if (rolesObj is System.Collections.IEnumerable enumerable && !(rolesObj is string))
        {
            return enumerable.Cast<object>().Select(r => r?.ToString() ?? "").Where(r => !string.IsNullOrEmpty(r)).ToList();
        }

        var rolesStr = rolesObj.ToString() ?? "";
        return string.IsNullOrEmpty(rolesStr) ? new List<string>() : new List<string> { rolesStr };
    }
}
