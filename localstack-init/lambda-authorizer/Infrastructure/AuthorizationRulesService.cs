using FiapCloudGames.Lambda.Authorizer.Domain;

namespace FiapCloudGames.Lambda.Authorizer.Infrastructure;

public interface IAuthorizationRulesService
{
    bool IsAuthorized(string routeKey, List<string> userRoles);
}

public class AuthorizationRulesService : IAuthorizationRulesService
{
    // Static cached rules - initialized once per Lambda container lifetime
    private static readonly Lazy<List<AuthorizationRule>> CachedRules = 
        new(() => InitializeRulesStatic(), LazyThreadSafetyMode.ExecutionAndPublication);

    public bool IsAuthorized(string routeKey, List<string> userRoles)
    {
        var parts = routeKey.Split(' ', 2, StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        var method = parts.Length > 0 ? parts[0].ToUpperInvariant() : "";
        var path = parts.Length > 1 ? parts[1] : "/";

        var rule = CachedRules.Value.FirstOrDefault(r =>
            (r.Method == "ANY" || r.Method.Equals(method, StringComparison.OrdinalIgnoreCase)) &&
            PathMatches(r.Path, path));

        if (rule == null)
        {
            // Default: deny if no rule matches
            return false;
        }

        if (rule.AllowAnonymous)
            return true;

        if (!userRoles.Any())
            return false;

        return rule.AllowedRoles.Any(allowedRole => 
            userRoles.Any(userRole => userRole.Equals(allowedRole, StringComparison.OrdinalIgnoreCase)));
    }

    private static bool PathMatches(string rulePath, string requestPath)
    {
        if (rulePath == "*")
            return true;

        if (rulePath.EndsWith('*'))
        {
            var prefix = rulePath.TrimEnd('*');
            return requestPath.StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
        }

        return string.Equals(rulePath, requestPath, StringComparison.OrdinalIgnoreCase);
    }

    private static List<AuthorizationRule> InitializeRulesStatic()
    {
        return new List<AuthorizationRule>
        {
            // Catalog API - public read, authenticated write
            new() { Method = "GET", Path = "/catalog*", AllowedRoles = new List<string> { "user", "admin" }, AllowAnonymous = true },
            new() { Method = "POST", Path = "/catalog*", AllowedRoles = new List<string> { "admin" } },
            new() { Method = "PUT", Path = "/catalog*", AllowedRoles = new List<string> { "admin" } },
            new() { Method = "DELETE", Path = "/catalog*", AllowedRoles = new List<string> { "admin" } },

            // Users API - admin only
            new() { Method = "GET", Path = "/users*", AllowedRoles = new List<string> { "admin" } },
            new() { Method = "POST", Path = "/users*", AllowedRoles = new List<string> { "admin" } },
            new() { Method = "PUT", Path = "/users*", AllowedRoles = new List<string> { "admin" } },
            new() { Method = "DELETE", Path = "/users*", AllowedRoles = new List<string> { "admin" } },

            // Payments API - authenticated users
            new() { Method = "GET", Path = "/payments*", AllowedRoles = new List<string> { "user", "admin" } },
            new() { Method = "POST", Path = "/payments*", AllowedRoles = new List<string> { "user", "admin" } },
            new() { Method = "PUT", Path = "/payments*", AllowedRoles = new List<string> { "admin" } },
            new() { Method = "DELETE", Path = "/payments*", AllowedRoles = new List<string> { "admin" } },

            // Notification API - authenticated users
            new() { Method = "GET", Path = "/notification*", AllowedRoles = new List<string> { "user", "admin" } },
            new() { Method = "POST", Path = "/notification*", AllowedRoles = new List<string> { "user", "admin" } },
            new() { Method = "DELETE", Path = "/notification*", AllowedRoles = new List<string> { "admin" } },

            // Health/public endpoints
            new() { Method = "GET", Path = "/health", AllowAnonymous = true },
            new() { Method = "GET", Path = "/ready", AllowAnonymous = true },
        };
    }
}
