using FiapCloudGames.Lambda.Authorizer.Domain;
using FiapCloudGames.Lambda.Authorizer.Infrastructure;

namespace FiapCloudGames.Lambda.Authorizer.Application.Queries;

public sealed class AuthorizeTokenQueryHandler
(
    IJwtTokenService jwtService
)
{
    public async Task<AuthorizationResult> Handle(AuthorizeTokenQuery request)
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

            var userId = claims.TryGetValue("sub", out object? value) ? value.ToString() : "unknown";
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

    private static string ExtractToken(string authorizationHeader)
    {
        if (string.IsNullOrEmpty(authorizationHeader))
            return string.Empty;

        const string bearer = "Bearer ";
        if (authorizationHeader.StartsWith(bearer, StringComparison.OrdinalIgnoreCase))
            return authorizationHeader[bearer.Length..];

        return authorizationHeader;
    }

    private static List<string> ExtractRoles(Dictionary<string, object> claims)
    {
        if (claims.TryGetValue("roles", out var rolesObj))
            return NormalizeRolesList(rolesObj);

        if (claims.TryGetValue("role", out var roleObj))
            return NormalizeRolesList(roleObj);

        return [];
    }

    private static List<string> NormalizeRolesList(object? rolesObj)
    {
        if (rolesObj == null)
            return [];

        if (rolesObj is System.Collections.IEnumerable enumerable && rolesObj is not string)
        {
            return [.. enumerable.Cast<object>().Select(r => r?.ToString() ?? "").Where(r => !string.IsNullOrEmpty(r))];
        }

        var rolesStr = rolesObj.ToString() ?? "";
        return string.IsNullOrEmpty(rolesStr) ? [] : [rolesStr];
    }
}
